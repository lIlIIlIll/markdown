package markdown

import std.unittest.*
import std.unittest.testmacro.*

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
}
