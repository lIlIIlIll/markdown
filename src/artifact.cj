package markdown

import std.collection.*

public class RenderedSourceMapEntry {
    public let outputRange: SourceSpan
    public let sourceSpan: ?SourceSpan
    public let nodeId: ?NodeId
    public let generated: Bool
    public init(outputRange: SourceSpan, sourceSpan: ?SourceSpan, nodeId: ?NodeId, generated: Bool) {
        this.outputRange = outputRange
        this.sourceSpan = sourceSpan
        this.nodeId = nodeId
        this.generated = generated
    }
}

public class RenderedOutput {
    public let content: String
    public let sourceMap: ImmutableArray<RenderedSourceMapEntry>
    public init(content: String, sourceMap: Array<RenderedSourceMapEntry>) {
        this.content = content
        this.sourceMap = ImmutableArray<RenderedSourceMapEntry>(sourceMap)
    }

    public func sourceSpanAt(outputByte: Int64): ?SourceSpan {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        findEntry(outputByte).sourceSpan
    }

    public func nodeIdAt(outputByte: Int64): ?NodeId {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        findEntry(outputByte).nodeId
    }

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
    public func renderWithSourceMap(document: Document): RenderedOutput {
        let sink = StringTextSink(true)
        renderTo(document, sink)
        RenderedOutput(sink.content(), sink.sourceMap())
    }
}

public enum ArtifactLoadResult {
    | Hit(Document)
    | CacheMiss(String)
}

public class MarkdownParseArtifact {
    public let schemaVersion: String
    public let libraryVersion: String
    public let parserPlanVersion: String
    public let profileId: String
    public let dialectFingerprint: String
    public let engineFingerprint: String
    public let sourceDigest: String
    public let decodedTextDigest: String
    public let utf8PolicyId: String
    public let offsetMappingDigest: String
    public let ast: Document
    public let references: ImmutableArray<ReferenceDefinition>
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

    public func debugJson(): String {
        "{\"debug\":true,\"profile\":\"${profileId}\",\"nodes\":${ast.nodeCount}}"
    }
}

extend MarkdownEngine {
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

    public func loadArtifact(artifact: MarkdownParseArtifact, source: String): ArtifactLoadResult {
        loadArtifactIdentity(artifact, source.toArray(), source, "strict")
    }

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
