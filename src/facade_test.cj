package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FacadeTest {
    @TestCase
    func convenienceApisAreProfileAwareAndSafeByDefault(): Unit {
        @Expect(Markdown.toSafeHtml("<script>x</script>").contains("&lt;script&gt;"), true)
        @Expect(unsafe { Markdown.toSpecHtml("# H") }, "<h1>H</h1>\n")
        @Expect(Markdown.toText("**x**"), "x")
        @Expect(Markdown.toSafeHtml("~~x~~", profile: MarkdownProfile.gfmModernV1()).contains("<del>"), true)
    }

    @TestCase
    func detachedDocumentNeedsNoSourceBuffer(): Unit {
        let longText = StringBuilder()
        for (_ in 0..300) {
            longText.append("x")
        }
        let ownedText = longText.toString()
        let result = Markdown.parse(ownedText)
        let parsed = result.document
        let parsedText = parsed.children()[0].children()[0]
        match (parsedText.kind) {
            case NodeKind.Text => match (parsedText.asText().getOrThrow().rawLiteralStorage()) {
                case LiteralStorage.Slice(_) => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let detached = parsed.detach()
        @ExpectThrows[IllegalArgumentException](ParseResult(detached, result.source, []))
        @Expect(detached.nodeCount, parsed.nodeCount)
        @Expect(detached.nodeId, parsed.nodeId)
        @Expect(detached.revision == parsed.revision, false)
        @Expect(PlainTextRenderer().render(detached), ownedText)
        let detachedText = detached.children()[0].children()[0]
        match (detachedText.kind) {
            case NodeKind.Text => match (detachedText.asText().getOrThrow().rawLiteralStorage()) {
                case LiteralStorage.Copy(_) => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let detachedLiterals = Markdown.parse("```\nx\n```\n\n<div>x</div>").document.detach()
        for (event in detachedLiterals.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                match (node.kind) {
                    case NodeKind.CodeBlock => match (node.asCodeBlock().getOrThrow().storedLiteral()) {
                        case LiteralStorage.Copy(_) => @Expect(true)
                        case _ => @Expect(false)
                    }
                    case NodeKind.HtmlBlock => match (node.asHtmlBlock().getOrThrow().storedLiteral()) {
                        case LiteralStorage.Copy(_) => @Expect(true)
                        case _ => @Expect(false)
                    }
                    case _ => ()
                }
            }
        }
    }

    @TestCase
    func detachPreservesBoundSemanticsAndRejectsOpaqueOwnership(): Unit {
        let engine = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        let parsed = engine.parse("# Heading {#explicit}\n\nword[^n]\n\n[^n]: **body**")
        let detached = parsed.document.detach()
        @Expect(HtmlRenderer().render(detached), HtmlRenderer().render(parsed.document))
        @Expect(CanonicalMarkdownRenderer().render(detached), CanonicalMarkdownRenderer().render(parsed.document))
        @Expect(detached.bindings.headings[0].id, "explicit")
        let rewritten = TreeRewriter.rewrite(parsed.document, {
            node => if (let NodeKind.Text <- node.kind) {
                RewriteAction.MapText("edited")
            } else {
                RewriteAction.Keep
            }
        })
        let compact = rewritten.detach()
        @Expect(HtmlRenderer().render(compact), HtmlRenderer().render(rewritten))
        @Expect(PlainTextRenderer().render(compact), PlainTextRenderer().render(rewritten))
        let opaque = opaqueArtifactEngine(OpaqueArtifactEmitter()).parse("%%text%%")
        try {
            opaque.document.detach()
            @Expect(false)
        } catch (error: MarkdownException) {
            @Expect(error.phase, "detach")
            @Expect(if (let MarkdownErrorCode.UnsupportedNode <- error.code) { true } else { false })
        }
    }
}
