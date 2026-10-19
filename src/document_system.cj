package markdown

import std.collection.*
import std.unicode.*

/** DocumentGraph 使用的显式文档 ID 和 source 文本。 */
public class DocumentInput {
    /** 文档的唯一标识。 */
    public let id: String
    /** 文档的 Markdown source 文本。 */
    public let source: String
    /**
     * 创建文档输入；`id` 为空时抛出 `IllegalArgumentException`。
     * @param id 文档的唯一标识。
     * @param source 文档的 Markdown source 文本。
     */
    public init(id: String, source: String) {
        if (id.isEmpty()) {
            throw IllegalArgumentException("document id must not be empty")
        }
        this.id = id
        this.source = source
    }
}

/** 从一个文档中的 link NodeId 指向 destination 的图边。 */
public class DocumentGraphEdge {
    /** link 所在文档的 ID。 */
    public let sourceDocumentId: String
    /** link 目标文本。 */
    public let destination: String
    /** link 节点的 id。 */
    public let nodeId: NodeId
    /**
     * 创建图边。
     * @param sourceDocumentId link 所在文档的 ID。
     * @param destination link 目标文本。
     * @param nodeId link 节点的 id。
     */
    public init(sourceDocumentId: String, destination: String, nodeId: NodeId) {
        this.sourceDocumentId = sourceDocumentId
        this.destination = destination
        this.nodeId = nodeId
    }
}

/** 跨文档 reference definition 及其所属文档 ID。 */
public class CrossDocumentReference {
    /** definition 所属文档 ID。 */
    public let documentId: String
    /** 引用定义。 */
    public let definition: ReferenceDefinition
    /**
     * 创建跨文档引用。
     * @param documentId definition 所属文档 ID。
     * @param definition 引用定义。
     */
    public init(documentId: String, definition: ReferenceDefinition) {
        this.documentId = documentId
        this.definition = definition
    }
}

/**
 * 对调用方提供的多个文档构建 snapshot 和 link edge 图。
 *
 * `build` 不读取文件或访问网络；`documentIds` 保留输入顺序，reference resolution
 * 也按该顺序查找 effective definition。
 */
public class DocumentGraph {
    private let snapshots: HashMap<String, DocumentSnapshot>
    /** 输入顺序的文档 ID 列表。 */
    public let documentIds: ImmutableArray<String>
    /** 跨文档 link edges。 */
    public let edges: ImmutableArray<DocumentGraphEdge>

    private init(ids: Array<String>, snapshots: HashMap<String, DocumentSnapshot>, edges: Array<DocumentGraphEdge>) {
        documentIds = ImmutableArray<String>(ids)
        this.snapshots = snapshots
        this.edges = ImmutableArray<DocumentGraphEdge>(edges)
    }

    /** 解析所有 inputs 并建立文档快照与 link edges。
     * @param engine 用于解析的 engine。
     * @param inputs 文档输入列表；id 重复时抛出异常。
     * @return 包含 snapshot 和 link edges 的 `DocumentGraph`。
     * @throws IllegalArgumentException 文档 id 重复时。
     * @throws MarkdownException 解析失败（含超限或取消）时。
     */
    public static func build(engine: MarkdownEngine, inputs: Array<DocumentInput>): DocumentGraph {
        let ids = ArrayList<String>()
        let snapshots = HashMap<String, DocumentSnapshot>()
        let edges = ArrayList<DocumentGraphEdge>()
        for (input in inputs) {
            if (snapshots.get(input.id).isSome()) {
                throw IllegalArgumentException("duplicate document id")
            }
            let snapshot = engine.parseSnapshot(input.source)
            ids.add(input.id);
            snapshots.add(input.id, snapshot)
            for (link in AstQuery.links(snapshot.result.document)) {
                if (documentDestination(link.destination)) {
                    edges.add(DocumentGraphEdge(input.id, link.destination, link.node.nodeId))
                }
            }
        }
        DocumentGraph(ids.toArray(), snapshots, edges.toArray())
    }

    /** 按文档 ID 返回 snapshot。
     * @param id 文档唯一标识。
     * @return 对应 snapshot；不存在时为 `None`。
     */
    public func snapshot(id: String): ?DocumentSnapshot {
        snapshots.get(id)
    }

    /** 按输入顺序查找第一个 effective reference definition。
     * @param label 引用 label。
     * @return 第一个生效的跨文档引用；不存在时为 `None`。
     */
    public func resolveReference(label: String): ?CrossDocumentReference {
        let normalized = normalizeGraphLabel(label)
        for (id in documentIds.toArray()) {
            if (let Some(snapshot) <- snapshots.get(id)) {
                let root = snapshot.result.document.root().asDocument().getOrThrow()
                for (definition in root.references.toArray()) {
                    if (definition.isEffective && definition.labelNormalized == normalized) {
                        return Some(CrossDocumentReference(id, definition))
                    }
                }
            }
        }
        None
    }
}

/** HTML 转 Markdown 的输入信任策略。 */
public enum HtmlInputPolicy {
    /** 拒绝包含 script、style 或事件处理的输入。 */
    | RejectDangerous
    /** 信任输入，仅做结构转换。 */
    | Trusted
}

/** HTML 转 Markdown 对未知 tag 的保真策略。 */
public enum HtmlFidelityPolicy {
    /** 丢弃未知 tag，仅保留语义内容。 */
    | Semantic
    /** 原样保留未知 tag 文本。 */
    | PreserveUnknownHtml
}

/** HTML 转 Markdown 的安全和保真选项。 */
public class HtmlToMarkdownOptions {
    /** 输入信任策略。 */
    public let inputPolicy: HtmlInputPolicy
    /** 未知 tag 保真策略。 */
    public let fidelityPolicy: HtmlFidelityPolicy
    /**
     * 创建转换选项。
     * @param inputPolicy 输入信任策略。
     * @param fidelityPolicy 未知 tag 保真策略。
     */
    public init(inputPolicy!: HtmlInputPolicy = HtmlInputPolicy.RejectDangerous,
        fidelityPolicy!: HtmlFidelityPolicy = HtmlFidelityPolicy.Semantic) {
        this.inputPolicy = inputPolicy
        this.fidelityPolicy = fidelityPolicy
    }
}

/** 将受限 HTML 结构转换为 Markdown 的 converter。 */
public class HtmlToMarkdownConverter {
    /** 转换选项。 */
    public let options: HtmlToMarkdownOptions
    /**
     * 创建 converter。
     * @param options 转换选项。
     */
    public init(options!: HtmlToMarkdownOptions = HtmlToMarkdownOptions()) {
        this.options = options
    }

    /** 转换 HTML；`RejectDangerous` 遇到 script/style/event handler 等输入会失败。
     * @param html 受限 HTML 输入。
     * @return 转换得到的 Markdown 文本。
     * @throws MarkdownException 输入被判定为危险 HTML 时。
     * @throws IllegalArgumentException 出现未闭合的 HTML tag 时。
     */
    public func convert(html: String): String {
        if (let HtmlInputPolicy.RejectDangerous <- options.inputPolicy) {
            let lower = html.toLower()
            if (lower.contains("<script") || lower.contains("<style") || lower.contains("javascript:") ||
                lower.contains("onerror=") || lower.contains("onload=")) {
                throw MarkdownException(MarkdownErrorCode.RenderFailure, "dangerous HTML input rejected",
                    phase: "html_to_markdown")
            }
        }
        let out = StringBuilder()
        let openLinks = ArrayList<String>()
        var index: Int64 = 0
        while (index < html.size) {
            if (html[index] != b'<') {
                let nextTag = documentFindByte(html, b'<', index)
                let end = if (nextTag < 0) {
                    html.size
                } else {
                    nextTag
                }
                out.append(decodeDocumentEntities(html[index..end]));
                index = end
                continue
            }
            let close = documentFindByte(html, b'>', index + 1)
            if (close < 0) {
                throw IllegalArgumentException("unclosed HTML tag")
            }
            let rawTag = html[index..close + 1]
            let tag = parseDocumentTag(rawTag)
            if (tag.name == "a" && !tag.closing) {
                out.append("[");
                openLinks.add(tag.href)
            } else if (tag.name == "a" && tag.closing) {
                let href = if (openLinks.isEmpty()) {
                    ""
                } else {
                    openLinks.remove(at: openLinks.size - 1)
                }
                out.append("](");
                out.append(href);
                out.append(")")
            } else {
                let marker = htmlMarkdownMarker(tag.name, tag.closing)
                if (!marker.isEmpty()) {
                    out.append(marker)
                } else if (let HtmlFidelityPolicy.PreserveUnknownHtml <- options.fidelityPolicy) {
                    out.append(rawTag)
                }
            }
            index = close + 1
        }
        trimDocumentMarkdown(out.toString())
    }
}

internal class ParsedDocumentTag {
    let name: String
    let closing: Bool
    let href: String
    init(name: String, closing: Bool, href: String) {
        this.name = name
        this.closing = closing
        this.href = href
    }
}

/** virtual syntax tree 的一页，包含源码范围、相交 tokens 和 NodeIds。 */
public class VirtualTreePage {
    /** 页序号，从 0 开始。 */
    public let index: Int64
    /** 本页覆盖的 source span。 */
    public let sourceRange: SourceSpan
    /** 与本页相交的 syntax tokens。 */
    public let tokens: ImmutableArray<SyntaxToken>
    /** 与本页相交的节点 id。 */
    public let nodeIds: ImmutableArray<NodeId>
    /**
     * 创建虚拟树页。
     * @param index 页序号。
     * @param sourceRange 本页覆盖的 source span。
     * @param tokens 与本页相交的 syntax tokens。
     * @param nodeIds 与本页相交的节点 id。
     */
    public init(index: Int64, sourceRange: SourceSpan, tokens: Array<SyntaxToken>, nodeIds: Array<NodeId>) {
        this.index = index
        this.sourceRange = sourceRange
        this.tokens = ImmutableArray<SyntaxToken>(tokens)
        this.nodeIds = ImmutableArray<NodeId>(nodeIds)
    }
}

/**
 * 将已完整解析 snapshot 按 byte 分页的虚拟 CST 视图。
 *
 * 它不会替代完整 AST/CST；page 访问按 `pageBytes` 扫描并受 cancellation 与 budget
 * 约束。
 */
public class VirtualSyntaxTree {
    /** 分页来源的 snapshot。 */
    public let snapshot: DocumentSnapshot
    /** 每页的 byte 数。 */
    public let pageBytes: Int64
    /** 总页数。 */
    public let pageCount: Int64
    /**
     * 创建虚拟 CST 视图。
     * @param snapshot 已完整解析的 snapshot。
     * @param pageBytes 每页 byte 数，必须为正。
     */
    public init(snapshot: DocumentSnapshot, pageBytes!: Int64 = 65536) {
        if (pageBytes <= 0) {
            throw IllegalArgumentException("virtual page size must be positive")
        }
        this.snapshot = snapshot
        this.pageBytes = pageBytes
        pageCount = (snapshot.result.source.byteLength() + pageBytes - 1) / pageBytes
    }

    /** 返回指定页；index 越界时失败。
     * @param index 页序号。
     * @param cancellation 协作式取消信号。
     * @param budget 单次分页的操作预算。
     * @return 对应页内容。
     * @throws IllegalArgumentException index 越界时。
     * @throws MarkdownException 取消或预算耗尽时。
     */
    public func page(index: Int64, cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()): VirtualTreePage {
        if (index < 0 || index >= pageCount) {
            throw IllegalArgumentException("virtual page index is outside tree")
        }
        cancellation.throwIfCancelled(phase: "virtual_tree")
        let start = index * pageBytes
        let end = min(snapshot.result.source.byteLength(), start + pageBytes)
        let range = SourceSpan(start, end)
        let tokens = ArrayList<SyntaxToken>()
        for (token in snapshot.syntaxTree.root.tokens.toArray()) {
            budget.consumeScan()
            if (documentSpansOverlap(token.span, range)) {
                tokens.add(token)
            }
        }
        let nodes = ArrayList<NodeId>()
        for (event in snapshot.result.document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                budget.consumeRenderedNode()
                if (let Some(span) <- node.span) {
                    if (documentSpansOverlap(span, range)) {
                        nodes.add(node.nodeId)
                    }
                }
            }
        }
        cancellation.throwIfCancelled(phase: "virtual_tree")
        VirtualTreePage(index, range, tokens.toArray(), nodes.toArray())
    }
}

private func documentDestination(value: String): Bool {
    !value.isEmpty() && !value.startsWith("#") && !value.contains(":")
}

private func normalizeGraphLabel(value: String): String {
    externalGraphCollapse(value.toLower())
}

private func externalGraphCollapse(value: String): String {
    let out = StringBuilder();
    var spacing = false
    for (byte in value.toArray()) {
        if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13) {
            spacing = true
        } else {
            if (spacing && out.size > 0) {
                out.append(" ")
            }
            spacing = false
            out.appendFromUtf8([byte])
        }
    }
    out.toString()
}

private func parseDocumentTag(raw: String): ParsedDocumentTag {
    let body = externalDocumentTrim(raw[1..raw.size - 1])
    let closing = body.startsWith("/")
    let start: Int64 = if (closing) {
        1
    } else {
        0
    }
    var end = start
    while (end < body.size && ((body[end] >= b'A' && body[end] <= b'Z') || (body[end] >= b'a' && body[end] <= b'z') || (body[end] >=
            b'0' && body[end] <= b'9'))) {
        end++
    }
    let name = body[start..end].toLower()
    var href = ""
    let hrefAt = documentFindString(body.toLower(), "href=", end)
    if (hrefAt >= 0) {
        var valueStart = hrefAt + 5
        if (valueStart < body.size && (body[valueStart] == b'"' || body[valueStart] == b'\'')) {
            let quoteByte = body[valueStart];
            valueStart++
            let valueEnd = documentFindByte(body, quoteByte, valueStart)
            if (valueEnd < 0) {
                throw IllegalArgumentException("unclosed href attribute")
            }
            href = body[valueStart..valueEnd]
        }
    }
    ParsedDocumentTag(name, closing, href)
}

private func htmlMarkdownMarker(name: String, closing: Bool): String {
    if (name == "strong" || name == "b") {
        "**"
    } else if (name == "em" || name == "i") {
        "*"
    } else if (name == "code") {
        "`"
    } else if (name == "del" || name == "s") {
        "~~"
    } else if (name == "p" || name == "div") {
        if (closing) {
            "\n\n"
        } else {
            ""
        }
    } else if (name == "br") {
        "  \n"
    } else if (name == "blockquote") {
        if (closing) {
            "\n"
        } else {
            "> "
        }
    } else if (name == "li") {
        if (closing) {
            "\n"
        } else {
            "- "
        }
    } else if (name == "ul" || name == "ol") {
        if (closing) {
            "\n"
        } else {
            ""
        }
    } else if (name == "hr") {
        "\n---\n"
    } else if (name.size == 2 && name[0] == b'h' && name[1] >= b'1' && name[1] <= b'6') {
        if (closing) {
            "\n\n"
        } else {
            documentRepeat("#", Int64(name[1] - b'0')) + " "
        }
    } else {
        ""
    }
}

private func decodeDocumentEntities(value: String): String {
    value.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'")
}

private func trimDocumentMarkdown(value: String): String {
    var start: Int64 = 0;
    var end = value.size
    while (start < end && (value[start] == 10 || value[start] == 13)) {
        start++
    }
    while (end > start && (value[end - 1] == 10 || value[end - 1] == 13 || value[end - 1] == b' ')) {
        end--
    }
    value[start..end] + "\n"
}

private func documentRepeat(value: String, count: Int64): String {
    let out = StringBuilder();
    for (_ in 0..count) {
        out.append(value)
    };
    out.toString()
}

private func externalDocumentTrim(value: String): String {
    var start: Int64 = 0;
    var end = value.size
    while (start < end && (value[start] == b' ' || value[start] == b'\t')) {
        start++
    }
    while (end > start && (value[end - 1] == b' ' || value[end - 1] == b'\t' || value[end - 1] == b'/')) {
        end--
    }
    value[start..end]
}

private func documentFindByte(value: String, byte: Byte, start: Int64): Int64 {
    var index = start;
    while (index < value.size) {
        if (value[index] == byte) {
            return index
        };
        index++
    };
    -1
}

private func documentFindString(value: String, target: String, start: Int64): Int64 {
    var index = start
    while (index + target.size <= value.size) {
        if (value[index..index + target.size] == target) {
            return index
        }
        index++
    }
    -1
}

private func documentSpansOverlap(left: SourceSpan, right: SourceSpan): Bool {
    left.startByte < right.endByte && right.startByte < left.endByte
}
