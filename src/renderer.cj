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

    internal func writeFromNode(slice: String, node: MarkdownNode): SinkWriteResult {
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
        if (slice.isEmpty()) {
            return
        }
        if (let Some(entries) <- mappedEntries) {
            let end = outputOffset + slice.size
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
    func renderHtml(node: MarkdownNode): TrustedHtml
}

internal class RenderFrame {
    let node: MarkdownNode
    let exiting: Bool
    let tableHeader: Bool
    let suppressParagraph: Bool
    let newlineAfter: Bool

    init(node: MarkdownNode, exiting: Bool, tableHeader!: Bool = false, suppressParagraph!: Bool = false,
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

    public func render(
        document: Document,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): String {
        let sink = StringTextSink()
        renderTo(document, sink, cancellation: cancellation, budget: budget)
        sink.content()
    }

    public func renderTo(
        document: Document,
        sink: TextSink,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): Unit {
        let stack = ArrayList<RenderFrame>()
        stack.add(RenderFrame(document, false))
        var checkpoints: Int64 = 0
        while (!stack.isEmpty()) {
            let frame = stack.remove(at: stack.size - 1)
            checkpoints++
            if (checkpoints >= 256) {
                cancellation.throwIfCancelled(phase: "render")
                checkpoints = 0
            }
            if (frame.exiting) {
                writeHtmlExit(frame, sink, cancellation, budget)
            } else {
                budget.consumeRenderedNode()
                writeHtmlEnter(frame, stack, sink, cancellation, budget)
            }
        }
    }

    private func writeHtmlEnter(
        frame: RenderFrame,
        stack: ArrayList<RenderFrame>,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        let node = frame.node
        match (node) {
            case _: Document => pushContainer(frame, stack)
            case heading: Heading =>
                write("<h${heading.level}>", sink, cancellation, budget)
                pushContainer(frame, stack)
            case _: Paragraph =>
                if (!frame.suppressParagraph) {
                    write("<p>", sink, cancellation, budget)
                }
                pushContainer(frame, stack)
            case _: BlockQuote =>
                write("<blockquote>\n", sink, cancellation, budget)
                pushContainer(frame, stack)
            case list: List =>
                match (list.listKind) {
                    case ListKind.Bullet => write("<ul>\n", sink, cancellation, budget)
                    case ListKind.Ordered =>
                        if (list.start == 1) {
                            write("<ol>\n", sink, cancellation, budget)
                        } else {
                            write("<ol start=\"${list.start}\">\n", sink, cancellation, budget)
                        }
                }
                stack.add(RenderFrame(list, true))
                pushChildren(list, stack, suppressParagraph: list.tight)
            case item: ListItem =>
                match (item.taskState) {
                    case TaskState.Checked => write(
                        "<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\" checked=\"\"> ", sink,
                        cancellation, budget)
                    case TaskState.Unchecked => write(
                        "<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"\"> ", sink, cancellation,
                        budget)
                    case TaskState.NotTask => write("<li>", sink, cancellation, budget)
                }
                let children = item.children()
                let startsWithBlock = children.size > 0 && !isParagraphNode(children[0])
                if (children.size > 0 && (!frame.suppressParagraph || startsWithBlock)) {
                    write("\n", sink, cancellation, budget)
                }
                stack.add(RenderFrame(item, true, suppressParagraph: frame.suppressParagraph))
                var childIndex = children.size - 1
                while (childIndex >= 0) {
                    let childSuppress = frame.suppressParagraph && isParagraphNode(children[childIndex])
                    stack.add(
                        RenderFrame(children[childIndex], false, suppressParagraph: childSuppress,
                            newlineAfter: childSuppress && childIndex + 1 < children.size))
                    childIndex--
                }
            case _: ThematicBreak => write("<hr />\n", sink, cancellation, budget)
            case code: CodeBlock =>
                var classAttribute = ""
                if (!code.language.isEmpty()) {
                    classAttribute = " class=\"language-${escapeAttribute(code.language, safe: isSafePolicy())}\""
                }
                let literal = if (code.literal.isEmpty() || code.literal.endsWith("\n")) {
                    code.literal
                } else {
                    code.literal + "\n"
                }
                write("<pre><code${classAttribute}>", sink, cancellation, budget)
                writeFromNode(escapeText(literal), code, sink, cancellation, budget)
                write("</code></pre>\n", sink, cancellation, budget)
            case html: HtmlBlock => writeRawHtml(html, true, sink, cancellation, budget)
            case table: Table => renderTable(table, sink, cancellation, budget)
            case row: TableRow =>
                write("<tr>\n", sink, cancellation, budget)
                stack.add(RenderFrame(row, true, tableHeader: row.header))
                pushChildren(row, stack, tableHeader: row.header)
            case cell: TableCell =>
                let tag = if (frame.tableHeader) {
                    "th"
                } else {
                    "td"
                }
                let alignment = alignmentAttribute(cell.alignment)
                write("<${tag}${alignment}>", sink, cancellation, budget)
                stack.add(RenderFrame(cell, true, tableHeader: frame.tableHeader))
                pushChildren(cell, stack, tableHeader: frame.tableHeader)
            case text: Text => writeFromNode(escapeText(text.value), text, sink, cancellation, budget)
            case _: SoftBreak => write("\n", sink, cancellation, budget)
            case _: HardBreak => write("<br />\n", sink, cancellation, budget)
            case code: CodeSpan =>
                write("<code>", sink, cancellation, budget)
                writeFromNode(escapeText(code.literal), code, sink, cancellation, budget)
                write("</code>", sink, cancellation, budget)
            case _: Emphasis =>
                write("<em>", sink, cancellation, budget)
                pushContainer(frame, stack)
            case _: Strong =>
                write("<strong>", sink, cancellation, budget)
                pushContainer(frame, stack)
            case _: Strikethrough =>
                write("<del>", sink, cancellation, budget)
                pushContainer(frame, stack)
            case link: Link =>
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
                let external = externalAttributes(link.destination)
                write("<a${href}${title}${external}>", sink, cancellation, budget)
                pushContainer(frame, stack)
            case image: Image =>
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
                write("<img${src} alt=\"${escapeAttribute(plainTextOf(image), safe: isSafePolicy())}\"${title} />", sink,
                    cancellation, budget)
            case html: HtmlInline => writeRawHtml(html, false, sink, cancellation, budget)
            case custom: CustomBlock => renderCustomEnter(custom.extensionId, custom.localKindId, frame, stack, sink,
                cancellation, budget)
            case custom: CustomInline => renderCustomEnter(custom.extensionId, custom.localKindId, frame, stack, sink,
                cancellation, budget)
            case _ => throw MarkdownException(MarkdownErrorCode.UnsupportedNode, "unsupported MarkdownNode subtype",
                phase: "render", span: node.span)
        }
    }

    private func writeHtmlExit(
        frame: RenderFrame,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        match (frame.node) {
            case _: Document => ()
            case heading: Heading => write("</h${heading.level}>\n", sink, cancellation, budget)
            case _: Paragraph =>
                if (!frame.suppressParagraph) {
                    write("</p>\n", sink, cancellation, budget)
                } else if (frame.newlineAfter) {
                    write("\n", sink, cancellation, budget)
                }
            case _: BlockQuote => write("</blockquote>\n", sink, cancellation, budget)
            case list: List => match (list.listKind) {
                case ListKind.Bullet => write("</ul>\n", sink, cancellation, budget)
                case ListKind.Ordered => write("</ol>\n", sink, cancellation, budget)
            }
            case _: ListItem => write("</li>\n", sink, cancellation, budget)
            case _: Table => write("</table>\n", sink, cancellation, budget)
            case _: TableRow => write("</tr>\n", sink, cancellation, budget)
            case _: TableCell =>
                let tag = if (frame.tableHeader) {
                    "th"
                } else {
                    "td"
                }
                write("</${tag}>\n", sink, cancellation, budget)
            case _: Emphasis => write("</em>", sink, cancellation, budget)
            case _: Strong => write("</strong>", sink, cancellation, budget)
            case _: Strikethrough => write("</del>", sink, cancellation, budget)
            case _: Link => write("</a>", sink, cancellation, budget)
            case custom: CustomBlock => renderCustomExit(custom.extensionId, custom.localKindId, sink, cancellation,
                budget)
            case custom: CustomInline => renderCustomExit(custom.extensionId, custom.localKindId, sink, cancellation,
                budget)
            case _ => ()
        }
    }

    private func pushContainer(frame: RenderFrame, stack: ArrayList<RenderFrame>): Unit {
        stack.add(
            RenderFrame(frame.node, true, tableHeader: frame.tableHeader, suppressParagraph: frame.suppressParagraph,
                newlineAfter: frame.newlineAfter))
        pushChildren(frame.node, stack, tableHeader: frame.tableHeader, suppressParagraph: frame.suppressParagraph)
    }

    private func pushChildren(
        node: MarkdownNode,
        stack: ArrayList<RenderFrame>,
        tableHeader!: Bool = false,
        suppressParagraph!: Bool = false
    ): Unit {
        let children = node.children()
        var index = children.size - 1
        while (index >= 0) {
            stack.add(RenderFrame(children[index], false, tableHeader: tableHeader, suppressParagraph: suppressParagraph))
            index--
        }
    }

    private func writeRawHtml(
        html: MarkdownNode,
        block: Bool,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        let literal = match (html) {
            case block: HtmlBlock => block.literal
            case inline: HtmlInline => inline.literal
            case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "raw HTML renderer received a non-HTML node", phase: "render", span: html.span)
        }
        match (options.rawHtmlPolicy) {
            case RawHtmlPolicyKind.Escape => writeFromNode(
                escapeText(literal) + if (block && !literal.endsWith("\n")) {
                    "\n"
                } else {
                    ""
                }, html, sink, cancellation, budget)
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
                }, html, sink, cancellation, budget)
            case RawHtmlPolicyKind.Sanitize => match (sanitizer) {
                case Some(port) =>
                    let sanitized = port.sanitize(literal)
                    writeFromNode(sanitized + if (block && !sanitized.endsWith("\n")) {
                        "\n"
                    } else {
                        ""
                    }, html, sink, cancellation, budget)
                case None => throw MarkdownException(MarkdownErrorCode.RenderFailure, "sanitizer adapter is required",
                    phase: "render")
            }
            case RawHtmlPolicyKind.CustomHandler => throw MarkdownException(MarkdownErrorCode.RenderFailure,
                "custom raw HTML handler is required", phase: "render")
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
        match (sink.write(value)) {
            case SinkWriteResult.Success => ()
            case SinkWriteResult.Failure(error) => throw SinkFailureException(error)
        }
        cancellation.throwIfCancelled(phase: "render")
    }

    private func writeFromNode(
        value: String,
        node: MarkdownNode,
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

    private func renderCustomEnter(
        extensionId: String,
        localKindId: String,
        frame: RenderFrame,
        stack: ArrayList<RenderFrame>,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (let Some(rule) <- findRendererRule(extensionId, localKindId)) {
            let attributes = StringBuilder()
            if (!rule.classToken.isEmpty()) {
                attributes.append(" class=\"")
                attributes.append(escapeAttribute(rule.classToken, safe: isSafePolicy()))
                attributes.append("\"")
            }
            for (attribute in rule.attributes.toArray()) {
                if (let Some(value) <- structuredAttributeValue(frame.node, attribute.source)) {
                    var allowed = true
                    match (attribute.kind) {
                        case RendererAttributeKind.Text => ()
                        case RendererAttributeKind.LinkUri => allowed = isAllowedLink(value)
                        case RendererAttributeKind.ImageUri => allowed = isAllowedImage(value)
                    }
                    if (allowed) {
                        attributes.append(" ");
                        attributes.append(attribute.name);
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
                writeFromNode(escapeText(customLiteral(frame.node)), frame.node, sink, cancellation, budget)
            }
            pushContainer(frame, stack)
        } else {
            let policy = match (findExtensionManifest(extensionId)) {
                case Some(manifest) => manifest.missingRendererPolicy
                case None => MissingRendererPolicy.Error
            }
            match (policy) {
                case MissingRendererPolicy.Error => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                    "missing renderer for ${extensionId}/${localKindId}", phase: "render", span: frame.node.span)
                case MissingRendererPolicy.RenderChildren => pushChildren(frame.node, stack)
                case MissingRendererPolicy.RenderLiteral => writeFromNode(escapeText(customLiteral(frame.node)),
                    frame.node, sink, cancellation, budget)
                case MissingRendererPolicy.Drop => ()
                case MissingRendererPolicy.CustomFallback => match (findExtensionFallback(extensionId)) {
                    case Some(fallback) => writeFromNode(fallback.renderHtml(frame.node).value, frame.node, sink,
                        cancellation, budget)
                    case None => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                        "custom renderer fallback is not installed for ${extensionId}", phase: "render",
                        span: frame.node.span)
                }
            }
        }
    }

    private func renderTable(
        table: Table,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        let rows = table.children()
        write("<table>\n", sink, cancellation, budget)
        if (rows.size > 0) {
            write("<thead>\n", sink, cancellation, budget)
            renderTableRowDirect(rows[0], true, sink, cancellation, budget)
            write("</thead>\n", sink, cancellation, budget)
        }
        if (rows.size > 1) {
            write("<tbody>\n", sink, cancellation, budget)
            for (index in 1..rows.size) {
                renderTableRowDirect(rows[index], false, sink, cancellation, budget)
            }
            write("</tbody>\n", sink, cancellation, budget)
        }
        write("</table>\n", sink, cancellation, budget)
    }

    private func renderTableRowDirect(
        node: MarkdownNode,
        header: Bool,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        match (node) {
            case row: TableRow =>
                budget.consumeRenderedNode()
                write("<tr>\n", sink, cancellation, budget)
                let cells = row.children()
                for (cellIndex in 0..cells.size) {
                    let cellNode = cells[cellIndex]
                    match (cellNode) {
                        case cell: TableCell =>
                            budget.consumeRenderedNode()
                            let tag = if (header) {
                                "th"
                            } else {
                                "td"
                            }
                            write("<${tag}${alignmentAttribute(cell.alignment)}>", sink, cancellation, budget)
                            renderInlineSequence(cell.children(), sink, cancellation, budget)
                            write("</${tag}>\n", sink, cancellation, budget)
                        case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                            "table row contains non-cell", phase: "render", span: cellNode.span)
                    }
                }
                write("</tr>\n", sink, cancellation, budget)
            case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "table contains non-row",
                phase: "render", span: node.span)
        }
    }

    private func renderInlineSequence(
        nodes: ImmutableArray<MarkdownNode>,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (nodes.size == 1) {
            match (nodes[0]) {
                case text: Text =>
                    budget.consumeRenderedNode()
                    writeFromNode(escapeText(text.value), text, sink, cancellation, budget)
                    return
                case _ => ()
            }
        }
        let frames = ArrayList<RenderFrame>()
        var index = nodes.size - 1
        while (index >= 0) {
            frames.add(RenderFrame(nodes[index], false));
            index--
        }
        while (!frames.isEmpty()) {
            let frame = frames.remove(at: frames.size - 1)
            if (frame.exiting) {
                writeHtmlExit(frame, sink, cancellation, budget)
            } else {
                budget.consumeRenderedNode();
                writeHtmlEnter(frame, frames, sink, cancellation, budget)
            }
        }
    }

    private func renderCustomExit(
        extensionId: String,
        localKindId: String,
        sink: TextSink,
        cancellation: CancellationToken,
        budget: OperationBudget
    ): Unit {
        if (let Some(rule) <- findRendererRule(extensionId, localKindId)) {
            write("</${rule.htmlTag}>", sink, cancellation, budget)
        } else {
            throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                "missing renderer for ${extensionId}/${localKindId}", phase: "render")
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
        if (index == value.size || rendererIsAsciiWhitespace(value[index])) {
            if (index > start && rendererLowerAscii(value[start..index]) == normalizedExpected) {
                return true
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

private func isParagraphNode(node: MarkdownNode): Bool {
    match (node) {
        case _: Paragraph => true;
        case _ => false
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
        let stack = ArrayList<RenderFrame>()
        stack.add(RenderFrame(document, false))
        while (!stack.isEmpty()) {
            let frame = stack.remove(at: stack.size - 1)
            if (frame.exiting) {
                match (frame.node) {
                    case _: Paragraph => out.append("\n\n")
                    case _: Heading => out.append("\n\n")
                    case _: ListItem => out.append("\n")
                    case _: CodeBlock => out.append("\n\n")
                    case _: TableCell => out.append("\t")
                    case _: TableRow => out.append("\n")
                    case link: Link =>
                        if (options.includeLinkDestinations) {
                            out.append(" (");
                            out.append(link.destination);
                            out.append(")")
                        }
                    case custom: CustomBlock => appendCustomTextSuffix(custom.extensionId, custom.localKindId, out)
                    case custom: CustomInline => appendCustomTextSuffix(custom.extensionId, custom.localKindId, out)
                    case _ => ()
                }
                continue
            }
            match (frame.node) {
                case text: Text => out.append(text.value)
                case _: SoftBreak => out.append(options.softBreak)
                case _: HardBreak => out.append("\n")
                case code: CodeSpan => out.append(code.literal)
                case code: CodeBlock =>
                    out.append(code.literal);
                    stack.add(RenderFrame(code, true))
                case html: HtmlBlock =>
                    out.append(stripHtmlTags(html.literal));
                    stack.add(RenderFrame(html, true))
                case html: HtmlInline => out.append(stripHtmlTags(html.literal))
                case image: Image => out.append(plainTextOf(image))
                case _: ThematicBreak => out.append("\n")
                case custom: CustomBlock =>
                    appendCustomTextPrefix(custom.extensionId, custom.localKindId, custom, out)
                    pushPlainContainer(frame, stack)
                case custom: CustomInline =>
                    appendCustomTextPrefix(custom.extensionId, custom.localKindId, custom, out)
                    pushPlainContainer(frame, stack)
                case _ => pushPlainContainer(frame, stack)
            }
        }
        trimTrailingNewlines(out.toString())
    }

    private func pushPlainContainer(frame: RenderFrame, stack: ArrayList<RenderFrame>): Unit {
        stack.add(RenderFrame(frame.node, true))
        let children = frame.node.children()
        var index = children.size - 1
        while (index >= 0) {
            stack.add(RenderFrame(children[index], false));
            index--
        }
    }

    private func appendCustomTextPrefix(extensionId: String, localKindId: String, node: MarkdownNode, out: StringBuilder): Unit {
        for (index in 0..extensionRules.size) {
            let rule = extensionRules[index]
            if (rule.extensionId == extensionId && rule.localKindId == localKindId) {
                out.append(rule.textPrefix);
                if (rule.renderPayloadLiteral) {
                    out.append(customLiteral(node))
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

private func plainTextOf(node: MarkdownNode): String {
    let out = StringBuilder()
    let stack = ArrayList<MarkdownNode>()
    stack.add(node)
    while (!stack.isEmpty()) {
        let current = stack.remove(at: stack.size - 1)
        match (current) {
            case text: Text => out.append(text.value)
            case code: CodeSpan => out.append(code.literal)
            case _: SoftBreak => out.append("\n")
            case _: HardBreak => out.append("\n")
            case _ =>
                let children = current.children()
                var index = children.size - 1
                while (index >= 0) {
                    stack.add(children[index]);
                    index--
                }
        }
    }
    out.toString()
}

private func customLiteral(node: MarkdownNode): String {
    match (node) {
        case custom: CustomBlock => match (custom.payload) {
            case syntax: SyntaxPayload => syntax.literal
            case _ => plainTextOf(custom)
        }
        case custom: CustomInline => match (custom.payload) {
            case syntax: SyntaxPayload => syntax.literal
            case _ => plainTextOf(custom)
        }
        case _ => ""
    }
}

private func structuredAttributeValue(node: MarkdownNode, source: RendererAttributeSource): ?String {
    match (source) {
        case RendererAttributeSource.FixedValue(value) => Some(value)
        case RendererAttributeSource.PayloadLiteral => Some(customLiteral(node))
        case RendererAttributeSource.PayloadParameter(name) =>
            let payload: ?CustomPayload = match (node) {
                case value: CustomBlock => Some(value.payload)
                case value: CustomInline => Some(value.payload)
                case _ => None
            }
            match (payload) {
                case Some(value: SyntaxPayload) => match (value.parameter(name)) {
                    case Some(parameter) => Some(syntaxParameterText(parameter))
                    case None => None
                }
                case _ => None
            }
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
