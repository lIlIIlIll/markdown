package markdown

import std.collection.*

/** 一段 renderer 输出与 source span、NodeId 的映射记录。 */
public class RenderedSourceMapEntry {
    /** 输出中的 byte range。 */
    public let outputRange: SourceSpan
    /** 对应的 source span；generated 内容为 `None`。 */
    public let sourceSpan: ?SourceSpan
    /** 产生该输出的 AST 节点 id；generated 内容为 `None`。 */
    public let nodeId: ?NodeId
    /** 是否为 renderer 生成的非 source 内容。 */
    public let generated: Bool
    /**
     * 创建 source map 记录。
     * @param outputRange 输出中的 byte range。
     * @param sourceSpan 对应的 source span，generated 内容为 `None`。
     * @param nodeId 产生该输出的节点 id，generated 内容为 `None`。
     * @param generated 是否为 renderer 生成的非 source 内容。
     */
    public init(outputRange: SourceSpan, sourceSpan: ?SourceSpan, nodeId: ?NodeId, generated: Bool) {
        this.outputRange = outputRange
        this.sourceSpan = sourceSpan
        this.nodeId = nodeId
        this.generated = generated
    }
}

/** 带 source map 的 HTML 输出；查询按 output byte range 工作。 */
public class RenderedOutput {
    /** 渲染得到的 HTML 文本。 */
    public let content: String
    /** 按 output byte 排序的 source map 记录。 */
    public let sourceMap: ImmutableArray<RenderedSourceMapEntry>
    /**
     * 创建带 source map 的输出。
     * @param content 渲染得到的 HTML 文本。
     * @param sourceMap source map 记录列表。
     */
    public init(content: String, sourceMap: Array<RenderedSourceMapEntry>) {
        this.content = content
        this.sourceMap = ImmutableArray<RenderedSourceMapEntry>(sourceMap)
    }

    /** 查询 output byte 对应的 source span；无 source 对应的 generated 片段返回 None。
     * @param outputByte 输出中的字节偏移。
     * @return 对应的 source span；generated 片段为 `None`。
     * @throws IllegalArgumentException outputByte 越界时。
     */
    public func sourceSpanAt(outputByte: Int64): ?SourceSpan {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        findEntry(outputByte).sourceSpan
    }

    /** 查询 output byte 对应的 NodeId；generated 片段返回 None。
     * @param outputByte 输出中的字节偏移。
     * @return 对应的 `NodeId`；generated 片段为 `None`。
     * @throws IllegalArgumentException outputByte 越界时。
     */
    public func nodeIdAt(outputByte: Int64): ?NodeId {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        findEntry(outputByte).nodeId
    }

    /** 返回一个 NodeId 产生的所有 output ranges。
     * @param nodeId 目标节点 id。
     * @return 该节点产生的全部 output range。
     */
    public func outputRanges(nodeId: NodeId): Array<SourceSpan> {
        let ranges = ArrayList<SourceSpan>()
        for (entry in sourceMap.toArray()) {
            if (entry.nodeId == Some(nodeId)) {
                ranges.add(entry.outputRange)
            }
        }
        ranges.toArray()
    }

    private func findEntry(outputByte: Int64): RenderedSourceMapEntry {
        var low: Int64 = 0
        var high = sourceMap.size
        while (low < high) {
            let middle = low + (high - low) / 2
            let entry = sourceMap[middle]
            if (outputByte < entry.outputRange.startByte) {
                high = middle
            } else if (outputByte >= entry.outputRange.endByte) {
                low = middle + 1
            } else {
                return entry
            }
        }
        throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
            "rendered source map does not cover output byte", phase: "source_map")
    }
}

extend HtmlRenderer {
    /**
     * 渲染 HTML 并同步记录 output-to-source map，不通过输出字符串反推映射。
     * @param document 要渲染的 Document。
     * @return 包含 HTML 和 source map 的 `RenderedOutput`。
     * @throws MarkdownException 取消或超出限制时。
     * @throws SinkFailureException sink 写入失败时。
     */
    public func renderWithSourceMap(document: Document): RenderedOutput {
        let sink = StringTextSink(true)
        renderTo(document, sink)
        RenderedOutput(sink.content(), sink.sourceMap())
    }
}

/** 文本 parse artifact 加载结果。 */
public enum ArtifactLoadResult {
    /** 命中，携带反序列化的 `Document`。 */
    | Hit(Document)
    /** 未命中，携带原因说明。 */
    | CacheMiss(String)
}

/**
 * 与 parser、profile、dialect、engine 和原始输入 digest 绑定的文本 parse artifact。
 *
 * `createArtifact` 只接受完整且 identity-preserving 的 parse result；`loadArtifact`
 * 在任一身份、schema、policy 或 digest 不匹配时返回 `CacheMiss`。
 */
public class MarkdownParseArtifact {
    /** artifact schema 版本。 */
    public let schemaVersion: String
    /** 生成本 artifact 的库版本。 */
    public let libraryVersion: String
    /** parser 计划版本。 */
    public let parserPlanVersion: String
    /** 使用的 profile id。 */
    public let profileId: String
    /** dialect fingerprint。 */
    public let dialectFingerprint: String
    /** engine 身份 fingerprint。 */
    public let engineFingerprint: String
    /** 原始输入字节的 SHA-256。 */
    public let sourceDigest: String
    /** 解码文本的 SHA-256。 */
    public let decodedTextDigest: String
    /** 解码使用的 UTF-8 策略 id。 */
    public let utf8PolicyId: String
    /** 偏移映射 digest。 */
    public let offsetMappingDigest: String
    /** 解析得到的 Document。 */
    public let ast: Document
    /** 文档级引用定义。 */
    public let references: ImmutableArray<ReferenceDefinition>
    /** 解析诊断。 */
    public let diagnostics: ImmutableArray<Diagnostic>
    internal let profileIdentity: String

    internal init(engine: MarkdownEngine, result: ParseResult) {
        schemaVersion = "2"
        libraryVersion = "0.9.0"
        parserPlanVersion = "2"
        profileId = engine.profile.id
        dialectFingerprint = engine.dialect.fingerprint
        engineFingerprint = computeEngineFingerprint(engine)
        let originalBytes = result.source.originalBytesForArtifact()
        sourceDigest = Sha256.digestBytes(originalBytes)
        decodedTextDigest = Sha256.digest(result.source.text())
        utf8PolicyId = artifactUtf8PolicyId(result.source.decodePolicy())
        offsetMappingDigest = identityOffsetMappingDigest(originalBytes.size)
        ast = result.ast
        references = result.ast.root().asDocument().getOrThrow().references
        diagnostics = result.diagnostics
        profileIdentity = profileIdentityDescriptor(engine.profile)
    }

    /**
     * 返回用于诊断的简短 JSON，不是稳定序列化格式。
     * @return 用于诊断的简短 JSON 文本。
     */
    public func debugJson(): String {
        "{\"debug\":true,\"profile\":\"${profileId}\",\"nodes\":${ast.nodeCount}}"
    }
}

extend MarkdownEngine {
    /**
     * 创建绑定当前 engine 和完整 parse result 的 artifact。
     * @param result 当前 engine 产生的完整 parse result。
     * @return 可用于 identity 校验和缓存加载的 artifact。
     * @throws MarkdownException result 不完整、mapping 非 identity 或 provenance 不匹配时。
     */
    public func createArtifact(result: ParseResult): MarkdownParseArtifact {
        if (!result.isComplete) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact, "partial parse results cannot be cached",
                phase: "artifact_encode")
        }
        if (!result.source.hasIdentityMapping()) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact,
                "artifacts require an identity-preserving UTF-8 source mapping", phase: "artifact_encode")
        }
        let originalBytes = result.source.originalBytesForArtifact()
        match (artifactDocumentProvenanceFailure(
            result.ast,
            profile,
            dialect.fingerprint,
            Sha256.digestBytes(originalBytes),
            Sha256.digest(result.source.text()),
            artifactUtf8PolicyId(result.source.decodePolicy()),
            originalBytes.size
        )) {
            case Some(reason) => throw MarkdownException(
                MarkdownErrorCode.InvalidArtifact,
                "parse result provenance does not match the artifact engine: ${reason}",
                phase: "artifact_encode"
            )
            case None => ()
        }
        MarkdownParseArtifact(this, result)
    }

    /**
     * 用 String 输入校验 artifact 身份，命中时返回其中的 Document。
     * @param artifact 待校验的 artifact。
     * @param source 与 artifact 对应的源文本。
     * @return `Hit` 或带原因的 `CacheMiss`。
     */
    public func loadArtifact(artifact: MarkdownParseArtifact, source: String): ArtifactLoadResult {
        loadArtifactIdentity(artifact, source.toArray(), source, "strict")
    }

    /**
     * 用 bytes 和 UTF-8 policy 校验 artifact；不匹配时返回带原因的 `CacheMiss`。
     * @param artifact 待校验的 artifact。
     * @param source 原始 UTF-8 bytes。
     * @param utf8Policy bytes 的解码策略。
     * @return `Hit` 或带原因的 `CacheMiss`。
     */
    public func loadArtifact(artifact: MarkdownParseArtifact, source: Array<Byte>,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict): ArtifactLoadResult {
        let decoded = try {
            String.fromUtf8(source)
        } catch (_: Exception) {
            return ArtifactLoadResult.CacheMiss("source encoding")
        }
        loadArtifactIdentity(artifact, source, decoded, artifactUtf8PolicyId(utf8Policy))
    }

    private func loadArtifactIdentity(artifact: MarkdownParseArtifact, originalBytes: Array<Byte>, decoded: String,
        utf8PolicyId: String): ArtifactLoadResult {
        if (artifact.schemaVersion != "2") {
            return ArtifactLoadResult.CacheMiss("schema version")
        }
        if (artifact.parserPlanVersion != "2") {
            return ArtifactLoadResult.CacheMiss("parser plan version")
        }
        if (artifact.profileId != profile.id) {
            return ArtifactLoadResult.CacheMiss("profile id")
        }
        if (artifact.profileIdentity != profileIdentityDescriptor(profile)) {
            return ArtifactLoadResult.CacheMiss("profile identity")
        }
        if (artifact.dialectFingerprint != dialect.fingerprint) {
            return ArtifactLoadResult.CacheMiss("dialect fingerprint")
        }
        if (artifact.engineFingerprint != computeEngineFingerprint(this)) {
            return ArtifactLoadResult.CacheMiss("engine fingerprint")
        }
        if (artifact.utf8PolicyId != utf8PolicyId) {
            return ArtifactLoadResult.CacheMiss("UTF-8 policy")
        }
        if (artifact.sourceDigest != Sha256.digestBytes(originalBytes)) {
            return ArtifactLoadResult.CacheMiss("source digest")
        }
        if (artifact.decodedTextDigest != Sha256.digest(decoded)) {
            return ArtifactLoadResult.CacheMiss("decoded text digest")
        }
        if (artifact.offsetMappingDigest != identityOffsetMappingDigest(originalBytes.size)) {
            return ArtifactLoadResult.CacheMiss("offset mapping digest")
        }
        match (artifactDocumentProvenanceFailure(
            artifact.ast,
            profile,
            dialect.fingerprint,
            artifact.sourceDigest,
            artifact.decodedTextDigest,
            artifact.utf8PolicyId,
            originalBytes.size
        )) {
            case Some(reason) => return ArtifactLoadResult.CacheMiss(reason)
            case None => ()
        }
        try {
            AstInvariantValidator().validate(artifact.ast, limits: limits)
        } catch (_: Exception) {
            return ArtifactLoadResult.CacheMiss("AST invariants")
        }
        ArtifactLoadResult.Hit(artifact.ast)
    }
}

private func artifactDocumentProvenanceFailure(
    document: Document,
    expectedProfile: MarkdownProfile,
    expectedDialectFingerprint: String,
    expectedSourceDigest: String,
    expectedDecodedTextDigest: String,
    expectedUtf8PolicyId: String,
    expectedByteLength: Int64
): ?String {
    let root = match (document.root().asDocument()) {
        case Some(value) => value
        case None => return Some("AST document root")
    }
    if (!root.profile.sameIdentity(expectedProfile)) {
        return Some("AST profile")
    }
    if (root.dialectFingerprint != expectedDialectFingerprint) {
        return Some("AST dialect fingerprint")
    }
    let documentSource = match (document.parserSourceBuffer()) {
        case Some(value) => value
        case None => return Some("AST source provenance")
    }
    if (!documentSource.hasIdentityMapping()) {
        return Some("AST source mapping")
    }
    if (artifactUtf8PolicyId(documentSource.decodePolicy()) != expectedUtf8PolicyId) {
        return Some("AST UTF-8 policy")
    }
    if (Sha256.digestBytes(documentSource.originalBytesForArtifact()) != expectedSourceDigest) {
        return Some("AST source digest")
    }
    if (Sha256.digest(documentSource.text()) != expectedDecodedTextDigest) {
        return Some("AST decoded text digest")
    }
    if (root.node.span != Some(SourceSpan(0, expectedByteLength))) {
        return Some("AST source span")
    }
    None
}

private func artifactUtf8PolicyId(policy: Utf8Policy): String {
    match (policy) {
        case Utf8Policy.Strict => "strict"
        case Utf8Policy.ReplaceInvalid => "replace-invalid"
    }
}

private func identityOffsetMappingDigest(byteLength: Int64): String {
    let descriptor = CanonicalDescriptor()
    descriptor.append("identity-offset-mapping")
    descriptor.append(byteLength)
    Sha256.digest(descriptor.toString())
}

private func computeEngineFingerprint(engine: MarkdownEngine): String {
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
