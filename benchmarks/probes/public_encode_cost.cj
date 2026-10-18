import markdown.*
import std.convert.*
import std.fs.*
import std.time.*

main(args: Array<String>): Int64 {
    if (args.size != 2) {
        throw IllegalArgumentException("usage: source-file repetitions")
    }
    let source = String.fromUtf8(File.readFrom(args[0]))
    let repetitions = Int64.parse(args[1])
    if (repetitions <= 0) {
        throw IllegalArgumentException("positive repetition count required")
    }
    let engine = MarkdownEngine.builder().build()
    let snapshot = engine.parseSnapshot(source)
    var totalBytes: Int64 = 0
    var tailBytes: Int64 = 0
    let begin = MonoTime.now()
    for (_ in 0..repetitions) {
        let bytes = BinaryArtifactCodec.encode(snapshot).bytes()
        totalBytes += bytes.size
        tailBytes += Int64(bytes[bytes.size - 1])
    }
    let elapsed = (MonoTime.now() - begin).toNanoseconds()
    println("metrics\t${elapsed}\t${repetitions}\t${totalBytes}\t${tailBytes}")
    for (line in String.fromUtf8(File.readFrom("/proc/self/status")).split("\n")) {
        if (line.startsWith("VmHWM:")) {
            println("rss\t${line}")
        }
    }
    let artifact = BinaryArtifactCodec.encode(snapshot)
    let restored = BinaryArtifactCodec.read(engine, artifact.bytes())
    if (restored.syntaxTree.losslessText() != source || restored.sourceDigest != snapshot.sourceDigest ||
        engine.htmlRenderer().render(restored.result.document) != engine
        .htmlRenderer()
        .render(snapshot.result.document)) {
        throw IllegalStateException("public encode workload differs")
    }
    println("PASS public encode workload ${snapshot.sourceDigest}")
    0
}
