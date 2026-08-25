package markdown

import std.collection.*
import std.unicode.*

public class DocumentInput {
    public let id: String
    public let source: String
    public init(id: String, source: String) {
        if (id.isEmpty()) {
            throw IllegalArgumentException("document id must not be empty")
        }
        this.id = id
        this.source = source
    }
}

public class DocumentGraphEdge {
    public let sourceDocumentId: String
    public let destination: String
    public let nodeId: NodeId
    public init(sourceDocumentId: String, destination: String, nodeId: NodeId) {
        this.sourceDocumentId = sourceDocumentId
        this.destination = destination
        this.nodeId = nodeId
    }
}

public class CrossDocumentReference {
    public let documentId: String
    public let definition: ReferenceDefinition
    public init(documentId: String, definition: ReferenceDefinition) {
        this.documentId = documentId
        this.definition = definition
    }
}

public class DocumentGraph {
    private let snapshots: HashMap<String, DocumentSnapshot>
    public let documentIds: ImmutableArray<String>
    public let edges: ImmutableArray<DocumentGraphEdge>

    private init(ids: Array<String>, snapshots: HashMap<String, DocumentSnapshot>, edges: Array<DocumentGraphEdge>) {
        documentIds = ImmutableArray<String>(ids)
        this.snapshots = snapshots
        this.edges = ImmutableArray<DocumentGraphEdge>(edges)
    }

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
                    edges.add(DocumentGraphEdge(input.id, link.destination, link.nodeId))
                }
            }
        }
        DocumentGraph(ids.toArray(), snapshots, edges.toArray())
    }

    public func snapshot(id: String): ?DocumentSnapshot {
        snapshots.get(id)
    }

    public func resolveReference(label: String): ?CrossDocumentReference {
        let normalized = normalizeGraphLabel(label)
        for (id in documentIds.toArray()) {
            if (let Some(snapshot) <- snapshots.get(id)) {
                for (definition in snapshot.result.document.references.toArray()) {
                    if (definition.isEffective && definition.labelNormalized == normalized) {
                        return Some(CrossDocumentReference(id, definition))
                    }
                }
            }
        }
        None
    }
}

public enum HtmlInputPolicy {
    | RejectDangerous
    | Trusted
}

public enum HtmlFidelityPolicy {
    | Semantic
    | PreserveUnknownHtml
}

public class HtmlToMarkdownOptions {
    public let inputPolicy: HtmlInputPolicy
    public let fidelityPolicy: HtmlFidelityPolicy
    public init(inputPolicy!: HtmlInputPolicy = HtmlInputPolicy.RejectDangerous,
        fidelityPolicy!: HtmlFidelityPolicy = HtmlFidelityPolicy.Semantic) {
        this.inputPolicy = inputPolicy
        this.fidelityPolicy = fidelityPolicy
    }
}

public class HtmlToMarkdownConverter {
    public let options: HtmlToMarkdownOptions
    public init(options!: HtmlToMarkdownOptions = HtmlToMarkdownOptions()) {
        this.options = options
    }

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

public class VirtualTreePage {
    public let index: Int64
    public let sourceRange: SourceSpan
    public let tokens: ImmutableArray<SyntaxToken>
    public let nodeIds: ImmutableArray<NodeId>
    public init(index: Int64, sourceRange: SourceSpan, tokens: Array<SyntaxToken>, nodeIds: Array<NodeId>) {
        this.index = index
        this.sourceRange = sourceRange
        this.tokens = ImmutableArray<SyntaxToken>(tokens)
        this.nodeIds = ImmutableArray<NodeId>(nodeIds)
    }
}

public class VirtualSyntaxTree {
    public let snapshot: DocumentSnapshot
    public let pageBytes: Int64
    public let pageCount: Int64
    public init(snapshot: DocumentSnapshot, pageBytes!: Int64 = 65536) {
        if (pageBytes <= 0) {
            throw IllegalArgumentException("virtual page size must be positive")
        }
        this.snapshot = snapshot
        this.pageBytes = pageBytes
        pageCount = (snapshot.result.source.byteLength() + pageBytes - 1) / pageBytes
    }

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
            if (let WalkEvent.Enter(node) <- event) {
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
