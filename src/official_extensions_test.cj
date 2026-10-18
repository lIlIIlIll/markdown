package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class OfficialExtensionsTest {
    @TestCase
    func frontMatterRequiresTheAbsoluteDocumentStartAndPreservesEmptyOrUnclosedInput(): Unit {
        let engine = MarkdownEngine
            .builder()
            .dialect(OfficialExtensions.frontMatter(MarkdownDialect.define("front-start", "1")).build())
            .build()
        for (source in ["\n---\nx: y\n---", " \n---\nx: y\n---", "text\n\n---\nx: y\n---", " ---\nx: y\n---",
            "    ---\nx: y\n---"]) {
            let result = engine.parse(source)
            @Expect(countOfficial(AstQuery.customNodes(result.document), "front-matter"), 0)
            @Expect(engine.parseSnapshot(source).syntaxTree.losslessText(), source)
        }
        let bom = engine.parse("\u{FEFF}---\nx: y\n---")
        let front = AstQuery.customNodes(bom.document)
        @Expect(front.size, 1)
        @Expect(bom.source.slice(front[0].span.getOrThrow()), "---\nx: y\n---")
        let empty = engine.parse("---\n---")
        match (AstQuery.customNodes(empty.document)[0].asCustomBlock().getOrThrow().payload) {
            case value: SyntaxPayload => @Expect(value.literal, "")
            case _ => @Expect(false)
        }
        let unclosed = engine.parse("---\nx: y")
        @Expect(AstQuery.customNodes(unclosed.document).size, 0)
        @Expect(unclosed.diagnostics[0].code, "MD3002_UNCLOSED_EXTENSION")
        @Expect(engine.htmlRenderer().render(unclosed.document).contains("x: y"), true)
    }

    @TestCase
    func catalogAndDefaultEnablementMatrixAreVersioned(): Unit {
        let catalog = OfficialExtensions.catalog()
        @Expect(catalog.size, 12)
        @Expect(findOfficial(catalog, "footnotes").targetVersion, "2.0")
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
            match (node.kind) {
                case NodeKind.CustomBlock =>
                    let value = node.asCustomBlock().getOrThrow()
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
        @Expect(html.contains("<h1 id=\"main\">H</h1>"), true)
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

private func countOfficial(nodes: Array<NodeRef>, kind: String): Int64 {
    var count: Int64 = 0
    for (node in nodes) {
        match (node.kind) {
            case NodeKind.CustomBlock =>
                let value = node.asCustomBlock().getOrThrow()
                if (value.localKindId == kind) {
                    count++
                }
            case NodeKind.CustomInline =>
                let value = node.asCustomInline().getOrThrow()
                if (value.localKindId == kind) {
                    count++
                }
            case _ => ()
        }
    }
    count
}
