import markdown.engine.{AppendChange, AppendReplica, AppendState, AppendUpdateBatch, MarkdownEngine}
import markdown.extensions.OfficialExtensions
import markdown.render.{AsyncRenderState, AsyncSinkWriteResult, AsyncTextSink, CanonicalMarkdownRenderer}
import std.collection.*
import std.convert.*
import std.fs.*
import std.overflow.*
import std.time.*

func workload(shape: String, units: Int64): String {
    let out = StringBuilder()
    if (shape == "unclosed") {
        out.append("```text\n")
    }
    for (index in 0..units) {
        match (shape) {
            case "closed" => out.append("中文😀 plain paragraph & escaped text.\r\n\r\n")
            case "unclosed" => out.append("中文😀 unfinished fenced body\r\n")
            case "references" => out.append("[late][id] and [^n] 中文😀.\n\n")
            case "list" => out.append("- item 中文😀\n\n  continuation\n\n")
            case _ => throw IllegalArgumentException("unknown workload")
        }
    }
    if (shape == "references") {
        out.append("[id]: /target\n\n[^n]: note **body**\n")
    }
    out.toString()
}

func peakRss(): String {
    let status = String.fromUtf8(File.readFrom("/proc/self/status"))
    for (line in status.split("\n")) {
        if (line.startsWith("VmHWM:")) {
            return line
        }
    }
    throw IllegalStateException("Linux peak RSS is unavailable")
}

func checked(batch: AppendUpdateBatch): Unit {
    if (let AppendState.Failed(error) <- batch.state) {
        throw error
    }
}

func checksum(value: String, seed: UInt64): UInt64 {
    var result = seed
    for (byte in value.toArray()) {
        result = (result ^ UInt64(byte)).wrappingMul(1099511628211)
    }
    result
}

class MeasuringSink <: AsyncTextSink {
    protected let begin: MonoTime
    var firstNanos: Int64 = -1
    protected var calls: Int64 = 0
    protected var bytes: Int64 = 0
    protected var digest: UInt64 = 14695981039346656037
    init(begin: MonoTime) {
        this.begin = begin
    }
    public func write(value: String): AsyncSinkWriteResult {
        if (firstNanos < 0) {
            firstNanos = (MonoTime.now() - begin).toNanoseconds()
        }
        calls++
        if (calls % 7 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        bytes += value.size
        digest = checksum(value, digest)
        if (calls % 2 == 0) {
            AsyncSinkWriteResult.Pause(value.size)
        } else {
            AsyncSinkWriteResult.Continue
        }
    }
}

func measureOutput(engine: MarkdownEngine, source: String, width: Int64): Unit {
    let parsed = engine.parse(source)
    let renderer = engine.htmlRenderer()
    let begin = MonoTime.now()
    let session = renderer.newOutputSession(parsed.document, chunkBytes: width)
    let constructed = (MonoTime.now() - begin).toNanoseconds()
    let sink = MeasuringSink(begin)
    var largestPending: Int64 = 0
    var complete = false
    while (!complete) {
        match (session.resume(sink)) {
            case AsyncRenderState.Complete => complete = true
            case AsyncRenderState.Paused => ()
            case AsyncRenderState.Failed(error) => throw error
        }
        largestPending = max(largestPending, session.bufferedBytes())
    }
    let elapsed = (MonoTime.now() - begin).toNanoseconds()
    println("rss\t${peakRss()}")
    println(
        "output\t${source.size}\t${width}\t${constructed}\t${sink.firstNanos}\t${elapsed}\t${sink.calls}\t${sink.bytes}\t${largestPending}")
    let expected = renderer.render(parsed.document)
    if (sink.bytes != expected.size || sink.digest != checksum(expected, 14695981039346656037)) {
        throw IllegalStateException("resumed output differs from batch HTML")
    }
}

func measureAppend(engine: MarkdownEngine, source: String, width: Int64): Unit {
    let bytes = source.toArray()
    let session = engine.newAppendSession()
    let replica = AppendReplica()
    let latencies = ArrayList<Int64>()
    var firstNanos: Int64 = -1
    var firstBytes: Int64 = -1
    var offset: Int64 = 0
    let begin = MonoTime.now()
    while (offset < bytes.size) {
        let end = min(bytes.size, offset + width)
        let start = MonoTime.now()
        let batch = session.feed(bytes[offset..end])
        latencies.add((MonoTime.now() - start).toNanoseconds())
        checked(batch)
        if (firstNanos < 0) {
            for (index in 0..batch.changes.size) {
                if (let AppendChange.Append(_) <- batch.changes[index]) {
                    firstNanos = (MonoTime.now() - begin).toNanoseconds()
                    firstBytes = end
                    break
                }
            }
        }
        replica.apply(batch)
        offset = end
    }
    let start = MonoTime.now()
    let final = session.finish()
    let finishNanos = (MonoTime.now() - start).toNanoseconds()
    checked(final)
    replica.apply(final)
    let totalNanos = (MonoTime.now() - begin).toNanoseconds()
    println("rss\t${peakRss()}")
    let progress = final.progress
    println(
        "append\t${source.size}\t${width}\t${firstNanos}\t${firstBytes}\t${finishNanos}\t${totalNanos}\t${progress.scanSteps}\t${progress.nodeConstructionSteps}\t${progress.patchSteps}\t${latencies.size}")
    for (index in 0..latencies.size) {
        println("feed\t${index}\t${latencies[index]}")
    }
    // The RSS checkpoint and all timers precede this independent oracle.
    let actual = replica.result.getOrThrow()
    let expected = engine.parse(source)
    if (actual.source.text() != source || actual.document.nodeCount != expected.document.nodeCount ||
        engine.htmlRenderer().render(actual.document) != engine.htmlRenderer().render(expected.document) ||
        CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(actual.document) !=
        CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(expected.document) ||
        actual.diagnostics.size != expected.diagnostics.size) {
        throw IllegalStateException("append differs from batch")
    }
}

main(args: Array<String>): Int64 {
    if (args.size != 4) {
        throw IllegalArgumentException("usage: append_workload append|output shape units chunk-bytes")
    }
    let units = Int64.parse(args[2])
    let width = Int64.parse(args[3])
    if (units <= 0 || width <= 0) {
        throw IllegalArgumentException("workload sizes must be positive")
    }
    let engine = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
    let source = workload(args[1], units)
    if (args[0] == "append") {
        measureAppend(engine, source, width)
    } else if (args[0] == "output") {
        measureOutput(engine, source, width)
    } else {
        throw IllegalArgumentException("unknown operation")
    }
    println("PASS workload equivalence")
    0
}
