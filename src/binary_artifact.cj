package markdown

import std.collection.*

public class BinarySnapshotArtifact {
    public let schemaVersion: String
    private let data: Array<Byte>
    public init(data: Array<Byte>) {
        this.schemaVersion = "markdown-snapshot-binary-1"
        this.data = data.clone()
    }
    public func bytes(): Array<Byte> {
        data.clone()
    }
}

public enum BinaryArtifactLoadResult {
    | Hit(DocumentSnapshot)
    | CacheMiss(String)
}

public class BinaryArtifactCodec {
    public static func encode(snapshot: DocumentSnapshot): BinarySnapshotArtifact {
        if (!snapshot.result.source.hasIdentityMapping()) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact,
                "binary artifacts require an identity-preserving UTF-8 source mapping", phase: "artifact_encode")
        }
        let out = ArrayList<Byte>()
        out.add(all: "MCJ1".toArray())
        binaryWriteString(out, snapshot.result.document.profile.id)
        binaryWriteString(out, snapshot.result.document.dialectFingerprint)
        binaryWriteString(out, binaryEngineFingerprint(snapshot.engine))
        binaryWriteString(out, snapshot.sourceDigest)
        binaryWriteString(out, binaryAstDigest(snapshot.result.document))
        binaryWriteString(out, Sha256.digest(snapshot.syntaxTree.losslessText()))
        binaryWriteString(out, snapshot.result.source.text())
        BinarySnapshotArtifact(out.toArray())
    }

    public static func decode(engine: MarkdownEngine, artifact: BinarySnapshotArtifact): BinaryArtifactLoadResult {
        let data = artifact.bytes()
        if (data.size > engine.limits.maximumInputBytes + 1024 * 1024) {
            return BinaryArtifactLoadResult.CacheMiss("artifact size")
        }
        try {
            let reader = BinaryArtifactReader(data)
            if (reader.readFixed(4) != "MCJ1") {
                return BinaryArtifactLoadResult.CacheMiss("schema magic")
            }
            let profile = reader.readString()
            let dialect = reader.readString()
            let engineFingerprint = reader.readString()
            let sourceDigest = reader.readString()
            let astDigest = reader.readString()
            let cstDigest = reader.readString()
            let source = reader.readString()
            if (!reader.isFinished()) {
                return BinaryArtifactLoadResult.CacheMiss("trailing bytes")
            }
            if (profile != engine.profile.id) {
                return BinaryArtifactLoadResult.CacheMiss("profile id")
            }
            if (dialect != engine.dialect.fingerprint) {
                return BinaryArtifactLoadResult.CacheMiss("dialect fingerprint")
            }
            if (engineFingerprint != binaryEngineFingerprint(engine)) {
                return BinaryArtifactLoadResult.CacheMiss("engine fingerprint")
            }
            if (sourceDigest != Sha256.digest(source)) {
                return BinaryArtifactLoadResult.CacheMiss("source digest")
            }
            let snapshot = engine.parseSnapshot(source)
            if (astDigest != binaryAstDigest(snapshot.result.document)) {
                return BinaryArtifactLoadResult.CacheMiss("AST digest")
            }
            if (cstDigest != Sha256.digest(snapshot.syntaxTree.losslessText())) {
                return BinaryArtifactLoadResult.CacheMiss("CST digest")
            }
            BinaryArtifactLoadResult.Hit(snapshot)
        } catch (_: Exception) {
            BinaryArtifactLoadResult.CacheMiss("malformed artifact")
        }
    }
}

internal class BinaryArtifactReader {
    private let data: Array<Byte>
    private var offset: Int64 = 0
    init(data: Array<Byte>) {
        this.data = data
    }
    func readFixed(size: Int64): String {
        if (size < 0 || offset + size > data.size) {
            throw IllegalArgumentException("truncated artifact")
        }
        let value = String.fromUtf8(data.slice(offset, size));
        offset += size
        value
    }
    func readString(): String {
        let size = readU64()
        if (size > UInt64(Int64.Max) || offset + Int64(size) > data.size) {
            throw IllegalArgumentException("invalid artifact string length")
        }
        readFixed(Int64(size))
    }
    func isFinished(): Bool {
        offset == data.size
    }
    private func readU64(): UInt64 {
        if (offset + 8 > data.size) {
            throw IllegalArgumentException("truncated artifact length")
        }
        var value: UInt64 = 0
        for (_ in 0..8) {
            value = (value << 8) | UInt64(data[offset])
            offset++
        }
        value
    }
}

private func binaryWriteString(out: ArrayList<Byte>, value: String): Unit {
    let bytes = value.toArray()
    binaryWriteU64(out, UInt64(bytes.size));
    out.add(all: bytes)
}

private func binaryWriteU64(out: ArrayList<Byte>, value: UInt64): Unit {
    for (shift in [56, 48, 40, 32, 24, 16, 8, 0]) {
        out.add(UInt8((value >> UInt64(shift)) & 0xff))
    }
}

private func binaryEngineFingerprint(engine: MarkdownEngine): String {
    let limits = engine.limits
    let out = CanonicalDescriptor()
    out.append("engine")
    out.append(engine.dialect.fingerprint)
    out.append(limits.maximumInputBytes)
    out.append(limits.maximumLineBytes)
    out.append(limits.maximumNestingDepth)
    out.append(limits.maximumAstNodes)
    out.append(limits.maximumReferences)
    out.append(limits.maximumTableColumns)
    out.append(limits.maximumUrlBytes)
    out.append(limits.maximumLiteralBytes)
    out.append(limits.maximumOutputBytes)
    out.append(limits.maximumExtensionCaptureBytes)
    out.append(limits.maximumExtensionLookaheadBytes)
    Sha256.digest(out.toString())
}

private func binaryAstDigest(document: Document): String {
    let out = CanonicalDescriptor()
    for (event in document.walk()) {
        match (event) {
            case WalkEvent.Enter(node) =>
                out.append("+");
                out.append(binaryNodeKind(node));
                out.append(":");
                out.append(node.nodeId.value)
                if (let Some(span) <- node.span) {
                    out.append("@");
                    out.append(span.startByte);
                    out.append(":");
                    out.append(span.endByte)
                }
                appendBinarySemantic(out, node)
            case WalkEvent.Exit(node) =>
                out.append("-");
                out.append(binaryNodeKind(node));
                out.append(";")
        }
    }
    Sha256.digest(out.toString())
}

private func appendBinarySemantic(out: CanonicalDescriptor, node: MarkdownNode): Unit {
    match (node) {
        case value: Text =>
            out.append("=");
            out.append(value.raw);
            out.append("=>");
            out.append(value.value)
        case value: Heading =>
            out.append("=");
            out.append(value.level)
        case value: CodeBlock =>
            out.append("=");
            out.append(value.literal);
            out.append(":");
            out.append(value.infoRaw)
        case value: CodeSpan =>
            out.append("=");
            out.append(value.literal)
        case value: HtmlBlock =>
            out.append("=");
            out.append(value.literal)
        case value: HtmlInline =>
            out.append("=");
            out.append(value.literal)
        case value: Link =>
            out.append("=");
            out.append(value.destination);
            out.append(":");
            out.append(value.title)
        case value: Image =>
            out.append("=");
            out.append(value.destination);
            out.append(":");
            out.append(value.title)
        case value: List =>
            out.append("=");
            out.append(value.start);
            out.append(":");
            out.append(value.tight)
        case value: ListItem =>
            out.append("=");
            out.append(binaryTaskState(value.taskState))
        case value: CustomBlock =>
            out.append("=");
            out.append(value.extensionId);
            out.append(":");
            out.append(value.localKindId)
        case value: CustomInline =>
            out.append("=");
            out.append(value.extensionId);
            out.append(":");
            out.append(value.localKindId)
        case _ => ()
    }
}

private func binaryNodeKind(node: MarkdownNode): String {
    match (node) {
        case _: Document => "document";
        case _: BlockQuote => "quote";
        case _: List => "list"
        case _: ListItem => "item";
        case _: Paragraph => "paragraph";
        case _: Heading => "heading"
        case _: ThematicBreak => "break";
        case _: CodeBlock => "code-block";
        case _: HtmlBlock => "html-block"
        case _: Table => "table";
        case _: TableRow => "row";
        case _: TableCell => "cell"
        case _: CustomBlock => "custom-block";
        case _: Text => "text";
        case _: SoftBreak => "soft"
        case _: HardBreak => "hard";
        case _: CodeSpan => "code";
        case _: Emphasis => "em"
        case _: Strong => "strong";
        case _: Strikethrough => "strike";
        case _: Link => "link"
        case _: Image => "image";
        case _: HtmlInline => "html-inline";
        case _: CustomInline => "custom-inline"
        case _ => "unknown"
    }
}

private func binaryTaskState(value: TaskState): String {
    match (value) {
        case TaskState.NotTask => "none";
        case TaskState.Checked => "checked";
        case TaskState.Unchecked => "unchecked"
    }
}
