import markdown.artifact.BinaryArtifactCodec
import markdown.core.MarkdownProfile
import markdown.editor.DocumentSnapshot
import markdown.engine.MarkdownEngine
import markdown.extensions.{MarkdownDialect, OfficialExtensions}
import std.fs.*

class WireProofInput {
    protected let bytes: Array<Byte>
    protected var offset: Int64 = 0
    init(bytes: Array<Byte>) {
        this.bytes = bytes
    }
    protected func number(maximum: Int64): Int64 {
        var value: Int64 = 0
        for (index in 0..5) {
            if (offset >= bytes.size) {
                throw IllegalArgumentException("truncated proof input")
            }
            let byte = bytes[offset];
            offset++
            value = value | (Int64(byte & 127) << UInt64(index * 7))
            if ((byte & 128) == 0) {
                if (value > maximum) {
                    throw IllegalArgumentException("proof input limit")
                }
                return value
            }
        }
        throw IllegalArgumentException("overlong proof input")
    }
    protected func string(maximum: Int64): String {
        let count = number(maximum)
        if (count > bytes.size - offset) {
            throw IllegalArgumentException("truncated proof text")
        }
        let result = String.fromUtf8(bytes.slice(offset, count));
        offset += count
        result
    }
}

func semanticProofEngine(profile: MarkdownProfile): MarkdownEngine {
    let builder = MarkdownDialect.define("cache-wire-proof", "1").base(profile)
    OfficialExtensions.footnotes(builder)
    OfficialExtensions.frontMatter(builder)
    OfficialExtensions.math(builder)
    OfficialExtensions.definitionLists(builder)
    OfficialExtensions.headingIds(builder)
    OfficialExtensions.smartPunctuation(builder)
    OfficialExtensions.codeGroups(builder)
    MarkdownEngine.builder().dialect(builder.build()).build()
}

main(args: Array<String>): Int64 {
    if (args.size != 2) {
        throw IllegalArgumentException("usage: input-file output-directory")
    }
    let input = WireProofInput(File.readFrom(args[0]))
    if (input.string(64) != "MD-PROBE-WIRE-PROOF/1") {
        throw IllegalArgumentException("proof input schema")
    }
    let engines: Array<MarkdownEngine> = [
        MarkdownEngine.builder().build(),
        MarkdownEngine.builder().profile(MarkdownProfile.gfm029()).build(),
        semanticProofEngine(MarkdownProfile.commonMark0312()),
        semanticProofEngine(MarkdownProfile.gfmModernV1())
    ]
    let count = input.number(10000)
    for (index in 0..count) {
        let engine = engines[input.number(3)]
        let source = input.string(1024 * 1024)
        let snapshot = DocumentSnapshot.parse(engine, source)
        let bytes = BinaryArtifactCodec.encode(snapshot).bytes()
        let restored = BinaryArtifactCodec.read(engine, bytes)
        if (restored.result.source.text() != source || restored.syntaxTree.losslessText() != source ||
            restored.sourceDigest != snapshot.sourceDigest || restored.result.document.nodeCount != snapshot
            .result
            .document
            .nodeCount || engine.htmlRenderer().render(restored.result.document) != engine
            .htmlRenderer()
            .render(snapshot.result.document) || restored.result.diagnostics.size != snapshot.result.diagnostics.size) {
            throw IllegalStateException("public artifact roundtrip differs")
        }
        let reencoded = BinaryArtifactCodec.encode(restored).bytes()
        if (bytes.size != reencoded.size) {
            throw IllegalStateException("artifact reencode size differs")
        }
        for (byteIndex in 0..bytes.size) {
            if (bytes[byteIndex] != reencoded[byteIndex]) {
                throw IllegalStateException("artifact reencode differs")
            }
        }
        File.writeTo(args[1] + "/" + index.toString() + ".bin", bytes)
    }
    if (input.offset != input.bytes.size) {
        throw IllegalArgumentException("trailing proof input")
    }
    println("PASS public cache wire proof ${count}")
    0
}
