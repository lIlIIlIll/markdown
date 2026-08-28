package markdown

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

private class CountingEventSink <: MarkdownEventSink {
    var count: Int64 = 0
    var sawDocument: Bool = false

    public func onEvent(event: MarkdownSourceEvent): Unit {
        count++
        if (let Some(NodeKind.Document) <- event.nodeKind) {
            sawDocument = true
        }
    }
}

@Test
class SourceEventApiTest {
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
}
