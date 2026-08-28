package markdown

import std.collection.*

public class ExtensionTckReport {
    public let checks: Int64
    public let passed: Int64
    public let failedChecks: ImmutableArray<String>
    public init(checks: Int64, passed: Int64, failedChecks!: Array<String> = []) {
        this.checks = checks
        this.passed = passed
        this.failedChecks = ImmutableArray<String>(failedChecks)
    }
    public func isSuccess(): Bool {
        checks == passed
    }
}

public class MarkdownExtensionTestKit {
    public static func verify(engine: MarkdownEngine, sample: String): ExtensionTckReport {
        var checks: Int64 = 0
        var passed: Int64 = 0
        let failures = ArrayList<String>()
        let all = engine.parse(sample)
        checks++
        try {
            AstInvariantValidator().validate(all.document);
            passed++
        } catch (_: Exception) {
            failures.add("ast-invariants")
        }

        let session = engine.newSession()
        for (byte in sample.toArray()) {
            session.feed([byte])
        }
        let chunked = session.finish()
        checks++
        let renderer = HtmlRenderer(extensionRules: engine.dialect.rendererRules.toArray())
        if (renderer.render(all.document) == renderer.render(chunked.document)) {
            passed++
        } else {
            failures.add("chunk-invariance")
        }

        checks++
        let safe = HtmlRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(all.document)
        if (!safe.contains("<script") && !safe.contains("javascript:")) {
            passed++
        } else {
            failures.add("safe-html")
        }

        checks++
        let repeated = engine.parse(sample)
        let repeatedRenderer = HtmlRenderer(extensionRules: engine.dialect.rendererRules.toArray())
        let firstHtml = repeatedRenderer.render(all.document)
        let repeatedHtml = repeatedRenderer.render(repeated.document)
        if (all.document.root().asDocument().getOrThrow().dialectFingerprint == repeated
            .document
            .root()
            .asDocument()
            .getOrThrow()
            .dialectFingerprint && firstHtml == repeatedHtml) {
            passed++
        } else {
            failures.add("determinism")
        }

        checks++
        let cancelled = CancellationSource();
        cancelled.cancel()
        let beforeCancellation = passed
        try {
            engine.parse(sample, cancellation: cancelled.token)
        } catch (error: MarkdownException) {
            if (let MarkdownErrorCode.Cancelled <- error.code) {
                passed++
            }
        }
        if (passed == beforeCancellation) {
            failures.add("cancellation")
        }

        checks++
        var spansValid = true
        let customNodes = AstQuery.customNodes(all.document)
        var spanNodes: Int64 = 0
        for (event in all.document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                spanNodes++
                if (node.span.isNone()) {
                    spansValid = false
                }
            }
        }
        if (spansValid && spanNodes > 0 && (customNodes.size > 0 || engine.dialect.documentProcessors.size > 0)) {
            passed++
        } else {
            failures.add("source-spans")
        }

        checks++
        try {
            let formatted = CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(
                all.document)
            let reparsed = engine.parse(formatted)
            if (renderer.render(reparsed.document) == renderer.render(all.document)) {
                passed++
            } else {
                failures.add("formatter-semantics")
            }
        } catch (_: Exception) {
            failures.add("formatter-semantics")
        }

        checks++
        let beforeBudget = passed
        try {
            engine.parse(sample, budget: OperationBudget(0, 0, 0, 0, 0, 0))
        } catch (error: MarkdownException) {
            if (let MarkdownErrorCode.BudgetExceeded <- error.code) {
                passed++
            }
        }
        if (passed == beforeBudget) {
            failures.add("budget-limit")
        }

        checks++
        var fuzzStable = true
        for (suffix in ["*", "[", "<", "\\", "&", "\n", "==", ":::"]) {
            try {
                let first = engine.parse(sample + suffix)
                let second = engine.parse(sample + suffix)
                if (renderer.render(first.document) != renderer.render(second.document)) {
                    fuzzStable = false
                }
            } catch (_: LimitExceededException) {
                ()
            } catch (_: Exception) {
                fuzzStable = false
            }
        }
        if (fuzzStable) {
            passed++
        } else {
            failures.add("fuzz-determinism")
        }

        checks++
        if (engine.dialect.fingerprint.size == 64 && engine.dialect.fingerprint == engine.dialect.fingerprint) {
            passed++
        } else {
            failures.add("fingerprint")
        }

        ExtensionTckReport(checks, passed, failedChecks: failures.toArray())
    }
}
