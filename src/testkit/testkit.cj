package markdown.testkit

import markdown.core.{AstInvariantValidator, AstQuery, CancellationSource, ImmutableArray, LimitExceededException, 
    MarkdownErrorCode, MarkdownException, NodeRefWalkEvent, OperationBudget}
import markdown.engine.MarkdownEngine
import markdown.render.{CanonicalMarkdownRenderer, HtmlRenderer}
import std.collection.*

/** 扩展 TCK 的检查数、通过数和失败名称。 */
public class ExtensionTckReport {
    /** 执行的检查总数。 */
    public let checks: Int64
    /** 通过的检查数。 */
    public let passed: Int64
    /** 失败检查的名称列表。 */
    public let failedChecks: ImmutableArray<String>
    /**
     * 创建报告实例。
     * @param checks 执行的检查总数。
     * @param passed 通过的检查数。
     * @param failedChecks 失败检查的名称列表。
     */
    public init(checks: Int64, passed: Int64, failedChecks!: Array<String> = []) {
        this.checks = checks
        this.passed = passed
        this.failedChecks = ImmutableArray<String>(failedChecks)
    }
    /**
     * 返回是否所有检查均通过。
     * @return 全部通过时为 `true`。
     */
    public func isSuccess(): Bool {
        checks == passed
    }
}

/**
 * 对已配置扩展的 engine 执行 AST、分块输入、渲染、确定性、取消和预算等契约检查。
 *
 * sample 应触发 custom node 或文档处理阶段；source-spans 检查同时要求其节点具有 span。
 * 检查还包括 Markdown formatter 语义回环、固定后缀扰动和 fingerprint 形态。
 * 扩展包仍需为自己的参数、嵌套与交互语义编写针对性测试。
 *
 * provider 与 renderer 是宿主代码，TCK 不能限制其文件、网络或其他宿主权限。
 * safe-html 检查只检查该样本输出是否包含 `<script` 或 `javascript:`，不是沙箱或完整安全证明。
 */
public class MarkdownExtensionTestKit {
    /** 使用 sample 对 engine 执行公开扩展契约测试。
     * @param engine 被测 engine。
     * @param sample 能触发被测扩展语义的 Markdown 文本。
     * @return 已执行检查的总数、通过数和失败名称；不保证 sample 覆盖扩展的全部行为。
     * @throws MarkdownException 初始解析、分块输入或未被单项检查捕获的处理失败时。
     */
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

        let session = engine.newBufferedInputSession()
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
        if (spansValid && spanNodes > 0 && (customNodes.size > 0 || engine.dialect.parserHotPlan.hasDocumentStages)) {
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
