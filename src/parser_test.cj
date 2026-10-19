package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParserBehaviorTest {
    @TestCase
    func multilineSetextInlineSpansKeepCrLfAndContainerOffsets(): Unit {
        let source = "> **a**\r\n> b\r\n> ---\r\n"
        let result = Markdown.parse(source)
        let headings = AstQuery.headings(result.document)
        @Expect(headings.size, 1)
        @Expect(headings[0].level, 2)
        let text = AstQuery.byKind(result.document, NodeKind.Text)
        @Expect(text.size, 2)
        @Expect(result.source.text(text[0]), "a")
        @Expect(result.source.text(text[1]), "b")
        @Expect(text[1].asText().getOrThrow().raw, "b")
        @Expect(text[1].span, Some(SourceSpan(11, 12)))
        AstInvariantValidator().validate(result.document)
    }

    @TestCase
    func coalescesTextLoweringsButKeepsSemanticInlineBoundaries(): Unit {
        let entityResult = Markdown.parse("a&amp;b")
        let entityChildren = entityResult.document.children()[0].children()
        @Expect(entityChildren.size, 1)
        @Expect(entityChildren[0].asText().getOrThrow().value, "a&b")
        @Expect(entityResult.document.storedNodeCount, entityResult.document.nodeCount)

        let delimiterResult = Markdown.parse("a&amp;b *c* \\!")
        let delimiterChildren = delimiterResult.document.children()[0].children()
        @Expect(delimiterChildren.size, 3)
        @Expect(delimiterChildren[0].asText().getOrThrow().value, "a&b ")
        @Expect(delimiterChildren[2].asText().getOrThrow().value, " !")
        // Core delimiter parsing delays text lowering until the final piece
        // sequence is known, so no unreachable Text records remain in storage.
        @Expect(delimiterResult.document.storedNodeCount, delimiterResult.document.nodeCount)

        let linkChildren = Markdown.parse("a [x](u) b").document.children()[0].children()
        @Expect(linkChildren.size, 3)
        match (linkChildren[0].kind) {
            case NodeKind.Text => @Expect(true)
            case _ => @Expect(false)
        }
        match (linkChildren[1].kind) {
            case NodeKind.Link => @Expect(true)
            case _ => @Expect(false)
        }
        match (linkChildren[2].kind) {
            case NodeKind.Text => @Expect(true)
            case _ => @Expect(false)
        }

        let gfmLinkResult = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfmModernV1())
            .build()
            .parse("a [x](https://example.com) b")
        @Expect(gfmLinkResult.document.children()[0].children().size, 3)
        @Expect(gfmLinkResult.document.storedNodeCount, gfmLinkResult.document.nodeCount)

        let multilineDelimiterResult = Markdown.parse("*cross\nline*")
        @Expect(multilineDelimiterResult.document.storedNodeCount, multilineDelimiterResult.document.nodeCount)
        match (multilineDelimiterResult.document.children()[0].children()[0].kind) {
            case NodeKind.Emphasis => @Expect(true)
            case _ => @Expect(false)
        }

        let multilineUnderscoreResult = Markdown.parse("_cross\nline_")
        @Expect(multilineUnderscoreResult.document.storedNodeCount, multilineUnderscoreResult.document.nodeCount)
        match (multilineUnderscoreResult.document.children()[0].children()[0].kind) {
            case NodeKind.Emphasis => @Expect(true)
            case _ => @Expect(false)
        }

        let multilineCodeResult = Markdown.parse("`cross\nline`")
        @Expect(multilineCodeResult.document.storedNodeCount, multilineCodeResult.document.nodeCount)
        match (multilineCodeResult.document.children()[0].children()[0].kind) {
            case NodeKind.CodeSpan => @Expect(true)
            case _ => @Expect(false)
        }
    }

    @TestCase
    func stripsListContainerIndentWithoutBreakingMultilineInlineSpans(): Unit {
        let source = "1.  first line with [a link\n    across lines](https://example.com) and `code`.\n"
        @Expect(
            unsafe { Markdown.toSpecHtml(source) },
            "<ol>\n<li>first line with <a href=\"https://example.com\">a link\nacross lines</a> and <code>code</code>.</li>\n</ol>\n")
        let paragraph = Markdown.parse(source).document.children()[0].children()[0].children()[0]
        let link = paragraph.children()[1]
        @Expect(link.span, Some(SourceSpan(20, 66)))
        @Expect(link.children()[0].span, Some(SourceSpan(21, 27)))
        @Expect(link.children()[1].span, Some(SourceSpan(27, 32)))
        @Expect(link.children()[2].span, Some(SourceSpan(32, 44)))

        @Expect(
            unsafe {
                Markdown.toSpecHtml(
                    "1.  first line\n    then [a link starts\n    here](https://example.com).\n")
            },
            "<ol>\n<li>first line\nthen <a href=\"https://example.com\">a link starts\nhere</a>.</li>\n</ol>\n")
        @Expect(
            unsafe {
                Markdown.toSpecHtml("1.  item\n\n    ``` markdown\n    paragraph\n        code?\n    ```\n")
            },
            "<ol>\n<li>\n<p>item</p>\n<pre><code class=\"language-markdown\">paragraph\n    code?\n</code></pre>\n</li>\n</ol>\n")
        @Expect(
            unsafe { Markdown.toSpecHtml("1.  *first line*\n    continuation\n") },
            "<ol>\n<li><em>first line</em>\ncontinuation</li>\n</ol>\n")
        @Expect(
            unsafe { Markdown.toSpecHtml("> *first line*\n> continuation\n") },
            "<blockquote>\n<p><em>first line</em>\ncontinuation</p>\n</blockquote>\n")
        @Expect(unsafe { Markdown.toSpecHtml("`code` and trailing ") }, "<p><code>code</code> and trailing</p>\n")
    }

    @TestCase
    func decodesOnlyLinkTargetsThatContainEscapesOrEntities(): Unit {
        let result = Markdown.parse(
            "[plain](https://example.com/路径 \"title\") [entity](https://example.com/a&amp;b \"x &amp; y\") " +
                "[escaped](foo\\(bar\\) \"a\\\"b\")")
        let children = result.document.children()[0].children()

        let plain = children[0].asLink().getOrThrow()
        @Expect(plain.destination, "https://example.com/路径")
        @Expect(plain.title, "title")

        let entity = children[2].asLink().getOrThrow()
        @Expect(entity.destination, "https://example.com/a&b")
        @Expect(entity.title, "x & y")

        let escaped = children[4].asLink().getOrThrow()
        @Expect(escaped.destination, "foo(bar)")
        @Expect(escaped.title, "a\"b")
    }

    @TestCase
    func validatesMultilineQuotedRawHtmlTag(): Unit {
        let quoted = Markdown.parse("before <a foo=\"bar\" bam='baz <em>\"</em>'\n_boolean zoop:33=zoop:33 /> after")
        let quotedParagraph = quoted.document.children()[0]
        match (quotedParagraph.kind) {
            case NodeKind.Paragraph => match (quotedParagraph.children()[1].kind) {
                case NodeKind.HtmlInline => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let invalid = Markdown.parse("<bar/ >")
        let invalidParagraph = invalid.document.children()[0]
        match (invalidParagraph.kind) {
            case NodeKind.Paragraph =>
                let text = invalidParagraph.children()[0]
                match (text.kind) {
                    case NodeKind.Text => @Expect(text.asText().getOrThrow().value, "<bar/ >")
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        let html = Markdown.parse("<div>\nx\n</div>").document.children()[0]
        match (html.kind) {
            case NodeKind.HtmlBlock => match (html.asHtmlBlock().getOrThrow().storedLiteral()) {
                case LiteralStorage.Slice(_) => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
    }

    @TestCase
    func htmlTypeOneOpenersRequireTagNameBoundary(): Unit {
        for (tag in ["scripture", "prelude", "stylex", "textareax"]) {
            let source = "<${tag}>\nraw *body*\n\n*after*\n"
            @Expect(
                unsafe { Markdown.toSpecHtml(source) },
                "<${tag}>\nraw *body*\n<p><em>after</em></p>\n")
        }

        for (source in [
            "<script >\nvalue\n</script>\n",
            "<script>\nvalue\n</script>\n",
            "<script\t>\nvalue\n</script>\n",
            "<script\nvalue\n</script>\n"
        ]) {
            @Expect(unsafe { Markdown.toSpecHtml(source) }, source)
        }
    }

    @TestCase
    func parsesBlocksInlinesReferencesAndExactSpans(): Unit {
        let input = "# 标题\n\nA **strong** and [link][id].\n\n[id]: https://example.com \"title\"\n"
        let result = MarkdownEngine.builder().build().parse(input)
        @Expect(result.document.children().size, 2)
        let headingNode = result.document.children()[0]
        match (headingNode.kind) {
            case NodeKind.Heading =>
                let heading = headingNode.asHeading().getOrThrow()
                @Expect(heading.level, 1)
                @Expect(headingNode.span, Some(SourceSpan(0, 8)))
                let textNode = headingNode.children()[0]
                match (textNode.kind) {
                    case NodeKind.Text =>
                        let text = textNode.asText().getOrThrow()
                        @Expect(text.value, "标题")
                        match (text.valueLiteralStorage()) {
                            case LiteralStorage.Slice(_) => @Expect(true)
                            case _ => @Expect(false)
                        }
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        let paragraph = result.document.children()[1]
        match (paragraph.kind) {
            case NodeKind.Paragraph =>
                @Expect(paragraph.children().size, 5)
                match (paragraph.children()[1].kind) {
                    case NodeKind.Strong => @Expect(paragraph.children()[1].children().size, 1)
                    case _ => @Expect(false)
                }
                let linkNode = paragraph.children()[3]
                match (linkNode.kind) {
                    case NodeKind.Link =>
                        let link = linkNode.asLink().getOrThrow()
                        @Expect(link.destination, "https://example.com")
                        @Expect(link.title, "title")
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        @Expect(result.document.references.size, 1)
        AstInvariantValidator().validate(result.document)
    }

    @TestCase
    func referenceNormalizationKeepsAsciiAndUnicodeCaseFoldingEquivalent(): Unit {
        let input = "[Foo \t Bar]: /ascii\n[Straße]: /unicode\n\n[foo bar] and [STRASSE]\n"
        @Expect(
            unsafe { Markdown.toSpecHtml(input) },
            "<p><a href=\"/ascii\">foo bar</a> and <a href=\"/unicode\">STRASSE</a></p>\n")
    }

    @TestCase
    func parsesFencesListsQuotesAndGfmTableWithoutLosingMetadata(): Unit {
        let input = "> quoted\n\n- [x] done\n- plain\n\n```cj\nmain()\n```\n\n| a | b |\n| :- | -: |\n| c | d |"
        let result = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build().parse(input)
        @Expect(result.document.children().size, 4)
        let listNode = result.document.children()[1]
        match (listNode.kind) {
            case NodeKind.List =>
                @Expect(listNode.children().size, 2)
                let itemNode = listNode.children()[0]
                match (itemNode.kind) {
                    case NodeKind.ListItem => match (itemNode.asListItem().getOrThrow().taskState) {
                        case TaskState.Checked => @Expect(itemNode.asListItem().getOrThrow().markerSpan.isSome(), true)
                        case _ => @Expect(false)
                    }
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        let codeNode = result.document.children()[2]
        match (codeNode.kind) {
            case NodeKind.CodeBlock =>
                let code = codeNode.asCodeBlock().getOrThrow()
                @Expect(code.literal, "main()\n")
                @Expect(code.language, "cj")
                @Expect(code.openingFenceSpan.isSome(), true)
                @Expect(code.closingFenceSpan.isSome(), true)
                match (code.storedLiteral()) {
                    case LiteralStorage.Slice(_) => @Expect(true)
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        let tableNode = result.document.children()[3]
        match (tableNode.kind) {
            case NodeKind.Table =>
                let table = tableNode.asTable().getOrThrow()
                @Expect(tableNode.children().size, 2)
                @Expect(table.alignments.size, 2)
                let header = tableNode.children()[0]
                match (header.kind) {
                    case NodeKind.TableRow =>
                        @Expect(header.children()[0].span, Some(SourceSpan(50, 51)))
                        @Expect(header.children()[1].span, Some(SourceSpan(54, 55)))
                    case _ => @Expect(false)
                }
                let body = tableNode.children()[1]
                match (body.kind) {
                    case NodeKind.TableRow =>
                        @Expect(body.children()[0].span, Some(SourceSpan(72, 73)))
                        @Expect(body.children()[1].span, Some(SourceSpan(76, 77)))
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }

        let autolinkTable = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfmModernV1())
            .build()
            .parse("| url |\n| --- |\n| www.example.com |")
            .document
            .children()[0]
        let autolinkCell = autolinkTable.children()[1].children()[0]
        match (autolinkCell.children()[0].kind) {
            case NodeKind.Link => @Expect(true)
            case _ => @Expect(false)
        }
    }

    @TestCase
    func singleFenceFastPathPreservesFullAstAndFallsBackWithoutSemanticDrift(): Unit {
        let result = Markdown.parse("```cj\nalpha\nbeta\n```\n\n")
        @Expect(result.document.children().size, 1)
        @Expect(result.document.nodeCount, 2)
        let node = result.document.children()[0]
        @Expect(node.nodeId, NodeId(result.document.lineage, 1))
        @Expect(node.span, Some(SourceSpan(0, 20)))
        let code = node.asCodeBlock().getOrThrow()
        @Expect(code.literal, "alpha\nbeta\n")
        @Expect(code.language, "cj")
        @Expect(code.openingFenceSpan, Some(SourceSpan(0, 3)))
        @Expect(code.closingFenceSpan, Some(SourceSpan(17, 20)))
        match (code.storedLiteral()) {
            case LiteralStorage.Slice(slice) => @Expect(slice.span, SourceSpan(6, 17))
            case _ => @Expect(false)
        }
        AstInvariantValidator().validate(result.document)

        let trailingBlock = Markdown.parse("```\nx\n```\nparagraph")
        @Expect(trailingBlock.document.children().size, 2)
        @Expect(trailingBlock.document.children()[0].asCodeBlock().getOrThrow().literal, "x\n")
        match (trailingBlock.document.children()[1].kind) {
            case NodeKind.Paragraph => @Expect(true)
            case _ => @Expect(false)
        }

        let crlf = Markdown.parse("```\r\nx\r\n```\r\n")
        @Expect(crlf.document.children().size, 1)
        @Expect(crlf.document.children()[0].asCodeBlock().getOrThrow().literal, "x\n")
        @Expect(crlf.document.children()[0].span, Some(SourceSpan(0, 11)))
        for (source in ["```", "```\n", "```\nx", "`````\n\n```\naaa\n"]) {
            let unclosed = Markdown.parse(source)
            @Expect(unclosed.document.children()[0].span, Some(SourceSpan(0, source.size)))
            let mapped = HtmlRenderer().renderWithSourceMap(unclosed.document)
            for (entry in mapped.sourceMap.toArray()) {
                if (!entry.generated) {
                    @Expect(entry.sourceSpan, Some(SourceSpan(0, source.size)))
                }
            }
        }
    }

    @TestCase
    func commonMarkPipeParagraphFastPathPreservesFullAst(): Unit {
        let result = Markdown.parse("| a |\n| b |\n")
        @Expect(result.document.nodeCount, 5)
        let paragraph = result.document.children()[0]
        @Expect(paragraph.nodeId, NodeId(result.document.lineage, 4))
        @Expect(paragraph.span, Some(SourceSpan(0, 11)))
        @Expect(paragraph.children().size, 3)
        @Expect(paragraph.children()[0].nodeId, NodeId(result.document.lineage, 1))
        @Expect(paragraph.children()[0].span, Some(SourceSpan(0, 5)))
        @Expect(paragraph.children()[0].asText().getOrThrow().value, "| a |")
        match (paragraph.children()[1].kind) {
            case NodeKind.SoftBreak => @Expect(paragraph.children()[1].span, Some(SourceSpan(5, 6)))
            case _ => @Expect(false)
        }
        @Expect(paragraph.children()[2].nodeId, NodeId(result.document.lineage, 3))
        @Expect(paragraph.children()[2].span, Some(SourceSpan(6, 11)))
        @Expect(paragraph.children()[2].asText().getOrThrow().value, "| b |")
        AstInvariantValidator().validate(result.document)
        @Expect(HtmlRenderer(options: unsafe { HtmlOptions.specCompatible() }).render(result.document), "<p>| a |\n| b |</p>\n")
    }

    @TestCase
    func preservesMalformedInlineAsTextAndHonorsResourceControls(): Unit {
        let input = "**unfinished [link `code"
        let result = MarkdownEngine.builder().build().parse(input)
        let malformedParagraph = result.document.children()[0]
        match (malformedParagraph.kind) {
            case NodeKind.Paragraph =>
                @Expect(malformedParagraph.children().size, 1)
                let malformedText = malformedParagraph.children()[0]
                match (malformedText.kind) {
                    case NodeKind.Text => @Expect(malformedText.asText().getOrThrow().value, input)
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }

        let tiny = ParseLimits(4, 4, 8, 16, 4, 4, 4, 4, 8, 4, 4)
        try {
            MarkdownEngine.builder().limits(tiny).build().parse("12345")
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "input_bytes")
            @Expect(error.configuredLimit, 4)
            @Expect(error.observedValue, 5)
        }

        let cancelled = CancellationSource()
        cancelled.cancel()
        try {
            MarkdownEngine.builder().build().parse("x", cancellation: cancelled.token)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled => @Expect(error.phase, "input")
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func enforcesAstNodeAndAccumulatedLiteralLimitsDuringConstruction(): Unit {
        let nodeLimited = ParseLimits(1024, 1024, 16, 4, 16, 16, 1024, 1024, 4096, 1024, 1024)
        try {
            MarkdownEngine.builder().limits(nodeLimited).build().parse("a *b* c")
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "ast_nodes")
            @Expect(error.configuredLimit, 4)
            @Expect(error.phase, "ast_allocation")
        }

        let literalLimited = ParseLimits(1024, 1024, 16, 64, 16, 16, 1024, 5, 4096, 1024, 1024)
        for (input in ["```\nab\ncd\n```", "<script>\nab\ncd\n</script>"]) {
            try {
                MarkdownEngine.builder().limits(literalLimited).build().parse(input)
                @Expect(false)
            } catch (error: LimitExceededException) {
                @Expect(error.limitKind, "literal_bytes")
                @Expect(error.configuredLimit, 5)
                @Expect(error.phase, "block_parse")
            }
        }
    }

    @TestCase
    func enforcesIndentedCodeLiteralLimitIncrementally(): Unit {
        let exact = MarkdownEngine.builder().limits(indentedLiteralLimits(5)).build()
        let multiline = exact.parse("    ab\n    cd\n")
        let multilineNode = multiline.document.children()[0]
        let multilineCode = multilineNode.asCodeBlock().getOrThrow()
        @Expect(multilineCode.literal, "ab\ncd")
        @Expect(multilineNode.span, Some(SourceSpan(0, 14)))

        let tabIndented = exact.parse("\tab\n\tcd")
        let tabNode = tabIndented.document.children()[0]
        let tabCode = tabNode.asCodeBlock().getOrThrow()
        @Expect(tabCode.literal, "ab\ncd")
        @Expect(tabNode.span, Some(SourceSpan(0, 7)))

        let trimmedNode = MarkdownEngine
            .builder()
            .limits(indentedLiteralLimits(2))
            .build()
            .parse("    \n    ab\n\n    \n")
            .document
            .children()[0]
        let trimmed = trimmedNode.asCodeBlock().getOrThrow()
        @Expect(trimmed.literal, "ab")
        @Expect(trimmedNode.span, Some(SourceSpan(5, 18)))

        try {
            MarkdownEngine.builder().limits(indentedLiteralLimits(4)).build().parse("    ab\n    cd\n")
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "literal_bytes")
            @Expect(error.configuredLimit, 4)
            @Expect(error.observedValue, 5)
            @Expect(error.phase, "block_parse")
        }

        try {
            MarkdownEngine.builder().limits(indentedLiteralLimits(1)).build().parse("    ab")
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "literal_bytes")
            @Expect(error.configuredLimit, 1)
            @Expect(error.observedValue, 2)
            @Expect(error.phase, "block_parse")
        }
    }

    @TestCase
    func distinguishesCommonMarkFromGfmExtensions(): Unit {
        let source = "~~gone~~\n\n| a |\n| --- |\n| b |"
        let common = MarkdownEngine.builder().build().parse(source)
        let gfm = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build().parse(source)
        @Expect(common.document.children().size, 2)
        @Expect(gfm.document.children().size, 2)
        let commonParagraph = common.document.children()[0]
        match (commonParagraph.kind) {
            case NodeKind.Paragraph => match (commonParagraph.children()[0].kind) {
                case NodeKind.Text => @Expect(commonParagraph.children()[0].asText().getOrThrow().value, "~~gone~~")
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let gfmParagraph = gfm.document.children()[0]
        match (gfmParagraph.kind) {
            case NodeKind.Paragraph => match (gfmParagraph.children()[0].kind) {
                case NodeKind.Strikethrough => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        match (gfm.document.children()[1].kind) {
            case NodeKind.Table => @Expect(true)
            case _ => @Expect(false)
        }
    }

    @TestCase
    func fatalParseFailureHasNoSuccessDocument(): Unit {
        let limits = ParseLimits(1, 4, 8, 16, 4, 4, 4, 4, 8, 4, 4)
        let engine = MarkdownEngine.builder().limits(limits).build()
        @ExpectThrows[LimitExceededException](engine.parse("xx"))
        match (engine.tryParse("xx")) {
            case ParseOutcome.Failure(error) =>
                @Expect(error.phase, "input")
                @Expect(if (let MarkdownErrorCode.LimitExceeded <- error.code) { true } else { false })
            case ParseOutcome.Success(_) => @Expect(false)
        }
        match (engine.tryParse("")) {
            case ParseOutcome.Success(result) =>
                @Expect(result.document.children().size, 0)
                @Expect(result.document.span, Some(SourceSpan(0, 0)))
                @Expect(engine.createArtifact(result).document.nodeId, result.document.nodeId)
            case ParseOutcome.Failure(_) => @Expect(false)
        }
        let cancellation = CancellationSource()
        cancellation.cancel()
        match (engine.tryParse("x", cancellation: cancellation.token)) {
            case ParseOutcome.Failure(error) =>
                @Expect(error.phase, "input")
                @Expect(if (let MarkdownErrorCode.Cancelled <- error.code) { true } else { false })
            case ParseOutcome.Success(_) => @Expect(false)
        }
    }

    private func indentedLiteralLimits(maximumLiteralBytes: Int64): ParseLimits {
        ParseLimits(1024, 1024, 16, 64, 16, 16, 1024, maximumLiteralBytes, 4096, 1024, 1024)
    }
}
