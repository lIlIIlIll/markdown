package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class OfficialExtensionsTest {
    @TestCase
    func catalogAndDefaultEnablementMatrixAreVersioned(): Unit {
        let catalog = OfficialExtensions.catalog()
        @Expect(catalog.size, 12)
        @Expect(findOfficial(catalog, "footnotes").targetVersion, "1.1")
        @Expect(findOfficial(catalog, "footnotes").defaultEnabled, false)
        @Expect(findOfficial(catalog, "gfm-tables").isDefaultFor("gfm-modern-v1"), true)
        @Expect(findOfficial(catalog, "gfm-tables").isDefaultFor("commonmark-0.31.2"), false)
        @Expect(findOfficial(catalog, "github-alerts").targetVersion, "future")
        @Expect(findOfficial(catalog, "wikilinks").defaultEnabled, false)

        let common = MarkdownEngine.builder().profile(MarkdownProfile.commonMark0312()).build()
        @Expect(AstQuery.customNodes(common.parse("$x$ {#id}").document).size, 0)
        let official = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        @Expect(official.capabilities().supportedExtensions.size, 6)
    }

    @TestCase
    func allOfficialP1ExtensionsPassTheSharedTck(): Unit {
        verifyOfficial({builder => OfficialExtensions.footnotes(builder)}, "A [^note].")
        verifyOfficial({builder => OfficialExtensions.frontMatter(builder)}, "---\ntitle: safe\n---")
        verifyOfficial({builder => OfficialExtensions.math(builder)}, "A $x + y$.")
        verifyOfficial({builder => OfficialExtensions.definitionLists(builder)}, "Term\n\n: Definition")
        verifyOfficial({builder => OfficialExtensions.headingIds(builder)}, "# Heading {#stable}")
        verifyOfficial({builder => OfficialExtensions.smartPunctuation(builder)}, "A -- B...")
    }

    @TestCase
    func frontMatterAndMathAreLiteralOnlyAndHeadingIdsAreStructured(): Unit {
        let engine = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        let parsed = engine.parse("---\ntitle: x\n---\n\n# H {#main}\n\n$$\na + b\n$$")
        let custom = AstQuery.customNodes(parsed.document)
        @Expect(countOfficial(custom, "front-matter"), 1)
        @Expect(countOfficial(custom, "heading-id"), 1)
        @Expect(countOfficial(custom, "math-block"), 1)
        for (node in custom) {
            match (node) {
                case value: CustomBlock =>
                    if (value.localKindId == "math-block") {
                        match (value.payload) {
                            case syntax: SyntaxPayload => @Expect(syntax.literal, "a + b")
                            case _ => @Expect(false)
                        }
                    }
                case _ => ()
            }
        }
        let html = engine.htmlRenderer().render(parsed.document)
        @Expect(html.contains("<span class=\"heading-id\" id=\"main\"></span>"), true)
        @Expect(html.contains("<div class=\"math-block\">a + b</div>"), true)
        @Expect(html.contains("title: x"), true)

        let notAtStart = engine.parse("text\n\n---\nnot front matter\n---")
        @Expect(countOfficial(AstQuery.customNodes(notAtStart.document), "front-matter"), 0)
    }
}

private func verifyOfficial(install: (MarkdownDialectBuilder) -> MarkdownDialectBuilder, sample: String): Unit {
    let builder = MarkdownDialect.define("official-test", "1")
    install(builder)
    let report = MarkdownExtensionTestKit.verify(MarkdownEngine.builder().dialect(builder.build()).build(), sample)
    for (failure in report.failedChecks.toArray()) {
        println("official TCK failure: ${failure} sample=${sample}")
    }
    @Expect(report.checks, 10)
    @Expect(report.passed, 10)
}

private func findOfficial(values: Array<OfficialExtensionDescriptor>, id: String): OfficialExtensionDescriptor {
    for (value in values) {
        if (value.extensionId == id) {
            return value
        }
    }
    throw IllegalArgumentException("missing official extension descriptor")
}

private func countOfficial(nodes: Array<MarkdownNode>, kind: String): Int64 {
    var count: Int64 = 0
    for (node in nodes) {
        match (node) {
            case value: CustomBlock =>
                if (value.localKindId == kind) {
                    count++
                }
            case value: CustomInline =>
                if (value.localKindId == kind) {
                    count++
                }
            case _ => ()
        }
    }
    count
}
