package markdown.integration

import markdown.core.{AstQuery, MarkdownException, MarkdownProfile, MathPayload, NodeKind, NodeRef, SyntaxPayload}
import markdown.editor.DocumentSnapshot
import markdown.engine.MarkdownEngine
import markdown.extensions.{MarkdownDialect, MarkdownDialectBuilder, OfficialExtensionDescriptor, OfficialExtensions}
import markdown.render.CanonicalMarkdownRenderer
import markdown.testkit.MarkdownExtensionTestKit
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
            @Expect(DocumentSnapshot.parse(engine, source).syntaxTree.losslessText(), source)
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
    func frontMatterCrLfBomSourceRangesAndBodySeparatorsSurviveAllOutputs(): Unit {
        let engine = MarkdownEngine
            .builder()
            .dialect(OfficialExtensions.frontMatter(MarkdownDialect.define("front-crlf", "1")).build())
            .build()
        for (bom in ["", "\u{FEFF}"]) {
            let source = bom + "---\r\nx: y\r\nz: v\r\n---\r\n\r\nbody\r\n---\r\n"
            let result = engine.parse(source)
            let node = AstQuery.customNodes(result.document)[0]
            @Expect(node.span.getOrThrow().startByte, bom.size)
            @Expect(result.source.text(node), "---\r\nx: y\r\nz: v\r\n---")
            let payload = node.asCustomBlock().getOrThrow().payload as SyntaxPayload
            @Expect(payload.getOrThrow().literal, "x: y\nz: v")
            @Expect(engine.htmlRenderer().render(result.document),
                "<pre class=\"front-matter\">x: y\nz: v</pre><h2>body</h2>\n")
            @Expect(DocumentSnapshot.parse(engine, source).syntaxTree.losslessText(), source)
            let formatter = CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray())
            @Expect(engine.htmlRenderer().render(engine.parse(formatter.render(result.document)).document),
                engine.htmlRenderer().render(result.document))
            for (widths in [[1], [7], [source.size]]) {
                expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), result)
            }
        }
    }

    @TestCase
    func catalogAndDefaultEnablementMatrixAreVersioned(): Unit {
        let catalog = OfficialExtensions.catalog()
        @Expect(catalog.size, 13)
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
    func officialCapabilityMatrixMatchesActualProfilesEnablementAndOutput(): Unit {
        let install: Array<(MarkdownDialectBuilder) -> MarkdownDialectBuilder> = [
            {builder => OfficialExtensions.footnotes(builder)},
            {builder => OfficialExtensions.frontMatter(builder)},
            {builder => OfficialExtensions.math(builder)},
            {builder => OfficialExtensions.definitionLists(builder)},
            {builder => OfficialExtensions.headingIds(builder)},
            {builder => OfficialExtensions.smartPunctuation(builder)}
        ]
        let ids = ["footnotes", "front-matter", "math", "definition-lists", "heading-ids", "smart-punctuation"]
        let versions = ["2.0.0", "1.0.0", "2.0.0", "2.0.0", "2.0.0", "2.0.0"]
        let samples = ["A [^missing].", "---\nx: y\n---", "$x--...$", "Term\n: body", "# Head {#id}", "A -- ..."]
        let html = ["<p>A [^missing].</p>\n", "<pre class=\"front-matter\">x: y</pre>",
            "<p><span class=\"math-inline\">x--...</span></p>\n",
            "<dl>\n<dt>Term</dt>\n<dd>\n<p>body</p>\n</dd>\n</dl>\n", "<h1 id=\"id\">Head</h1>\n", "<p>A – …</p>\n"]
        for (profile in [MarkdownProfile.commonMark0312(), MarkdownProfile.gfmModernV1()]) {
            let base = MarkdownEngine.builder().profile(profile).build()
            for (index in 0..ids.size) {
                let builder = install[index](MarkdownDialect.define("matrix", "2").base(profile))
                let engine = MarkdownEngine.builder().dialect(builder.build()).build()
                let capability = engine.capabilities().extension(ids[index]).getOrThrow()
                @Expect(capability.semanticVersion, versions[index])
                @Expect(capability.capabilities.parse, index != 5)
                @Expect(capability.capabilities.transform, index == 5)
                let result = engine.parse(samples[index])
                @Expect(engine.htmlRenderer().render(result.document), html[index])
                @Expect(DocumentSnapshot.parse(engine, samples[index]).syntaxTree.losslessText(), samples[index])
                if (index == 0) {
                    @Expect(result.diagnostics[0].code, "MD4001_UNDEFINED_FOOTNOTE")
                }
                let disabled = MarkdownEngine.builder().dialect(builder.disable(ids[index]).build()).build()
                @Expect(disabled.capabilities().extension(ids[index]).isNone(), true)
                @Expect(disabled.htmlRenderer().render(disabled.parse(samples[index]).document),
                    base.htmlRenderer().render(base.parse(samples[index]).document))
                @Expect(engine.htmlRenderer().render(engine.parse(samples[index]).document), html[index])
            }
        }
        for (index in 0..ids.size) {
            let duplicate = install[index](install[index](MarkdownDialect.define("duplicate-official", "2"))).build()
            @ExpectThrows[MarkdownException](MarkdownEngine.builder().dialect(duplicate).build())
            let unsupported = install[index](
                MarkdownDialect.define("unsupported-official", "2").base(MarkdownProfile.gfm029())).build()
            try {
                MarkdownEngine.builder().dialect(unsupported).build()
                @Expect(false)
            } catch (error: MarkdownException) {
                @Expect(error.phase, "dialect_compile")
                @Expect(error.message, "extension ${ids[index]} does not support profile gfm-0.29")
            }
        }
        @Expect(findOfficial(OfficialExtensions.catalog(), "front-matter").targetVersion, "1.0")
        @Expect(findOfficial(OfficialExtensions.catalog(), "math").targetVersion, "2.0")
        @Expect(findOfficial(OfficialExtensions.catalog(), "smart-punctuation").targetVersion, "2.0")
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
                            case value: MathPayload => @Expect(value.expression, "a + b")
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
