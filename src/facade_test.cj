package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FacadeTest {
    @TestCase
    func convenienceApisAreProfileAwareAndSafeByDefault(): Unit {
        @Expect(Markdown.toSafeHtml("<script>x</script>").contains("&lt;script&gt;"), true)
        @Expect(Markdown.toSpecHtml("# H"), "<h1>H</h1>\n")
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
        let parsed = Markdown.parse(ownedText).document
        match (parsed.children()[0].children()[0]) {
            case text: Text => match (text.rawStorage) {
                case LiteralStorage.Slice(_) => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let detached = parsed.detach()
        @Expect(PlainTextRenderer().render(detached), ownedText)
        match (detached.children()[0].children()[0]) {
            case text: Text => match (text.rawStorage) {
                case LiteralStorage.Copy(_) => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let detachedLiterals = Markdown.parse("```\nx\n```\n\n<div>x</div>").document.detach()
        for (event in detachedLiterals.walk()) {
            if (let WalkEvent.Enter(node) <- event) {
                match (node) {
                    case code: CodeBlock => match (code.literalStorage) {
                        case LiteralStorage.Copy(_) => @Expect(true)
                        case _ => @Expect(false)
                    }
                    case html: HtmlBlock => match (html.literalStorage) {
                        case LiteralStorage.Copy(_) => @Expect(true)
                        case _ => @Expect(false)
                    }
                    case _ => ()
                }
            }
        }
    }
}
