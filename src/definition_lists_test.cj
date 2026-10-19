package markdown

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func definitionTestEngine(): MarkdownEngine {
    MarkdownEngine
        .builder()
        .dialect(
            OfficialExtensions
                .definitionLists(MarkdownDialect.define("definitions-test", "2").base(MarkdownProfile.gfmModernV1()))
                .build())
        .build()
}

private class InvalidDefinitionInlineEmitter <: InlinePayloadEmitter {
    public func emit(_: InlineSyntaxMatch): CustomPayload {
        DefinitionListPayload(DefinitionListRole.Term)
    }
}

private class DefinitionOutputSink <: AsyncTextSink {
    private let out = StringBuilder()
    private var calls: Int64 = 0
    public func write(value: String): AsyncSinkWriteResult {
        calls++
        if (calls % 2 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        out.append(value)
        AsyncSinkWriteResult.Pause(value.size)
    }
    func content(): String {
        out.toString()
    }
}

@Test
class DefinitionListTests {
    @TestCase
    func groupsMultipleTermsAndDefinitionsWithExactHtmlTextAndMarkdown(): Unit {
        let engine = definitionTestEngine()
        let source = "Term one\nTerm *two*\n: first\n: second\n\nNext\n: third\n"
        let result = engine.parse(source)
        let list = result.document.root().children()[0]
        @Expect(result.document.root().children().size, 1)
        @Expect(list.children().size, 2)
        let payload = list.asCustomBlock().getOrThrow().payload as DefinitionListPayload
        if (let DefinitionListRole.List <- payload.getOrThrow().role) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        @Expect(list.children()[0].children().size, 4)
        @Expect(list.children()[1].children().size, 2)
        let expected = "<dl>\n<dt>Term one</dt>\n<dt>Term <em>two</em></dt>\n<dd>\n<p>first</p>\n</dd>\n<dd>\n<p>second</p>\n</dd>\n<dt>Next</dt>\n<dd>\n<p>third</p>\n</dd>\n</dl>\n"
        @Expect(engine.htmlRenderer().render(result.document), expected)
        @Expect(PlainTextRenderer().render(result.document), "Term one\nTerm two\nfirst\n\nsecond\n\nNext\nthird")
        let formatted = CanonicalMarkdownRenderer().render(result.document)
        @Expect(formatted, "Term&#32;one\nTerm&#32;*two*\n: first\n: second\n\nNext\n: third\n")
        @Expect(engine.htmlRenderer().render(engine.parse(formatted).document), expected)
        for (node in AstQuery.customNodes(result.document)) {
            if (let value: DefinitionListPayload <- node.asCustomBlock().getOrThrow().payload) {
                if (let Some(marker) <- value.markerSpan) {
                    @Expect(result.source.slice(marker), ":")
                }
            }
        }
        let empty = engine.parse("Empty\n:\n")
        @Expect(engine.htmlRenderer().render(empty.document), "<dl>\n<dt>Empty</dt>\n<dd>\n</dd>\n</dl>\n")
        @Expect(CanonicalMarkdownRenderer().render(empty.document), "Empty\n:\n")
    }

    @TestCase
    func bodyUsesNormalBlocksAndKeepsContainerUnicodeAndCrLfPositions(): Unit {
        let engine = definitionTestEngine()
        let inputs = ["术语😀\r\n: first **body**\r\n\r\n  second\r\n\r\n  > quote\r\n\r\n  - item\r\n\r\n  ```cj\r\n  code < x\r\n  ```\r\n\r\noutside\r\n",
            "> Term\n> : definition\n>\n>   continued\n\noutside\n",
            "- Term\n  : definition\n\n    second\n\n- outside\n", "Term\n: before\n\n\tcontinued\n",
            "Outer\n: Inner\n  : nested\n"]
        for (source in inputs) {
            let expected = engine.parse(source)
            @Expect(AstQuery.customNodes(expected.document).size > 0, true)
            @Expect(engine.parseSnapshot(source).syntaxTree.losslessText(), source)
            let formatted = CanonicalMarkdownRenderer().render(expected.document)
            @Expect(engine.htmlRenderer().render(engine.parse(formatted).document), engine.htmlRenderer().render(expected.document))
            for (widths in [[1], [1, 13, 2, 7], [source.size]]) {
                expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), expected)
            }
        }
    }

    @TestCase
    func orphanMarkersSetextCodeAndDisabledProfilesRemainOrdinaryMarkdown(): Unit {
        let engine = definitionTestEngine()
        for (source in [": orphan", "Term\n===\n: orphan", "Term\n---\n: orphan", "Term\n\n\n: orphan",
            "    Term\n    : code", "```text\nTerm\n: code\n```", "Term\n:not-a-marker"]) {
            @Expect(AstQuery.customNodes(engine.parse(source).document).size, 0)
        }
        let atMostOneBlank = engine.parse("Term\n\n: definition")
        @Expect(atMostOneBlank.document.root().children().size, 1)
        @Expect(AstQuery.customNodes(atMostOneBlank.document).size, 4)
        let base = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        let source = "Term\n: definition\n"
        @Expect(AstQuery.customNodes(base.parse(source).document).size, 0)
        let disabled = MarkdownEngine
            .builder()
            .dialect(
                OfficialExtensions
                    .definitionLists(MarkdownDialect.define("off", "2"))
                    .parserOptions(DialectParserOptions(extensionsEnabled: false))
                    .build())
            .build()
        @Expect(disabled.htmlRenderer().render(disabled.parse(source).document), base.htmlRenderer().render(base.parse(source).document))
        @ExpectThrows[MarkdownException](engine.parseEvents(source))
        @ExpectThrows[MarkdownException](engine.newRawBlockEventSession())
        @ExpectThrows[MarkdownException](engine.renderHtml(source, mode: HtmlExecutionMode.RequireFused))
    }

    @TestCase
    func lateMarkersAndAdditionalEntriesDoNotCommitTermParagraphsTooEarly(): Unit {
        let engine = definitionTestEngine()
        let session = engine.newAppendSession()
        let replica = AppendReplica()
        replica.apply(session.feed("Term\n\n"))
        @Expect(replica.blocks().size, 0)
        replica.apply(session.feed(": first\n\nNext\n"))
        @Expect(replica.blocks().size, 0)
        replica.apply(session.feed(": second\n\n# stop\n"))
        let final = session.finish()
        replica.apply(final)
        let result = replica.result.getOrThrow()
        @Expect(result.document.root().children().size, 2)
        @Expect(result.document.root().children()[0].children().size, 2)
        expectAppendEquivalent(engine, result, engine.parse("Term\n\n: first\n\nNext\n: second\n\n# stop\n"))
        for (source in ["Term\n: first\n\n\nOther\n: second\n", "Term\n: first\n\nplain\n\n\n: orphan\n",
            "Term\n: first\n\nNext\n: second\n\nplain\n", "Term\n: first\n\n# Heading\n\n: orphan\n"]) {
            for (widths in [[1], [7], [source.size]]) {
                expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), engine.parse(source))
            }
        }
    }

    @TestCase
    func footnoteHeadingAndNestedLinkDefinitionsShareBindingAndSnapshotState(): Unit {
        let engine = MarkdownEngine
            .builder()
            .dialect(
                OfficialExtensions
                    .headingIds(
                        OfficialExtensions.footnotes(
                            OfficialExtensions.definitionLists(MarkdownDialect.define("combined-definitions", "2"))))
                    .build())
            .bindingOptions(BindingOptions(idScope: "part"))
            .build()
        let source = "Term [^n]\n: # Body {#body}\n\n  See [later][id] & **strong**.\n\n  [id]: /target\n\n[^n]: note\n"
        let expected = engine.parse(source)
        @Expect(expected.document.references.size, 1)
        @Expect(expected.document.bindings.footnotes.size, 1)
        @Expect(expected.document.bindings.headings.size, 1)
        let heading = expected.document.bindings.headings[0]
        let html = engine.htmlRenderer().render(expected.document)
        @Expect(html.contains("<h1 id=\"${heading.id}\">Body</h1>"), true)
        @Expect(html.contains("href=\"/target\""), true)
        let markdown = CanonicalMarkdownRenderer().render(expected.document)
        @Expect(engine.htmlRenderer().render(engine.parse(markdown).document), html)
        for (widths in [[1], [1, 17, 3], [source.size]]) {
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), expected)
        }
        let invalid: Array<Byte> = [0xFF, b'\n', b':', b' ', b'b', b'\n']
        let replaced = engine.parse(invalid, utf8Policy: Utf8Policy.ReplaceInvalid)
        expectAppendEquivalent(engine, appendByWidths(engine, invalid, [1], policy: Utf8Policy.ReplaceInvalid), replaced)
    }

    @TestCase
    func resumableHtmlUsesTheSameTypedDefinitionStructure(): Unit {
        let engine = definitionTestEngine()
        let source = "Term **one**\nTerm 中文😀\n: first & body\n\n  second\n: - nested\n\nNext\n: ```text\n  code < x\n  ```\n"
        let document = engine.parse(source).document
        for (width in [4, 7, 4096]) {
            let session = engine.htmlRenderer().newOutputSession(document, chunkBytes: width)
            let sink = DefinitionOutputSink()
            var complete = false
            while (!complete) {
                match (session.resume(sink)) {
                    case AsyncRenderState.Paused => ()
                    case AsyncRenderState.Complete => complete = true
                    case AsyncRenderState.Failed(error) => throw error
                }
            }
            @Expect(sink.content(), engine.htmlRenderer().render(document))
            @Expect(session.bytesWritten(), session.bytesProduced())
        }
    }

    @TestCase
    func malformedTypedPayloadsAndConfiguredBoundsFailExplicitly(): Unit {
        let invalid = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("invalid-definition", "2")
                    .enable(ExtensionManifest("invalid-definition", "2.0.0", "1"))
                    .inline(
                        InlineSyntax
                            .define("invalid-definition", "term")
                            .delimiter("!")
                            .content(false)
                            .emitContent(false)
                            .emit(InvalidDefinitionInlineEmitter()))
                    .build())
            .build()
        match (invalid.tryParse("!term!")) {
            case ParseOutcome.Failure(error) => @Expect(error.phase, "bind")
            case _ => @Expect(false)
        }
        for (kind in [0, 1]) {
            let rule = BlockSyntax.define("definition-lists", "definition-list").definitionList()
            if (kind == 0) {
                rule.maximumBlockBytes(10)
            } else {
                rule.maximumCaptureLength(4)
            }
            let engine = MarkdownEngine
                .builder()
                .dialect(
                    MarkdownDialect
                        .define("bounded-definitions", "2")
                        .enable(ExtensionManifest("definition-lists", "2.0.0", "1"))
                        .block(rule)
                        .build())
                .build()
            match (engine.tryParse("Long term\n: definition\n")) {
                case ParseOutcome.Failure(error) => @Expect(error is LimitExceededException, true)
                case _ => @Expect(false)
            }
        }
        let source = CancellationSource()
        source.cancel()
        @ExpectThrows[MarkdownException](definitionTestEngine().parse("Term\n: body", cancellation: source.token))
    }

    @TestCase
    func structuredGrammarRejectsUnsupportedFlagsAndChargesDeclaredResourceCost(): Unit {
        for (kind in [0, 1]) {
            let rule = BlockSyntax.define("definition-lists", "definition-list").definitionList()
            if (kind == 0) {
                rule.nesting(false)
            } else {
                rule.documentStartOnly()
            }
            let dialect = MarkdownDialect
                .define("invalid-definition-options", "2")
                .enable(ExtensionManifest("definition-lists", "2.0.0", "1"))
                .block(rule)
                .build()
            @ExpectThrows[MarkdownException](DialectCompiler.compile(dialect))
        }
        let costly = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("costly-definitions", "2")
                    .enable(ExtensionManifest("definition-lists", "2.0.0", "1"))
                    .block(
                        BlockSyntax
                            .define("definition-lists", "definition-list")
                            .definitionList()
                            .resourceCost(SyntaxResourceCost(baseCost: 1000, perByteCost: 10)))
                    .build())
            .build()
        match (costly.tryParse("Term\n: body\n", budget: OperationBudget(500, 100, 10, 10, 100, 100))) {
            case ParseOutcome.Failure(error) =>
                if (let MarkdownErrorCode.BudgetExceeded <- error.code) {
                    @Expect(true)
                } else {
                    @Expect(false)
                }
            case _ => @Expect(false)
        }
    }

    @TestCase
    func nestedFencesAndIndentedBodiesHaveLinearAppendWork(): Unit {
        let engine = definitionTestEngine()
        for (shape in [0, 1]) {
            var previousScan: Int64 = 0
            var previousNodes: Int64 = 0
            for (count in [16, 32, 64]) {
                let source = StringBuilder()
                for (index in 0..count) {
                    source.append("Term ${index}\n: body\n\n")
                    source.append(if (shape == 0) {
                        "  ```text\n  literal\n  ```\n\n"
                    } else {
                        "    paragraph\n\n"
                    })
                }
                source.append("# stop\n")
                let text = source.toString()
                let bytes = text.toArray()
                let session = engine.newAppendSession()
                let replica = AppendReplica()
                var start: Int64 = 0
                for (index in 0..bytes.size) {
                    if (bytes[index] == b'\n') {
                        replica.apply(session.feed(bytes[start..index + 1]));
                        start = index + 1
                    }
                }
                let final = session.finish()
                replica.apply(final)
                @Expect(final.progress.scanSteps <= bytes.size * 64, true)
                if (previousScan > 0) {
                    @Expect(final.progress.scanSteps <= previousScan * 3, true)
                    @Expect(final.progress.nodeConstructionSteps <= previousNodes * 3, true)
                }
                previousScan = final.progress.scanSteps
                previousNodes = final.progress.nodeConstructionSteps
                expectAppendEquivalent(engine, replica.result.getOrThrow(), engine.parse(text))
            }
        }
    }
}
