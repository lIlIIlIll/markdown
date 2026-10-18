package markdown

import std.collection.*
import std.convert.*
import std.fs.*
import std.sort.sort
import std.time.*

// These counters exist only in the instrumented private probe build.
var probeCoalesceCst = false
var probeBitmapCst = false
var probeAstRecords: Int64 = 0
var probeSyntaxTokens: Int64 = 0
var probeSyntaxNodes: Int64 = 0
var probeChargedScans: Int64 = 0
var probeMapVisits: Int64 = 0
var probeCstBytes: Int64 = 0
var probeRepetitions: Int64 = 1
var probeLocalEdit = false
var probeSharedDigests = false

func probeTextBoundaries(source: SourceBuffer, document: ?Document): Array<Int64> {
    let values = HashSet<Int64>()
    values.add(source.text().size)
    if (let Some(doc) <- document) {
        for (event in doc.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                if (let Some(span) <- node.span) {
                    values.add(source.decodedOffset(span.startByte))
                    values.add(source.decodedOffset(span.endByte))
                }
            }
        }
    }
    let result = ArrayList<Int64>()
    for (value in values) {
        result.add(value)
    }
    let ordered = result.toArray()
    sort(ordered, lessThan: {left, right => left < right})
    ordered
}

func probeTextByte(byte: Byte): Bool {
    byte != b' ' && byte != b'\t' && byte != 10 && byte != 13 && byte != b'`' && byte != b'~' && byte != b'<' && byte !=
        b'&' && byte != b':' && byte != b'\\' && byte != b'#' && byte != b'>' && byte != b'*' && byte != b'_' && byte !=
        b'[' && byte != b']' && byte != b'(' && byte != b')'
}

func probeTextBitmap(source: SourceBuffer, document: ?Document): Array<Bool> {
    let boundaries = Array<Bool>(source.text().size + 1, repeat: false)
    if (let Some(doc) <- document) {
        for (event in doc.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                if (let Some(span) <- node.span) {
                    boundaries[source.decodedOffset(span.startByte)] = true
                    boundaries[source.decodedOffset(span.endByte)] = true
                }
            }
        }
    }
    boundaries
}

func probeSource(size: Int64): String {
    let out = StringBuilder()
    let prefix = "# heading\n\nalpha中文😀 paragraph\r\n\r\n"
    let line = "paragraph plain text for edit measurement 中文😀.\r\n\r\n"
    out.append(prefix)
    var bytes = prefix.size
    while (bytes < size) {
        out.append(line);
        bytes += line.size
    }
    out.toString()
}

func probeRss(): String {
    let out = StringBuilder()
    for (line in String.fromUtf8(File.readFrom("/proc/self/status")).split("\n")) {
        if (line.startsWith("VmHWM:") || line.startsWith("VmRSS:")) {
            out.append(line);
            out.append(";")
        }
    }
    out.toString()
}

func measured<T>(work: () -> T): T {
    let before = probeRss()
    probeAstRecords = 0
    probeSyntaxTokens = 0
    probeSyntaxNodes = 0
    probeChargedScans = 0
    probeMapVisits = 0
    probeCstBytes = 0
    let begin = MonoTime.now()
    var value = work()
    for (_ in 1..probeRepetitions) {
        value = work()
    }
    let elapsed = (MonoTime.now() - begin).toNanoseconds()
    println(
        "metrics\t${elapsed}\t${probeAstRecords}\t${probeSyntaxTokens}\t${probeSyntaxNodes}\t${probeChargedScans}\t${probeMapVisits}\t${probeCstBytes}")
    println("rssBefore\t${before}")
    println("rssAfter\t${probeRss()}")
    value
}

func probeCheck(snapshot: DocumentSnapshot, source: String): Unit {
    if (snapshot.result.source.text() != source || snapshot.syntaxTree.losslessText() != source) {
        throw IllegalStateException("snapshot source differs")
    }
    let expected = snapshot.engine.parse(source)
    if (snapshot.result.document.nodeCount != expected.document.nodeCount) {
        throw IllegalStateException("snapshot AST size differs")
    }
    let actual = snapshot.engine.htmlRenderer().renderWithSourceMap(snapshot.result.document)
    let wanted = snapshot.engine.htmlRenderer().renderWithSourceMap(expected.document)
    if (actual.content != wanted.content || actual.sourceMap.size != wanted.sourceMap.size ||
        snapshot.result.diagnostics.size != expected.diagnostics.size) {
        throw IllegalStateException("snapshot output differs")
    }
    for (index in 0..actual.sourceMap.size) {
        if (actual.sourceMap[index].sourceSpan != wanted.sourceMap[index].sourceSpan ||
            actual.sourceMap[index].outputRange != wanted.sourceMap[index].outputRange) {
            throw IllegalStateException("snapshot map differs")
        }
    }
    var end: Int64 = 0
    for (token in snapshot.syntaxTree.root.tokens.toArray()) {
        if (token.span.startByte != end || snapshot.result.source.slice(token.span) != token.raw) {
            throw IllegalStateException("token coverage differs")
        }
        end = token.span.endByte
    }
    if (end != source.size) {
        throw IllegalStateException("incomplete token coverage")
    }
    let expectedSnapshot = DocumentSnapshot(snapshot.engine, 1, expected)
    let actualTokens = snapshot.syntaxTree.root.tokens
    let expectedTokens = expectedSnapshot.syntaxTree.root.tokens
    if (actualTokens.size != expectedTokens.size) {
        throw IllegalStateException("CST token count differs")
    }
    for (index in 0..actualTokens.size) {
        if (actualTokens[index].raw != expectedTokens[index].raw || actualTokens[index].span != expectedTokens[index]
            .span) {
            throw IllegalStateException("CST token identity differs")
        }
    }
    let left = BinaryArtifactCodec.encode(snapshot).bytes()
    let right = BinaryArtifactCodec.encode(expectedSnapshot).bytes()
    if (left.size != right.size) {
        throw IllegalStateException("snapshot semantic digest size differs")
    }
    for (index in 0..left.size) {
        if (left[index] != right[index]) {
            throw IllegalStateException("snapshot semantic digest differs")
        }
    }
}

func editSequence(snapshot: DocumentSnapshot, variable: Bool): DocumentSnapshot {
    var current = snapshot
    var hits: Int64 = 0
    for (index in 0..10) {
        let edit = if (variable) {
            if (index % 2 == 0) {
                SourceEdit(SourceSpan(11, 11), "x")
            } else {
                SourceEdit(SourceSpan(11, 12), "")
            }
        } else {
            SourceEdit(SourceSpan(11, 16), if (index % 2 == 0) {
                "omega"
            } else {
                "alpha"
            })
        }
        let local: ?DocumentSnapshot = if (variable && probeLocalEdit) {
            probeVariableEdit(current, edit)
        } else {
            None
        }
        if (let Some(value) <- local) {
            hits++
            current = value
        } else {
            let next = current.applyEdits([edit])
            if (next.wasIncremental) {
                hits++
            }
            current = next.snapshot
        }
    }
    println("editHits\t${hits}\t10")
    current
}

main(args: Array<String>): Int64 {
    if (args.size != 4 && args.size != 5) {
        throw IllegalArgumentException("mode phase size private-file [repetitions]")
    }
    if (args.size == 5) {
        probeRepetitions = Int64.parse(args[4])
    }
    if (probeRepetitions <= 0) {
        throw IllegalArgumentException("positive repetition count required")
    }
    probeCoalesceCst = args[0] == "candidate" || args[0] == "bitmap"
    probeBitmapCst = args[0] == "bitmap"
    probeLocalEdit = args[0] == "local"
    probeSharedDigests = args[0] == "shared"
    let phase = args[1]
    let source = probeSource(Int64.parse(args[2]))
    let engine = MarkdownEngine.builder().build()
    println("case\t${args[0]}\t${phase}\t${source.size}")
    match (phase) {
        case "cache-prepare" | "cache-encode" | "cache-write" =>
            let snapshot = engine.parseSnapshot(source)
            let bytes = if (phase == "cache-prepare") {
                probeEncodeCache(snapshot, args[0])
            } else {
                measured(
                    {
                        =>
                            let encoded = probeEncodeCache(snapshot, args[0])
                            if (phase == "cache-write") {
                                File.writeTo(args[3], encoded)
                            }
                            encoded
                    }
                )
            }
            File.writeTo(args[3], bytes)
            println("artifactBytes\t${bytes.size}")
            probeCheck(probeDecodeCache(engine, bytes, args[0]), source)
        case "cache-decode" | "cache-read-decode" =>
            let bytes: Array<Byte> = if (phase == "cache-decode") {
                File.readFrom(args[3])
            } else {
                []
            }
            let value = measured({
                => probeDecodeCache(engine, if (phase == "cache-decode") {
                    bytes
                } else {
                    File.readFrom(args[3])
                }, args[0])
            })
            probeCheck(value, source)
        case "local-proof" =>
            let original = engine.parseSnapshot(source)
            let inserted = probeVariableEdit(original, SourceEdit(SourceSpan(11, 11), "x")).getOrThrow()
            probeCheck(inserted, source[..11] + "x" + source[11..])
            let removed = probeVariableEdit(inserted, SourceEdit(SourceSpan(11, 12), "")).getOrThrow()
            probeCheck(removed, source)
        case "parse" =>
            let value = measured({=> engine.parse(source)})
            if (value.source.text() != source) {
                throw IllegalStateException("parse source differs")
            }
        case "snapshot" => probeCheck(measured({=> engine.parseSnapshot(source)}), source)
        case "cst" =>
            let value = engine.parse(source)
            let syntax = measured({=> SyntaxTree.parse(value.source, document: Some(value.document))})
            if (syntax.losslessText() != source) {
                throw IllegalStateException("CST source differs")
            }
        case "map" =>
            let value = engine.parse(source)
            let syntax = SyntaxTree.parse(value.source, document: Some(value.document))
            let map = measured({=> SyntaxToAstMap(syntax, value.document)})
            if (map.originatingTokens(value.document.root()).size != syntax.root.tokens.size) {
                throw IllegalStateException("map root differs")
            }
        case "equal-edit" | "variable-edit" =>
            let snapshot = engine.parseSnapshot(source)
            probeCheck(measured({=> editSequence(snapshot, phase == "variable-edit")}), source)
        case "encode" | "write" | "decode" | "read-decode" =>
            let snapshot = engine.parseSnapshot(source)
            let artifact = BinaryArtifactCodec.encode(snapshot)
            if (phase == "encode") {
                let value = measured({=> BinaryArtifactCodec.encode(snapshot)})
                println("artifactBytes\t${value.bytes().size}")
            } else if (phase == "write") {
                let value = measured(
                    {
                        =>
                            let bytes = BinaryArtifactCodec.encode(snapshot).bytes()
                            File.writeTo(args[3], bytes)
                            bytes.size
                    }
                )
                println("artifactBytes\t${value}")
            } else {
                File.writeTo(args[3], artifact.bytes())
                let value = measured({
                    => BinaryArtifactCodec.decode(engine, if (phase == "read-decode") {
                        BinarySnapshotArtifact(File.readFrom(args[3]))
                    } else {
                        artifact
                    })
                })
                match (value) {
                    case BinaryArtifactLoadResult.Hit(restored) => probeCheck(restored, source)
                    case BinaryArtifactLoadResult.CacheMiss(reason) => throw IllegalStateException(reason)
                }
            }
        case "render" | "source-map" =>
            let document = engine.parse(source).document
            if (phase == "render") {
                let value = measured({=> engine.htmlRenderer().render(document)})
                println("outputBytes\t${value.size}")
            } else {
                let value = measured({=> engine.htmlRenderer().renderWithSourceMap(document)})
                println("outputBytes\t${value.content.size}")
            }
        case _ => throw IllegalArgumentException("unknown phase")
    }
    println("PASS editor cost probe")
    0
}
