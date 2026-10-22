package markdown.integration

import markdown.core.{CancellationSource, LimitExceededException, MarkdownErrorCode, MarkdownException, OperationBudget, 
    ParseLimits}
import markdown.engine.{FusedScanCheckpointObserver, HtmlExecutionMode, HtmlExecutionPath, MarkdownEngine}
import markdown.render.HtmlOptions
import std.unittest.*
import std.unittest.testmacro.*

private class CancelOnFusedScanCheckpoint <: FusedScanCheckpointObserver {
    private let cancellation: CancellationSource
    private let targetPhase: String
    var observedBytes: Int64 = -1
    protected var checkpoints: Int64 = 0

    init(cancellation: CancellationSource, targetPhase: String) {
        this.cancellation = cancellation
        this.targetPhase = targetPhase
    }

    public func onFusedScanCheckpoint(phase: String, bytesProcessed: Int64): Unit {
        checkpoints++
        if (phase == targetPhase && observedBytes < 0) {
            observedBytes = bytesProcessed
            cancellation.cancel()
        }
    }
}

@Test
class HtmlExecutionTest {
    @TestCase
    func preferFusedUsesRealDirectPathForProvenPlainDocuments(): Unit {
        let engine = MarkdownEngine.builder().build()
        let source = "hello world\nsecond line\n\nnext paragraph"
        let fused = engine.renderHtml(source, mode: HtmlExecutionMode.PreferFused)
        let full = engine.renderHtml(source, mode: HtmlExecutionMode.FullAst)
        @Expect(fused.html, full.html)
        match (fused.path) {
            case HtmlExecutionPath.Fused => @Expect(true)
            case _ => @Expect(false)
        }
        match (full.path) {
            case HtmlExecutionPath.FullAst => @Expect(true)
            case _ => @Expect(false)
        }
    }

    @TestCase
    func preferFallsBackAndRequireFailsClosedForAstSyntax(): Unit {
        let engine = MarkdownEngine.builder().build()
        let preferred = engine.renderHtml("**strong**", mode: HtmlExecutionMode.PreferFused)
        match (preferred.path) {
            case HtmlExecutionPath.FullAst => @Expect(preferred.html, "<p><strong>strong</strong></p>\n")
            case _ => @Expect(false)
        }
        try {
            engine.renderHtml("**strong**", mode: HtmlExecutionMode.RequireFused)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.RenderFailure => @Expect(error.phase, "fused_preflight")
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func fullAndFusedPathsEnforceStaticOutputAndLiteralLimits(): Unit {
        let outputLimits = ParseLimits(1024, 1024, 16, 64, 16, 16, 1024, 1024, 4, 1024, 1024)
        let outputEngine = MarkdownEngine.builder().limits(outputLimits).build()
        assertLimit(outputEngine, "abc", HtmlExecutionMode.FullAst, "output_bytes")
        assertLimit(outputEngine, "abc", HtmlExecutionMode.PreferFused, "output_bytes")
        assertLimit(outputEngine, "abc", HtmlExecutionMode.RequireFused, "output_bytes")

        let literalLimits = ParseLimits(1024, 1024, 16, 64, 16, 16, 1024, 2, 4096, 1024, 1024)
        let literalEngine = MarkdownEngine.builder().limits(literalLimits).build()
        assertLimit(literalEngine, "abc", HtmlExecutionMode.FullAst, "literal_bytes")
        assertLimit(literalEngine, "abc", HtmlExecutionMode.PreferFused, "literal_bytes")
        assertLimit(literalEngine, "abc", HtmlExecutionMode.RequireFused, "literal_bytes")
    }

    @TestCase
    func fusedOrdinaryRangeChecksStaticAndOperationLimitsBeforeSlicing(): Unit {
        let source = fusedOrdinaryText(65536)
        let fixedLimits = ParseLimits(131072, 131072, 16, 64, 16, 16, 131072, 131072, 4, 1024, 1024)
        let fixedEngine = MarkdownEngine.builder().limits(fixedLimits).build()
        assertLimit(fixedEngine, source, HtmlExecutionMode.RequireFused, "output_bytes")

        let operationLimits = ParseLimits(131072, 131072, 16, 64, 16, 16, 131072, 131072, 131072, 1024, 1024)
        let operationEngine = MarkdownEngine.builder().limits(operationLimits).build()
        try {
            operationEngine.renderHtml(source, mode: HtmlExecutionMode.RequireFused,
                budget: OperationBudget(131072, 100, 100, 100, 100, 4))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "output_bytes")
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func fusedPreflightChecksEntryCancellationBeforeAccountingOrOutput(): Unit {
        let source = fusedOrdinaryText(65536)
        let cancellation = CancellationSource()
        cancellation.cancel()
        let budget = OperationBudget.safe()
        let observer = CancelOnFusedScanCheckpoint(cancellation, "preflight")
        assertFusedCancelled(source, cancellation, budget, observer)
        @Expect(observer.checkpoints, 0)
        @Expect(budget.usedScanSteps(), 0)
        @Expect(budget.usedOutputBytes(), 0)
    }

    @TestCase
    func fusedPreflightAndOutputScansHaveDeterministicCancellationBounds(): Unit {
        let source = fusedOrdinaryText(65536)

        let preflightCancellation = CancellationSource()
        let preflightBudget = OperationBudget.safe()
        let preflightObserver = CancelOnFusedScanCheckpoint(preflightCancellation, "preflight")
        assertFusedCancelled(source, preflightCancellation, preflightBudget, preflightObserver)
        @Expect(preflightObserver.observedBytes, 1024)
        @Expect(preflightBudget.usedScanSteps(), 1024)
        @Expect(preflightBudget.usedOutputBytes(), 0)

        let outputCancellation = CancellationSource()
        let outputBudget = OperationBudget.safe()
        let outputObserver = CancelOnFusedScanCheckpoint(outputCancellation, "output_scan")
        assertFusedCancelled(source, outputCancellation, outputBudget, outputObserver)
        @Expect(outputObserver.observedBytes, 1024)
        @Expect(outputBudget.usedScanSteps(), source.size)
        // The opening tag precedes the range scan. Cancellation at the first
        // range checkpoint must prevent both text and closing-tag writes.
        @Expect(outputBudget.usedOutputBytes(), 3)
    }

    private func assertFusedCancelled(source: String, cancellation: CancellationSource, budget: OperationBudget,
        observer: FusedScanCheckpointObserver): Unit {
        var cancelled = false
        try {
            let _ = MarkdownEngine
                .builder()
                .build()
                .renderHtmlWithFusedScanObserver(source, HtmlExecutionMode.RequireFused, HtmlOptions.safe(),
                    cancellation.token, budget, observer)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled =>
                    cancelled = true
                    @Expect(error.phase, "fused_render")
                case _ => @Expect(false)
            }
        }
        @Expect(cancelled, true)
    }

    private func assertLimit(engine: MarkdownEngine, source: String, mode: HtmlExecutionMode, expectedKind: String): Unit {
        try {
            engine.renderHtml(source, mode: mode)
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, expectedKind)
        }
    }
}

private func fusedOrdinaryText(size: Int64): String {
    let out = StringBuilder()
    for (_ in 0..size) {
        out.append("a")
    }
    out.toString()
}
