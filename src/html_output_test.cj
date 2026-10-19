package markdown

import std.unittest.*
import std.unittest.testmacro.*

private class PartialHtmlSink <: AsyncTextSink {
    private let out = StringBuilder()
    var calls: Int64 = 0
    var largestChunk: Int64 = 0
    public func write(value: String): AsyncSinkWriteResult {
        calls++
        largestChunk = max(largestChunk, value.size)
        let _ = String.fromUtf8(value.toArray())
        if (calls % 7 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        if (calls % 3 == 0) {
            out.append(value);
            return AsyncSinkWriteResult.Pause(value.size)
        }
        if (calls % 2 == 0) {
            var end: Int64 = 1
            while (end < value.size && (value[end] & 0xC0) == 0x80) {
                end++
            }
            out.append(value[..end])
            return AsyncSinkWriteResult.Pause(end)
        }
        out.append(value)
        AsyncSinkWriteResult.Continue
    }
    func content(): String {
        out.toString()
    }
}

private class RefusingHtmlSink <: AsyncTextSink {
    var calls: Int64 = 0
    public func write(_: String): AsyncSinkWriteResult {
        calls++;
        AsyncSinkWriteResult.Pause(0)
    }
}

private class CountingHtmlLinkRewriter <: ExternalLinkRewriterPort {
    var calls: Int64 = 0
    public prop identity: String {
        get() {
            "counting-output-test/1"
        }
    }
    public func rewriteExternalLink(uri: String): String {
        calls++;
        uri
    }
}

private class InvalidHtmlAckSink <: AsyncTextSink {
    private let mode: Int64
    var accepted: Int64 = 0
    init(mode: Int64) {
        this.mode = mode
    }
    public func write(value: String): AsyncSinkWriteResult {
        if (mode == 0) {
            return AsyncSinkWriteResult.Pause(-1)
        }
        if (mode == 1) {
            return AsyncSinkWriteResult.Pause(value.size + 1)
        }
        for (index in 0..value.size) {
            if (value[index] >= 0x80) {
                return AsyncSinkWriteResult.Pause(index + 1)
            }
        }
        accepted += value.size
        AsyncSinkWriteResult.Continue
    }
}

private class BrokenHtmlSink <: AsyncTextSink {
    private let throwing: Bool
    init(throwing: Bool) {
        this.throwing = throwing
    }
    public func write(_: String): AsyncSinkWriteResult {
        if (throwing) {
            throw IllegalStateException("sink failed")
        }
        AsyncSinkWriteResult.Failed(SinkError("sink failed"))
    }
}

private class CancellingHtmlSink <: AsyncTextSink {
    private let cancellation: CancellationSource
    var accepted: Int64 = 0
    init(cancellation: CancellationSource) {
        this.cancellation = cancellation
    }
    public func write(value: String): AsyncSinkWriteResult {
        accepted += value.size
        cancellation.cancel()
        AsyncSinkWriteResult.Continue
    }
}

private func completeHtmlOutput(session: HtmlOutputSession, sink: PartialHtmlSink): Unit {
    var finished = false
    var resumes: Int64 = 0
    while (!finished) {
        resumes++
        if (resumes > 1000000) {
            throw IllegalStateException("HTML output made no progress")
        }
        match (session.resume(sink)) {
            case AsyncRenderState.Complete => finished = true
            case AsyncRenderState.Paused => ()
            case AsyncRenderState.Failed(error) => throw error
        }
    }
}

internal func verifyHtmlOutputStandardCases(cases: Array<(MarkdownProfile, String)>): Unit {
    for ((profile, source) in cases) {
        let engine = MarkdownEngine.builder().profile(profile).build()
        let document = engine.parse(source).document
        for (renderer in [engine.htmlRenderer(), engine.htmlRenderer(options: unsafe { HtmlOptions.specCompatible() }),
            engine.htmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() })]) {
            let expectedBudget = OperationBudget.safe()
            let expected = renderer.render(document, budget: expectedBudget)
            for (width in [4, 7, 4096]) {
                let budget = OperationBudget.safe()
                let session = renderer.newOutputSession(document, chunkBytes: width, budget: budget)
                let sink = PartialHtmlSink()
                @Expect(budget.usedRenderedNodes(), 0)
                @Expect(session.bytesProduced(), 0)
                completeHtmlOutput(session, sink)
                @Expect(sink.content(), expected)
                @Expect(session.bytesWritten(), expected.size)
                @Expect(session.bytesProduced(), expected.size)
                @Expect(session.bufferedBytes(), 0)
                @Expect(sink.largestChunk <= width, true)
                @Expect(budget.usedRenderedNodes(), expectedBudget.usedRenderedNodes())
            }
        }
    }
}

@Test
class HtmlOutputSessionTests {
    @TestCase
    func refusedOutputDoesNotRenderAheadChargeAgainOrRepeatHostCallbacks(): Unit {
        let port = CountingHtmlLinkRewriter()
        let options = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
            ImageUriPolicy.safe(), rewriteExternalLinks: Some(port))
        let renderer = HtmlRenderer(options: options)
        let source = "prefix 中文😀 & [later](https://example.com/path)\n\nlast"
        let document = Markdown.parse(source).document
        let budget = OperationBudget.safe()
        let session = renderer.newOutputSession(document, chunkBytes: 4, budget: budget)
        @Expect(port.calls, 0)
        @Expect(budget.usedRenderedNodes(), 0)
        let refusing = RefusingHtmlSink()
        for (_ in 0..3) {
            if (let AsyncRenderState.Paused <- session.resume(refusing)) {
                @Expect(true)
            } else {
                @Expect(false)
            }
            @Expect(port.calls, 0)
            @Expect(budget.usedRenderedNodes(), 2)
            @Expect(session.bytesWritten(), 0)
            @Expect(session.bytesProduced(), 3)
            @Expect(session.bufferedBytes(), 3)
        }
        let sink = PartialHtmlSink()
        completeHtmlOutput(session, sink)
        @Expect(port.calls, 1)
        @Expect(sink.content(), HtmlRenderer().render(document))
        @Expect(session.bytesWritten(), sink.content().size)
        @ExpectThrows[IllegalStateException](session.resume(sink))
    }

    @TestCase
    func footnotesTablesExtensionsAndEscapingResumeAtExactUtf8Prefixes(): Unit {
        let engine = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        let source = "# 标题😀 {#id}\n\n[^n] and [^n]\n\n| H | H |\n| :- | -: |\n| 中文😀 & < | ![**alt** `x`](a.png) |\n\n[^n]: body *note*\n\n    second\n\n---\nx: y\n---\n"
        let document = engine.parse(source).document
        for (renderer in [engine.htmlRenderer(), engine.htmlRenderer(options: unsafe { HtmlOptions.specCompatible() }),
            engine.htmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() })]) {
            for (width in [4, 5, 7, 32, 4096]) {
                let sink = PartialHtmlSink()
                let session = renderer.newOutputSession(document, chunkBytes: width)
                completeHtmlOutput(session, sink)
                @Expect(sink.content(), renderer.render(document))
                @Expect(session.bytesWritten(), session.bytesProduced())
                @Expect(sink.largestChunk <= width, true)
            }
        }
        @ExpectThrows[IllegalArgumentException](HtmlRenderer().newOutputSession(document, chunkBytes: 3))
    }

    @TestCase
    func invalidAcknowledgementsAndSinkFailuresAreTerminal(): Unit {
        let document = Markdown.parse("😀 text").document
        for (mode in [0, 1, 2]) {
            let session = HtmlRenderer().newOutputSession(document, chunkBytes: 4)
            let sink = InvalidHtmlAckSink(mode)
            if (let AsyncRenderState.Failed(error) <- session.resume(sink)) {
                if (let MarkdownErrorCode.SinkFailure <- error.code) {
                    @Expect(true)
                } else {
                    @Expect(false)
                }
            } else {
                @Expect(false)
            }
            @Expect(session.bytesWritten(), sink.accepted)
            @Expect(session.bufferedBytes(), 0)
            @ExpectThrows[IllegalStateException](session.resume(sink))
        }
        for (throwing in [false, true]) {
            let session = HtmlRenderer().newOutputSession(document)
            let sink = BrokenHtmlSink(throwing)
            if (let AsyncRenderState.Failed(error) <- session.resume(sink)) {
                @Expect(error is SinkFailureException, true)
            } else {
                @Expect(false)
            }
            @Expect(session.bytesWritten(), 0)
            @ExpectThrows[IllegalStateException](session.resume(sink))
        }
    }

    @TestCase
    func cancellationAndCumulativeOutputBudgetStopWithoutMoreWrites(): Unit {
        let document = Markdown.parse("&&&&&&&&&&&&&&&&&&&&").document
        let source = CancellationSource()
        let session = HtmlRenderer().newOutputSession(document, cancellation: source.token)
        let sink = CancellingHtmlSink(source)
        if (let AsyncRenderState.Failed(error) <- session.resume(sink)) {
            if (let MarkdownErrorCode.Cancelled <- error.code) {
                @Expect(true)
            } else {
                @Expect(false)
            }
        } else {
            @Expect(false)
        }
        @Expect(session.bytesWritten(), sink.accepted)
        @Expect(sink.accepted, 3)
        @ExpectThrows[IllegalStateException](session.resume(sink))
        let cancelledSource = CancellationSource()
        cancelledSource.cancel()
        let before = HtmlRenderer().newOutputSession(document, cancellation: cancelledSource.token)
        let refusing = RefusingHtmlSink()
        if (let AsyncRenderState.Failed(_) <- before.resume(refusing)) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        @Expect(refusing.calls, 0)
        @Expect(before.bytesProduced(), 0)
        let bounded = HtmlRenderer(maximumOutputBytes: Some(10)).newOutputSession(document, chunkBytes: 4)
        let partial = PartialHtmlSink()
        var failed = false
        while (!failed) {
            match (bounded.resume(partial)) {
                case AsyncRenderState.Paused => ()
                case AsyncRenderState.Failed(error) =>
                    @Expect(error is LimitExceededException, true)
                    failed = true
                case AsyncRenderState.Complete => throw IllegalStateException("output limit was bypassed")
            }
        }
        @Expect(bounded.bytesWritten() <= 10, true)
        @Expect(bounded.bytesProduced() <= 10, true)
        @Expect(bounded.bufferedBytes(), 0)
        @ExpectThrows[IllegalStateException](bounded.resume(partial))
    }
    @TestCase
    func emptyOutputAndCancellationWhilePausedHaveTerminalStates(): Unit {
        let empty = HtmlRenderer().newOutputSession(Markdown.parse("").document)
        let sink = RefusingHtmlSink()
        if (let AsyncRenderState.Complete <- empty.resume(sink)) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        @Expect(sink.calls, 0)
        @Expect(empty.bytesWritten(), 0)
        @Expect(empty.bytesProduced(), 0)
        @ExpectThrows[IllegalStateException](empty.resume(sink))
        let source = CancellationSource()
        let paused = HtmlRenderer().newOutputSession(Markdown.parse("body").document, cancellation: source.token)
        if (let AsyncRenderState.Paused <- paused.resume(sink)) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        @Expect(sink.calls, 1)
        source.cancel()
        if (let AsyncRenderState.Failed(error) <- paused.resume(sink)) {
            if (let MarkdownErrorCode.Cancelled <- error.code) {
                @Expect(true)
            } else {
                @Expect(false)
            }
        } else {
            @Expect(false)
        }
        @Expect(sink.calls, 1)
        @Expect(paused.bytesWritten(), 0)
        @Expect(paused.bytesProduced(), 3)
        @Expect(paused.bufferedBytes(), 0)
    }

    @TestCase
    func longFlatDocumentsAndSingleEscapedLiteralsKeepOutputBufferBounded(): Unit {
        for (flat in [false, true]) {
            let source = StringBuilder()
            for (_ in 0..4096) {
                source.append(if (flat) {
                    "paragraph 中文😀 &\n\n"
                } else {
                    "&&😀"
                })
            }
            let document = Markdown.parse(source.toString()).document
            let renderer = HtmlRenderer()
            let budget = OperationBudget.safe()
            let session = renderer.newOutputSession(document, chunkBytes: 4, budget: budget)
            let sink = PartialHtmlSink()
            var complete = false
            while (!complete) {
                match (session.resume(sink)) {
                    case AsyncRenderState.Paused => @Expect(session.bufferedBytes() <= 36, true)
                    case AsyncRenderState.Complete => complete = true
                    case AsyncRenderState.Failed(error) => throw error
                }
            }
            @Expect(sink.content(), renderer.render(document))
            @Expect(session.bytesWritten(), session.bytesProduced())
            @Expect(budget.usedRenderedNodes(), if (flat) { 8193 } else { 3 })
        }
    }
}
