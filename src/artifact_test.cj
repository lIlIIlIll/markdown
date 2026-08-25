package markdown

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
        let paragraph = HtmlRenderer().renderWithSourceMap(Markdown.parse("p").document)
        let noSpan: ?SourceSpan = None
        @Expect(paragraph.content, "<p>p</p>\n")
        @Expect(paragraph.sourceSpanAt(1), noSpan)
        @Expect(paragraph.sourceSpanAt(3), Some(SourceSpan(0, 1)))

        let emphasis = HtmlRenderer().renderWithSourceMap(Markdown.parse("*em*").document)
        @Expect(emphasis.content, "<p><em>em</em></p>\n")
        @Expect(emphasis.sourceSpanAt(4), noSpan)
        @Expect(emphasis.sourceSpanAt(7), Some(SourceSpan(1, 3)))
    }

    @TestCase
    func artifactHitsOnlyExactSourceEngineAndDialect(): Unit {
        let engine = MarkdownEngine.builder().build()
        let result = engine.parse("text")
        let artifact = engine.createArtifact(result)
        match (engine.loadArtifact(artifact, "text")) {
            case ArtifactLoadResult.Hit(document) => @Expect(PlainTextRenderer().render(document), "text")
            case _ => @Expect(false)
        }
        match (engine.loadArtifact(artifact, "changed")) {
            case ArtifactLoadResult.CacheMiss(reason) => @Expect(reason, "source digest")
            case _ => @Expect(false)
        }
        @Expect(artifact.debugJson().contains("\"debug\":true"), true)

        let replaced = engine.parse([0xFF], utf8Policy: Utf8Policy.ReplaceInvalid)
        try {
            engine.createArtifact(replaced)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InvalidArtifact => @Expect(error.phase, "artifact_encode")
                case _ => @Expect(false)
            }
        }
    }
}
