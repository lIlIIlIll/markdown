package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ExtensionTckAndFuzzTest {
    @TestCase
    func extensionTckPassesAllRequiredRuntimeChecks(): Unit {
        let manifest = ExtensionManifest("tck", "1", "1", capabilities: ExtensionCapabilities(safeHtml: true))
        let dialect = MarkdownDialect
            .define("tck", "1")
            .enable(manifest)
            .inline(InlineSyntax.define("tck", "mark").delimiter("=="))
            .renderer(RendererRule("tck", "mark", "mark", markdownOpener: "==", markdownCloser: "=="))
            .build()
        let report = MarkdownExtensionTestKit.verify(MarkdownEngine.builder().dialect(dialect).build(),
            "A ==nested **value**==")
        for (failed in report.failedChecks.toArray()) {
            println("TCK failure: ${failed}")
        }
        @Expect(report.checks, 10)
        @Expect(report.passed, 10)
    }

    @TestCase
    func deterministicFuzzSmokeCoversAllPublicPipelines(): Unit {
        let alphabet = "*_[]()`<>\\&\n abcXYZ012"
        var state: Int64 = 20260817
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        for (caseIndex in 0..500) {
            let length = caseIndex % 96
            let value = StringBuilder()
            for (_ in 0..length) {
                state = (state * 1103515245 + 12345) % 2147483647
                let offset = state % alphabet.size
                value.append(alphabet[offset..offset + 1])
            }
            let source = value.toString()
            let parsed = engine.parse(source)
            AstInvariantValidator().validate(parsed.document)
            let bytes = engine.parse(source.toArray())
            let session = engine.newSession()
            var offset: Int64 = 0
            while (offset < source.size) {
                let size = min(source.size - offset, (caseIndex % 7) + 1)
                session.feed(source.toArray().slice(offset, size))
                offset += size
            }
            let chunked = session.finish()
            @Expect(HtmlRenderer().render(parsed.document), HtmlRenderer().render(bytes.document))
            @Expect(HtmlRenderer().render(parsed.document), HtmlRenderer().render(chunked.document))
            let formatted = CanonicalMarkdownRenderer().render(parsed.document)
            let twice = CanonicalMarkdownRenderer().render(engine.parse(formatted).document)
            @Expect(twice, formatted)
            let rewritten = TreeRewriter.rewrite(parsed.document, {_ => RewriteAction.Keep})
            AstInvariantValidator().validate(rewritten)
            let artifact = engine.createArtifact(parsed)
            match (engine.loadArtifact(artifact, source)) {
                case ArtifactLoadResult.Hit(_) => ()
                case _ => @Expect(false)
            }
            match (engine.loadArtifact(artifact, source + "#")) {
                case ArtifactLoadResult.CacheMiss(_) => ()
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func pathologicalDepthAndOutputAmplificationAreBounded(): Unit {
        let nested = StringBuilder()
        for (_ in 0..300) {
            nested.append("> ")
        }
        nested.append("x")
        try {
            Markdown.parse(nested.toString())
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "nesting_depth")
        }
        let document = Markdown.parse("**amplify**").document
        try {
            HtmlRenderer().render(document, budget: OperationBudget(1000, 1000, 1000, 1000, 1000, 2))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(true)
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func trustedDeepBlockContainersUseExplicitFramesWithoutHostStackGrowth(): Unit {
        let engine = MarkdownEngine.builder().limits(ParseLimits.trusted()).build()
        let quoteInput = StringBuilder()
        for (_ in 0..2000) {
            quoteInput.append("> ")
        }
        quoteInput.append("leaf")
        let quoted = engine.parse(quoteInput.toString()).document
        var quoteDepth: Int64 = 0
        var quoteNode = quoted.children()[0]
        while (let blockQuote: BlockQuote <- quoteNode) {
            quoteDepth++
            quoteNode = blockQuote.children()[0]
        }
        @Expect(quoteDepth, 2000)
        match (quoteNode) {
            case _: Paragraph => @Expect(true)
            case _ => @Expect(false)
        }

        let listInput = StringBuilder()
        for (_ in 0..2000) {
            listInput.append("- ")
        }
        listInput.append("leaf")
        let listed = engine.parse(listInput.toString()).document
        var listDepth: Int64 = 0
        var listNode = listed.children()[0]
        while (let list: List <- listNode) {
            listDepth++
            let item = list.children()[0]
            listNode = item.children()[0]
        }
        @Expect(listDepth, 2000)
        match (listNode) {
            case _: Paragraph => @Expect(true)
            case _ => @Expect(false)
        }

        let dialect = MarkdownDialect
            .define("deep-extension", "1")
            .enable(ExtensionManifest("deep-extension", "1", "1"))
            .block(BlockSyntax.define("deep-extension", "box").opener(":::box").closer(":::").nesting(true))
            .renderer(RendererRule("deep-extension", "box", "section", markdownOpener: ":::", markdownCloser: ":::"))
            .limits(ParseLimits.trusted())
            .build()
        let extensionInput = StringBuilder()
        for (_ in 0..1000) {
            extensionInput.append(":::box\n")
        }
        extensionInput.append("leaf\n")
        for (_ in 0..1000) {
            extensionInput.append(":::\n")
        }
        let extended = MarkdownEngine.builder().dialect(dialect).build().parse(extensionInput.toString()).document
        var extensionDepth: Int64 = 0
        var extensionNode = extended.children()[0]
        while (let custom: CustomBlock <- extensionNode) {
            extensionDepth++
            extensionNode = custom.children()[0]
        }
        @Expect(extensionDepth, 1000)
        match (extensionNode) {
            case _: Paragraph => @Expect(true)
            case _ => @Expect(false)
        }
    }
}
