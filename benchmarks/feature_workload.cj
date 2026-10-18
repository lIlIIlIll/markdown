import markdown.*
import std.collection.*
import std.convert.*
import std.fs.*
import std.time.*

func featureEngine(enabled: Bool, shape: String): MarkdownEngine {
    if (!enabled) {
        return MarkdownEngine.builder().build()
    }
    if (shape == "dense") {
        return MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
    }
    let builder = MarkdownDialect.define("feature-cost", "1")
    if (shape == "footnotes") {
        OfficialExtensions.footnotes(builder)
    } else if (shape == "headings") {
        OfficialExtensions.headingIds(builder)
    } else {
        throw IllegalArgumentException("unknown workload shape")
    }
    MarkdownEngine.builder().dialect(builder.build()).build()
}

func featureRss(): String {
    for (line in String.fromUtf8(File.readFrom("/proc/self/status")).split("\n")) {
        if (line.startsWith("VmHWM:")) {
            return line
        }
    }
    throw IllegalStateException("Linux peak RSS unavailable")
}

func featureMeasured<T>(repetitions: Int64, work: () -> T): T {
    let begin = MonoTime.now()
    var value = work()
    for (_ in 1..repetitions) {
        value = work()
    }
    let elapsed = (MonoTime.now() - begin).toNanoseconds()
    println("metrics\t${elapsed}\t${repetitions}")
    println("rss\t${featureRss()}")
    value
}

func featureCheck(result: ParseResult, source: String, enabled: Bool, shape: String, units: Int64): Unit {
    if (result.source.text() != source || !result.diagnostics.isEmpty()) {
        throw IllegalStateException("source or diagnostics differ")
    }
    let bindings = result.document.bindings
    let notes = if (!enabled || shape == "headings") {
        0
    } else if (shape == "dense") {
        units
    } else {
        1
    }
    let headings = if (enabled && shape != "footnotes") {
        units
    } else {
        0
    }
    if (bindings.footnotes.size != notes || bindings.headings.size != headings) {
        throw IllegalStateException("feature bindings differ")
    }
    var references: Int64 = 0
    for (note in bindings.footnotes.toArray()) {
        references += note.references.size
        for (reference in note.references.toArray()) {
            if (reference.definition != note.definition || reference.number != note.number ||
                bindings.fragmentTarget(note.definitionId) != Some(note.definition)) {
                throw IllegalStateException("footnote target differs")
            }
        }
    }
    if (references != (if (notes == 0) {
        0
    } else {
        2 * units
    })) {
        throw IllegalStateException("footnote reference count differs")
    }
    let ids = HashSet<String>()
    for (heading in bindings.headings.toArray()) {
        if (!ids.add(heading.id) || bindings.headingForId(heading.id).getOrThrow().heading != heading.heading ||
            bindings.fragmentTarget(heading.id) != Some(heading.heading)) {
            throw IllegalStateException("heading target differs")
        }
    }
    println("summary\t${source.size}\t${result.document.nodeCount}\t${notes}\t${references}\t${headings}")
}

func featureCheckSnapshot(snapshot: DocumentSnapshot, source: String, enabled: Bool, shape: String, units: Int64): Unit {
    featureCheck(snapshot.result, source, enabled, shape, units)
    if (snapshot.syntaxTree.losslessText() != source) {
        throw IllegalStateException("lossless source differs")
    }
    let full = snapshot.engine.parseSnapshot(source)
    let actual = snapshot.engine.htmlRenderer().renderWithSourceMap(snapshot.result.document)
    let expected = snapshot.engine.htmlRenderer().renderWithSourceMap(full.result.document)
    if (actual.content != expected.content || actual.sourceMap.size != expected.sourceMap.size ||
        snapshot.syntaxTree.root.tokens.size != full.syntaxTree.root.tokens.size) {
        throw IllegalStateException("snapshot output differs")
    }
    for (index in 0..actual.sourceMap.size) {
        if (actual.sourceMap[index].sourceSpan != expected.sourceMap[index].sourceSpan ||
            actual.sourceMap[index].outputRange != expected.sourceMap[index].outputRange) {
            throw IllegalStateException("snapshot source map differs")
        }
    }
    for (index in 0..snapshot.syntaxTree.root.tokens.size) {
        let left = snapshot.syntaxTree.root.tokens[index]
        let right = full.syntaxTree.root.tokens[index]
        if (left.raw != right.raw || left.span != right.span) {
            throw IllegalStateException("snapshot token differs")
        }
    }
}

main(args: Array<String>): Int64 {
    if (args.size != 7 || (args[0] != "on" && args[0] != "off")) {
        throw IllegalArgumentException("usage: on|off phase shape units repetitions input-file wire-file")
    }
    let enabled = args[0] == "on"
    let phase = args[1]
    let shape = args[2]
    let units = Int64.parse(args[3])
    let repetitions = Int64.parse(args[4])
    if (units <= 0 || repetitions <= 0) {
        throw IllegalArgumentException("positive units and repetitions required")
    }
    let source = String.fromUtf8(File.readFrom(args[5]))
    let engine = featureEngine(enabled, shape)
    match (phase) {
        case "prepare" =>
            let snapshot = engine.parseSnapshot(source)
            File.writeTo(args[6], BinaryArtifactCodec.encode(snapshot).bytes())
            featureCheckSnapshot(snapshot, source, enabled, shape, units)
        case "parse" =>
            let result = featureMeasured(repetitions, {=> engine.parse(source)})
            featureCheck(result, source, enabled, shape, units)
            let expected = engine.parse(source)
            if (engine.htmlRenderer().render(result.document) != engine.htmlRenderer().render(expected.document)) {
                throw IllegalStateException("parse output differs")
            }
        case "snapshot" => featureCheckSnapshot(featureMeasured(repetitions, {=> engine.parseSnapshot(source)}), source,
            enabled, shape, units)
        case "render" =>
            let result = engine.parse(source)
            let renderer = engine.htmlRenderer()
            let html = featureMeasured(repetitions, {=> renderer.render(result.document)})
            featureCheck(result, source, enabled, shape, units)
            if (html != renderer.render(result.document)) {
                throw IllegalStateException("render output differs")
            }
            println("outputBytes\t${html.size}")
        case "decode-hot" | "decode-read" =>
            let bytes: Array<Byte> = if (phase == "decode-hot") {
                File.readFrom(args[6])
            } else {
                []
            }
            let snapshot = featureMeasured(repetitions, {
                => BinaryArtifactCodec.read(engine, if (phase == "decode-hot") {
                    bytes
                } else {
                    File.readFrom(args[6])
                })
            })
            featureCheckSnapshot(snapshot, source, enabled, shape, units)
        case _ => throw IllegalArgumentException("unknown workload phase")
    }
    println("PASS feature cost workload")
    0
}
