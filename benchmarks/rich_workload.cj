import markdown.*
import markdown.node.NodeRichContentBackend
import std.fs.*
import std.time.*

func richRss(): String {
    for (line in String.fromUtf8(File.readFrom("/proc/self/status")).split("\n")) {
        if (line.startsWith("VmHWM:")) {
            return line
        }
    }
    throw IllegalStateException("Linux peak RSS unavailable")
}

main(args: Array<String>): Int64 {
    if (args.size != 5 || args[4] != "allow-unsandboxed-chromium") {
        throw IllegalArgumentException("usage: phase runtime work input-file allow-unsandboxed-chromium")
    }
    let phase = args[0]
    let source = String.fromUtf8(File.readFrom(args[3]))
    let builder = MarkdownDialect.define("rich-cost", "1")
    OfficialExtensions.math(builder)
    OfficialExtensions.codeGroups(builder)
    let engine = MarkdownEngine.builder().dialect(builder.build()).build()
    let result = engine.parse(source)
    let initialize = MonoTime.now()
    let backend = NodeRichContentBackend(args[1], args[2], allowUnsandboxedChromium: true)
    let initializeNanos = (MonoTime.now() - initialize).toNanoseconds()
    let options = RichContentOptions(math: true, diagrams: true, highlight: true)
    let cache = RichContentCache()
    let usePrepared = phase == "render-prepared" || phase == "warm"
    let prior: ?RichContentPreparation = if (usePrepared) {
        Some(RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache)))
    } else {
        None
    }
    let htmlOptions = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
        ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/png"]))
    let renderer = engine.htmlRenderer(options: htmlOptions, prepared: prior)
    let begin = MonoTime.now()
    let prepared: ?RichContentPreparation = match (phase) {
        case "disabled" => Some(RichContentPreparer.prepare(result))
        case "missing" => Some(RichContentPreparer.prepare(result, options: options))
        case "cold" | "warm" => Some(
            RichContentPreparer.prepare(result, options: options, backend: Some(backend), cache: Some(cache)))
        case "render-fallback" | "render-prepared" => None
        case _ => throw IllegalArgumentException("unknown rich workload phase")
    }
    let html = if (prepared.isNone()) {
        renderer.render(result.document)
    } else {
        ""
    }
    let elapsed = (MonoTime.now() - begin).toNanoseconds()
    println("metrics\t${elapsed}\t${initializeNanos}\t${cache.entryCount}\t${cache.productBytes}\t${html.size}")
    println("rss\t${richRss()}")
    let checked = if (prepared.isSome()) {
        prepared
    } else {
        prior
    }
    if (let Some(value) <- checked) {
        if (value.entries.size != 4) {
            throw IllegalStateException("unexpected rich entry count")
        }
        for (entry in value.entries.toArray()) {
            match (entry.outcome) {
                case RichContentOutcome.Ready(_) =>
                    if (phase == "disabled" || phase == "missing") {
                        throw IllegalStateException("unexpected rich success")
                    }
                case RichContentOutcome.Unavailable(reason) =>
                    if (reason.code() != phase) {
                        throw IllegalStateException("actual backend did not produce a valid product")
                    }
            }
        }
        if (phase == "warm" && value.fingerprint != prior.getOrThrow().fingerprint) {
            throw IllegalStateException("warm product differs")
        }
    }
    if (phase == "render-prepared" && (!html.contains("<mfrac>") || !html.contains("<msqrt>") ||
        !html.contains("style=\"color:") || !html.contains("src=\"data:image/png;base64,"))) {
        throw IllegalStateException("actual derived output missing")
    }
    if (phase == "render-fallback" && (!html.contains("flowchart LR") || !html.contains("frac"))) {
        throw IllegalStateException("fallback source missing")
    }
    if (result.source.text() != source) {
        throw IllegalStateException("source mutated")
    }
    println("PASS actual rich cost workload")
    0
}
