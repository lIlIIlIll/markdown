package markdown.integration

import markdown.artifact.{ArtifactLoadResult, MarkdownParseArtifact}
import markdown.core.{AstQuery, MarkdownErrorCode, MarkdownException, MarkdownProfile, NodeKind, ParseResult, 
    RewriteAction, SourceBuffer, SourceSpan, TreeRewriter, Utf8Policy}
import markdown.engine.MarkdownEngine
import markdown.extensions.MarkdownDialect
import markdown.render.HtmlRenderer
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ArtifactSourceMapTest {
    @TestCase
    func renderedSourceMapSeparatesSourceAndGeneratedRanges(): Unit {
        let document = MarkdownEngine.builder().build().parse("# A & B").document
        let output = HtmlRenderer().renderWithSourceMap(document)
        @Expect(output.content, "<h1>A &amp; B</h1>\n")
        @Expect(output.sourceMap.size >= 2, true)
        var mapped = false
        var generated = false
        for (entry in output.sourceMap.toArray()) {
            if (entry.generated) {
                generated = true
            } else {
                mapped = true
            }
        }
        @Expect(mapped && generated, true)
        let textNode = AstQuery.descendants(document)[1]
        let noSpan: ?SourceSpan = None
        @Expect(output.sourceSpanAt(0), noSpan)
        @Expect(output.sourceSpanAt(4), textNode.span)
        @Expect(output.nodeIdAt(4), Some(textNode.nodeId))
        @Expect(output.outputRanges(textNode.nodeId).size, 1)
        try {
            output.sourceSpanAt(output.content.size)
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }
    }

    @TestCase
    func renderedSourceMapCannotMatchVisibleTextInsideGeneratedTags(): Unit {
        let paragraph = HtmlRenderer().renderWithSourceMap(MarkdownEngine.builder().build().parse("p").document)
        let noSpan: ?SourceSpan = None
        @Expect(paragraph.content, "<p>p</p>\n")
        @Expect(paragraph.sourceSpanAt(1), noSpan)
        @Expect(paragraph.sourceSpanAt(3), Some(SourceSpan(0, 1)))

        let emphasis = HtmlRenderer().renderWithSourceMap(MarkdownEngine.builder().build().parse("*em*").document)
        @Expect(emphasis.content, "<p><em>em</em></p>\n")
        @Expect(emphasis.sourceSpanAt(4), noSpan)
        @Expect(emphasis.sourceSpanAt(7), Some(SourceSpan(1, 3)))
    }

    @TestCase
    func artifactHitsOnlyExactSourceEngineAndDialect(): Unit {
        let engine = MarkdownEngine.builder().build()
        let result = engine.parse("text")
        let artifact = MarkdownParseArtifact.create(engine, result)
        @Expect(artifact.schemaVersion, "3")
        @Expect(artifact.parserPlanVersion, "7")
        @Expect(artifact.utf8PolicyId, "strict")
        @Expect(artifact.sourceDigest, artifact.decodedTextDigest)
        match (artifact.load(engine, "text")) {
            case ArtifactLoadResult.Hit(document) => @Expect(HtmlRenderer().render(document), "<p>text</p>\n")
            case _ => @Expect(false)
        }
        match (artifact.load(engine, "changed")) {
            case ArtifactLoadResult.CacheMiss(reason) => @Expect(reason, "source digest")
            case _ => @Expect(false)
        }
        @Expect(artifact.debugJson().contains("\"debug\":true"), true)

        let replaceIdentity = engine.parse([b't', b'e', b'x', b't'], utf8Policy: Utf8Policy.ReplaceInvalid)
        let replaceArtifact = MarkdownParseArtifact.create(engine, replaceIdentity)
        @Expect(replaceArtifact.utf8PolicyId, "replace-invalid")
        match (replaceArtifact.load(engine, [b't', b'e', b'x', b't'], utf8Policy: Utf8Policy.ReplaceInvalid)) {
            case ArtifactLoadResult.Hit(_) => @Expect(true)
            case _ => @Expect(false)
        }
        match (replaceArtifact.load(engine, "text")) {
            case ArtifactLoadResult.CacheMiss(reason) => @Expect(reason, "UTF-8 policy")
            case _ => @Expect(false)
        }

        let replaced = engine.parse([0xFF], utf8Policy: Utf8Policy.ReplaceInvalid)
        try {
            MarkdownParseArtifact.create(engine, replaced)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InvalidArtifact => @Expect(error.phase, "artifact_encode")
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func artifactRejectsParseResultWithMismatchedSourceOrEngine(): Unit {
        let commonmark = MarkdownEngine.builder().build()
        let parsed = commonmark.parse("original")
        @ExpectThrows[IllegalArgumentException](ParseResult(
            parsed.document,
            SourceBuffer("different"),
            parsed.diagnostics.toArray()
        ))

        let gfm = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        expectInvalidArtifact(gfm, parsed, "AST profile")

        let gfmProfile = MarkdownProfile.gfmModernV1()
        let customAlias = MarkdownProfile.custom(gfmProfile.id, gfmProfile.standardVersion)
        let customProfileEngine = MarkdownEngine.builder().profile(customAlias).build()
        let gfmParsed = gfm.parse("original")
        expectInvalidArtifact(customProfileEngine, gfmParsed, "AST profile")

        let gfmArtifact = MarkdownParseArtifact.create(gfm, gfmParsed)
        match (gfmArtifact.load(customProfileEngine, "original")) {
            case ArtifactLoadResult.CacheMiss(reason) => @Expect(reason, "profile identity")
            case _ => @Expect(false)
        }

        let customDialect = MarkdownDialect
            .define("artifact-test", "1.0.0")
            .base(MarkdownProfile.commonMark0312())
            .build()
        let custom = MarkdownEngine.builder().dialect(customDialect).build()
        expectInvalidArtifact(custom, parsed, "AST dialect fingerprint")
    }

    @TestCase
    func artifactAcceptsTransformedDocumentThatPreservesParserProvenance(): Unit {
        let engine = MarkdownEngine.builder().build()
        let parsed = engine.parse("before")
        let rewritten = TreeRewriter.rewrite(parsed.document, {
            node => match (node.kind) {
                case NodeKind.Text => RewriteAction.MapText("after")
                case _ => RewriteAction.Keep
            }
        })
        let transformed = ParseResult(rewritten, parsed.source, parsed.diagnostics.toArray())
        let artifact = MarkdownParseArtifact.create(engine, transformed)
        match (artifact.load(engine, "before")) {
            case ArtifactLoadResult.Hit(document) => @Expect(HtmlRenderer().render(document), "<p>after</p>\n")
            case _ => @Expect(false)
        }
    }

    private func expectInvalidArtifact(engine: MarkdownEngine, result: ParseResult, detail: String): Unit {
        try {
            MarkdownParseArtifact.create(engine, result)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InvalidArtifact =>
                    @Expect(error.phase, "artifact_encode")
                    @Expect(error.message.contains(detail), true)
                case _ => @Expect(false)
            }
        }
    }
}
