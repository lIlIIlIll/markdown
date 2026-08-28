package markdown_benchmark_driver

import markdown.*
import markdown.native.NativeLineScanner
import std.collection.*
import std.convert.*
import std.io.*
import std.process.Process

private class BenchmarkInputStream <: InputStream {
    private let bytes: Array<Byte>
    private var offset: Int64 = 0

    init(bytes: Array<Byte>) {
        this.bytes = bytes
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (offset >= bytes.size) {
            return 0
        }
        let count = min(buffer.size, bytes.size - offset)
        for (index in 0..count) {
            buffer[index] = bytes[offset + index]
        }
        offset += count
        count
    }
}

private func readInputBytes(): Array<Byte> {
    // ConsoleReader performs formatted character input and reaches libc one
    // byte at a time on the current SDK. The benchmark protocol consumes a
    // binary UTF-8 corpus, so use the process InputStream and its bulk read
    // path; parser work and the bytes delivered to every profile are unchanged.
    let input = Process.current.stdIn
    let chunkSize: Int64 = 65536
    let bytes = ByteBuffer(chunkSize)
    let buffer = Array<Byte>(chunkSize, repeat: 0)
    while (true) {
        let count = input.read(buffer)
        if (count == 0) {
            break
        }
        if (count < 0) {
            throw IllegalStateException("stdin returned a negative byte count")
        }
        if (count == buffer.size) {
            bytes.write(buffer)
        } else {
            bytes.write(buffer.slice(0, count))
        }
    }
    bytes.bytes()
}

private func parseOwned(engine: AcceleratedMarkdownEngine, bytes: Array<Byte>): ParseResult {
    unsafe { engine.parse(OwnedUtf8Input.take(bytes.clone())) }
}

private func parseStream(engine: AcceleratedMarkdownEngine, bytes: Array<Byte>): ParseResult {
    engine.parse(BenchmarkInputStream(bytes))
}

private func benchmarkEngineBuilder(): MarkdownEngineBuilder {
    MarkdownEngine.builder()
}

private func accelerate(engine: MarkdownEngine): AcceleratedMarkdownEngine {
    engine.acceleratedBy(NativeLineScanner())
}

main(args: Array<String>): Int64 {
    if (args.size < 2) {
        eprintln(
            "usage: markdown_benchmark_driver <commonmark-parse|commonmark-parse-string|commonmark-parse-bytes|commonmark-parse-owned|commonmark-parse-stream|commonmark-html|commonmark-source-map|commonmark-cst|gfm-parse|gfm-html|extension-html> <iterations>")
        return 2
    }
    let iterations = try {
        Int64.parse(args[1])
    } catch (_: Exception) {
        return 2
    }
    if (iterations <= 0) {
        return 2
    }
    let sourceBytes = readInputBytes()
    var observed: Int64 = 0
    if (args[0] == "commonmark-parse") {
        let engine = accelerate(
            benchmarkEngineBuilder().profile(MarkdownProfile.commonMark0312()).limits(ParseLimits.trusted()).build())
        let input = unsafe { ReusableUtf8Input.take(sourceBytes) }
        for (_ in 0..iterations) {
            observed += engine.parse(input).ast.root().children().size
        }
    } else if (args[0] == "commonmark-parse-owned") {
        let engine = accelerate(
            benchmarkEngineBuilder().profile(MarkdownProfile.commonMark0312()).limits(ParseLimits.trusted()).build())
        for (_ in 0..iterations) {
            observed += parseOwned(engine, sourceBytes).ast.root().children().size
        }
    } else if (args[0] == "commonmark-parse-string") {
        let engine = benchmarkEngineBuilder()
            .profile(MarkdownProfile.commonMark0312())
            .limits(ParseLimits.trusted())
            .build()
        let sourceText = String.fromUtf8(sourceBytes)
        for (_ in 0..iterations) {
            observed += engine.parse(sourceText).ast.root().children().size
        }
    } else if (args[0] == "commonmark-parse-bytes") {
        let engine = accelerate(
            benchmarkEngineBuilder().profile(MarkdownProfile.commonMark0312()).limits(ParseLimits.trusted()).build())
        for (_ in 0..iterations) {
            observed += engine.parse(sourceBytes).ast.root().children().size
        }
    } else if (args[0] == "commonmark-parse-stream") {
        let engine = accelerate(
            benchmarkEngineBuilder().profile(MarkdownProfile.commonMark0312()).limits(ParseLimits.trusted()).build())
        for (_ in 0..iterations) {
            observed += parseStream(engine, sourceBytes).ast.root().children().size
        }
    } else if (args[0] == "commonmark-cst") {
        let engine = benchmarkEngineBuilder()
            .profile(MarkdownProfile.commonMark0312())
            .limits(ParseLimits.trusted())
            .build()
        let sourceText = String.fromUtf8(sourceBytes)
        for (_ in 0..iterations) {
            observed += engine.parseSnapshot(sourceText).syntaxTree.root.tokens.size
        }
    } else if (args[0] == "commonmark-html" || args[0] == "commonmark-source-map") {
        let engine = accelerate(
            benchmarkEngineBuilder().profile(MarkdownProfile.commonMark0312()).limits(ParseLimits.trusted()).build())
        let renderer = HtmlRenderer(options: HtmlOptions.specCompatible())
        let input = unsafe { ReusableUtf8Input.take(sourceBytes) }
        for (_ in 0..iterations) {
            if (args[0] == "commonmark-html") {
                observed += renderer.render(engine.parse(input).ast).size
            } else if (args[0] == "commonmark-source-map") {
                observed += renderer.renderWithSourceMap(engine.parse(input).document).sourceMap.size
            }
        }
    } else if (args[0] == "gfm-parse" || args[0] == "gfm-html") {
        let engine = accelerate(
            benchmarkEngineBuilder().profile(MarkdownProfile.gfmModernV1()).limits(ParseLimits.trusted()).build())
        let input = unsafe { ReusableUtf8Input.take(sourceBytes) }
        if (args[0] == "gfm-parse") {
            for (_ in 0..iterations) {
                observed += engine.parse(input).ast.root().children().size
            }
        } else {
            let renderer = HtmlRenderer(options: HtmlOptions.gfmCompatible())
            for (_ in 0..iterations) {
                observed += renderer.render(engine.parse(input).ast).size
            }
        }
    } else if (args[0] == "extension-html") {
        let baseEngine = benchmarkEngineBuilder()
            .dialect(OfficialExtensions.p1Dialect())
            .limits(ParseLimits.trusted())
            .build()
        let engine = accelerate(baseEngine)
        let renderer = baseEngine.htmlRenderer(options: HtmlOptions.safe())
        let input = unsafe { ReusableUtf8Input.take(sourceBytes) }
        for (_ in 0..iterations) {
            observed += renderer.render(engine.parse(input).document).size
        }
    } else {
        return 2
    }
    println(observed)
    0
}
