package markdown.core

import std.sync.AtomicInt64

private let NEXT_NODE_LINEAGE = AtomicInt64(1)
private let NEXT_DOCUMENT_REVISION = AtomicInt64(1)

// The exclusive upper bound is representable even when every usable identity
// has been consumed. Exhaustion never wraps or reuses a prior identity.
private func reserveIdentityRange(sequence: AtomicInt64, requested: Int64, limit: Int64): (Int64, Int64) {
    var first: Int64 = 0
    var end: Int64 = 0
    while (first == 0) {
        let start = sequence.load()
        if (start > limit) {
            throw MarkdownException(MarkdownErrorCode.LimitExceeded, "node identity space exhausted",
                phase: "ast_identity")
        }
        let count = min(requested, limit - start + 1)
        if (sequence.compareAndSwap(start, start + count)) {
            first = start
            end = start + count
        }
    }
    (first, end)
}

internal func nextDocumentRevision(): Int64 {
    reserveIdentityRange(NEXT_DOCUMENT_REVISION, 1, Int64.Max - 1)[0]
}

// Mix both identity components before power-of-two hash-table indexing. A
// sparse serial stride must not turn fragment lookup into long bucket chains.
@OverflowWrapping
internal func nodeIdentityHash(lineage: Int64, serial: Int64): Int64 {
    var value = UInt64(lineage) * 0x9E3779B97F4A7C15 ^ UInt64(serial)
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9
    value = (value ^ (value >> 27)) * 0x94D049BB133111EB
    value = value ^ (value >> 31)
    Int64(value & 0x7FFFFFFFFFFFFFFF)
}

// Persistent forks share only this allocation sequence, never mutable arena
// records. Builders reserve bounded ranges and allocate locally within them.
// Rollback deliberately does not rewind either reservation or local serial.
/** 持久化文档分叉共享的节点编号分配器；不共享可变 arena 记录。 */
protected class NodeLineage {
    /** 进程内唯一的正数 lineage 标识；独立解析和完整重解析不会复用。 */
    protected let identity: Int64
    private let serials = AtomicInt64(1)

    /** 分配全新的 lineage；身份空间耗尽时以 LimitExceeded 失败。 */
    protected init() {
        identity = reserveIdentityRange(NEXT_NODE_LINEAGE, 1, Int64.Max - 1)[0]
    }

    /** 原子预留一段局部编号；回滚不会回收，耗尽时失败而不回绕。
     * @param requested 请求的编号数，默认为一个节点 chunk，必须在 1 到 AST_NODE_CHUNK_SIZE 之间。
     * @return 预留区间的起点和不包含的终点；末段可能短于请求，编号不超过 UInt32.Max。
     */
    protected func reserve(requested!: Int64 = AST_NODE_CHUNK_SIZE): (Int64, Int64) {
        if (requested <= 0 || requested > AST_NODE_CHUNK_SIZE) {
            throw IllegalArgumentException("identity reservation must fit one arena chunk")
        }
        reserveIdentityRange(serials, requested, Int64(UInt32.Max))
    }
}
