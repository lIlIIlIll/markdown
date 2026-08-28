package markdown

import std.unittest.*
import std.unittest.testmacro.*

class AlwaysFailSink <: TextSink {
    public func write(_: String): SinkWriteResult {
        SinkWriteResult.Failure(SinkError("write failed"))
    }
}

class PrefixSanitizer <: HtmlSanitizerPort {
    public func sanitize(_: String): String {
        "<span>sanitized</span>"
    }
}

class FailingSanitizer <: HtmlSanitizerPort {
    public func sanitize(_: String): String {
        throw IllegalStateException("sanitize failed")
    }
}

class PauseOnceSink <: AsyncTextSink {
    private var paused = false
    private let out = StringBuilder()
    public func write(slice: String): AsyncSinkWriteResult {
        if (!paused) {
            paused = true
            return AsyncSinkWriteResult.Pause
        }
        out.append(slice)
        AsyncSinkWriteResult.Continue
    }
    public func content(): String {
        out.toString()
    }
}

class TrustedFallback <: ExtensionRendererFallback {
    public prop extensionId: String {
        get() {
            "fallback"
        }
    }
    public func renderHtml(_: NodeRef): TrustedHtml {
        unsafe { TrustedHtml.fromString("<span>trusted fallback</span>") }
    }
}

@Test
class RendererBehaviorTest {
    @TestCase
    func arenaRendererIsDeterministicForCoreAndGfmTrees(): Unit {
        let commonSource = "# H\n\n> quoted *em* and **strong**\n\n1. one\n2. `two`\n\n---\n\n" +
            "[link](https://example.com \"t\") ![alt *text*](img.png)  \nnext\n\n<div>x</div>\n"
        let common = MarkdownEngine.builder().build().parse(commonSource)
        let safe = HtmlRenderer()
        @Expect(safe.render(common.ast), safe.render(common.document))

        let gfmSource = "| a | b |\n| :- | -: |\n| ~~x~~ | y |\n\n- [x] done\n"
        let gfm = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build().parse(gfmSource)
        let compatible = HtmlRenderer(options: HtmlOptions.gfmCompatible())
        @Expect(compatible.render(gfm.ast), compatible.render(gfm.document))
    }

    @TestCase
    func safeHtmlEscapesTextRawHtmlAndDangerousUris(): Unit {
        let source = "<script>alert(1)</script>\n\n[x](JaVa\tScRiPt:alert(1)) & <b>"
        let document = MarkdownEngine.builder().build().parse(source).document
        let html = HtmlRenderer().render(document)
        @Expect(html.contains("&lt;script&gt;"), true)
        @Expect(html.contains("javascript"), false)
        @Expect(html.contains(" href="), false)
        @Expect(html.contains("&amp;"), true)
        @Expect(html.contains("&lt;b&gt;"), true)
    }

    @TestCase
    func specHtmlPassesRawHtmlAndSafeTaskIsDisabled(): Unit {
        let raw = MarkdownEngine.builder().build().parse("<em>x</em>").document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(raw), "<p><em>x</em></p>\n")

        let task = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build().parse("- [x] done").document
        let safe = HtmlRenderer().render(task)
        @Expect(safe.contains("type=\"checkbox\""), true)
        @Expect(safe.contains("disabled=\"\""), true)
        @Expect(safe.contains("checked=\"\""), true)
    }

    @TestCase
    func safeImagesBlockRemoteAndDataButAllowRelative(): Unit {
        let document = MarkdownEngine
            .builder()
            .build()
            .parse("![remote](https://example.com/a.png) ![data](data:image/png;base64,AA) ![local](img/a.png)")
            .document
        let html = HtmlRenderer().render(document)
        @Expect(html.contains("src=\"https://"), false)
        @Expect(html.contains("src=\"data:"), false)
        @Expect(html.contains("src=\"img/a.png\""), true)
        let controlled = Markdown.parse("[x](https://example.com \"a\tb\")").document
        let controlledHtml = HtmlRenderer().render(controlled)
        @Expect(controlledHtml.contains("title=\"a\tb\""), false)
        @Expect(controlledHtml.contains("a&#xfffd;b"), true)
    }

    @TestCase
    func safeDataImageMimeAndBlankTargetPoliciesAreExact(): Unit {
        let dataOptions = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
            ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/png"]))
        let dataDocument = Markdown
            .parse("![ok](data:image/PNG;charset=utf-8;base64,AA) ![bad](data:image/pngx;base64,AA)")
            .document
        let dataHtml = HtmlRenderer(options: dataOptions).render(dataDocument)
        @Expect(dataHtml.contains("src=\"data:image/PNG;charset=utf-8;base64,AA\""), true)
        @Expect(dataHtml.contains("src=\"data:image/pngx;base64,AA\""), false)

        let blankOptions = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
            ImageUriPolicy.safe(), externalLinkRel: "nofollow NOOPENER", externalLinkTarget: "_BLANK")
        let blankHtml = HtmlRenderer(options: blankOptions).render(Markdown.parse("[x](https://example.com)").document)
        @Expect(blankHtml.contains("rel=\"nofollow NOOPENER noreferrer\""), true)
        @Expect(blankHtml.contains("noopener noopener"), false)
        @Expect(blankHtml.contains("target=\"_BLANK\""), true)

        let specOptions = HtmlOptions(HtmlPolicy.specCompatible(), RawHtmlPolicyKind.PassThrough, LinkUriPolicy.safe(),
            ImageUriPolicy.safe(), externalLinkTarget: "_blank")
        let specHtml = HtmlRenderer(options: specOptions).render(Markdown.parse("[x](https://example.com)").document)
        @Expect(specHtml.contains(" rel="), false)
    }

    @TestCase
    func outputBudgetCancellationAndSinkErrorsPropagate(): Unit {
        let document = MarkdownEngine.builder().build().parse("hello").document
        try {
            HtmlRenderer().render(document, budget: OperationBudget(100, 100, 100, 100, 100, 1))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "output_bytes")
                case _ => @Expect(false)
            }
        }

        try {
            HtmlRenderer().renderTo(document, AlwaysFailSink())
            @Expect(false)
        } catch (error: SinkFailureException) {
            @Expect(error.cause.message, "write failed")
        }
    }

    @TestCase
    func plainTextIsDeterministicAndContainsNoAnsi(): Unit {
        let document = MarkdownEngine
            .builder()
            .build()
            .parse("# Title\n\nA [link](https://example.com) and `code`.")
            .document
        let text = PlainTextRenderer(options: PlainTextOptions(includeLinkDestinations: true)).render(document)
        @Expect(text, "Title\n\nA link (https://example.com) and code.")
        @Expect(text.contains("\u{001b}"), false)
    }

    @TestCase
    func sanitizerAdapterFailsClosedAndAsyncSinkResumesWithoutDuplication(): Unit {
        let document = Markdown.parse("<script>x</script>").document
        let options = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Sanitize, LinkUriPolicy.safe(),
            ImageUriPolicy.safe())
        let sanitized = HtmlRenderer(options: options, sanitizer: Some(PrefixSanitizer())).render(document)
        @Expect(sanitized.contains("<script>"), false)
        @Expect(sanitized.contains("<span>sanitized</span>"), true)
        try {
            HtmlRenderer(options: options, sanitizer: Some(FailingSanitizer())).render(document)
            @Expect(false)
        } catch (_: IllegalStateException) {
            @Expect(true)
        }

        let normal = HtmlRenderer().render(Markdown.parse("async output").document)
        let session = AsyncHtmlRenderSession(HtmlRenderer(), Markdown.parse("async output").document, chunkBytes: 3)
        let sink = PauseOnceSink()
        match (session.resume(sink)) {
            case AsyncRenderState.Paused => @Expect(true)
            case _ => @Expect(false)
        }
        match (session.resume(sink)) {
            case AsyncRenderState.Complete => @Expect(true)
            case _ => @Expect(false)
        }
        @Expect(sink.content(), normal)
        @Expect(session.bytesWritten(), normal.size)
    }

    @TestCase
    func explicitlyNamedBufferedAsyncSessionPreservesBackpressure(): Unit {
        let session = BufferedAsyncHtmlOutputSession(HtmlRenderer(), Markdown.parse("buffered output").document,
            chunkBytes: 4)
        let sink = PauseOnceSink()
        match (session.resume(sink)) {
            case AsyncRenderState.Paused => @Expect(true)
            case _ => @Expect(false)
        }
        match (session.resume(sink)) {
            case AsyncRenderState.Complete => @Expect(true)
            case _ => @Expect(false)
        }
        @Expect(session.bytesWritten(), "<p>buffered output</p>\n".size)
    }

    @TestCase
    func rendererFingerprintIsDeterministicAndPolicySensitive(): Unit {
        let safe1 = HtmlRenderer().fingerprint()
        let safe2 = HtmlRenderer().fingerprint()
        let spec = HtmlRenderer(options: HtmlOptions.specCompatible()).fingerprint()
        @Expect(safe1, safe2)
        @Expect(safe1 == spec, false)
        @Expect(safe1.size, 64)
        let splitLeft = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy.safe(), externalLinkRel: "a|target=b", externalLinkTarget: "c"))
        let splitRight = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy.safe(), externalLinkRel: "a", externalLinkTarget: "b|target=c"))
        @Expect(splitLeft.fingerprint() == splitRight.fingerprint(), false)
        try {
            HtmlRenderer(
                extensionRules: [RendererRule("bad", "node", "span",
                    attributes: [RendererAttributeSpec("onload", RendererAttributeKind.Text,
                        RendererAttributeSource.FixedValue("alert(1)"))])])
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }
    }

    @TestCase
    func extensionMissingRendererPoliciesAreExplicitAndBounded(): Unit {
        let childrenEngine = missingRendererEngine("children", MissingRendererPolicy.RenderChildren,
            BlockContentMode.Markdown)
        @Expect(childrenEngine.htmlRenderer().render(childrenEngine.parse(":::box\n**body**\n:::").document),
            "<p><strong>body</strong></p>\n")

        let literalEngine = missingRendererEngine("literal", MissingRendererPolicy.RenderLiteral,
            BlockContentMode.Literal)
        @Expect(literalEngine.htmlRenderer().render(literalEngine.parse(":::box\n<b>\n:::").document),
            "&lt;b&gt;")

        let dropEngine = missingRendererEngine("drop", MissingRendererPolicy.Drop, BlockContentMode.Markdown)
        @Expect(dropEngine.htmlRenderer().render(dropEngine.parse(":::box\nbody\n:::").document), "")

        let fallbackEngine = missingRendererEngine("fallback", MissingRendererPolicy.CustomFallback,
            BlockContentMode.Markdown)
        @Expect(fallbackEngine.htmlRenderer(fallbacks: [TrustedFallback()])
            .render(fallbackEngine.parse(":::box\nbody\n:::").document),
            "<span>trusted fallback</span>")

        let errorEngine = missingRendererEngine("error", MissingRendererPolicy.Error, BlockContentMode.Markdown)
        try {
            errorEngine.htmlRenderer().render(errorEngine.parse(":::box\nbody\n:::").document);
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.UnsupportedNode => @Expect(true)
                case _ => @Expect(false)
            }
            @Expect(error.span.isSome(), true)
        }
    }
}

private func missingRendererEngine(id: String, policy: MissingRendererPolicy, content: BlockContentMode): MarkdownEngine {
    let dialect = MarkdownDialect
        .define(id, "1")
        .enable(ExtensionManifest(id, "1.0.0", "1", missingRendererPolicy: policy))
        .block(BlockSyntax.define(id, "box").opener(":::").closer(":::").content(content))
        .build()
    MarkdownEngine.builder().dialect(dialect).build()
}
