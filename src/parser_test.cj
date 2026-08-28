package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParserBehaviorTest {
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
        @Expect(node.nodeId, NodeId(1))
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
    }

    @TestCase
    func commonMarkPipeParagraphFastPathPreservesFullAst(): Unit {
        let result = Markdown.parse("| a |\n| b |\n")
        @Expect(result.document.nodeCount, 5)
        let paragraph = result.document.children()[0]
        @Expect(paragraph.nodeId, NodeId(4))
        @Expect(paragraph.span, Some(SourceSpan(0, 11)))
        @Expect(paragraph.children().size, 3)
        @Expect(paragraph.children()[0].nodeId, NodeId(1))
        @Expect(paragraph.children()[0].span, Some(SourceSpan(0, 5)))
        @Expect(paragraph.children()[0].asText().getOrThrow().value, "| a |")
        match (paragraph.children()[1].kind) {
            case NodeKind.SoftBreak => @Expect(paragraph.children()[1].span, Some(SourceSpan(5, 6)))
            case _ => @Expect(false)
        }
        @Expect(paragraph.children()[2].nodeId, NodeId(3))
        @Expect(paragraph.children()[2].span, Some(SourceSpan(6, 11)))
        @Expect(paragraph.children()[2].asText().getOrThrow().value, "| b |")
        AstInvariantValidator().validate(result.document)
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(result.document), "<p>| a |\n| b |</p>\n")
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
    func partialResultsRequireExplicitEntryAndCannotBecomeArtifacts(): Unit {
        let limits = ParseLimits(1, 4, 8, 16, 4, 4, 4, 4, 8, 4, 4)
        let engine = MarkdownEngine.builder().limits(limits).build()
        try {
            engine.parse("xx");
            @Expect(false)
        } catch (_: LimitExceededException) {
            @Expect(true)
        }

        let partial = engine.parsePartial("xx")
        @Expect(partial.isComplete, false)
        @Expect(partial.unfinishedPhase, "input")
        @Expect(partial.errors.size, 1)
        @Expect(partial.document.children().size, 0)
        try {
            engine.createArtifact(partial);
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InvalidArtifact => @Expect(true)
                case _ => @Expect(false)
            }
        }
    }
}
