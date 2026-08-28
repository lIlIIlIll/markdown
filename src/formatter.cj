package markdown

import std.collection.*

public class MarkdownFormatOptions {
    public let newline: String
    public let bulletMarker: String
    public let orderedDelimiter: String
    public let headingMarker: String
    public let emphasisMarker: String
    public let strongMarker: String
    public let fenceMarker: String
    public let minimumFenceLength: Int64
    public let tablePadding: Bool
    public let finalNewline: Bool
    public let maximumLineWidth: Int64
    public let reflowParagraphs: Bool

    public init(
        newline!: String = "\n",
        bulletMarker!: String = "-",
        orderedDelimiter!: String = ".",
        headingMarker!: String = "#",
        emphasisMarker!: String = "*",
        strongMarker!: String = "**",
        fenceMarker!: String = "`",
        minimumFenceLength!: Int64 = 3,
        tablePadding!: Bool = true,
        finalNewline!: Bool = true,
        maximumLineWidth!: Int64 = 100,
        reflowParagraphs!: Bool = false
    ) {
        if (newline != "\n" && newline != "\r\n") {
            throw IllegalArgumentException("formatter newline must be LF or CRLF")
        }
        if (bulletMarker != "-" && bulletMarker != "*" && bulletMarker != "+") {
            throw IllegalArgumentException("invalid bullet marker")
        }
        if (orderedDelimiter != "." && orderedDelimiter != ")") {
            throw IllegalArgumentException("invalid ordered delimiter")
        }
        if (minimumFenceLength < 3) {
            throw IllegalArgumentException("minimum fence length must be at least three")
        }
        if (emphasisMarker != "*" && emphasisMarker != "_") {
            throw IllegalArgumentException("emphasis marker must be * or _")
        }
        if (strongMarker != "**" && strongMarker != "__") {
            throw IllegalArgumentException("strong marker must be ** or __")
        }
        this.newline = newline
        this.bulletMarker = bulletMarker
        this.orderedDelimiter = orderedDelimiter
        this.headingMarker = headingMarker
        this.emphasisMarker = emphasisMarker
        this.strongMarker = strongMarker
        this.fenceMarker = fenceMarker
        this.minimumFenceLength = minimumFenceLength
        this.tablePadding = tablePadding
        this.finalNewline = finalNewline
        this.maximumLineWidth = maximumLineWidth
        this.reflowParagraphs = reflowParagraphs
    }
}

internal enum FormatAction {
    | TextValue(String)
    | NodeValue(NodeRef)
}

public class CanonicalMarkdownRenderer {
    public let options: MarkdownFormatOptions
    private let extensionRules: ImmutableArray<RendererRule>

    public init(options!: MarkdownFormatOptions = MarkdownFormatOptions(), extensionRules!: Array<RendererRule> = []) {
        this.options = options
        this.extensionRules = ImmutableArray<RendererRule>(extensionRules)
    }

    public func render(document: Document): String {
        let out = StringBuilder()
        let stack = ArrayList<FormatAction>()
        stack.add(FormatAction.NodeValue(document.root()))
        while (!stack.isEmpty()) {
            let action = stack.remove(at: stack.size - 1)
            match (action) {
                case FormatAction.TextValue(value) => out.append(value)
                case FormatAction.NodeValue(node) => formatNode(node, stack, out)
            }
        }
        var value = trimFormatEnd(out.toString())
        if (options.finalNewline) {
            value += "\n"
        }
        if (options.newline == "\r\n") {
            value = replaceLfWithCrlf(value)
        }
        value
    }

    private func formatNode(node: NodeRef, stack: ArrayList<FormatAction>, out: StringBuilder): Unit {
        match (node.kind) {
            case NodeKind.Document => pushSeparated(node.children(), "\n\n", stack)
            case NodeKind.Paragraph => pushNodes(node.children(), stack)
            case NodeKind.Heading =>
                pushNodes(node.children(), stack)
                stack.add(
                    FormatAction.TextValue(repeatString(options.headingMarker, node.asHeading().getOrThrow().level) + " "))
            case NodeKind.BlockQuote =>
                stack.add(FormatAction.TextValue("\n"))
                pushNodes(node.children(), stack)
                stack.add(FormatAction.TextValue("> "))
            case NodeKind.List => pushList(node, stack)
            case NodeKind.ListItem => pushNodes(node.children(), stack)
            case NodeKind.ThematicBreak => out.append("---")
            case NodeKind.CodeBlock => formatCodeBlock(node.asCodeBlock().getOrThrow(), out)
            case NodeKind.HtmlBlock => out.append(node.asHtmlBlock().getOrThrow().literal)
            case NodeKind.Table => formatTable(node, out)
            case NodeKind.TableRow => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "TableRow must be formatted through Table", phase: "format", span: node.span)
            case NodeKind.TableCell => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "TableCell must be formatted through Table", phase: "format", span: node.span)
            case NodeKind.Text => out.append(escapeMarkdownText(node.asText().getOrThrow().value))
            case NodeKind.SoftBreak => out.append("\n")
            case NodeKind.HardBreak => out.append("\\\n")
            case NodeKind.CodeSpan => formatCodeSpan(node.asCodeSpan().getOrThrow(), out)
            case NodeKind.Emphasis =>
                if (isSimpleDelimiterContent(node) && !endsWithDelimiter(out)) {
                    pushDelimited(options.emphasisMarker, node.children(), stack)
                } else {
                    pushWrapped("<em>", "</em>", node.children(), stack)
                }
            case NodeKind.Strong =>
                if (isSimpleDelimiterContent(node) && !endsWithDelimiter(out)) {
                    pushDelimited(options.strongMarker, node.children(), stack)
                } else {
                    pushWrapped("<strong>", "</strong>", node.children(), stack)
                }
            case NodeKind.Strikethrough =>
                if (isSimpleDelimiterContent(node) && !out.toString().endsWith("~")) {
                    pushDelimited("~~", node.children(), stack)
                } else {
                    pushWrapped("<del>", "</del>", node.children(), stack)
                }
            case NodeKind.Link =>
                let link = node.asLink().getOrThrow()
                stack.add(
                    FormatAction.TextValue("](" + formatDestination(link.destination) + formatTitle(link.title) + ")"))
                pushNodes(node.children(), stack)
                stack.add(FormatAction.TextValue("["))
            case NodeKind.Image =>
                let image = node.asImage().getOrThrow()
                out.append("![")
                out.append(escapeMarkdownText(plainTextOfFormatter(node)))
                out.append("](")
                out.append(formatDestination(image.destination))
                out.append(formatTitle(image.title))
                out.append(")")
            case NodeKind.HtmlInline => out.append(node.asHtmlInline().getOrThrow().literal)
            case NodeKind.CustomBlock =>
                let custom = node.asCustomBlock().getOrThrow()
                formatCustom(custom.extensionId, custom.localKindId, custom.payload, node.children(), node.span, true,
                    stack)
            case NodeKind.CustomInline =>
                let custom = node.asCustomInline().getOrThrow()
                formatCustom(custom.extensionId, custom.localKindId, custom.payload, node.children(), node.span, false,
                    stack)
        }
    }

    private func pushSeparated(nodes: NodeChildren, separator: String, stack: ArrayList<FormatAction>): Unit {
        var index = nodes.size - 1
        while (index >= 0) {
            stack.add(FormatAction.NodeValue(nodes[index]))
            if (index > 0) {
                stack.add(FormatAction.TextValue(separator))
            }
            index--
        }
    }

    private func pushNodes(nodes: NodeChildren, stack: ArrayList<FormatAction>): Unit {
        var index = nodes.size - 1
        while (index >= 0) {
            stack.add(FormatAction.NodeValue(nodes[index]));
            index--
        }
    }

    private func pushDelimited(marker: String, children: NodeChildren, stack: ArrayList<FormatAction>): Unit {
        stack.add(FormatAction.TextValue(marker))
        pushNodes(children, stack)
        stack.add(FormatAction.TextValue(marker))
    }

    private func pushWrapped(opener: String, closer: String, children: NodeChildren, stack: ArrayList<FormatAction>): Unit {
        stack.add(FormatAction.TextValue(closer))
        pushNodes(children, stack)
        stack.add(FormatAction.TextValue(opener))
    }

    private func endsWithDelimiter(out: StringBuilder): Bool {
        let current = out.toString()
        current.endsWith("*") || current.endsWith("_")
    }

    private func isSimpleDelimiterContent(node: NodeRef): Bool {
        let children = node.children()
        if (children.isEmpty()) {
            return false
        }
        var firstByte: Byte = 0
        var lastByte: Byte = 0
        var hasText = false
        for (child in children.toArray()) {
            match (child.kind) {
                case NodeKind.Text =>
                    let text = child.asText().getOrThrow()
                    if (!text.value.isEmpty()) {
                        if (!hasText) {
                            firstByte = text.value[0]
                            hasText = true
                        }
                        lastByte = text.value[text.value.size - 1]
                    }
                case _ => return false
            }
        }
        hasText && isDelimiterWordByte(firstByte) && isDelimiterWordByte(lastByte)
    }

    private func isDelimiterWordByte(value: Byte): Bool {
        (value >= b'a' && value <= b'z') || (value >= b'A' && value <= b'Z') || (value >= b'0' && value <= b'9') ||
            value >= 128
    }

    private func formatCustom(extensionId: String, localKindId: String, payload: CustomPayload, children: NodeChildren,
        span: ?SourceSpan, block: Bool, stack: ArrayList<FormatAction>): Unit {
        for (index in 0..extensionRules.size) {
            let rule = extensionRules[index]
            if (rule.extensionId == extensionId && rule.localKindId == localKindId) {
                if (block) {
                    if (let MarkdownBlockLowering.Line <- rule.markdownBlockLowering) {
                        if (rule.markdownOpener.isEmpty()) {
                            throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                                "line formatter rule has no Markdown opener", phase: "format", span: span)
                        }
                        let literal = match (payload) {
                            case syntax: SyntaxPayload => syntax.literal
                            case _ => ""
                        }
                        stack.add(FormatAction.TextValue(rule.markdownOpener + literal))
                        return
                    }
                }
                if (rule.markdownOpener.isEmpty() || rule.markdownCloser.isEmpty()) {
                    throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                        "extension formatter rule has no Markdown lowering", phase: "format", span: span)
                }
                var parameters = ""
                if (block) {
                    if (let syntax: SyntaxPayload <- payload) {
                        if (!syntax.parameters.isEmpty()) {
                            parameters = " " + syntax.parameters
                        }
                    }
                }
                let opener = if (block) {
                    rule.markdownOpener + parameters + "\n"
                } else {
                    rule.markdownOpener
                }
                let closer = if (block) {
                    "\n" + rule.markdownCloser
                } else {
                    rule.markdownCloser
                }
                stack.add(FormatAction.TextValue(closer))
                if (children.isEmpty()) {
                    if (let syntax: SyntaxPayload <- payload) {
                        stack.add(FormatAction.TextValue(syntax.literal))
                    }
                } else {
                    pushNodes(children, stack)
                }
                stack.add(FormatAction.TextValue(opener))
                return
            }
        }
        throw MarkdownException(MarkdownErrorCode.UnsupportedNode, "missing canonical formatter for extension node",
            phase: "format", span: span)
    }

    private func pushList(node: NodeRef, stack: ArrayList<FormatAction>): Unit {
        let list = node.asList().getOrThrow()
        let children = node.children()
        var index = children.size - 1
        while (index >= 0) {
            match (children[index].kind) {
                case NodeKind.ListItem =>
                    let item = children[index].asListItem().getOrThrow()
                    pushNodes(children[index].children(), stack)
                    let marker = match (list.listKind) {
                        case ListKind.Bullet => options.bulletMarker
                        case ListKind.Ordered => "${list.start + index}${options.orderedDelimiter}"
                    }
                    let task = match (item.taskState) {
                        case TaskState.Checked => " [x]"
                        case TaskState.Unchecked => " [ ]"
                        case TaskState.NotTask => ""
                    }
                    stack.add(FormatAction.TextValue(marker + task + " "))
                    if (index > 0) {
                        stack.add(FormatAction.TextValue("\n"))
                    }
                case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                    "List has non-ListItem child", phase: "format", span: children[index].span)
            }
            index--
        }
    }

    private func formatCodeBlock(code: CodeBlockNodeView, out: StringBuilder): Unit {
        let fence = chooseFence(code.literal)
        out.append(fence)
        if (!code.language.isEmpty()) {
            out.append(code.language)
        }
        out.append("\n")
        out.append(code.literal)
        if (!code.literal.isEmpty() && !code.literal.endsWith("\n")) {
            out.append("\n")
        }
        out.append(fence)
    }

    private func chooseFence(literal: String): String {
        let marker = options.fenceMarker
        var longest: Int64 = 0
        var current: Int64 = 0
        var index: Int64 = 0
        while (index < literal.size) {
            if (literal[index] == marker[0]) {
                current++;
                longest = max(longest, current)
            } else {
                current = 0
            }
            index++
        }
        repeatString(marker, max(options.minimumFenceLength, longest + 1))
    }

    private func formatCodeSpan(code: CodeSpanNodeView, out: StringBuilder): Unit {
        var longest: Int64 = 0
        var current: Int64 = 0
        var index: Int64 = 0
        while (index < code.literal.size) {
            if (code.literal[index] == b'`') {
                current++;
                longest = max(longest, current)
            } else {
                current = 0
            }
            index++
        }
        let marker = repeatString("`", longest + 1)
        out.append(marker)
        if (code.literal.startsWith("`") || code.literal.endsWith("`")) {
            out.append(" ")
        }
        out.append(code.literal)
        if (code.literal.startsWith("`") || code.literal.endsWith("`")) {
            out.append(" ")
        }
        out.append(marker)
    }

    private func formatTable(node: NodeRef, out: StringBuilder): Unit {
        let table = node.asTable().getOrThrow()
        let rows = node.children()
        if (rows.isEmpty()) {
            return
        }
        formatTableRow(rows[0], out)
        out.append("\n|")
        for (index in 0..table.alignments.size) {
            let marker = match (table.alignments[index]) {
                case TableAlignment.Left => ":---"
                case TableAlignment.Center => ":---:"
                case TableAlignment.Right => "---:"
                case TableAlignment.None => "---"
            }
            out.append(if (options.tablePadding) {
                " ${marker} |"
            } else {
                "${marker}|"
            })
        }
        for (index in 1..rows.size) {
            out.append("\n");
            formatTableRow(rows[index], out)
        }
    }

    private func formatTableRow(node: NodeRef, out: StringBuilder): Unit {
        match (node.kind) {
            case NodeKind.TableRow =>
                out.append("|")
                for (cell in node.children().toArray()) {
                    let text = escapeTableCell(plainTextOfFormatter(cell))
                    if (options.tablePadding) {
                        out.append(" ${text} |")
                    } else {
                        out.append("${text}|")
                    }
                }
            case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "Table has non-TableRow child", phase: "format", span: node.span)
        }
    }
}

private func plainTextOfFormatter(node: NodeRef): String {
    let out = StringBuilder()
    let stack = ArrayList<NodeRef>()
    stack.add(node)
    while (!stack.isEmpty()) {
        let current = stack.remove(at: stack.size - 1)
        match (current.kind) {
            case NodeKind.Text => out.append(current.asText().getOrThrow().value)
            case NodeKind.CodeSpan => out.append(current.asCodeSpan().getOrThrow().literal)
            case NodeKind.SoftBreak => out.append(" ")
            case NodeKind.HardBreak => out.append(" ")
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

private func escapeMarkdownText(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        let byte = value[index]
        if (byte == b' ') {
            // A literal space at a block boundary can become indentation or
            // combine with a generated list marker on the next parse.
            out.append("&#32;")
            index++
        } else if (isMarkdownAsciiPunctuation(byte)) {
            // Numeric entities cannot join an adjacent emphasis/link marker
            // into a new delimiter run on the next parse.
            out.append("&#${Int64(byte)};")
            index++
        } else {
            let next = formatterNextRune(value, index)
            out.append(value[index..next])
            index = next
        }
    }
    out.toString()
}

private func isMarkdownAsciiPunctuation(byte: Byte): Bool {
    (byte >= 33 && byte <= 47) || (byte >= 58 && byte <= 64) || (byte >= 91 && byte <= 96) || (byte >= 123 && byte <= 126)
}

private func escapeTableCell(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'|') {
            out.append("\\|");
            index++
        } else {
            let next = formatterNextRune(value, index);
            out.append(value[index..next]);
            index = next
        }
    }
    out.toString()
}

private func formatDestination(value: String): String {
    if (value.contains(" ") || value.contains("(") || value.contains(")")) {
        "<${value}>"
    } else {
        value
    }
}

private func formatTitle(value: String): String {
    if (value.isEmpty()) {
        ""
    } else {
        " \"${value}\""
    }
}

private func repeatString(value: String, count: Int64): String {
    let out = StringBuilder()
    for (_ in 0..count) {
        out.append(value)
    }
    out.toString()
}

private func trimFormatEnd(value: String): String {
    var end = value.size
    while (end > 0 && (value[end - 1] == 10 || value[end - 1] == 13 || value[end - 1] == b' ')) {
        end--
    }
    value[..end]
}

private func replaceLfWithCrlf(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == 10) {
            out.append("\r\n");
            index++
        } else {
            let next = formatterNextRune(value, index);
            out.append(value[index..next]);
            index = next
        }
    }
    out.toString()
}

private func formatterNextRune(value: String, offset: Int64): Int64 {
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
