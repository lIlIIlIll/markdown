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
        for (entry in sourceMap.toArray()) {
            if (entry.outputRange.contains(SourceOffset(outputByte))) {
                return entry.sourceSpan
            }
        }
        None
    }

    public func nodeIdAt(outputByte: Int64): ?NodeId {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        for (entry in sourceMap.toArray()) {
            if (entry.outputRange.contains(SourceOffset(outputByte))) {
                return entry.nodeId
            }
        }
        None
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
}

extend HtmlRenderer {
    public func renderWithSourceMap(document: Document): RenderedOutput {
        let content = render(document)
        let entries = ArrayList<RenderedSourceMapEntry>()
        let noSource: ?SourceSpan = None
        let noNode: ?NodeId = None
        var cursor: Int64 = 0
        for (event in document.walk()) {
            if (let WalkEvent.Enter(node) <- event) {
                let visible = sourceMapVisibleText(node)
                if (!visible.isEmpty()) {
                    let found = findSourceMapText(content, visible, cursor)
                    if (found >= 0) {
                        if (found > cursor) {
                            entries.add(RenderedSourceMapEntry(SourceSpan(cursor, found), noSource, noNode, true))
                        }
                        entries.add(
                            RenderedSourceMapEntry(SourceSpan(found, found + visible.size), node.span, Some(node.nodeId),
                                false))
                        cursor = found + visible.size
                    }
                }
            }
        }
        if (cursor < content.size) {
            entries.add(RenderedSourceMapEntry(SourceSpan(cursor, content.size), noSource, noNode, true))
        }
        RenderedOutput(content, entries.toArray())
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
        libraryVersion = "1.0.0"
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
    Sha256.digest(
        "${engine.dialect.fingerprint}|${limits.maximumInputBytes}|${limits.maximumLineBytes}|" +
            "${limits.maximumNestingDepth}|${limits.maximumAstNodes}|${limits.maximumReferences}|" +
            "${limits.maximumTableColumns}|${limits.maximumUrlBytes}|${limits.maximumLiteralBytes}|" +
            "${limits.maximumOutputBytes}|${limits.maximumExtensionCaptureBytes}|${limits.maximumExtensionLookaheadBytes}")
}

private func sourceMapVisibleText(node: MarkdownNode): String {
    match (node) {
        case text: Text => escapeSourceMapText(text.value)
        case code: CodeSpan => escapeSourceMapText(code.literal)
        case _ => ""
    }
}

private func escapeSourceMapText(value: String): String {
    value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
}

private func findSourceMapText(haystack: String, needle: String, start: Int64): Int64 {
    var index = start
    while (index + needle.size <= haystack.size) {
        if (haystack[index..index + needle.size] == needle) {
            return index
        }
        index++
    }
    -1
}
