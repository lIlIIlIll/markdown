package markdown

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private class LifecycleTransformFixture <: ExtensionAstTransform {
    private let body: (Document, SourceBuffer, ParseLimits, OperationBudget, CancellationToken) -> Document
    public init(body: (Document, SourceBuffer, ParseLimits, OperationBudget, CancellationToken) -> Document) {
        this.body = body
    }
    public prop extensionId: String {
        get() {
            "lifecycle"
        }
    }
    public prop transformId: String {
        get() {
            "rewrite"
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    public func transform(document: Document, source: SourceBuffer, limits: ParseLimits, budget: OperationBudget,
        cancellation: CancellationToken): Document {
        body(document, source, limits, budget, cancellation)
    }
}

private class LifecycleAnalysisFixture <: ExtensionDocumentAnalysis {
    private let body: (Document, SourceBuffer, ParseLimits, OperationBudget, CancellationToken) -> Array<Diagnostic>
    private let idValue: String
    private let versionValue: String
    private let priorityValue: Int64
    private let deterministicValue: Bool
    public init(body: (Document, SourceBuffer, ParseLimits, OperationBudget, CancellationToken) -> Array<Diagnostic>,
        id!: String = "observe", version!: String = "1", priority!: Int64 = 100, deterministic!: Bool = true) {
        this.body = body
        idValue = id
        versionValue = version
        priorityValue = priority
        deterministicValue = deterministic
    }
    public prop extensionId: String {
        get() {
            "lifecycle"
        }
    }
    public prop analysisId: String {
        get() {
            idValue
        }
    }
    public prop version: String {
        get() {
            versionValue
        }
    }
    public prop priority: Int64 {
        get() {
            priorityValue
        }
    }
    public prop deterministic: Bool {
        get() {
            deterministicValue
        }
    }
    public func analyze(document: Document, source: SourceBuffer, limits: ParseLimits, budget: OperationBudget,
        cancellation: CancellationToken): Array<Diagnostic> {
        body(document, source, limits, budget, cancellation)
    }
}

private func lifecycleEngine(transform!: ?ExtensionAstTransform = None, analysis!: ?ExtensionDocumentAnalysis = None,
    bindings!: Bool = false, limits!: ParseLimits = ParseLimits.safe()): MarkdownEngine {
    let builder = MarkdownDialect
        .define("lifecycle", "1")
        .enable(
            ExtensionManifest("lifecycle", "1.0.0", "fixture",
                capabilities: ExtensionCapabilities(parse: false, transform: transform.isSome(),
                    analysis: analysis.isSome())))
    if (bindings) {
        OfficialExtensions.headingIds(OfficialExtensions.footnotes(builder))
    }
    if (let Some(value) <- transform) {
        builder.astTransform(value)
    }
    if (let Some(value) <- analysis) {
        builder.documentAnalysis(value)
    }
    MarkdownEngine.builder().dialect(builder.build()).limits(limits).build()
}

private func expectLifecycleFailure(outcome: ParseOutcome, expected: String): Unit {
    match (outcome) {
        case ParseOutcome.Failure(error) =>
            let actual = match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => "budget"
                case MarkdownErrorCode.Cancelled => "cancel"
                case MarkdownErrorCode.LimitExceeded => "limit"
                case MarkdownErrorCode.ExtensionFailure => "extension"
                case _ => "other"
            }
            @Expect(actual, expected)
            if (expected == "extension") {
                let failure = error as ExtensionFailureException
                @Expect(failure.isSome(), true)
                @Expect(failure.getOrThrow().extensionId, "lifecycle")
            }
        case _ => @Expect(false)
    }
}

@Test
class ExtensionLifecycleTests {
    @TestCase
    func sharedBatchAndAppendPipelineTransformsThenBindsThenAnalyzesExactlyOnce(): Unit {
        let trace = ArrayList<String>()
        let observedRevision = [Int64(0)]
        let transform = LifecycleTransformFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    trace.add("transform")
                    @Expect(document.bindings.headings.size, 0)
                    @Expect(document.bindings.footnotes.size, 0)
                    @Expect(source.text(document).startsWith("# Head"), true)
                    TreeRewriter.rewrite(
                        document,
                        {
                            node =>
                                if (let NodeKind.Text <- node.kind) {
                                    if (node.asText().getOrThrow().value == "Head") {
                                        return RewriteAction.MapText("Changed")
                                    }
                                }
                                RewriteAction.Keep
                        },
                        limits: stageLimits,
                        budget: budget,
                        cancellation: cancellation
                    )
            }
        )
        let analysis = LifecycleAnalysisFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    trace.add("analysis")
                    @Expect(document.bindings.headings.size, 1)
                    @Expect(document.bindings.headings[0].text, "Changed")
                    @Expect(document.bindings.headings[0].id, "changed")
                    @Expect(document.bindings.footnotes.size, 1)
                    let heading = AstQuery.byNodeId(document, document.bindings.headings[0].heading).getOrThrow()
                    @Expect(source.text(heading), "# Head")
                    observedRevision[0] = document.revision
                    [Diagnostic("OBS", DiagnosticSeverity.Info, "changed/1", heading.span.getOrThrow())]
            }
        )
        let engine = lifecycleEngine(transform: Some(transform), analysis: Some(analysis), bindings: true)
        let source = "# Head\n\nRef [^n].\n\n[^n]: note\n"
        let batch = engine.parse(source)
        @Expect(trace.toArray(), ["transform", "analysis"])
        @Expect(batch.document.revision, observedRevision[0])
        @Expect(batch.diagnostics.size, 1)
        @Expect(batch.diagnostics[0].message, "changed/1")
        @Expect(batch.diagnostics[0].extensionId, Some("lifecycle"))
        @Expect(batch.diagnostics[0].ruleId, Some("observe"))
        trace.clear()
        let session = engine.newAppendSession()
        let replica = AppendReplica()
        replica.apply(session.feed("# Head\n\nRef [^n].\n\n"))
        replica.apply(session.feed("[^n]: note\n"))
        @Expect(trace.size, 0)
        replica.apply(session.finish())
        @Expect(trace.toArray(), ["transform", "analysis"])
        @Expect(replica.result.getOrThrow().document.revision, observedRevision[0])
        expectAppendEquivalent(engine, replica.result.getOrThrow(), batch)
    }

    @TestCase
    func analysisOnlyRunsAfterBindingAndForcesHonestEditorFallback(): Unit {
        let calls = [Int64(0)]
        let analysis = LifecycleAnalysisFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    calls[0] = calls[0] + 1
                    [Diagnostic("OBS", DiagnosticSeverity.Info, source.text(), SourceSpan(0, source.byteLength()))]
            }
        )
        let engine = lifecycleEngine(analysis: Some(analysis))
        let original = engine.parseSnapshot("plain")
        let changed = original.applyEdits([SourceEdit(SourceSpan(0, 5), "other")]).snapshot
        @Expect(calls[0], 2)
        @Expect(changed.result.diagnostics[0].message, "other")
        @Expect(changed.syntaxTree.losslessText(), "other")
        @Expect(engine.capabilities().extension("lifecycle").getOrThrow().capabilities.analysis, true)
        @Expect(engine.capabilities().extension("lifecycle").getOrThrow().capabilities.transform, false)
        let bound = LifecycleAnalysisFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    @Expect(document.bindings.headings[0].id, "head")
                    @Expect(document.bindings.footnotes[0].number, 1)
                    []
            }
        )
        lifecycleEngine(analysis: Some(bound), bindings: true).parse("# Head\n\n[^n]\n\n[^n]: note")
    }

    @TestCase
    func wholeDocumentEntryPointsRejectBeforeInvokingCallbacksAndPreferFusedFallsBack(): Unit {
        let calls = [Int64(0)]
        let analysis = LifecycleAnalysisFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    calls[0] = calls[0] + 1
                    []
            }
        )
        let engine = lifecycleEngine(analysis: Some(analysis))
        @ExpectThrows[MarkdownException](engine.parseEvents("plain"))
        @ExpectThrows[MarkdownException](engine.newRawBlockEventSession())
        @ExpectThrows[MarkdownException](engine.renderHtml("plain", mode: HtmlExecutionMode.RequireFused))
        @Expect(calls[0], 0)
        let output = engine.renderHtml("plain", mode: HtmlExecutionMode.PreferFused)
        @Expect(output.html, "<p>plain</p>\n")
        if (let HtmlExecutionPath.FullAst <- output.path) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        @Expect(calls[0], 1)
    }

    @TestCase
    func invalidAnalysisSpansFixesAndAttributionFailInsteadOfPublishingSuccess(): Unit {
        for (mode in 0..5) {
            let analysis = LifecycleAnalysisFixture(
                {
                    document, source, stageLimits, budget, cancellation =>
                        let outside = SourceSpan(0, source.byteLength() + 1)
                        match (mode) {
                            case 0 => [Diagnostic("OBS", DiagnosticSeverity.Info, "invalid", outside)]
                            case 1 => [Diagnostic("OBS", DiagnosticSeverity.Info, "invalid", SourceSpan(0, 0),
                                relatedSpans: [outside])]
                            case 2 => [Diagnostic("OBS", DiagnosticSeverity.Info, "invalid", SourceSpan(0, 0),
                                fixes: [DiagnosticFix("fix", outside, "replacement")])]
                            case 3 => [Diagnostic("OBS", DiagnosticSeverity.Info, "invalid", SourceSpan(0, 0),
                                extensionId: Some("other"))]
                            case _ => throw IllegalStateException("analysis failed")
                        }
                }
            )
            expectLifecycleFailure(lifecycleEngine(analysis: Some(analysis)).tryParse("plain"), "extension")
        }
        let related = [SourceSpan(0, 0)]
        let analysis = LifecycleAnalysisFixture({
            document, source, stageLimits, budget, cancellation => [Diagnostic("OBS", DiagnosticSeverity.Info, "valid",
                SourceSpan(0, 0), relatedSpans: related)]
        })
        let parsed = lifecycleEngine(analysis: Some(analysis)).parse("plain")
        related[0] = SourceSpan(0, 999)
        @Expect(parsed.diagnostics[0].relatedSpans[0], SourceSpan(0, 0))
    }

    @TestCase
    func analysisDiagnosticsUseOriginalUtf8AndReplacementBoundaries(): Unit {
        let split = LifecycleAnalysisFixture({
            document, source, stageLimits, budget, cancellation => [Diagnostic("OBS", DiagnosticSeverity.Info, "split",
                SourceSpan(0, 1))]
        })
        expectLifecycleFailure(lifecycleEngine(analysis: Some(split)).tryParse("中😀"), "extension")
        let complete = LifecycleAnalysisFixture({
            document, source, stageLimits, budget, cancellation => [Diagnostic("OBS", DiagnosticSeverity.Info, "emoji",
                SourceSpan(3, 7))]
        })
        let parsed = lifecycleEngine(analysis: Some(complete)).parse("中😀")
        @Expect(parsed.source.slice(parsed.diagnostics[0].span), "😀")
        @Expect(parsed.source.utf16Position(parsed.diagnostics[0].span.startByte).character, 1)
        @Expect(parsed.source.utf16Position(parsed.diagnostics[0].span.endByte).character, 3)
        let invalid: Array<Byte> = [0xFF]
        let replaced = lifecycleEngine(analysis: Some(split)).parse(invalid, utf8Policy: Utf8Policy.ReplaceInvalid)
        @Expect(replaced.diagnostics[replaced.diagnostics.size - 1].span, SourceSpan(0, 1))
        @Expect(replaced.source.slice(SourceSpan(0, 1)), "�")
        @Expect(replaced.source.utf16Position(1).character, 1)
    }

    @TestCase
    func stageBudgetsCancellationAndForeignDocumentsKeepTheirRealFailureKinds(): Unit {
        let budgetAnalysis = LifecycleAnalysisFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    budget.consumeScan(steps: Int64.Max);
                    []
            }
        )
        expectLifecycleFailure(lifecycleEngine(analysis: Some(budgetAnalysis)).tryParse("plain"), "budget")
        let budgetTransform = LifecycleTransformFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    budget.consumeScan(steps: Int64.Max);
                    document
            }
        )
        expectLifecycleFailure(lifecycleEngine(transform: Some(budgetTransform)).tryParse("plain"), "budget")
        for (stage in [0, 1]) {
            let cancel = CancellationSource()
            let analysis = LifecycleAnalysisFixture(
                {
                    document, source, stageLimits, budget, cancellation =>
                        cancel.cancel();
                        []
                }
            )
            let transform = LifecycleTransformFixture(
                {
                    document, source, stageLimits, budget, cancellation =>
                        cancel.cancel();
                        document
                }
            )
            let engine = if (stage == 0) {
                lifecycleEngine(analysis: Some(analysis))
            } else {
                lifecycleEngine(transform: Some(transform))
            }
            expectLifecycleFailure(engine.tryParse("plain", cancellation: cancel.token), "cancel")
        }
        let foreignTransform = LifecycleTransformFixture(
            {document, source, stageLimits, budget, cancellation => Markdown.parse("foreign").document})
        expectLifecycleFailure(lifecycleEngine(transform: Some(foreignTransform)).tryParse("plain"), "extension")
        let large = LifecycleAnalysisFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    @Expect(stageLimits.maximumLiteralBytes, 8)
                    [Diagnostic("OBS", DiagnosticSeverity.Info, "a diagnostic over eight bytes", SourceSpan(0, 0))]
            }
        )
        let limits = ParseLimits(4096, 4096, 32, 4096, 4096, 32, 1024, 8, 4096, 1024, 1024)
        expectLifecycleFailure(lifecycleEngine(analysis: Some(large), limits: limits).tryParse("plain"), "limit")
        let document = Markdown.parse("plain").document
        @ExpectThrows[MarkdownException](AstInvariantValidator().validate(document,
            budget: OperationBudget(0, 0, 0, 0, 0, 0)))
    }

    @TestCase
    func callbacksAndRewriterUseTheEnginesActualStructuralLimit(): Unit {
        let limits = ParseLimits(4096, 4096, 32, 3, 4096, 32, 1024, 4096, 4096, 1024, 1024)
        let transform = LifecycleTransformFixture(
            {
                document, source, stageLimits, budget, cancellation =>
                    @Expect(stageLimits.maximumAstNodes, 3)
                    TreeRewriter.rewrite(
                        document,
                        {
                            node =>
                                if (let NodeKind.Text <- node.kind) {
                                    return RewriteAction.InsertAfter([node])
                                }
                                RewriteAction.Keep
                        },
                        limits: stageLimits,
                        budget: budget,
                        cancellation: cancellation
                    )
            }
        )
        expectLifecycleFailure(lifecycleEngine(transform: Some(transform), limits: limits).tryParse("plain"), "limit")
    }

    @TestCase
    func compiledAnalysisIdentityOrderingCapabilitiesAndDisableAreEnforced(): Unit {
        let body: (Document, SourceBuffer, ParseLimits, OperationBudget, CancellationToken) -> Array<Diagnostic> = {
            document, source, stageLimits, budget, cancellation => []
        }
        let first = LifecycleAnalysisFixture(body, id: "first", priority: 200)
        let second = LifecycleAnalysisFixture(body, id: "second", priority: 100)
        let builder = MarkdownDialect
            .define("order", "1")
            .enable(
                ExtensionManifest("lifecycle", "1.0.0", "fixture",
                    capabilities: ExtensionCapabilities(parse: false, analysis: true)))
            .documentAnalysis(second)
            .documentAnalysis(first)
        let engine = MarkdownEngine.builder().dialect(builder.build()).build()
        @Expect(engine.dialect.documentAnalyses[0].analysisId, "first")
        @Expect(engine.dialect.documentAnalyses[1].analysisId, "second")
        let original = lifecycleEngine(analysis: Some(LifecycleAnalysisFixture(body)))
        let changed = lifecycleEngine(analysis: Some(LifecycleAnalysisFixture(body, version: "2")))
        @Expect(original.dialect.fingerprint == changed.dialect.fingerprint, false)
        let artifact = original.createArtifact(original.parse("plain"))
        match (changed.loadArtifact(artifact, "plain")) {
            case ArtifactLoadResult.CacheMiss(_) => @Expect(true)
            case _ => @Expect(false)
        }
        @Expect(MarkdownEngine.builder().dialect(builder.disable("lifecycle").build()).build().dialect.documentAnalyses.size, 0)
        for (kind in 0..4) {
            let invalid = MarkdownDialect.define("invalid-analysis", "1")
            if (kind == 0) {
                invalid.enable(
                    ExtensionManifest("lifecycle", "1.0.0", "fixture",
                        capabilities: ExtensionCapabilities(analysis: true)))
            } else if (kind == 1) {
                invalid.enable(ExtensionManifest("lifecycle", "1.0.0", "fixture")).documentAnalysis(first)
            } else {
                invalid.enable(
                    ExtensionManifest("lifecycle", "1.0.0", "fixture",
                        capabilities: ExtensionCapabilities(analysis: true)))
                if (kind == 2) {
                    invalid.documentAnalysis(first).documentAnalysis(first)
                } else {
                    invalid.documentAnalysis(LifecycleAnalysisFixture(body, deterministic: false))
                }
            }
            @ExpectThrows[MarkdownException](DialectCompiler.compile(invalid.build()))
        }
    }
}
