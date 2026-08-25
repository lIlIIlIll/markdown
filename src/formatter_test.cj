package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FormatterBehaviorTest {
    @TestCase
    func canonicalMarkdownIsIdempotentForMixedDocument(): Unit {
        let input = "# Title ###\n\n- [x] **done**\n- [ ] [link](https://example.com)\n\n```cj\nmain()\n```\n"
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        let formatter = CanonicalMarkdownRenderer()
        let once = formatter.render(engine.parse(input).document)
        let twice = formatter.render(engine.parse(once).document)
        @Expect(twice, once)
    }

    @TestCase
    func formatterPreservesCodeDestinationsTaskStateAndTableAlignment(): Unit {
        let input = "1. [x] [a](https://example.com/x)\n\n| a | b |\n| :--- | ---: |\n| `x|y` | z |\n\n````\na ``` fence\n````"
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        let formatted = CanonicalMarkdownRenderer().render(engine.parse(input).document)
        @Expect(formatted.contains("1. [x] [a](https://example.com/x)"), true)
        @Expect(formatted.contains(":---"), true)
        @Expect(formatted.contains("---:"), true)
        @Expect(formatted.contains("a ``` fence"), true)
        let again = engine.parse(formatted).document
        AstInvariantValidator().validate(again)
    }

    @TestCase
    func formatterSupportsCrlfAndFinalNewlineOptions(): Unit {
        let document = MarkdownEngine.builder().build().parse("text").document
        let crlf = CanonicalMarkdownRenderer(options: MarkdownFormatOptions(newline: "\r\n")).render(document)
        @Expect(crlf, "text\r\n")
        let noFinal = CanonicalMarkdownRenderer(options: MarkdownFormatOptions(finalNewline: false)).render(document)
        @Expect(noFinal, "text")
    }
}
