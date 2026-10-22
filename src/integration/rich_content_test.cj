package markdown.integration

import markdown.core.{CancellationSource, CancellationToken, Document, ImmutableArray, MarkdownErrorCode, 
    MarkdownException, OperationBudget, SourceSpan}
import markdown.engine.MarkdownEngine
import markdown.extensions.{MarkdownDialect, OfficialExtensions}
import markdown.render.{AsyncRenderState, AsyncSinkWriteResult, AsyncTextSink, CanonicalMarkdownRenderer, 
    CodeGroupHtmlOptions, CodeHighlightToken, HtmlOptions, HtmlPolicy, HtmlRenderer, ImageUriPolicy, LinkUriPolicy, 
    MathMlAttribute, MathMlNode, RawHtmlPolicyKind, RichContentBackend, RichContentCache, RichContentFailure, 
    RichContentKind, RichContentLimits, RichContentOptions, RichContentOutcome, RichContentPreparer, RichContentProduct, 
    RichContentRequest, RichPngImage, RichPreparedEntry, StringTextSink}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

// These fixtures test the typed boundary. Real engine qualification is separate.
private func richTestEngine(): MarkdownEngine {
    MarkdownEngine
        .builder()
        .dialect(
            OfficialExtensions
                .codeGroups(OfficialExtensions.math(MarkdownDialect.define("rich-boundary-test", "1")))
                .build())
        .build()
}

private func richTestPng(): Array<Byte> {
    [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
        137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0,
        0, 0, 73, 69, 78, 68, 174, 66, 96, 130]
}

private class RichBoundaryBackend <: RichContentBackend {
    protected var mode = "ready"
    var theme = "light"
    protected var calls: Int64 = 0
    protected let requests = ArrayList<RichContentRequest>()
    public func identity(kind: RichContentKind): String {
        "boundary-fixture/1/${kind.id()}/${if (let RichContentKind.Highlight <- kind) { theme } else { "fixed" }}"
    }
    public func prepare(values: Array<RichContentRequest>, _: RichContentLimits, budget: OperationBudget,
        cancellation: CancellationToken): Array<RichContentOutcome> {
        calls++
        requests.add(all: values)
        cancellation.throwIfCancelled(phase: "prepare")
        if (mode == "throws") {
            throw IllegalStateException("fixture backend failed")
        }
        if (mode == "cancel") {
            throw MarkdownException(MarkdownErrorCode.Cancelled, "fixture cancelled")
        }
        if (mode == "budget") {
            budget.consumeScan(steps: 9223372036854775807)
        }
        if (mode == "length") {
            return []
        }
        Array<RichContentOutcome>(values.size, {i => produce(values[i])})
    }
    private func produce(request: RichContentRequest): RichContentOutcome {
        for (reason in [RichContentFailure.Disabled, RichContentFailure.Missing, RichContentFailure.Unsupported,
            RichContentFailure.TimedOut, RichContentFailure.Failed, RichContentFailure.Limited]) {
            if (mode == reason.code()) {
                return RichContentOutcome.Unavailable(reason)
            }
        }
        let product = match (request.kind) {
            case RichContentKind.Math =>
                let child = if (mode == "evil-tag") {
                    "script"
                } else {
                    "mtext"
                }
                let attributes: Array<MathMlAttribute> = if (mode == "evil-attribute") {
                    [MathMlAttribute("href", "https://example.test/")]
                } else if (mode == "evil-style") {
                    [MathMlAttribute("style", "color:red")]
                } else if (mode == "huge-layout") {
                    [MathMlAttribute("width", "99999999999999em")]
                } else {
                    []
                }
                RichContentProduct.MathMl(
                    MathMlNode("math",
                        children: [MathMlNode(child, attributes: attributes,
                            children: [MathMlNode("", text: request.source)])]))
            case RichContentKind.Highlight =>
                let tokens = ArrayList<CodeHighlightToken>()
                if (!request.source.isEmpty()) {
                    let start: Int64 = if (mode == "split-scalar") {
                        1
                    } else {
                        0
                    }
                    let end = request.source.size + (if (mode == "outside") {
                        1
                    } else {
                        0
                    })
                    tokens.add(CodeHighlightToken(SourceSpan(start, end), if (mode == "evil-color") {
                        "red;background:url(x)"
                    } else {
                        "#123abc"
                    }, fontStyle: 7))
                    if (mode == "overlap" || mode == "tokens") {
                        tokens.add(CodeHighlightToken(SourceSpan(0, end), "#123abc"))
                    }
                }
                RichContentProduct.Highlight(ImmutableArray<CodeHighlightToken>(tokens.toArray()))
            case RichContentKind.Diagram =>
                let png = ArrayList<Byte>()
                png.add(all: richTestPng())
                if (mode == "png-trailing") {
                    png.add(0)
                }
                let data = png.toArray()
                if (mode == "png-corrupt") {
                    data[29] = 0
                }
                RichContentProduct.Diagram(RichPngImage(data))
        }
        RichContentOutcome.Ready(if (mode == "wrong-kind") {
            RichContentProduct.Diagram(RichPngImage(richTestPng()))
        } else {
            product
        })
    }
}

private func richFailure(entry: RichPreparedEntry): String {
    match (entry.outcome) {
        case RichContentOutcome.Unavailable(reason) => reason.code()
        case _ => "ready"
    }
}

private class RichPartialSink <: AsyncTextSink {
    protected let text = StringBuilder()
    protected var calls: Int64 = 0
    var largest: Int64 = 0
    public func write(value: String): AsyncSinkWriteResult {
        calls++
        largest = max(largest, value.size)
        if (calls % 3 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        var end: Int64 = 1
        while (end < value.size && (value[end] & 0xC0) == 0x80) {
            end++
        }
        text.append(value[..end])
        AsyncSinkWriteResult.Pause(end)
    }
}

private func expectRichOutput(renderer: HtmlRenderer, document: Document): Unit {
    let expected = renderer.render(document)
    for (width in [4, 7, 4096]) {
        let sink = RichPartialSink()
        let session = renderer.newOutputSession(document, chunkBytes: width)
        var done = false
        var attempts: Int64 = 0
        while (!done && attempts < expected.size * 4 + 100) {
            attempts++
            match (session.resume(sink)) {
                case AsyncRenderState.Complete => done = true
                case AsyncRenderState.Paused => ()
                case AsyncRenderState.Failed(error) => throw error
            }
        }
        @Expect(done, true)
        @Expect(sink.text.toString(), expected)
        @Expect(sink.largest <= width, true)
        @Expect(session.bytesWritten(), expected.size)
    }
}

@Test
class RichContentTests {
    @TestCase
    func disabledMissingAndStrictStatesPreserveFullSource(): Unit {
        let engine = richTestEngine()
        let result = engine.parse("$x + y$\n\n```mermaid\nflowchart LR\n A --> B\n```\n\n```js\nconst x = 1\n```\n")
        let backend = RichBoundaryBackend()
        let disabled = RichContentPreparer.prepare(result, backend: Some(backend))
        @Expect(disabled.entries.size, 3)
        for (entry in disabled.entries.toArray()) {
            @Expect(richFailure(entry), "disabled")
        }
        @Expect(backend.calls, 0)
        let options = RichContentOptions(math: true, diagrams: true, highlight: true)
        let missing = RichContentPreparer.prepare(result, options: options)
        for (entry in missing.entries.toArray()) {
            @Expect(richFailure(entry), "missing")
        }
        @Expect(engine.htmlRenderer(prepared: Some(missing)).render(result.document), engine.htmlRenderer().render(result.document))
        @ExpectThrows[MarkdownException](RichContentPreparer.prepare(result, options: RichContentOptions(math: true, strict: true)))
    }

    @TestCase
    func mathProducesEscapedStructuredOutputAndCoarseProvenance(): Unit {
        let engine = richTestEngine()
        let result = engine.parse("> $$\r\n> a < b & 中😀\r\n> $$\r\n")
        let backend = RichBoundaryBackend()
        let prepared = RichContentPreparer.prepare(result, options: RichContentOptions(math: true),
            backend: Some(backend))
        @Expect(backend.calls, 1)
        @Expect(backend.requests[0].source, "a < b & 中😀")
        let entry = prepared.entries[0]
        @Expect(result.source.slice(entry.sourceParts[0]), "a < b & 中😀")
        let renderer = engine.htmlRenderer(prepared: Some(prepared))
        @Expect(renderer.render(result.document), "<blockquote>\n<div class=\"math-block\"><math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><mtext>a &lt; b &amp; 中😀</mtext></math></div></blockquote>\n")
        let mapped = renderer.renderWithSourceMap(result.document)
        var found = false
        for (mapping in mapped.sourceMap.toArray()) {
            if (mapping.nodeId == Some(entry.nodeId) && mapping.generated) {
                found = true
                @Expect(mapping.sourceSpan.isSome(), true)
            }
        }
        @Expect(found, true)
        expectRichOutput(renderer, result.document)
    }

    @TestCase
    func highlightKeepsUnicodeGapsLinesAndCodeGroupCopyBytes(): Unit {
        let engine = richTestEngine()
        let source = ":::code-group\r\n```js title=\"main\" {2}\r\nconst x = 1\r\n中😀<&>\r\n```\r\n```mermaid\r\nflowchart LR\r\n```\r\n:::\r\n"
        let result = engine.parse(source)
        let backend = RichBoundaryBackend()
        let prepared = RichContentPreparer.prepare(result, options: RichContentOptions(highlight: true),
            backend: Some(backend))
        @Expect(backend.requests.size, 2)
        @Expect(backend.requests[1].kind.id(), "highlight")
        let renderer = engine.htmlRenderer(prepared: Some(prepared), codeGroups: CodeGroupHtmlOptions(interactive: true))
        let html = renderer.render(result.document)
        @Expect(html.contains("<mark class=\"code-line\"><span style=\"color:#123abc;font-style:italic;font-weight:bold;text-decoration:underline\">中😀&lt;&amp;&gt;</span></mark>\n"), true)
        @Expect(html.contains("data-code-copy-hex=\"636f6e73742078203d20310d0ae4b8adf09f98803c263e0d0a\""), true)
        @Expect(html.contains("<img"), false)
        @Expect(CanonicalMarkdownRenderer().render(result.document).contains("中😀<&>"), true)
        expectRichOutput(renderer, result.document)
    }

    @TestCase
    func pngRequiresExplicitMimePolicyAndStreamsTheExactControlledImage(): Unit {
        let engine = richTestEngine()
        let result = engine.parse("```mermaid\nflowchart LR\n A --> B\n```\n")
        let backend = RichBoundaryBackend()
        let prepared = RichContentPreparer.prepare(result, options: RichContentOptions(diagrams: true),
            backend: Some(backend))
        @Expect(richFailure(prepared.entries[0]), "ready")
        @Expect(engine.htmlRenderer(prepared: Some(prepared)).render(result.document), engine.htmlRenderer().render(result.document))
        let options = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
            ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/png"]))
        let renderer = engine.htmlRenderer(options: options, prepared: Some(prepared))
        let html = renderer.render(result.document)
        @Expect(html, "<img class=\"diagram\" width=\"1\" height=\"1\" alt=\"Mermaid diagram\" src=\"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==\" />\n")
        expectRichOutput(renderer, result.document)
        let bytes = richTestPng()
        let immutable = RichPngImage(bytes)
        bytes[16] = 255
        @Expect(immutable.width, 1)
        @Expect(immutable.height, 1)
    }

    @TestCase
    func untrustedTreesTokensAndImagesNeverBecomeRawHtml(): Unit {
        let engine = richTestEngine()
        for ((source, modes) in [("$x$", ["evil-tag", "evil-attribute", "evil-style", "huge-layout", "wrong-kind"]),
            ("```js\n中😀<&>\n```\n", ["split-scalar", "outside", "evil-color", "overlap"]),
            ("```mermaid\nA --> B\n```\n", ["png-corrupt", "png-trailing"])]) {
            let result = engine.parse(source)
            for (mode in modes) {
                let backend = RichBoundaryBackend();
                backend.mode = mode
                let cache = RichContentCache()
                let prepared = RichContentPreparer.prepare(result,
                    options: RichContentOptions(math: true, diagrams: true, highlight: true), backend: Some(backend),
                    cache: Some(cache))
                @Expect(richFailure(prepared.entries[0]), "failed")
                @Expect(cache.entryCount, 0)
                @Expect(engine.htmlRenderer(prepared: Some(prepared)).render(result.document), engine.htmlRenderer().render(result.document))
            }
        }
    }

    @TestCase
    func readyCacheUsesSourceLanguageBackendConfigAndActualThemeDependencies(): Unit {
        let engine = richTestEngine()
        let backend = RichBoundaryBackend()
        let cache = RichContentCache()
        let options = RichContentOptions(math: true, highlight: true)
        let one = engine.parse("$x$\n\n```js\nx\n```\n")
        let first = RichContentPreparer.prepare(one, options: options, backend: Some(backend), cache: Some(cache))
        let two = engine.parse("$x$\n\n```js\nx\n```\n")
        let second = RichContentPreparer.prepare(two, options: options, backend: Some(backend), cache: Some(cache))
        @Expect(first.fingerprint, second.fingerprint)
        @Expect(backend.calls, 1)
        @Expect(cache.entryCount, 2)
        backend.theme = "dark"
        let third = RichContentPreparer.prepare(two, options: options, backend: Some(backend), cache: Some(cache))
        @Expect(backend.calls, 2)
        @Expect(backend.requests.size, 3)
        @Expect(backend.requests[2].kind.id(), "highlight")
        @Expect(third.fingerprint != first.fingerprint, true)
        let changed = engine.parse("$$\nx\n$$\n\n```python\nx\n```\n\n$y$")
        let _ = RichContentPreparer.prepare(changed, options: options, backend: Some(backend), cache: Some(cache))
        @Expect(backend.calls, 3)
        @Expect(cache.entryCount, 6)
        @Expect(cache.productBytes > 0, true)
        cache.clear();
        @Expect(cache.entryCount, 0)
        @Expect(cache.productBytes, 0)
    }

    @TestCase
    func transientFailuresAreNotCachedAndCancellationBudgetRemainFatal(): Unit {
        let engine = richTestEngine()
        let result = engine.parse("$x$")
        let options = RichContentOptions(math: true)
        let backend = RichBoundaryBackend()
        let cache = RichContentCache()
        for (mode in ["missing", "unsupported", "timed-out", "failed", "limited", "throws", "length"]) {
            backend.mode = mode
            let prepared = RichContentPreparer.prepare(result, options: options, backend: Some(backend),
                cache: Some(cache))
            @Expect(richFailure(prepared.entries[0]), if (mode == "throws" || mode == "length") { "failed" } else { mode })
            @Expect(cache.entryCount, 0)
        }
        backend.mode = "ready"
        let _ = RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache))
        @Expect(cache.entryCount, 1)
        for (mode in ["cancel", "budget"]) {
            backend.mode = mode
            try {
                let _ = RichContentPreparer.prepare(result, options: options, backend: Some(backend))
                @Expect(false)
            } catch (error: MarkdownException) {
                let correct = match (error.code) {
                    case MarkdownErrorCode.Cancelled => mode == "cancel"
                    case MarkdownErrorCode.BudgetExceeded => mode == "budget"
                    case _ => false
                }
                @Expect(correct, true)
            }
        }
    }

    @TestCase
    func limitsApplyToCachedProductsAndToWholePreparation(): Unit {
        let engine = richTestEngine()
        let backend = RichBoundaryBackend()
        let options = RichContentOptions(math: true, highlight: true)
        let result = engine.parse("$abc$\n\n```js\nhello\n```\n")
        @ExpectThrows[MarkdownException](RichContentPreparer.prepare(result, options: options, backend: Some(backend),
            limits: RichContentLimits(maximumRequests: 1)))
        @ExpectThrows[MarkdownException](RichContentPreparer.prepare(result, options: options, backend: Some(backend),
            limits: RichContentLimits(maximumTotalInputBytes: 4)))
        let cache = RichContentCache()
        let _ = RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache))
        let limited = RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache),
            limits: RichContentLimits(maximumOutputBytes: 1))
        for (entry in limited.entries.toArray()) {
            @Expect(richFailure(entry), "limited")
        }
        @Expect(backend.calls, 1)
        let tree = RichContentPreparer.prepare(engine.parse("$x$"), options: options, backend: Some(backend),
            limits: RichContentLimits(maximumTreeDepth: 1))
        @Expect(richFailure(tree.entries[0]), "limited")
        backend.mode = "tokens"
        let tokens = RichContentPreparer.prepare(engine.parse("```js\nx\n```"), options: options, backend: Some(backend),
            limits: RichContentLimits(maximumTokens: 1))
        @Expect(richFailure(tokens.entries[0]), "limited")
        let cancelled = CancellationSource();
        cancelled.cancel()
        @ExpectThrows[MarkdownException](RichContentPreparer.prepare(result, cancellation: cancelled.token))
        @ExpectThrows[MarkdownException](RichContentPreparer.prepare(result, budget: OperationBudget(0, 0, 0, 0, 0, 0)))
    }

    @TestCase
    func oldPreparationCannotTouchAnotherRevisionOrStartWriting(): Unit {
        let engine = richTestEngine()
        let one = engine.parse("$x$")
        let two = engine.parse("$x$")
        let prepared = RichContentPreparer.prepare(one, options: RichContentOptions(math: true),
            backend: Some(RichBoundaryBackend()))
        let node = one.document.root().children()[0].children()[0]
        @Expect(prepared.entry(node).isSome(), true)
        @ExpectThrows[IllegalArgumentException](prepared.entry(two.document.root().children()[0].children()[0]))
        let renderer = engine.htmlRenderer(prepared: Some(prepared))
        let sink = StringTextSink()
        @ExpectThrows[IllegalArgumentException](renderer.renderTo(two.document, sink))
        @Expect(sink.content(), "")
        @ExpectThrows[IllegalArgumentException](renderer.newOutputSession(two.document))
    }

    @TestCase
    func cacheCapacityAndCumulativeOutputDoNotPromoteLimitedProducts(): Unit {
        let engine = richTestEngine()
        let backend = RichBoundaryBackend()
        let options = RichContentOptions(math: true)
        let cache = RichContentCache(maximumEntries: 1)
        let one = engine.parse("$x$")
        let _ = RichContentPreparer.prepare(one, options: options, backend: Some(backend), cache: Some(cache))
        let size = cache.productBytes
        let two = engine.parse("$x$ $y$")
        let limited = RichContentPreparer.prepare(two, options: options, backend: Some(backend), cache: Some(cache),
            limits: RichContentLimits(maximumTotalOutputBytes: size))
        @Expect(richFailure(limited.entries[0]), "ready")
        @Expect(richFailure(limited.entries[1]), "limited")
        @Expect(cache.entryCount, 1)
        let tiny = RichContentCache(maximumBytes: 1)
        let _ = RichContentPreparer.prepare(two, options: options, backend: Some(backend), cache: Some(tiny))
        @Expect(tiny.entryCount, 0)
        @Expect(one.source.text(), "$x$")
        @Expect(CanonicalMarkdownRenderer().render(one.document), "$x$\n")
    }

    @TestCase
    func preparedOutputStillHonorsCancellationAndCumulativeOutputLimits(): Unit {
        let engine = richTestEngine()
        let result = engine.parse("$中😀 & x$")
        let prepared = RichContentPreparer.prepare(result, options: RichContentOptions(math: true),
            backend: Some(RichBoundaryBackend()))
        let renderer = engine.htmlRenderer(prepared: Some(prepared))
        let cancellation = CancellationSource()
        let session = renderer.newOutputSession(result.document, chunkBytes: 4, cancellation: cancellation.token)
        let sink = RichPartialSink()
        if (let AsyncRenderState.Paused <- session.resume(sink)) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        cancellation.cancel()
        if (let AsyncRenderState.Failed(error) <- session.resume(sink)) {
            if (let MarkdownErrorCode.Cancelled <- error.code) {
                @Expect(true)
            } else {
                @Expect(false)
            }
        } else {
            @Expect(false)
        }
        @ExpectThrows[IllegalStateException](session.resume(sink))
        @ExpectThrows[MarkdownException](HtmlRenderer(maximumOutputBytes: Some(8), prepared: Some(prepared)).render(result.document))
    }
}
