package markdown

import std.collection.*
import std.unicode.*

/** 标题尾部的作者显式 ID；保留原始拼写和精确来源。 */
public class HeadingIdPayload <: CustomPayload {
    /** 作者输入的 ID，不含 `{#` 和 `}`。 */
    public let rawId: String
    /** ID 本身的 UTF-8 来源范围。 */
    public let idSpan: SourceSpan

    /** 创建标题元数据。
     * @param rawId 合法的非空 ID。
     * @param idSpan ID 本身的来源范围。
     * @throws IllegalArgumentException ID 不符合标题扩展语法时。
     */
    public init(rawId: String, idSpan: SourceSpan) {
        if (!validHeadingId(rawId)) {
            throw IllegalArgumentException("invalid explicit heading ID")
        }
        this.rawId = rawId
        this.idSpan = idSpan
    }

    /** 返回版本化 payload schema。
     * @return 标题 ID schema 身份。
     */
    public func payloadTypeId(): String {
        "markdown.heading-id/1"
    }
}

/** 标题查询、TOC、fragment 校验与 renderer 共用的不可变决策。 */
public class HeadingBinding {
    /** 标题节点身份。 */
    public let heading: NodeId
    /** 标题层级。 */
    public let level: Int64
    /** 不含显式 ID 语法的显示文本。 */
    public let text: String
    /** 文档作用域内唯一的最终 ID。 */
    public let id: String
    /** 作者显式 ID；自动标题时为 None。 */
    public let explicitId: ?String
    /** 标题的来源范围。 */
    public let span: ?SourceSpan
    /** 显式 ID 的来源范围。 */
    public let explicitIdSpan: ?SourceSpan
    /** 宿主指定的文档片段作用域。 */
    public let scope: String

    internal init(node: NodeRef, text: String, id: String, metadata: ?HeadingIdPayload, scope: String) {
        heading = node.nodeId
        level = node.asHeading().getOrThrow().level
        this.text = text
        this.id = id
        explicitId = metadata.map({value => value.rawId})
        explicitIdSpan = metadata.map({value => value.idSpan})
        span = node.span
        this.scope = scope
    }
}

/** 结构化目录条目；跳级标题归属于此前最近的较低层级标题。 */
public class TocEntry {
    /** 条目引用的同一标题绑定。 */
    public let heading: HeadingBinding
    /** 保持文档顺序的子条目。 */
    public let children: ImmutableArray<TocEntry>
    internal init(heading: HeadingBinding, children: Array<TocEntry>) {
        this.heading = heading
        this.children = ImmutableArray<TocEntry>(children)
    }
}

private class PendingTocEntry {
    let heading: HeadingBinding
    let children = ArrayList<Int64>()
    init(heading: HeadingBinding) {
        this.heading = heading
    }
}

internal func buildToc(headings: ImmutableArray<HeadingBinding>, minimumLevel: Int64, maximumLevel: Int64): Array<TocEntry> {
    if (minimumLevel < 1 || maximumLevel > 6 || minimumLevel > maximumLevel) {
        throw IllegalArgumentException("TOC levels must form a range within 1..6")
    }
    let entries = ArrayList<PendingTocEntry>()
    let parents = ArrayList<Int64>()
    let roots = ArrayList<Int64>()
    for (heading in headings.toArray()) {
        if (heading.level < minimumLevel || heading.level > maximumLevel) {
            continue
        }
        while (!parents.isEmpty() && entries[parents[parents.size - 1]].heading.level >= heading.level) {
            parents.remove(at: parents.size - 1)
        }
        let index = entries.size
        if (parents.isEmpty()) {
            roots.add(index)
        } else {
            entries[parents[parents.size - 1]].children.add(index)
        }
        entries.add(PendingTocEntry(heading))
        parents.add(index)
    }
    let result = HashMap<Int64, TocEntry>()
    var index = entries.size - 1
    while (index >= 0) {
        let children = ArrayList<TocEntry>()
        for (child in entries[index].children) {
            children.add(result[child])
        }
        result.add(index, TocEntry(entries[index].heading, children.toArray()))
        index--
    }
    let output = ArrayList<TocEntry>()
    for (root in roots) {
        output.add(result[root])
    }
    output.toArray()
}

internal func validHeadingId(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (byte >= 0x80) {
            continue
        }
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'_' || byte == b'-' || byte == b'.' || byte == b':')) {
            return false
        }
    }
    true
}

internal func headingMetadata(node: NodeRef): ?HeadingIdPayload {
    let children = node.children()
    for (index in 0..children.size) {
        let child = children[index]
        if (let NodeKind.CustomInline <- child.kind) {
            if (let value: HeadingIdPayload <- child.asCustomInline().getOrThrow().payload) {
                return Some(value)
            }
        }
    }
    None
}

internal func headingDisplayText(node: NodeRef, consume: (Int64) -> Unit, maximumBytes: Int64): String {
    let output = StringBuilder()
    var bytes: Int64 = 0
    let stack = ArrayList<NodeRef>()
    stack.add(node)
    while (!stack.isEmpty()) {
        let current = stack.remove(at: stack.size - 1)
        consume(1)
        var text = ""
        match (current.kind) {
            case NodeKind.Text => text = current.asText().getOrThrow().value
            case NodeKind.CodeSpan => text = current.asCodeSpan().getOrThrow().literal
            case NodeKind.SoftBreak | NodeKind.HardBreak => text = " "
            case _ =>
                let children = current.children()
                var index = children.size - 1
                while (index >= 0) {
                    stack.add(children[index]);
                    index--
                }
        }
        consume(text.size)
        if (text.size > maximumBytes - bytes) {
            throw LimitExceededException("literal_bytes", maximumBytes, bytes + text.size, "bind", span: node.span)
        }
        bytes += text.size
        output.append(text)
    }
    output.toString()
}

internal func headingSlug(text: String, consume: (Int64) -> Unit): String {
    let output = StringBuilder()
    var pendingSpace = false
    var written = false
    var index: Int64 = 0
    var checkpoint: Int64 = 0
    while (index < text.size) {
        if (index - checkpoint >= 1024) {
            consume(index - checkpoint);
            checkpoint = index
        }
        let byte = text[index]
        if (byte >= 0x80) {
            let end = nextRuneOffset(text, index)
            let (rune, _) = Rune.fromUtf8(text[index..end].toArray(), 0)
            if (rune.isWhiteSpace()) {
                pendingSpace = written
                index = end
                continue
            }
        }
        if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13) {
            pendingSpace = written
            index++
            continue
        }
        if (byte >= 0x80 || (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <=
            b'9') || byte == b'_' || byte == b'-') {
            if (pendingSpace) {
                output.append("-");
                pendingSpace = false
            }
            if (byte >= b'A' && byte <= b'Z') {
                output.appendFromUtf8([byte + 32]);
                index++
            } else {
                let end = nextRuneOffset(text, index)
                output.append(text[index..end])
                index = end
            }
            written = true
        } else {
            index++
        }
    }
    consume(text.size - checkpoint)
    let value = output.toString()
    var start: Int64 = 0
    var end = value.size
    while (start < end && value[start] == b'-') {
        start++
    }
    while (end > start && value[end - 1] == b'-') {
        end--
    }
    if (start == end) {
        "section"
    } else {
        value[start..end]
    }
}
