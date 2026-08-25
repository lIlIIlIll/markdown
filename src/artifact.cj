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
    public let document: Document
    public let references: ImmutableArray<ReferenceDefinition>
    public let diagnostics: ImmutableArray<Diagnostic>

    internal init(engine: MarkdownEngine, result: ParseResult) {
        schemaVersion = "1"
        libraryVersion = "0.8.0"
        parserPlanVersion = "1"
        profileId = engine.profile.id
        dialectFingerprint = engine.dialect.fingerprint
        engineFingerprint = computeEngineFingerprint(engine)
        sourceDigest = Sha256.digestBytes(result.source.text().toArray())
        document = result.document
        references = result.document.references
        diagnostics = result.diagnostics
    }

    public func debugJson(): String {
        "{\"debug\":true,\"profile\":\"${profileId}\",\"nodes\":${AstQuery.descendants(document).size + 1}}"
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
        MarkdownParseArtifact(this, result)
    }

    public func loadArtifact(artifact: MarkdownParseArtifact, source: String): ArtifactLoadResult {
        if (artifact.schemaVersion != "1") {
            return ArtifactLoadResult.CacheMiss("schema version")
        }
        if (artifact.parserPlanVersion != "1") {
            return ArtifactLoadResult.CacheMiss("parser plan version")
        }
        if (artifact.profileId != profile.id) {
            return ArtifactLoadResult.CacheMiss("profile id")
        }
        if (artifact.dialectFingerprint != dialect.fingerprint) {
            return ArtifactLoadResult.CacheMiss("dialect fingerprint")
        }
        if (artifact.engineFingerprint != computeEngineFingerprint(this)) {
            return ArtifactLoadResult.CacheMiss("engine fingerprint")
        }
        if (artifact.sourceDigest != Sha256.digest(source)) {
            return ArtifactLoadResult.CacheMiss("source digest")
        }
        try {
            AstInvariantValidator().validate(artifact.document, limits: limits)
        } catch (_: Exception) {
            return ArtifactLoadResult.CacheMiss("AST invariants")
        }
        ArtifactLoadResult.Hit(artifact.document)
    }
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
