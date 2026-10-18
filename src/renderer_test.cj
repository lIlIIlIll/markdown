package markdown

import std.unittest.*
import std.unittest.testmacro.*

class AlwaysFailSink <: TextSink {
    public func write(_: String): SinkWriteResult {
        SinkWriteResult.Failure(SinkError("write failed"))
    }
}

class RecordingSink <: TextSink {
    public var writes: Int64 = 0
    public var bytes: Int64 = 0
    public func write(slice: String): SinkWriteResult {
        writes++
        bytes += slice.size
        SinkWriteResult.Success
    }
}

class CancelOnFirstWriteSink <: TextSink {
    private let cancellation: CancellationSource
    public var writes: Int64 = 0
    public var bytes: Int64 = 0

    public init(cancellation: CancellationSource) {
        this.cancellation = cancellation
    }

    public func write(slice: String): SinkWriteResult {
        writes++
        bytes += slice.size
        if (writes == 1) {
            cancellation.cancel()
        }
        SinkWriteResult.Success
    }
}

class PrefixSanitizer <: HtmlSanitizerPort {
    public prop identity: String {
        get() {
            "prefix-sanitizer-v1"
        }
    }
    public func sanitize(_: String): String {
        "<span>sanitized</span>"
    }
}

class FailingSanitizer <: HtmlSanitizerPort {
    public prop identity: String {
        get() {
            "failing-sanitizer-v1"
        }
    }
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
    public prop implementationVersion: String {
        get() {
            "1"
        }
    }
    public func renderHtml(_: NodeRef): TrustedHtml {
        unsafe { TrustedHtml.fromString("<span>trusted fallback</span>") }
    }
}

class MarkRawHtmlHandler <: RawHtmlHandlerPort {
    public prop identity: String {
        get() {
            "mark-raw-v1"
        }
    }
    public func renderRawHtml(literal: String, block: Bool): TrustedHtml {
        unsafe { TrustedHtml.fromString("<mark data-block=\"${block}\">${literal.size}</mark>") }
    }
}

class FixedExternalLinkRewriter <: ExternalLinkRewriterPort {
    private let destination: String
    private let id: String
    public init(destination: String, id!: String = "fixed-link-v1") {
        this.destination = destination
        this.id = id
    }
    public prop identity: String {
        get() {
            id
        }
    }
    public func rewriteExternalLink(_: String): String {
        destination
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
        let compatible = HtmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() })
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
        @Expect(HtmlRenderer(options: unsafe { HtmlOptions.specCompatible() }).render(raw), "<p><em>x</em></p>\n")

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

        let specOptions = unsafe {
            HtmlOptions.passThrough(HtmlPolicy.specCompatible(), LinkUriPolicy.safe(), ImageUriPolicy.safe(),
                externalLinkTarget: "_blank")
        }
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
    func cancellationChecksEmptyEntryAndStopsAfterMidRenderCancellation(): Unit {
        let emptyCancellation = CancellationSource()
        emptyCancellation.cancel()
        let emptySink = RecordingSink()
        try {
            HtmlRenderer().renderTo(Markdown.parse("").document, emptySink, cancellation: emptyCancellation.token)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled => @Expect(error.phase, "render")
                case _ => @Expect(false)
            }
        }
        @Expect(emptySink.writes, 0)

        let text = StringBuilder()
        for (_ in 0..262144) {
            text.append("a")
        }
        let document = Markdown.parse(text.toString()).document
        let cancellation = CancellationSource()
        let sink = CancelOnFirstWriteSink(cancellation)
        try {
            HtmlRenderer().renderTo(document, sink, cancellation: cancellation.token)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled => @Expect(error.phase, "render")
                case _ => @Expect(false)
            }
        }
        // The paragraph opener was already handed to the sink when the sink
        // cancelled. No part of the huge Text node may be written afterward.
        @Expect(sink.writes, 1)
        @Expect(sink.bytes, 3)
    }

    @TestCase
    func escapeHeavyTextChecksBudgetBeforeAnyEscapedSinkWrite(): Unit {
        let document = Markdown.parse("&&&&&&&&").document
        let sink = RecordingSink()
        try {
            HtmlRenderer().renderTo(document, sink, budget: OperationBudget(100, 100, 100, 100, 100, 4))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "output_bytes")
                case _ => @Expect(false)
            }
        }
        // The generated paragraph opener fits; the first escaped replacement
        // does not, so no oversized replacement reaches the sink.
        @Expect(sink.bytes, 3)
        @Expect(sink.writes, 1)
    }

    @TestCase
    func hugeOrdinaryRangesAreRejectedBeforeTheyReachTheSink(): Unit {
        let value = repeatedOrdinaryText(65536)
        let document = Markdown.parse(value).document

        let fixedSink = RecordingSink()
        try {
            HtmlRenderer(maximumOutputBytes: Some(4)).renderTo(document, fixedSink)
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "output_bytes")
            @Expect(error.phase, "render")
        }
        @Expect(fixedSink.bytes, 3)
        @Expect(fixedSink.writes, 1)

        let budgetSink = RecordingSink()
        try {
            HtmlRenderer().renderTo(document, budgetSink, budget: OperationBudget(100, 100, 100, 100, 100, 4))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "output_bytes")
                case _ => @Expect(false)
            }
        }
        @Expect(budgetSink.bytes, 3)
        @Expect(budgetSink.writes, 1)
    }

    @TestCase
    func gfmTagFilterChecksBudgetBeforeFilteredOutputIsMaterialized(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfmModernV1())
            .build()
            .parse("<script>x</script>")
            .document
        let sink = RecordingSink()
        try {
            HtmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() }).renderTo(document, sink,
                budget: OperationBudget(100, 100, 100, 100, 100, 4))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "output_bytes")
                case _ => @Expect(false)
            }
        }
        @Expect(sink.bytes, 4)
        @Expect(sink.writes, 1)
    }

    @TestCase
    func gfmTagFilterRejectsOversizedOutputWithoutMaterializingLongTagName(): Unit {
        let name = StringBuilder()
        for (_ in 0..65536) {
            name.append("a")
        }
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfmModernV1())
            .build()
            .parse("<${name.toString()}>\n")
            .document
        let sink = RecordingSink()
        try {
            HtmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() }, maximumOutputBytes: Some(1)).renderTo(
                document, sink)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.LimitExceeded => @Expect(error.phase, "render")
                case _ => @Expect(false)
            }
        }
        @Expect(sink.bytes, 0)
        @Expect(sink.writes, 0)
    }

    @TestCase
    func gfmTagFilterRequiresTheSpecifiedPostNameBoundaryForBlockAndInlineHtml(): Unit {
        let literal = "<script-x><script1><script_><script><SCRIPT><script ><script/><script"
        let expectedLiteral = "<script-x><script1><script_>&lt;script>&lt;SCRIPT>&lt;script >&lt;script/>&lt;script"
        let renderer = HtmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() })
        @Expect(renderer.render(rawHtmlDocument(literal, true)), expectedLiteral + "\n")
        @Expect(renderer.render(rawHtmlDocument(literal, false)), "<p>" + expectedLiteral + "</p>\n")
    }

    @TestCase
    func customRawHtmlAndExternalLinkRewriteAreExplicitAndFailClosed(): Unit {
        let customOptions = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.CustomHandler, LinkUriPolicy.safe(),
            ImageUriPolicy.safe())
        let raw = Markdown.parse("<div>x</div>\n").document
        try {
            HtmlRenderer(options: customOptions).render(raw)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.RenderFailure => @Expect(error.phase, "render")
                case _ => @Expect(false)
            }
        }
        @Expect(HtmlRenderer(options: customOptions, rawHtmlHandler: Some(MarkRawHtmlHandler())).render(raw),
            "<mark data-block=\"true\">12</mark>\n")

        let rewritten = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
            ImageUriPolicy.safe(), rewriteExternalLinks: Some(FixedExternalLinkRewriter("https://new.example/x")),
            externalLinkRel: "nofollow", externalLinkTarget: "_blank")
        let rewrittenHtml = HtmlRenderer(options: rewritten).render(
            Markdown.parse("[x](https://old.example/y) [r](/relative)").document)
        @Expect(rewrittenHtml.contains("href=\"https://new.example/x\""), true)
        @Expect(rewrittenHtml.contains("href=\"/relative\""), true)
        @Expect(rewrittenHtml.contains("rel=\"nofollow noopener noreferrer\""), true)

        let rejected = HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
            ImageUriPolicy.safe(), rewriteExternalLinks: Some(FixedExternalLinkRewriter("javascript:alert(1)")))
        @Expect(HtmlRenderer(options: rejected).render(Markdown.parse("[x](https://old.example)").document)
            .contains(" href="), false)

        try {
            HtmlOptions(HtmlPolicy.specCompatible(), RawHtmlPolicyKind.PassThrough, LinkUriPolicy.safe(),
                ImageUriPolicy.safe())
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }
    }

    @TestCase
    func externalLinkRewriteIsRevalidatedAcrossSafeSpecAndGfmPolicies(): Unit {
        let source = Markdown.parse("[x](https://old.example/path)").document
        let dangerous: ?ExternalLinkRewriterPort = Some(FixedExternalLinkRewriter("javascript:alert(1)"))
        let dangerousOptions = [
            HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(), ImageUriPolicy.safe(),
                rewriteExternalLinks: dangerous),
            unsafe {
                HtmlOptions.passThrough(HtmlPolicy.specCompatible(), LinkUriPolicy(true, true, true, true),
                    ImageUriPolicy(true, true, true), rewriteExternalLinks: dangerous)
            },
            unsafe {
                HtmlOptions.passThrough(HtmlPolicy.gfmCompatible(), LinkUriPolicy(true, true, true, true),
                    ImageUriPolicy(true, true, true), rewriteExternalLinks: dangerous)
            }
        ]
        for (options in dangerousOptions) {
            let html = HtmlRenderer(options: options).render(source)
            @Expect(html.contains(" href="), false)
            @Expect(html.contains("javascript"), false)
        }

        let legitimate: ?ExternalLinkRewriterPort = Some(FixedExternalLinkRewriter("https://new.example/safe"))
        let legitimateOptions = [
            HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(), ImageUriPolicy.safe(),
                rewriteExternalLinks: legitimate),
            unsafe {
                HtmlOptions.passThrough(HtmlPolicy.specCompatible(), LinkUriPolicy(true, true, true, true),
                    ImageUriPolicy(true, true, true), rewriteExternalLinks: legitimate)
            },
            unsafe {
                HtmlOptions.passThrough(HtmlPolicy.gfmCompatible(), LinkUriPolicy(true, true, true, true),
                    ImageUriPolicy(true, true, true), rewriteExternalLinks: legitimate)
            }
        ]
        for (options in legitimateOptions) {
            @Expect(HtmlRenderer(options: options).render(source).contains("href=\"https://new.example/safe\""), true)
        }

        let legacy = Markdown.parse("[x](javascript:alert(1))").document
        @Expect(HtmlRenderer(options: unsafe { HtmlOptions.specCompatible() }).render(legacy).contains(" href="), true)
        @Expect(HtmlRenderer(options: unsafe { HtmlOptions.gfmCompatible() }).render(legacy).contains(" href="), true)
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
    func sanitizerAdapterFailsClosed(): Unit {
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
    }

    @TestCase
    func explicitlyNamedBufferedAsyncSessionPreservesBackpressure(): Unit {
        let normal = HtmlRenderer().render(Markdown.parse("buffered output").document)
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
        @Expect(sink.content(), normal)
        @Expect(session.bytesWritten(), normal.size)
    }

    @TestCase
    func rendererFingerprintIsDeterministicAndPolicySensitive(): Unit {
        let safe1 = HtmlRenderer().fingerprint()
        let safe2 = HtmlRenderer().fingerprint()
        let spec = HtmlRenderer(options: unsafe { HtmlOptions.specCompatible() }).fingerprint()
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
        let png = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/png"]))).fingerprint()
        let jpeg = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/jpeg"]))).fingerprint()
        let normalizedPng = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["IMAGE/JPEG", "image/png", "image/jpeg"])))
            .fingerprint()
        let reorderedPng = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy(true, false, true, allowedDataMimeTypes: ["image/png", "image/jpeg"]))).fingerprint()
        @Expect(png == jpeg, false)
        @Expect(normalizedPng, reorderedPng)
        let inactiveLeft = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy(true, false, false, allowedDataMimeTypes: ["image/png"]))).fingerprint()
        let inactiveRight = HtmlRenderer(
            options: HtmlOptions(HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(),
                ImageUriPolicy(true, false, false, allowedDataMimeTypes: ["image/jpeg"]))).fingerprint()
        @Expect(inactiveLeft, inactiveRight)
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
    func rendererFingerprintIncludesFixedOutputLimit(): Unit {
        let unlimited = HtmlRenderer().fingerprint()
        let limit100a = HtmlRenderer(maximumOutputBytes: Some(100)).fingerprint()
        let limit100b = HtmlRenderer(maximumOutputBytes: Some(100)).fingerprint()
        let limit101 = HtmlRenderer(maximumOutputBytes: Some(101)).fingerprint()
        @Expect(unlimited == limit100a, false)
        @Expect(limit100a, limit100b)
        @Expect(limit100a == limit101, false)
    }

    @TestCase
    func rendererFingerprintCanonicalizesManifestOrderAndIncludesFallbackPolicy(): Unit {
        let alpha = ExtensionManifest("alpha", "1.0.0", "a1",
            missingRendererPolicy: MissingRendererPolicy.RenderChildren)
        let beta = ExtensionManifest("beta", "2.0.0", "b1", missingRendererPolicy: MissingRendererPolicy.Drop)
        let forward = HtmlRenderer(extensionManifests: [alpha, beta]).fingerprint()
        let reverse = HtmlRenderer(extensionManifests: [beta, alpha]).fingerprint()
        let changedPolicy = HtmlRenderer(
            extensionManifests: [
                ExtensionManifest("alpha", "1.0.0", "a1", missingRendererPolicy: MissingRendererPolicy.RenderLiteral),
                beta
            ]
        ).fingerprint()
        @Expect(forward, reverse)
        @Expect(forward == changedPolicy, false)
    }

    @TestCase
    func duplicateManifestIdsFailBeforeFingerprintOrRuntimeSelection(): Unit {
        let renderChildren = ExtensionManifest("duplicate", "1.0.0", "children",
            missingRendererPolicy: MissingRendererPolicy.RenderChildren)
        let drop = ExtensionManifest("duplicate", "1.0.0", "drop", missingRendererPolicy: MissingRendererPolicy.Drop)
        try {
            HtmlRenderer(extensionManifests: [renderChildren, drop]).fingerprint()
            @Expect(false)
        } catch (error: IllegalArgumentException) {
            @Expect(error.message.contains("duplicate extension id"), true)
        }
        try {
            HtmlRenderer(extensionManifests: [drop, renderChildren]).render(Markdown.parse("body").document)
            @Expect(false)
        } catch (error: IllegalArgumentException) {
            @Expect(error.message.contains("duplicate extension id"), true)
        }
    }

    @TestCase
    func rendererFingerprintPreservesSemanticRuleOrder(): Unit {
        let first = RendererRule("ordered", "first", "em")
        let second = RendererRule("ordered", "second", "strong")
        let forward = HtmlRenderer(extensionRules: [first, second]).fingerprint()
        let reverse = HtmlRenderer(extensionRules: [second, first]).fingerprint()
        @Expect(forward == reverse, false)
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

private func rawHtmlDocument(literal: String, block: Bool): Document {
    let builder = AstArenaBuilder()
    let html = if (block) {
        builder.append(NodeKind.HtmlBlock, NodeCategory.Block, Some(SourceSpan(0, literal.size)), NodeOriginKind.Parsed,
            [], payload: ArenaNodePayload.HtmlBlockValue(LiteralStorage.Copy(literal), 7))
    } else {
        builder.append(NodeKind.HtmlInline, NodeCategory.Inline, Some(SourceSpan(0, literal.size)),
            NodeOriginKind.Parsed, [], payload: ArenaNodePayload.HtmlInlineValue(literal))
    }
    let child = if (block) {
        html
    } else {
        builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, literal.size)), NodeOriginKind.Parsed,
            [html])
    }
    let _ = builder.append(NodeKind.DocumentNode, NodeCategory.Block, Some(SourceSpan(0, literal.size)),
        NodeOriginKind.Parsed, [child])
    builder.freeze()
}

private func repeatedOrdinaryText(size: Int64): String {
    let out = StringBuilder()
    for (_ in 0..size) {
        out.append("a")
    }
    out.toString()
}
