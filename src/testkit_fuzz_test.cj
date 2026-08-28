package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ExtensionTckAndFuzzTest {
    @TestCase
    func extensionTckPassesAllRequiredRuntimeChecks(): Unit {
        let manifest = ExtensionManifest("tck", "1.0.0", "1", capabilities: ExtensionCapabilities(safeHtml: true))
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
            AstInvariantValidator().validate(parsed.ast)
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
    func arbitraryByteFuzzMatchesBufferedAndChunkedUtf8Policies(): Unit {
        var state: Int64 = 20260825
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        for (caseIndex in 0..256) {
            let length = caseIndex % 192
            let bytes = Array<Byte>(length, repeat: 0)
            for (index in 0..length) {
                state = (state * 1103515245 + 12345) % 2147483647
                bytes[index] = UInt8(state % 256)
            }

            var directStrictSucceeded = false
            var chunkedStrictSucceeded = false
            var directStrictHtml = ""
            var chunkedStrictHtml = ""
            try {
                let result = engine.parse(bytes, utf8Policy: Utf8Policy.Strict)
                directStrictSucceeded = true
                directStrictHtml = HtmlRenderer().render(result.document)
            } catch (_: MarkdownException) {
            }
            try {
                let session = engine.newSession(utf8Policy: Utf8Policy.Strict)
                feedFuzzPartitions(session, bytes, caseIndex)
                let result = session.finish()
                chunkedStrictSucceeded = true
                chunkedStrictHtml = HtmlRenderer().render(result.document)
            } catch (_: MarkdownException) {
            }
            @Expect(chunkedStrictSucceeded, directStrictSucceeded)
            if (directStrictSucceeded) {
                @Expect(chunkedStrictHtml, directStrictHtml)
            }

            let directReplace = engine.parse(bytes, utf8Policy: Utf8Policy.ReplaceInvalid)
            let replaceSession = engine.newSession(utf8Policy: Utf8Policy.ReplaceInvalid)
            feedFuzzPartitions(replaceSession, bytes, caseIndex)
            let chunkedReplace = replaceSession.finish()
            @Expect(chunkedReplace.source.text(), directReplace.source.text())
            @Expect(chunkedReplace.source.byteLength(), directReplace.source.byteLength())
            @Expect(chunkedReplace.diagnostics.size, directReplace.diagnostics.size)
            @Expect(HtmlRenderer().render(chunkedReplace.document), HtmlRenderer().render(directReplace.document))
            AstInvariantValidator().validate(directReplace.document)
            AstInvariantValidator().validate(chunkedReplace.document)
        }
    }

    @TestCase
    func historicalInvalidUtf8GfmCrashCorpusStaysFixed(): Unit {
        let bytes: Array<Byte> = [
            0xA0,
            0x8A,
            0xE6,
            0xDF,
            0x4B,
            0xFE,
            0x31,
            0xBD,
            0x5C,
            0x8D,
            0x1B,
            0xE8,
            0x40,
            0x4F,
            0xA9,
            0x24
        ]
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        try {
            engine.parse(bytes, utf8Policy: Utf8Policy.Strict)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InvalidEncoding => @Expect(true)
                case _ => @Expect(false)
            }
        }
        let direct = engine.parse(bytes, utf8Policy: Utf8Policy.ReplaceInvalid)
        let buffered = engine.newBufferedInputSession(utf8Policy: Utf8Policy.ReplaceInvalid)
        var offset: Int64 = 0
        while (offset < bytes.size) {
            let size = min(3, bytes.size - offset)
            buffered.feed(bytes.slice(offset, size))
            offset += size
        }
        let partitioned = buffered.finish()
        @Expect(partitioned.source.text(), direct.source.text())
        @Expect(partitioned.source.byteLength(), direct.source.byteLength())
        @Expect(HtmlRenderer().render(partitioned.document), HtmlRenderer().render(direct.document))
        AstInvariantValidator().validate(partitioned.document)
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
        while (let NodeKind.BlockQuote <- quoteNode.kind) {
            quoteDepth++
            quoteNode = quoteNode.children()[0]
        }
        @Expect(quoteDepth, 2000)
        match (quoteNode.kind) {
            case NodeKind.Paragraph => @Expect(true)
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
        while (let NodeKind.List <- listNode.kind) {
            listDepth++
            let item = listNode.children()[0]
            listNode = item.children()[0]
        }
        @Expect(listDepth, 2000)
        match (listNode.kind) {
            case NodeKind.Paragraph => @Expect(true)
            case _ => @Expect(false)
        }

        let dialect = MarkdownDialect
            .define("deep-extension", "1")
            .enable(ExtensionManifest("deep-extension", "1.0.0", "1"))
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
        while (let NodeKind.CustomBlock <- extensionNode.kind) {
            extensionDepth++
            extensionNode = extensionNode.children()[0]
        }
        @Expect(extensionDepth, 1000)
        match (extensionNode.kind) {
            case NodeKind.Paragraph => @Expect(true)
            case _ => @Expect(false)
        }
    }
}

private func feedFuzzPartitions(session: ChunkedParseSession, bytes: Array<Byte>, caseIndex: Int64): Unit {
    var offset: Int64 = 0
    while (offset < bytes.size) {
        let size = min(bytes.size - offset, ((offset + caseIndex) % 11) + 1)
        session.feed(bytes.slice(offset, size))
        offset += size
    }
}
