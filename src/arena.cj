package markdown

import std.collection.*

// Arena storage boundaries do not determine public NodeIds or persisted
// identities. Keep storage parameters next to their implementation.
internal let AST_NODE_CHUNK_SIZE: Int64 = 4096
internal let AST_CHILD_CHUNK_SIZE: Int64 = 16384
internal let AST_SOURCE_OFFSET_MAX: Int64 = 4294967294
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
        case NodeKind.DocumentNode => 0
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
        case 0 => NodeKind.DocumentNode
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

/** arena 中的紧凑语义 header；kind-specific payload 单独存储。 */
public struct ArenaNodeRecord {
    private let localIdentityValue: UInt32
    private let identityDescriptorValue: UInt32
    private let spanStartByteValue: UInt32
    private let spanEndByteValue: UInt32
    private let firstChildValue: UInt32
    private let childCountValue: UInt32
    private let payloadIndexValue: UInt32

    internal init(localIdentity: Int64, kind: NodeKind, span: ?SourceSpan, originKind: NodeOriginKind,
        originMetadataIndex: Int64, firstChild: Int64, childCount: Int64, payloadIndex: Int64) {
        localIdentityValue = UInt32(localIdentity)
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

    internal prop localIdentity: Int64 {
        get() {
            Int64(localIdentityValue)
        }
    }

    /** 第一个 child 的物理 arena index。 */
    public prop firstChild: Int64 {
        get() {
            Int64(firstChildValue)
        }
    }

    /** 节点种类。 */
    public prop kind: NodeKind {
        get() {
            nodeKindFromTag(Int64(identityDescriptorValue & 0x1Fu32))
        }
    }

    /** child 数量。 */
    public prop childCount: Int64 {
        get() {
            Int64(childCountValue)
        }
    }

    /** payload 的 arena index。 */
    public prop payloadIndex: Int64 {
        get() {
            Int64(payloadIndexValue) + ARENA_PAYLOAD_INLINE_MIN
        }
    }

    /** 节点的 source span；无 span 时为 `None`。 */
    public prop span: ?SourceSpan {
        get() {
            if (spanStartByteValue == UInt32.Max) {
                None
            } else {
                Some(SourceSpan(Int64(spanStartByteValue), Int64(spanEndByteValue)))
            }
        }
    }

    /** block/inline 分类。 */
    public prop category: NodeCategory {
        get() {
            match (kind) {
                case NodeKind.DocumentNode | NodeKind.BlockQuote | NodeKind.List | NodeKind.ListItem
                    | NodeKind.Paragraph | NodeKind.Heading | NodeKind.ThematicBreak | NodeKind.CodeBlock
                    | NodeKind.HtmlBlock | NodeKind.Table | NodeKind.TableRow | NodeKind.TableCell
                    | NodeKind.CustomBlock => NodeCategory.Block
                case _ => NodeCategory.Inline
            }
        }
    }

    /** 节点来源类别。 */
    public prop originKind: NodeOriginKind {
        get() {
            originKindFromTag(Int64((identityDescriptorValue >> 5) & 0x7u32))
        }
    }

    /** 非 parsed 来源的 metadata index；parsed 节点为 -1。 */
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

/**
 * 不可变 arena AST snapshot 的 owner。
 *
 * `NodeRef` 只对所属 Document 有效；把其他 snapshot 的 NodeRef 传入访问器会被拒绝。
 * `nodeCount` 和 `childCount` 描述从 root 可达的逻辑结构。
 */
public class Document {
    /** 此不可变 Document 视图的唯一 revision；不同视图的 NodeRef 不可混用。 */
    public let revision: Int64
    private let lineageAllocator: NodeLineage
    /** 当前不可变视图的语义绑定索引。 */
    public let bindings: DocumentBindings
    private let nodeChunks: Array<ArenaNodeChunk>
    private let childChunks: Array<ArenaChildChunk>
    private let payloads: Array<ArenaNodePayload>
    private let originMetadata: Array<NodeOrigin>
    private let sourceBuffer: ?SourceBuffer
    private let physicalNodeCount: Int64
    private let physicalChildCount: Int64
    private let rootRecordIndex: Int64
    private let logicalNodeIndexes: Array<Int64>
    /** 逻辑节点总数。 */
    public let nodeCount: Int64
    /** 逻辑 child 总数。 */
    public let childCount: Int64

    internal init(documentRevision: Int64, lineageAllocator: NodeLineage, nodeChunks: Array<ArenaNodeChunk>,
        childChunks: Array<ArenaChildChunk>, payloads: Array<ArenaNodePayload>, originMetadata: Array<NodeOrigin>,
        physicalNodeCount: Int64, physicalChildCount: Int64, rootIndex!: Int64 = -1,
        reachableNodeIndexes!: Array<Int64> = [], reachableChildCount!: Int64 = -1, sourceBuffer!: ?SourceBuffer = None,
        bindings!: DocumentBindings = DocumentBindings.empty()) {
        this.revision = documentRevision
        this.lineageAllocator = lineageAllocator
        this.bindings = bindings
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

    /** 节点的共同分配 lineage；持久化分叉共享此值。 */
    public prop lineage: Int64 {
        get() {
            lineageAllocator.identity
        }
    }

    internal func nodeLineage(): NodeLineage {
        lineageAllocator
    }

    internal func nodeIdAt(index: Int64): NodeId {
        NodeId(lineage, recordAt(index).localIdentity)
    }

    internal func withBindings(value: DocumentBindings): Document {
        copySnapshot(sourceBuffer, value)
    }

    internal func withSourceBuffer(value: SourceBuffer): Document {
        copySnapshot(Some(value), bindings)
    }

    private func copySnapshot(source: ?SourceBuffer, bindings: DocumentBindings): Document {
        Document(nextDocumentRevision(), lineageAllocator, nodeChunks, childChunks, payloads, originMetadata,
            physicalNodeCount, physicalChildCount, rootIndex: rootRecordIndex, reachableNodeIndexes: logicalNodeIndexes,
            reachableChildCount: childCount, sourceBuffer: source, bindings: bindings)
    }

    internal func requireSource(source: SourceBuffer): Unit {
        if (let Some(owned) <- sourceBuffer) {
            if (refEq(owned, source)) {
                return
            }
        }
        throw IllegalArgumentException("source buffer does not belong to this Document snapshot")
    }

    /** 返回逻辑 arena index 对应的 NodeRef。
     * @param index 逻辑 arena index。
     * @return 对应的 `NodeRef`。
     * @throws IndexOutOfBoundsException index 越界时。
     */
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

    /**
     * 返回 Document root。
     * @return document root 节点。
     * @throws IllegalStateException arena 为空时。
     */
    public func root(): NodeRef {
        if (nodeCount == 0 || rootRecordIndex < 0) {
            throw IllegalStateException("AST arena has no root node")
        }
        nodeRefAtPhysical(rootRecordIndex)
    }

    /** 返回 root 的 NodeId。 */
    public prop nodeId: NodeId {
        get() {
            root().nodeId
        }
    }
    /** root 节点的 source span。 */
    public prop span: ?SourceSpan {
        get() {
            root().span
        }
    }
    /** document 使用的 profile。 */
    public prop profile: MarkdownProfile {
        get() {
            root().asDocument().getOrThrow().profile
        }
    }
    /** document 使用的 dialect fingerprint。 */
    public prop dialectFingerprint: String {
        get() {
            root().asDocument().getOrThrow().dialectFingerprint
        }
    }
    /** 文档级引用定义。 */
    public prop references: ImmutableArray<ReferenceDefinition> {
        get() {
            root().asDocument().getOrThrow().references
        }
    }
    /**
     * 返回 root 的零复制 child view。
     * @return root 的零复制 child view。
     */
    public func children(): NodeChildren {
        root().children()
    }

    /** 返回指定节点的零复制 child view；node 必须属于当前 Document。
     * @param node 目标节点。
     * @return 指定节点的零复制 child view。
     * @throws IllegalArgumentException node 不属于当前 Document 时。
     */
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
        if (node.documentIdentity != revision) {
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
            revision
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
        NodeRef(this, revision, index)
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

/**
 * 绑定 Document snapshot 的轻量节点引用和 typed-view anchor。
 *
 * 引用不包含 child array 或 origin 对象；通过 properties 和 `as*` 方法读取它们。
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

    /** 节点在 lineage 内不回收的身份，与 arena 下标无关。 */
    public prop nodeId: NodeId {
        get() {
            snapshot.nodeIdAt(index)
        }
    }
    /** 此引用绑定的不可变 Document revision。 */
    public prop revision: Int64 {
        get() {
            documentIdentity
        }
    }

    internal prop documentBindings: DocumentBindings {
        get() {
            snapshot.bindings
        }
    }

    internal func requireSource(source: SourceBuffer): Unit {
        snapshot.requireSource(source)
    }
    /** 节点种类。 */
    public prop kind: NodeKind {
        get() {
            snapshot.recordAt(index).kind
        }
    }
    /** block/inline 分类。 */
    public prop category: NodeCategory {
        get() {
            snapshot.recordAt(index).category
        }
    }
    /** 节点的 source span。 */
    public prop span: ?SourceSpan {
        get() {
            snapshot.recordAt(index).span
        }
    }
    /** 节点来源类别。 */
    public prop originKind: NodeOriginKind {
        get() {
            snapshot.recordAt(index).originKind
        }
    }
    /** 节点来源详情。 */
    public prop origin: NodeOrigin {
        get() {
            snapshot.originAt(index)
        }
    }

    /**
     * 返回该节点的零复制 child view。
     * @return 该节点的零复制 child view。
     */
    public func children(): NodeChildren {
        snapshot.children(this)
    }

    internal func snapshotPayload(): ArenaNodePayload {
        snapshot.payloadAt(index)
    }

    /**
     * 若节点是 Heading，则返回带 level 的 view。
     * @return 对应的 `HeadingNodeView`；节点类别不符时为 `None`。
     */
    public func asHeading(): ?HeadingNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HeadingValue(level) => Some(HeadingNodeView(this, level))
            case _ => None
        }
    }

    /**
     * 若节点是 DocumentNode，则返回 document view。
     * @return 对应的 `DocumentNodeView`；节点类别不符时为 `None`。
     */
    public func asDocument(): ?DocumentNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.DocumentValue(profile, dialectFingerprint, references) => Some(
                DocumentNodeView(this, profile, dialectFingerprint, references))
            case _ => None
        }
    }

    /**
     * 若节点是 Text，则返回 raw、value 和 normalized view。
     * @return 对应的 `TextNodeView`；节点类别不符时为 `None`。
     */
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

    /**
     * 若节点是 List，则返回 list metadata view。
     * @return 对应的 `ListNodeView`；节点类别不符时为 `None`。
     */
    public func asList(): ?ListNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.ListValue(kind, start, delimiter, tight) => Some(
                ListNodeView(this, kind, start, delimiter, tight))
            case _ => None
        }
    }

    /**
     * 若节点是 ListItem，则返回 task state view。
     * @return 对应的 `ListItemNodeView`；节点类别不符时为 `None`。
     */
    public func asListItem(): ?ListItemNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.ListItemValue(taskState, markerSpan) => Some(
                ListItemNodeView(this, taskState, markerSpan))
            case _ => None
        }
    }

    /**
     * 若节点是 ThematicBreak，则返回 marker view。
     * @return 对应的 `ThematicBreakNodeView`；节点类别不符时为 `None`。
     */
    public func asThematicBreak(): ?ThematicBreakNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.ThematicBreakValue(marker) => Some(ThematicBreakNodeView(this, marker))
            case _ => None
        }
    }

    /**
     * 若节点是 CodeBlock，则返回 fenced/indented 和 literal metadata。
     * @return 对应的 `CodeBlockNodeView`；节点类别不符时为 `None`。
     */
    public func asCodeBlock(): ?CodeBlockNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.CodeBlockValue(kind, literal, fenceCharacter, fenceLength, openingFenceSpan, closingFenceSpan, infoRaw, language, attributesRaw) => Some(
                CodeBlockNodeView(this, kind, literal, fenceCharacter, fenceLength, openingFenceSpan, closingFenceSpan,
                    infoRaw, language, attributesRaw))
            case _ => None
        }
    }

    /**
     * 若节点是 HtmlBlock，则返回 raw literal view。
     * @return 对应的 `HtmlBlockNodeView`；节点类别不符时为 `None`。
     */
    public func asHtmlBlock(): ?HtmlBlockNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HtmlBlockValue(literal, blockType) => Some(HtmlBlockNodeView(this, literal, blockType))
            case _ => None
        }
    }

    /**
     * 若节点是 Link，则返回 raw/normalized destination view。
     * @return 对应的 `LinkNodeView`；节点类别不符时为 `None`。
     */
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

    /**
     * 若节点是 Image，则返回 raw/normalized destination view。
     * @return 对应的 `ImageNodeView`；节点类别不符时为 `None`。
     */
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

    /**
     * 若节点是 Table，则返回列对齐 view。
     * @return 对应的 `TableNodeView`；节点类别不符时为 `None`。
     */
    public func asTable(): ?TableNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TableValue(alignments) => Some(TableNodeView(this, alignments))
            case _ => None
        }
    }

    /**
     * 若节点是 TableRow，则返回 header 标记 view。
     * @return 对应的 `TableRowNodeView`；节点类别不符时为 `None`。
     */
    public func asTableRow(): ?TableRowNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TableRowValue(header) => Some(TableRowNodeView(this, header))
            case _ => None
        }
    }

    /**
     * 若节点是 TableCell，则返回 alignment view。
     * @return 对应的 `TableCellNodeView`；节点类别不符时为 `None`。
     */
    public func asTableCell(): ?TableCellNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.TableCellValue(alignment) => Some(TableCellNodeView(this, alignment))
            case _ => None
        }
    }

    /**
     * 若节点是 HardBreak，则返回语法来源 view。
     * @return 对应的 `HardBreakNodeView`；节点类别不符时为 `None`。
     */
    public func asHardBreak(): ?HardBreakNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HardBreakValue(syntaxKind) => Some(HardBreakNodeView(this, syntaxKind))
            case _ => None
        }
    }

    /**
     * 若节点是 CodeSpan，则返回 literal 和 delimiter view。
     * @return 对应的 `CodeSpanNodeView`；节点类别不符时为 `None`。
     */
    public func asCodeSpan(): ?CodeSpanNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.CodeSpanValue(literal, delimiterRaw) => Some(
                CodeSpanNodeView(this, literal, delimiterRaw))
            case _ => None
        }
    }

    /**
     * 若节点是 HtmlInline，则返回 raw literal view。
     * @return 对应的 `HtmlInlineNodeView`；节点类别不符时为 `None`。
     */
    public func asHtmlInline(): ?HtmlInlineNodeView {
        match (snapshot.payloadAt(index)) {
            case ArenaNodePayload.HtmlInlineValue(literal) => Some(HtmlInlineNodeView(this, literal))
            case _ => None
        }
    }

    /**
     * 若节点是 CustomBlock，则返回扩展身份和 payload view。
     * @return 对应的 `CustomNodeView`；节点类别不符时为 `None`。
     */
    public func asCustomBlock(): ?CustomNodeView {
        if (let NodeKind.CustomBlock <- kind) {
            customView()
        } else {
            None
        }
    }

    /**
     * 若节点是 CustomInline，则返回扩展身份和 payload view。
     * @return 对应的 `CustomNodeView`；节点类别不符时为 `None`。
     */
    public func asCustomInline(): ?CustomNodeView {
        if (let NodeKind.CustomInline <- kind) {
            customView()
        } else {
            None
        }
    }

    /** 按文档身份和物理 index 比较两个节点引用。
     * @param other 参与比较的另一个节点引用。
     * @return 两个引用是否指向同一 snapshot 的同一节点。
     */
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

/** 一个节点连续 child-index range 的零复制 view。 */
public struct NodeChildren {
    private let snapshot: Document
    private let firstChild: Int64
    /** child 数量。 */
    public let size: Int64

    internal init(snapshot: Document, firstChild: Int64, size: Int64) {
        this.snapshot = snapshot
        this.firstChild = firstChild
        this.size = size
    }

    /**
     * 返回 child 数量是否为零。
     * @return child 数量是否为零。
     */
    public func isEmpty(): Bool {
        size == 0
    }

    /** 按 child index 读取 NodeRef；越界时抛出异常。
     * @param index 目标 child index。
     * @return 对应的 child `NodeRef`。
     * @throws IndexOutOfBoundsException index 越界时。
     */
    public operator func [](index: Int64): NodeRef {
        if (index < 0 || index >= size) {
            throw IndexOutOfBoundsException("child index is outside the node range")
        }
        snapshot.nodeRefAtPhysical(snapshot.childIndexAt(firstChild + index))
    }

    /**
     * 将 child view materialize 为数组。
     * @return 物化后的 child 数组。
     */
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

/** Document root 的 profile、dialect fingerprint 和 reference view。 */
public struct DocumentNodeView {
    /** 锚定的 document root 节点。 */
    public let node: NodeRef
    /** document 使用的 profile。 */
    public let profile: MarkdownProfile
    /** document 使用的 dialect fingerprint。 */
    public let dialectFingerprint: String
    /** 文档级引用定义。 */
    public let references: ImmutableArray<ReferenceDefinition>
    internal init(node: NodeRef, profile: MarkdownProfile, dialectFingerprint: String,
        references: ImmutableArray<ReferenceDefinition>) {
        this.node = node
        this.profile = profile
        this.dialectFingerprint = dialectFingerprint
        this.references = references
    }
}

/** Heading 节点及其 level。 */
public struct HeadingNodeView {
    /** 锚定的 Heading 节点。 */
    public let node: NodeRef
    /** 标题级别（1-6）。 */
    public let level: Int64
    /** 标题扩展启用后的权威锚点与展示信息。 */
    public prop binding: ?HeadingBinding {
        get() {
            node.documentBindings.headingForNode(node.nodeId)
        }
    }
    internal init(node: NodeRef, level: Int64) {
        this.node = node
        this.level = level
    }
}

/** Text 节点的 raw、semantic value 和可选 normalized value。 */
public struct TextNodeView {
    /** 锚定的 Text 节点。 */
    public let node: NodeRef
    private let rawStorage: LiteralStorage
    private let valueStorage: LiteralStorage
    /** 规范化后的文本；不存在时为 `None`。 */
    public let normalized: ?String
    internal init(node: NodeRef, raw: LiteralStorage, value: LiteralStorage, normalized: ?String) {
        this.node = node
        rawStorage = raw
        valueStorage = value
        this.normalized = normalized
    }
    /** 原始文本。 */
    public prop raw: String {
        get() {
            rawStorage.text()
        }
    }
    /** 语义文本。 */
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

/** List 节点的 kind、起始编号、delimiter 和 tight 状态。 */
public struct ListNodeView {
    /** 锚定的 List 节点。 */
    public let node: NodeRef
    /** bullet 或 ordered 类别。 */
    public let listKind: ListKind
    /** ordered list 的起始编号。 */
    public let start: Int64
    /** ordered delimiter 形式。 */
    public let delimiter: ListDelimiter
    /** 是否为 tight list。 */
    public let tight: Bool
    internal init(node: NodeRef, listKind: ListKind, start: Int64, delimiter: ListDelimiter, tight: Bool) {
        this.node = node
        this.listKind = listKind
        this.start = start
        this.delimiter = delimiter
        this.tight = tight
    }
}

/** ListItem 节点的 task state 和 marker span。 */
public struct ListItemNodeView {
    /** 锚定的 ListItem 节点。 */
    public let node: NodeRef
    /** task list 状态。 */
    public let taskState: TaskState
    /** list marker 的 source span。 */
    public let markerSpan: ?SourceSpan
    internal init(node: NodeRef, taskState: TaskState, markerSpan: ?SourceSpan) {
        this.node = node
        this.taskState = taskState
        this.markerSpan = markerSpan
    }
}

/** ThematicBreak 节点及其 marker byte。 */
public struct ThematicBreakNodeView {
    /** 锚定的 ThematicBreak 节点。 */
    public let node: NodeRef
    /** 使用的 marker 字符。 */
    public let marker: Byte
    internal init(node: NodeRef, marker: Byte) {
        this.node = node
        this.marker = marker
    }
}

/** CodeBlock 节点的 fence、language、attributes 和 literal view。 */
public struct CodeBlockNodeView {
    /** 锚定的 CodeBlock 节点。 */
    public let node: NodeRef
    /** fenced 或 indented 形态。 */
    public let codeKind: CodeBlockKind
    private let literalStorage: LiteralStorage
    /** 围栏字符；indented 块为 `None`。 */
    public let fenceCharacter: ?Byte
    /** 围栏长度。 */
    public let fenceLength: Int64
    /** 开始围栏的 source span。 */
    public let openingFenceSpan: ?SourceSpan
    /** 结束围栏的 source span；未闭合时为 `None`。 */
    public let closingFenceSpan: ?SourceSpan
    /** 原始 info string。 */
    public let infoRaw: String
    /** 解析出的 language 标识。 */
    public let language: String
    /** 原始 attributes 文本。 */
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
    /** 代码块文本。 */
    public prop literal: String {
        get() {
            literalStorage.text()
        }
    }
    internal func storedLiteral(): LiteralStorage {
        literalStorage
    }
}

/** HtmlBlock 节点的 HTML block type 和 literal view。 */
public struct HtmlBlockNodeView {
    /** 锚定的 HtmlBlock 节点。 */
    public let node: NodeRef
    private let literalStorage: LiteralStorage
    /** HTML block type（0-7）。 */
    public let blockType: Int64
    internal init(node: NodeRef, literalStorage: LiteralStorage, blockType: Int64) {
        this.node = node
        this.literalStorage = literalStorage
        this.blockType = blockType
    }
    /** 原始 HTML literal 文本。 */
    public prop literal: String {
        get() {
            literalStorage.text()
        }
    }
    internal func storedLiteral(): LiteralStorage {
        literalStorage
    }
}

/** Link 节点的 raw/normalized destination、title 和语法来源。 */
public struct LinkNodeView {
    /** 锚定的 Link 节点。 */
    public let node: NodeRef
    /** 原始 destination 文本。 */
    public let destinationRaw: String
    /** 解析后的 destination。 */
    public let destination: String
    /** 原始 title 文本。 */
    public let titleRaw: String
    /** 解析后的 title。 */
    public let title: String
    /** destination 的语法来源。 */
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

/** Image 节点的 raw/normalized destination、title 和语法来源。 */
public struct ImageNodeView {
    /** 锚定的 Image 节点。 */
    public let node: NodeRef
    /** 原始 destination 文本。 */
    public let destinationRaw: String
    /** 解析后的 destination。 */
    public let destination: String
    /** 原始 title 文本。 */
    public let titleRaw: String
    /** 解析后的 title。 */
    public let title: String
    /** destination 的语法来源。 */
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

/** Table 节点及其列对齐信息。 */
public struct TableNodeView {
    /** 锚定的 Table 节点。 */
    public let node: NodeRef
    /** 各列的对齐方式。 */
    public let alignments: ImmutableArray<TableAlignment>
    internal init(node: NodeRef, alignments: ImmutableArray<TableAlignment>) {
        this.node = node
        this.alignments = alignments
    }
}

/** TableRow 节点及其 header 标记。 */
public struct TableRowNodeView {
    /** 锚定的 TableRow 节点。 */
    public let node: NodeRef
    /** 是否为表头行。 */
    public let header: Bool
    internal init(node: NodeRef, header: Bool) {
        this.node = node
        this.header = header
    }
}

/** TableCell 节点及其 alignment。 */
public struct TableCellNodeView {
    /** 锚定的 TableCell 节点。 */
    public let node: NodeRef
    /** 单元格对齐方式。 */
    public let alignment: TableAlignment
    internal init(node: NodeRef, alignment: TableAlignment) {
        this.node = node
        this.alignment = alignment
    }
}

/** HardBreak 节点及其语法来源。 */
public struct HardBreakNodeView {
    /** 锚定的 HardBreak 节点。 */
    public let node: NodeRef
    /** 硬换行的语法来源。 */
    public let syntaxKind: HardBreakKind
    internal init(node: NodeRef, syntaxKind: HardBreakKind) {
        this.node = node
        this.syntaxKind = syntaxKind
    }
}

/** CodeSpan 节点的 literal 和 delimiter raw spelling。 */
public struct CodeSpanNodeView {
    /** 锚定的 CodeSpan 节点。 */
    public let node: NodeRef
    /** 代码文本。 */
    public let literal: String
    /** 原始 delimiter spelling。 */
    public let delimiterRaw: String
    internal init(node: NodeRef, literal: String, delimiterRaw: String) {
        this.node = node
        this.literal = literal
        this.delimiterRaw = delimiterRaw
    }
}

/** HtmlInline 节点的 raw literal。 */
public struct HtmlInlineNodeView {
    /** 锚定的 HtmlInline 节点。 */
    public let node: NodeRef
    /** 原始 HTML 文本。 */
    public let literal: String
    internal init(node: NodeRef, literal: String) {
        this.node = node
        this.literal = literal
    }
}

/** custom node 的扩展身份、local kind 和 typed payload。 */
public struct CustomNodeView {
    /** 锚定的 custom 节点。 */
    public let node: NodeRef
    /** 定义该节点的扩展 id。 */
    public let extensionId: String
    /** 扩展的语义版本。 */
    public let extensionSemanticVersion: String
    /** 扩展内的 local kind id。 */
    public let localKindId: String
    /** 扩展提供的 typed payload。 */
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
    private let lineageAllocator: NodeLineage
    private var nextLocalIdentity: Int64 = 0
    private var reservedIdentityEnd: Int64 = 0
    private var identityReservationSize: Int64 = AST_NODE_CHUNK_SIZE
    private let maximumNodes: Int64
    private let constructionBudget: ?NodeConstructionBudget
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
        initialChildCapacity!: Int64 = 16, sourceBuffer!: ?SourceBuffer = None, lineage!: ?NodeLineage = None,
        constructionBudget!: ?NodeConstructionBudget = None) {
        if (maximumNodes <= 0) {
            throw IllegalArgumentException("maximum AST nodes must be positive")
        }
        if (initialNodeCapacity < 0 || initialNodeCapacity > AST_NODE_CHUNK_SIZE || initialChildCapacity < 0 ||
            initialChildCapacity > AST_CHILD_CHUNK_SIZE) {
            throw IllegalArgumentException("initial arena capacity exceeds its chunk size")
        }
        lineageAllocator = match (lineage) {
            case Some(value) => value;
            case None => NodeLineage()
        }
        // Short append/resolver arenas share a lineage. Start with one serial
        // and grow geometrically instead of abandoning a full 4096-node range.
        if (lineage.isSome()) {
            identityReservationSize = 1
        }
        this.maximumNodes = maximumNodes
        this.constructionBudget = constructionBudget
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
        lineageAllocator = base.nodeLineage()
        identityReservationSize = 1
        constructionBudget = None
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

    /** A session owns its lineage and copies each retained node once. Storage
     * relocation preserves identity; public transforms still allocate new IDs. */
    func appendSessionNode(source: NodeRef, children: Array<Int64>, span: ?SourceSpan, payload: ArenaNodePayload,
        origin: ?NodeOrigin): Int64 {
        if (!trustedParserConstruction || source.nodeId.lineage != lineageAllocator.identity) {
            throw IllegalArgumentException("session node does not belong to the assembly lineage")
        }
        appendUnchecked(source.kind, span, source.originKind, children, payload, origin,
            preservedIdentity: Some(source.nodeId.value))
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
        payload: ArenaNodePayload, origin: ?NodeOrigin, preservedIdentity!: ?Int64 = None): Int64 {
        if (nodeCountValue >= maximumNodes) {
            throw LimitExceededException("ast_nodes", maximumNodes, nodeCountValue + 1, "ast_allocation")
        }
        if (let Some(value) <- constructionBudget) {
            value.consume()
        }
        let localIdentity = match (preservedIdentity) {
            case Some(value) => value;
            case None => allocateLocalIdentity()
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
            ArenaNodeRecord(localIdentity, kind, span, originKind, originMetadataIndex, childCountValue - children.size,
                children.size, payloadIndex))
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
        if (let Some(value) <- constructionBudget) {
            value.consume()
        }
        let localIdentity = allocateLocalIdentity()
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
            ArenaNodeRecord(localIdentity, kind, span, originKind, originMetadataIndex, childCountValue - children.size,
                children.size, payloadIndex))
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
        Document(nextDocumentRevision(), lineageAllocator, frozenNodeChunks.toArray(), frozenChildChunks.toArray(),
            payloads.toArray(), originMetadata.toArray(), nodeCountValue, childCountValue, sourceBuffer: sourceBuffer)
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
            if (nodeTail.size > retainedNodeTail) {
                nodeTail.remove(retainedNodeTail..nodeTail.size)
            }
            if (childTail.size > retainedChildTail) {
                childTail.remove(retainedChildTail..childTail.size)
            }
            if (payloads.size > checkpoint.payloadCount) {
                payloads.remove(checkpoint.payloadCount..payloads.size)
            }
            if (originMetadata.size > checkpoint.originMetadataCount) {
                originMetadata.remove(checkpoint.originMetadataCount..originMetadata.size)
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
        if (frozenNodeChunks.size > fullNodeChunks) {
            frozenNodeChunks.remove(fullNodeChunks..frozenNodeChunks.size)
        }
        nodeTail = retainedNodes
        let fullChildChunks = checkpoint.childCount / AST_CHILD_CHUNK_SIZE
        if (frozenChildChunks.size > fullChildChunks) {
            frozenChildChunks.remove(fullChildChunks..frozenChildChunks.size)
        }
        childTail = retainedChildren

        if (payloads.size > checkpoint.payloadCount) {
            payloads.remove(checkpoint.payloadCount..payloads.size)
        }
        if (originMetadata.size > checkpoint.originMetadataCount) {
            originMetadata.remove(checkpoint.originMetadataCount..originMetadata.size)
        }
        if (!trustedParserConstruction) {
            if (parentIndexes.size > checkpoint.nodeCount) {
                parentIndexes.remove(checkpoint.nodeCount..parentIndexes.size)
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
        Document(nextDocumentRevision(), lineageAllocator, frozenNodeChunks.toArray(), frozenChildChunks.toArray(),
            payloads.toArray(), originMetadata.toArray(), nodeCountValue, childCountValue, rootIndex: rootIndex,
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
        Document(nextDocumentRevision(), lineageAllocator, nodeChunks.toArray(), childChunks.toArray(),
            payloads.toArray(), originMetadata.toArray(), nodeCountValue, childCountValue, sourceBuffer: sourceBuffer)
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

    private func allocateLocalIdentity(): Int64 {
        if (nextLocalIdentity == reservedIdentityEnd) {
            let (start, end) = lineageAllocator.reserve(requested: identityReservationSize)
            nextLocalIdentity = start
            reservedIdentityEnd = end
            identityReservationSize = min(AST_NODE_CHUNK_SIZE, identityReservationSize * 2)
        }
        let identity = nextLocalIdentity
        nextLocalIdentity++
        identity
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
        ArenaNodeRecord(previous.localIdentity, kind, span, originKind, originMetadataIndex, previous.firstChild,
            previous.childCount, payloadIndex)
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
