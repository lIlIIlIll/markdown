package markdown.engine

import markdown.core.{CancellationToken, LimitExceededException, OperationBudget, SourceSpan}
import markdown.extensions.BlockSyntaxRule
import std.collection.*

internal class PendingDefinitionBody {
    protected let lines: Array<LineRecord>
    protected let span: SourceSpan
    protected let markerSpan: SourceSpan
    init(lines: Array<LineRecord>, span: SourceSpan, markerSpan: SourceSpan) {
        this.lines = lines
        this.span = span
        this.markerSpan = markerSpan
    }
}

internal class PendingDefinitionEntry {
    protected let terms: Array<LineRecord>
    protected let definitions: Array<PendingDefinitionBody>
    protected let span: SourceSpan
    init(terms: Array<LineRecord>, definitions: Array<PendingDefinitionBody>, span: SourceSpan) {
        this.terms = terms
        this.definitions = definitions
        this.span = span
    }
}

internal class PendingDefinitionList {
    protected let rule: BlockSyntaxRule
    protected let entries: Array<PendingDefinitionEntry>
    protected let span: SourceSpan
    let nextIndex: Int64
    protected let nodes = ArrayList<Int64>()
    let entryNodes = ArrayList<Int64>()
    var entryIndex: Int64 = 0
    protected var definitionIndex: Int64 = 0
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
