package markdown

import std.unittest.*
import std.unittest.testmacro.*

private func punctuationEngine(profile: MarkdownProfile): MarkdownEngine {
    MarkdownEngine
        .builder()
        .dialect(OfficialExtensions.smartPunctuation(MarkdownDialect.define("punctuation", "2").base(profile)).build())
        .build()
}

@Test
class SmartPunctuationTests {
    @TestCase
    func matchesLongestAsciiSequencesWithinEachSemanticTextNode(): Unit {
        let engine = punctuationEngine(MarkdownProfile.commonMark0312())
        let source = "A . .. ... .... ..... ...... -- --- ---- ----- ------ ------- …—– “q” \"q\"."
        let result = engine.parse(source)
        @Expect(engine.htmlRenderer().render(result.document),
            "<p>A . .. … …. ….. …… – — —- —– —— ——- …—– “q” &quot;q&quot;.</p>\n")
        @Expect(result.source.text(result.document), source)
        @Expect(result.document.root().children()[0].children()[0].asText().getOrThrow().raw, source)
        @Expect(engine.htmlRenderer().render(engine.parse("..*.* --*x*- 中文...😀---").document),
            "<p>..<em>.</em> –<em>x</em>- 中文…😀—</p>\n")
        let normalized = engine.parse("A &#45;&#45; &amp;...")
        @Expect(engine.htmlRenderer().render(normalized.document), "<p>A – &amp;…</p>\n")
    }

    @TestCase
    func protectsCodeDestinationsTitlesRawHtmlAndAutomaticLinkLabels(): Unit {
        let source = "Text -- ... `code -- ...` [label -- ...](https://example.test/a--b... \"title -- ...\") <https://example.test/a--b...>.\n\n<div title=\"-- ...\">raw -- ...</div>\n\n```text\ncode -- ...\n```\n"
        let engine = punctuationEngine(MarkdownProfile.commonMark0312())
        let result = engine.parse(source)
        let renderer = unsafe { HtmlRenderer(options: HtmlOptions.specCompatible()) }
        @Expect(renderer.render(result.document),
            "<p>Text – … <code>code -- ...</code> <a href=\"https://example.test/a--b...\" title=\"title -- ...\">label – …</a> <a href=\"https://example.test/a--b...\">https://example.test/a--b...</a>.</p>\n<div title=\"-- ...\">raw -- ...</div>\n<pre><code class=\"language-text\">code -- ...\n</code></pre>\n")
        let gfm = punctuationEngine(MarkdownProfile.gfmModernV1())
        @Expect(gfm.htmlRenderer().render(gfm.parse("www.example.test/a--b ...").document),
            "<p><a href=\"http://www.example.test/a--b\">www.example.test/a--b</a> …</p>\n")
    }

    @TestCase
    func repeatedProcessingKeepsUnchangedContentAndNodeIdentity(): Unit {
        let processor = SmartPunctuationTransform()
        let original = Markdown.parse("中文😀 -- ...")
        let once = processor.transform(original.document, original.source, ParseLimits.safe(), OperationBudget.safe(),
            CancellationToken.none())
        let again = processor.transform(once, original.source, ParseLimits.safe(), OperationBudget.safe(),
            CancellationToken.none())
        @Expect(HtmlRenderer().render(again), "<p>中文😀 – …</p>\n")
        @Expect(again.revision, once.revision)
        @Expect(again.nodeId, once.nodeId)
        let plain = Markdown.parse("unchanged 中文😀 — …")
        @Expect(processor.transform(plain.document, plain.source, ParseLimits.safe(), OperationBudget.safe(), CancellationToken.none()).revision, plain.document.revision)
    }

    @TestCase
    func textScanningUsesCumulativeBudgetAndObservesCancellation(): Unit {
        let processor = SmartPunctuationTransform()
        let text = StringBuilder()
        for (_ in 0..4096) {
            text.append("中文😀 -- ... ")
        }
        let parsed = Markdown.parse(text.toString())
        let document = parsed.document
        @ExpectThrows[MarkdownException](processor.transform(document, parsed.source, ParseLimits.safe(), OperationBudget(0, 0, 0, 100, 0, 0),
            CancellationToken.none()))
        let cancellation = CancellationSource()
        cancellation.cancel()
        @ExpectThrows[MarkdownException](processor.transform(document, parsed.source, ParseLimits.safe(), OperationBudget.safe(), cancellation.token))
        let budget = OperationBudget.safe()
        let changed = processor.transform(document, parsed.source, ParseLimits.safe(), budget, CancellationToken.none())
        @Expect(budget.usedScanSteps() >= text.size, true)
        @Expect(budget.usedScanSteps() <= text.size + document.nodeCount * 8, true)
        @Expect(changed.nodeCount, document.nodeCount)
    }

    @TestCase
    func combinesWithTypedBindingsAndLiteralExtensionsAcrossAppendPartitions(): Unit {
        let engine = MarkdownEngine
            .builder()
            .dialect(OfficialExtensions.p1Dialect(profile: MarkdownProfile.gfmModernV1()))
            .build()
        let source = "---\ntitle: -- ...\n---\n\n# Head-- {#head}\n\nTerm... [^n--]\n: body-- $x--...$\n\n[^n--]: note... `code--...`\n"
        let result = engine.parse(source)
        @Expect(result.document.bindings.headings[0].text, "Head–")
        @Expect(result.document.bindings.headings[0].id, "head")
        let definition = AstQuery
            .byNodeId(result.document, result.document.bindings.footnotes[0].definition)
            .getOrThrow()
            .asCustomBlock()
            .getOrThrow()
            .payload as FootnoteDefinitionPayload
        @Expect(definition.getOrThrow().labelNormalized, "n--")
        @Expect(engine.parseSnapshot(source).syntaxTree.losslessText(), source)
        for (widths in [[1], [2, 13, 7], [source.size]]) {
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), result)
        }
        let formatted = CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(
            result.document)
        @Expect(engine.htmlRenderer().render(engine.parse(formatted).document), engine.htmlRenderer().render(result.document))
        let base = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        @Expect(base.htmlRenderer().render(base.parse("A -- ...").document), "<p>A -- ...</p>\n")
    }
}
