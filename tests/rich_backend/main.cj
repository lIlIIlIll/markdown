import markdown.core.{CancellationSource, OperationBudget, MarkdownException, MarkdownErrorCode}
import markdown.engine.{MarkdownEngine, AppendReplica}
import markdown.extensions.{MarkdownDialect, OfficialExtensions}
import markdown.render.{AsyncTextSink, AsyncSinkWriteResult, AsyncRenderState, RichContentOptions, RichContentCache, 
    RichContentPreparer, RichContentOutcome, HtmlOptions, HtmlPolicy, RawHtmlPolicyKind, LinkUriPolicy, ImageUriPolicy, 
    CodeGroupHtmlOptions, RichContentLimits, RichContentRequest, RichContentKind, RichContentFailure}
import markdown.node.NodeRichContentBackend

class Sink <: AsyncTextSink {
    let out = StringBuilder()
    var calls: Int64 = 0
    public func write(value: String): AsyncSinkWriteResult {
        calls++
        if (calls % 4 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        out.append(value)
        AsyncSinkWriteResult.Pause(value.size)
    }
}

main(args: Array<String>): Int64 {
    if (args.size != 3 || (args[2] != "true" && args[2] != "false")) {
        return 2
    }
    let builder = MarkdownDialect.define("actual-rich", "1")
    OfficialExtensions.math(builder)
    OfficialExtensions.codeGroups(builder)
    let engine = MarkdownEngine.builder().dialect(builder.build()).build()
    let source = "Formula $\\frac{x^2}{2} + \\sqrt{y}$!\n\n```mermaid\nflowchart LR\n A[输入] --> B[AST]\n```\n\n:::code-group\r\n```js title=\"main.js\" {2}\r\n\u{FEFF}const x = 1;\r\n中😀\r\n```\r\n\r\n```javascript title=\"empty.js\"\r\n```\r\n:::\r\n"
    let result = engine.parse(source)
    let backend = NodeRichContentBackend(args[0], args[1], allowUnsandboxedChromium: args[2] == "true")
    let options = RichContentOptions(math: true, diagrams: true, highlight: true)
    let cache = RichContentCache()
    let prepared = RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache))
    var ready: Int64 = 0
    for (entry in prepared.entries.toArray()) {
        match (entry.outcome) {
            case RichContentOutcome.Ready(_) => ready++
            case RichContentOutcome.Unavailable(reason) => throw IllegalStateException(
                "actual ${entry.kind.id()}=${reason.code()}")
        }
    }
    if (ready != 4) {
        throw IllegalStateException("unexpected preparation count ${ready}")
    }
    let warm = RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache))
    if (warm.fingerprint != prepared.fingerprint || cache.entryCount != 4) {
        throw IllegalStateException("warm cache")
    }
    let htmlOptions = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
        ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/png"]))
    let renderer = engine.htmlRenderer(options: htmlOptions, prepared: Some(prepared),
        codeGroups: CodeGroupHtmlOptions(interactive: true))
    let html = renderer.render(result.document)
    if (!html.contains("<mfrac>") || !html.contains("<msqrt>") || !html.contains("style=\"color:") ||
        !html.contains("src=\"data:image/png;base64,")) {
        throw IllegalStateException("derived output missing")
    }
    let output = renderer.newOutputSession(result.document, chunkBytes: 7)
    let sink = Sink()
    var done = false
    while (!done) {
        match (output.resume(sink)) {
            case AsyncRenderState.Complete => done = true
            case AsyncRenderState.Paused => ()
            case AsyncRenderState.Failed(error) => throw error
        }
    }
    if (sink.out.toString() != html) {
        throw IllegalStateException("actual resumed output differs")
    }
    let mapped = renderer.renderWithSourceMap(result.document)
    var provenance: Int64 = 0
    for (entry in mapped.sourceMap.toArray()) {
        if (entry.generated && entry.sourceSpan.isSome() && entry.nodeId.isSome()) {
            provenance++
        }
    }
    if (provenance == 0 || result.source.text() != source) {
        throw IllegalStateException("source/provenance")
    }
    let append = engine.newAppendSession()
    let replica = AppendReplica()
    for (byte in source.toArray()) {
        replica.apply(append.feed([byte]))
    }
    replica.apply(append.finish())
    let appended = replica.result.getOrThrow()
    let appendPrepared = RichContentPreparer.prepare(appended, options: options, backend: Some(backend),
        cache: Some(cache))
    let appendHtml = engine
        .htmlRenderer(options: htmlOptions, prepared: Some(appendPrepared),
            codeGroups: CodeGroupHtmlOptions(interactive: true))
        .render(appended.document)
    if (appendHtml != html || appendPrepared.fingerprint != prepared.fingerprint || cache.entryCount != 4) {
        throw IllegalStateException("actual append preparation differs")
    }
    let timeout = backend.prepare([RichContentRequest(RichContentKind.Math, "x")],
        RichContentLimits(maximumTimeMilliseconds: 1), OperationBudget.safe(), CancellationSource().token)
    if (let RichContentOutcome.Unavailable(RichContentFailure.TimedOut) <- timeout[0]) {
        ()
    } else {
        throw IllegalStateException("actual backend timeout category")
    }
    let cancel = CancellationSource()
    let cancelling = spawn {
        try {
            let _ = backend.prepare([RichContentRequest(RichContentKind.Math, "x")], RichContentLimits(),
                OperationBudget.safe(), cancel.token)
            false
        } catch (error: MarkdownException) {
            if (let MarkdownErrorCode.Cancelled <- error.code) {
                true
            } else {
                throw error
            }
        }
    }
    var pending = false
    try {
        let _ = cancelling.get(Duration.millisecond * 50)
    } catch (_: TimeoutException) {
        pending = true
    }
    if (!pending) {
        throw IllegalStateException("cancellation job ended before observation")
    }
    cancel.cancel()
    let cancelled = cancelling.get(Duration.second * 10)
    if (!cancelled) {
        throw IllegalStateException("actual backend cancellation category")
    }
    println(
        "PASS actual STS1.2 parse/append/Node preparation/validation/cache/render/resume/source-map; ready=${ready}")
    println("BEGINHTML")
    println(html)
    println("ENDHTML")
    0
}
