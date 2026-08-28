package markdown

import std.collection.*

public class SinkError <: Exception {
    public init(message: String) {
        super(message)
    }
    protected override func getClassName(): String {
        "SinkError"
    }
}

public enum SinkWriteResult {
    | Success
    | Failure(SinkError)
}

public interface TextSink {
    func write(slice: String): SinkWriteResult
}

public enum AsyncSinkWriteResult {
    | Continue
    | Pause
    | Failed(SinkError)
}

public interface AsyncTextSink {
    func write(slice: String): AsyncSinkWriteResult
}

public enum AsyncRenderState {
    | Complete
    | Paused
    | Failed(SinkError)
}

public class StringTextSink <: TextSink {
    private let builder = StringBuilder()
    private let mappedEntries: ?ArrayList<RenderedSourceMapEntry>
    private var outputOffset: Int64 = 0

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
            entries.add(RenderedSourceMapEntry(SourceSpan(outputOffset, end), sourceSpan, nodeId, generated))
            outputOffset = end
        }
    }
}

public class SinkFailureException <: MarkdownException {
    public let cause: SinkError

    public init(cause: SinkError) {
        super(MarkdownErrorCode.SinkFailure, cause.message, phase: "render")
        this.cause = cause
    }

    protected override func getClassName(): String {
        "SinkFailureException"
    }
}

public enum RawHtmlPolicyKind {
    | Escape
    | Drop
    | PassThrough
    | Sanitize
    | CustomHandler
}

public class LinkUriPolicy {
    public let allowRelative: Bool
    public let allowHttp: Bool
    public let allowHttps: Bool
    public let allowMailto: Bool

    public init(allowRelative: Bool, allowHttp: Bool, allowHttps: Bool, allowMailto: Bool) {
        this.allowRelative = allowRelative
        this.allowHttp = allowHttp
        this.allowHttps = allowHttps
        this.allowMailto = allowMailto
    }

    public static func safe(): LinkUriPolicy {
        LinkUriPolicy(true, true, true, true)
    }
}

public class ImageUriPolicy {
    public let allowRelative: Bool
    public let allowRemoteImages: Bool
    public let allowDataImages: Bool
    public let allowedDataMimeTypes: ImmutableArray<String>

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

    public static func safe(): ImageUriPolicy {
        ImageUriPolicy(true, false, false)
    }
}

public class HtmlOptions {
    public let policy: HtmlPolicy
    public let rawHtmlPolicy: RawHtmlPolicyKind
    public let linkUriPolicy: LinkUriPolicy
    public let imageUriPolicy: ImageUriPolicy
    public let externalLinkRel: String
    public let externalLinkTarget: String

    public init(
        policy: HtmlPolicy,
        rawHtmlPolicy: RawHtmlPolicyKind,
        linkUriPolicy: LinkUriPolicy,
        imageUriPolicy: ImageUriPolicy,
        externalLinkRel!: String = "",
        externalLinkTarget!: String = ""
    ) {
        this.policy = policy
        this.rawHtmlPolicy = rawHtmlPolicy
        this.linkUriPolicy = linkUriPolicy
        this.imageUriPolicy = imageUriPolicy
        this.externalLinkRel = externalLinkRel
        this.externalLinkTarget = externalLinkTarget
    }

    public static func safe(): HtmlOptions {
        HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(), ImageUriPolicy.safe())
    }

    public static func specCompatible(): HtmlOptions {
        HtmlOptions(HtmlPolicy.specCompatible(), RawHtmlPolicyKind.PassThrough, LinkUriPolicy(true, true, true, true),
            ImageUriPolicy(true, true, true))
    }

    public static func gfmCompatible(): HtmlOptions {
        HtmlOptions(HtmlPolicy.gfmCompatible(), RawHtmlPolicyKind.PassThrough, LinkUriPolicy(true, true, true, true),
            ImageUriPolicy(true, true, true))
    }
}

public class TrustedHtml {
    public let value: String

    private init(value: String) {
        this.value = value
    }

    public static unsafe func fromString(value: String): TrustedHtml {
        TrustedHtml(value)
    }
}

public interface ExtensionRendererFallback {
    prop extensionId: String
    func renderHtml(node: NodeRef): TrustedHtml
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

public class HtmlRenderer {
    public let options: HtmlOptions
    private let extensionRules: ImmutableArray<RendererRule>
    private let sanitizer: ?HtmlSanitizerPort
    private let extensionManifests: ImmutableArray<ExtensionManifest>
    private let extensionFallbacks: ImmutableArray<ExtensionRendererFallback>

    public init(options!: HtmlOptions = HtmlOptions.safe(), extensionRules!: Array<RendererRule> = [],
        sanitizer!: ?HtmlSanitizerPort = None, extensionManifests!: Array<ExtensionManifest> = [],
        extensionFallbacks!: Array<ExtensionRendererFallback> = []) {
        for (rule in extensionRules) {
            validateRendererRuleForRuntime(rule)
        }
        this.options = options
        this.extensionRules = ImmutableArray<RendererRule>(extensionRules)
        this.sanitizer = sanitizer
        this.extensionManifests = ImmutableArray<ExtensionManifest>(extensionManifests)
        this.extensionFallbacks = ImmutableArray<ExtensionRendererFallback>(extensionFallbacks)
    }

    public func fingerprint(): String {
        let out = CanonicalDescriptor()
        out.append("html-renderer-v1|")
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
        out.append("|rel=");
        out.append(options.externalLinkRel);
        out.append("|target=")
        out.append(options.externalLinkTarget)
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

    /** Renders the canonical arena AST directly. */
    public func render(
        ast: Document,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): String {
        let sink = StringTextSink()
        renderArenaTo(ast, sink, cancellation, budget)
        sink.content()
    }

    public func renderTo(
        ast: Document,
        sink: TextSink,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): Unit {
        renderArenaTo(ast, sink, cancellation, budget)
    }

    private func renderArenaTo(ast: Document, sink: TextSink, cancellation: CancellationToken, budget: OperationBudget): Unit {
        let stack = ArrayList<ArenaRenderFrame>()
        stack.add(ArenaRenderFrame(ast.root(), false))
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
    }

    private func writeArenaEnter(frame: ArenaRenderFrame, stack: ArrayList<ArenaRenderFrame>, sink: TextSink,
        cancellation: CancellationToken, budget: OperationBudget): Unit {
        let node = frame.node
        match (node.kind) {
            case NodeKind.DocumentNode => pushArenaContainer(frame, stack)
            case NodeKind.Heading =>
                let level = node.asHeading().getOrThrow().level
                write("<h${level}>", sink, cancellation, budget)
                pushArenaContainer(frame, stack)
            case NodeKind.Paragraph =>
                if (!frame.suppressParagraph) {
                    write("<p>", sink, cancellation, budget)
                }
                pushArenaContainer(frame, stack)
            case NodeKind.BlockQuote =>
                write("<blockquote>\n", sink, cancellation, budget)
                pushArenaContainer(frame, stack)
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
                pushArenaChildren(node, stack, suppressParagraph: list.tight)
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
                let classAttribute = if (code.language.isEmpty()) {
                    ""
                } else {
                    " class=\"language-${escapeAttribute(code.language, safe: isSafePolicy())}\""
                }
                let literal = if (code.literal.isEmpty() || code.literal.endsWith("\n")) {
                    code.literal
                } else {
                    code.literal + "\n"
                }
                write("<pre><code${classAttribute}>", sink, cancellation, budget)
                writeFromNode(escapeText(literal), node, sink, cancellation, budget)
                write("</code></pre>\n", sink, cancellation, budget)
            case NodeKind.HtmlBlock => writeArenaRawHtml(node.asHtmlBlock().getOrThrow().literal, true, node, sink,
                cancellation, budget)
            case NodeKind.Table => renderArenaTable(node, sink, cancellation, budget)
            case NodeKind.TableRow =>
                let row = node.asTableRow().getOrThrow()
                write("<tr>\n", sink, cancellation, budget)
                stack.add(ArenaRenderFrame(node, true, tableHeader: row.header))
                pushArenaChildren(node, stack, tableHeader: row.header)
            case NodeKind.TableCell =>
                let tag = if (frame.tableHeader) {
                    "th"
                } else {
                    "td"
                }
                let alignment = alignmentAttribute(node.asTableCell().getOrThrow().alignment)
                write("<${tag}${alignment}>", sink, cancellation, budget)
                stack.add(ArenaRenderFrame(node, true, tableHeader: frame.tableHeader))
                pushArenaChildren(node, stack, tableHeader: frame.tableHeader)
            case NodeKind.Text => writeFromNode(escapeText(node.asText().getOrThrow().value), node, sink, cancellation,
                budget)
            case NodeKind.SoftBreak => write("\n", sink, cancellation, budget)
            case NodeKind.HardBreak => write("<br />\n", sink, cancellation, budget)
            case NodeKind.CodeSpan =>
                write("<code>", sink, cancellation, budget)
                writeFromNode(escapeText(node.asCodeSpan().getOrThrow().literal), node, sink, cancellation, budget)
                write("</code>", sink, cancellation, budget)
            case NodeKind.Emphasis =>
                write("<em>", sink, cancellation, budget)
                pushArenaContainer(frame, stack)
            case NodeKind.Strong =>
                write("<strong>", sink, cancellation, budget)
                pushArenaContainer(frame, stack)
            case NodeKind.Strikethrough =>
                write("<del>", sink, cancellation, budget)
                pushArenaContainer(frame, stack)
            case NodeKind.Link =>
                let link = node.asLink().getOrThrow()
                let href = if (isAllowedLink(link.destination)) {
                    " href=\"${escapeAttribute(encodeUri(link.destination), safe: isSafePolicy())}\""
                } else {
                    ""
                }
                let title = if (link.title.isEmpty()) {
                    ""
                } else {
                    " title=\"${escapeAttribute(link.title, safe: isSafePolicy())}\""
                }
                write("<a${href}${title}${externalAttributes(link.destination)}>", sink, cancellation, budget)
                pushArenaContainer(frame, stack)
            case NodeKind.Image =>
                let image = node.asImage().getOrThrow()
                let src = if (isAllowedImage(image.destination)) {
                    " src=\"${escapeAttribute(encodeUri(image.destination), safe: isSafePolicy())}\""
                } else {
                    ""
                }
                let title = if (image.title.isEmpty()) {
                    ""
                } else {
                    " title=\"${escapeAttribute(image.title, safe: isSafePolicy())}\""
                }
                write("<img${src} alt=\"${escapeAttribute(arenaPlainText(node), safe: isSafePolicy())}\"${title} />",
                    sink, cancellation, budget)
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

    private func pushArenaContainer(frame: ArenaRenderFrame, stack: ArrayList<ArenaRenderFrame>): Unit {
        stack.add(
            ArenaRenderFrame(frame.node, true, tableHeader: frame.tableHeader,
                suppressParagraph: frame.suppressParagraph, newlineAfter: frame.newlineAfter))
        pushArenaChildren(frame.node, stack, tableHeader: frame.tableHeader, suppressParagraph: frame.suppressParagraph)
    }

    private func pushArenaChildren(node: NodeRef, stack: ArrayList<ArenaRenderFrame>, tableHeader!: Bool = false,
        suppressParagraph!: Bool = false): Unit {
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
        if (let Some(rule) <- findRendererRule(custom.extensionId, custom.localKindId)) {
            let attributes = StringBuilder()
            if (!rule.classToken.isEmpty()) {
                attributes.append(" class=\"")
                attributes.append(escapeAttribute(rule.classToken, safe: isSafePolicy()))
                attributes.append("\"")
            }
            for (attribute in rule.attributes.toArray()) {
                if (let Some(value) <- arenaStructuredAttributeValue(node, attribute.source)) {
                    var allowed = true
                    match (attribute.kind) {
                        case RendererAttributeKind.Text => ()
                        case RendererAttributeKind.LinkUri => allowed = isAllowedLink(value)
                        case RendererAttributeKind.ImageUri => allowed = isAllowedImage(value)
                    }
                    if (allowed) {
                        attributes.append(" ")
                        attributes.append(attribute.name)
                        attributes.append("=\"")
                        let encoded = match (attribute.kind) {
                            case RendererAttributeKind.Text => value
                            case _ => encodeUri(value)
                        }
                        attributes.append(escapeAttribute(encoded, safe: isSafePolicy()))
                        attributes.append("\"")
                    }
                }
            }
            write("<${rule.htmlTag}${attributes.toString()}>", sink, cancellation, budget)
            if (rule.renderPayloadLiteral) {
                writeFromNode(escapeText(arenaCustomLiteral(node)), node, sink, cancellation, budget)
            }
            pushArenaContainer(frame, stack)
            return
        }
        let policy = match (findExtensionManifest(custom.extensionId)) {
            case Some(manifest) => manifest.missingRendererPolicy
            case None => MissingRendererPolicy.Error
        }
        match (policy) {
            case MissingRendererPolicy.Error => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                "missing renderer for ${custom.extensionId}/${custom.localKindId}", phase: "render", span: node.span)
            case MissingRendererPolicy.RenderChildren => pushArenaChildren(node, stack)
            case MissingRendererPolicy.RenderLiteral => writeFromNode(escapeText(arenaCustomLiteral(node)), node, sink,
                cancellation, budget)
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
        if (let Some(rule) <- findRendererRule(custom.extensionId, custom.localKindId)) {
            write("</${rule.htmlTag}>", sink, cancellation, budget)
        }
    }

    private func arenaCustomLiteral(node: NodeRef): String {
        let payload = match (node.kind) {
            case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow().payload
            case NodeKind.CustomInline => node.asCustomInline().getOrThrow().payload
            case _ => return ""
        }
        match (payload) {
            case syntax: SyntaxPayload => syntax.literal
            case _ => arenaPlainText(node)
        }
    }

    private func arenaStructuredAttributeValue(node: NodeRef, source: RendererAttributeSource): ?String {
        match (source) {
            case RendererAttributeSource.FixedValue(value) => Some(value)
            case RendererAttributeSource.PayloadLiteral => Some(arenaCustomLiteral(node))
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
            case RawHtmlPolicyKind.Escape => writeFromNode(
                escapeText(literal) + if (block && !literal.endsWith("\n")) {
                    "\n"
                } else {
                    ""
                }, node, sink, cancellation, budget)
            case RawHtmlPolicyKind.Drop => ()
            case RawHtmlPolicyKind.PassThrough =>
                let filtered = match (options.policy.kind) {
                    case HtmlPolicyKind.GfmCompatible => applyGfmTagFilter(literal)
                    case _ => literal
                }
                writeFromNode(filtered + if (block && !filtered.endsWith("\n")) {
                    "\n"
                } else {
                    ""
                }, node, sink, cancellation, budget)
            case RawHtmlPolicyKind.Sanitize => match (sanitizer) {
                case Some(port) =>
                    let sanitized = port.sanitize(literal)
                    writeFromNode(sanitized + if (block && !sanitized.endsWith("\n")) {
                        "\n"
                    } else {
                        ""
                    }, node, sink, cancellation, budget)
                case None => throw MarkdownException(MarkdownErrorCode.RenderFailure, "sanitizer adapter is required",
                    phase: "render", span: node.span)
            }
            case RawHtmlPolicyKind.CustomHandler => throw MarkdownException(MarkdownErrorCode.RenderFailure,
                "custom raw HTML handler is required", phase: "render", span: node.span)
        }
    }

    private func renderArenaTable(table: NodeRef, sink: TextSink, cancellation: CancellationToken,
        budget: OperationBudget): Unit {
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
        if (nodes.size == 1) {
            let node = nodes[0]
            if (let NodeKind.Text <- node.kind) {
                budget.consumeRenderedNode()
                writeFromNode(escapeText(node.asText().getOrThrow().value), node, sink, cancellation, budget)
                return
            }
        }
        var index = nodes.size - 1
        while (index >= 0) {
            frames.add(ArenaRenderFrame(nodes[index], false))
            index--
        }
        while (!frames.isEmpty()) {
            let frame = frames.remove(at: frames.size - 1)
            if (frame.exiting) {
                writeArenaExit(frame, sink, cancellation, budget)
            } else {
                budget.consumeRenderedNode()
                writeArenaEnter(frame, frames, sink, cancellation, budget)
            }
        }
    }

    private func arenaPlainText(root: NodeRef): String {
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
        cancellation.throwIfCancelled(phase: "render")
        budget.consumeOutput(bytes: value.size)
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
        cancellation.throwIfCancelled(phase: "render")
        budget.consumeOutput(bytes: value.size)
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

    private func isAllowedLink(uri: String): Bool {
        match (options.policy.kind) {
            case HtmlPolicyKind.SpecCompatible => return true
            case HtmlPolicyKind.GfmCompatible => return true
            case _ => ()
        }
        let scheme = uriScheme(uri)
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

    private func isAllowedImage(uri: String): Bool {
        let scheme = uriScheme(uri)
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
            let comma = rendererFindByte(uri, b',', 5)
            if (comma < 0) {
                return false
            }
            let metadata = rendererLowerAscii(uri[5..comma])
            let semicolon = rendererFindByte(metadata, b';', 0)
            let mediaType = if (semicolon < 0) {
                metadata
            } else {
                metadata[0..semicolon]
            }
            for (mime in options.imageUriPolicy.allowedDataMimeTypes.toArray()) {
                if (mediaType == rendererLowerAscii(mime)) {
                    return true
                }
            }
        }
        false
    }

    private func externalAttributes(uri: String): String {
        let scheme = uriScheme(uri)
        if (scheme != "http" && scheme != "https") {
            return ""
        }
        let out = StringBuilder()
        var rel = options.externalLinkRel
        if (isSafePolicy() && rendererLowerAscii(options.externalLinkTarget) == "_blank") {
            if (!containsAsciiWhitespaceToken(rel, "noopener")) {
                rel = appendAsciiWhitespaceToken(rel, "noopener")
            }
            if (!containsAsciiWhitespaceToken(rel, "noreferrer")) {
                rel = appendAsciiWhitespaceToken(rel, "noreferrer")
            }
        }
        if (!rel.isEmpty()) {
            out.append(" rel=\"")
            out.append(escapeAttribute(rel, safe: isSafePolicy()))
            out.append("\"")
        }
        if (!options.externalLinkTarget.isEmpty()) {
            out.append(" target=\"")
            out.append(escapeAttribute(options.externalLinkTarget, safe: isSafePolicy()))
            out.append("\"")
        }
        out.toString()
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

private func appendAsciiWhitespaceToken(value: String, token: String): String {
    if (value.isEmpty()) {
        token
    } else {
        "${value} ${token}"
    }
}

private func containsAsciiWhitespaceToken(value: String, expected: String): Bool {
    let normalizedExpected = rendererLowerAscii(expected)
    var start: Int64 = 0
    var index: Int64 = 0
    while (index <= value.size) {
        let separator = if (index == value.size) {
            true
        } else {
            rendererIsAsciiWhitespace(value[index])
        }
        if (separator) {
            if (index > start) {
                let token = rendererLowerAscii(value[start..index])
                if (token == normalizedExpected) {
                    return true
                }
            }
            start = index + 1
        }
        index++
    }
    false
}

private func rendererIsAsciiWhitespace(byte: Byte): Bool {
    byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r' || byte == 12
}

extend MarkdownEngine {
    public func htmlRenderer(options!: HtmlOptions = HtmlOptions.safe(), sanitizer!: ?HtmlSanitizerPort = None,
        fallbacks!: Array<ExtensionRendererFallback> = []): HtmlRenderer {
        HtmlRenderer(options: options, extensionRules: dialect.rendererRules.toArray(), sanitizer: sanitizer,
            extensionManifests: dialect.manifests.toArray(), extensionFallbacks: fallbacks)
    }
}

public interface HtmlSanitizerPort {
    // Implementations may throw; HtmlRenderer propagates the failure and never
    // falls back to the unsanitized literal.
    func sanitize(html: String): String
}

public class AsyncHtmlRenderSession {
    private let content: String
    private let chunkBytes: Int64
    private var offset: Int64 = 0

    public init(renderer: HtmlRenderer, document: Document, chunkBytes!: Int64 = 4096,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()) {
        if (chunkBytes <= 0) {
            throw IllegalArgumentException("async render chunk size must be positive")
        }
        this.content = renderer.render(document, cancellation: cancellation, budget: budget)
        this.chunkBytes = chunkBytes
    }

    public func resume(sink: AsyncTextSink, cancellation!: CancellationToken = CancellationToken.none()): AsyncRenderState {
        while (offset < content.size) {
            cancellation.throwIfCancelled(phase: "async_render")
            let end = min(content.size, offset + chunkBytes)
            let chunk = content[offset..end]
            match (sink.write(chunk)) {
                case AsyncSinkWriteResult.Continue => offset = end
                case AsyncSinkWriteResult.Pause => return AsyncRenderState.Paused
                case AsyncSinkWriteResult.Failed(error) => return AsyncRenderState.Failed(error)
            }
        }
        AsyncRenderState.Complete
    }

    public func bytesWritten(): Int64 {
        offset
    }
}

/**
 * Pre-renders the complete HTML value, then applies sink backpressure while
 * emitting bounded chunks. This is buffered output, not incremental rendering.
 */
public class BufferedAsyncHtmlOutputSession {
    private let content: String
    private let chunkBytes: Int64
    private var offset: Int64 = 0

    public init(renderer: HtmlRenderer, document: Document, chunkBytes!: Int64 = 4096,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()) {
        if (chunkBytes <= 0) {
            throw IllegalArgumentException("buffered async output chunk size must be positive")
        }
        this.content = renderer.render(document, cancellation: cancellation, budget: budget)
        this.chunkBytes = chunkBytes
    }

    public func resume(sink: AsyncTextSink, cancellation!: CancellationToken = CancellationToken.none()): AsyncRenderState {
        while (offset < content.size) {
            cancellation.throwIfCancelled(phase: "async_render")
            let end = min(content.size, offset + chunkBytes)
            let chunk = content[offset..end]
            match (sink.write(chunk)) {
                case AsyncSinkWriteResult.Continue => offset = end
                case AsyncSinkWriteResult.Pause => return AsyncRenderState.Paused
                case AsyncSinkWriteResult.Failed(error) => return AsyncRenderState.Failed(error)
            }
        }
        AsyncRenderState.Complete
    }

    public func bytesWritten(): Int64 {
        offset
    }
}

public class PlainTextOptions {
    public let includeLinkDestinations: Bool
    public let softBreak: String

    public init(includeLinkDestinations!: Bool = false, softBreak!: String = "\n") {
        this.includeLinkDestinations = includeLinkDestinations
        this.softBreak = softBreak
    }
}

public class PlainTextRenderer {
    public let options: PlainTextOptions
    private let extensionRules: ImmutableArray<RendererRule>

    public init(options!: PlainTextOptions = PlainTextOptions(), extensionRules!: Array<RendererRule> = []) {
        this.options = options
        this.extensionRules = ImmutableArray<RendererRule>(extensionRules)
    }

    public func render(document: Document): String {
        let out = StringBuilder()
        let stack = ArrayList<ArenaRenderFrame>()
        stack.add(ArenaRenderFrame(document.root(), false))
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
                            out.append(frame.node.asLink().getOrThrow().destination);
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
                    appendCustomTextPrefix(custom.extensionId, custom.localKindId, frame.node, out)
                    pushPlainContainer(frame, stack)
                case NodeKind.CustomInline =>
                    let custom = frame.node.asCustomInline().getOrThrow()
                    appendCustomTextPrefix(custom.extensionId, custom.localKindId, frame.node, out)
                    pushPlainContainer(frame, stack)
                case _ => pushPlainContainer(frame, stack)
            }
        }
        trimTrailingNewlines(out.toString())
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

private func escapeText(value: String): String {
    var needsEscape = false
    var scan: Int64 = 0
    while (scan < value.size) {
        let byte = value[scan]
        if (byte == b'&' || byte == b'<' || byte == b'>' || byte == b'"') {
            needsEscape = true
            break
        }
        scan++
    }
    if (!needsEscape) {
        return value
    }
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        let byte = value[index]
        if (byte == b'&') {
            out.append("&amp;");
            index++
        } else if (byte == b'<') {
            out.append("&lt;");
            index++
        } else if (byte == b'>') {
            out.append("&gt;");
            index++
        } else if (byte == b'"') {
            out.append("&quot;");
            index++
        } else {
            let next = rendererNextRune(value, index);
            out.append(value[index..next]);
            index = next
        }
    }
    out.toString()
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

private func escapeAttribute(value: String, safe!: Bool = false): String {
    var needsEscape = false
    var scan: Int64 = 0
    while (scan < value.size) {
        let byte = value[scan]
        if (byte == b'&' || byte == b'<' || byte == b'>' || byte == b'"' || byte == b'\'' || (safe && (byte < 32 ||
            byte == 127))) {
            needsEscape = true
            break
        }
        scan++
    }
    if (!needsEscape) {
        return value
    }
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        let byte = value[index]
        if (byte == b'&') {
            out.append("&amp;");
            index++
        } else if (byte == b'<') {
            out.append("&lt;");
            index++
        } else if (byte == b'>') {
            out.append("&gt;");
            index++
        } else if (byte == b'"') {
            out.append("&quot;");
            index++
        } else if (byte == b'\'') {
            out.append("&#39;");
            index++
        } else if (safe && (byte < 32 || byte == 127)) {
            out.append("&#xfffd;");
            index++
        } else {
            let next = rendererNextRune(value, index);
            out.append(value[index..next]);
            index = next
        }
    }
    out.toString()
}

private func uriScheme(uri: String): String {
    let normalized = StringBuilder()
    var index: Int64 = 0
    while (index < uri.size) {
        let byte = uri[index]
        if (byte <= 32 || byte == 127) {
            index++;
            continue
        }
        if (byte >= 0x80) {
            return ""
        }
        if (byte == b':') {
            return rendererLowerAscii(normalized.toString())
        }
        if (byte == b'/' || byte == b'#' || byte == b'?') {
            return ""
        }
        normalized.appendFromUtf8([byte])
        index++
    }
    ""
}

private func encodeUri(value: String): String {
    var needsEncoding = false
    var scan: Int64 = 0
    while (scan < value.size) {
        let byte = value[scan]
        if (byte == b' ' || byte == b'`' || byte == b'"' || byte == b'\\' || byte < 0x20 || byte >= 0x80 || byte == b'[' ||
            byte == b']') {
            needsEncoding = true
            break
        }
        scan++
    }
    if (!needsEncoding) {
        return value
    }
    let out = StringBuilder()
    for (byte in value.toArray()) {
        if (byte == b' ') {
            out.append("%20")
        } else if (byte == b'`') {
            out.append("%60")
        } else if (byte == b'"') {
            out.append("%22")
        } else if (byte == b'\\') {
            out.append("%5C")
        } else if (byte < 0x20 || byte >= 0x80 || byte == b'[' || byte == b']') {
            appendPercentByte(out, byte)
        } else {
            out.appendFromUtf8([byte])
        }
    }
    out.toString()
}

private func appendPercentByte(out: StringBuilder, byte: Byte): Unit {
    let digits = "0123456789ABCDEF"
    out.append("%")
    let high = Int64((byte >> 4) & 0x0F)
    let low = Int64(byte & 0x0F)
    out.append(digits[high..high + 1])
    out.append(digits[low..low + 1])
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

private func applyGfmTagFilter(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'<') {
            var nameStart = index + 1
            if (nameStart < value.size && value[nameStart] == b'/') {
                nameStart++
            }
            var nameEnd = nameStart
            while (nameEnd < value.size && ((value[nameEnd] >= b'A' && value[nameEnd] <= b'Z') || (value[nameEnd] >= b'a' &&
                    value[nameEnd] <= b'z'))) {
                nameEnd++
            }
            let name = rendererLowerAscii(value[nameStart..nameEnd])
            if (isGfmDisallowedTag(name)) {
                out.append("&lt;");
                index++;
                continue
            }
        }
        let next = rendererNextRune(value, index)
        out.append(value[index..next])
        index = next
    }
    out.toString()
}

private func isGfmDisallowedTag(name: String): Bool {
    name == "title" || name == "textarea" || name == "style" || name == "xmp" || name == "iframe" || name == "noembed" ||
        name == "noframes" || name == "script" || name == "plaintext"
}

private func trimTrailingNewlines(value: String): String {
    var end = value.size
    while (end > 0 && (value[end - 1] == 10 || value[end - 1] == 13)) {
        end--
    }
    value[..end]
}

private func rendererFindByte(value: String, byte: Byte, start: Int64): Int64 {
    var index = start
    while (index < value.size) {
        if (value[index] == byte) {
            return index
        };
        index++
    }
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
