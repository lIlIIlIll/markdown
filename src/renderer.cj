package markdown

import std.collection.*

private let RENDER_SCAN_CANCELLATION_BYTES: Int64 = 1024

/** `TextSink` 或 `AsyncTextSink` 报告的写入失败。 */
public class SinkError <: Exception {
    /**
     * 创建 sink 错误。
     * @param message 人读错误消息。
     */
    public init(message: String) {
        super(message)
    }
    /** 返回异常类名。 */
    protected override func getClassName(): String {
        "SinkError"
    }
}

/** 同步 sink 一次写入的结果。 */
public enum SinkWriteResult {
    /** 写入成功。 */
    | Success
    /** 写入失败，携带错误详情。 */
    | Failure(SinkError)
}

/** 接收 renderer 输出片段的同步 sink。 */
public interface TextSink {
    /** 写入一个输出片段。
     * @param slice 要写入的输出片段。
     */
    func write(slice: String): SinkWriteResult
}

/** 异步 sink 一次写入后的 backpressure 状态。 */
public enum AsyncSinkWriteResult {
    /** 确认接收本次完整片段并继续写出。 */
    | Continue
    /** 确认本次片段的 UTF-8 前缀字节数后暂停；0 表示未接收，全部接收也可暂停。 */
    | Pause(Int64)
    /** 写入失败，携带错误详情。 */
    | Failed(SinkError)
}

/** 接收 bounded chunk、可暂停的异步 sink。 */
public interface AsyncTextSink {
    /** 写入一个输出 chunk 并报告 backpressure 状态。
     * @param slice 要写入的输出片段。
     */
    func write(slice: String): AsyncSinkWriteResult
}

/** 实际 renderer 遍历和输出确认的会话状态。 */
public enum AsyncRenderState {
    /** 全部输出已写出。 */
    | Complete
    /** 因 sink `Pause` 暂停。 */
    | Paused
    /** 因 sink、取消、预算或 renderer 错误终止。 */
    | Failed(MarkdownException)
}

/** 将同步 renderer 输出收集到一个 String 的内建 sink。 */
public class StringTextSink <: TextSink {
    private let builder = StringBuilder()
    private let mappedEntries: ?ArrayList<RenderedSourceMapEntry>
    private var outputOffset: Int64 = 0

    /** 创建不记录 source map 的收集 sink。 */
    public init() {
        mappedEntries = None
    }

    internal init(sourceMapEnabled: Bool) {
        mappedEntries = if (sourceMapEnabled) {
            Some(ArrayList<RenderedSourceMapEntry>())
        } else {
            None
        }
    }

    /** 追加一个 generated 输出片段；内建实现始终返回 `Success`。
     * @param slice 要追加的输出片段。
     */
    public func write(slice: String): SinkWriteResult {
        let noSpan: ?SourceSpan = None
        let noNode: ?NodeId = None
        record(slice, noSpan, noNode, true)
        builder.append(slice)
        SinkWriteResult.Success
    }

    internal func writeFromNode(slice: String, node: NodeRef): SinkWriteResult {
        record(slice, node.span, Some(node.nodeId), false)
        builder.append(slice)
        SinkWriteResult.Success
    }

    /** 返回目前已收集的 HTML 或其他文本。 */
    public func content(): String {
        builder.toString()
    }

    internal func sourceMap(): Array<RenderedSourceMapEntry> {
        match (mappedEntries) {
            case Some(entries) => entries.toArray()
            case None => []
        }
    }

    private func record(slice: String, sourceSpan: ?SourceSpan, nodeId: ?NodeId, generated: Bool): Unit {
        recordSize(slice.size, sourceSpan, nodeId, generated)
    }

    private func recordSize(size: Int64, sourceSpan: ?SourceSpan, nodeId: ?NodeId, generated: Bool): Unit {
        if (size == 0) {
            return
        }
        if (let Some(entries) <- mappedEntries) {
            let end = outputOffset + size
            if (entries.size > 0) {
                let last = entries[entries.size - 1]
                if (last.outputRange.endByte == outputOffset && last.sourceSpan == sourceSpan && last.nodeId == nodeId &&
                    last.generated == generated) {
                    entries.remove(at: entries.size - 1)
                    entries.add(
                        RenderedSourceMapEntry(SourceSpan(last.outputRange.startByte, end), sourceSpan, nodeId,
                            generated))
                    outputOffset = end
                    return
                }
            }
            entries.add(RenderedSourceMapEntry(SourceSpan(outputOffset, end), sourceSpan, nodeId, generated))
            outputOffset = end
        }
    }
}

/** sink 返回失败后 renderer 抛出的异常包装。 */
public class SinkFailureException <: MarkdownException {
    /** 底层的 sink 错误。 */
    public let cause: SinkError

    /**
     * 包装 sink 错误。
     * @param cause 底层的 sink 错误。
     */
    public init(cause: SinkError) {
        super(MarkdownErrorCode.SinkFailure, cause.message, phase: "render")
        this.cause = cause
    }

    /** 返回异常类名。 */
    protected override func getClassName(): String {
        "SinkFailureException"
    }
}

/** raw HTML 节点的处理方式。 */
public enum RawHtmlPolicyKind {
    /** 转义 raw HTML。 */
    | Escape
    /** 丢弃 raw HTML。 */
    | Drop
    /** 原样输出 raw HTML（仅 unsafe 选项可用）。 */
    | PassThrough
    /** 交给 sanitizer 清洗。 */
    | Sanitize
    /** 交给宿主 handler 处理。 */
    | CustomHandler
}

/** link destination 的 scheme 和相对地址策略。 */
public class LinkUriPolicy {
    /** 是否允许相对地址。 */
    public let allowRelative: Bool
    /** 是否允许 `http:` scheme。 */
    public let allowHttp: Bool
    /** 是否允许 `https:` scheme。 */
    public let allowHttps: Bool
    /** 是否允许 `mailto:` scheme。 */
    public let allowMailto: Bool

    /**
     * 创建 link URI policy。
     * @param allowRelative 是否允许相对地址。
     * @param allowHttp 是否允许 `http:` scheme。
     * @param allowHttps 是否允许 `https:` scheme。
     * @param allowMailto 是否允许 `mailto:` scheme。
     */
    public init(allowRelative: Bool, allowHttp: Bool, allowHttps: Bool, allowMailto: Bool) {
        this.allowRelative = allowRelative
        this.allowHttp = allowHttp
        this.allowHttps = allowHttps
        this.allowMailto = allowMailto
    }

    /**
     * 允许 relative、HTTP、HTTPS 和 mailto 的默认 link policy。
     * @return 默认安全 link policy。
     */
    public static func safe(): LinkUriPolicy {
        LinkUriPolicy(true, true, true, true)
    }
}

/** image destination 的 relative、remote 和 data URI 策略。 */
public class ImageUriPolicy {
    /** 是否允许相对地址。 */
    public let allowRelative: Bool
    /** 是否允许远程图片地址。 */
    public let allowRemoteImages: Bool
    /** 是否允许 data URI 图片。 */
    public let allowDataImages: Bool
    /** 允许的 data URI MIME 类型列表。 */
    public let allowedDataMimeTypes: ImmutableArray<String>

    /**
     * 创建 image URI policy。
     * @param allowRelative 是否允许相对地址。
     * @param allowRemoteImages 是否允许远程图片地址。
     * @param allowDataImages 是否允许 data URI 图片。
     * @param allowedDataMimeTypes 允许的 data URI MIME 类型列表。
     */
    public init(
        allowRelative: Bool,
        allowRemoteImages: Bool,
        allowDataImages: Bool,
        allowedDataMimeTypes!: Array<String> = []
    ) {
        this.allowRelative = allowRelative
        this.allowRemoteImages = allowRemoteImages
        this.allowDataImages = allowDataImages
        this.allowedDataMimeTypes = ImmutableArray<String>(allowedDataMimeTypes)
    }

    /**
     * 默认允许 relative image，关闭 remote 和 data image。
     * @return 默认安全 image policy。
     */
    public static func safe(): ImageUriPolicy {
        ImageUriPolicy(true, false, false)
    }
}

/** 在 URI policy 和 escaping 前重写已解析的 HTTP(S) destination。 */
public interface ExternalLinkRewriterPort {
    /** 稳定语义身份；会进入 renderer fingerprint。 */
    prop identity: String
    /** 重写已解析的外部链接 destination。
     * @param uri 原始 destination 文本。
     */
    func rewriteExternalLink(uri: String): String
}

/**
 * HTML renderer 的 raw HTML、URI 和外链属性策略。
 *
 * `safe()` 用于不可信输入；`passThrough`、`specCompatible` 和 `gfmCompatible`
 * 是 unsafe factory，因为它们允许 raw HTML 原样输出。
 */
public class HtmlOptions {
    /** raw HTML 使用的 HTML policy。 */
    public let policy: HtmlPolicy
    /** raw HTML 的处理方式。 */
    public let rawHtmlPolicy: RawHtmlPolicyKind
    /** link destination policy。 */
    public let linkUriPolicy: LinkUriPolicy
    /** image destination policy。 */
    public let imageUriPolicy: ImageUriPolicy
    /** 外链重写端口；未配置为 `None`。 */
    public let rewriteExternalLinks: ?ExternalLinkRewriterPort
    /** 附加到外部链接的 `rel` 属性。 */
    public let externalLinkRel: String
    /** 附加到外部链接的 `target` 属性。 */
    public let externalLinkTarget: String

    /**
     * 创建选项；raw HTML pass-through 必须使用 unsafe factory。
     * @param policy raw HTML 使用的 HTML policy。
     * @param rawHtmlPolicy raw HTML 的处理方式。
     * @param linkUriPolicy link destination policy。
     * @param imageUriPolicy image destination policy。
     * @param rewriteExternalLinks 外链重写端口。
     * @param externalLinkRel 附加到外部链接的 `rel` 属性。
     * @param externalLinkTarget 附加到外部链接的 `target` 属性。
     */
    public init(
        policy: HtmlPolicy,
        rawHtmlPolicy: RawHtmlPolicyKind,
        linkUriPolicy: LinkUriPolicy,
        imageUriPolicy: ImageUriPolicy,
        rewriteExternalLinks!: ?ExternalLinkRewriterPort = None,
        externalLinkRel!: String = "",
        externalLinkTarget!: String = ""
    ) {
        if (let RawHtmlPolicyKind.PassThrough <- rawHtmlPolicy) {
            throw IllegalArgumentException(
                "raw HTML pass-through requires HtmlOptions.passThrough(), specCompatible(), or gfmCompatible() in an unsafe context")
        }
        this.policy = policy
        this.rawHtmlPolicy = rawHtmlPolicy
        this.linkUriPolicy = linkUriPolicy
        this.imageUriPolicy = imageUriPolicy
        this.rewriteExternalLinks = rewriteExternalLinks
        this.externalLinkRel = externalLinkRel
        this.externalLinkTarget = externalLinkTarget
    }

    private init(
        policy: HtmlPolicy,
        rawHtmlPolicy: RawHtmlPolicyKind,
        linkUriPolicy: LinkUriPolicy,
        imageUriPolicy: ImageUriPolicy,
        rewriteExternalLinks: ?ExternalLinkRewriterPort,
        externalLinkRel: String,
        externalLinkTarget: String,
        allowRawHtmlPassThrough: Bool
    ) {
        if (!allowRawHtmlPassThrough) {
            throw IllegalArgumentException("raw HTML pass-through capability was not enabled")
        }
        this.policy = policy
        this.rawHtmlPolicy = rawHtmlPolicy
        this.linkUriPolicy = linkUriPolicy
        this.imageUriPolicy = imageUriPolicy
        this.rewriteExternalLinks = rewriteExternalLinks
        this.externalLinkRel = externalLinkRel
        this.externalLinkTarget = externalLinkTarget
    }

    /** 返回转义 raw HTML、关闭 remote/data image 的安全选项。 */
    public static func safe(): HtmlOptions {
        HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(), ImageUriPolicy.safe())
    }

    /**
     * 在显式 unsafe context 中创建 raw HTML pass-through 选项。
     * @param policy raw HTML 使用的 HTML policy。
     * @param linkUriPolicy link destination policy。
     * @param imageUriPolicy image destination policy。
     * @return raw HTML pass-through options。
     * @param rewriteExternalLinks 外链重写端口。
     * @param externalLinkRel 附加到外部链接的 `rel` 属性。
     * @param externalLinkTarget 附加到外部链接的 `target` 属性。
     */
    public static unsafe func passThrough(
        policy: HtmlPolicy,
        linkUriPolicy: LinkUriPolicy,
        imageUriPolicy: ImageUriPolicy,
        rewriteExternalLinks!: ?ExternalLinkRewriterPort = None,
        externalLinkRel!: String = "",
        externalLinkTarget!: String = ""
    ): HtmlOptions {
        HtmlOptions(policy, RawHtmlPolicyKind.PassThrough, linkUriPolicy, imageUriPolicy, rewriteExternalLinks,
            externalLinkRel, externalLinkTarget, true)
    }

    /** 返回 CommonMark 规范兼容的 unsafe raw HTML 选项。 */
    public static unsafe func specCompatible(): HtmlOptions {
        HtmlOptions.passThrough(HtmlPolicy.specCompatible(), LinkUriPolicy(true, true, true, true),
            ImageUriPolicy(true, true, true))
    }

    /** 返回 GFM 兼容的 unsafe raw HTML 选项和 tagfilter 行为。 */
    public static unsafe func gfmCompatible(): HtmlOptions {
        HtmlOptions.passThrough(HtmlPolicy.gfmCompatible(), LinkUriPolicy(true, true, true, true),
            ImageUriPolicy(true, true, true))
    }
}

/**
 * 宿主已经验证过的 HTML 标记。
 *
 * 只能由 `unsafe { TrustedHtml.fromString(...) }` 创建；它仍受 renderer 的
 * output budget、取消和 sink error 约束。
 */
public class TrustedHtml {
    /** 宿主信任的 HTML 文本。 */
    public let value: String

    private init(value: String) {
        this.value = value
    }

    /** 将宿主确认可信的 HTML 包装为 renderer fallback 的返回值。
     * @param value 宿主确认可信的 HTML 文本。
     */
    public static unsafe func fromString(value: String): TrustedHtml {
        TrustedHtml(value)
    }
}

/** 为没有 `RendererRule` 的 custom node 提供显式 HTML fallback。 */
public interface ExtensionRendererFallback {
    /** fallback 所属的扩展 id。 */
    prop extensionId: String
    /** fallback 的实现版本。 */
    prop implementationVersion: String
    /** 为 custom node 渲染宿主信任的 HTML。
     * @param node 目标 custom 节点。
     */
    func renderHtml(node: NodeRef): TrustedHtml
}

/** 显式处理 raw HTML，并返回宿主信任的 HTML。 */
public interface RawHtmlHandlerPort {
    /** 稳定语义身份；会进入 renderer fingerprint。 */
    prop identity: String
    /** 显式处理 raw HTML 并返回宿主信任的 HTML。
     * @param literal 原始 HTML 文本。
     * @param block 是否为 block 级 HTML。
     */
    func renderRawHtml(literal: String, block: Bool): TrustedHtml
}

internal struct ArenaRenderFrame {
    let node: NodeRef
    let exiting: Bool
    let tableHeader: Bool
    let suppressParagraph: Bool
    let newlineAfter: Bool

    init(node: NodeRef, exiting: Bool, tableHeader!: Bool = false, suppressParagraph!: Bool = false,
        newlineAfter!: Bool = false) {
        this.node = node
        this.exiting = exiting
        this.tableHeader = tableHeader
        this.suppressParagraph = suppressParagraph
        this.newlineAfter = newlineAfter
    }
}

/**
 * 将不可变 arena AST 渲染为 HTML。
 *
 * 默认使用 `HtmlOptions.safe()`。`render` 返回 String，`renderTo` 写入受控 sink；
 * 每个节点、escape、URI 和输出片段都受 cancellation、`OperationBudget` 与可选
 * `maximumOutputBytes` 约束。
 */
public class HtmlRenderer {
    /** renderer 使用的选项。 */
    public let options: HtmlOptions
    private let extensionRules: ImmutableArray<RendererRule>
    private let sanitizer: ?HtmlSanitizerPort
    private let rawHtmlHandler: ?RawHtmlHandlerPort
    private let extensionManifests: ImmutableArray<ExtensionManifest>
    private let extensionFallbacks: ImmutableArray<ExtensionRendererFallback>
    private let maximumOutputBytes: ?Int64

    /**
     * 创建 HTML renderer。
     * @param options HTML 输出选项。
     * @param extensionRules 参与渲染的扩展 renderer 规则。
     * @param sanitizer 宿主提供的 HTML sanitizer。
     * @param extensionManifests 扩展 manifest 列表。
     * @param extensionFallbacks custom node 的显式 HTML fallback。
     * @param rawHtmlHandler 宿主提供的 raw HTML handler。
     * @param maximumOutputBytes 输出字节数上限。
     */
    public init(options!: HtmlOptions = HtmlOptions.safe(), extensionRules!: Array<RendererRule> = [],
        sanitizer!: ?HtmlSanitizerPort = None, extensionManifests!: Array<ExtensionManifest> = [],
        extensionFallbacks!: Array<ExtensionRendererFallback> = [], rawHtmlHandler!: ?RawHtmlHandlerPort = None,
        maximumOutputBytes!: ?Int64 = None) {
        for (rule in extensionRules) {
            validateRendererRuleForRuntime(rule)
        }
        if (let Some(port) <- sanitizer) {
            if (port.identity.isEmpty()) {
                throw IllegalArgumentException("sanitizer identity must not be empty")
            }
        }
        if (let Some(port) <- rawHtmlHandler) {
            if (port.identity.isEmpty()) {
                throw IllegalArgumentException("raw HTML handler identity must not be empty")
            }
        }
        if (let Some(port) <- options.rewriteExternalLinks) {
            if (port.identity.isEmpty()) {
                throw IllegalArgumentException("external link rewriter identity must not be empty")
            }
        }
        let manifestIds = HashSet<String>()
        for (manifest in extensionManifests) {
            if (!manifestIds.add(manifest.extensionId)) {
                throw IllegalArgumentException("duplicate extension id: ${manifest.extensionId}")
            }
        }
        this.options = options
        this.extensionRules = ImmutableArray<RendererRule>(extensionRules)
        this.sanitizer = sanitizer
        this.rawHtmlHandler = rawHtmlHandler
        this.extensionManifests = ImmutableArray<ExtensionManifest>(extensionManifests)
        this.extensionFallbacks = ImmutableArray<ExtensionRendererFallback>(extensionFallbacks)
        if (let Some(value) <- maximumOutputBytes) {
            if (value <= 0) {
                throw IllegalArgumentException("maximum output bytes must be positive")
            }
        }
        this.maximumOutputBytes = maximumOutputBytes
    }

    /** 返回包含策略、扩展和 adapter identity 的稳定 renderer fingerprint。 */
    public func fingerprint(): String {
        let out = CanonicalDescriptor()
        out.append("html-renderer-v3|")
        match (options.policy.kind) {
            case HtmlPolicyKind.SpecCompatible => out.append("spec")
            case HtmlPolicyKind.GfmCompatible => out.append("gfm")
            case HtmlPolicyKind.Safe => out.append("safe")
        }
        out.append("|raw=")
        match (options.rawHtmlPolicy) {
            case RawHtmlPolicyKind.Escape => out.append("escape")
            case RawHtmlPolicyKind.Drop => out.append("drop")
            case RawHtmlPolicyKind.PassThrough => out.append("pass")
            case RawHtmlPolicyKind.Sanitize => out.append("sanitize")
            case RawHtmlPolicyKind.CustomHandler => out.append("custom")
        }
        out.append("|link=");
        out.append(options.linkUriPolicy.allowRelative);
        out.append(":")
        out.append(options.linkUriPolicy.allowHttp);
        out.append(":");
        out.append(options.linkUriPolicy.allowHttps)
        out.append(":");
        out.append(options.linkUriPolicy.allowMailto)
        out.append("|image=");
        out.append(options.imageUriPolicy.allowRelative);
        out.append(":")
        out.append(options.imageUriPolicy.allowRemoteImages);
        out.append(":")
        out.append(options.imageUriPolicy.allowDataImages)
        out.append("|data-mime=")
        if (options.imageUriPolicy.allowDataImages) {
            let normalizedMimeTypes = rendererNormalizedMimeTypes(options.imageUriPolicy.allowedDataMimeTypes)
            for (mime in normalizedMimeTypes) {
                out.append(mime)
            }
        } else {
            out.append("inactive")
        }
        out.append("|rewrite=")
        match (options.rewriteExternalLinks) {
            case Some(port) => out.append(port.identity)
            case None => out.append("none")
        }
        out.append("|rel=");
        out.append(options.externalLinkRel);
        out.append("|target=")
        out.append(options.externalLinkTarget)
        out.append("|sanitizer=")
        if (let RawHtmlPolicyKind.Sanitize <- options.rawHtmlPolicy) {
            match (sanitizer) {
                case Some(port) => out.append(port.identity)
                case None => out.append("none")
            }
        } else {
            out.append("inactive")
        }
        out.append("|raw-handler=")
        if (let RawHtmlPolicyKind.CustomHandler <- options.rawHtmlPolicy) {
            match (rawHtmlHandler) {
                case Some(port) => out.append(port.identity)
                case None => out.append("none")
            }
        } else {
            out.append("inactive")
        }
        out.append("|max-output=")
        match (maximumOutputBytes) {
            case Some(value) => out.append(value)
            case None => out.append("none")
        }
        for (manifest in rendererCanonicalManifests(extensionManifests)) {
            out.append("|manifest=")
            out.append(manifest.extensionId)
            out.append(manifest.semanticVersion)
            out.append(manifest.implementationVersion)
            out.append(rendererMissingPolicyName(manifest.missingRendererPolicy))
        }
        for (fallback in extensionFallbacks.toArray()) {
            out.append("|fallback=")
            out.append(fallback.extensionId)
            out.append(fallback.implementationVersion)
        }
        for (index in 0..extensionRules.size) {
            let rule = extensionRules[index]
            out.append("|ext=");
            out.append(rule.extensionId);
            out.append("/");
            out.append(rule.localKindId)
            out.append(":");
            out.append(rule.htmlTag);
            out.append(":");
            out.append(rule.classToken)
            out.append(":");
            out.append(rule.markdownOpener);
            out.append(":");
            out.append(rule.markdownCloser)
            out.append(":");
            out.append(rule.textPrefix);
            out.append(":");
            out.append(rule.textSuffix)
            out.append(":payload-literal=");
            out.append(rule.renderPayloadLiteral)
            out.append(":block-lowering=")
            match (rule.markdownBlockLowering) {
                case MarkdownBlockLowering.Container => out.append("container")
                case MarkdownBlockLowering.Line => out.append("line")
            }
            for (attribute in rule.attributes.toArray()) {
                out.append(":attr=");
                out.append(attribute.name);
                out.append(":")
                match (attribute.kind) {
                    case RendererAttributeKind.Text => out.append("text")
                    case RendererAttributeKind.LinkUri => out.append("link-uri")
                    case RendererAttributeKind.ImageUri => out.append("image-uri")
                }
                out.append(":")
                match (attribute.source) {
                    case RendererAttributeSource.FixedValue(value) =>
                        out.append("fixed:");
                        out.append(value)
                    case RendererAttributeSource.PayloadParameter(name) =>
                        out.append("parameter:");
                        out.append(name)
                    case RendererAttributeSource.PayloadLiteral => out.append("literal")
                }
            }
        }
        Sha256.digest(out.toString())
    }

    /**
     * 直接渲染 canonical arena AST，并返回完整 HTML String。
     * @param ast 要渲染的 Document。
     * @param cancellation 可选取消 token。
     * @param budget 可选 operation budget。
     * @return HTML 文本。
     * @throws MarkdownException 取消或超出预算/输出上限时。
     */
    public func render(
        ast: Document,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): String {
        cancellation.throwIfCancelled(phase: "render")
        let sink = StringTextSink()
        renderArenaTo(ast, sink, cancellation, budget)
        let content = sink.content()
        cancellation.throwIfCancelled(phase: "render")
        content
    }

    /**
     * 将 HTML 输出写入 sink；sink 失败会转换为 `SinkFailureException`。
     * @param ast 要渲染的 Document。
     * @param sink 接收输出片段的 sink。
     * @param cancellation 可选取消 token。
     * @param budget 可选 operation budget。
     * @throws SinkFailureException sink 返回失败时。
     * @throws MarkdownException 取消或超出预算时。
     */
    public func renderTo(
        ast: Document,
        sink: TextSink,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): Unit {
        cancellation.throwIfCancelled(phase: "render")
        renderArenaTo(ast, sink, cancellation, budget)
        cancellation.throwIfCancelled(phase: "render")
    }

    internal func expandCursorNode(frame: ArenaRenderFrame, frames: ArrayList<ArenaRenderFrame>, sink: HtmlPlanSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        cancellation.throwIfCancelled(phase: "render")
        if (frame.exiting) {
            writeArenaExit(frame, sink, cancellation, budget)
        } else {
            budget.consumeRenderedNode()
            writeArenaEnter(frame, frames, sink, cancellation, budget)
        }
        // Planning helpers keep only exits here; child iteration is lazy.
        while (!frames.isEmpty()) {
            sink.emit(HtmlCursorAction.Node(frames.remove(at: frames.size - 1)))
        }
    }

    internal func expandCursorTableRow(row: NodeRef, header: Bool, sink: HtmlPlanSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        if (row.asTableRow().isNone()) {
            throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "table contains non-row",
                phase: "render", span: row.span)
        }
        budget.consumeRenderedNode()
        write("<tr>\n", sink, cancellation, budget)
        sink.emit(HtmlCursorAction.TableCells(row, 0, header))
        write("</tr>\n", sink, cancellation, budget)
    }

    internal func encodeCursorEmission(emission: HtmlCursorEmission, start: Int64, end: Int64,
        cancellation: CancellationToken, budget: OperationBudget): String {
        let sink = StringTextSink()
        match (emission.kind) {
            case 0 => writeRange(emission.value, start, end, sink, cancellation, budget)
            case 1 => writeEscapedTextFromNode(emission.value[start..end], emission.node.getOrThrow(), sink,
                cancellation, budget)
            case 2 => writeEscapedAttribute(emission.value[start..end], sink, cancellation, budget)
            case 3 => writeEncodedUriAttribute(emission.value[start..end], sink, cancellation, budget)
            case 4 => writeGfmTagFilteredRange(emission.value, start, end, emission.node.getOrThrow(), sink,
                cancellation, budget)
            case _ => throw IllegalStateException("unknown cursor encoding")
        }
        sink.content()
    }

    internal func cursorFootnoteOpen(note: FootnoteDefinitionBinding, sink: HtmlPlanSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        write("<li id=\"", sink, cancellation, budget)
        writeEscapedAttribute(note.definitionId, sink, cancellation, budget)
        write("\">\n", sink, cancellation, budget)
    }

    internal func cursorFootnoteBacklink(note: FootnoteDefinitionBinding, index: Int64, node: NodeRef,
        sink: HtmlPlanSink, cancellation: CancellationToken, budget: OperationBudget): Unit {
        if (index > 0) {
            write(" ", sink, cancellation, budget)
        }
        write("<a href=\"#", sink, cancellation, budget)
        writeEncodedUriAttribute(note.references[index].referenceId, sink, cancellation, budget)
        write("\" aria-label=\"Back to reference ${index + 1} for footnote ${note.number}\">", sink, cancellation,
            budget)
        writeFromNode("↩", node, sink, cancellation, budget)
        write("</a>", sink, cancellation, budget)
    }

    private func renderArenaTo(ast: Document, sink: TextSink, cancellation: CancellationToken, budget: OperationBudget): Unit {
        renderArenaSubtree(ast.root(), sink, cancellation, budget)
        renderFootnoteSection(ast, sink, cancellation, budget)
    }

    private func renderArenaSubtree(root: NodeRef, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        cancellation.throwIfCancelled(phase: "render")
        let stack = ArrayList<ArenaRenderFrame>()
        stack.add(ArenaRenderFrame(root, false))
        var checkpoints: Int64 = 0
        while (!stack.isEmpty()) {
            let frame = stack.remove(at: stack.size - 1)
            checkpoints++
            if (checkpoints >= 256) {
                cancellation.throwIfCancelled(phase: "render")
                checkpoints = 0
            }
            if (frame.exiting) {
                writeArenaExit(frame, sink, cancellation, budget)
            } else {
                budget.consumeRenderedNode()
                writeArenaEnter(frame, stack, sink, cancellation, budget)
            }
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func renderFootnoteSection(document: Document, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        let notes = document.bindings.footnotes
        if (notes.isEmpty()) {
            return
        }
        write("<section class=\"footnotes\" aria-label=\"Footnotes\">\n<ol>\n", sink, cancellation, budget)
        for (note in notes.toArray()) {
            let node = document.nodeRefAtPhysical(note.definitionIndex)
            write("<li id=\"", sink, cancellation, budget)
            writeEscapedAttribute(note.definitionId, sink, cancellation, budget)
            write("\">\n", sink, cancellation, budget)
            let children = node.children()
            for (index in 0..children.size) {
                renderArenaSubtree(children[index], sink, cancellation, budget)
            }
            write("<p class=\"footnote-backlinks\">", sink, cancellation, budget)
            for (index in 0..note.references.size) {
                let reference = note.references[index]
                if (index > 0) {
                    write(" ", sink, cancellation, budget)
                }
                write("<a href=\"#", sink, cancellation, budget)
                writeEncodedUriAttribute(reference.referenceId, sink, cancellation, budget)
                write("\" aria-label=\"Back to reference ${index + 1} for footnote ${note.number}\">", sink,
                    cancellation, budget)
                writeFromNode("↩", node, sink, cancellation, budget)
                write("</a>", sink, cancellation, budget)
            }
            write("</p>\n</li>\n", sink, cancellation, budget)
        }
        write("</ol>\n</section>\n", sink, cancellation, budget)
    }

    private func writeArenaEnter(frame: ArenaRenderFrame, stack: ArrayList<ArenaRenderFrame>, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        let node = frame.node
        match (node.kind) {
            case NodeKind.DocumentNode => pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.Heading =>
                let level = node.asHeading().getOrThrow().level
                write("<h${level}", sink, cancellation, budget)
                if (let Some(binding) <- node.documentBindings.headingForNode(node.nodeId)) {
                    write(" id=\"", sink, cancellation, budget)
                    writeEscapedAttribute(binding.id, sink, cancellation, budget)
                    write("\"", sink, cancellation, budget)
                }
                write(">", sink, cancellation, budget)
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.Paragraph =>
                if (!frame.suppressParagraph) {
                    write("<p>", sink, cancellation, budget)
                }
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.BlockQuote =>
                write("<blockquote>\n", sink, cancellation, budget)
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.List =>
                let list = node.asList().getOrThrow()
                match (list.listKind) {
                    case ListKind.Bullet => write("<ul>\n", sink, cancellation, budget)
                    case ListKind.Ordered =>
                        if (list.start == 1) {
                            write("<ol>\n", sink, cancellation, budget)
                        } else {
                            write("<ol start=\"${list.start}\">\n", sink, cancellation, budget)
                        }
                }
                stack.add(ArenaRenderFrame(node, true))
                pushArenaChildren(node, stack, suppressParagraph: list.tight, planner: htmlOutputPlanner(sink))
            case NodeKind.ListItem =>
                let item = node.asListItem().getOrThrow()
                match (item.taskState) {
                    case TaskState.Checked => write(
                        "<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\" checked=\"\"> ", sink,
                        cancellation, budget)
                    case TaskState.Unchecked => write(
                        "<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\"> ", sink, cancellation,
                        budget)
                    case TaskState.NotTask => write("<li>", sink, cancellation, budget)
                }
                let children = node.children()
                let startsWithBlock = if (children.size > 0) {
                    !isArenaParagraphNode(children[0])
                } else {
                    false
                }
                if (children.size > 0 && (!frame.suppressParagraph || startsWithBlock)) {
                    write("\n", sink, cancellation, budget)
                }
                stack.add(ArenaRenderFrame(node, true, suppressParagraph: frame.suppressParagraph))
                if (let Some(plan) <- htmlOutputPlanner(sink)) {
                    plan.children(node, suppressParagraph: frame.suppressParagraph, listItem: true)
                    return
                }
                var childIndex = children.size - 1
                while (childIndex >= 0) {
                    let childSuppress = if (frame.suppressParagraph) {
                        isArenaParagraphNode(children[childIndex])
                    } else {
                        false
                    }
                    stack.add(
                        ArenaRenderFrame(children[childIndex], false, suppressParagraph: childSuppress,
                            newlineAfter: childSuppress && childIndex + 1 < children.size))
                    childIndex--
                }
            case NodeKind.ThematicBreak => write("<hr />\n", sink, cancellation, budget)
            case NodeKind.CodeBlock =>
                let code = node.asCodeBlock().getOrThrow()
                write("<pre><code", sink, cancellation, budget)
                if (!code.language.isEmpty()) {
                    write(" class=\"language-", sink, cancellation, budget)
                    writeEscapedAttribute(code.language, sink, cancellation, budget)
                    write("\"", sink, cancellation, budget)
                }
                write(">", sink, cancellation, budget)
                writeEscapedTextFromNode(code.literal, node, sink, cancellation, budget)
                if (!code.literal.isEmpty() && !code.literal.endsWith("\n")) {
                    writeFromNode("\n", node, sink, cancellation, budget)
                }
                write("</code></pre>\n", sink, cancellation, budget)
            case NodeKind.HtmlBlock => writeArenaRawHtml(node.asHtmlBlock().getOrThrow().literal, true, node, sink,
                cancellation, budget)
            case NodeKind.Table => renderArenaTable(node, sink, cancellation, budget)
            case NodeKind.TableRow =>
                let row = node.asTableRow().getOrThrow()
                write("<tr>\n", sink, cancellation, budget)
                stack.add(ArenaRenderFrame(node, true, tableHeader: row.header))
                pushArenaChildren(node, stack, tableHeader: row.header, planner: htmlOutputPlanner(sink))
            case NodeKind.TableCell =>
                let tag = if (frame.tableHeader) {
                    "th"
                } else {
                    "td"
                }
                let alignment = alignmentAttribute(node.asTableCell().getOrThrow().alignment)
                write("<${tag}${alignment}>", sink, cancellation, budget)
                stack.add(ArenaRenderFrame(node, true, tableHeader: frame.tableHeader))
                pushArenaChildren(node, stack, tableHeader: frame.tableHeader, planner: htmlOutputPlanner(sink))
            case NodeKind.Text => writeEscapedTextFromNode(node.asText().getOrThrow().value, node, sink, cancellation,
                budget)
            case NodeKind.SoftBreak => write("\n", sink, cancellation, budget)
            case NodeKind.HardBreak => write("<br />\n", sink, cancellation, budget)
            case NodeKind.CodeSpan =>
                write("<code>", sink, cancellation, budget)
                writeEscapedTextFromNode(node.asCodeSpan().getOrThrow().literal, node, sink, cancellation, budget)
                write("</code>", sink, cancellation, budget)
            case NodeKind.Emphasis =>
                write("<em>", sink, cancellation, budget)
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.Strong =>
                write("<strong>", sink, cancellation, budget)
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.Strikethrough =>
                write("<del>", sink, cancellation, budget)
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.Link =>
                let link = node.asLink().getOrThrow()
                let boundDestination = match (node.documentBindings.linkForNode(node.nodeId)) {
                    case Some(value) => value.renderedDestination
                    case None => link.destination
                }
                let externalRewriteApplied = isExternalLinkRewriteApplied(boundDestination, cancellation)
                let destination = rewriteExternalLink(boundDestination, externalRewriteApplied)
                write("<a", sink, cancellation, budget)
                if (isAllowedLink(destination, cancellation, rewrittenExternal: externalRewriteApplied)) {
                    write(" href=\"", sink, cancellation, budget)
                    writeEncodedUriAttribute(destination, sink, cancellation, budget)
                    write("\"", sink, cancellation, budget)
                }
                if (!link.title.isEmpty()) {
                    write(" title=\"", sink, cancellation, budget)
                    writeEscapedAttribute(link.title, sink, cancellation, budget)
                    write("\"", sink, cancellation, budget)
                }
                writeExternalAttributes(destination, sink, cancellation, budget)
                write(">", sink, cancellation, budget)
                pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            case NodeKind.Image =>
                let image = node.asImage().getOrThrow()
                write("<img", sink, cancellation, budget)
                if (isAllowedImage(image.destination, cancellation)) {
                    write(" src=\"", sink, cancellation, budget)
                    writeEncodedUriAttribute(image.destination, sink, cancellation, budget)
                    write("\"", sink, cancellation, budget)
                }
                write(" alt=\"", sink, cancellation, budget)
                writeArenaPlainTextAttribute(node, sink, cancellation, budget)
                write("\"", sink, cancellation, budget)
                if (!image.title.isEmpty()) {
                    write(" title=\"", sink, cancellation, budget)
                    writeEscapedAttribute(image.title, sink, cancellation, budget)
                    write("\"", sink, cancellation, budget)
                }
                write(" />", sink, cancellation, budget)
            case NodeKind.HtmlInline => writeArenaRawHtml(node.asHtmlInline().getOrThrow().literal, false, node, sink,
                cancellation, budget)
            case NodeKind.CustomBlock => renderArenaCustomEnter(node, frame, stack, sink, cancellation, budget)
            case NodeKind.CustomInline => renderArenaCustomEnter(node, frame, stack, sink, cancellation, budget)
        }
    }

    private func writeArenaExit(frame: ArenaRenderFrame, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        match (frame.node.kind) {
            case NodeKind.DocumentNode => ()
            case NodeKind.Heading => write("</h${frame.node.asHeading().getOrThrow().level}>\n", sink, cancellation,
                budget)
            case NodeKind.Paragraph =>
                if (!frame.suppressParagraph) {
                    write("</p>\n", sink, cancellation, budget)
                } else if (frame.newlineAfter) {
                    write("\n", sink, cancellation, budget)
                }
            case NodeKind.BlockQuote => write("</blockquote>\n", sink, cancellation, budget)
            case NodeKind.List => match (frame.node.asList().getOrThrow().listKind) {
                case ListKind.Bullet => write("</ul>\n", sink, cancellation, budget)
                case ListKind.Ordered => write("</ol>\n", sink, cancellation, budget)
            }
            case NodeKind.ListItem => write("</li>\n", sink, cancellation, budget)
            case NodeKind.Table => write("</table>\n", sink, cancellation, budget)
            case NodeKind.TableRow => write("</tr>\n", sink, cancellation, budget)
            case NodeKind.TableCell =>
                let tag = if (frame.tableHeader) {
                    "th"
                } else {
                    "td"
                }
                write("</${tag}>\n", sink, cancellation, budget)
            case NodeKind.Emphasis => write("</em>", sink, cancellation, budget)
            case NodeKind.Strong => write("</strong>", sink, cancellation, budget)
            case NodeKind.Strikethrough => write("</del>", sink, cancellation, budget)
            case NodeKind.Link => write("</a>", sink, cancellation, budget)
            case NodeKind.CustomBlock => renderArenaCustomExit(frame.node, sink, cancellation, budget)
            case NodeKind.CustomInline => renderArenaCustomExit(frame.node, sink, cancellation, budget)
            case _ => ()
        }
    }

    private func pushArenaContainer(frame: ArenaRenderFrame, stack: ArrayList<ArenaRenderFrame>,
        planner!: ?HtmlPlanSink = None): Unit {
        stack.add(
            ArenaRenderFrame(frame.node, true, tableHeader: frame.tableHeader,
                suppressParagraph: frame.suppressParagraph, newlineAfter: frame.newlineAfter))
        pushArenaChildren(frame.node, stack, tableHeader: frame.tableHeader, suppressParagraph: frame.suppressParagraph,
            planner: planner)
    }

    private func pushArenaChildren(node: NodeRef, stack: ArrayList<ArenaRenderFrame>, tableHeader!: Bool = false,
        suppressParagraph!: Bool = false, planner!: ?HtmlPlanSink = None): Unit {
        if (let Some(plan) <- planner) {
            plan.children(node, tableHeader: tableHeader, suppressParagraph: suppressParagraph)
            return
        }
        let children = node.children()
        var index = children.size - 1
        while (index >= 0) {
            stack.add(
                ArenaRenderFrame(children[index], false, tableHeader: tableHeader, suppressParagraph: suppressParagraph))
            index--
        }
    }

    private func renderArenaCustomEnter(node: NodeRef, frame: ArenaRenderFrame, stack: ArrayList<ArenaRenderFrame>,
        sink: TextSink, cancellation: CancellationToken, budget: OperationBudget): Unit {
        let custom = match (node.kind) {
            case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow()
            case NodeKind.CustomInline => node.asCustomInline().getOrThrow()
            case _ => throw IllegalStateException("arena custom renderer received a core node")
        }
        if (custom.payload is FootnoteReferencePayload || custom.payload is FootnoteDefinitionPayload) {
            if (!node.documentBindings.footnotesEnabled) {
                throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                    "footnote rendering requires a bound document", phase: "render", span: node.span)
            }
        }
        if (custom.payload is FootnoteDefinitionPayload || custom.payload is HeadingIdPayload) {
            return
        }
        if (let payload: FootnoteReferencePayload <- custom.payload) {
            match (node.documentBindings.footnoteReference(node.nodeId)) {
                case Some(binding) =>
                    write("<sup class=\"footnote-ref\" id=\"", sink, cancellation, budget)
                    writeEscapedAttribute(binding.referenceId, sink, cancellation, budget)
                    write("\"><a href=\"#", sink, cancellation, budget)
                    writeEncodedUriAttribute(binding.definitionId, sink, cancellation, budget)
                    write("\" aria-label=\"Footnote ${binding.number}\">", sink, cancellation, budget)
                    writeFromNode("${binding.number}", node, sink, cancellation, budget)
                    write("</a></sup>", sink, cancellation, budget)
                case None => writeEscapedTextFromNode("[^${payload.labelRaw}]", node, sink, cancellation, budget)
            }
            return
        }
        if (let Some(rule) <- findRendererRule(custom.extensionId, custom.localKindId)) {
            write("<${rule.htmlTag}", sink, cancellation, budget)
            if (!rule.classToken.isEmpty()) {
                write(" class=\"", sink, cancellation, budget)
                writeEscapedAttribute(rule.classToken, sink, cancellation, budget)
                write("\"", sink, cancellation, budget)
            }
            for (attribute in rule.attributes.toArray()) {
                if (let Some(value) <- arenaStructuredAttributeValue(node, attribute.source, cancellation)) {
                    var allowed = true
                    match (attribute.kind) {
                        case RendererAttributeKind.Text => ()
                        case RendererAttributeKind.LinkUri => allowed = isAllowedLink(value, cancellation)
                        case RendererAttributeKind.ImageUri => allowed = isAllowedImage(value, cancellation)
                    }
                    if (allowed) {
                        write(" ${attribute.name}=\"", sink, cancellation, budget)
                        match (attribute.kind) {
                            case RendererAttributeKind.Text => writeEscapedAttribute(value, sink, cancellation, budget)
                            case _ => writeEncodedUriAttribute(value, sink, cancellation, budget)
                        }
                        write("\"", sink, cancellation, budget)
                    }
                }
            }
            write(">", sink, cancellation, budget)
            if (rule.renderPayloadLiteral) {
                writeEscapedTextFromNode(arenaCustomLiteral(node, cancellation), node, sink, cancellation, budget)
            }
            pushArenaContainer(frame, stack, planner: htmlOutputPlanner(sink))
            return
        }
        let policy = match (findExtensionManifest(custom.extensionId)) {
            case Some(manifest) => manifest.missingRendererPolicy
            case None => MissingRendererPolicy.Error
        }
        match (policy) {
            case MissingRendererPolicy.Error => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                "missing renderer for ${custom.extensionId}/${custom.localKindId}", phase: "render", span: node.span)
            case MissingRendererPolicy.RenderChildren => pushArenaChildren(node, stack, planner: htmlOutputPlanner(sink))
            case MissingRendererPolicy.RenderLiteral => writeEscapedTextFromNode(arenaCustomLiteral(node, cancellation),
                node, sink, cancellation, budget)
            case MissingRendererPolicy.Drop => ()
            case MissingRendererPolicy.CustomFallback => match (findExtensionFallback(custom.extensionId)) {
                case Some(fallback) => writeFromNode(fallback.renderHtml(node).value, node, sink, cancellation, budget)
                case None => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                    "custom renderer fallback is not installed for ${custom.extensionId}", phase: "render",
                    span: node.span)
            }
        }
    }

    private func renderArenaCustomExit(node: NodeRef, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        let custom = match (node.kind) {
            case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow()
            case NodeKind.CustomInline => node.asCustomInline().getOrThrow()
            case _ => throw IllegalStateException("arena custom renderer received a core node")
        }
        if (custom.payload is FootnoteReferencePayload || custom.payload is FootnoteDefinitionPayload ||
            custom.payload is HeadingIdPayload) {
            return
        }
        if (let Some(rule) <- findRendererRule(custom.extensionId, custom.localKindId)) {
            write("</${rule.htmlTag}>", sink, cancellation, budget)
        }
    }

    private func arenaCustomLiteral(node: NodeRef, cancellation: CancellationToken): String {
        let payload = match (node.kind) {
            case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow().payload
            case NodeKind.CustomInline => node.asCustomInline().getOrThrow().payload
            case _ => return ""
        }
        match (payload) {
            case syntax: SyntaxPayload => syntax.literal
            case _ => arenaPlainText(node, cancellation)
        }
    }

    private func arenaStructuredAttributeValue(node: NodeRef, source: RendererAttributeSource,
        cancellation: CancellationToken): ?String {
        match (source) {
            case RendererAttributeSource.FixedValue(value) => Some(value)
            case RendererAttributeSource.PayloadLiteral => Some(arenaCustomLiteral(node, cancellation))
            case RendererAttributeSource.PayloadParameter(name) =>
                let payload = match (node.kind) {
                    case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow().payload
                    case NodeKind.CustomInline => node.asCustomInline().getOrThrow().payload
                    case _ => return None
                }
                match (payload) {
                    case value: SyntaxPayload => match (value.parameter(name)) {
                        case Some(parameter) => Some(syntaxParameterText(parameter))
                        case None => None
                    }
                    case _ => None
                }
        }
    }

    private func writeArenaRawHtml(literal: String, block: Bool, node: NodeRef, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        match (options.rawHtmlPolicy) {
            case RawHtmlPolicyKind.Escape =>
                writeEscapedTextFromNode(literal, node, sink, cancellation, budget)
                writeRawHtmlTerminatingNewline(literal, block, node, sink, cancellation, budget)
            case RawHtmlPolicyKind.Drop => ()
            case RawHtmlPolicyKind.PassThrough =>
                match (options.policy.kind) {
                    case HtmlPolicyKind.GfmCompatible => writeGfmTagFilteredFromNode(literal, node, sink, cancellation,
                        budget)
                    case _ => writeFromNode(literal, node, sink, cancellation, budget)
                }
                writeRawHtmlTerminatingNewline(literal, block, node, sink, cancellation, budget)
            case RawHtmlPolicyKind.Sanitize => match (sanitizer) {
                case Some(port) =>
                    let sanitized = port.sanitize(literal)
                    writeFromNode(sanitized, node, sink, cancellation, budget)
                    writeRawHtmlTerminatingNewline(sanitized, block, node, sink, cancellation, budget)
                case None => throw MarkdownException(MarkdownErrorCode.RenderFailure, "sanitizer adapter is required",
                    phase: "render", span: node.span)
            }
            case RawHtmlPolicyKind.CustomHandler => match (rawHtmlHandler) {
                case Some(port) =>
                    let rendered = port.renderRawHtml(literal, block).value
                    writeFromNode(rendered, node, sink, cancellation, budget)
                    writeRawHtmlTerminatingNewline(rendered, block, node, sink, cancellation, budget)
                case None => throw MarkdownException(MarkdownErrorCode.RenderFailure,
                    "custom raw HTML handler is required", phase: "render", span: node.span)
            }
        }
    }

    private func renderArenaTable(table: NodeRef, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.emit(HtmlCursorAction.Table(table, 0, 0));
            return
        }
        let rows = table.children()
        let inlineFrames = ArrayList<ArenaRenderFrame>()
        write("<table>\n", sink, cancellation, budget)
        if (rows.size > 0) {
            write("<thead>\n", sink, cancellation, budget)
            renderArenaTableRow(rows[0], true, inlineFrames, sink, cancellation, budget)
            write("</thead>\n", sink, cancellation, budget)
        }
        if (rows.size > 1) {
            write("<tbody>\n", sink, cancellation, budget)
            for (index in 1..rows.size) {
                renderArenaTableRow(rows[index], false, inlineFrames, sink, cancellation, budget)
            }
            write("</tbody>\n", sink, cancellation, budget)
        }
        write("</table>\n", sink, cancellation, budget)
    }

    private func renderArenaTableRow(row: NodeRef, header: Bool, inlineFrames: ArrayList<ArenaRenderFrame>,
        sink: TextSink, cancellation: CancellationToken, budget: OperationBudget): Unit {
        if (let NodeKind.TableRow <- row.kind) {
            budget.consumeRenderedNode()
            write("<tr>\n", sink, cancellation, budget)
            let cells = row.children()
            for (index in 0..cells.size) {
                let cell = cells[index]
                if (let NodeKind.TableCell <- cell.kind) {
                    budget.consumeRenderedNode()
                    write(tableCellOpenTag(header, cell.asTableCell().getOrThrow().alignment), sink, cancellation,
                        budget)
                    renderArenaInlineSequence(cell.children(), inlineFrames, sink, cancellation, budget)
                    write(if (header) {
                        "</th>\n"
                    } else {
                        "</td>\n"
                    }, sink, cancellation, budget)
                } else {
                    throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "table row contains non-cell",
                        phase: "render", span: cell.span)
                }
            }
            write("</tr>\n", sink, cancellation, budget)
        } else {
            throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "table contains non-row",
                phase: "render", span: row.span)
        }
    }

    private func renderArenaInlineSequence(nodes: NodeChildren, frames: ArrayList<ArenaRenderFrame>, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        cancellation.throwIfCancelled(phase: "render")
        if (nodes.size == 1) {
            let node = nodes[0]
            if (let NodeKind.Text <- node.kind) {
                budget.consumeRenderedNode()
                writeEscapedTextFromNode(node.asText().getOrThrow().value, node, sink, cancellation, budget)
                return
            }
        }
        var index = nodes.size - 1
        while (index >= 0) {
            frames.add(ArenaRenderFrame(nodes[index], false))
            index--
        }
        var checkpoints: Int64 = 0
        while (!frames.isEmpty()) {
            let frame = frames.remove(at: frames.size - 1)
            checkpoints++
            if (checkpoints >= 256) {
                cancellation.throwIfCancelled(phase: "render")
                checkpoints = 0
            }
            if (frame.exiting) {
                writeArenaExit(frame, sink, cancellation, budget)
            } else {
                budget.consumeRenderedNode()
                writeArenaEnter(frame, frames, sink, cancellation, budget)
            }
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func arenaPlainText(root: NodeRef, cancellation: CancellationToken): String {
        cancellation.throwIfCancelled(phase: "render")
        let out = StringBuilder()
        let stack = ArrayList<NodeRef>()
        stack.add(root)
        var checkpoints: Int64 = 0
        while (!stack.isEmpty()) {
            let node = stack.remove(at: stack.size - 1)
            checkpoints++
            if (checkpoints >= 256) {
                cancellation.throwIfCancelled(phase: "render")
                checkpoints = 0
            }
            match (node.kind) {
                case NodeKind.Text => out.append(node.asText().getOrThrow().value)
                case NodeKind.CodeSpan => out.append(node.asCodeSpan().getOrThrow().literal)
                case NodeKind.SoftBreak => out.append("\n")
                case NodeKind.HardBreak => out.append("\n")
                case _ =>
                    let children = node.children()
                    var index = children.size - 1
                    while (index >= 0) {
                        stack.add(children[index])
                        index--
                    }
            }
        }
        cancellation.throwIfCancelled(phase: "render")
        out.toString()
    }

    private func isArenaParagraphNode(node: NodeRef): Bool {
        if (let NodeKind.Paragraph <- node.kind) {
            true
        } else {
            false
        }
    }

    private func write(
        value: String,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(0, value);
            return
        }
        cancellation.throwIfCancelled(phase: "render")
        consumeOutput(value.size, budget)
        let result = match (sink) {
            case stringSink: StringTextSink => stringSink.write(value)
            case _ => sink.write(value)
        }
        match (result) {
            case SinkWriteResult.Success => ()
            case SinkWriteResult.Failure(error) => throw SinkFailureException(error)
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func writeFromNode(
        value: String,
        node: NodeRef,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(0, value);
            return
        }
        cancellation.throwIfCancelled(phase: "render")
        consumeOutput(value.size, budget)
        let result = match (sink) {
            case mapped: StringTextSink => mapped.writeFromNode(value, node)
            case _ => sink.write(value)
        }
        match (result) {
            case SinkWriteResult.Success => ()
            case SinkWriteResult.Failure(error) => throw SinkFailureException(error)
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func writeRangeFromNode(
        value: String,
        start: Int64,
        end: Int64,
        node: NodeRef,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(0, value, start: start, end: end);
            return
        }
        cancellation.throwIfCancelled(phase: "render")
        consumeOutput(end - start, budget)
        let slice = value[start..end]
        let result = match (sink) {
            case mapped: StringTextSink => mapped.writeFromNode(slice, node)
            case _ => sink.write(slice)
        }
        match (result) {
            case SinkWriteResult.Success => ()
            case SinkWriteResult.Failure(error) => throw SinkFailureException(error)
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func writeRange(
        value: String,
        start: Int64,
        end: Int64,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(0, value, start: start, end: end);
            return
        }
        cancellation.throwIfCancelled(phase: "render")
        consumeOutput(end - start, budget)
        let slice = value[start..end]
        let result = match (sink) {
            case stringSink: StringTextSink => stringSink.write(slice)
            case _ => sink.write(slice)
        }
        match (result) {
            case SinkWriteResult.Success => ()
            case SinkWriteResult.Failure(error) => throw SinkFailureException(error)
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func consumeOutput(bytes: Int64, budget: OperationBudget): Unit {
        if (let Some(limit) <- maximumOutputBytes) {
            let observed = budget.usedOutputBytes() + bytes
            if (observed > limit) {
                throw LimitExceededException("output_bytes", limit, observed, "render")
            }
        }
        budget.consumeOutput(bytes: bytes)
    }

    /** Writes escaped text without materializing a node-sized temporary String. */
    private func writeEscapedTextFromNode(value: String, node: NodeRef, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(1, value, node: Some(node));
            return
        }
        var segmentStart: Int64 = 0
        var index: Int64 = 0
        var nextCancellationCheck: Int64 = 0
        while (index < value.size) {
            if (index >= nextCancellationCheck) {
                cancellation.throwIfCancelled(phase: "render")
                nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
            }
            let replacement = match (value[index]) {
                case b'&' => "&amp;"
                case b'<' => "&lt;"
                case b'>' => "&gt;"
                case b'\"' => "&quot;"
                case _ => ""
            }
            if (!replacement.isEmpty()) {
                if (segmentStart < index) {
                    writeRangeFromNode(value, segmentStart, index, node, sink, cancellation, budget)
                }
                writeFromNode(replacement, node, sink, cancellation, budget)
                segmentStart = index + 1
            }
            index++
        }
        cancellation.throwIfCancelled(phase: "render")
        if (segmentStart < value.size) {
            writeRangeFromNode(value, segmentStart, value.size, node, sink, cancellation, budget)
        }
    }

    private func writeEscapedAttribute(value: String, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(2, value);
            return
        }
        var segmentStart: Int64 = 0
        var index: Int64 = 0
        var nextCancellationCheck: Int64 = 0
        while (index < value.size) {
            if (index >= nextCancellationCheck) {
                cancellation.throwIfCancelled(phase: "render")
                nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
            }
            let byte = value[index]
            let replacement = if (byte == b'&') {
                "&amp;"
            } else if (byte == b'<') {
                "&lt;"
            } else if (byte == b'>') {
                "&gt;"
            } else if (byte == b'\"') {
                "&quot;"
            } else if (byte == b'\'') {
                "&#39;"
            } else if (isSafePolicy() && (byte < 32 || byte == 127)) {
                "&#xfffd;"
            } else {
                ""
            }
            if (!replacement.isEmpty()) {
                if (segmentStart < index) {
                    writeRange(value, segmentStart, index, sink, cancellation, budget)
                }
                write(replacement, sink, cancellation, budget)
                index++
                segmentStart = index
            } else {
                index = rendererNextRune(value, index)
            }
        }
        cancellation.throwIfCancelled(phase: "render")
        if (segmentStart < value.size) {
            writeRange(value, segmentStart, value.size, sink, cancellation, budget)
        }
    }

    private func writeEncodedUriAttribute(value: String, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(3, value);
            return
        }
        var segmentStart: Int64 = 0
        var index: Int64 = 0
        var nextCancellationCheck: Int64 = 0
        while (index < value.size) {
            if (index >= nextCancellationCheck) {
                cancellation.throwIfCancelled(phase: "render")
                nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
            }
            let byte = value[index]
            let percentEncode = byte == b' ' || byte == b'`' || byte == b'\"' || byte == b'\\' || byte < 0x20 || byte >=
                0x80 || byte == b'[' || byte == b']'
            let htmlReplacement = if (!percentEncode && byte == b'&') {
                "&amp;"
            } else if (!percentEncode && byte == b'<') {
                "&lt;"
            } else if (!percentEncode && byte == b'>') {
                "&gt;"
            } else if (!percentEncode && byte == b'\'') {
                "&#39;"
            } else {
                ""
            }
            if (percentEncode || !htmlReplacement.isEmpty()) {
                if (segmentStart < index) {
                    writeRange(value, segmentStart, index, sink, cancellation, budget)
                }
                if (percentEncode) {
                    writePercentEncodedByte(byte, sink, cancellation, budget)
                } else {
                    write(htmlReplacement, sink, cancellation, budget)
                }
                index++
                segmentStart = index
            } else {
                index++
            }
        }
        cancellation.throwIfCancelled(phase: "render")
        if (segmentStart < value.size) {
            writeRange(value, segmentStart, value.size, sink, cancellation, budget)
        }
    }

    private func writePercentEncodedByte(byte: Byte, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        let digits = "0123456789ABCDEF"
        let high = Int64((byte >> 4) & 0x0F)
        let low = Int64(byte & 0x0F)
        write("%", sink, cancellation, budget)
        write(digits[high..high + 1], sink, cancellation, budget)
        write(digits[low..low + 1], sink, cancellation, budget)
    }

    private func writeArenaPlainTextAttribute(root: NodeRef, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.emit(HtmlCursorAction.ImageAlt(root));
            return
        }
        cancellation.throwIfCancelled(phase: "render")
        let stack = ArrayList<NodeRef>()
        stack.add(root)
        var checkpoints: Int64 = 0
        while (!stack.isEmpty()) {
            let node = stack.remove(at: stack.size - 1)
            checkpoints++
            if (checkpoints >= 256) {
                cancellation.throwIfCancelled(phase: "render")
                checkpoints = 0
            }
            match (node.kind) {
                case NodeKind.Text => writeEscapedAttribute(node.asText().getOrThrow().value, sink, cancellation, budget)
                case NodeKind.CodeSpan => writeEscapedAttribute(node.asCodeSpan().getOrThrow().literal, sink,
                    cancellation, budget)
                case NodeKind.SoftBreak => writeEscapedAttribute("\n", sink, cancellation, budget)
                case NodeKind.HardBreak => writeEscapedAttribute("\n", sink, cancellation, budget)
                case _ =>
                    let children = node.children()
                    var index = children.size - 1
                    while (index >= 0) {
                        stack.add(children[index])
                        index--
                    }
            }
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func writeRawHtmlTerminatingNewline(value: String, block: Bool, node: NodeRef, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        if (block && !value.endsWith("\n")) {
            writeFromNode("\n", node, sink, cancellation, budget)
        }
    }

    /** Applies the GFM raw-tag filter while checking the output limit before every emitted segment. */
    private func writeGfmTagFilteredFromNode(value: String, node: NodeRef, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        if (let Some(plan) <- htmlOutputPlanner(sink)) {
            plan.output(4, value, node: Some(node));
            return
        }
        writeGfmTagFilteredRange(value, 0, value.size, node, sink, cancellation, budget)
    }

    private func writeGfmTagFilteredRange(value: String, start: Int64, end: Int64, node: NodeRef, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        var segmentStart: Int64 = start
        var index: Int64 = start
        var nextCancellationCheck: Int64 = 0
        while (index < end) {
            if (index >= nextCancellationCheck) {
                cancellation.throwIfCancelled(phase: "render")
                nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
            }
            if (value[index] == b'<') {
                var nameStart = index + 1
                if (nameStart < value.size && value[nameStart] == b'/') {
                    nameStart++
                }
                if (isGfmDisallowedTagAt(value, nameStart)) {
                    if (segmentStart < index) {
                        writeRangeFromNode(value, segmentStart, index, node, sink, cancellation, budget)
                    }
                    writeFromNode("&lt;", node, sink, cancellation, budget)
                    index++
                    segmentStart = index
                    continue
                }
            }
            index = rendererNextRune(value, index)
        }
        cancellation.throwIfCancelled(phase: "render")
        if (segmentStart < end) {
            writeRangeFromNode(value, segmentStart, end, node, sink, cancellation, budget)
        }
    }

    private func rewriteExternalLink(uri: String, rewriteApplied: Bool): String {
        if (!rewriteApplied) {
            return uri
        }
        match (options.rewriteExternalLinks) {
            case Some(port) => port.rewriteExternalLink(uri)
            case None => uri
        }
    }

    private func isExternalLinkRewriteApplied(uri: String, cancellation: CancellationToken): Bool {
        if (options.rewriteExternalLinks.isNone()) {
            return false
        }
        let scheme = uriScheme(uri, cancellation)
        scheme == "http" || scheme == "https"
    }

    private func isAllowedLink(uri: String, cancellation: CancellationToken, rewrittenExternal!: Bool = false): Bool {
        let scheme = uriScheme(uri, cancellation)
        // Spec/GFM compatibility intentionally preserves their legacy URI
        // behavior when no rewriter is installed. Once host code rewrites an
        // external HTTP(S) link, however, the returned value crosses a trust
        // boundary and must remain an absolute HTTP(S) destination.
        if (rewrittenExternal && scheme != "http" && scheme != "https") {
            return false
        }
        match (options.policy.kind) {
            case HtmlPolicyKind.SpecCompatible => return true
            case HtmlPolicyKind.GfmCompatible => return true
            case _ => ()
        }
        if (scheme.isEmpty()) {
            return options.linkUriPolicy.allowRelative
        }
        if (scheme == "http") {
            return options.linkUriPolicy.allowHttp
        }
        if (scheme == "https") {
            return options.linkUriPolicy.allowHttps
        }
        if (scheme == "mailto") {
            return options.linkUriPolicy.allowMailto
        }
        false
    }

    private func isAllowedImage(uri: String, cancellation: CancellationToken): Bool {
        let scheme = uriScheme(uri, cancellation)
        if (scheme.isEmpty()) {
            return options.imageUriPolicy.allowRelative
        }
        if (scheme == "http" || scheme == "https") {
            return options.imageUriPolicy.allowRemoteImages
        }
        if (scheme == "data") {
            if (!options.imageUriPolicy.allowDataImages) {
                return false
            }
            let comma = rendererFindByte(uri, b',', 5, cancellation)
            if (comma < 0) {
                return false
            }
            cancellation.throwIfCancelled(phase: "render")
            let metadata = rendererLowerAsciiCancellable(uri[5..comma], cancellation)
            let semicolon = rendererFindByte(metadata, b';', 0, cancellation)
            let mediaType = if (semicolon < 0) {
                metadata
            } else {
                metadata[0..semicolon]
            }
            for (mime in options.imageUriPolicy.allowedDataMimeTypes.toArray()) {
                cancellation.throwIfCancelled(phase: "render")
                if (rendererAsciiWholeEqualsIgnoreCaseCancellable(mediaType, mime, cancellation)) {
                    return true
                }
            }
        }
        false
    }

    private func writeExternalAttributes(uri: String, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
        let scheme = uriScheme(uri, cancellation)
        if (scheme != "http" && scheme != "https") {
            return
        }
        let rel = options.externalLinkRel
        var addNoopener = false
        var addNoreferrer = false
        if (isSafePolicy() && rendererAsciiWholeEqualsIgnoreCase(options.externalLinkTarget, "_blank")) {
            if (!containsAsciiWhitespaceToken(rel, "noopener", cancellation)) {
                addNoopener = true
            }
            if (!containsAsciiWhitespaceToken(rel, "noreferrer", cancellation)) {
                addNoreferrer = true
            }
        }
        if (!rel.isEmpty() || addNoopener || addNoreferrer) {
            write(" rel=\"", sink, cancellation, budget)
            if (!rel.isEmpty()) {
                writeEscapedAttribute(rel, sink, cancellation, budget)
            }
            if (addNoopener) {
                write(if (rel.isEmpty()) {
                    "noopener"
                } else {
                    " noopener"
                }, sink, cancellation, budget)
            }
            if (addNoreferrer) {
                write(if (rel.isEmpty() && !addNoopener) {
                    "noreferrer"
                } else {
                    " noreferrer"
                }, sink, cancellation, budget)
            }
            write("\"", sink, cancellation, budget)
        }
        if (!options.externalLinkTarget.isEmpty()) {
            write(" target=\"", sink, cancellation, budget)
            writeEscapedAttribute(options.externalLinkTarget, sink, cancellation, budget)
            write("\"", sink, cancellation, budget)
        }
    }

    private func findRendererRule(extensionId: String, localKindId: String): ?RendererRule {
        for (index in 0..extensionRules.size) {
            let rule = extensionRules[index]
            if (rule.extensionId == extensionId && rule.localKindId == localKindId) {
                return Some(rule)
            }
        }
        None
    }

    private func isSafePolicy(): Bool {
        match (options.policy.kind) {
            case HtmlPolicyKind.Safe => true
            case _ => false
        }
    }

    private func findExtensionManifest(extensionId: String): ?ExtensionManifest {
        for (index in 0..extensionManifests.size) {
            if (extensionManifests[index].extensionId == extensionId) {
                return Some(extensionManifests[index])
            }
        }
        None
    }

    private func findExtensionFallback(extensionId: String): ?ExtensionRendererFallback {
        for (index in 0..extensionFallbacks.size) {
            if (extensionFallbacks[index].extensionId == extensionId) {
                return Some(extensionFallbacks[index])
            }
        }
        None
    }
}

private func containsAsciiWhitespaceToken(value: String, expected: String, cancellation: CancellationToken): Bool {
    cancellation.throwIfCancelled(phase: "render")
    var start: Int64 = 0
    var index: Int64 = 0
    var nextCancellationCheck: Int64 = RENDER_SCAN_CANCELLATION_BYTES
    while (index <= value.size) {
        if (index >= nextCancellationCheck) {
            cancellation.throwIfCancelled(phase: "render")
            nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
        }
        let separator = if (index == value.size) {
            true
        } else {
            rendererIsAsciiWhitespace(value[index])
        }
        if (separator) {
            if (index > start && rendererAsciiRangeEqualsIgnoreCase(value, start, index, expected)) {
                return true
            }
            start = index + 1
        }
        index++
    }
    cancellation.throwIfCancelled(phase: "render")
    false
}

private func rendererIsAsciiWhitespace(byte: Byte): Bool {
    byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r' || byte == 12
}

extend MarkdownEngine {
    /**
     * 按 engine 的 dialect rules 创建 renderer，并继承 `maximumOutputBytes`。
     * @param options HTML 和 URI 策略，默认 `HtmlOptions.safe()`。
     * @param sanitizer Sanitize policy 使用的 sanitizer。
     * @param fallbacks custom node 的 fallback 列表。
     * @param rawHtmlHandler CustomHandler 使用的 handler。
     * @return 配置好的 `HtmlRenderer`。
     */
    public func htmlRenderer(options!: HtmlOptions = HtmlOptions.safe(), sanitizer!: ?HtmlSanitizerPort = None,
        fallbacks!: Array<ExtensionRendererFallback> = [], rawHtmlHandler!: ?RawHtmlHandlerPort = None): HtmlRenderer {
        HtmlRenderer(options: options, extensionRules: dialect.rendererRules.toArray(), sanitizer: sanitizer,
            extensionManifests: dialect.manifests.toArray(), extensionFallbacks: fallbacks,
            rawHtmlHandler: rawHtmlHandler, maximumOutputBytes: Some(limits.maximumOutputBytes))
    }
}

/** 宿主提供的 HTML sanitizer 端口。 */
public interface HtmlSanitizerPort {
    /** 稳定语义身份；会进入 renderer fingerprint。 */
    prop identity: String
    // Implementations may throw; HtmlRenderer propagates the failure and never
    // falls back to the unsanitized literal.
    /** 清洗宿主传入的 HTML 片段。
     * @param html 待清洗的 HTML 文本。
     */
    func sanitize(html: String): String
}

/** 纯文本 renderer 的链接和软换行选项。 */
public class PlainTextOptions {
    /** 是否在链接文本后附加 destination。 */
    public let includeLinkDestinations: Bool
    /** 软换行的输出形式。 */
    public let softBreak: String

    /**
     * 创建纯文本选项。
     * @param includeLinkDestinations 是否在链接文本后附加 destination。
     * @param softBreak 软换行的输出形式。
     */
    public init(includeLinkDestinations!: Bool = false, softBreak!: String = "\n") {
        this.includeLinkDestinations = includeLinkDestinations
        this.softBreak = softBreak
    }
}

/** 从 AST 提取纯文本的 renderer。 */
public class PlainTextRenderer {
    /** renderer 使用的选项。 */
    public let options: PlainTextOptions
    private let extensionRules: ImmutableArray<RendererRule>

    /**
     * 创建纯文本 renderer。
     * @param options 纯文本输出选项。
     * @param extensionRules 参与渲染的扩展 renderer 规则。
     */
    public init(options!: PlainTextOptions = PlainTextOptions(), extensionRules!: Array<RendererRule> = []) {
        this.options = options
        this.extensionRules = ImmutableArray<RendererRule>(extensionRules)
    }

    /**
     * 按文档结构输出纯文本，并按 options 处理软换行和链接 destination。
     * @param document 要渲染的 Document。
     * @return 纯文本结果。
     */
    public func render(document: Document): String {
        let out = StringBuilder()
        appendPlainSubtree(document.root(), out)
        for (note in document.bindings.footnotes.toArray()) {
            out.append("\n\n[${note.number}] ")
            let definition = document.nodeRefAtPhysical(note.definitionIndex)
            let children = definition.children()
            for (index in 0..children.size) {
                appendPlainSubtree(children[index], out)
            }
        }
        trimTrailingNewlines(out.toString())
    }

    private func appendPlainSubtree(root: NodeRef, out: StringBuilder): Unit {
        let stack = ArrayList<ArenaRenderFrame>()
        stack.add(ArenaRenderFrame(root, false))
        while (!stack.isEmpty()) {
            let frame = stack.remove(at: stack.size - 1)
            if (frame.exiting) {
                match (frame.node.kind) {
                    case NodeKind.Paragraph => out.append("\n\n")
                    case NodeKind.Heading => out.append("\n\n")
                    case NodeKind.ListItem => out.append("\n")
                    case NodeKind.CodeBlock => out.append("\n\n")
                    case NodeKind.TableCell => out.append("\t")
                    case NodeKind.TableRow => out.append("\n")
                    case NodeKind.Link =>
                        if (options.includeLinkDestinations) {
                            out.append(" (");
                            out.append(match (frame.node.documentBindings.linkForNode(frame.node.nodeId)) {
                                case Some(value) => value.renderedDestination
                                case None => frame.node.asLink().getOrThrow().destination
                            });
                            out.append(")")
                        }
                    case NodeKind.CustomBlock =>
                        let custom = frame.node.asCustomBlock().getOrThrow()
                        appendCustomTextSuffix(custom.extensionId, custom.localKindId, out)
                    case NodeKind.CustomInline =>
                        let custom = frame.node.asCustomInline().getOrThrow()
                        appendCustomTextSuffix(custom.extensionId, custom.localKindId, out)
                    case _ => ()
                }
                continue
            }
            match (frame.node.kind) {
                case NodeKind.Text => out.append(frame.node.asText().getOrThrow().value)
                case NodeKind.SoftBreak => out.append(options.softBreak)
                case NodeKind.HardBreak => out.append("\n")
                case NodeKind.CodeSpan => out.append(frame.node.asCodeSpan().getOrThrow().literal)
                case NodeKind.CodeBlock =>
                    out.append(frame.node.asCodeBlock().getOrThrow().literal)
                    stack.add(ArenaRenderFrame(frame.node, true))
                case NodeKind.HtmlBlock =>
                    out.append(stripHtmlTags(frame.node.asHtmlBlock().getOrThrow().literal))
                    stack.add(ArenaRenderFrame(frame.node, true))
                case NodeKind.HtmlInline => out.append(stripHtmlTags(frame.node.asHtmlInline().getOrThrow().literal))
                case NodeKind.Image => out.append(arenaPlainTextValue(frame.node))
                case NodeKind.ThematicBreak => out.append("\n")
                case NodeKind.CustomBlock =>
                    let custom = frame.node.asCustomBlock().getOrThrow()
                    if (custom.payload is FootnoteDefinitionPayload) {
                        continue
                    }
                    appendCustomTextPrefix(custom.extensionId, custom.localKindId, frame.node, out)
                    pushPlainContainer(frame, stack)
                case NodeKind.CustomInline =>
                    let custom = frame.node.asCustomInline().getOrThrow()
                    if (custom.payload is HeadingIdPayload) {
                        continue
                    }
                    if (let payload: FootnoteReferencePayload <- custom.payload) {
                        match (frame.node.documentBindings.footnoteReference(frame.node.nodeId)) {
                            case Some(value) => out.append("[${value.number}]")
                            case None => out.append("[^${payload.labelRaw}]")
                        }
                        continue
                    }
                    appendCustomTextPrefix(custom.extensionId, custom.localKindId, frame.node, out)
                    pushPlainContainer(frame, stack)
                case _ => pushPlainContainer(frame, stack)
            }
        }
    }

    private func pushPlainContainer(frame: ArenaRenderFrame, stack: ArrayList<ArenaRenderFrame>): Unit {
        stack.add(ArenaRenderFrame(frame.node, true))
        let children = frame.node.children()
        var index = children.size - 1
        while (index >= 0) {
            stack.add(ArenaRenderFrame(children[index], false));
            index--
        }
    }

    private func appendCustomTextPrefix(extensionId: String, localKindId: String, node: NodeRef, out: StringBuilder): Unit {
        for (index in 0..extensionRules.size) {
            let rule = extensionRules[index]
            if (rule.extensionId == extensionId && rule.localKindId == localKindId) {
                out.append(rule.textPrefix);
                if (rule.renderPayloadLiteral) {
                    out.append(arenaCustomLiteralValue(node))
                }
                return
            }
        }
    }

    private func appendCustomTextSuffix(extensionId: String, localKindId: String, out: StringBuilder): Unit {
        for (index in 0..extensionRules.size) {
            let rule = extensionRules[index]
            if (rule.extensionId == extensionId && rule.localKindId == localKindId) {
                out.append(rule.textSuffix);
                return
            }
        }
    }
}

private func arenaPlainTextValue(root: NodeRef): String {
    let out = StringBuilder()
    let stack = ArrayList<NodeRef>()
    stack.add(root)
    while (!stack.isEmpty()) {
        let node = stack.remove(at: stack.size - 1)
        match (node.kind) {
            case NodeKind.Text => out.append(node.asText().getOrThrow().value)
            case NodeKind.CodeSpan => out.append(node.asCodeSpan().getOrThrow().literal)
            case NodeKind.SoftBreak => out.append("\n")
            case NodeKind.HardBreak => out.append("\n")
            case _ =>
                let children = node.children()
                var index = children.size - 1
                while (index >= 0) {
                    stack.add(children[index])
                    index--
                }
        }
    }
    out.toString()
}

private func arenaCustomLiteralValue(node: NodeRef): String {
    let payload = match (node.kind) {
        case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow().payload
        case NodeKind.CustomInline => node.asCustomInline().getOrThrow().payload
        case _ => return ""
    }
    match (payload) {
        case syntax: SyntaxPayload => syntax.literal
        case _ => arenaPlainTextValue(node)
    }
}

private func syntaxParameterText(value: SyntaxParameterValue): String {
    match (value) {
        case SyntaxParameterValue.StringValue(text) => text
        case SyntaxParameterValue.IntegerValue(number) => "${number}"
        case SyntaxParameterValue.BooleanValue(boolean) => "${boolean}"
        case SyntaxParameterValue.IdentifierValue(identifier) => identifier
    }
}

private func tableCellOpenTag(header: Bool, alignment: TableAlignment): String {
    if (header) {
        return match (alignment) {
            case TableAlignment.Left => "<th align=\"left\">"
            case TableAlignment.Center => "<th align=\"center\">"
            case TableAlignment.Right => "<th align=\"right\">"
            case TableAlignment.None => "<th>"
        }
    }
    match (alignment) {
        case TableAlignment.Left => "<td align=\"left\">"
        case TableAlignment.Center => "<td align=\"center\">"
        case TableAlignment.Right => "<td align=\"right\">"
        case TableAlignment.None => "<td>"
    }
}

private func validateRendererRuleForRuntime(rule: RendererRule): Unit {
    if (!rendererHtmlName(rule.htmlTag)) {
        throw IllegalArgumentException("invalid structured renderer tag")
    }
    if (!rule.classToken.isEmpty() && !rendererClassToken(rule.classToken)) {
        throw IllegalArgumentException("invalid structured renderer class token")
    }
    match (rule.markdownBlockLowering) {
        case MarkdownBlockLowering.Container =>
            if (rule.markdownOpener.isEmpty() != rule.markdownCloser.isEmpty()) {
                throw IllegalArgumentException("container Markdown lowering requires both delimiters")
            }
        case MarkdownBlockLowering.Line =>
            if (rule.markdownOpener.isEmpty() || !rule.markdownCloser.isEmpty()) {
                throw IllegalArgumentException("line Markdown lowering requires opener only")
            }
    }
    for (attribute in rule.attributes.toArray()) {
        if (!rendererAttributeName(attribute.name)) {
            throw IllegalArgumentException("invalid structured renderer attribute name")
        }
        let lower = rendererLowerAscii(attribute.name)
        if (lower.startsWith("on") || lower == "style") {
            throw IllegalArgumentException("event/style attributes are forbidden")
        }
        match (attribute.kind) {
            case RendererAttributeKind.Text =>
                if (lower == "href" || lower == "src") {
                    throw IllegalArgumentException("URI attributes require URI policy")
                }
            case RendererAttributeKind.LinkUri =>
                if (lower != "href") {
                    throw IllegalArgumentException("LinkUri must use href")
                }
            case RendererAttributeKind.ImageUri =>
                if (lower != "src") {
                    throw IllegalArgumentException("ImageUri must use src")
                }
        }
    }
}

private func rendererHtmlName(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'0' && byte <= b'9') || byte == b'-')) {
            return false
        }
    }
    true
}

private func rendererClassToken(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'-' || byte == b'_')) {
            return false
        }
    }
    true
}

private func rendererAttributeName(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'-' || byte == b'_')) {
            return false
        }
    }
    true
}

private func uriScheme(uri: String, cancellation: CancellationToken): String {
    cancellation.throwIfCancelled(phase: "render")
    let normalized = StringBuilder()
    var index: Int64 = 0
    var nextCancellationCheck: Int64 = RENDER_SCAN_CANCELLATION_BYTES
    while (index < uri.size) {
        if (index >= nextCancellationCheck) {
            cancellation.throwIfCancelled(phase: "render")
            nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
        }
        let byte = uri[index]
        if (byte <= 32 || byte == 127) {
            index++;
            continue
        }
        if (byte >= 0x80) {
            cancellation.throwIfCancelled(phase: "render")
            return ""
        }
        if (byte == b':') {
            cancellation.throwIfCancelled(phase: "render")
            return normalized.toString()
        }
        if (byte == b'/' || byte == b'#' || byte == b'?') {
            cancellation.throwIfCancelled(phase: "render")
            return ""
        }
        normalized.appendFromUtf8([if (byte >= b'A' && byte <= b'Z') {
            byte + 32
        } else {
            byte
        }])
        index++
    }
    cancellation.throwIfCancelled(phase: "render")
    ""
}

private func rendererNormalizedMimeTypes(values: ImmutableArray<String>): Array<String> {
    let normalized = ArrayList<String>()
    for (value in values.toArray()) {
        let candidate = rendererLowerAscii(value)
        var duplicate = false
        for (existing in normalized) {
            if (existing == candidate) {
                duplicate = true
                break
            }
        }
        if (!duplicate) {
            normalized.add(candidate)
        }
    }
    var index: Int64 = 1
    while (index < normalized.size) {
        var current = index
        while (current > 0 && normalized[current] < normalized[current - 1]) {
            let swap = normalized[current - 1]
            normalized[current - 1] = normalized[current]
            normalized[current] = swap
            current--
        }
        index++
    }
    normalized.toArray()
}

private func rendererLowerAscii(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        let byte = value[index]
        if (byte >= b'A' && byte <= b'Z') {
            out.appendFromUtf8([byte + 32]);
            index++
        } else {
            let next = rendererNextRune(value, index);
            out.append(value[index..next]);
            index = next
        }
    }
    out.toString()
}

private func rendererLowerAsciiCancellable(value: String, cancellation: CancellationToken): String {
    cancellation.throwIfCancelled(phase: "render")
    let out = StringBuilder()
    var index: Int64 = 0
    var nextCancellationCheck: Int64 = RENDER_SCAN_CANCELLATION_BYTES
    while (index < value.size) {
        if (index >= nextCancellationCheck) {
            cancellation.throwIfCancelled(phase: "render")
            nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
        }
        let byte = value[index]
        if (byte >= b'A' && byte <= b'Z') {
            out.appendFromUtf8([byte + 32])
            index++
        } else {
            let next = rendererNextRune(value, index)
            out.append(value[index..next])
            index = next
        }
    }
    cancellation.throwIfCancelled(phase: "render")
    out.toString()
}

private func alignmentAttribute(alignment: TableAlignment): String {
    match (alignment) {
        case TableAlignment.Left => " align=\"left\""
        case TableAlignment.Center => " align=\"center\""
        case TableAlignment.Right => " align=\"right\""
        case TableAlignment.None => ""
    }
}

private func stripHtmlTags(value: String): String {
    let out = StringBuilder()
    var inside = false
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'<') {
            inside = true
            index++;
            continue
        }
        if (value[index] == b'>') {
            inside = false
            index++;
            continue
        }
        let next = rendererNextRune(value, index)
        if (!inside) {
            out.append(value[index..next])
        }
        index = next
    }
    out.toString()
}

private func isGfmDisallowedTagAt(value: String, nameStart: Int64): Bool {
    var nameEnd = nameStart
    while (nameEnd < value.size && rendererIsAsciiLetter(value[nameEnd])) {
        // "plaintext" is the longest GFM tagfilter name. Once a tenth
        // alphabetic byte is observed, this tag cannot match, so avoid
        // scanning, slicing, or lowercasing the rest of an attacker-sized
        // name before the output budget is enforced.
        if (nameEnd - nameStart >= 9) {
            return false
        }
        nameEnd++
    }
    let length = nameEnd - nameStart
    if (!isGfmTagFilterBoundary(value, nameEnd)) {
        return false
    }
    match (length) {
        case 3 => rendererAsciiEqualsIgnoreCase(value, nameStart, "xmp")
        case 5 => rendererAsciiEqualsIgnoreCase(value, nameStart, "title") || rendererAsciiEqualsIgnoreCase(value,
            nameStart, "style")
        case 6 => rendererAsciiEqualsIgnoreCase(value, nameStart, "iframe") || rendererAsciiEqualsIgnoreCase(value,
            nameStart, "script")
        case 7 => rendererAsciiEqualsIgnoreCase(value, nameStart, "noembed")
        case 8 => rendererAsciiEqualsIgnoreCase(value, nameStart, "textarea") || rendererAsciiEqualsIgnoreCase(value,
            nameStart, "noframes")
        case 9 => rendererAsciiEqualsIgnoreCase(value, nameStart, "plaintext")
        case _ => false
    }
}

private func isGfmTagFilterBoundary(value: String, index: Int64): Bool {
    if (index == value.size) {
        return true
    }
    let byte = value[index]
    rendererIsAsciiWhitespace(byte) || byte == b'/' || byte == b'>'
}

private func rendererIsAsciiLetter(byte: Byte): Bool {
    (byte >= b'A' && byte <= b'Z') || (byte >= b'a' && byte <= b'z')
}

private func rendererAsciiEqualsIgnoreCase(value: String, start: Int64, expected: String): Bool {
    rendererAsciiRangeEqualsIgnoreCase(value, start, start + expected.size, expected)
}

private func rendererAsciiRangeEqualsIgnoreCase(value: String, start: Int64, end: Int64, expected: String): Bool {
    if (end - start != expected.size) {
        return false
    }
    var index: Int64 = 0
    while (index < expected.size) {
        var actual = value[start + index]
        var wanted = expected[index]
        if (actual >= b'A' && actual <= b'Z') {
            actual += 32
        }
        if (wanted >= b'A' && wanted <= b'Z') {
            wanted += 32
        }
        if (actual != wanted) {
            return false
        }
        index++
    }
    true
}

private func rendererAsciiWholeEqualsIgnoreCase(value: String, expected: String): Bool {
    rendererAsciiRangeEqualsIgnoreCase(value, 0, value.size, expected)
}

private func rendererAsciiWholeEqualsIgnoreCaseCancellable(value: String, expected: String,
    cancellation: CancellationToken): Bool {
    cancellation.throwIfCancelled(phase: "render")
    if (value.size != expected.size) {
        return false
    }
    var index: Int64 = 0
    var nextCancellationCheck: Int64 = RENDER_SCAN_CANCELLATION_BYTES
    while (index < value.size) {
        if (index >= nextCancellationCheck) {
            cancellation.throwIfCancelled(phase: "render")
            nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
        }
        var actual = value[index]
        var wanted = expected[index]
        if (actual >= b'A' && actual <= b'Z') {
            actual += 32
        }
        if (wanted >= b'A' && wanted <= b'Z') {
            wanted += 32
        }
        if (actual != wanted) {
            cancellation.throwIfCancelled(phase: "render")
            return false
        }
        index++
    }
    cancellation.throwIfCancelled(phase: "render")
    true
}

private func rendererCanonicalManifests(values: ImmutableArray<ExtensionManifest>): Array<ExtensionManifest> {
    let manifests = values.toArray()
    var index: Int64 = 1
    while (index < manifests.size) {
        var current = index
        while (current > 0 && rendererManifestComesBefore(manifests[current], manifests[current - 1])) {
            let swap = manifests[current - 1]
            manifests[current - 1] = manifests[current]
            manifests[current] = swap
            current--
        }
        index++
    }
    manifests
}

private func rendererManifestComesBefore(left: ExtensionManifest, right: ExtensionManifest): Bool {
    if (left.extensionId != right.extensionId) {
        return left.extensionId < right.extensionId
    }
    if (left.semanticVersion != right.semanticVersion) {
        return left.semanticVersion < right.semanticVersion
    }
    if (left.implementationVersion != right.implementationVersion) {
        return left.implementationVersion < right.implementationVersion
    }
    rendererMissingPolicyRank(left.missingRendererPolicy) < rendererMissingPolicyRank(right.missingRendererPolicy)
}

private func rendererMissingPolicyName(policy: MissingRendererPolicy): String {
    match (policy) {
        case MissingRendererPolicy.Error => "error"
        case MissingRendererPolicy.RenderChildren => "render-children"
        case MissingRendererPolicy.RenderLiteral => "render-literal"
        case MissingRendererPolicy.Drop => "drop"
        case MissingRendererPolicy.CustomFallback => "custom-fallback"
    }
}

private func rendererMissingPolicyRank(policy: MissingRendererPolicy): Int64 {
    match (policy) {
        case MissingRendererPolicy.Error => 0
        case MissingRendererPolicy.RenderChildren => 1
        case MissingRendererPolicy.RenderLiteral => 2
        case MissingRendererPolicy.Drop => 3
        case MissingRendererPolicy.CustomFallback => 4
    }
}

private func trimTrailingNewlines(value: String): String {
    var end = value.size
    while (end > 0 && (value[end - 1] == 10 || value[end - 1] == 13)) {
        end--
    }
    value[..end]
}

private func rendererFindByte(value: String, byte: Byte, start: Int64, cancellation: CancellationToken): Int64 {
    cancellation.throwIfCancelled(phase: "render")
    var index = start
    var nextCancellationCheck = start + RENDER_SCAN_CANCELLATION_BYTES
    while (index < value.size) {
        if (index >= nextCancellationCheck) {
            cancellation.throwIfCancelled(phase: "render")
            nextCancellationCheck = index + RENDER_SCAN_CANCELLATION_BYTES
        }
        if (value[index] == byte) {
            cancellation.throwIfCancelled(phase: "render")
            return index
        };
        index++
    }
    cancellation.throwIfCancelled(phase: "render")
    -1
}

private func rendererNextRune(value: String, offset: Int64): Int64 {
    if (offset >= value.size) {
        return value.size
    }
    let first = value[offset]
    let width: Int64 = if ((first & 0b1000_0000) == 0) {
        1
    } else if ((first & 0b1110_0000) == 0b1100_0000) {
        2
    } else if ((first & 0b1111_0000) == 0b1110_0000) {
        3
    } else if ((first & 0b1111_1000) == 0b1111_0000) {
        4
    } else {
        1
    }
    let end = offset + width
    if (end < value.size) {
        end
    } else {
        value.size
    }
}

private func htmlOutputPlanner(sink: TextSink): ?HtmlPlanSink {
    if (let plan: HtmlPlanSink <- sink) {
        Some(plan)
    } else {
        None
    }
}
