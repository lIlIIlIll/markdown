package markdown

import std.collection.*
import std.unittest.*

private func hasEventKind(events: Array<MarkdownSourceEvent>, kind: MarkdownSourceEventKind): Bool {
    for (event in events) {
        if (sameEventKind(event.kind, kind)) {
            return true
        }
    }
    false
}

private func hasTextValue(events: Array<MarkdownSourceEvent>, value: String): Bool {
    for (event in events) {
        if (let Some(text) <- event.semanticValue) {
            if (text == value) {
                return true
            }
        }
    }
    false
}

private func linkDestination(events: Array<MarkdownSourceEvent>): ?String {
    for (event in events) {
        if (let MarkdownSourceEventKind.InlineStart <- event.kind) {
            if (!isLinkKind(event.nodeKind)) {
                continue
            }
            for (attribute in event.attributes.toArray()) {
                if (attribute.name == "destination") {
                    return Some(attribute.value)
                }
            }
        }
    }
    None
}

private func isLinkKind(value: ?NodeKind): Bool {
    if (let Some(NodeKind.Link) <- value) {
        true
    } else {
        false
    }
}

private func sameEventKind(left: MarkdownSourceEventKind, right: MarkdownSourceEventKind): Bool {
    match (left) {
        case MarkdownSourceEventKind.DocumentStart =>
            if (let MarkdownSourceEventKind.DocumentStart <- right) {
                true
            } else {
                false
            }
        case MarkdownSourceEventKind.DocumentEnd =>
            if (let MarkdownSourceEventKind.DocumentEnd <- right) {
                true
            } else {
                false
            }
        case MarkdownSourceEventKind.BlockStart =>
            if (let MarkdownSourceEventKind.BlockStart <- right) {
                true
            } else {
                false
            }
        case MarkdownSourceEventKind.BlockEnd =>
            if (let MarkdownSourceEventKind.BlockEnd <- right) {
                true
            } else {
                false
            }
        case MarkdownSourceEventKind.InlineStart =>
            if (let MarkdownSourceEventKind.InlineStart <- right) {
                true
            } else {
                false
            }
        case MarkdownSourceEventKind.InlineEnd =>
            if (let MarkdownSourceEventKind.InlineEnd <- right) {
                true
            } else {
                false
            }
        case MarkdownSourceEventKind.Text =>
            if (let MarkdownSourceEventKind.Text <- right) {
                true
            } else {
                false
            }
    }
}

private func expectSameEventSequence(left: Array<MarkdownSourceEvent>, right: Array<MarkdownSourceEvent>): Unit {
    @Expect(left.size, right.size)
    for (index in 0..left.size) {
        @Expect(sameEventKind(left[index].kind, right[index].kind), true)
        @Expect(eventNodeKindOrdinal(left[index].nodeKind), eventNodeKindOrdinal(right[index].nodeKind))
        @Expect(left[index].sourceRange, right[index].sourceRange)
        @Expect(left[index].textSourceRange, right[index].textSourceRange)
        @Expect(left[index].semanticValue, right[index].semanticValue)
        @Expect(left[index].finalSemantics, right[index].finalSemantics)
        let leftAttributes = left[index].attributes.toArray()
        let rightAttributes = right[index].attributes.toArray()
        @Expect(leftAttributes.size, rightAttributes.size)
        for (attributeIndex in 0..leftAttributes.size) {
            @Expect(leftAttributes[attributeIndex].name, rightAttributes[attributeIndex].name)
            @Expect(leftAttributes[attributeIndex].value, rightAttributes[attributeIndex].value)
        }
    }
}

private func eventNodeKindOrdinal(kind: ?NodeKind): Int64 {
    match (kind) {
        case None => -1
        case Some(NodeKind.DocumentNode) => 0
        case Some(NodeKind.BlockQuote) => 1
        case Some(NodeKind.List) => 2
        case Some(NodeKind.ListItem) => 3
        case Some(NodeKind.Paragraph) => 4
        case Some(NodeKind.Heading) => 5
        case Some(NodeKind.ThematicBreak) => 6
        case Some(NodeKind.CodeBlock) => 7
        case Some(NodeKind.HtmlBlock) => 8
        case Some(NodeKind.Table) => 9
        case Some(NodeKind.TableRow) => 10
        case Some(NodeKind.TableCell) => 11
        case Some(NodeKind.CustomBlock) => 12
        case Some(NodeKind.Text) => 13
        case Some(NodeKind.SoftBreak) => 14
        case Some(NodeKind.HardBreak) => 15
        case Some(NodeKind.CodeSpan) => 16
        case Some(NodeKind.Emphasis) => 17
        case Some(NodeKind.Strong) => 18
        case Some(NodeKind.Strikethrough) => 19
        case Some(NodeKind.Link) => 20
        case Some(NodeKind.Image) => 21
        case Some(NodeKind.HtmlInline) => 22
        case Some(NodeKind.CustomInline) => 23
    }
}

private func collectRawSessionEvents(engine: MarkdownEngine, bytes: Array<Byte>, chunkWidths: Array<Int64>): Array<MarkdownSourceEvent> {
    let session = engine.newRawBlockEventSession()
    let out = ArrayList<MarkdownSourceEvent>()
    var offset: Int64 = 0
    var chunkIndex: Int64 = 0
    while (offset < bytes.size) {
        let width = chunkWidths[chunkIndex % chunkWidths.size]
        let end = min(bytes.size, offset + width)
        out.add(all: session.feed(bytes[offset..end]))
        offset = end
        chunkIndex++
    }
    out.add(all: session.finish())
    out.toArray()
}

private func collectRawSessionEventsByLine(engine: MarkdownEngine, bytes: Array<Byte>): Array<MarkdownSourceEvent> {
    let session = engine.newRawBlockEventSession()
    let out = ArrayList<MarkdownSourceEvent>()
    var lineStart: Int64 = 0
    var index: Int64 = 0
    while (index < bytes.size) {
        if (bytes[index] == b'\n') {
            out.add(all: session.feed(bytes[lineStart..index + 1]))
            lineStart = index + 1
        }
        index++
    }
    if (lineStart < bytes.size) {
        out.add(all: session.feed(bytes[lineStart..]))
    }
    out.add(all: session.finish())
    out.toArray()
}

private func rawSessionEmitsHtmlBlockBeforeFinish(engine: MarkdownEngine, bytes: Array<Byte>, chunkWidths: Array<Int64>): Bool {
    let session = engine.newRawBlockEventSession()
    var offset: Int64 = 0
    var chunkIndex: Int64 = 0
    var emitted = false
    while (offset < bytes.size) {
        let width = chunkWidths[chunkIndex % chunkWidths.size]
        let end = min(bytes.size, offset + width)
        if (eventSequenceHasNodeKind(session.feed(bytes[offset..end]), NodeKind.HtmlBlock)) {
            emitted = true
        }
        offset = end
        chunkIndex++
    }
    emitted
}

private class CountingEventSink <: MarkdownEventSink {
    var count: Int64 = 0
    var sawDocument: Bool = false

    public func onEvent(event: MarkdownSourceEvent): Unit {
        count++
        if (let Some(NodeKind.DocumentNode) <- event.nodeKind) {
            sawDocument = true
        }
    }
}

private class CancelOnRawBlockScanCheckpoint <: RawBlockScanCheckpointObserver {
    private let cancellation: CancellationSource
    private let targetPhase: String
    var observedBytes: Int64 = -1
    var checkpoints: Int64 = 0

    init(cancellation: CancellationSource, targetPhase: String) {
        this.cancellation = cancellation
        this.targetPhase = targetPhase
    }

    public func onRawBlockScanCheckpoint(phase: String, bytesProcessed: Int64): Unit {
        checkpoints++
        if (phase == targetPhase && observedBytes < 0) {
            observedBytes = bytesProcessed
            cancellation.cancel()
        }
    }
}

private func isCancelled(error: MarkdownException): Bool {
    match (error.code) {
        case MarkdownErrorCode.Cancelled => true
        case _ => false
    }
}

@Test
class SourceEventApiTest {
    @TestCase
    func looseListLineFeedsKeepEventsExactAndScanGrowthLinear(): Unit {
        let engine = MarkdownEngine.builder().build()
        var previousSteps: Int64 = 0
        for (count in [64, 128]) {
            let text = StringBuilder()
            for (_ in 0..count) {
                text.append("- item\n\n  paragraph\n\n")
            }
            let input = text.toString()
            let bytes = input.toArray()
            let budget = OperationBudget.safe()
            let session = engine.newRawBlockEventSession(budget: budget)
            let events = ArrayList<MarkdownSourceEvent>()
            var start: Int64 = 0
            for (index in 0..bytes.size) {
                if (bytes[index] == b'\n') {
                    events.add(all: session.feed(bytes[start..index + 1]))
                    start = index + 1
                }
            }
            events.add(all: session.finish())
            expectSameEventSequence(events.toArray(), collectRawSessionEvents(engine, bytes, [bytes.size]))
            @Expect(budget.usedScanSteps() <= bytes.size * 32, true)
            if (previousSteps > 0) {
                @Expect(budget.usedScanSteps() <= previousSteps * 3, true)
            }
            previousSteps = budget.usedScanSteps()
        }
    }

    @TestCase
    func resolvedModeUsesReferenceIndexBeforeSemanticEvents(): Unit {
        let result = MarkdownEngine.builder().build().parseEvents("[label][id]\n\n[id]: /target \"title\"\n")
        let events = result.events.toArray()
        @Expect(sameEventKind(events[0].kind, MarkdownSourceEventKind.DocumentStart), true)
        @Expect(sameEventKind(events[events.size - 1].kind, MarkdownSourceEventKind.DocumentEnd), true)
        @Expect(linkDestination(events), Some("/target"))
        for (event in events) {
            @Expect(event.finalSemantics, true)
        }
    }

    @TestCase
    func rawModeDoesNotClaimResolvedReferenceSemantics(): Unit {
        let result = MarkdownEngine
            .builder()
            .build()
            .parseEvents("[label][id]\n", mode: MarkdownEventMode.RawBlockEventMode)
        let events = result.events.toArray()
        @Expect(linkDestination(events).isNone(), true)
        @Expect(hasTextValue(events, "[label][id]"), true)
        for (event in events) {
            @Expect(event.finalSemantics, false)
        }
    }

    @TestCase
    func rawSessionEmitsClosedParagraphBeforeFinish(): Unit {
        let session = MarkdownEngine.builder().build().newRawBlockEventSession()
        let first = session.feed("first\n\nsecond")
        @Expect(sameEventKind(first[0].kind, MarkdownSourceEventKind.DocumentStart), true)
        @Expect(hasTextValue(first, "first"), true)
        @Expect(hasTextValue(first, "second"), false)

        let second = session.feed("\n\n")
        @Expect(hasTextValue(second, "second"), true)
        @Expect(hasEventKind(second, MarkdownSourceEventKind.DocumentEnd), false)

        let finalEvents = session.finish()
        @Expect(sameEventKind(finalEvents[finalEvents.size - 1].kind, MarkdownSourceEventKind.DocumentEnd), true)
    }

    @TestCase
    func eventRangesAndStartEndPairsRemainBalanced(): Unit {
        let events = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm())
            .build()
            .parseEvents("# 标题\n\nA *strong* value\n")
            .events
            .toArray()
        var blocks: Int64 = 0
        var inlines: Int64 = 0
        for (event in events) {
            match (event.kind) {
                case MarkdownSourceEventKind.BlockStart => blocks++
                case MarkdownSourceEventKind.BlockEnd => blocks--
                case MarkdownSourceEventKind.InlineStart => inlines++
                case MarkdownSourceEventKind.InlineEnd => inlines--
                case _ => ()
            }
            @Expect(blocks >= 0, true)
            @Expect(inlines >= 0, true)
            if (let Some(span) <- event.sourceRange) {
                @Expect(span.startByte <= span.endByte, true)
            }
        }
        @Expect(blocks, 0)
        @Expect(inlines, 0)
    }

    @TestCase
    func rawSessionRejectsUseAfterFinish(): Unit {
        let session = MarkdownEngine.builder().build().newRawBlockEventSession()
        let _ = session.finish()
        @ExpectThrows[IllegalStateException](session.feed("later"))
        @ExpectThrows[IllegalStateException](session.finish())
    }

    @TestCase
    func rawSessionStringFeedPreflightsBeforeScanningOrBuffering(): Unit {
        let large = StringBuilder()
        for (_ in 0..8192) {
            large.append("x")
        }
        let source = large.toString()

        let finishedCancellation = CancellationSource()
        let finishedObserver = CancelOnRawBlockScanCheckpoint(finishedCancellation, "line_validation")
        let finished = RawBlockEventSession(MarkdownEngine.builder().build(), Utf8Policy.Strict,
            finishedCancellation.token, OperationBudget.safe(), scanCheckpointObserver: Some(finishedObserver))
        let _ = finished.finish()
        @ExpectThrows[IllegalStateException](finished.feed(source))
        @Expect(finishedObserver.checkpoints, 0)

        let cancelledSource = CancellationSource()
        let cancelledObserver = CancelOnRawBlockScanCheckpoint(cancelledSource, "line_validation")
        let cancelled = RawBlockEventSession(MarkdownEngine.builder().build(), Utf8Policy.Strict, cancelledSource.token,
            OperationBudget.safe(), scanCheckpointObserver: Some(cancelledObserver))
        cancelledSource.cancel()
        var sawCancelled = false
        try {
            let _ = cancelled.feed(source)
        } catch (error: MarkdownException) {
            sawCancelled = isCancelled(error)
            @Expect(error.phase, "input")
        }
        @Expect(sawCancelled, true)
        @Expect(cancelledObserver.checkpoints, 0)

        let limits = ParseLimits(1, 1024, 16, 128, 16, 16, 1024, 1024, 4096, 1024, 1024)
        let limitedCancellation = CancellationSource()
        let limitedObserver = CancelOnRawBlockScanCheckpoint(limitedCancellation, "line_validation")
        let limited = RawBlockEventSession(MarkdownEngine.builder().limits(limits).build(), Utf8Policy.Strict,
            limitedCancellation.token, OperationBudget.safe(), scanCheckpointObserver: Some(limitedObserver))
        var sawLimit = false
        try {
            let _ = limited.feed(source)
        } catch (error: LimitExceededException) {
            sawLimit = true
            @Expect(error.limitKind, "input_bytes")
            @Expect(error.configuredLimit, 1)
            @Expect(error.observedValue, source.size)
        }
        @Expect(sawLimit, true)
        @Expect(limitedObserver.checkpoints, 0)
        let accepted = limited.feed("a")
        @Expect(hasTextValue(accepted, source), false)
        let finalEvents = limited.finish()
        @Expect(hasTextValue(finalEvents, "a"), true)
        @Expect(hasTextValue(finalEvents, source), false)
    }

    @TestCase
    func rawSessionCancellationIsBoundedInBothInputScansAndRemainsTerminal(): Unit {
        let bytes = Array<Byte>(4096, repeat: b'a')
        for (targetPhase in ["line_validation", "append_scan"]) {
            let cancellation = CancellationSource()
            let observer = CancelOnRawBlockScanCheckpoint(cancellation, targetPhase)
            let session = RawBlockEventSession(MarkdownEngine.builder().build(), Utf8Policy.Strict, cancellation.token,
                OperationBudget.safe(), scanCheckpointObserver: Some(observer))
            var sawCancelled = false
            try {
                let _ = session.feed(bytes)
            } catch (error: MarkdownException) {
                sawCancelled = isCancelled(error)
                @Expect(error.phase, "input")
            }
            @Expect(sawCancelled, true)
            @Expect(observer.observedBytes, 1024)

            var feedRemainsCancelled = false
            try {
                let events = session.feed("later\n\n")
                @Expect(events.size, 0)
            } catch (error: MarkdownException) {
                feedRemainsCancelled = isCancelled(error)
                @Expect(error.phase, "input")
            }
            @Expect(feedRemainsCancelled, true)

            var finishRemainsCancelled = false
            try {
                let events = session.finish()
                @Expect(events.size, 0)
            } catch (error: MarkdownException) {
                finishRemainsCancelled = isCancelled(error)
                @Expect(error.phase, "input")
            }
            @Expect(finishRemainsCancelled, true)
        }
    }

    @TestCase
    func directSinkAndCumulativeNodeLimitUsePublicContracts(): Unit {
        let sink = CountingEventSink()
        let summary = MarkdownEngine.builder().build().emitEvents("one\n\ntwo\n", sink)
        @Expect(summary.emittedEvents, sink.count)
        @Expect(sink.sawDocument, true)

        let nodeLimited = ParseLimits(1024, 1024, 16, 3, 16, 16, 1024, 1024, 4096, 1024, 1024)
        let engine = MarkdownEngine.builder().limits(nodeLimited).build()
        @ExpectThrows[LimitExceededException](engine.parseEvents("one\n\ntwo\n"))
    }

    @TestCase
    func rawSessionBuffersSplitUtf8UntilACompleteLine(): Unit {
        let session = MarkdownEngine.builder().build().newRawBlockEventSession()
        let bytes = "你好\n\n".toArray()
        let first = session.feed(bytes[..1])
        @Expect(hasTextValue(first, "你好"), false)
        let second = session.feed(bytes[1..])
        @Expect(hasTextValue(second, "你好"), true)
        let finalEvents = session.finish()
        @Expect(hasEventKind(finalEvents, MarkdownSourceEventKind.DocumentEnd), true)
    }

    @TestCase
    func rawSessionOneByteChunksMatchWholeChunkAcrossCrLfAndUtf8(): Unit {
        let engine = MarkdownEngine.builder().build()
        let bytes = "first\r\n\r\n你好 *world*\r\n\r\n```cj\r\nvalue\r\n```\r\n".toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let bytewise = collectRawSessionEvents(engine, bytes, [1])
        expectSameEventSequence(bytewise, whole)
    }

    @TestCase
    func rawSessionUnclosedFenceCandidateLinesAreChunkInvariant(): Unit {
        let engine = MarkdownEngine.builder().build()
        let bytes = "```cj\r\n# 候选\r\n---\r\n~~~\r\n`` nope\r\n\r\n😀 `value`\r\n".toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let bytewise = collectRawSessionEvents(engine, bytes, [1])
        let byLine = collectRawSessionEventsByLine(engine, bytes)
        expectSameEventSequence(bytewise, whole)
        expectSameEventSequence(byLine, whole)
        @Expect(hasTextValue(whole, "# 候选\n---\n~~~\n`` nope\n\n😀 `value`\n"), true)
    }

    @TestCase
    func rawSessionChunkPartitionDifferentialPreservesEventsAndSpans(): Unit {
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfm()).build()
        let bytes = "# head\n\n| a | b |\n| - | - |\n| 你 | 😀 |\n\nlast".toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let partitioned = collectRawSessionEvents(engine, bytes, [1, 2, 5, 3, 8])
        expectSameEventSequence(partitioned, whole)
    }

    @TestCase
    func rawSessionRejectsOverlongUnclosedLineDuringFeed(): Unit {
        let limits = ParseLimits(1024, 4, 16, 128, 16, 16, 1024, 1024, 4096, 1024, 1024)
        let budget = OperationBudget(1024, 1024, 16, 16, 128, 4096)
        let session = MarkdownEngine.builder().limits(limits).build().newRawBlockEventSession(budget: budget)
        let _ = session.feed("abcd")
        var rejected = false
        try {
            let _ = session.feed("e")
        } catch (error: LimitExceededException) {
            rejected = true
            @Expect(error.limitKind, "line_bytes")
            @Expect(error.configuredLimit, 4)
            @Expect(error.observedValue, 5)
            @Expect(error.span, Some(SourceSpan(0, 5)))
        }
        @Expect(rejected, true)
        @Expect(budget.usedScanSteps(), 4)
    }

    @TestCase
    func rawSessionMetersOnlyNewBytesForFineGrainedUnclosedInput(): Unit {
        let scanBytes: Int64 = 2048
        let budget = OperationBudget(scanBytes, 1024, 16, 16, 128, 4096)
        let session = MarkdownEngine.builder().build().newRawBlockEventSession(budget: budget)
        for (_ in 0..scanBytes) {
            let events = session.feed([b'a'])
            @Expect(hasTextValue(events, "a"), false)
        }
        @Expect(budget.usedScanSteps(), scanBytes)
        @ExpectThrows[MarkdownException](session.feed([b'a']))
    }

    @TestCase
    func rawSessionUnclosedFenceCandidateLinesHaveLinearMeteredWork(): Unit {
        let input = StringBuilder()
        input.append("```cj\n")
        for (_ in 0..256) {
            input.append("# candidate\n---\n~~~\n`` nope\n\n")
        }
        let bytes = input.toString().toArray()
        let linearLimit = bytes.size * 5
        let budget = OperationBudget(linearLimit, 1024, 16, 16, 128, 4096)
        let session = MarkdownEngine.builder().build().newRawBlockEventSession(budget: budget)
        var start: Int64 = 0
        var index: Int64 = 0
        while (index < bytes.size) {
            if (bytes[index] == b'\n') {
                let _ = session.feed(bytes[start..index + 1])
                start = index + 1
            }
            index++
        }
        if (start < bytes.size) {
            let _ = session.feed(bytes[start..])
        }
        let _ = session.finish()
        @Expect(budget.usedScanSteps() <= bytes.size * 4, true)
    }

    @TestCase
    func rawSessionAtxBoundaryPreservesEarlyClosureAndChunkParity(): Unit {
        let engine = MarkdownEngine.builder().build()
        for (heading in ["#\n", "# heading\n", "###### heading\n", "######\theading\n"]) {
            let session = engine.newRawBlockEventSession()
            let _ = session.feed("paragraph\n")
            let closed = session.feed(heading)
            @Expect(eventSequenceHasNodeKind(closed, NodeKind.Paragraph), true)
            @Expect(eventSequenceHasNodeKind(closed, NodeKind.Heading), true)
        }

        for (source in [
            "paragraph\n#x\n\n",
            "paragraph\n####### heading\n\n",
            "paragraph\n#######\n\n",
            "paragraph\n\\# heading\n\n",
            "paragraph\n    # heading\n\n"
        ]) {
            let bytes = source.toArray()
            let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
            let byLine = collectRawSessionEventsByLine(engine, bytes)
            let bytewise = collectRawSessionEvents(engine, bytes, [1])
            expectSameEventSequence(byLine, whole)
            expectSameEventSequence(bytewise, whole)
        }
    }

    @TestCase
    func rawSessionHashTextStormDoesNotReparseTheRetainedParagraph(): Unit {
        let lineCount: Int64 = 2048
        let budget = OperationBudget(lineCount * 64, 1024, 16, 16, 65536, 1024 * 1024)
        let engine = MarkdownEngine.builder().build()
        let session = engine.newRawBlockEventSession(budget: budget)
        let first = session.feed("a\n")
        @Expect(hasEventKind(first, MarkdownSourceEventKind.DocumentStart), true)
        for (_ in 0..lineCount) {
            let before = budget.usedScanSteps()
            let events = session.feed("#x\n")
            @Expect(events.size, 0)
            // Only the three newly appended bytes are scanned. A semantic
            // retained-tail parse here would make this delta grow per line.
            @Expect(budget.usedScanSteps() - before, 3)
        }
        @Expect(budget.usedScanSteps(), 2 + lineCount * 3)
        let finalEvents = session.finish()
        @Expect(eventSequenceHasNodeKind(finalEvents, NodeKind.Paragraph), true)

        let source = StringBuilder()
        source.append("a\n")
        for (_ in 0..lineCount) {
            source.append("#x\n")
        }
        source.append("\n")
        let bytes = source.toString().toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let byLine = collectRawSessionEventsByLine(engine, bytes)
        let bytewise = collectRawSessionEvents(engine, bytes, [1])
        expectSameEventSequence(byLine, whole)
        expectSameEventSequence(bytewise, whole)
    }

    @TestCase
    func rawSessionFalseFenceMarkersRemainLinearAndTrueFencesCloseEarly(): Unit {
        let engine = MarkdownEngine.builder().build()
        for (fence in ["```cj\n", "~~~cj\n"]) {
            let session = engine.newRawBlockEventSession()
            let _ = session.feed("paragraph\n")
            let closed = session.feed(fence)
            @Expect(eventSequenceHasNodeKind(closed, NodeKind.Paragraph), true)
        }

        for (line in ["`x\n", "~x\n", "`` nope\n", "~~ nope\n"]) {
            let lineCount: Int64 = 2048
            let budget = OperationBudget(lineCount * line.size * 4, 1024, 16, 16, 65536, 1024 * 1024)
            let session = engine.newRawBlockEventSession(budget: budget)
            let _ = session.feed("a\n")
            for (_ in 0..lineCount) {
                let before = budget.usedScanSteps()
                let events = session.feed(line)
                @Expect(events.size, 0)
                @Expect(budget.usedScanSteps() - before, line.size)
            }
            let _ = session.finish()

            let source = StringBuilder()
            source.append("a\n")
            for (_ in 0..lineCount) {
                source.append(line)
            }
            source.append("\n")
            let bytes = source.toString().toArray()
            let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
            let byLine = collectRawSessionEventsByLine(engine, bytes)
            let bytewise = collectRawSessionEvents(engine, bytes, [1])
            expectSameEventSequence(byLine, whole)
            expectSameEventSequence(bytewise, whole)
        }
    }

    @TestCase
    func rawSessionEnforcesHtmlLiteralLimitsForTypesOneThroughSevenDuringFeed(): Unit {
        for (opener in ["<script>\n", "<!--\n", "<?x\n", "<!A\n", "<![CDATA[\n", "<div>\n", "<span>\n"]) {
            // Explicitly terminated types 1-5 retain a trailing normalized LF
            // while still open. Blank-terminated types 6-7 exclude it.
            let literalBytes = if (opener == "<div>\n" || opener == "<span>\n") {
                opener.size - 1
            } else {
                opener.size
            }
            let engine = rawLiteralLimitEngine(literalBytes)
            let session = engine.newRawBlockEventSession()
            let openingEvents = session.feed(opener)
            @Expect(eventSequenceHasNodeKind(openingEvents, NodeKind.HtmlBlock), false)

            // The first byte of the next semantic line first materializes the
            // normalized LF. Repeating a rejected feed must report the same
            // value rather than retaining source or billing it twice.
            for (_ in 0..2) {
                var rejected = false
                try {
                    let _ = session.feed("x\n")
                } catch (error: LimitExceededException) {
                    rejected = true
                    expectRawLiteralLimit(error, literalBytes, literalBytes + 1)
                }
                @Expect(rejected, true)
            }

            let finalEvents = session.finish()
            @Expect(eventSequenceHasNodeKind(finalEvents, NodeKind.HtmlBlock), true)
            let clean = collectRawSessionEvents(engine, opener.toArray(), [1])
            let actual = ArrayList<MarkdownSourceEvent>()
            actual.add(all: openingEvents)
            actual.add(all: finalEvents)
            expectSameEventSequence(actual.toArray(), clean)
        }
    }

    @TestCase
    func rawSessionLiteralAccountingMatchesBatchNormalizationAndChunking(): Unit {
        let exactCases = [
            ("<script>\r\nx\r\n</script>\r\n", 20),
            ("<div>\r\nx\r\n\r\n", 7),
            ("<span>\r\nx\r\n\r\n", 8),
            ("\t1234\r\n    567\r\n", 8)
        ]
        for ((source, maximum) in exactCases) {
            let engine = rawLiteralLimitEngine(maximum)
            let bytes = source.toArray()
            let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
            let byLine = collectRawSessionEventsByLine(engine, bytes)
            let bytewise = collectRawSessionEvents(engine, bytes, [1])
            expectSameEventSequence(byLine, whole)
            expectSameEventSequence(bytewise, whole)
        }

        // A whitespace-only line closes HTML types 6/7 and is excluded from
        // their literal even while the line is still unfinished.
        let blankClosedHtml = "<div>\r\n   \r\n".toArray()
        let blankWhole = collectRawSessionEvents(rawLiteralLimitEngine(5), blankClosedHtml, [blankClosedHtml.size])
        let blankBytewise = collectRawSessionEvents(rawLiteralLimitEngine(5), blankClosedHtml, [1])
        expectSameEventSequence(blankBytewise, blankWhole)

        let htmlOver = "<script>\r\nx\r\n</script>\r\n".toArray()
        expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(19), htmlOver, [htmlOver.size], 19, 20)
        expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(19), htmlOver, [10, 3, 11], 19, 20)
        expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(19), htmlOver, [1], 19, 20)

        let indentedOver = "\t1234\r\n    5678\r\n".toArray()
        expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(8), indentedOver, [indentedOver.size], 8, 9)
        expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(8), indentedOver, [7, 10], 8, 9)
        expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(8), indentedOver, [1], 8, 9)
    }

    @TestCase
    func rawSessionRejectsUnfinishedHtmlIndentedAndFenceLiteralsDuringFeed(): Unit {
        let cases = [
            ("<script>x", 8, 9),
            ("    12345", 4, 5),
            ("```\n12345", 4, 5)
        ]
        for ((source, maximum, observed) in cases) {
            let bytes = source.toArray()
            expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(maximum), bytes, [bytes.size], maximum, observed)
            expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(maximum), bytes, [3, 2, 5], maximum, observed)
            expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(maximum), bytes, [1], maximum, observed)
        }
    }

    @TestCase
    func rawSessionRejectsCrossLineAccumulatedHtmlIndentedAndFenceLiterals(): Unit {
        let cases = [
            ("<script>\r\n1234\r\n5678", 14, 15),
            ("    1234\r\n    5678", 8, 9),
            ("```\r\n1234\r\n5678", 8, 9)
        ]
        for ((source, maximum, observed) in cases) {
            let bytes = source.toArray()
            expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(maximum), bytes, [bytes.size], maximum, observed)
            expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(maximum), bytes, [7, 4, 9], maximum, observed)
            expectRawLiteralLimitWithChunks(rawLiteralLimitEngine(maximum), bytes, [1], maximum, observed)
        }
    }

    @TestCase
    func rawSessionUnfinishedLiteralRejectionAllowsDeterministicRetry(): Unit {
        let fenceEngine = rawLiteralLimitEngine(4)
        let fence = fenceEngine.newRawBlockEventSession()
        let fenceEvents = ArrayList<MarkdownSourceEvent>()
        fenceEvents.add(all: fence.feed("```\n"))
        for (_ in 0..2) {
            var rejected = false
            try {
                let _ = fence.feed("12345")
            } catch (error: LimitExceededException) {
                rejected = true
                expectRawLiteralLimit(error, 4, 5)
            }
            @Expect(rejected, true)
        }
        fenceEvents.add(all: fence.feed("123\n```\n"))
        fenceEvents.add(all: fence.finish())
        expectSameEventSequence(fenceEvents.toArray(),
            collectRawSessionEvents(fenceEngine, "```\n123\n```\n".toArray(), [1]))

        let htmlEngine = rawLiteralLimitEngine(8)
        let html = htmlEngine.newRawBlockEventSession()
        for (_ in 0..2) {
            var rejected = false
            try {
                let _ = html.feed("<script>x")
            } catch (error: LimitExceededException) {
                rejected = true
                expectRawLiteralLimit(error, 8, 9)
            }
            @Expect(rejected, true)
        }
        let htmlActual = ArrayList<MarkdownSourceEvent>()
        htmlActual.add(all: html.feed("<script>"))
        htmlActual.add(all: html.finish())
        expectSameEventSequence(htmlActual.toArray(), collectRawSessionEvents(htmlEngine, "<script>".toArray(), [1]))

        let indentedEngine = rawLiteralLimitEngine(4)
        let indented = indentedEngine.newRawBlockEventSession()
        for (_ in 0..2) {
            var rejected = false
            try {
                let _ = indented.feed("    12345")
            } catch (error: LimitExceededException) {
                rejected = true
                expectRawLiteralLimit(error, 4, 5)
            }
            @Expect(rejected, true)
        }
        let accepted = "    1234"
        let indentedActual = ArrayList<MarkdownSourceEvent>()
        indentedActual.add(all: indented.feed(accepted))
        indentedActual.add(all: indented.finish())
        expectSameEventSequence(indentedActual.toArray(), collectRawSessionEvents(indentedEngine, accepted.toArray(),
            [1]))
    }

    @TestCase
    func rawSessionLiteralRejectionRollsBackPendingAndLexicalState(): Unit {
        let engine = rawLiteralLimitEngine(8)
        let session = engine.newRawBlockEventSession()
        var rejected = false
        try {
            let _ = session.feed("    123456789\n")
        } catch (error: LimitExceededException) {
            rejected = true
            expectRawLiteralLimit(error, 8, 9)
        }
        @Expect(rejected, true)

        let accepted = "\t12345678\n"
        let actual = ArrayList<MarkdownSourceEvent>()
        actual.add(all: session.feed(accepted))
        actual.add(all: session.finish())
        let clean = collectRawSessionEvents(engine, accepted.toArray(), [accepted.size])
        expectSameEventSequence(actual.toArray(), clean)
    }

    @TestCase
    func rawSessionHtmlBlockTypesAreChunkInvariant(): Unit {
        let engine = MarkdownEngine.builder().build()
        for (source in [
            "<SCRIPT>\r\n\r\n你好 😀\r\n</ScRiPt>\r\nafter\r\n\r\n",
            "<script >\n\nvalue\n</script>\nafter\n\n",
            "<script>\n\nvalue\n</script>\nafter\n\n",
            "<script\t>\n\nvalue\n</script>\nafter\n\n",
            "<script\n\nvalue\n</script>\nafter\n\n",
            "<!--\n\nvalue\n-->\nafter\n\n",
            "<?target\n\nvalue\n?>\nafter\n\n",
            "<!DOCTYPE\n\nhtml>\nafter\n\n",
            "<![CDATA[\n\nvalue\n]]>\nafter\n\n",
            "<div>\nvalue\n\nafter\n\n",
            "<x-box>\nvalue\n\nafter\n\n"
        ]) {
            let bytes = source.toArray()
            let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
            let bytewise = collectRawSessionEvents(engine, bytes, [1])
            let byLine = collectRawSessionEventsByLine(engine, bytes)
            expectSameEventSequence(bytewise, whole)
            expectSameEventSequence(byLine, whole)
        }

        for (tag in ["scripture", "prelude", "stylex", "textareax"]) {
            let opener = "<${tag}>\n"
            let closedPrefix = "${opener}value\n\n"
            let source = "${closedPrefix}after\n\n"
            let bytes = source.toArray()
            let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
            let bytewise = collectRawSessionEvents(engine, bytes, [1])
            let byLine = collectRawSessionEventsByLine(engine, bytes)
            expectSameEventSequence(bytewise, whole)
            expectSameEventSequence(byLine, whole)

            let closedBytes = closedPrefix.toArray()
            @Expect(rawSessionEmitsHtmlBlockBeforeFinish(engine, closedBytes, [closedBytes.size]), true)
            @Expect(rawSessionEmitsHtmlBlockBeforeFinish(engine, closedBytes, [opener.size, 6, 1]), true)
            @Expect(rawSessionEmitsHtmlBlockBeforeFinish(engine, closedBytes, [1]), true)
        }

        let session = engine.newRawBlockEventSession()
        let _ = session.feed("<script>\n\n")
        let closing = session.feed("</script>\n")
        @Expect(eventSequenceHasNodeKind(closing, NodeKind.HtmlBlock), true)

        let blankClosed = engine.newRawBlockEventSession()
        let closedByBlank = blankClosed.feed("<div>\nvalue\n\n")
        @Expect(eventSequenceHasNodeKind(closedByBlank, NodeKind.HtmlBlock), true)
    }

    @TestCase
    func rawSessionClosedIndentedBlockIsEmittedBeforeFinish(): Unit {
        let engine = MarkdownEngine.builder().build()
        let bytes = "    你好\r\n\r\n\t😀\r\n\r\nnext\r\n\r\n".toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let bytewise = collectRawSessionEvents(engine, bytes, [1])
        let byLine = collectRawSessionEventsByLine(engine, bytes)
        expectSameEventSequence(bytewise, whole)
        expectSameEventSequence(byLine, whole)

        let session = engine.newRawBlockEventSession()
        let _ = session.feed("    alpha\n\n    beta\n\n")
        let closing = session.feed("next\n")
        @Expect(eventSequenceHasNodeKind(closing, NodeKind.CodeBlock), true)
    }

    @TestCase
    func rawSessionDoesNotMisclassifyLazyParagraphIndentation(): Unit {
        let session = MarkdownEngine.builder().build().newRawBlockEventSession()
        let events = session.feed("paragraph\n    continuation\n\n")
        @Expect(eventSequenceHasNodeKind(events, NodeKind.Paragraph), true)
        @Expect(eventSequenceHasNodeKind(events, NodeKind.CodeBlock), false)
    }

    @TestCase
    func rawSessionDefersBuiltInLexicalStateWhenBlockDslCanShadowIt(): Unit {
        let manifest = ExtensionManifest("shadow", "1.0.0", "events-test")
        let dialect = MarkdownDialect
            .define("shadow", "1.0.0")
            .enable(manifest)
            .block(BlockSyntax.define("shadow", "html-like").opener("<script>").closer("END"))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let bytes = "<script>\n\n<script> nested\nbody\nEND\nEND\n\nafter\n\n".toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let byLine = collectRawSessionEventsByLine(engine, bytes)
        let bytewise = collectRawSessionEvents(engine, bytes, [1])
        expectSameEventSequence(byLine, whole)
        expectSameEventSequence(bytewise, whole)
        @Expect(eventSequenceHasNodeKind(whole, NodeKind.CustomBlock), true)
        @Expect(eventSequenceHasNodeKind(whole, NodeKind.HtmlBlock), false)
    }

    @TestCase
    func blockDslDoesNotDisableBuiltInRawBlockStates(): Unit {
        let manifest = ExtensionManifest("unrelated", "1.0.0", "events-test")
        let dialect = MarkdownDialect
            .define("unrelated", "1.0.0")
            .enable(manifest)
            .block(BlockSyntax.define("unrelated", "container").opener(":::note").closer(":::"))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let sources = ArrayList<Array<Byte>>()

        let fence = StringBuilder()
        fence.append("```cj\n")
        for (_ in 0..128) {
            fence.append("# candidate\n---\n~~~\n`` nope\n\n")
        }
        fence.append("tail")
        sources.add(fence.toString().toArray())

        let html = StringBuilder()
        html.append("<script>\n")
        for (_ in 0..256) {
            html.append("\n")
        }
        html.append("value")
        sources.add(html.toString().toArray())

        let indented = StringBuilder()
        indented.append("    value\n")
        for (_ in 0..256) {
            indented.append("\n")
        }
        indented.append("    tail")
        sources.add(indented.toString().toArray())

        for (bytes in sources) {
            let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
            let byLine = collectRawSessionEventsByLine(engine, bytes)
            let bytewise = collectRawSessionEvents(engine, bytes, [1])
            expectSameEventSequence(byLine, whole)
            expectSameEventSequence(bytewise, whole)
            expectRawSessionLinearMeteredWorkWithChunks(engine, bytes, [1])
        }
    }

    @TestCase
    func rawSessionEnforcesPairedBlockDslBytesAcrossChunkBoundaries(): Unit {
        let engine = limitedRawBlockDslEngine(29)
        let exactBlock = ":::note\r\na\r\n:::note nested\r\nb\n:::\r\nc\r\n:::\r\n"
        let exact = "${exactBlock}${exactBlock}".toArray()
        let whole = collectRawSessionEvents(engine, exact, [exact.size])
        let byLine = collectRawSessionEventsByLine(engine, exact)
        let bytewise = collectRawSessionEvents(engine, exact, [1])
        expectSameEventSequence(byLine, whole)
        expectSameEventSequence(bytewise, whole)
        @Expect(eventSequenceHasNodeKind(whole, NodeKind.CustomBlock), true)

        let beforeOffending = ":::note\r\na\r\n:::note nested\r\nb\n:::\r\n"
        let overText = "${beforeOffending}cc\r\n:::\r\n"
        let over = overText.toArray()
        let expectedSpan = SourceSpan(0, "${beforeOffending}cc".size)
        expectBatchBlockDslLimit(engine, overText, 29, 30, expectedSpan)
        expectBlockDslLimitWithChunks(engine, over, [over.size], 29, 30, expectedSpan)
        expectBlockDslLimitByLine(engine, over, 29, 30, expectedSpan)
        expectBlockDslLimitWithChunks(engine, over, [1], 29, 30, expectedSpan)
    }

    @TestCase
    func rawSessionRejectsImpossibleCloserBodyBeforeLineCompletion(): Unit {
        let engine = limitedRawBlockDslEngine(4)
        let opener = ":::note\n"
        let sourceText = "${opener}abcde"
        let source = sourceText.toArray()
        expectBatchBlockDslLimit(engine, sourceText, 4, 5, SourceSpan(0, opener.size + 5))
        expectBlockDslLimitWithChunks(engine, source, [1], 4, 5, SourceSpan(0, opener.size + 5))
    }

    @TestCase
    func rawSessionBlockDslLimitSurvivesPrefixCompaction(): Unit {
        let engine = limitedRawBlockDslEngine(5)
        let prefix = StringBuilder()
        for (_ in 0..1400) {
            prefix.append("p\n\n")
        }
        let prefixText = prefix.toString()
        let source = "${prefixText}:::note\nabcd\n:::\n\n".toArray()
        let expected = collectRawSessionEvents(engine, source, [source.size])

        let session = engine.newRawBlockEventSession()
        let actual = ArrayList<MarkdownSourceEvent>()
        actual.add(all: session.feed("${prefixText}:::note\n"))
        actual.add(all: session.feed("abcd\n"))
        actual.add(all: session.feed(":::\n\n"))
        actual.add(all: session.finish())
        expectSameEventSequence(actual.toArray(), expected)

        let limited = limitedRawBlockDslEngine(4).newRawBlockEventSession()
        let _ = limited.feed("${prefixText}:::note\n")
        var rejected = false
        try {
            let _ = limited.feed("abcde")
        } catch (error: LimitExceededException) {
            rejected = true
            expectBlockDslLimitError(error, 4, 5, SourceSpan(prefixText.size, prefixText.size + ":::note\nabcde".size))
        }
        @Expect(rejected, true)
    }

    @TestCase
    func rawSessionPairedBlockDslCloserTailWhitespaceIsLinear(): Unit {
        let engine = limitedRawBlockDslEngine(1)
        let source = StringBuilder()
        source.append(":::note\n:::")
        for (_ in 0..65536) {
            source.append(" ")
        }
        source.append("\n\n")
        let bytes = source.toString().toArray()
        let whole = collectRawSessionEvents(engine, bytes, [bytes.size])
        let byLine = collectRawSessionEventsByLine(engine, bytes)
        expectSameEventSequence(byLine, whole)

        let budget = OperationBudget(bytes.size * 20, 1024, 16, 16, 128, 4096)
        let session = engine.newRawBlockEventSession(budget: budget)
        let bytewise = ArrayList<MarkdownSourceEvent>()
        var index: Int64 = 0
        while (index < bytes.size) {
            bytewise.add(all: session.feed(bytes[index..index + 1]))
            index++
        }
        bytewise.add(all: session.finish())
        expectSameEventSequence(bytewise.toArray(), whole)
        @Expect(budget.usedScanSteps() <= bytes.size * 12, true)
    }

    @TestCase
    func rawSessionUnclosedHtmlAndIndentedBlocksHaveLinearMeteredWork(): Unit {
        let html = StringBuilder()
        html.append("<script>\n")
        for (_ in 0..256) {
            html.append("\n")
        }
        html.append("value")
        expectRawSessionLinearMeteredWork(html.toString().toArray())

        let indented = StringBuilder()
        indented.append("    value\n")
        for (_ in 0..256) {
            indented.append("\n")
        }
        indented.append("    tail")
        expectRawSessionLinearMeteredWork(indented.toString().toArray())
    }
}

private func eventSequenceHasNodeKind(events: Array<MarkdownSourceEvent>, kind: NodeKind): Bool {
    let expected = eventNodeKindOrdinal(Some(kind))
    for (event in events) {
        if (eventNodeKindOrdinal(event.nodeKind) == expected) {
            return true
        }
    }
    false
}

private func expectRawSessionLinearMeteredWork(bytes: Array<Byte>): Unit {
    let linearLimit = bytes.size * 5
    let budget = OperationBudget(linearLimit, 1024, 16, 16, 128, 4096)
    let session = MarkdownEngine.builder().build().newRawBlockEventSession(budget: budget)
    var start: Int64 = 0
    var index: Int64 = 0
    while (index < bytes.size) {
        if (bytes[index] == b'\n') {
            let _ = session.feed(bytes[start..index + 1])
            start = index + 1
        }
        index++
    }
    if (start < bytes.size) {
        let _ = session.feed(bytes[start..])
    }
    let _ = session.finish()
    @Expect(budget.usedScanSteps() <= bytes.size * 4, true)
}

private func expectRawSessionLinearMeteredWorkWithChunks(engine: MarkdownEngine, bytes: Array<Byte>,
    chunkWidths: Array<Int64>): Unit {
    let linearLimit = bytes.size * 20
    let budget = OperationBudget(linearLimit, 1024, 16, 16, 128, 4096)
    let session = engine.newRawBlockEventSession(budget: budget)
    var offset: Int64 = 0
    var chunkIndex: Int64 = 0
    while (offset < bytes.size) {
        let width = chunkWidths[chunkIndex % chunkWidths.size]
        let end = min(bytes.size, offset + width)
        let _ = session.feed(bytes[offset..end])
        offset = end
        chunkIndex++
    }
    let _ = session.finish()
    @Expect(budget.usedScanSteps() <= bytes.size * 12, true)
}

private func rawLiteralLimitEngine(maximumLiteralBytes: Int64): MarkdownEngine {
    let limits = ParseLimits(4096, 4096, 16, 128, 16, 16, 1024, maximumLiteralBytes, 4096, 1024, 1024)
    MarkdownEngine.builder().limits(limits).build()
}

private func expectRawLiteralLimit(error: LimitExceededException, configured: Int64, observed: Int64): Unit {
    @Expect(error.limitKind, "literal_bytes")
    @Expect(error.configuredLimit, configured)
    @Expect(error.observedValue, observed)
    @Expect(error.phase, "block_parse")
}

private func expectRawLiteralLimitWithChunks(engine: MarkdownEngine, bytes: Array<Byte>, chunkWidths: Array<Int64>,
    configured: Int64, observed: Int64): Unit {
    let session = engine.newRawBlockEventSession()
    var offset: Int64 = 0
    var chunkIndex: Int64 = 0
    var rejected = false
    while (offset < bytes.size && !rejected) {
        let width = chunkWidths[chunkIndex % chunkWidths.size]
        let end = min(bytes.size, offset + width)
        try {
            let _ = session.feed(bytes[offset..end])
            offset = end
            chunkIndex++
        } catch (error: LimitExceededException) {
            rejected = true
            expectRawLiteralLimit(error, configured, observed)
        }
    }
    @Expect(rejected, true)
}

private func limitedRawBlockDslEngine(maximumBlockBytes: Int64): MarkdownEngine {
    let manifest = ExtensionManifest("limited", "1.0.0", "events-test")
    let dialect = MarkdownDialect
        .define("limited", "1.0.0")
        .enable(manifest)
        .block(
            BlockSyntax
                .define("limited", "container")
                .opener(":::note")
                .closer(":::")
                .maximumBlockBytes(maximumBlockBytes))
        .build()
    MarkdownEngine.builder().dialect(dialect).build()
}

private func expectBlockDslLimitWithChunks(engine: MarkdownEngine, bytes: Array<Byte>, chunkWidths: Array<Int64>,
    configured: Int64, observed: Int64, span: SourceSpan): Unit {
    let session = engine.newRawBlockEventSession()
    var offset: Int64 = 0
    var chunkIndex: Int64 = 0
    var rejectedDuringFeed = false
    try {
        while (offset < bytes.size) {
            let width = chunkWidths[chunkIndex % chunkWidths.size]
            let end = min(bytes.size, offset + width)
            let _ = session.feed(bytes[offset..end])
            offset = end
            chunkIndex++
        }
    } catch (error: LimitExceededException) {
        rejectedDuringFeed = true
        expectBlockDslLimitError(error, configured, observed, span)
    }
    @Expect(rejectedDuringFeed, true)
}

private func expectBatchBlockDslLimit(engine: MarkdownEngine, source: String, configured: Int64, observed: Int64,
    span: SourceSpan): Unit {
    var rejected = false
    try {
        let _ = engine.parseEvents(source, mode: MarkdownEventMode.RawBlockEventMode)
    } catch (error: LimitExceededException) {
        rejected = true
        expectBlockDslLimitError(error, configured, observed, span)
    }
    @Expect(rejected, true)
}

private func expectBlockDslLimitByLine(engine: MarkdownEngine, bytes: Array<Byte>, configured: Int64, observed: Int64,
    span: SourceSpan): Unit {
    let session = engine.newRawBlockEventSession()
    var lineStart: Int64 = 0
    var index: Int64 = 0
    var rejectedDuringFeed = false
    try {
        while (index < bytes.size) {
            if (bytes[index] == b'\n') {
                let _ = session.feed(bytes[lineStart..index + 1])
                lineStart = index + 1
            }
            index++
        }
        if (lineStart < bytes.size) {
            let _ = session.feed(bytes[lineStart..])
        }
    } catch (error: LimitExceededException) {
        rejectedDuringFeed = true
        expectBlockDslLimitError(error, configured, observed, span)
    }
    @Expect(rejectedDuringFeed, true)
}

private func expectBlockDslLimitError(error: LimitExceededException, configured: Int64, observed: Int64,
    span: SourceSpan): Unit {
    @Expect(error.limitKind, "extension_block_bytes")
    @Expect(error.configuredLimit, configured)
    @Expect(error.observedValue, observed)
    @Expect(error.phase, "extension_parse")
    @Expect(error.extensionId, Some("limited"))
    @Expect(error.span, Some(span))
}
