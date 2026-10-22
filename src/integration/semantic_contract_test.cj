package markdown.integration

import markdown.core.{AstQuery, CustomPayload, FootnoteReferencePayload, LimitExceededException, MarkdownErrorCode, 
    MarkdownException, OperationBudget, ParseLimits, ParseOutcome}
import markdown.engine.MarkdownEngine
import markdown.extensions.{BlockSyntax, DialectCompiler, ExtensionCapabilities, ExtensionManifest, InlineEscapePolicy, 
    InlineFlankingRule, InlinePayloadEmitter, InlineSyntax, InlineSyntaxMatch, MarkdownDialect, OfficialExtensions, 
    RendererRule, SyntaxParameterType, SyntaxResourceCost}
import markdown.render.{AsyncRenderState, AsyncSinkWriteResult, AsyncTextSink, CanonicalMarkdownRenderer, 
    PlainTextRenderer}
import std.unittest.*
import std.unittest.testmacro.*

private class OpaqueSemanticEmitter <: InlinePayloadEmitter {
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        FootnoteReferencePayload(value.rawLiteral, value.literalSpan)
    }
}

private func semanticLimitConfiguration(capture: Int64, lookahead: Int64): ParseLimits {
    ParseLimits(4096, 4096, 32, 4096, 4096, 32, 1024, 4096, 4096, capture, lookahead)
}

@Test
class SemanticContractTests {
    @TestCase
    func specializedGrammarsRejectUnsupportedConfiguration(): Unit {
        for (kind in [0, 1]) {
            let rule = BlockSyntax.define("footnotes", "footnote-definition").footnoteDefinition()
            if (kind == 0) {
                rule.nesting(false)
            } else {
                rule.parameter("unused", SyntaxParameterType.StringValue)
            }
            let dialect = MarkdownDialect
                .define("invalid-footnote-rule", "1")
                .enable(ExtensionManifest("footnotes", "2.0.0", "fixture"))
                .block(rule)
                .build()
            @ExpectThrows[MarkdownException](DialectCompiler.compile(dialect))
        }
        for (kind in 0..4) {
            let rule = InlineSyntax.define("heading-ids", "heading-id").headingIdSuffix()
            match (kind) {
                case 0 => rule.nesting(true)
                case 1 => rule.escaping(InlineEscapePolicy.LiteralBackslash)
                case 2 => rule.flanking(InlineFlankingRule.CommonMark)
                case _ => rule.flanking(InlineFlankingRule.WordBoundary)
            }
            let dialect = MarkdownDialect
                .define("invalid-heading-rule", "1")
                .enable(ExtensionManifest("heading-ids", "2.0.0", "fixture"))
                .inline(rule)
                .build()
            @ExpectThrows[MarkdownException](DialectCompiler.compile(dialect))
        }
    }

    @TestCase
    func footnotesAndHeadingMetadataChargeConfiguredCostsAndRespectGlobalBounds(): Unit {
        for (kind in [0, 1]) {
            let id = if (kind == 0) {
                "footnotes"
            } else {
                "heading-ids"
            }
            let builder = MarkdownDialect
                .define("costly-semantics", "1")
                .enable(ExtensionManifest(id, "2.0.0", "fixture"))
            let cost = SyntaxResourceCost(baseCost: 1000, perByteCost: 10)
            if (kind == 0) {
                builder.block(BlockSyntax.define(id, "footnote-definition").footnoteDefinition().resourceCost(cost))
            } else {
                builder.inline(InlineSyntax.define(id, "heading-id").headingIdSuffix().resourceCost(cost))
            }
            let engine = MarkdownEngine.builder().dialect(builder.build()).build()
            let source = if (kind == 0) {
                "[^n]: body"
            } else {
                "# Head {#id}"
            }
            match (engine.tryParse(source, budget: OperationBudget(500, 100, 100, 100, 100, 100))) {
                case ParseOutcome.Failure(error) =>
                    if (let MarkdownErrorCode.BudgetExceeded <- error.code) {
                        @Expect(true)
                    } else {
                        @Expect(false)
                    }
                case _ => @Expect(false)
            }
        }
        let dialect = OfficialExtensions.headingIds(MarkdownDialect.define("bounded-heading", "1")).build()
        let capture = MarkdownEngine.builder().dialect(dialect).limits(semanticLimitConfiguration(2, 4096)).build()
        @ExpectThrows[LimitExceededException](capture.parse("# H {#long}"))
        let lookahead = MarkdownEngine.builder().dialect(dialect).limits(semanticLimitConfiguration(4096, 2)).build()
        let parsed = lookahead.parse("# H {#long}")
        @Expect(parsed.document.bindings.headings[0].explicitId.isNone(), true)
        @Expect(parsed.document.bindings.headings[0].text, "H {#long}")
        @Expect(AstQuery.customNodes(parsed.document).size, 0)
    }

    @TestCase
    func compiledTypedRulesRejectGenericRendererOverrides(): Unit {
        let ids = ["footnotes", "footnotes", "heading-ids", "definition-lists", "definition-lists", "definition-lists",
            "definition-lists"]
        let kinds = ["footnote-reference", "footnote-definition", "heading-id", "definition-list", "definition-entry",
            "definition-term", "definition-body"]
        for (index in 0..ids.size) {
            let builder = MarkdownDialect.define("unsupported-renderer", "1")
            if (index < 2) {
                OfficialExtensions.footnotes(builder)
            } else if (index == 2) {
                OfficialExtensions.headingIds(builder)
            } else {
                OfficialExtensions.definitionLists(builder)
            }
            builder.renderer(RendererRule(ids[index], kinds[index], "span"))
            @ExpectThrows[MarkdownException](DialectCompiler.compile(builder.build()))
        }
    }

    @TestCase
    func opaqueTypedEmittersCannotSilentlyIgnoreConfiguredOutputRules(): Unit {
        let dialect = MarkdownDialect
            .define("opaque-semantic", "1")
            .enable(
                ExtensionManifest("opaque", "1.0.0", "fixture",
                    capabilities: ExtensionCapabilities(safeHtml: true, plainText: true, markdown: true)))
            .inline(
                InlineSyntax
                    .define("opaque", "reference")
                    .delimiter("!")
                    .content(false)
                    .emitContent(false)
                    .emit(OpaqueSemanticEmitter()))
            .renderer(
                RendererRule("opaque", "reference", "mark", markdownOpener: "!", markdownCloser: "!",
                    textPrefix: "override", renderPayloadLiteral: true))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let document = engine.parse("!n!").document
        @ExpectThrows[MarkdownException](engine.htmlRenderer().render(document))
        @ExpectThrows[MarkdownException](PlainTextRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(document))
        @ExpectThrows[MarkdownException](CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(document))
        let session = engine.htmlRenderer().newOutputSession(document, chunkBytes: 4)
        let sink = SemanticContractSink()
        match (session.resume(sink)) {
            case AsyncRenderState.Failed(error) =>
                if (let MarkdownErrorCode.UnsupportedNode <- error.code) {
                    @Expect(true)
                } else {
                    @Expect(false)
                }
            case _ => @Expect(false)
        }
    }
}

private class SemanticContractSink <: AsyncTextSink {
    public func write(_: String): AsyncSinkWriteResult {
        AsyncSinkWriteResult.Continue
    }
}
