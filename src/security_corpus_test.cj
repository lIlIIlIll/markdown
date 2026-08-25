package markdown

import std.unicode.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SecurityCorpusTest {
    @TestCase
    func safeHtmlCorpusRejectsInjectionAndUriConfusion(): Unit {
        let attacks = [
            "<script>alert(1)</script>",
            "<img src=x onerror=alert(1)>",
            "[x](javascript:alert(1))",
            "[x](JaVa\tScRiPt:alert(1))",
            "[x](vbscript:msgbox(1))",
            "[x](file:///etc/passwd)",
            "![x](data:image/svg+xml,<svg/onload=alert(1)>)",
            "![x](https://tracker.invalid/pixel)",
            "<iframe srcdoc='<script>x</script>'></iframe>",
            "\u{202E}<b>hidden</b>"
        ]
        for (attack in attacks) {
            let html = Markdown.toSafeHtml(attack)
            @Expect(html.contains("<script"), false)
            @Expect(html.contains("<img src=x"), false)
            @Expect(html.contains("<iframe"), false)
            @Expect(html.toLower().contains("javascript:"), false)
            @Expect(html.toLower().contains("vbscript:"), false)
            @Expect(html.toLower().contains("file:"), false)
            @Expect(html.contains("src=\"data:"), false)
            @Expect(html.contains("src=\"https://tracker.invalid"), false)
        }
    }

    @TestCase
    func pathologicalDelimiterReferenceHtmlAndTableInputsRemainBounded(): Unit {
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        let inputs = [
            repeatedSecurity("*_~", 4000),
            repeatedSecurity("[", 8000),
            repeatedSecurity("<tag ", 2000),
            repeatedSecurity("[a]: /x\n", 2000),
            "|" + repeatedSecurity(" c |", 1024) + "\n|" + repeatedSecurity("---|", 1024),
            repeatedSecurity("a", 1024 * 1024)
        ]
        for (input in inputs) {
            let result = engine.parse(input)
            AstInvariantValidator().validate(result.document)
            HtmlRenderer().render(result.document)
        }
    }

    @TestCase
    func extensionCompilerFuzzRejectsInvalidRulesDeterministically(): Unit {
        for (index in 0..128) {
            let opener = if (index % 3 == 0) {
                ""
            } else {
                repeatedSecurity("=", (index % 20) + 1)
            }
            let dialect = MarkdownDialect
                .define("fuzz", "1")
                .enable(ExtensionManifest("fuzz", "1.0.0", "${index}"))
                .inline(
                    InlineSyntax
                        .define("fuzz", "r${index}")
                        .delimiter(opener)
                        .maximumDelimiterLength(16)
                        .maximumLookahead(64))
                .build()
            var failed = false
            try {
                DialectCompiler.compile(dialect)
            } catch (_: MarkdownException) {
                failed = true
            }
            let shouldFail = opener.isEmpty() || opener.size > 16
            @Expect(failed, shouldFail)
        }
    }
}

private func repeatedSecurity(value: String, count: Int64): String {
    let out = StringBuilder()
    for (_ in 0..count) {
        out.append(value)
    }
    out.toString()
}
