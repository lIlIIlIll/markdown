package markdown

import std.collection.*
import std.sync.AtomicInt64

// The sizes are part of the 0.9 snapshot format and intentionally live next
// to the storage implementation instead of being parser tuning knobs.
internal let AST_NODE_CHUNK_SIZE: Int64 = 4096
internal let AST_CHILD_CHUNK_SIZE: Int64 = 16384
internal let AST_SOURCE_OFFSET_MAX: Int64 = 4294967294
private let NEXT_ARENA_DOCUMENT_ID = AtomicInt64(1)
private let ARENA_PAYLOAD_EMPTY: Int64 = -1
private let ARENA_PAYLOAD_TABLE_ROW_BODY: Int64 = -2
private let ARENA_PAYLOAD_TABLE_ROW_HEADER: Int64 = -3
private let ARENA_PAYLOAD_TABLE_CELL_NONE: Int64 = -4
private let ARENA_PAYLOAD_TABLE_CELL_LEFT: Int64 = -5
private let ARENA_PAYLOAD_TABLE_CELL_CENTER: Int64 = -6
private let ARENA_PAYLOAD_TABLE_CELL_RIGHT: Int64 = -7
private let ARENA_PAYLOAD_LIST_ITEM_PLAIN: Int64 = -8
private let ARENA_PAYLOAD_TEXT_SOURCE: Int64 = -9
private let ARENA_PAYLOAD_HEADING_1: Int64 = -10
private let ARENA_PAYLOAD_HEADING_2: Int64 = -11
private let ARENA_PAYLOAD_HEADING_3: Int64 = -12
private let ARENA_PAYLOAD_HEADING_4: Int64 = -13
private let ARENA_PAYLOAD_HEADING_5: Int64 = -14
private let ARENA_PAYLOAD_HEADING_6: Int64 = -15
private let ARENA_PAYLOAD_THEMATIC_DASH: Int64 = -16
private let ARENA_PAYLOAD_THEMATIC_STAR: Int64 = -17
private let ARENA_PAYLOAD_THEMATIC_UNDERSCORE: Int64 = -18
private let ARENA_PAYLOAD_HARD_BREAK_BACKSLASH: Int64 = -19
private let ARENA_PAYLOAD_HARD_BREAK_SPACES: Int64 = -20
private let ARENA_PAYLOAD_BULLET_LIST_LOOSE: Int64 = -21
private let ARENA_PAYLOAD_BULLET_LIST_TIGHT: Int64 = -22
private let ARENA_PAYLOAD_ORDERED_ZERO_PERIOD_LOOSE: Int64 = -23
private let ARENA_PAYLOAD_ORDERED_ZERO_PERIOD_TIGHT: Int64 = -24
private let ARENA_PAYLOAD_ORDERED_ZERO_PAREN_LOOSE: Int64 = -25
private let ARENA_PAYLOAD_ORDERED_ZERO_PAREN_TIGHT: Int64 = -26
private let ARENA_PAYLOAD_ORDERED_ONE_PERIOD_LOOSE: Int64 = -27
private let ARENA_PAYLOAD_ORDERED_ONE_PERIOD_TIGHT: Int64 = -28
private let ARENA_PAYLOAD_ORDERED_ONE_PAREN_LOOSE: Int64 = -29
private let ARENA_PAYLOAD_ORDERED_ONE_PAREN_TIGHT: Int64 = -30
private let ARENA_PAYLOAD_INLINE_MIN: Int64 = ARENA_PAYLOAD_ORDERED_ONE_PAREN_TIGHT
private let COMPACT_ARENA_INDEX_MAX: Int64 = 4294967295
private let COMPACT_ORIGIN_METADATA_MAX: Int64 = 16777214

private func compactArenaIndex(value: Int64, field: String): UInt32 {
    if (value < 0 || value > COMPACT_ARENA_INDEX_MAX) {
        throw IllegalArgumentException("arena ${field} exceeds compact index range")
    }
    UInt32(value)
}

private func compactSourceOffset(value: Int64, field: String): UInt32 {
    if (value < 0 || value > AST_SOURCE_OFFSET_MAX) {
        throw LimitExceededException("input_bytes", AST_SOURCE_OFFSET_MAX, value, field)
    }
    UInt32(value)
}

private func compactPayloadIndex(value: Int64): UInt32 {
    compactArenaIndex(value - ARENA_PAYLOAD_INLINE_MIN, "payload index")
}

private func nodeKindTag(kind: NodeKind): Int64 {
    match (kind) {
        case NodeKind.Document => 0
        case NodeKind.BlockQuote => 1
        case NodeKind.List => 2
        case NodeKind.ListItem => 3
        case NodeKind.Paragraph => 4
        case NodeKind.Heading => 5
        case NodeKind.ThematicBreak => 6
        case NodeKind.CodeBlock => 7
        case NodeKind.HtmlBlock => 8
        case NodeKind.Table => 9
        case NodeKind.TableRow => 10
        case NodeKind.TableCell => 11
        case NodeKind.CustomBlock => 12
        case NodeKind.Text => 13
        case NodeKind.SoftBreak => 14
        case NodeKind.HardBreak => 15
        case NodeKind.CodeSpan => 16
        case NodeKind.Emphasis => 17
        case NodeKind.Strong => 18
        case NodeKind.Strikethrough => 19
        case NodeKind.Link => 20
        case NodeKind.Image => 21
        case NodeKind.HtmlInline => 22
        case NodeKind.CustomInline => 23
    }
}

private func nodeKindFromTag(tag: Int64): NodeKind {
    match (tag) {
        case 0 => NodeKind.Document
        case 1 => NodeKind.BlockQuote
        case 2 => NodeKind.List
        case 3 => NodeKind.ListItem
        case 4 => NodeKind.Paragraph
        case 5 => NodeKind.Heading
        case 6 => NodeKind.ThematicBreak
        case 7 => NodeKind.CodeBlock
        case 8 => NodeKind.HtmlBlock
        case 9 => NodeKind.Table
        case 10 => NodeKind.TableRow
        case 11 => NodeKind.TableCell
        case 12 => NodeKind.CustomBlock
        case 13 => NodeKind.Text
        case 14 => NodeKind.SoftBreak
        case 15 => NodeKind.HardBreak
        case 16 => NodeKind.CodeSpan
        case 17 => NodeKind.Emphasis
        case 18 => NodeKind.Strong
        case 19 => NodeKind.Strikethrough
        case 20 => NodeKind.Link
        case 21 => NodeKind.Image
        case 22 => NodeKind.HtmlInline
        case 23 => NodeKind.CustomInline
        case _ => throw IllegalStateException("unknown arena node kind tag")
    }
}

private func originKindTag(kind: NodeOriginKind): Int64 {
    match (kind) {
        case NodeOriginKind.Parsed => 0
        case NodeOriginKind.ExtensionGenerated => 1
        case NodeOriginKind.Transformed => 2
        case NodeOriginKind.Synthetic => 3
        case NodeOriginKind.Deserialized => 4
    }
}

private func originKindFromTag(tag: Int64): NodeOriginKind {
    match (tag) {
        case 0 => NodeOriginKind.Parsed
        case 1 => NodeOriginKind.ExtensionGenerated
        case 2 => NodeOriginKind.Transformed
        case 3 => NodeOriginKind.Synthetic
        case 4 => NodeOriginKind.Deserialized
        case _ => throw IllegalStateException("unknown arena origin kind tag")
    }
}

private func compactNodeIdentity(kind: NodeKind, originKind: NodeOriginKind, originMetadataIndex: Int64): UInt32 {
    let metadataTag = if (let NodeOriginKind.Parsed <- originKind) {
        0
    } else {
        if (originMetadataIndex < 0 || originMetadataIndex > COMPACT_ORIGIN_METADATA_MAX) {
            throw LimitExceededException("ast_nodes", COMPACT_ORIGIN_METADATA_MAX + 1, originMetadataIndex + 1,
                "origin_metadata")
        }
        originMetadataIndex + 1
    }
    UInt32((metadataTag << 8) | (originKindTag(originKind) << 5) | nodeKindTag(kind))
}

/** Compact semantic header stored in the node arena. Kind-specific payloads
 * are stored separately so traversing the tree does not trace payload objects.
 */
public struct ArenaNodeRecord {
    private let identityDescriptorValue: UInt32
    private let spanStartByteValue: UInt32
    private let spanEndByteValue: UInt32
    private let firstChildValue: UInt32
    private let childCountValue: UInt32
    private let payloadIndexValue: UInt32

    internal init(kind: NodeKind, span: ?SourceSpan, originKind: NodeOriginKind, originMetadataIndex: Int64,
        firstChild: Int64, childCount: Int64, payloadIndex: Int64) {
        identityDescriptorValue = compactNodeIdentity(kind, originKind, originMetadataIndex)
        match (span) {
            case Some(value) =>
                spanStartByteValue = compactSourceOffset(value.startByte, "ast_span_start")
                spanEndByteValue = compactSourceOffset(value.endByte, "ast_span_end")
            case None =>
                spanStartByteValue = UInt32.Max
                spanEndByteValue = UInt32.Max
        }
        firstChildValue = compactArenaIndex(firstChild, "first child")
        childCountValue = compactArenaIndex(childCount, "child count")
        payloadIndexValue = compactPayloadIndex(payloadIndex)
    }

    public prop firstChild: Int64 {
        get() {
            Int64(firstChildValue)
        }
    }

    public prop kind: NodeKind {
        get() {
            nodeKindFromTag(Int64(identityDescriptorValue & 0x1Fu32))
        }
    }

    public prop childCount: Int64 {
        get() {
            Int64(childCountValue)
        }
    }

    public prop payloadIndex: Int64 {
        get() {
            Int64(payloadIndexValue) + ARENA_PAYLOAD_INLINE_MIN
        }
    }

    public prop span: ?SourceSpan {
        get() {
            if (spanStartByteValue == UInt32.Max) {
                None
            } else {
                Some(SourceSpan(Int64(spanStartByteValue), Int64(spanEndByteValue)))
            }
        }
    }

    public prop category: NodeCategory {
        get() {
            match (kind) {
                case NodeKind.Document | NodeKind.BlockQuote | NodeKind.List | NodeKind.ListItem | NodeKind.Paragraph
                    | NodeKind.Heading | NodeKind.ThematicBreak | NodeKind.CodeBlock | NodeKind.HtmlBlock
                    | NodeKind.Table | NodeKind.TableRow | NodeKind.TableCell | NodeKind.CustomBlock => NodeCategory
                    .Block
                case _ => NodeCategory.Inline
            }
        }
    }

    public prop originKind: NodeOriginKind {
        get() {
            originKindFromTag(Int64((identityDescriptorValue >> 5) & 0x7u32))
        }
    }

    public prop originMetadataIndex: Int64 {
        get() {
            if (let NodeOriginKind.Parsed <- originKind) {
                -1
            } else {
                Int64(identityDescriptorValue >> 8) - 1
            }
        }
    }
}

internal enum ArenaNodePayload {
    | Empty
    | DocumentValue(MarkdownProfile, String, ImmutableArray<ReferenceDefinition>)
    | HeadingValue(Int64)
    | TextValue(LiteralStorage, LiteralStorage, ?String)
    | TextSourceValue
    | ListValue(ListKind, Int64, ListDelimiter, Bool)
    | ListItemValue(TaskState, ?SourceSpan)
    | ThematicBreakValue(Byte)
    | CodeBlockValue(CodeBlockKind, LiteralStorage, ?Byte, Int64, ?SourceSpan, ?SourceSpan, String, String, String)
    | HtmlBlockValue(LiteralStorage, Int64)
    | LinkValue(String, String, String, String, LinkSyntaxKind)
    | TableValue(ImmutableArray<TableAlignment>)
    | TableRowValue(Bool)
    | TableCellValue(TableAlignment)
    | HardBreakValue(HardBreakKind)
    | CodeSpanValue(String, String)
    | HtmlInlineValue(String)
    | CustomValue(String, String, String, CustomPayload)
}

private func inlineArenaPayload(encoded: Int64): ArenaNodePayload {
    let noMarkerSpan: ?SourceSpan = None
    match (encoded) {
        case -1 => ArenaNodePayload.Empty
        case -2 => ArenaNodePayload.TableRowValue(false)
        case -3 => ArenaNodePayload.TableRowValue(true)
        case -4 => ArenaNodePayload.TableCellValue(TableAlignment.None)
        case -5 => ArenaNodePayload.TableCellValue(TableAlignment.Left)
        case -6 => ArenaNodePayload.TableCellValue(TableAlignment.Center)
        case -7 => ArenaNodePayload.TableCellValue(TableAlignment.Right)
        case -8 => ArenaNodePayload.ListItemValue(TaskState.NotTask, noMarkerSpan)
        case -9 => ArenaNodePayload.TextSourceValue
        case -10 => ArenaNodePayload.HeadingValue(1)
        case -11 => ArenaNodePayload.HeadingValue(2)
        case -12 => ArenaNodePayload.HeadingValue(3)
        case -13 => ArenaNodePayload.HeadingValue(4)
        case -14 => ArenaNodePayload.HeadingValue(5)
        case -15 => ArenaNodePayload.HeadingValue(6)
        case -16 => ArenaNodePayload.ThematicBreakValue(b'-')
        case -17 => ArenaNodePayload.ThematicBreakValue(b'*')
        case -18 => ArenaNodePayload.ThematicBreakValue(b'_')
        case -19 => ArenaNodePayload.HardBreakValue(HardBreakKind.Backslash)
        case -20 => ArenaNodePayload.HardBreakValue(HardBreakKind.Spaces)
        case -21 => ArenaNodePayload.ListValue(ListKind.Bullet, 0, ListDelimiter.None, false)
        case -22 => ArenaNodePayload.ListValue(ListKind.Bullet, 0, ListDelimiter.None, true)
        case -23 => ArenaNodePayload.ListValue(ListKind.Ordered, 0, ListDelimiter.Period, false)
        case -24 => ArenaNodePayload.ListValue(ListKind.Ordered, 0, ListDelimiter.Period, true)
        case -25 => ArenaNodePayload.ListValue(ListKind.Ordered, 0, ListDelimiter.Parenthesis, false)
        case -26 => ArenaNodePayload.ListValue(ListKind.Ordered, 0, ListDelimiter.Parenthesis, true)
        case -27 => ArenaNodePayload.ListValue(ListKind.Ordered, 1, ListDelimiter.Period, false)
        case -28 => ArenaNodePayload.ListValue(ListKind.Ordered, 1, ListDelimiter.Period, true)
        case -29 => ArenaNodePayload.ListValue(ListKind.Ordered, 1, ListDelimiter.Parenthesis, false)
        case -30 => ArenaNodePayload.ListValue(ListKind.Ordered, 1, ListDelimiter.Parenthesis, true)
        case _ => throw IllegalStateException("unknown inline arena payload encoding")
    }
}

internal class ArenaNodeChunk {
    let records: Array<ArenaNodeRecord>

    init(records: Array<ArenaNodeRecord>) {
        if (records.size > AST_NODE_CHUNK_SIZE) {
            throw IllegalArgumentException("node arena chunk exceeds 4096 records")
        }
        this.records = records
    }
}

internal class ArenaChildChunk {
    let nodeIndexes: Array<UInt32>

    init(nodeIndexes: Array<UInt32>) {
        if (nodeIndexes.size > AST_CHILD_CHUNK_SIZE) {
            throw IllegalArgumentException("child arena chunk exceeds 16384 entries")
        }
        this.nodeIndexes = nodeIndexes
    }
}

/** Opaque parser-construction checkpoint. A rollback discards every node,
 * child edge and side payload appended after this value. */
internal struct AstArenaCheckpoint {
    let nodeCount: Int64
    let childCount: Int64
    let payloadCount: Int64
    let originMetadataCount: Int64
    let unparentedCount: Int64

    init(nodeCount: Int64, childCount: Int64, payloadCount: Int64, originMetadataCount: Int64, unparentedCount: Int64) {
        this.nodeCount = nodeCount
        this.childCount = childCount
        this.payloadCount = payloadCount
        this.originMetadataCount = originMetadataCount
        this.unparentedCount = unparentedCount
    }
}

/** Immutable owner of node and child chunks. NodeRef values are valid only
 * while this snapshot remains reachable and are rejected by other snapshots.
 */
public class Document {
    private let documentIdentity: Int64
    private let nodeChunks: Array<ArenaNodeChunk>
    private let childChunks: Array<ArenaChildChunk>
    private let payloads: Array<ArenaNodePayload>
    private let originMetadata: Array<NodeOrigin>
    private let sourceBuffer: ?SourceBuffer
    private let physicalNodeCount: Int64
    private let physicalChildCount: Int64
    private let rootRecordIndex: Int64
    private let logicalNodeIndexes: Array<Int64>
    public let nodeCount: Int64
    public let childCount: Int64

    internal init(documentIdentity: Int64, nodeChunks: Array<ArenaNodeChunk>, childChunks: Array<ArenaChildChunk>,
        payloads: Array<ArenaNodePayload>, originMetadata: Array<NodeOrigin>, physicalNodeCount: Int64,
        physicalChildCount: Int64, rootIndex!: Int64 = -1, reachableNodeIndexes!: Array<Int64> = [],
        reachableChildCount!: Int64 = -1, sourceBuffer!: ?SourceBuffer = None) {
        this.documentIdentity = documentIdentity
        this.nodeChunks = nodeChunks
        this.childChunks = childChunks
        this.payloads = payloads
        this.originMetadata = originMetadata
        this.sourceBuffer = sourceBuffer
        this.physicalNodeCount = physicalNodeCount
        this.physicalChildCount = physicalChildCount
        rootRecordIndex = if (rootIndex < 0) {
            physicalNodeCount - 1
        } else {
            rootIndex
        }
        logicalNodeIndexes = reachableNodeIndexes
        nodeCount = if (reachableNodeIndexes.isEmpty()) {
            physicalNodeCount
        } else {
            reachableNodeIndexes.size
        }
        childCount = if (reachableChildCount < 0) {
            physicalChildCount
        } else {
            reachableChildCount
        }
    }

    public func nodeAt(index: Int64): NodeRef {
        if (index < 0 || index >= nodeCount) {
            throw IndexOutOfBoundsException("node arena index is outside the snapshot")
        }
        let physicalIndex = if (logicalNodeIndexes.isEmpty()) {
            index
        } else {
            logicalNodeIndexes[index]
        }
        nodeRefAtPhysical(physicalIndex)
    }

    public func root(): NodeRef {
        if (nodeCount == 0 || rootRecordIndex < 0) {
            throw IllegalStateException("AST arena has no root node")
        }
        nodeRefAtPhysical(rootRecordIndex)
    }

    /** Convenience accessors for the arena root. They preserve the snapshot
     * ownership model while keeping common document-level reads concise. */
    public prop nodeId: NodeId {
        get() {
            root().nodeId
        }
    }
    public prop span: ?SourceSpan {
        get() {
            root().span
        }
    }
    public prop profile: MarkdownProfile {
        get() {
            root().asDocument().getOrThrow().profile
        }
    }
    public prop dialectFingerprint: String {
        get() {
            root().asDocument().getOrThrow().dialectFingerprint
        }
    }
    public prop references: ImmutableArray<ReferenceDefinition> {
        get() {
            root().asDocument().getOrThrow().references
        }
    }
    public func children(): NodeChildren {
        root().children()
    }

    public func children(node: NodeRef): NodeChildren {
        requireOwned(node)
        let record = recordAt(node.index)
        NodeChildren(this, record.firstChild, record.childCount)
    }

    internal func recordAt(index: Int64): ArenaNodeRecord {
        requirePhysicalNodeIndex(index)
        nodeChunks[index / AST_NODE_CHUNK_SIZE].records[index % AST_NODE_CHUNK_SIZE]
    }

    internal func requireOwned(node: NodeRef): Unit {
        if (node.documentIdentity != documentIdentity) {
            throw IllegalArgumentException("NodeRef belongs to a different Document snapshot")
        }
        requirePhysicalNodeIndex(node.index)
    }

    internal func nodeChunkArray(): Array<ArenaNodeChunk> {
        nodeChunks.clone()
    }

    internal func childChunkArray(): Array<ArenaChildChunk> {
        childChunks.clone()
    }

    internal func payloadArray(): Array<ArenaNodePayload> {
        payloads.clone()
    }

    internal func originMetadataArray(): Array<NodeOrigin> {
        originMetadata.clone()
    }

    internal func parserSourceBuffer(): ?SourceBuffer {
        sourceBuffer
    }

    internal func sourceTextStorage(index: Int64): LiteralStorage {
        let source = sourceBuffer.getOrThrow()
        let span = recordAt(index).span.getOrThrow()
        LiteralStorage.Slice(source.sourceSlice(span))
    }

    internal func originAt(index: Int64): NodeOrigin {
        let record = recordAt(index)
        if (let NodeOriginKind.Parsed <- record.originKind) {
            return match (record.span) {
                case Some(value) => NodeOrigin.parsed(value)
                case None => NodeOrigin(NodeOriginKind.Parsed)
            }
        }
        if (record.originMetadataIndex < 0 || record.originMetadataIndex >= originMetadata.size) {
            throw IllegalStateException("non-parsed arena node is missing origin metadata")
        }
        originMetadata[record.originMetadataIndex]
    }

    internal func payloadAt(index: Int64): ArenaNodePayload {
        let record = recordAt(index)
        if (record.payloadIndex < 0) {
            return inlineArenaPayload(record.payloadIndex)
        }
        if (record.payloadIndex >= payloads.size) {
            throw IllegalStateException("arena node payload index is outside the snapshot")
        }
        payloads[record.payloadIndex]
    }

    internal prop identity: Int64 {
        get() {
            documentIdentity
        }
    }

    internal prop storedNodeCount: Int64 {
        get() {
            physicalNodeCount
        }
    }

    internal prop storedChildCount: Int64 {
        get() {
            physicalChildCount
        }
    }

    internal prop rootIndex: Int64 {
        get() {
            rootRecordIndex
        }
    }

    internal func nodeRefAtPhysical(index: Int64): NodeRef {
        requirePhysicalNodeIndex(index)
        NodeRef(this, documentIdentity, index)
    }

    private func requirePhysicalNodeIndex(index: Int64): Unit {
        if (index < 0 || index >= physicalNodeCount) {
            throw IndexOutOfBoundsException("node arena index is outside the snapshot")
        }
    }

    internal func childIndexAt(index: Int64): Int64 {
        if (index < 0 || index >= physicalChildCount) {
            throw IndexOutOfBoundsException("child arena index is outside the snapshot")
        }
        Int64(childChunks[index / AST_CHILD_CHUNK_SIZE].nodeIndexes[index % AST_CHILD_CHUNK_SIZE])
    }
}

/** Lightweight identity and typed-view anchor. It deliberately contains no
 * child array or origin object.
 */
public struct NodeRef <: Equatable<NodeRef> {
    private let snapshot: Document
    internal let documentIdentity: Int64
    internal let index: Int64

    internal init(snapshot: Document, documentIdentity: Int64, index: Int64) {
        this.snapshot = snapshot
        this.documentIdentity = documentIdentity
        this.index = index
    }

    public prop nodeId: NodeId {
        get() {
            NodeId(index + 1)
        }
    }
    public prop kind: NodeKind {
        get() {
            snapshot.recordAt(index).kind
        }
    }
    public prop category: NodeCategory {
        get() {
            snapshot.recordAt(index).category
        }
    }
    public prop span: ?SourceSpan {
        get() {
            snapshot.recordAt(index).span
        }
    }
    public prop originKind: NodeOriginKind {
        get() {
            snapshot.recordAt(index).originKind
        }
    }
    public prop origin: NodeOrigin {
        get() {
            snapshot.originAt(index)
        }
    }

    public func children(): NodeChildren {
        snapshot.children(this)
    }

    internal func snapshotPayload(): ArenaNodePayload {
        snapshot.payloadAt(index)
    }

    public func asHeading(): ?HeadingNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HeadingValue(level) => Some(HeadingNodeView(this, level))
            case _ => None
        }
    }

    public func asDocument(): ?DocumentNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.DocumentValue(profile, dialectFingerprint, references) => Some(
                DocumentNodeView(this, profile, dialectFingerprint, references))
            case _ => None
        }
    }

    public func asText(): ?TextNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TextValue(raw, value, normalized) => Some(TextNodeView(this, raw, value, normalized))
            case ArenaNodePayload.TextSourceValue =>
                let storage = snapshot.sourceTextStorage(index)
                let normalized: ?String = None
                Some(TextNodeView(this, storage, storage, normalized))
            case _ => None
        }
    }

    public func asList(): ?ListNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.ListValue(kind, start, delimiter, tight) => Some(
                ListNodeView(this, kind, start, delimiter, tight))
            case _ => None
        }
    }

    public func asListItem(): ?ListItemNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.ListItemValue(taskState, markerSpan) => Some(
                ListItemNodeView(this, taskState, markerSpan))
            case _ => None
        }
    }

    public func asThematicBreak(): ?ThematicBreakNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.ThematicBreakValue(marker) => Some(ThematicBreakNodeView(this, marker))
            case _ => None
        }
    }

    public func asCodeBlock(): ?CodeBlockNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.CodeBlockValue(kind, literal, fenceCharacter, fenceLength, openingFenceSpan, closingFenceSpan, infoRaw, language, attributesRaw) => Some(
                CodeBlockNodeView(this, kind, literal, fenceCharacter, fenceLength, openingFenceSpan, closingFenceSpan,
                    infoRaw, language, attributesRaw))
            case _ => None
        }
    }

    public func asHtmlBlock(): ?HtmlBlockNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HtmlBlockValue(literal, blockType) => Some(HtmlBlockNodeView(this, literal, blockType))
            case _ => None
        }
    }

    public func asLink(): ?LinkNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntaxKind) =>
                if (let NodeKind.Link <- kind) {
                    Some(LinkNodeView(this, destinationRaw, destination, titleRaw, title, syntaxKind))
                } else {
                    None
                }
            case _ => None
        }
    }

    public func asImage(): ?ImageNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntaxKind) =>
                if (let NodeKind.Image <- kind) {
                    Some(ImageNodeView(this, destinationRaw, destination, titleRaw, title, syntaxKind))
                } else {
                    None
                }
            case _ => None
        }
    }

    public func asTable(): ?TableNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TableValue(alignments) => Some(TableNodeView(this, alignments))
            case _ => None
        }
    }

    public func asTableRow(): ?TableRowNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TableRowValue(header) => Some(TableRowNodeView(this, header))
            case _ => None
        }
    }

    public func asTableCell(): ?TableCellNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TableCellValue(alignment) => Some(TableCellNodeView(this, alignment))
            case _ => None
        }
    }

    public func asHardBreak(): ?HardBreakNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HardBreakValue(syntaxKind) => Some(HardBreakNodeView(this, syntaxKind))
            case _ => None
        }
    }

    public func asCodeSpan(): ?CodeSpanNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.CodeSpanValue(literal, delimiterRaw) => Some(
                CodeSpanNodeView(this, literal, delimiterRaw))
            case _ => None
        }
    }

    public func asHtmlInline(): ?HtmlInlineNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HtmlInlineValue(literal) => Some(HtmlInlineNodeView(this, literal))
            case _ => None
        }
    }

    public func asCustomBlock(): ?CustomNodeView {
        if (let NodeKind.CustomBlock <- kind) {
            customView()
        } else {
            None
        }
    }

    public func asCustomInline(): ?CustomNodeView {
        if (let NodeKind.CustomInline <- kind) {
            customView()
        } else {
            None
        }
    }

    public operator func ==(other: NodeRef): Bool {
        documentIdentity == other.documentIdentity && index == other.index
    }

    private func customView(): ?CustomNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.CustomValue(extensionId, extensionSemanticVersion, localKindId, payload) => Some(
                CustomNodeView(this, extensionId, extensionSemanticVersion, localKindId, payload))
            case _ => None
        }
    }
}

/** Zero-copy view over one node's contiguous child-index range. */
public struct NodeChildren {
    private let snapshot: Document
    private let firstChild: Int64
    public let size: Int64

    internal init(snapshot: Document, firstChild: Int64, size: Int64) {
        this.snapshot = snapshot
        this.firstChild = firstChild
        this.size = size
    }

    public func isEmpty(): Bool {
        size == 0
    }

    public operator func [](index: Int64): NodeRef {
        if (index < 0 || index >= size) {
            throw IndexOutOfBoundsException("child index is outside the node range")
        }
        snapshot.nodeRefAtPhysical(snapshot.childIndexAt(firstChild + index))
    }

    public func toArray(): Array<NodeRef> {
        let values = ArrayList<NodeRef>()
        var index: Int64 = 0
        while (index < size) {
            values.add(this[index])
            index++
        }
        values.toArray()
    }
}

public struct DocumentNodeView {
    public let node: NodeRef
    public let profile: MarkdownProfile
    public let dialectFingerprint: String
    public let references: ImmutableArray<ReferenceDefinition>
    internal init(node: NodeRef, profile: MarkdownProfile, dialectFingerprint: String,
        references: ImmutableArray<ReferenceDefinition>) {
        this.node = node
        this.profile = profile
        this.dialectFingerprint = dialectFingerprint
        this.references = references
    }
}

public struct HeadingNodeView {
    public let node: NodeRef
    public let level: Int64
    internal init(node: NodeRef, level: Int64) {
        this.node = node
        this.level = level
    }
}

public struct TextNodeView {
    public let node: NodeRef
    private let rawStorage: LiteralStorage
    private let valueStorage: LiteralStorage
    public let normalized: ?String
    internal init(node: NodeRef, raw: LiteralStorage, value: LiteralStorage, normalized: ?String) {
        this.node = node
        rawStorage = raw
        valueStorage = value
        this.normalized = normalized
    }
    public prop raw: String {
        get() {
            rawStorage.text()
        }
    }
    public prop value: String {
        get() {
            valueStorage.text()
        }
    }
    internal func rawLiteralStorage(): LiteralStorage {
        rawStorage
    }
    internal func valueLiteralStorage(): LiteralStorage {
        valueStorage
    }
}

public struct ListNodeView {
    public let node: NodeRef
    public let listKind: ListKind
    public let start: Int64
    public let delimiter: ListDelimiter
    public let tight: Bool
    internal init(node: NodeRef, listKind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool) {
        this.node = node
        this.listKind = listKind
        this.start = start
        this.delimiter = delimiter
        this.tight = tight
    }
}

public struct ListItemNodeView {
    public let node: NodeRef
    public let taskState: TaskState
    public let markerSpan: ?SourceSpan
    internal init(node: NodeRef, taskState: TaskState, markerSpan: ?SourceSpan) {
        this.node = node
        this.taskState = taskState
        this.markerSpan = markerSpan
    }
}

public struct ThematicBreakNodeView {
    public let node: NodeRef
    public let marker: Byte
    internal init(node: NodeRef, marker: Byte) {
        this.node = node
        this.marker = marker
    }
}

public struct CodeBlockNodeView {
    public let node: NodeRef
    public let codeKind: CodeBlockKind
    private let literalStorage: LiteralStorage
    public let fenceCharacter: ?Byte
    public let fenceLength: Int64
    public let openingFenceSpan: ?SourceSpan
    public let closingFenceSpan: ?SourceSpan
    public let infoRaw: String
    public let language: String
    public let attributesRaw: String
    internal init(node: NodeRef, codeKind: CodeBlockKind, literalStorage: LiteralStorage, fenceCharacter: ?Byte,
        fenceLength: Int64, openingFenceSpan: ?SourceSpan, closingFenceSpan: ?SourceSpan, infoRaw: String,
        language: String, attributesRaw: String) {
        this.node = node
        this.codeKind = codeKind
        this.literalStorage = literalStorage
        this.fenceCharacter = fenceCharacter
        this.fenceLength = fenceLength
        this.openingFenceSpan = openingFenceSpan
        this.closingFenceSpan = closingFenceSpan
        this.infoRaw = infoRaw
        this.language = language
        this.attributesRaw = attributesRaw
    }
    public prop literal: String {
        get() {
            literalStorage.text()
        }
    }
    internal func storedLiteral(): LiteralStorage {
        literalStorage
    }
}

public struct HtmlBlockNodeView {
    public let node: NodeRef
    private let literalStorage: LiteralStorage
    public let blockType: Int64
    internal init(node: NodeRef, literalStorage: LiteralStorage, blockType: Int64) {
        this.node = node
        this.literalStorage = literalStorage
        this.blockType = blockType
    }
    public prop literal: String {
        get() {
            literalStorage.text()
        }
    }
    internal func storedLiteral(): LiteralStorage {
        literalStorage
    }
}

public struct LinkNodeView {
    public let node: NodeRef
    public let destinationRaw: String
    public let destination: String
    public let titleRaw: String
    public let title: String
    public let syntaxKind: LinkSyntaxKind
    internal init(node: NodeRef, destinationRaw: String, destination: String, titleRaw: String, title: String,
        syntaxKind: LinkSyntaxKind) {
        this.node = node
        this.destinationRaw = destinationRaw
        this.destination = destination
        this.titleRaw = titleRaw
        this.title = title
        this.syntaxKind = syntaxKind
    }
}

public struct ImageNodeView {
    public let node: NodeRef
    public let destinationRaw: String
    public let destination: String
    public let titleRaw: String
    public let title: String
    public let syntaxKind: LinkSyntaxKind
    internal init(node: NodeRef, destinationRaw: String, destination: String, titleRaw: String, title: String,
        syntaxKind: LinkSyntaxKind) {
        this.node = node
        this.destinationRaw = destinationRaw
        this.destination = destination
        this.titleRaw = titleRaw
        this.title = title
        this.syntaxKind = syntaxKind
    }
}

public struct TableNodeView {
    public let node: NodeRef
    public let alignments: ImmutableArray<TableAlignment>
    internal init(node: NodeRef, alignments: ImmutableArray<TableAlignment>) {
        this.node = node
        this.alignments = alignments
    }
}

public struct TableRowNodeView {
    public let node: NodeRef
    public let header: Bool
    internal init(node: NodeRef, header: Bool) {
        this.node = node
        this.header = header
    }
}

public struct TableCellNodeView {
    public let node: NodeRef
    public let alignment: TableAlignment
    internal init(node: NodeRef, alignment: TableAlignment) {
        this.node = node
        this.alignment = alignment
    }
}

public struct HardBreakNodeView {
    public let node: NodeRef
    public let syntaxKind: HardBreakKind
    internal init(node: NodeRef, syntaxKind: HardBreakKind) {
        this.node = node
        this.syntaxKind = syntaxKind
    }
}

public struct CodeSpanNodeView {
    public let node: NodeRef
    public let literal: String
    public let delimiterRaw: String
    internal init(node: NodeRef, literal: String, delimiterRaw: String) {
        this.node = node
        this.literal = literal
        this.delimiterRaw = delimiterRaw
    }
}

public struct HtmlInlineNodeView {
    public let node: NodeRef
    public let literal: String
    internal init(node: NodeRef, literal: String) {
        this.node = node
        this.literal = literal
    }
}

public struct CustomNodeView {
    public let node: NodeRef
    public let extensionId: String
    public let extensionSemanticVersion: String
    public let localKindId: String
    public let payload: CustomPayload
    internal init(node: NodeRef, extensionId: String, extensionSemanticVersion: String, localKindId: String,
        payload: CustomPayload) {
        this.node = node
        this.extensionId = extensionId
        this.extensionSemanticVersion = extensionSemanticVersion
        this.localKindId = localKindId
        this.payload = payload
    }
}

/** Session-confined builder. Fresh chunks are mutable until freeze; a builder
 * forked from a snapshot shares every untouched chunk and clones only the
 * chunk modified by replaceRecord().
 */
internal class AstArenaBuilder {
    private let documentIdentity: Int64
    private let maximumNodes: Int64
    private let trustedParserConstruction: Bool
    private let sourceBuffer: ?SourceBuffer
    private let frozenNodeChunks: ArrayList<ArenaNodeChunk>
    private let frozenChildChunks: ArrayList<ArenaChildChunk>
    private let nodeTailCapacity: Int64
    private let childTailCapacity: Int64
    private var nodeTail: ArrayList<ArenaNodeRecord>
    private var childTail: ArrayList<UInt32>
    private let payloads: ArrayList<ArenaNodePayload>
    private let originMetadata: ArrayList<NodeOrigin>
    private let parentIndexes: ArrayList<Int64>
    private var nodeCountValue: Int64
    private var childCountValue: Int64
    private var unparentedCountValue: Int64

    init(maximumNodes!: Int64 = Int64.Max, trustedParserConstruction!: Bool = false, initialNodeCapacity!: Int64 = 16,
        initialChildCapacity!: Int64 = 16, sourceBuffer!: ?SourceBuffer = None) {
        if (maximumNodes <= 0) {
            throw IllegalArgumentException("maximum AST nodes must be positive")
        }
        if (initialNodeCapacity < 0 || initialNodeCapacity > AST_NODE_CHUNK_SIZE || initialChildCapacity < 0 ||
            initialChildCapacity > AST_CHILD_CHUNK_SIZE) {
            throw IllegalArgumentException("initial arena capacity exceeds its chunk size")
        }
        documentIdentity = NEXT_ARENA_DOCUMENT_ID.fetchAdd(1)
        this.maximumNodes = maximumNodes
        this.trustedParserConstruction = trustedParserConstruction
        this.sourceBuffer = sourceBuffer
        nodeTailCapacity = initialNodeCapacity
        childTailCapacity = initialChildCapacity
        frozenNodeChunks = ArrayList<ArenaNodeChunk>()
        frozenChildChunks = ArrayList<ArenaChildChunk>()
        nodeTail = ArrayList<ArenaNodeRecord>(nodeTailCapacity)
        childTail = ArrayList<UInt32>(childTailCapacity)
        payloads = ArrayList<ArenaNodePayload>()
        originMetadata = ArrayList<NodeOrigin>()
        parentIndexes = ArrayList<Int64>()
        nodeCountValue = 0
        childCountValue = 0
        unparentedCountValue = 0
    }

    init(base: Document, maximumNodes!: Int64 = Int64.Max) {
        if (maximumNodes < base.nodeCount) {
            throw LimitExceededException("ast_nodes", maximumNodes, base.nodeCount, "ast_transform")
        }
        // A transformed snapshot is a different Document identity even when
        // it shares immutable chunks with its source snapshot.
        documentIdentity = NEXT_ARENA_DOCUMENT_ID.fetchAdd(1)
        this.maximumNodes = if (maximumNodes == Int64.Max) {
            Int64.Max
        } else {
            base.storedNodeCount + maximumNodes
        }
        trustedParserConstruction = false
        sourceBuffer = base.parserSourceBuffer()
        nodeTailCapacity = 16
        childTailCapacity = 16
        frozenNodeChunks = ArrayList<ArenaNodeChunk>()
        frozenChildChunks = ArrayList<ArenaChildChunk>()
        nodeTail = ArrayList<ArenaNodeRecord>(nodeTailCapacity)
        childTail = ArrayList<UInt32>(childTailCapacity)
        payloads = ArrayList<ArenaNodePayload>()
        payloads.add(all: base.payloadArray())
        originMetadata = ArrayList<NodeOrigin>()
        originMetadata.add(all: base.originMetadataArray())
        parentIndexes = ArrayList<Int64>()
        var parentIndex: Int64 = 0
        while (parentIndex < base.storedNodeCount) {
            parentIndexes.add(-1)
            parentIndex++
        }
        let stack = ArrayList<Int64>()
        stack.add(base.rootIndex)
        while (!stack.isEmpty()) {
            let current = stack.remove(at: stack.size - 1)
            let record = base.recordAt(current)
            var childOffset: Int64 = record.childCount - 1
            while (childOffset >= 0) {
                let childIndex = base.childIndexAt(record.firstChild + childOffset)
                if (parentIndexes[childIndex] >= 0) {
                    throw IllegalStateException("base AST arena contains a reachable node with multiple parents")
                }
                parentIndexes[childIndex] = current
                stack.add(childIndex)
                childOffset--
            }
        }
        unparentedCountValue = 0
        for (index in 0..parentIndexes.size) {
            if (parentIndexes[index] < 0) {
                unparentedCountValue++
            }
        }
        let nodes = base.nodeChunkArray()
        if (!nodes.isEmpty() && nodes[nodes.size - 1].records.size < AST_NODE_CHUNK_SIZE) {
            var index: Int64 = 0
            while (index + 1 < nodes.size) {
                frozenNodeChunks.add(nodes[index])
                index++
            }
            nodeTail.add(all: nodes[nodes.size - 1].records)
        } else {
            frozenNodeChunks.add(all: nodes)
        }
        let children = base.childChunkArray()
        if (!children.isEmpty() && children[children.size - 1].nodeIndexes.size < AST_CHILD_CHUNK_SIZE) {
            var index: Int64 = 0
            while (index + 1 < children.size) {
                frozenChildChunks.add(children[index])
                index++
            }
            childTail.add(all: children[children.size - 1].nodeIndexes)
        } else {
            frozenChildChunks.add(all: children)
        }
        nodeCountValue = base.storedNodeCount
        childCountValue = base.storedChildCount
    }

    func append(kind: NodeKind, _category: NodeCategory, span: ?SourceSpan, originKind: NodeOriginKind,
        children: Array<Int64>, payload!: ArenaNodePayload = ArenaNodePayload.Empty, origin!: ?NodeOrigin = None): Int64 {
        let _ = _category
        if (children.size <= 8) {
            var childOffset: Int64 = 0
            while (childOffset < children.size) {
                let child = children[childOffset]
                if (child < 0 || child >= nodeCountValue) {
                    throw IllegalArgumentException("arena child must refer to an earlier node in the same Document")
                }
                if (parentIndexes[child] >= 0) {
                    throw IllegalArgumentException("arena node must have at most one parent")
                }
                var earlier: Int64 = 0
                while (earlier < childOffset) {
                    if (children[earlier] == child) {
                        throw IllegalArgumentException("arena node must have at most one parent")
                    }
                    earlier++
                }
                childOffset++
            }
        } else {
            let uniqueChildren = HashSet<Int64>()
            for (child in children) {
                if (child < 0 || child >= nodeCountValue) {
                    throw IllegalArgumentException("arena child must refer to an earlier node in the same Document")
                }
                if (parentIndexes[child] >= 0 || !uniqueChildren.add(child)) {
                    throw IllegalArgumentException("arena node must have at most one parent")
                }
            }
        }
        appendUnchecked(kind, span, originKind, children, payload, origin)
    }

    /** Parser-only construction path. ParserNodeFactory owns every child index
     * and emits a strict postorder tree, so general duplicate, forward and
     * multiple-parent scans are redundant. The shared allocation boundary still
     * enforces the AST node limit before mutating storage. */
    func appendParserOwned(kind: NodeKind, _category: NodeCategory, span: ?SourceSpan, originKind: NodeOriginKind,
        children: Array<Int64>, payload!: ArenaNodePayload = ArenaNodePayload.Empty, origin!: ?NodeOrigin = None): Int64 {
        let _ = _category
        if (!trustedParserConstruction) {
            throw IllegalStateException("parser-owned append requires a trusted parser arena")
        }
        appendUnchecked(kind, span, originKind, children, payload, origin)
    }

    /** Parser-owned list variant. The parser already owns this buffer and the
     * arena copies its indexes into chunked child storage, so materializing an
     * intermediate Array would add no isolation. */
    func appendParserOwnedList(kind: NodeKind, _category: NodeCategory, span: ?SourceSpan, originKind: NodeOriginKind,
        children: ArrayList<Int64>, payload!: ArenaNodePayload = ArenaNodePayload.Empty, origin!: ?NodeOrigin = None): Int64 {
        let _ = _category
        if (!trustedParserConstruction) {
            throw IllegalStateException("parser-owned append requires a trusted parser arena")
        }
        appendUncheckedList(kind, span, originKind, children, payload, origin)
    }

    private func appendUnchecked(kind: NodeKind, span: ?SourceSpan, originKind: NodeOriginKind, children: Array<Int64>,
        payload: ArenaNodePayload, origin: ?NodeOrigin): Int64 {
        if (nodeCountValue >= maximumNodes) {
            throw LimitExceededException("ast_nodes", maximumNodes, nodeCountValue + 1, "ast_allocation")
        }
        let index = nodeCountValue
        for (child in children) {
            if (!trustedParserConstruction) {
                parentIndexes[child] = index
            }
            unparentedCountValue--
            appendChild(child)
        }
        let payloadIndex = storePayload(payload)
        let originMetadataIndex: Int64 = if (let NodeOriginKind.Parsed <- originKind) {
            -1
        } else {
            match (origin) {
                case Some(value) =>
                    let metadataIndex = originMetadata.size
                    originMetadata.add(value)
                    metadataIndex
                case None => throw IllegalArgumentException("non-parsed arena node requires origin metadata")
            }
        }
        nodeTail.add(
            ArenaNodeRecord(kind, span, originKind, originMetadataIndex, childCountValue - children.size, children.size,
                payloadIndex))
        nodeCountValue++
        if (!trustedParserConstruction) {
            parentIndexes.add(-1)
        }
        unparentedCountValue++
        if (nodeTail.size == AST_NODE_CHUNK_SIZE) {
            freezeNodeTail()
        }
        index
    }

    private func appendUncheckedList(kind: NodeKind, span: ?SourceSpan, originKind: NodeOriginKind,
        children: ArrayList<Int64>, payload: ArenaNodePayload, origin: ?NodeOrigin): Int64 {
        if (nodeCountValue >= maximumNodes) {
            throw LimitExceededException("ast_nodes", maximumNodes, nodeCountValue + 1, "ast_allocation")
        }
        let index = nodeCountValue
        for (child in children) {
            unparentedCountValue--
            appendChild(child)
        }
        let payloadIndex = storePayload(payload)
        let originMetadataIndex: Int64 = if (let NodeOriginKind.Parsed <- originKind) {
            -1
        } else {
            match (origin) {
                case Some(value) =>
                    let metadataIndex = originMetadata.size
                    originMetadata.add(value)
                    metadataIndex
                case None => throw IllegalArgumentException("non-parsed arena node requires origin metadata")
            }
        }
        nodeTail.add(
            ArenaNodeRecord(kind, span, originKind, originMetadataIndex, childCountValue - children.size, children.size,
                payloadIndex))
        nodeCountValue++
        unparentedCountValue++
        if (nodeTail.size == AST_NODE_CHUNK_SIZE) {
            freezeNodeTail()
        }
        index
    }

    func freeze(): Document {
        freezeNodeTail()
        freezeChildTail()
        Document(documentIdentity, frozenNodeChunks.toArray(), frozenChildChunks.toArray(), payloads.toArray(),
            originMetadata.toArray(), nodeCountValue, childCountValue, sourceBuffer: sourceBuffer)
    }

    /** Captures the append-only construction state without allocating an AST
     * snapshot. Parser speculation must rollback to this value or commit it. */
    func checkpoint(): AstArenaCheckpoint {
        AstArenaCheckpoint(nodeCountValue, childCountValue, payloads.size, originMetadata.size, unparentedCountValue)
    }

    /** Removes append-only parser work performed after a checkpoint. The
     * implementation also handles a speculation that crossed a chunk boundary. */
    func rollback(checkpoint: AstArenaCheckpoint): Unit {
        if (checkpoint.nodeCount < 0 || checkpoint.nodeCount > nodeCountValue || checkpoint.childCount < 0 ||
            checkpoint.childCount > childCountValue || checkpoint.payloadCount < 0 || checkpoint.payloadCount > payloads
            .size || checkpoint.originMetadataCount < 0 || checkpoint.originMetadataCount > originMetadata.size) {
            throw IllegalArgumentException("arena checkpoint does not belong to the current append state")
        }

        // Parser speculation overwhelmingly stays inside the current chunks.
        // In that case the retained prefix is already present in both tails;
        // truncate only the discarded suffix instead of copying the whole
        // retained chunk into new ArrayLists on every rollback.
        let retainedNodeChunks = checkpoint.nodeCount / AST_NODE_CHUNK_SIZE
        let retainedChildChunks = checkpoint.childCount / AST_CHILD_CHUNK_SIZE
        if (trustedParserConstruction && frozenNodeChunks.size == retainedNodeChunks && frozenChildChunks.size ==
            retainedChildChunks) {
            let retainedNodeTail = checkpoint.nodeCount % AST_NODE_CHUNK_SIZE
            let retainedChildTail = checkpoint.childCount % AST_CHILD_CHUNK_SIZE
            while (nodeTail.size > retainedNodeTail) {
                nodeTail.remove(at: nodeTail.size - 1)
            }
            while (childTail.size > retainedChildTail) {
                childTail.remove(at: childTail.size - 1)
            }
            while (payloads.size > checkpoint.payloadCount) {
                payloads.remove(at: payloads.size - 1)
            }
            while (originMetadata.size > checkpoint.originMetadataCount) {
                originMetadata.remove(at: originMetadata.size - 1)
            }
            nodeCountValue = checkpoint.nodeCount
            childCountValue = checkpoint.childCount
            unparentedCountValue = checkpoint.unparentedCount
            return
        }

        // Capture the partial retained tails before removing chunks that may
        // have been frozen while the speculative parse was running.
        let retainedNodes = ArrayList<ArenaNodeRecord>()
        let retainedNodeStart = (checkpoint.nodeCount / AST_NODE_CHUNK_SIZE) * AST_NODE_CHUNK_SIZE
        if (checkpoint.nodeCount % AST_NODE_CHUNK_SIZE != 0) {
            var index = retainedNodeStart
            while (index < checkpoint.nodeCount) {
                retainedNodes.add(recordAt(index))
                index++
            }
        }
        let retainedChildren = ArrayList<UInt32>()
        let retainedChildStart = (checkpoint.childCount / AST_CHILD_CHUNK_SIZE) * AST_CHILD_CHUNK_SIZE
        if (checkpoint.childCount % AST_CHILD_CHUNK_SIZE != 0) {
            var index = retainedChildStart
            while (index < checkpoint.childCount) {
                retainedChildren.add(compactArenaIndex(childIndexAt(index), "child index"))
                index++
            }
        }

        let fullNodeChunks = checkpoint.nodeCount / AST_NODE_CHUNK_SIZE
        while (frozenNodeChunks.size > fullNodeChunks) {
            frozenNodeChunks.remove(at: frozenNodeChunks.size - 1)
        }
        nodeTail = retainedNodes
        let fullChildChunks = checkpoint.childCount / AST_CHILD_CHUNK_SIZE
        while (frozenChildChunks.size > fullChildChunks) {
            frozenChildChunks.remove(at: frozenChildChunks.size - 1)
        }
        childTail = retainedChildren

        while (payloads.size > checkpoint.payloadCount) {
            payloads.remove(at: payloads.size - 1)
        }
        while (originMetadata.size > checkpoint.originMetadataCount) {
            originMetadata.remove(at: originMetadata.size - 1)
        }
        if (!trustedParserConstruction) {
            while (parentIndexes.size > checkpoint.nodeCount) {
                parentIndexes.remove(at: parentIndexes.size - 1)
            }
            // A surviving node may have been attached to a speculative parent.
            // Reconstruct only the retained parent relation instead of walking
            // the discarded suffix or the full tree.
            for (index in 0..parentIndexes.size) {
                parentIndexes[index] = -1
            }
            var parent: Int64 = 0
            while (parent < checkpoint.nodeCount) {
                let record = if (parent < retainedNodeStart || checkpoint.nodeCount % AST_NODE_CHUNK_SIZE == 0) {
                    frozenNodeChunks[parent / AST_NODE_CHUNK_SIZE].records[parent % AST_NODE_CHUNK_SIZE]
                } else {
                    retainedNodes[parent - retainedNodeStart]
                }
                var offset: Int64 = 0
                while (offset < record.childCount) {
                    let childOffset = record.firstChild + offset
                    let child = Int64(if (childOffset < retainedChildStart ||
                        checkpoint.childCount % AST_CHILD_CHUNK_SIZE == 0) {
                        frozenChildChunks[childOffset / AST_CHILD_CHUNK_SIZE].nodeIndexes[childOffset %
                                AST_CHILD_CHUNK_SIZE]
                    } else {
                        retainedChildren[childOffset - retainedChildStart]
                    })
                    parentIndexes[child] = parent
                    offset++
                }
                parent++
            }
        }
        nodeCountValue = checkpoint.nodeCount
        childCountValue = checkpoint.childCount
        unparentedCountValue = checkpoint.unparentedCount
    }

    /** Freezes a persistent transform whose physical storage may also contain
     * unreachable records shared from the base snapshot. The public document
     * exposes only the records reachable from the selected root. */
    func freeze(rootIndex: Int64): Document {
        if (rootIndex < 0 || rootIndex >= nodeCountValue) {
            throw IndexOutOfBoundsException("transformed AST root is outside the arena")
        }
        let visited = HashSet<Int64>()
        let stack = ArrayList<Int64>()
        stack.add(rootIndex)
        var reachableChildren: Int64 = 0
        while (!stack.isEmpty()) {
            let current = stack.remove(at: stack.size - 1)
            if (!visited.add(current)) {
                throw IllegalStateException("transformed AST contains a cycle or multiple parents")
            }
            let record = recordAt(current)
            reachableChildren += record.childCount
            var offset: Int64 = record.childCount - 1
            while (offset >= 0) {
                stack.add(childIndexAt(record.firstChild + offset))
                offset--
            }
        }
        let reachable = ArrayList<Int64>()
        var index: Int64 = 0
        while (index < nodeCountValue) {
            if (visited.contains(index)) {
                reachable.add(index)
            }
            index++
        }
        freezeNodeTail()
        freezeChildTail()
        Document(documentIdentity, frozenNodeChunks.toArray(), frozenChildChunks.toArray(), payloads.toArray(),
            originMetadata.toArray(), nodeCountValue, childCountValue, rootIndex: rootIndex,
            reachableNodeIndexes: reachable.toArray(), reachableChildCount: reachableChildren,
            sourceBuffer: sourceBuffer)
    }

    /** Appends a path-copied record while reusing unchanged child subtrees.
     * Their old physical parents become unreachable in the new snapshot. */
    func appendPersistentCopy(source: NodeRef, children: Array<Int64>, transformId: String): Int64 {
        for (child in children) {
            if (child < 0 || child >= parentIndexes.size) {
                throw IllegalArgumentException("persistent child is outside the transform arena")
            }
            parentIndexes[child] = -1
        }
        let sourceSpan = source.span
        let origin = NodeOrigin(NodeOriginKind.Transformed, sourceNodeIds: [source.nodeId], sourceSpan: sourceSpan,
            transformId: Some(transformId))
        append(source.kind, source.category, sourceSpan, NodeOriginKind.Transformed, children,
            payload: source.snapshotPayload(), origin: Some(origin))
    }

    /** Returns a read-only view of the builder without sealing its partial
     * chunks. Extension compatibility code may inspect a node while parsing is
     * still active, so a preview must not change the append/index layout.
     */
    internal func snapshotView(): Document {
        let nodeChunks = ArrayList<ArenaNodeChunk>()
        nodeChunks.add(all: frozenNodeChunks.toArray())
        if (!nodeTail.isEmpty()) {
            nodeChunks.add(ArenaNodeChunk(nodeTail.toArray()))
        }
        let childChunks = ArrayList<ArenaChildChunk>()
        childChunks.add(all: frozenChildChunks.toArray())
        if (!childTail.isEmpty()) {
            childChunks.add(ArenaChildChunk(childTail.toArray()))
        }
        Document(documentIdentity, nodeChunks.toArray(), childChunks.toArray(), payloads.toArray(),
            originMetadata.toArray(), nodeCountValue, childCountValue, sourceBuffer: sourceBuffer)
    }

    /** Replaces one compact header while preserving its NodeId and child
     * range. A frozen chunk is cloned once; every other chunk stays shared.
     */
    func replaceRecord(index: Int64, kind: NodeKind, _category: NodeCategory, span: ?SourceSpan,
        originKind: NodeOriginKind, payload!: ?ArenaNodePayload = None, origin!: ?NodeOrigin = None): Unit {
        let _ = _category
        if (index < 0 || index >= nodeCountValue) {
            throw IndexOutOfBoundsException("node arena replacement index is outside the builder")
        }
        let frozenCount = frozenNodeChunks.size * AST_NODE_CHUNK_SIZE
        if (index < frozenCount) {
            let chunkIndex = index / AST_NODE_CHUNK_SIZE
            let within = index % AST_NODE_CHUNK_SIZE
            let records = frozenNodeChunks[chunkIndex].records.clone()
            let previous = records[within]
            records[within] = replacementRecord(previous, kind, span, originKind,
                replacementPayloadIndex(previous, payload), replacementOriginMetadataIndex(previous, originKind, origin))
            frozenNodeChunks[chunkIndex] = ArenaNodeChunk(records)
        } else {
            let within = index - frozenCount
            let previous = nodeTail[within]
            nodeTail[within] = replacementRecord(previous, kind, span, originKind,
                replacementPayloadIndex(previous, payload), replacementOriginMetadataIndex(previous, originKind, origin))
        }
    }

    internal func recordAt(index: Int64): ArenaNodeRecord {
        if (index < 0 || index >= nodeCountValue) {
            throw IndexOutOfBoundsException("node arena index is outside the builder")
        }
        let frozenCount = frozenNodeChunks.size * AST_NODE_CHUNK_SIZE
        if (index < frozenCount) {
            return frozenNodeChunks[index / AST_NODE_CHUNK_SIZE].records[index % AST_NODE_CHUNK_SIZE]
        }
        nodeTail[index - frozenCount]
    }

    internal func childIndexAt(index: Int64): Int64 {
        if (index < 0 || index >= childCountValue) {
            throw IndexOutOfBoundsException("child arena index is outside the builder")
        }
        let frozenCount = frozenChildChunks.size * AST_CHILD_CHUNK_SIZE
        if (index < frozenCount) {
            return Int64(frozenChildChunks[index / AST_CHILD_CHUNK_SIZE].nodeIndexes[index % AST_CHILD_CHUNK_SIZE])
        }
        Int64(childTail[index - frozenCount])
    }

    internal func payloadAt(index: Int64): ArenaNodePayload {
        let record = recordAt(index)
        if (record.payloadIndex < 0) {
            return inlineArenaPayload(record.payloadIndex)
        }
        if (record.payloadIndex >= payloads.size) {
            throw IllegalStateException("arena node payload index is outside the builder")
        }
        payloads[record.payloadIndex]
    }

    internal func unparentedNodeCount(): Int64 {
        unparentedCountValue
    }

    private func appendChild(index: Int64): Unit {
        childTail.add(compactArenaIndex(index, "child index"))
        childCountValue++
        if (childTail.size == AST_CHILD_CHUNK_SIZE) {
            freezeChildTail()
        }
    }

    private func freezeNodeTail(): Unit {
        if (!nodeTail.isEmpty()) {
            let records = if (nodeTail.size == nodeTail.capacity) {
                // The parser owns this tail exclusively and replaces it below.
                // Transfer an exactly filled backing array into the immutable
                // chunk instead of allocating and copying it in toArray().
                unsafe { nodeTail.getRawArray() }
            } else {
                nodeTail.toArray()
            }
            frozenNodeChunks.add(ArenaNodeChunk(records))
            nodeTail = ArrayList<ArenaNodeRecord>(nodeTailCapacity)
        }
    }

    private func freezeChildTail(): Unit {
        if (!childTail.isEmpty()) {
            let indexes = if (childTail.size == childTail.capacity) {
                unsafe { childTail.getRawArray() }
            } else {
                childTail.toArray()
            }
            frozenChildChunks.add(ArenaChildChunk(indexes))
            childTail = ArrayList<UInt32>(childTailCapacity)
        }
    }

    private func replacementRecord(previous: ArenaNodeRecord, kind: NodeKind, span: ?SourceSpan,
        originKind: NodeOriginKind, payloadIndex: Int64, originMetadataIndex: Int64): ArenaNodeRecord {
        ArenaNodeRecord(kind, span, originKind, originMetadataIndex, previous.firstChild, previous.childCount,
            payloadIndex)
    }

    private func replacementPayloadIndex(previous: ArenaNodeRecord, payload: ?ArenaNodePayload): Int64 {
        match (payload) {
            case Some(value) => storePayload(value)
            case None => previous.payloadIndex
        }
    }

    private func storePayload(payload: ArenaNodePayload): Int64 {
        match (payload) {
            case ArenaNodePayload.Empty => ARENA_PAYLOAD_EMPTY
            case ArenaNodePayload.HeadingValue(level) => match (level) {
                case 1 => ARENA_PAYLOAD_HEADING_1
                case 2 => ARENA_PAYLOAD_HEADING_2
                case 3 => ARENA_PAYLOAD_HEADING_3
                case 4 => ARENA_PAYLOAD_HEADING_4
                case 5 => ARENA_PAYLOAD_HEADING_5
                case 6 => ARENA_PAYLOAD_HEADING_6
                case _ => storeSidePayload(payload)
            }
            case ArenaNodePayload.ThematicBreakValue(marker) => match (marker) {
                case b'-' => ARENA_PAYLOAD_THEMATIC_DASH
                case b'*' => ARENA_PAYLOAD_THEMATIC_STAR
                case b'_' => ARENA_PAYLOAD_THEMATIC_UNDERSCORE
                case _ => storeSidePayload(payload)
            }
            case ArenaNodePayload.HardBreakValue(syntaxKind) => match (syntaxKind) {
                case HardBreakKind.Backslash => ARENA_PAYLOAD_HARD_BREAK_BACKSLASH
                case HardBreakKind.Spaces => ARENA_PAYLOAD_HARD_BREAK_SPACES
            }
            case ArenaNodePayload.ListValue(kind, start, delimiter, tight) => inlineListPayload(kind, start, delimiter,
                tight, payload)
            case ArenaNodePayload.TableRowValue(header) =>
                if (header) {
                    ARENA_PAYLOAD_TABLE_ROW_HEADER
                } else {
                    ARENA_PAYLOAD_TABLE_ROW_BODY
                }
            case ArenaNodePayload.TableCellValue(alignment) => match (alignment) {
                case TableAlignment.None => ARENA_PAYLOAD_TABLE_CELL_NONE
                case TableAlignment.Left => ARENA_PAYLOAD_TABLE_CELL_LEFT
                case TableAlignment.Center => ARENA_PAYLOAD_TABLE_CELL_CENTER
                case TableAlignment.Right => ARENA_PAYLOAD_TABLE_CELL_RIGHT
            }
            case ArenaNodePayload.ListItemValue(taskState, markerSpan) => match (taskState) {
                case TaskState.NotTask =>
                    if (markerSpan.isNone()) {
                        ARENA_PAYLOAD_LIST_ITEM_PLAIN
                    } else {
                        storeSidePayload(payload)
                    }
                case _ => storeSidePayload(payload)
            }
            case ArenaNodePayload.TextSourceValue => ARENA_PAYLOAD_TEXT_SOURCE
            case _ => storeSidePayload(payload)
        }
    }

    private func storeSidePayload(payload: ArenaNodePayload): Int64 {
        let index = payloads.size
        payloads.add(payload)
        index
    }

    private func inlineListPayload(kind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool,
        payload: ArenaNodePayload): Int64 {
        match (kind) {
            case ListKind.Bullet =>
                if (start == 0) {
                    match (delimiter) {
                        case ListDelimiter.None =>
                            if (tight) {
                                ARENA_PAYLOAD_BULLET_LIST_TIGHT
                            } else {
                                ARENA_PAYLOAD_BULLET_LIST_LOOSE
                            }
                        case _ => storeSidePayload(payload)
                    }
                } else {
                    storeSidePayload(payload)
                }
            case ListKind.Ordered =>
                if (start == 0) {
                    match (delimiter) {
                        case ListDelimiter.Period =>
                            if (tight) {
                                ARENA_PAYLOAD_ORDERED_ZERO_PERIOD_TIGHT
                            } else {
                                ARENA_PAYLOAD_ORDERED_ZERO_PERIOD_LOOSE
                            }
                        case ListDelimiter.Parenthesis =>
                            if (tight) {
                                ARENA_PAYLOAD_ORDERED_ZERO_PAREN_TIGHT
                            } else {
                                ARENA_PAYLOAD_ORDERED_ZERO_PAREN_LOOSE
                            }
                        case ListDelimiter.None => storeSidePayload(payload)
                    }
                } else if (start == 1) {
                    match (delimiter) {
                        case ListDelimiter.Period =>
                            if (tight) {
                                ARENA_PAYLOAD_ORDERED_ONE_PERIOD_TIGHT
                            } else {
                                ARENA_PAYLOAD_ORDERED_ONE_PERIOD_LOOSE
                            }
                        case ListDelimiter.Parenthesis =>
                            if (tight) {
                                ARENA_PAYLOAD_ORDERED_ONE_PAREN_TIGHT
                            } else {
                                ARENA_PAYLOAD_ORDERED_ONE_PAREN_LOOSE
                            }
                        case ListDelimiter.None => storeSidePayload(payload)
                    }
                } else {
                    storeSidePayload(payload)
                }
        }
    }

    private func replacementOriginMetadataIndex(previous: ArenaNodeRecord, originKind: NodeOriginKind,
        origin: ?NodeOrigin): Int64 {
        if (let NodeOriginKind.Parsed <- originKind) {
            return -1
        }
        match (origin) {
            case Some(value) =>
                let index = originMetadata.size
                originMetadata.add(value)
                index
            case None =>
                if (previous.originMetadataIndex >= 0) {
                    previous.originMetadataIndex
                } else {
                    throw IllegalArgumentException("non-parsed arena replacement requires origin metadata")
                }
        }
    }
}
