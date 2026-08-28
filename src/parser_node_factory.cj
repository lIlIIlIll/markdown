package markdown

import std.collection.*

/** The only node-construction boundary used by the parser. It centralizes
 * limits, schema validation, origin handling and deterministic record order.
 */
internal class ParserNodeFactory {
    private let arena: AstArenaBuilder
    private let maximumAstNodes: Int64
    private let source: ?SourceBuffer
    private var hasOrphans = false

    init(maximumAstNodes: Int64, estimatedInputBytes!: Int64 = 0, source!: ?SourceBuffer = None) {
        this.maximumAstNodes = maximumAstNodes
        this.source = source
        let estimatedNodes = max(16, estimatedInputBytes / 16)
        arena = AstArenaBuilder(maximumNodes: maximumAstNodes, trustedParserConstruction: true,
            initialNodeCapacity: min(AST_NODE_CHUNK_SIZE, estimatedNodes),
            initialChildCapacity: min(AST_CHILD_CHUNK_SIZE, estimatedNodes), sourceBuffer: source)
    }

    func finishDocument(children: Array<Int64>, span: SourceSpan, profile: MarkdownProfile, dialectFingerprint: String,
        references: Array<ReferenceDefinition>): Document {
        let root = arena.appendParserOwned(NodeKind.DocumentNode, NodeCategory.Block, Some(span), NodeOriginKind.Parsed,
            children,
            payload: ArenaNodePayload.DocumentValue(profile, dialectFingerprint,
                ImmutableArray<ReferenceDefinition>(references)))
        if (!hasOrphans && arena.unparentedNodeCount() == 1) {
            return arena.freeze()
        }
        // Preserve one immutable arena snapshot and expose only the reachable
        // records. Speculative parser branches normally rollback before this
        // point; this sparse fallback avoids ever rebuilding the entire AST.
        arena.freeze(root)
    }

    func checkpoint(): AstArenaCheckpoint {
        arena.checkpoint()
    }

    func rollback(checkpoint: AstArenaCheckpoint): Unit {
        arena.rollback(checkpoint)
    }

    func blockQuote(children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.BlockQuote, NodeCategory.Block, children, span)
    }

    func list(listKind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool, children: Array<Int64>,
        span: SourceSpan): Int64 {
        if (start < 0) {
            throw IllegalArgumentException("list start must be non-negative")
        }
        parsed(NodeKind.List, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.ListValue(listKind, start, delimiter, tight))
    }

    func list(listKind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool, children: ArrayList<Int64>,
        span: SourceSpan): Int64 {
        if (start < 0) {
            throw IllegalArgumentException("list start must be non-negative")
        }
        parsedList(NodeKind.List, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.ListValue(listKind, start, delimiter, tight))
    }

    func listItem(children: Array<Int64>, span: SourceSpan, taskState!: TaskState = TaskState.NotTask,
        markerSpan!: ?SourceSpan = None): Int64 {
        parsed(NodeKind.ListItem, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.ListItemValue(taskState, markerSpan))
    }

    func paragraph(children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Paragraph, NodeCategory.Block, children, span)
    }

    func paragraph(children: ArrayList<Int64>, span: SourceSpan): Int64 {
        parsedList(NodeKind.Paragraph, NodeCategory.Block, children, span)
    }

    func heading(level: Int64, children: Array<Int64>, span: SourceSpan): Int64 {
        if (level < 1 || level > 6) {
            throw IllegalArgumentException("heading level must be 1 through 6")
        }
        parsed(NodeKind.Heading, NodeCategory.Block, children, span, payload: ArenaNodePayload.HeadingValue(level))
    }

    func thematicBreak(marker: Byte, span: SourceSpan): Int64 {
        parsed(NodeKind.ThematicBreak, NodeCategory.Block, [], span,
            payload: ArenaNodePayload.ThematicBreakValue(marker))
    }

    func codeBlock(codeKind: CodeBlockKind, literal: LiteralStorage, span: SourceSpan, fenceCharacter!: ?Byte = None,
        fenceLength!: Int64 = 0, openingFenceSpan!: ?SourceSpan = None, closingFenceSpan!: ?SourceSpan = None,
        infoRaw!: String = "", language!: String = "", attributesRaw!: String = ""): Int64 {
        parsed(NodeKind.CodeBlock, NodeCategory.Block, [], span,
            payload: ArenaNodePayload.CodeBlockValue(codeKind, literal, fenceCharacter, fenceLength, openingFenceSpan,
                closingFenceSpan, infoRaw, language, attributesRaw))
    }

    func htmlBlock(literal: LiteralStorage, blockType: Int64, span: SourceSpan): Int64 {
        parsed(NodeKind.HtmlBlock, NodeCategory.Block, [], span,
            payload: ArenaNodePayload.HtmlBlockValue(literal, blockType))
    }

    func table(alignments: Array<TableAlignment>, rows: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Table, NodeCategory.Block, rows, span,
            payload: ArenaNodePayload.TableValue(ImmutableArray<TableAlignment>(alignments)))
    }

    func table(alignments: Array<TableAlignment>, rows: ArrayList<Int64>, span: SourceSpan): Int64 {
        parsedList(NodeKind.Table, NodeCategory.Block, rows, span,
            payload: ArenaNodePayload.TableValue(ImmutableArray<TableAlignment>(alignments)))
    }

    func tableRow(header: Bool, cells: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.TableRow, NodeCategory.Block, cells, span, payload: ArenaNodePayload.TableRowValue(header))
    }

    func tableRow(header: Bool, cells: ArrayList<Int64>, span: SourceSpan): Int64 {
        parsedList(NodeKind.TableRow, NodeCategory.Block, cells, span, payload: ArenaNodePayload.TableRowValue(header))
    }

    func tableCell(alignment: TableAlignment, children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.TableCell, NodeCategory.Block, children, span,
            payload: ArenaNodePayload.TableCellValue(alignment))
    }

    func customBlock(extensionId: String, extensionSemanticVersion: String, localKindId: String, payload: CustomPayload,
        children: Array<Int64>, span: ?SourceSpan, origin: NodeOrigin): Int64 {
        arena.appendParserOwned(NodeKind.CustomBlock, NodeCategory.Block, span, origin.kind, children,
            payload: ArenaNodePayload.CustomValue(extensionId, extensionSemanticVersion, localKindId, payload),
            origin: Some(origin))
    }

    func text(raw: LiteralStorage, value: LiteralStorage, span: SourceSpan, normalized!: ?String = None,
        origin!: ?NodeOrigin = None): Int64 {
        match (origin) {
            case Some(valueOrigin) => arena.appendParserOwned(NodeKind.Text, NodeCategory.Inline, Some(span),
                valueOrigin.kind, [], payload: ArenaNodePayload.TextValue(raw, value, normalized),
                origin: Some(valueOrigin))
            case None => parsed(NodeKind.Text, NodeCategory.Inline, [], span,
                payload: ArenaNodePayload.TextValue(raw, value, normalized))
        }
    }

    /** Stores unchanged parser text as a source range. This avoids eagerly
     * copying the same bytes into both raw and semantic text payloads. */
    func sourceText(span: SourceSpan): Int64 {
        let sourceBuffer = source.getOrThrow()
        let _ = sourceBuffer
        parsed(NodeKind.Text, NodeCategory.Inline, [], span, payload: ArenaNodePayload.TextSourceValue)
    }

    func replaceSourceText(index: Int64, span: SourceSpan): Unit {
        let sourceBuffer = source.getOrThrow()
        let _ = sourceBuffer
        arena.replaceRecord(index, NodeKind.Text, NodeCategory.Inline, Some(span), NodeOriginKind.Parsed,
            payload: Some(ArenaNodePayload.TextSourceValue))
    }

    func sourceTextSpan(index: Int64): ?SourceSpan {
        match (arena.payloadAt(index)) {
            case ArenaNodePayload.TextSourceValue => arena.recordAt(index).span
            case _ => None
        }
    }

    func replaceText(index: Int64, raw: LiteralStorage, value: LiteralStorage, span: SourceSpan,
        normalized!: ?String = None, origin!: ?NodeOrigin = None): Unit {
        match (origin) {
            case Some(valueOrigin) => arena.replaceRecord(index, NodeKind.Text, NodeCategory.Inline, Some(span),
                valueOrigin.kind, payload: Some(ArenaNodePayload.TextValue(raw, value, normalized)),
                origin: Some(valueOrigin))
            case None => arena.replaceRecord(index, NodeKind.Text, NodeCategory.Inline, Some(span),
                NodeOriginKind.Parsed, payload: Some(ArenaNodePayload.TextValue(raw, value, normalized)))
        }
    }

    func textPayload(index: Int64): ?ArenaTextPayload {
        match (arena.payloadAt(index)) {
            case ArenaNodePayload.TextValue(raw, value, normalized) => Some(ArenaTextPayload(raw, value, normalized))
            case ArenaNodePayload.TextSourceValue =>
                let sourceBuffer = source.getOrThrow()
                let span = arena.recordAt(index).span.getOrThrow()
                let storage = LiteralStorage.Slice(sourceBuffer.sourceSlice(span))
                let normalized: ?String = None
                Some(ArenaTextPayload(storage, storage, normalized))
            case _ => None
        }
    }

    func span(index: Int64): ?SourceSpan {
        arena.recordAt(index).span
    }

    func abandon(index: Int64): Unit {
        let _ = arena.recordAt(index)
        hasOrphans = true
    }

    func abandonAll(indexes: Array<Int64>): Unit {
        if (!indexes.isEmpty()) {
            let _ = arena.recordAt(indexes[0])
            hasOrphans = true
        }
    }

    func softBreak(span: SourceSpan): Int64 {
        parsed(NodeKind.SoftBreak, NodeCategory.Inline, [], span)
    }

    func hardBreak(syntaxKind: HardBreakKind, span: SourceSpan): Int64 {
        parsed(NodeKind.HardBreak, NodeCategory.Inline, [], span, payload: ArenaNodePayload.HardBreakValue(syntaxKind))
    }

    func codeSpan(literal: String, delimiterRaw: String, span: SourceSpan): Int64 {
        parsed(NodeKind.CodeSpan, NodeCategory.Inline, [], span,
            payload: ArenaNodePayload.CodeSpanValue(literal, delimiterRaw))
    }

    func inlineContainer(kind: NodeKind, children: Array<Int64>, span: SourceSpan): Int64 {
        match (kind) {
            case NodeKind.Emphasis => parsed(kind, NodeCategory.Inline, children, span)
            case NodeKind.Strong => parsed(kind, NodeCategory.Inline, children, span)
            case NodeKind.Strikethrough => parsed(kind, NodeCategory.Inline, children, span)
            case _ => throw IllegalArgumentException("node kind is not an inline container")
        }
    }

    func link(destinationRaw: String, destination: String, titleRaw: String, title: String, syntaxKind: LinkSyntaxKind,
        children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Link, NodeCategory.Inline, children, span,
            payload: ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntaxKind))
    }

    func image(destinationRaw: String, destination: String, titleRaw: String, title: String, syntaxKind: LinkSyntaxKind,
        children: Array<Int64>, span: SourceSpan): Int64 {
        parsed(NodeKind.Image, NodeCategory.Inline, children, span,
            payload: ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntaxKind))
    }

    func htmlInline(literal: String, span: SourceSpan): Int64 {
        parsed(NodeKind.HtmlInline, NodeCategory.Inline, [], span, payload: ArenaNodePayload.HtmlInlineValue(literal))
    }

    func customInline(extensionId: String, extensionSemanticVersion: String, localKindId: String,
        payload: CustomPayload, children: Array<Int64>, span: ?SourceSpan, origin: NodeOrigin): Int64 {
        arena.appendParserOwned(NodeKind.CustomInline, NodeCategory.Inline, span, origin.kind, children,
            payload: ArenaNodePayload.CustomValue(extensionId, extensionSemanticVersion, localKindId, payload),
            origin: Some(origin))
    }

    func snapshotNode(index: Int64): NodeRef {
        let snapshot = arena.snapshotView()
        snapshot.nodeAt(index)
    }

    /** Read-only access used by the source-event lowering path while the
     * parser-owned subtree is still transient. No Document snapshot is
     * created, and the caller must finish before the next rollback. */
    func eventRecord(index: Int64): ArenaNodeRecord {
        arena.recordAt(index)
    }

    func eventPayload(index: Int64): ArenaNodePayload {
        arena.payloadAt(index)
    }

    func eventChildIndex(index: Int64): Int64 {
        arena.childIndexAt(index)
    }

    func eventSourceText(span: SourceSpan): String {
        source.getOrThrow().slice(span)
    }

    /** Inspect a completed parser-owned subtree without snapshot allocation. */
    func containsLink(index: Int64): Bool {
        let stack = ArrayList<Int64>()
        stack.add(index)
        while (!stack.isEmpty()) {
            let current = stack.remove(at: stack.size - 1)
            let record = arena.recordAt(current)
            match (record.kind) {
                case NodeKind.Link => return true
                case _ => ()
            }
            var childOffset: Int64 = 0
            while (childOffset < record.childCount) {
                stack.add(arena.childIndexAt(record.firstChild + childOffset))
                childOffset++
            }
        }
        false
    }

    private func parsed(kind: NodeKind, category: NodeCategory, children: Array<Int64>, span: SourceSpan,
        payload!: ArenaNodePayload = ArenaNodePayload.Empty): Int64 {
        arena.appendParserOwned(kind, category, Some(span), NodeOriginKind.Parsed, children, payload: payload)
    }

    private func parsedList(kind: NodeKind, category: NodeCategory, children: ArrayList<Int64>, span: SourceSpan,
        payload!: ArenaNodePayload = ArenaNodePayload.Empty): Int64 {
        arena.appendParserOwnedList(kind, category, Some(span), NodeOriginKind.Parsed, children, payload: payload)
    }
}

internal struct ArenaTextPayload {
    let rawStorage: LiteralStorage
    let valueStorage: LiteralStorage
    let normalized: ?String

    init(rawStorage: LiteralStorage, valueStorage: LiteralStorage, normalized: ?String) {
        this.rawStorage = rawStorage
        this.valueStorage = valueStorage
        this.normalized = normalized
    }
}
