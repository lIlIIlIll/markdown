package markdown_benchmark_driver

import markdown.*
import std.collection.*
import std.convert.*
import std.env.*

private func readInputBytes(): Array<Byte> {
    let input = getStdIn()
    let bytes = ArrayList<Byte>()
    let buffer = Array<Byte>(8192, repeat: 0)
    while (true) {
        let count = input.read(buffer)
        if (count == 0) {
            break
        }
        if (count < 0) {
            throw IllegalStateException("stdin returned a negative byte count")
        }
        for (index in 0..count) {
            bytes.add(buffer[index])
        }
    }
    bytes.toArray()
}

// OwnedUtf8Input transfers ownership, so each iteration receives a fresh
// clone. The clone cost is shared by the CFFI and Cangjie baselines.
private func parseOwned(engine: MarkdownEngine, bytes: Array<Byte>): ParseResult {
    unsafe { engine.parse(OwnedUtf8Input.take(bytes.clone())) }
}

main(args: Array<String>): Int64 {
    if (args.size < 2) {
        eprintln(
            "usage: markdown_benchmark_driver <commonmark-parse|commonmark-html|commonmark-source-map|commonmark-cst|gfm-html|extension-html> <iterations>")
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
        let engine = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.commonMark0312())
            .limits(ParseLimits.trusted())
            .build()
        for (_ in 0..iterations) {
            observed += parseOwned(engine, sourceBytes).document.children().size
        }
    } else if (args[0] == "commonmark-cst") {
        let engine = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.commonMark0312())
            .limits(ParseLimits.trusted())
            .build()
        let sourceText = String.fromUtf8(sourceBytes)
        for (_ in 0..iterations) {
            observed += engine.parseSnapshot(sourceText).syntaxTree.root.tokens.size
        }
    } else if (args[0] == "commonmark-html" || args[0] == "commonmark-source-map") {
        let engine = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.commonMark0312())
            .limits(ParseLimits.trusted())
            .build()
        let renderer = HtmlRenderer(options: HtmlOptions.specCompatible())
        for (_ in 0..iterations) {
            if (args[0] == "commonmark-html") {
                observed += renderer.render(parseOwned(engine, sourceBytes).document).size
            } else if (args[0] == "commonmark-source-map") {
                observed += renderer.renderWithSourceMap(parseOwned(engine, sourceBytes).document).sourceMap.size
            }
        }
    } else if (args[0] == "gfm-html") {
        let engine = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfmModernV1())
            .limits(ParseLimits.trusted())
            .build()
        let renderer = HtmlRenderer(options: HtmlOptions.gfmCompatible())
        for (_ in 0..iterations) {
            observed += renderer.render(parseOwned(engine, sourceBytes).document).size
        }
    } else if (args[0] == "extension-html") {
        let engine = MarkdownEngine
            .builder()
            .dialect(OfficialExtensions.p1Dialect())
            .limits(ParseLimits.trusted())
            .build()
        let renderer = engine.htmlRenderer(options: HtmlOptions.safe())
        for (_ in 0..iterations) {
            observed += renderer.render(parseOwned(engine, sourceBytes).document).size
        }
    } else {
        return 2
    }
    println(observed)
    0
}
