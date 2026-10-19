package markdown

import std.collection.*

/** Code Groups 1.0 的容器或单个 fenced-code 条目。 */
public enum CodeGroupRole {
    /** 有序代码条目的容器。 */
    | Group
    /** 包含一个普通 CodeBlock 的条目。 */
    | Item
}

/** 从一开始计数、包含两端的代码行范围。 */
public class CodeLineRange {
    /** 首行。 */
    public let firstLine: Int64
    /** 末行。 */
    public let lastLine: Int64
    /** 创建非空正数范围；绑定时再验证代码行数。 */
    public init(firstLine: Int64, lastLine: Int64) {
        if (firstLine < 1 || lastLine < firstLine) {
            throw IllegalArgumentException("invalid code line range")
        }
        this.firstLine = firstLine
        this.lastLine = lastLine
    }
}

/** 代码组的版本化源语义；不包含执行指令、第三方 token 或主题。 */
public class CodeGroupPayload <: CustomPayload {
    /** 容器或条目角色。 */
    public let role: CodeGroupRole
    /** 条目标题；未指定时使用语言，无语言时为 text。 */
    public let title: String
    /** 有序且不重叠的行高亮范围。 */
    public let highlightedLines: ImmutableArray<CodeLineRange>
    /** 可复制的代码正文，保留原始换行，按输入策略解码并移除容器/fence 缩进。 */
    public let copyText: String

    /** 创建容器或条目；容器不携带条目数据。 */
    public init(role: CodeGroupRole, title!: String = "", highlightedLines!: Array<CodeLineRange> = [],
        copyText!: String = "") {
        if (let CodeGroupRole.Group <- role) {
            if (!title.isEmpty() || !highlightedLines.isEmpty() || !copyText.isEmpty()) {
                throw IllegalArgumentException("code group containers cannot carry item data")
            }
        }
        this.role = role
        this.title = title
        this.highlightedLines = ImmutableArray<CodeLineRange>(highlightedLines)
        this.copyText = copyText
    }

    /** 返回 payload schema 身份。 */
    public func payloadTypeId(): String {
        "markdown.code-group/1"
    }
}

/** 显式为可选 code-groups.js 输出渐进增强数据；不会加载脚本。 */
public class CodeGroupHtmlOptions {
    private static let DEFAULT = CodeGroupHtmlOptions()
    /** 是否输出 tabs/copy 增强所需数据；没有脚本时所有代码仍可见。 */
    public let interactive: Bool
    /** 代码组和 tablist 的可访问名称。 */
    public let groupLabel: String
    /** 复制按钮文本。 */
    public let copyLabel: String
    /** 复制成功的 live status。 */
    public let copiedLabel: String
    /** Clipboard API 失败的 live status。 */
    public let copyFailedLabel: String
    /** 复制超限或不可用的按钮说明。 */
    public let copyUnavailableLabel: String
    /** 单块复制数据上限；最大为 4 MiB，超限仍完整显示代码。 */
    public let maximumCopyBytes: Int64

    /** 返回共享的不可变默认选项，避免普通 renderer 为关闭的功能重复分配。 */
    public static func defaults(): CodeGroupHtmlOptions {
        DEFAULT
    }

    /** 创建独立于 parser 和后端主题的 HTML 选项；文本必须非空且不超过 1024 bytes。 */
    public init(interactive!: Bool = false, groupLabel!: String = "Code examples", copyLabel!: String = "Copy code",
        copiedLabel!: String = "Copied", copyFailedLabel!: String = "Copy failed",
        copyUnavailableLabel!: String = "Copy unavailable", maximumCopyBytes!: Int64 = 1048576) {
        if (maximumCopyBytes < 0 || maximumCopyBytes > 4194304) {
            throw IllegalArgumentException("code copy limit must be between zero and 4 MiB")
        }
        for (label in [groupLabel, copyLabel, copiedLabel, copyFailedLabel, copyUnavailableLabel]) {
            if (label.isEmpty() || label.size > 1024) {
                throw IllegalArgumentException("code group labels must contain 1..1024 bytes")
            }
        }
        this.interactive = interactive
        this.groupLabel = groupLabel
        this.copyLabel = copyLabel
        this.copiedLabel = copiedLabel
        this.copyFailedLabel = copyFailedLabel
        this.copyUnavailableLabel = copyUnavailableLabel
        this.maximumCopyBytes = maximumCopyBytes
    }
}

internal func codeGroupPayload(node: NodeRef): ?CodeGroupPayload {
    if (let NodeKind.CustomBlock <- node.kind) {
        return node.asCustomBlock().getOrThrow().payload as CodeGroupPayload
    }
    None
}

internal func isCodeGroupLanguage(language: String): Bool {
    for (index in 0..language.size) {
        let byte = language[index]
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'_' || byte == b'-' || byte == b'+')) {
            return false
        }
    }
    true
}

internal func codeLineCount(code: String): Int64 {
    if (code.isEmpty()) {
        return 0
    }
    var count: Int64 = 0
    for (index in 0..code.size) {
        if (code[index] == b'\n') {
            count++
        }
    }
    count + (if (code.endsWith("\n")) {
        0
    } else {
        1
    })
}

internal class CodeGroupHeader {
    let title: String
    let ranges: Array<CodeLineRange>
    init(title: String, ranges: Array<CodeLineRange>) {
        this.title = title
        this.ranges = ranges
    }
}

/** Parses only the versioned info suffix, never source Markdown or a command. */
internal class CodeGroupHeaderParser {
    private let text: String
    private let maximumLine: Int64
    private var cursor: Int64 = 0

    init(text: String, maximumLine: Int64) {
        this.text = text
        this.maximumLine = maximumLine
    }

    func parse(fallbackTitle: String): ?CodeGroupHeader {
        skipSpace()
        var title = fallbackTitle
        if (text[cursor..].startsWith("title=")) {
            cursor += 6
            if (cursor >= text.size || text[cursor] != b'"') {
                return None
            }
            cursor++
            let out = StringBuilder()
            var run = cursor
            while (cursor < text.size && text[cursor] != b'"') {
                if (text[cursor] < 0x20 || text[cursor] == 0x7F) {
                    return None
                }
                if (text[cursor] == b'\\') {
                    out.append(text[run..cursor])
                    cursor++
                    if (cursor >= text.size || (text[cursor] != b'"' && text[cursor] != b'\\')) {
                        return None
                    }
                    out.append(text[cursor..cursor + 1])
                    cursor++
                    run = cursor
                } else {
                    cursor++
                }
            }
            if (cursor >= text.size) {
                return None
            }
            out.append(text[run..cursor])
            cursor++
            if (out.size > 0) {
                title = out.toString()
            }
            if (cursor < text.size && text[cursor] != b' ' && text[cursor] != b'\t') {
                return None
            }
            skipSpace()
        }
        let ranges = ArrayList<CodeLineRange>()
        if (cursor < text.size && text[cursor] == b'{') {
            cursor++
            while (true) {
                let first = number()
                if (first.isNone()) {
                    return None
                }
                var last = first.getOrThrow()
                if (cursor < text.size && text[cursor] == b'-') {
                    cursor++
                    let end = number()
                    if (end.isNone()) {
                        return None
                    }
                    last = end.getOrThrow()
                }
                if (last < first.getOrThrow() || (!ranges.isEmpty() && first.getOrThrow() <= ranges[ranges
                        .size - 1]
                    .lastLine)) {
                    return None
                }
                ranges.add(CodeLineRange(first.getOrThrow(), last))
                if (cursor >= text.size) {
                    return None
                }
                if (text[cursor] == b'}') {
                    cursor++;
                    break
                }
                if (text[cursor] != b',') {
                    return None
                }
                cursor++
            }
            skipSpace()
        }
        if (cursor != text.size) {
            return None
        }
        Some(CodeGroupHeader(title, ranges.toArray()))
    }

    private func skipSpace(): Unit {
        while (cursor < text.size && (text[cursor] == b' ' || text[cursor] == b'\t')) {
            cursor++
        }
    }

    private func number(): ?Int64 {
        let start = cursor
        var value: Int64 = 0
        while (cursor < text.size && text[cursor] >= b'0' && text[cursor] <= b'9') {
            let digit = Int64(text[cursor] - b'0')
            if (value > maximumLine / 10 || (value == maximumLine / 10 && digit > maximumLine % 10)) {
                return None
            }
            value = value * 10 + digit
            cursor++
        }
        if (cursor == start || value < 1) {
            None
        } else {
            Some(value)
        }
    }
}

internal func validateCodeGroupNode(node: NodeRef, parents: ArrayList<NodeRef>, limits: ParseLimits,
    budget: OperationBudget, cancellation: CancellationToken): Unit {
    if (let NodeKind.CustomInline <- node.kind) {
        if (node.asCustomInline().getOrThrow().payload is CodeGroupPayload) {
            invalidCodeGroup(node)
        }
    }
    if (let Some(value) <- codeGroupPayload(node)) {
        let children = node.children()
        let custom = node.asCustomBlock().getOrThrow()
        match (value.role) {
            case CodeGroupRole.Group =>
                if (custom.localKindId != "code-group" || children.size == 0) {
                    invalidCodeGroup(node)
                }
                for (index in 0..children.size) {
                    budget.consumeScan()
                    cancellation.throwIfCancelled(phase: "bind")
                    let child = codeGroupPayload(children[index])
                    if (child.isNone()) {
                        invalidCodeGroup(node)
                    }
                    if (let CodeGroupRole.Group <- child.getOrThrow().role) {
                        invalidCodeGroup(node)
                    }
                    if (children[index].asCustomBlock().getOrThrow().extensionId != custom.extensionId) {
                        invalidCodeGroup(node)
                    }
                }
            case CodeGroupRole.Item =>
                if (custom.localKindId != "code-group-item" || children.size != 1 || parents.isEmpty()) {
                    invalidCodeGroup(node)
                }
                let owner = codeGroupPayload(parents[parents.size - 1])
                if (owner.isNone()) {
                    invalidCodeGroup(node)
                }
                if (let CodeGroupRole.Item <- owner.getOrThrow().role) {
                    invalidCodeGroup(node)
                }
                let code = children[0].asCodeBlock()
                if (code.isNone() || code.getOrThrow().closingFenceSpan.isNone() || value.title.isEmpty()) {
                    invalidCodeGroup(node)
                }
                if (let CodeBlockKind.Indented <- code.getOrThrow().codeKind) {
                    invalidCodeGroup(node)
                }
                for (literal in [value.title, value.copyText, code.getOrThrow().language]) {
                    if (literal.size > limits.maximumLiteralBytes) {
                        throw LimitExceededException("literal_bytes", limits.maximumLiteralBytes, literal.size, "bind",
                            span: node.span)
                    }
                    budget.consumeScan(steps: literal.size)
                }
                let language = code.getOrThrow().language
                if (!isCodeGroupLanguage(language)) {
                    invalidCodeGroup(node)
                }
                if (language.isEmpty() && (value.title != "text" || !value.highlightedLines.isEmpty())) {
                    invalidCodeGroup(node)
                }
                for (index in 0..value.title.size) {
                    if (index % 256 == 0) {
                        cancellation.throwIfCancelled(phase: "bind")
                    }
                    if (value.title[index] < 0x20 || value.title[index] == 0x7F) {
                        invalidCodeGroup(node)
                    }
                }
                let text = code.getOrThrow().literal
                var matched: Int64 = 0
                var cursor: Int64 = 0
                while (cursor < value.copyText.size) {
                    if (cursor % 256 == 0) {
                        cancellation.throwIfCancelled(phase: "bind")
                    }
                    var byte = value.copyText[cursor]
                    cursor++
                    if (byte == b'\r') {
                        byte = b'\n'
                        if (cursor < value.copyText.size && value.copyText[cursor] == b'\n') {
                            cursor++
                        }
                    }
                    if (matched >= text.size || text[matched] != byte) {
                        invalidCodeGroup(node)
                    }
                    matched++
                }
                if (matched != text.size) {
                    invalidCodeGroup(node)
                }
                budget.consumeScan(steps: text.size)
                let lines = codeLineCount(text)
                var previous: Int64 = 0
                for (index in 0..value.highlightedLines.size) {
                    budget.consumeScan()
                    let range = value.highlightedLines[index]
                    if (range.firstLine <= previous || range.lastLine > lines) {
                        invalidCodeGroup(node)
                    }
                    previous = range.lastLine
                }
        }
    }
}

private func invalidCodeGroup(node: NodeRef): Nothing {
    throw MarkdownException(MarkdownErrorCode.ExtensionFailure, "invalid code group structure or copy content",
        phase: "bind", span: node.span)
}

/** One immutable code String and a bounded mutable traversal cursor per item. */
internal class CodeGroupLineState {
    let node: NodeRef
    let code: String
    let ranges: ImmutableArray<CodeLineRange>
    var offset: Int64 = 0
    var line: Int64 = 1
    var rangeIndex: Int64 = 0
    init(node: NodeRef, code: String, ranges: ImmutableArray<CodeLineRange>) {
        this.node = node
        this.code = code
        this.ranges = ranges
    }
}
