package markdown.integration

import markdown.artifact.BinaryArtifactCodec
import markdown.core.{AstInvariantValidator, AstQuery, BindingOptions, MarkdownException}
import markdown.editor.{DocumentSnapshot, MarkdownLinter}
import markdown.engine.MarkdownEngine
import markdown.extensions.{MarkdownDialect, OfficialExtensions}
import markdown.render.{CanonicalMarkdownRenderer, HtmlRenderer, PlainTextOptions, PlainTextRenderer}
import std.unittest.*
import std.unittest.testmacro.*

private func headingTestEngine(scope!: String = ""): MarkdownEngine {
    let builder = OfficialExtensions.headingIds(OfficialExtensions.footnotes(MarkdownDialect.define("headings", "2")))
    MarkdownEngine.builder().dialect(builder.build()).bindingOptions(BindingOptions(idScope: scope)).build()
}

@Test
class HeadingBindingTests {
    @TestCase
    func scopedFragmentLinksQueriesLintAndSnapshotConsumeTheSameTargets(): Unit {
        let engine = headingTestEngine(scope: "chapter")
        let source = "# Heading {#main}\n\n# Scoped spelling {#chapter-main}\n\n# 中文\n\n[main](#main) [other](#chapter-main) [unicode](#%E4%B8%AD%E6%96%87) [note](#fn-1) [missing](#absent) [invalid](#%FF) [top](#) [external](guide.md#absent)\n\nx[^n]\n\n[^n]: [back](#main)"
        let result = engine.parse(source)
        let bindings = result.document.bindings
        @Expect(bindings.links[0].renderedDestination, "#chapter-main")
        @Expect(bindings.links[1].renderedDestination, "#chapter-chapter-main")
        @Expect(bindings.links[2].renderedDestination, "#chapter-中文")
        @Expect(bindings.links[3].renderedDestination, "#chapter-fn-1")
        @Expect(bindings.links[0].destination, "#main")
        for (index in 0..4) {
            let link = bindings.links[index]
            @Expect(link.target, bindings.fragmentTarget(link.renderedDestination[1..]))
            @Expect(link.target.isSome(), true)
            @Expect(bindings.linkForNode(link.link).getOrThrow().renderedDestination, link.renderedDestination)
        }
        let snapshot = DocumentSnapshot.parse(engine, source)
        var missing: Int64 = 0
        for (diagnostic in MarkdownLinter(engine).lint(snapshot)) {
            if (diagnostic.code == "MDL1005_MISSING_FRAGMENT") {
                missing++
            }
        }
        @Expect(missing, 2)
        let html = engine.htmlRenderer().render(result.document)
        @Expect(html.contains("href=\"#chapter-main\""), true)
        @Expect(html.contains("href=\"#chapter-chapter-main\""), true)
        @Expect(PlainTextRenderer(options: PlainTextOptions(includeLinkDestinations: true))
            .render(result.document).contains("(#chapter-main)"), true)
        @Expect(engine.htmlRenderer().render(engine.parse(CanonicalMarkdownRenderer().render(result.document)).document), html)
        let restored = BinaryArtifactCodec.read(engine, BinaryArtifactCodec.encode(snapshot).bytes())
        @Expect(engine.htmlRenderer().render(restored.result.document), html)
        @Expect(headingTestEngine(scope: "second").parse(source).document.bindings.links[0].renderedDestination,
            "#second-main")
    }

    @TestCase
    func explicitIdsAreReservedBeforeAutomaticSlugsAndShareFootnoteAnchors(): Unit {
        let source = "# Same\n\n# explicit {#same}\n\n# duplicate {#same}\n\n# reserved {#same-2}\n\n# note {#fn-1}\n\nx[^n]\n\n[^n]: body"
        let engine = headingTestEngine()
        let result = engine.parse(source)
        let headings = result.document.bindings.headings
        @Expect(headings.size, 5)
        @Expect(headings[0].id, "same-4")
        @Expect(headings[1].id, "same")
        @Expect(headings[2].id, "same-3")
        @Expect(headings[3].id, "same-2")
        @Expect(headings[4].id, "fn-1")
        @Expect(result.document.bindings.footnotes[0].definitionId, "fn-1-2")
        @Expect(result.diagnostics.size, 1)
        @Expect(result.diagnostics[0].code, "MD4010_DUPLICATE_HEADING_ID")
        @Expect(result.source.slice(result.diagnostics[0].span), "same")
        @Expect(result.source.slice(result.diagnostics[0].relatedSpans[0]), "same")
        let html = HtmlRenderer().render(result.document)
        for (heading in headings.toArray()) {
            @Expect(html.contains("id=\"${heading.id}\""), true)
            @Expect(result.document.bindings.headingForId(heading.id).getOrThrow().heading, heading.heading)
            @Expect(result.document.bindings.fragmentTarget(heading.id).getOrThrow(), heading.heading)
        }
        @Expect(html.contains("<span"), false)
        @Expect(engine.htmlRenderer().render(result.document), html)
        @Expect(HtmlRenderer().render(engine.parse(CanonicalMarkdownRenderer().render(result.document)).document), html)
    }

    @TestCase
    func unicodeEmptyAndRepeatedHeadingsHaveDeterministicStructuredToc(): Unit {
        let engine = headingTestEngine(scope: "chapter")
        let source = "# Hello, WORLD!\n\n### 中文　😀\n\n##### deep\n\n## Sibling\n\n# !!!\n\n# 中文 😀\n\n#"
        let result = engine.parse(source)
        let headings = result.document.bindings.headings
        let expected = ["chapter-hello-world", "chapter-中文-😀", "chapter-deep", "chapter-sibling", "chapter-section",
            "chapter-中文-😀-2", "chapter-section-2"]
        for (index in 0..expected.size) {
            @Expect(headings[index].id, expected[index])
        }
        let toc = result.document.bindings.tableOfContents()
        @Expect(toc.size, 4)
        @Expect(toc[0].children.size, 2)
        @Expect(toc[0].children[0].heading.level, 3)
        @Expect(toc[0].children[0].children[0].heading.level, 5)
        @Expect(result.document.bindings.tableOfContents(minimumLevel: 2, maximumLevel: 3).size, 2)
        @ExpectThrows[IllegalArgumentException](result.document.bindings.tableOfContents(minimumLevel: 0))
        let views = AstQuery.headings(result.document)
        @Expect(views[1].binding.getOrThrow().text, "中文　😀")
        @Expect(HtmlRenderer().render(result.document), HtmlRenderer().render(engine.parse(source).document))
    }

    @TestCase
    func suffixIsHeadingOnlyAndSetextContainerMetadataKeepsExactSource(): Unit {
        let engine = headingTestEngine()
        let source = "paragraph {#literal}\n\n# `code {#code}`\n\n# Head {#not-id} tail\n\n> **中文**\r\n> emoji 😀 {#显式-ID}\r\n> ---\r\n"
        let result = engine.parse(source)
        let headings = result.document.bindings.headings
        @Expect(headings.size, 3)
        @Expect(headings[2].id, "显式-ID")
        @Expect(headings[2].text, "中文 emoji 😀")
        @Expect(result.source.slice(headings[2].explicitIdSpan.getOrThrow()), "显式-ID")
        @Expect(headings[0].explicitId.isNone(), true)
        @Expect(headings[1].explicitId.isNone(), true)
        let html = HtmlRenderer().render(result.document)
        @Expect(html.contains("<p>paragraph {#literal}</p>"), true)
        @Expect(html.contains("<h2 id=\"显式-ID\"><strong>中文</strong>\nemoji 😀</h2>"), true)
        @Expect(PlainTextRenderer().render(result.document).contains("{#显式-ID}"), false)
        let snapshot = DocumentSnapshot.parse(engine, source)
        let restored = BinaryArtifactCodec.read(engine, BinaryArtifactCodec.encode(snapshot).bytes())
        @Expect(HtmlRenderer().render(restored.result.document), html)
        @Expect(restored.syntaxTree.losslessText(), source)
        AstInvariantValidator().validate(result.document)
    }

    @TestCase
    func unusedFootnoteHeadingsAreNotPublishedAsTocOrFragmentTargets(): Unit {
        let engine = headingTestEngine()
        let result = engine.parse(
            "# Main\n\nx[^used]\n\n[^used]: ## Visible {#visible}\n\n[^unused]: ## Hidden {#hidden}")
        @Expect(result.document.bindings.headings.size, 2)
        @Expect(result.document.bindings.headingForId("visible").isSome(), true)
        @Expect(result.document.bindings.fragmentTarget("hidden").isNone(), true)
        @Expect(HtmlRenderer().render(result.document).contains("id=\"hidden\""), false)
        @ExpectThrows[MarkdownException](engine.parseEvents("# Main"))
        @ExpectThrows[MarkdownException](engine.newRawBlockEventSession())
    }
}
