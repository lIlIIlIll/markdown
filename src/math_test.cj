package markdown

import std.unittest.*
import std.unittest.testmacro.*

private func mathTestEngine(): MarkdownEngine {
    MarkdownEngine.builder().dialect(OfficialExtensions.math(MarkdownDialect.define("math-test", "2")).build()).build()
}

private class MathOutputSink <: AsyncTextSink {
    let text = StringBuilder()
    private var calls: Int64 = 0
    public func write(value: String): AsyncSinkWriteResult {
        calls++
        if (calls % 2 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        text.append(value)
        AsyncSinkWriteResult.Pause(value.size)
    }
}

private class InvalidMathEmitter <: InlinePayloadEmitter {
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        MathPayload(false, "different", [MathSourcePart(value.literalSpan)],
            SourceSpan(value.span.startByte, value.literalSpan.startByte),
            SourceSpan(value.literalSpan.endByte, value.span.endByte))
    }
}

@Test
class StructuredMathTests {
    @TestCase
    func keepsTexAndExactSourcePartsWithoutDerivedMarkup(): Unit {
        let engine = mathTestEngine()
        let input = "A $\\frac{中😀}{2} & x$!\r\n\r\n> $$\r\n> a < b\r\n> + c\r\n> $$\r\n"
        let result = engine.parse(input)
        let nodes = AstQuery.customNodes(result.document)
        @Expect(nodes.size, 2)
        let inlineValue = mathPayload(nodes[0]).getOrThrow()
        @Expect(inlineValue.display, false)
        @Expect(inlineValue.expression, "\\frac{中😀}{2} & x")
        @Expect(result.source.slice(inlineValue.expressionSource[0].span), inlineValue.expression)
        @Expect(result.source.slice(inlineValue.openerSpan), "$")
        @Expect(result.source.slice(inlineValue.closerSpan), "$")
        let block = mathPayload(nodes[1]).getOrThrow()
        @Expect(block.display, true)
        @Expect(block.expression, "a < b\n+ c")
        @Expect(block.expressionSource.size, 2)
        @Expect(result.source.slice(block.expressionSource[0].span), "a < b\r\n")
        @Expect(result.source.slice(block.expressionSource[1].span), "+ c")
        @Expect(engine.htmlRenderer().render(result.document),
            "<p>A <span class=\"math-inline\">\\frac{中😀}{2} &amp; x</span>!</p>\n<blockquote>\n<div class=\"math-block\">a &lt; b\n+ c</div></blockquote>\n")
        @Expect(engine.parseSnapshot(input).syntaxTree.losslessText(), input)
        @Expect(PlainTextRenderer().render(result.document).contains(block.expression), true)
        let output = engine.htmlRenderer().renderWithSourceMap(result.document)
        var mapped = false
        for (entry in output.sourceMap.toArray()) {
            if (entry.nodeId == Some(nodes[0].nodeId)) {
                @Expect(entry.sourceSpan, nodes[0].span)
                mapped = true
            }
        }
        @Expect(mapped, true)
        for (widths in [[1], [2, 9, 1, 13], [input.size]]) {
            expectAppendEquivalent(engine, appendByWidths(engine, input.toArray(), widths), result)
        }
    }

    @TestCase
    func canonicalRoundTripsEmptyNestedAndEscapedMath(): Unit {
        let engine = mathTestEngine()
        for (source in [">\t$$\r\n>\t x\r\n>\t$$", "- $$\n\t\t x\n  $$", "\u{FEFF}$$\r\nx\r\n$$", "$$\n$$", "$$\n\n$$",
            "$$\na\n\n\nb\n$$", "- $$\n  x + y\n  $$\n", "before $a \\$ b$ after", "$x <script> & y$", "# $x$",
            "![value $x$](image.png)"]) {
            let result = engine.parse(source)
            let canonical = CanonicalMarkdownRenderer().render(result.document)
            @Expect(engine.htmlRenderer().render(engine.parse(canonical).document), engine.htmlRenderer().render(result.document))
            @Expect(CanonicalMarkdownRenderer().render(engine.parse(canonical).document), canonical)
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), [1]), result)
        }
        @Expect(engine.htmlRenderer().render(engine.parse("![value $x$](image.png)").document),
            "<p><img src=\"image.png\" alt=\"value x\" /></p>\n")
        let withHeading = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        @Expect(withHeading.parse("# $x$ {#formula}").document.bindings.headings[0].text, "x")
        let document = engine.parse("![value $中😀$](image.png)\n\n$$\na < b\n$$").document
        let output = engine.htmlRenderer().newOutputSession(document, chunkBytes: 4)
        let sink = MathOutputSink()
        var complete = false
        while (!complete) {
            match (output.resume(sink)) {
                case AsyncRenderState.Complete => complete = true
                case AsyncRenderState.Paused => ()
                case AsyncRenderState.Failed(error) => throw error
            }
        }
        @Expect(sink.text.toString(), engine.htmlRenderer().render(document))
    }

    @TestCase
    func partialTabExpansionKeepsPhysicalSourceAndNormalizedExpressionSeparate(): Unit {
        let engine = mathTestEngine()
        let input = ">\t$$\r\n>\t x\r\n>\t$$"
        let parsed = engine.parse(input)
        let value = mathPayload(AstQuery.customNodes(parsed.document)[0]).getOrThrow()
        @Expect(value.expression, "   x")
        let part = value.expressionSource[0]
        @Expect(parsed.source.slice(part.span), "\t x")
        @Expect(part.expandedPrefixBytes, 1)
        @Expect(part.expandedPrefixSpaces, 2)
        let original = [MathSourcePart(SourceSpan(0, 0))]
        let copied = MathPayload(true, "", original, SourceSpan(0, 2), SourceSpan(3, 5))
        original[0] = MathSourcePart(SourceSpan(6, 6))
        @Expect(copied.expressionSource[0].span, SourceSpan(0, 0))
        @ExpectThrows[IllegalArgumentException](MathSourcePart(SourceSpan(0, 1), expandedPrefixBytes: 1,
            expandedPrefixSpaces: 5))
        @ExpectThrows[IllegalArgumentException](MathSourcePart(SourceSpan(0, 1), expandedPrefixSpaces: 1))
    }

    @TestCase
    func fixedGrammarRejectsIgnoredFlagsAndKeepsNonMathText(): Unit {
        let engine = mathTestEngine()
        for (source in ["$$ trailing\nx\n$$", "$$\nunclosed", "`$code$`", "\\$escaped$", "    $$\n    code\n    $$",
            "\t$$\n\tcode\n\t$$"]) {
            let result = engine.parse(source)
            var displayCount: Int64 = 0
            for (node in AstQuery.customNodes(result.document)) {
                if (let Some(value) <- mathPayload(node)) {
                    if (value.display) {
                        displayCount++
                    }
                }
            }
            @Expect(displayCount, 0)
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), [1, 3]), result)
        }
        for (index in 0..3) {
            let rule = BlockSyntax.define("math", "math-block").displayMath()
            if (index == 0) {
                rule.nesting(true)
            }
            if (index == 1) {
                rule.content(BlockContentMode.Markdown)
            }
            if (index == 2) {
                rule.documentStartOnly()
            }
            let dialect = MarkdownDialect
                .define("bad-math", "2")
                .enable(ExtensionManifest("math", "2.0.0", "2"))
                .block(rule)
                .build()
            @ExpectThrows[MarkdownException](DialectCompiler.compile(dialect))
        }
        let override = OfficialExtensions
            .math(MarkdownDialect.define("override-math", "2"))
            .renderer(RendererRule("math", "math-inline", "span"))
            .build()
        @ExpectThrows[MarkdownException](DialectCompiler.compile(override))
        @ExpectThrows[MarkdownException](engine.parseEvents("$x$"))
        @ExpectThrows[MarkdownException](engine.newRawBlockEventSession())
        @ExpectThrows[MarkdownException](engine.renderHtml("$x$", mode: HtmlExecutionMode.RequireFused))
        @Expect(AstQuery.customNodes(Markdown.parse("$x$\n\n$$\ny\n$$").document).size, 0)
    }

    @TestCase
    func boundsSourceCaptureAndRejectsForgedPayloads(): Unit {
        let dialect = OfficialExtensions.math(MarkdownDialect.define("bounded-math", "2")).build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let limited = MarkdownEngine
            .builder()
            .dialect(dialect)
            .limits(ParseLimits(4096, 4096, 32, 4096, 4096, 32, 1024, 4096, 4096, 2, 4096))
            .build()
        @ExpectThrows[LimitExceededException](limited.parse("$abc$"))
        @ExpectThrows[LimitExceededException](limited.parse("$$\nabc\n$$"))
        let cancelled = CancellationSource()
        cancelled.cancel()
        @ExpectThrows[MarkdownException](engine.parse("$x$", cancellation: cancelled.token))
        @ExpectThrows[MarkdownException](engine.parse("$$\nx\n$$", budget: OperationBudget(1, 100, 100, 100, 100, 100)))
        let invalid = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("forged-math", "2")
                    .enable(ExtensionManifest("forged", "1.0.0", "1"))
                    .inline(
                        InlineSyntax
                            .define("forged", "math")
                            .delimiter("$")
                            .content(false)
                            .emitContent(false)
                            .emit(InvalidMathEmitter()))
                    .build())
            .build()
        @ExpectThrows[MarkdownException](invalid.parse("$x$"))
        let bytes: Array<Byte> = [b'$', 0xFF, b'$', b'\n', b'\n', b'$', b'$', b'\r', b'\n', 0xFF, b'\r', b'\n', b'$',
            b'$']
        let replaced = engine.parse(bytes, utf8Policy: Utf8Policy.ReplaceInvalid)
        @Expect(mathPayload(AstQuery.customNodes(replaced.document)[0]).getOrThrow().expression, "�")
        expectAppendEquivalent(engine, appendByWidths(engine, bytes, [1], policy: Utf8Policy.ReplaceInvalid), replaced)
    }
}
