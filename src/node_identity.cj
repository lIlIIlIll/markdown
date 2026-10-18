package markdown

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

// Persistent forks share only this allocation sequence, never mutable arena
// records. Each session reserves a range once per chunk and allocates locally.
// Rollback deliberately does not rewind either reservation or local serial.
internal class NodeLineage {
    let identity: Int64
    private let serials = AtomicInt64(1)

    init() {
        identity = reserveIdentityRange(NEXT_NODE_LINEAGE, 1, Int64.Max - 1)[0]
    }

    func reserve(): (Int64, Int64) {
        reserveIdentityRange(serials, AST_NODE_CHUNK_SIZE, Int64(UInt32.Max))
    }
}
