package markdown.integration

import markdown.core.ParseLimits
import markdown.editor.{DocumentSnapshot, Fix, LintDiagnostic, MarkdownLinter}
import markdown.engine.MarkdownEngine
import markdown.extensions.{ExtensionManifest, InlineSyntax, MarkdownDialect}
import std.unittest.*
import std.unittest.testmacro.*

@Test
class LintExplainTest {
    @TestCase
    func lintFindsStructureAccessibilityAndSecurityIssuesAndAppliesFreshFix(): Unit {
        let snapshot = DocumentSnapshot.parse(MarkdownEngine.builder().build(), "# H\n### Jump\n\n![]()\n\n<div>x</div>")
        let diagnostics = MarkdownLinter(snapshot.engine).lint(snapshot)
        @Expect(diagnostics.size >= 4, true)
        var rawFix: ?Fix = None
        for (diagnostic in diagnostics) {
            if (diagnostic.code == "MDL3003_RAW_HTML") {
                rawFix = Some(diagnostic.fixes[0])
            }
        }
        match (rawFix) {
            case Some(fix) =>
                let changed = MarkdownLinter.applyFix(snapshot, fix)
                @Expect(changed.snapshot.result.source.text().contains("&lt;div&gt;"), true)
            case None => @Expect(false)
        }
    }

    @TestCase
    func explainReportsActualExtensionSelectionAndFingerprint(): Unit {
        let dialect = MarkdownDialect
            .define("docs", "1")
            .enable(ExtensionManifest("docs", "1.0.0", "1"))
            .inline(InlineSyntax.define("docs", "mark").delimiter("==").priority(200))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let explanation = engine.explain("==x==", 0)
        @Expect(explanation.selectedRule, "inline:docs/mark")
        @Expect(explanation.priority, 200)
        @Expect(explanation.fingerprint, engine.dialect.fingerprint)
        let compiled = engine.explainDialect()
        @Expect(compiled.profileId, "commonmark-0.31.2")
        @Expect(compiled.inlineRuleOrder[0], "docs/mark")
        @Expect(compiled.maximumInputBytes, ParseLimits.safe().maximumInputBytes)
        @Expect(compiled.fingerprint, engine.dialect.fingerprint)
    }

    @TestCase
    func lintCoversUnusedReferencesMixedMarkersAmbiguityAndInvisibleSeparators(): Unit {
        let source = "[used]: /used\n[unused]: /unused\n\n[used]\n\n- one\n+ two\n\n**open\n\nsoft\u{2028}separator"
        let engine = MarkdownEngine.builder().build()
        let snapshot = DocumentSnapshot.parse(engine, source)
        let diagnostics = MarkdownLinter(engine).lint(snapshot)
        @Expect(hasLintCode(diagnostics, "MDL1003_UNUSED_REFERENCE"), true)
        @Expect(hasLintCode(diagnostics, "MDL4001_MIXED_LIST_MARKERS"), true)
        @Expect(hasLintCode(diagnostics, "MDL1005_AMBIGUOUS_OR_UNCLOSED_SYNTAX"), true)
        @Expect(hasLintCode(diagnostics, "MDL3002_INVISIBLE_UNICODE"), true)
    }
}

private func hasLintCode(diagnostics: Array<LintDiagnostic>, code: String): Bool {
    for (diagnostic in diagnostics) {
        if (diagnostic.code == code) {
            return true
        }
    }
    false
}
