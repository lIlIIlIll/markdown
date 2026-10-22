package markdown.core

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
    /** 创建非空正数范围；绑定时再验证代码行数。
     * @param firstLine 首行的一基编号，必须至少为 1。
     * @param lastLine 末行的一基编号，不得小于 firstLine；范围包含两端。
     */
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

    /** 创建容器或条目；容器不携带条目数据。
     * @param role 代码组容器或条目角色。
     * @param title 条目标题；容器必须为空，默认空。
     * @param highlightedLines 有序不重叠的高亮行范围；容器必须为空，默认空。
     * @param copyText 保留原始换行的复制正文；容器必须为空，默认空。
     */
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

    /** 返回 payload schema 身份。
     * @return 代码组语义的 schema 身份 markdown.code-group/1。
     */
    public func payloadTypeId(): String {
        "markdown.code-group/1"
    }
}

/** 从自定义块读取代码组语义；其他节点不参与代码组处理。
 * @param node 待检查的节点引用。
 * @return CodeGroupPayload；节点类型或 payload 不匹配时为 None。
 */
protected func codeGroupPayload(node: NodeRef): ?CodeGroupPayload {
    if (let NodeKind.CustomBlock <- node.kind) {
        return node.asCustomBlock().getOrThrow().payload as CodeGroupPayload
    }
    None
}

/** 检查代码组语言标记是否只含 ASCII 字母、数字、下划线、连字符或加号。
 * @param language 代码 fence 中的语言标记，允许为空。
 * @return 每个字节均符合允许范围时为 true；空字符串也合法。
 */
protected func isCodeGroupLanguage(language: String): Bool {
    for (index in 0..language.size) {
        let byte = language[index]
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'_' || byte == b'-' || byte == b'+')) {
            return false
        }
    }
    true
}

/** 按 LF 计算代码正文的逻辑行数，末尾换行不额外生成空行。
 * @param code 已规范化换行的代码正文。
 * @return 逻辑行数；空正文为 0。
 */
protected func codeLineCount(code: String): Int64 {
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

/** 校验代码组的父子结构、fence、语言、高亮范围和复制正文一致性。
 * @param node 当前遍历的节点；非代码组节点直接跳过。
 * @param parents 从根到直接父节点排列的祖先栈。
 * @param limits 标题、复制文本和语言标记的 literal 字节限制。
 * @param budget 遍历和文本校验消耗的共享扫描预算。
 * @param cancellation 绑定阶段的取消信号。
 */
protected func validateCodeGroupNode(node: NodeRef, parents: ArrayList<NodeRef>, limits: ParseLimits,
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
