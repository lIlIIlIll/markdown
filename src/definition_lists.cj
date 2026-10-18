package markdown

import std.collection.*

/** 定义列表节点的结构归属；entry 内先放 term，再放 definition。 */
public enum DefinitionListRole {
    /** 包含 entry 的完整定义列表。 */
    | List
    /** 共享一组 term 和 definition 的条目。 */
    | Entry
    /** children 为行内内容的术语。 */
    | Term
    /** children 为普通 Markdown blocks 的定义正文。 */
    | Definition
}

/** 定义列表的 typed 结构；原文仍由节点 SourceSpan 和 SourceBuffer 保存。 */
public class DefinitionListPayload <: CustomPayload {
    /** 节点在定义列表中的角色。 */
    public let role: DefinitionListRole
    /** 定义正文的原始冒号位置；生成节点可没有标记来源。 */
    public let markerSpan: ?SourceSpan

    /** 创建结构 payload；仅 Definition 角色可以携带 markerSpan。 */
    public init(role: DefinitionListRole, markerSpan!: ?SourceSpan = None) {
        if (markerSpan.isSome()) {
            if (let DefinitionListRole.Definition <- role) {
                ()
            } else {
                throw IllegalArgumentException("only a definition body may have a marker span")
            }
        }
        this.role = role
        this.markerSpan = markerSpan
    }

    /** 返回 payload schema 身份。 */
    public func payloadTypeId(): String {
        "markdown.definition-list/1"
    }
}

internal func definitionListKind(role: DefinitionListRole): String {
    match (role) {
        case DefinitionListRole.List => "definition-list"
        case DefinitionListRole.Entry => "definition-entry"
        case DefinitionListRole.Term => "definition-term"
        case DefinitionListRole.Definition => "definition-body"
    }
}

internal class PendingDefinitionBody {
    let lines: Array<LineRecord>
    let span: SourceSpan
    let markerSpan: SourceSpan
    init(lines: Array<LineRecord>, span: SourceSpan, markerSpan: SourceSpan) {
        this.lines = lines
        this.span = span
        this.markerSpan = markerSpan
    }
}

internal class PendingDefinitionEntry {
    let terms: Array<LineRecord>
    let definitions: Array<PendingDefinitionBody>
    let span: SourceSpan
    init(terms: Array<LineRecord>, definitions: Array<PendingDefinitionBody>, span: SourceSpan) {
        this.terms = terms
        this.definitions = definitions
        this.span = span
    }
}

internal class PendingDefinitionList {
    let rule: BlockSyntaxRule
    let entries: Array<PendingDefinitionEntry>
    let span: SourceSpan
    let nextIndex: Int64
    let nodes = ArrayList<Int64>()
    let entryNodes = ArrayList<Int64>()
    var entryIndex: Int64 = 0
    var definitionIndex: Int64 = 0
    init(rule: BlockSyntaxRule, entries: Array<PendingDefinitionEntry>, span: SourceSpan, nextIndex: Int64) {
        this.rule = rule
        this.entries = entries
        this.span = span
        this.nextIndex = nextIndex
    }
}

/** A boundary scan only; normal block/inline parsing happens on the shared parser stack. */
internal class DefinitionListScanner {
    private let lines: Array<LineRecord>
    private let rule: BlockSyntaxRule
    private let budget: OperationBudget
    private let cancellation: CancellationToken
    private let mapSpan: (Int64, Int64) -> SourceSpan
    private let termCandidate: (Int64) -> Bool
    private var listStart: Int64 = 0

    init(lines: Array<LineRecord>, rule: BlockSyntaxRule, budget: OperationBudget, cancellation: CancellationToken,
        mapSpan: (Int64, Int64) -> SourceSpan, termCandidate: (Int64) -> Bool) {
        this.lines = lines
        this.rule = rule
        this.budget = budget
        this.cancellation = cancellation
        this.mapSpan = mapSpan
        this.termCandidate = termCandidate
    }

    func scan(start: Int64): ?PendingDefinitionList {
        let firstMarker = findTermsEnd(start)
        if (firstMarker.isNone()) {
            return None
        }
        listStart = start
        var termStart = start
        var marker = firstMarker.getOrThrow()
        let entries = ArrayList<PendingDefinitionEntry>()
        var nextIndex = start
        while (true) {
            var termEnd = marker
            if (blankLine(lines[marker - 1].text)) {
                termEnd--
            }
            checkEnd(lines[marker].endWithNewline)
            for (index in termStart..termEnd) {
                let bytes = lines[index].text.size
                if (bytes > rule.maximumCaptureLength) {
                    throw LimitExceededException("extension_capture_bytes", rule.maximumCaptureLength, bytes,
                        "definition_list_parse", span: Some(mapSpan(lines[index].startByte, lines[index].endByte)),
                        extensionId: Some(rule.extensionId))
                }
            }
            let definitions = ArrayList<PendingDefinitionBody>()
            var cursor = marker
            var entryCandidate = marker
            while (true) {
                let (definition, next) = scanBody(cursor)
                definitions.add(definition)
                nextIndex = next
                entryCandidate = skipOneBlank(next)
                if (entryCandidate < lines.size && definitionListMarker(lines[entryCandidate].text).isSome()) {
                    cursor = entryCandidate
                    continue
                }
                break
            }
            let end = definitions[definitions.size - 1].span.endByte
            entries.add(
                PendingDefinitionEntry(lines[termStart..termEnd], definitions.toArray(),
                    SourceSpan(mapSpan(lines[termStart].startByte, lines[termStart].startByte).startByte, end)))
            let nextMarker = findTermsEnd(entryCandidate)
            if (nextMarker.isNone()) {
                break
            }
            termStart = entryCandidate
            marker = nextMarker.getOrThrow()
        }
        let first = entries[0].span.startByte
        let last = entries[entries.size - 1].span.endByte
        Some(PendingDefinitionList(rule, entries.toArray(), SourceSpan(first, last), nextIndex))
    }

    private func findTermsEnd(start: Int64): ?Int64 {
        var index = start
        while (index < lines.size) {
            step()
            let line = lines[index]
            if (definitionListMarker(line.text).isSome()) {
                return if (index > start) {
                    Some(index)
                } else {
                    None
                }
            }
            if (blankLine(line.text)) {
                if (index > start && index + 1 < lines.size && definitionListMarker(lines[index + 1].text).isSome()) {
                    return Some(index + 1)
                }
                return None
            }
            if (!termCandidate(index)) {
                return None
            }
            index++
        }
        None
    }

    private func scanBody(start: Int64): (PendingDefinitionBody, Int64) {
        step()
        let first = lines[start]
        let (marker, content) = definitionListMarker(first.text).getOrThrow()
        checkEnd(first.endWithNewline)
        let body = ArrayList<LineRecord>()
        body.add(definitionBodyLine(first, content))
        var index = start + 1
        var last = start
        while (index < lines.size) {
            step()
            if (blankLine(lines[index].text)) {
                var next = index
                while (next < lines.size && blankLine(lines[next].text)) {
                    step();
                    next++
                }
                if (next >= lines.size || definitionContinuationPrefix(lines[next].text).isNone()) {
                    break
                }
                checkEnd(lines[next].endWithNewline)
                for (blank in index..next) {
                    body.add(lines[blank])
                }
                index = next
            }
            let prefix = definitionContinuationPrefix(lines[index].text)
            if (prefix.isNone()) {
                break
            }
            checkEnd(lines[index].endWithNewline)
            body.add(definitionBodyLine(lines[index], prefix.getOrThrow()))
            last = index
            index++
        }
        (PendingDefinitionBody(body.toArray(), mapSpan(first.startByte + marker, lines[last].endByte),
                mapSpan(first.startByte + marker, first.startByte + marker + 1)), index)
    }

    private func checkEnd(end: Int64): Unit {
        let span = mapSpan(lines[listStart].startByte, end)
        let bytes = span.endByte - span.startByte
        if (bytes > rule.maximumBlockBytes) {
            throw LimitExceededException("extension_block_bytes", rule.maximumBlockBytes, bytes, "definition_list_parse",
                span: Some(span), extensionId: Some(rule.extensionId))
        }
    }

    private func skipOneBlank(index: Int64): Int64 {
        if (index < lines.size && blankLine(lines[index].text)) {
            if (index + 1 >= lines.size || !blankLine(lines[index + 1].text)) {
                return index + 1
            }
        }
        index
    }

    private func blankLine(text: String): Bool {
        var index: Int64 = 0
        while (index < text.size) {
            step()
            if (text[index] != b' ' && text[index] != b'\t') {
                return false
            }
            index++
        }
        true
    }

    private func step(): Unit {
        budget.consumeScan()
        cancellation.throwIfCancelled(phase: "definition_list_parse")
    }
}

internal func definitionListMarker(text: String): ?(Int64, Int64) {
    var marker: Int64 = 0
    while (marker < text.size && marker < 4 && text[marker] == b' ') {
        marker++
    }
    if (marker > 3 || marker >= text.size || text[marker] != b':') {
        return None
    }
    let after = marker + 1
    if (after == text.size) {
        return Some((marker, after))
    }
    if (text[after] != b' ' && text[after] != b'\t') {
        return None
    }
    Some((marker, after + 1))
}

private func definitionContinuationPrefix(text: String): ?Int64 {
    var bytes: Int64 = 0
    var columns: Int64 = 0
    while (bytes < text.size && columns < 2) {
        if (text[bytes] == b' ') {
            columns++
        } else if (text[bytes] == b'\t') {
            columns += 4 - columns % 4
        } else {
            return None
        }
        bytes++
    }
    if (columns >= 2) {
        Some(bytes)
    } else {
        None
    }
}

private func definitionBodyLine(line: LineRecord, prefix: Int64): LineRecord {
    LineRecord(line.text[prefix..], line.startByte + prefix, line.endByte, line.endWithNewline,
        allowSetext: line.allowSetext, hasCoreInlineSpecial: line.hasCoreInlineSpecial,
        hasCoreDelimiter: line.hasCoreDelimiter, hasTextLoweringCandidate: line.hasTextLoweringCandidate,
        hasReferenceOpener: line.hasReferenceOpener)
}

internal func definitionListPayload(node: NodeRef): ?DefinitionListPayload {
    if (let NodeKind.CustomBlock <- node.kind) {
        if (let value: DefinitionListPayload <- node.asCustomBlock().getOrThrow().payload) {
            return Some(value)
        }
    }
    None
}

internal func validateDefinitionListNode(document: Document, node: NodeRef, parents: ArrayList<NodeRef>,
    budget: OperationBudget, cancellation: CancellationToken): Unit {
    if (let NodeKind.CustomInline <- node.kind) {
        if (node.asCustomInline().getOrThrow().payload is DefinitionListPayload) {
            invalidDefinitionList(node, "definition list roles must be block nodes")
        }
        return
    }
    let payload = definitionListPayload(node)
    if (payload.isNone()) {
        return
    }
    let value = payload.getOrThrow()
    if (node.asCustomBlock().getOrThrow().localKindId != definitionListKind(value.role)) {
        invalidDefinitionList(node, "definition list role does not match its node kind")
    }
    let children = node.children()
    match (value.role) {
        case DefinitionListRole.List =>
            if (children.isEmpty()) {
                invalidDefinitionList(node, "definition list requires an entry")
            }
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                let child = definitionListPayload(children[index])
                if (child.isNone()) {
                    invalidDefinitionList(children[index], "definition list children must be entries")
                }
                if (let DefinitionListRole.Entry <- child.getOrThrow().role) {
                    ()
                } else {
                    invalidDefinitionList(children[index], "definition list children must be entries")
                }
            }
        case DefinitionListRole.Entry =>
            requireDefinitionParent(node, parents, DefinitionListRole.List)
            var terms: Int64 = 0
            var definitions: Int64 = 0
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                let child = definitionListPayload(children[index])
                if (child.isNone()) {
                    invalidDefinitionList(children[index], "entry children must be terms or definitions")
                }
                match (child.getOrThrow().role) {
                    case DefinitionListRole.Term =>
                        if (definitions > 0) {
                            invalidDefinitionList(children[index], "entry terms must precede definitions")
                        }
                        terms++
                    case DefinitionListRole.Definition => definitions++
                    case _ => invalidDefinitionList(children[index], "entry children must be terms or definitions")
                }
            }
            if (terms == 0 || definitions == 0) {
                invalidDefinitionList(node, "entry requires terms and definitions")
            }
        case DefinitionListRole.Term =>
            requireDefinitionParent(node, parents, DefinitionListRole.Entry)
            if (children.isEmpty()) {
                invalidDefinitionList(node, "term requires inline content")
            }
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                if (let NodeCategory.Inline <- children[index].category) {
                    ()
                } else {
                    invalidDefinitionList(children[index], "term children must be inline nodes")
                }
            }
        case DefinitionListRole.Definition =>
            requireDefinitionParent(node, parents, DefinitionListRole.Entry)
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                if (let NodeCategory.Block <- children[index].category) {
                    ()
                } else {
                    invalidDefinitionList(children[index], "definition children must be block nodes")
                }
            }
            match (value.markerSpan) {
                case Some(marker) =>
                    budget.consumeScan()
                    let span = node.span
                    if (marker.endByte - marker.startByte != 1 || span.isNone() ||
                        !span.getOrThrow().containsSpan(marker)) {
                        invalidDefinitionList(node, "definition marker must belong to its body span")
                    }
                    if (let Some(source) <- document.parserSourceBuffer()) {
                        if (marker.endByte > source.byteLength() || source.slice(marker) != ":") {
                            invalidDefinitionList(node, "definition marker does not match source")
                        }
                    } else {
                        invalidDefinitionList(node, "definition marker requires its original source")
                    }
                case None =>
                    if (node.span.isSome()) {
                        invalidDefinitionList(node, "source-backed definition requires a marker span")
                    }
            }
    }
}

private func requireDefinitionParent(node: NodeRef, parents: ArrayList<NodeRef>, expected: DefinitionListRole): Unit {
    if (parents.isEmpty()) {
        invalidDefinitionList(node, "definition role has no owner")
    }
    let parent = definitionListPayload(parents[parents.size - 1])
    if (parent.isNone()) {
        invalidDefinitionList(node, "definition role has an invalid owner")
    }
    let valid = match (expected) {
        case DefinitionListRole.List =>
            if (let DefinitionListRole.List <- parent.getOrThrow().role) {
                true
            } else {
                false
            }
        case DefinitionListRole.Entry =>
            if (let DefinitionListRole.Entry <- parent.getOrThrow().role) {
                true
            } else {
                false
            }
        case _ => false
    }
    if (!valid) {
        invalidDefinitionList(node, "definition role has an invalid owner")
    }
}

private func invalidDefinitionList(node: NodeRef, message: String): Nothing {
    throw MarkdownException(MarkdownErrorCode.ExtensionFailure, message, phase: "bind", span: node.span)
}

internal func requireDefinitionListBinding(node: NodeRef): Unit {
    if (!node.documentBindings.definitionListsValidated) {
        throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
            "definition list rendering requires a validated complete document", phase: "render", span: node.span)
    }
}
