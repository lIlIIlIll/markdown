package markdown

import std.collection.*

public class BinarySnapshotArtifact {
    public let schemaVersion: String
    private let data: Array<Byte>
    public init(data: Array<Byte>) {
        this.schemaVersion = "markdown-snapshot-binary-2"
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
        let originalBytes = snapshot.result.source.originalBytesForArtifact()
        out.add(all: "MCJ2".toArray())
        let root = snapshot.result.ast.root().asDocument().getOrThrow()
        binaryWriteString(out, root.profile.id)
        binaryWriteString(out, root.dialectFingerprint)
        binaryWriteString(out, binaryEngineFingerprint(snapshot.engine))
        binaryWriteString(out, binaryUtf8PolicyId(snapshot.result.source.decodePolicy()))
        binaryWriteString(out, Sha256.digestBytes(originalBytes))
        binaryWriteString(out, Sha256.digest(snapshot.result.source.text()))
        binaryWriteString(out, binaryIdentityOffsetMappingDigest(originalBytes.size))
        binaryWriteString(out, binaryAstDigest(snapshot.result.ast))
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
            if (reader.readFixed(4) != "MCJ2") {
                return BinaryArtifactLoadResult.CacheMiss("schema magic")
            }
            let profile = reader.readString()
            let dialect = reader.readString()
            let engineFingerprint = reader.readString()
            let utf8PolicyId = reader.readString()
            let originalBytesDigest = reader.readString()
            let decodedTextDigest = reader.readString()
            let offsetMappingDigest = reader.readString()
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
            if (utf8PolicyId != "strict" && utf8PolicyId != "replace-invalid") {
                return BinaryArtifactLoadResult.CacheMiss("UTF-8 policy")
            }
            let sourceBytes = source.toArray()
            if (originalBytesDigest != Sha256.digestBytes(sourceBytes)) {
                return BinaryArtifactLoadResult.CacheMiss("original bytes digest")
            }
            if (decodedTextDigest != Sha256.digest(source)) {
                return BinaryArtifactLoadResult.CacheMiss("decoded text digest")
            }
            if (offsetMappingDigest != binaryIdentityOffsetMappingDigest(sourceBytes.size)) {
                return BinaryArtifactLoadResult.CacheMiss("offset mapping digest")
            }
            let snapshot = engine.parseSnapshot(source)
            if (astDigest != binaryAstDigest(snapshot.result.ast)) {
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

private func binaryUtf8PolicyId(policy: Utf8Policy): String {
    match (policy) {
        case Utf8Policy.Strict => "strict"
        case Utf8Policy.ReplaceInvalid => "replace-invalid"
    }
}

private func binaryIdentityOffsetMappingDigest(byteLength: Int64): String {
    let descriptor = CanonicalDescriptor()
    descriptor.append("identity-offset-mapping")
    descriptor.append(byteLength)
    Sha256.digest(descriptor.toString())
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
            case NodeRefWalkEvent.Enter(node) =>
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
            case NodeRefWalkEvent.Exit(node) =>
                out.append("-");
                out.append(binaryNodeKind(node));
                out.append(";")
        }
    }
    Sha256.digest(out.toString())
}

private func appendBinarySemantic(out: CanonicalDescriptor, node: NodeRef): Unit {
    match (node.kind) {
        case NodeKind.Text =>
            let value = node.asText().getOrThrow()
            out.append("=");
            out.append(value.raw);
            out.append("=>");
            out.append(value.value)
        case NodeKind.Heading =>
            let value = node.asHeading().getOrThrow()
            out.append("=");
            out.append(value.level)
        case NodeKind.CodeBlock =>
            let value = node.asCodeBlock().getOrThrow()
            out.append("=");
            out.append(value.literal);
            out.append(":");
            out.append(value.infoRaw)
        case NodeKind.CodeSpan =>
            let value = node.asCodeSpan().getOrThrow()
            out.append("=");
            out.append(value.literal)
        case NodeKind.HtmlBlock =>
            let value = node.asHtmlBlock().getOrThrow()
            out.append("=");
            out.append(value.literal)
        case NodeKind.HtmlInline =>
            let value = node.asHtmlInline().getOrThrow()
            out.append("=");
            out.append(value.literal)
        case NodeKind.Link =>
            let value = node.asLink().getOrThrow()
            out.append("=");
            out.append(value.destination);
            out.append(":");
            out.append(value.title)
        case NodeKind.Image =>
            let value = node.asImage().getOrThrow()
            out.append("=");
            out.append(value.destination);
            out.append(":");
            out.append(value.title)
        case NodeKind.List =>
            let value = node.asList().getOrThrow()
            out.append("=");
            out.append(value.start);
            out.append(":");
            out.append(value.tight)
        case NodeKind.ListItem =>
            let value = node.asListItem().getOrThrow()
            out.append("=");
            out.append(binaryTaskState(value.taskState))
        case NodeKind.CustomBlock =>
            let value = node.asCustomBlock().getOrThrow()
            out.append("=");
            out.append(value.extensionId);
            out.append(":");
            out.append(value.localKindId)
        case NodeKind.CustomInline =>
            let value = node.asCustomInline().getOrThrow()
            out.append("=");
            out.append(value.extensionId);
            out.append(":");
            out.append(value.localKindId)
        case _ => ()
    }
}

private func binaryNodeKind(node: NodeRef): String {
    match (node.kind) {
        case NodeKind.Document => "document";
        case NodeKind.BlockQuote => "quote";
        case NodeKind.List => "list"
        case NodeKind.ListItem => "item";
        case NodeKind.Paragraph => "paragraph";
        case NodeKind.Heading => "heading"
        case NodeKind.ThematicBreak => "break";
        case NodeKind.CodeBlock => "code-block";
        case NodeKind.HtmlBlock => "html-block"
        case NodeKind.Table => "table";
        case NodeKind.TableRow => "row";
        case NodeKind.TableCell => "cell"
        case NodeKind.CustomBlock => "custom-block";
        case NodeKind.Text => "text";
        case NodeKind.SoftBreak => "soft"
        case NodeKind.HardBreak => "hard";
        case NodeKind.CodeSpan => "code";
        case NodeKind.Emphasis => "em"
        case NodeKind.Strong => "strong";
        case NodeKind.Strikethrough => "strike";
        case NodeKind.Link => "link"
        case NodeKind.Image => "image";
        case NodeKind.HtmlInline => "html-inline";
        case NodeKind.CustomInline => "custom-inline"
    }
}

private func binaryTaskState(value: TaskState): String {
    match (value) {
        case TaskState.NotTask => "none";
        case TaskState.Checked => "checked";
        case TaskState.Unchecked => "unchecked"
    }
}
