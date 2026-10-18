package markdown

import std.collection.*

/** `DocumentSnapshot` 的二进制快照容器；`bytes()` 返回独立副本。 */
public class BinarySnapshotArtifact {
    /** 快照二进制格式的 schema 版本标识。 */
    public let schemaVersion: String
    private let data: Array<Byte>
    /**
     * 用原始字节构造快照容器。
     * @param data 快照的完整二进制内容，构造时会复制一份。
     */
    public init(data: Array<Byte>) {
        this.schemaVersion = "markdown-snapshot-binary-3"
        this.data = data.clone()
    }
    /**
     * 返回快照的二进制副本。
     * @return 快照二进制的独立副本。
     */
    public func bytes(): Array<Byte> {
        data.clone()
    }
}

/** 二进制快照解码结果。 */
public enum BinaryArtifactLoadResult {
    /** 快照命中，携带解码出的 `DocumentSnapshot`。 */
    | Hit(DocumentSnapshot)
    /** 快照未命中，携带原因说明文本。 */
    | CacheMiss(String)
}

/** 编解码包含 AST、CST 和身份 digest 的 binary snapshot。 */
public class BinaryArtifactCodec {
    /** 读取显式提供的持久化快照；旧版和未知版明确报 UnsupportedVersion。
     * @param engine 用于身份及资源校验的目标 engine。
     * @param data 持久化快照字节。
     * @return 经当前格式校验的 snapshot。
     * @throws MarkdownException 版本不支持、身份不符或内容无效时。
     */
    public static func read(engine: MarkdownEngine, data: Array<Byte>): DocumentSnapshot {
        if (data.size >= 4 && data[0] == b'M' && data[1] == b'C' && data[2] == b'J' && data[3] != b'3') {
            throw MarkdownException(MarkdownErrorCode.UnsupportedVersion, "unsupported binary snapshot version",
                phase: "artifact_decode")
        }
        if (data.size > engine.limits.maximumInputBytes && data.size - engine.limits.maximumInputBytes > 1024 * 1024) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact, "binary snapshot exceeds the input limit",
                phase: "artifact_decode")
        }
        match (decode(engine, BinarySnapshotArtifact(data))) {
            case BinaryArtifactLoadResult.Hit(snapshot) => snapshot
            case BinaryArtifactLoadResult.CacheMiss(reason) => throw MarkdownException(
                MarkdownErrorCode.InvalidArtifact, "invalid binary snapshot: ${reason}", phase: "artifact_decode")
        }
    }

    /** 编码完整且 identity-preserving 的 snapshot；不支持非 identity UTF-8 mapping。
     * @param snapshot 要编码的完整 snapshot。
     * @return 编码后的二进制快照。
     * @throws MarkdownException snapshot 的 UTF-8 mapping 非 identity 时。
     */
    public static func encode(snapshot: DocumentSnapshot): BinarySnapshotArtifact {
        if (!snapshot.result.source.hasIdentityMapping()) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact,
                "binary artifacts require an identity-preserving UTF-8 source mapping", phase: "artifact_encode")
        }
        let out = ArrayList<Byte>()
        let originalBytes = snapshot.result.source.originalBytesForArtifact()
        out.add(all: "MCJ3".toArray())
        let root = snapshot.result.document.root().asDocument().getOrThrow()
        binaryWriteString(out, root.profile.id)
        binaryWriteString(out, root.dialectFingerprint)
        binaryWriteString(out,
            parserConfigurationFingerprint(snapshot.engine.dialect.fingerprint, snapshot.engine.limits,
                snapshot.engine.bindingOptions))
        binaryWriteString(out, binaryUtf8PolicyId(snapshot.result.source.decodePolicy()))
        binaryWriteString(out, Sha256.digestBytes(originalBytes))
        binaryWriteString(out, Sha256.digest(snapshot.result.source.text()))
        binaryWriteString(out,
            binaryIdentityOffsetMappingDigest(originalBytes.size, snapshot.result.source.decodePolicy()))
        binaryWriteString(out, binaryAstDigest(snapshot.result.document))
        binaryWriteString(out, Sha256.digest(snapshot.syntaxTree.losslessText()))
        binaryWriteString(out, snapshot.result.source.text())
        BinarySnapshotArtifact(out.toArray())
    }

    /** 按 engine 身份、digest 和 schema 校验并解码 snapshot；失败返回 `CacheMiss`。
     * @param engine 用于身份校验并提供解析限制的目标 engine。
     * @param artifact 待解码的二进制快照。
     * @return `Hit` 或带原因的 `CacheMiss`。
     */
    public static func decode(engine: MarkdownEngine, artifact: BinarySnapshotArtifact): BinaryArtifactLoadResult {
        let data = artifact.bytes()
        if (data.size > engine.limits.maximumInputBytes && data.size - engine.limits.maximumInputBytes > 1024 * 1024) {
            return BinaryArtifactLoadResult.CacheMiss("artifact size")
        }
        try {
            let reader = BinaryArtifactReader(data)
            if (reader.readFixed(4) != "MCJ3") {
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
            if (engineFingerprint != parserConfigurationFingerprint(engine.dialect.fingerprint, engine.limits,
                engine.bindingOptions)) {
                return BinaryArtifactLoadResult.CacheMiss("engine fingerprint")
            }
            let utf8Policy = match (utf8PolicyId) {
                case "strict" => Utf8Policy.Strict
                case "replace-invalid" => Utf8Policy.ReplaceInvalid
                case _ => return BinaryArtifactLoadResult.CacheMiss("UTF-8 policy")
            }
            let sourceBytes = source.toArray()
            if (originalBytesDigest != Sha256.digestBytes(sourceBytes)) {
                return BinaryArtifactLoadResult.CacheMiss("original bytes digest")
            }
            if (decodedTextDigest != Sha256.digest(source)) {
                return BinaryArtifactLoadResult.CacheMiss("decoded text digest")
            }
            if (offsetMappingDigest != binaryIdentityOffsetMappingDigest(sourceBytes.size, utf8Policy)) {
                return BinaryArtifactLoadResult.CacheMiss("offset mapping digest")
            }
            let snapshot = DocumentSnapshot(engine, 1, engine.parse(sourceBytes, utf8Policy: utf8Policy))
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

private func binaryUtf8PolicyId(policy: Utf8Policy): String {
    match (policy) {
        case Utf8Policy.Strict => "strict"
        case Utf8Policy.ReplaceInvalid => "replace-invalid"
    }
}

private func binaryIdentityOffsetMappingDigest(byteLength: Int64, utf8Policy: Utf8Policy): String {
    let descriptor = CanonicalDescriptor()
    descriptor.append("identity-offset-mapping")
    descriptor.append(byteLength)
    descriptor.append(binaryUtf8PolicyId(utf8Policy))
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

private func binaryAstDigest(document: Document): String {
    let out = CanonicalDescriptor()
    for (event in document.walk()) {
        match (event) {
            case NodeRefWalkEvent.Enter(node) =>
                out.append("+");
                out.append(binaryNodeKind(node));
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
            appendBinaryCustomPayload(out, value.payload)
        case NodeKind.CustomInline =>
            let value = node.asCustomInline().getOrThrow()
            out.append("=");
            out.append(value.extensionId);
            out.append(":");
            out.append(value.localKindId)
            appendBinaryCustomPayload(out, value.payload)
        case _ => ()
    }
}

private func appendBinaryCustomPayload(out: CanonicalDescriptor, payload: CustomPayload): Unit {
    out.append(payload.payloadTypeId())
    match (payload) {
        case value: HeadingIdPayload =>
            out.append(value.rawId)
            out.append(value.idSpan.startByte)
            out.append(value.idSpan.endByte)
        case value: FootnoteDefinitionPayload =>
            out.append(value.labelRaw)
            out.append(value.labelNormalized)
            out.append(value.labelSpan.startByte)
            out.append(value.labelSpan.endByte)
        case value: FootnoteReferencePayload =>
            out.append(value.labelRaw)
            out.append(value.labelNormalized)
            out.append(value.labelSpan.startByte)
            out.append(value.labelSpan.endByte)
        case value: SyntaxPayload =>
            out.append(value.name)
            out.append(value.parameters)
            out.append(value.literal)
        case _ => ()
    }
}

private func binaryNodeKind(node: NodeRef): String {
    match (node.kind) {
        case NodeKind.DocumentNode => "document";
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
