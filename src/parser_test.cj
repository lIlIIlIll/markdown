package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParserBehaviorTest {
    @TestCase
    func validatesMultilineQuotedRawHtmlTag(): Unit {
        let quoted = Markdown.parse("before <a foo=\"bar\" bam='baz <em>\"</em>'\n_boolean zoop:33=zoop:33 /> after")
        match (quoted.document.children()[0]) {
            case paragraph: Paragraph => match (paragraph.children()[1]) {
                case _: HtmlInline => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let invalid = Markdown.parse("<bar/ >")
        match (invalid.document.children()[0]) {
            case paragraph: Paragraph => match (paragraph.children()[0]) {
                case text: Text => @Expect(text.value, "<bar/ >")
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let html = Markdown.parse("<div>\nx\n</div>").document.children()[0]
        match (html) {
            case block: HtmlBlock => match (block.literalStorage) {
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
        match (result.document.children()[0]) {
            case heading: Heading =>
                @Expect(heading.level, 1)
                @Expect(heading.span, Some(SourceSpan(0, 8)))
                match (heading.children()[0]) {
                    case text: Text =>
                        @Expect(text.value, "标题")
                        match (text.valueStorage) {
                            case LiteralStorage.Copy(_) => @Expect(true)
                            case _ => @Expect(false)
                        }
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        match (result.document.children()[1]) {
            case paragraph: Paragraph =>
                @Expect(paragraph.children().size, 5)
                match (paragraph.children()[1]) {
                    case strong: Strong => @Expect(strong.children().size, 1)
                    case _ => @Expect(false)
                }
                match (paragraph.children()[3]) {
                    case link: Link =>
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
        match (result.document.children()[1]) {
            case list: List =>
                @Expect(list.children().size, 2)
                match (list.children()[0]) {
                    case item: ListItem => match (item.taskState) {
                        case TaskState.Checked => @Expect(item.markerSpan.isSome(), true)
                        case _ => @Expect(false)
                    }
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        match (result.document.children()[2]) {
            case code: CodeBlock =>
                @Expect(code.literal, "main()\n")
                @Expect(code.language, "cj")
                @Expect(code.openingFenceSpan.isSome(), true)
                @Expect(code.closingFenceSpan.isSome(), true)
                match (code.literalStorage) {
                    case LiteralStorage.Slice(_) => @Expect(true)
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
        match (result.document.children()[3]) {
            case table: Table =>
                @Expect(table.children().size, 2)
                @Expect(table.alignments.size, 2)
            case _ => @Expect(false)
        }
    }

    @TestCase
    func preservesMalformedInlineAsTextAndHonorsResourceControls(): Unit {
        let input = "**unfinished [link `code"
        let result = MarkdownEngine.builder().build().parse(input)
        match (result.document.children()[0]) {
            case paragraph: Paragraph =>
                @Expect(paragraph.children().size, 1)
                match (paragraph.children()[0]) {
                    case text: Text => @Expect(text.value, input)
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
    func distinguishesCommonMarkFromGfmExtensions(): Unit {
        let source = "~~gone~~\n\n| a |\n| --- |\n| b |"
        let common = MarkdownEngine.builder().build().parse(source)
        let gfm = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build().parse(source)
        @Expect(common.document.children().size, 2)
        @Expect(gfm.document.children().size, 2)
        match (common.document.children()[0]) {
            case paragraph: Paragraph => match (paragraph.children()[0]) {
                case text: Text => @Expect(text.value, "~~gone~~")
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        match (gfm.document.children()[0]) {
            case paragraph: Paragraph => match (paragraph.children()[0]) {
                case _: Strikethrough => @Expect(true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        match (gfm.document.children()[1]) {
            case _: Table => @Expect(true)
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
