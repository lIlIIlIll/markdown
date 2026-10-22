package markdown.artifact

import markdown.core.{AstInvariantValidator, CanonicalDescriptor, Diagnostic, Document, ImmutableArray, 
    MARKDOWN_PARSER_PLAN_VERSION, MarkdownErrorCode, MarkdownException, MarkdownProfile, ParseResult, 
    ReferenceDefinition, Sha256, SourceSpan, Utf8Policy, parserConfigurationFingerprint, profileIdentityDescriptor}
import markdown.engine.MarkdownEngine

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
 * `create` 交叉验证 parse result 的 source 与 AST parser provenance。
 * profile 的 kind、id、标准版本，dialect、engine 配置，原始与解码 digest，UTF-8 policy
 * 及根节点完整源码范围都必须一致，不能将另一个 Document 与 source 或 engine 拼接后缓存。
 * 保留 parser provenance 的树变换结果仍可创建 artifact。
 *
 * 只有实际替换无效 UTF-8 字节时，`ReplaceInvalid` 才产生非 identity mapping 并被拒绝。
 * 有效 UTF-8 bytes 使用该 policy 仍可缓存，但加载时必须使用同一 policy。
 * `load` 对不匹配的身份、当前 schema 或 digest 返回 `CacheMiss`，不猜测迁移旧格式。
 * fingerprint 与 digest 用于缓存身份；libraryVersion 和英文错误消息不能单独充当 cache key。
 *
 * @example 绑定 engine 和源码加载 artifact {run}
 * ```cangjie
 * let engine = MarkdownEngine.builder().build()
 * let source = "# title"
 * let artifact = MarkdownParseArtifact.create(engine, engine.parse(source))
 * match (artifact.load(engine, source)) {
 *     case ArtifactLoadResult.Hit(document) =>
 *         if (document.nodeCount == 0) {
 *             throw IllegalStateException("artifact document is empty")
 *         }
 *     case ArtifactLoadResult.CacheMiss(reason) => throw IllegalStateException(reason)
 * }
 * ```
 */
public class MarkdownParseArtifact {

    /**
     * 创建绑定当前 engine 和完整 parse result 的 artifact。
     * @param engine 产生 parse result 的 engine。
     * @param result 当前 engine 产生的完整 parse result。
     * @return 可用于 identity 校验和缓存加载的 artifact。
     * @throws MarkdownException mapping 非 identity、绑定配置或 parser provenance 不匹配时，代码为 `InvalidArtifact`。
     */
    public static func create(engine: MarkdownEngine, result: ParseResult): MarkdownParseArtifact {
        if (result.document.bindings.footnotesEnabled && result.document.bindings.engineFingerprint !=
            parserConfigurationFingerprint(engine.dialect.fingerprint, engine.limits, engine.bindingOptions)) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact,
                "bound document configuration does not match the artifact engine", phase: "artifact_encode")
        }
        if (!result.source.hasIdentityMapping()) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact,
                "artifacts require an identity-preserving UTF-8 source mapping", phase: "artifact_encode")
        }
        let originalBytes = result.source.originalBytesForArtifact()
        match (artifactDocumentProvenanceFailure(
            result.document,
            engine.profile,
            engine.dialect.fingerprint,
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
        MarkdownParseArtifact(engine, result)
    }

    /**
     * 按 strict UTF-8 policy 校验 String 输入，命中时返回 artifact 持有的同一 Document。
     *
     * 还会重新验证 AST provenance 和 engine limits 下的 AST invariants，不执行重新解析。
     * @param engine 校验 artifact 身份使用的 engine。
     * @param source 与 artifact 对应的源文本。
     * @return `Hit` 或带原因的 `CacheMiss`。
     */
    public func load(engine: MarkdownEngine, source: String): ArtifactLoadResult {
        loadArtifactIdentity(engine, this, source.toArray(), source, "strict")
    }

    /**
     * 用原始 bytes 和 UTF-8 policy 校验 artifact，不匹配时返回带原因的 `CacheMiss`。
     *
     * bytes 必须可直接解码为有效 UTF-8；此入口不会对无效输入执行替换解码。
     * @param engine 校验 artifact 身份使用的 engine。
     * @param source 原始 UTF-8 bytes。
     * @param utf8Policy 缓存身份中的 UTF-8 policy，默认为 Strict，必须与创建时相同。
     * @return `Hit` 或带原因的 `CacheMiss`。
     */
    public func load(engine: MarkdownEngine, source: Array<Byte>, utf8Policy!: Utf8Policy = Utf8Policy.Strict): ArtifactLoadResult {
        let decoded = try {
            String.fromUtf8(source)
        } catch (_: Exception) {
            return ArtifactLoadResult.CacheMiss("source encoding")
        }
        loadArtifactIdentity(engine, this, source, decoded, artifactUtf8PolicyId(utf8Policy))
    }

    private func loadArtifactIdentity(engine: MarkdownEngine, artifact: MarkdownParseArtifact,
        originalBytes: Array<Byte>, decoded: String, utf8PolicyId: String): ArtifactLoadResult {
        if (artifact.schemaVersion != "3") {
            return ArtifactLoadResult.CacheMiss("schema version")
        }
        if (artifact.parserPlanVersion != MARKDOWN_PARSER_PLAN_VERSION) {
            return ArtifactLoadResult.CacheMiss("parser plan version")
        }
        if (artifact.profileId != engine.profile.id) {
            return ArtifactLoadResult.CacheMiss("profile id")
        }
        if (artifact.profileIdentity != profileIdentityDescriptor(engine.profile)) {
            return ArtifactLoadResult.CacheMiss("profile identity")
        }
        if (artifact.dialectFingerprint != engine.dialect.fingerprint) {
            return ArtifactLoadResult.CacheMiss("dialect fingerprint")
        }
        if (artifact.engineFingerprint != parserConfigurationFingerprint(engine.dialect.fingerprint, engine.limits,
            engine.bindingOptions)) {
            return ArtifactLoadResult.CacheMiss("engine fingerprint")
        }
        if (artifact.document.bindings.footnotesEnabled && artifact.document.bindings.engineFingerprint != artifact
            .engineFingerprint) {
            return ArtifactLoadResult.CacheMiss("document binding identity")
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
            artifact.document,
            engine.profile,
            engine.dialect.fingerprint,
            artifact.sourceDigest,
            artifact.decodedTextDigest,
            artifact.utf8PolicyId,
            originalBytes.size
        )) {
            case Some(reason) => return ArtifactLoadResult.CacheMiss(reason)
            case None => ()
        }
        try {
            AstInvariantValidator().validate(artifact.document, limits: engine.limits)
        } catch (_: Exception) {
            return ArtifactLoadResult.CacheMiss("AST invariants")
        }
        ArtifactLoadResult.Hit(artifact.document)
    }

    /** artifact schema 版本。 */
    public let schemaVersion: String
    /** 生成本 artifact 的库版本。 */
    public let libraryVersion: String
    /** parser 计划版本。 */
    public let parserPlanVersion: String
    /** 使用的 profile id。 */
    public let profileId: String
    /** 创建 artifact 时 engine 的已编译语法与扩展配置指纹，加载时要求与目标 engine 一致。 */
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
    public let document: Document
    /** 文档级引用定义。 */
    public let references: ImmutableArray<ReferenceDefinition>
    /** 解析诊断。 */
    public let diagnostics: ImmutableArray<Diagnostic>
    internal let profileIdentity: String

    /**
     * 从 engine 与 parse result 保存 artifact 字段，不执行 `create` 的 provenance 校验。
     * @param engine 提供 profile、dialect、limits 和 binding 配置的 engine。
     * @param result 调用方已验证为完整且 identity-preserving 的解析结果。
     */
    protected init(engine: MarkdownEngine, result: ParseResult) {
        schemaVersion = "3"
        libraryVersion = "0.9.2"
        parserPlanVersion = MARKDOWN_PARSER_PLAN_VERSION
        profileId = engine.profile.id
        dialectFingerprint = engine.dialect.fingerprint
        engineFingerprint = parserConfigurationFingerprint(engine.dialect.fingerprint, engine.limits,
            engine.bindingOptions)
        let originalBytes = result.source.originalBytesForArtifact()
        sourceDigest = Sha256.digestBytes(originalBytes)
        decodedTextDigest = Sha256.digest(result.source.text())
        utf8PolicyId = artifactUtf8PolicyId(result.source.decodePolicy())
        offsetMappingDigest = identityOffsetMappingDigest(originalBytes.size)
        document = result.document
        references = result.document.root().asDocument().getOrThrow().references
        diagnostics = result.diagnostics
        profileIdentity = profileIdentityDescriptor(engine.profile)
    }

    /**
     * 返回用于诊断的简短 JSON，不是稳定序列化格式。
     * @return 用于诊断的简短 JSON 文本。
     */
    public func debugJson(): String {
        "{\"debug\":true,\"profile\":\"${profileId}\",\"nodes\":${document.nodeCount}}"
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
