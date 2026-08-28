package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TreeRewriterTest {
    @TestCase
    func mapsTextWithoutMutatingOriginalAndSharesUntouchedBranch(): Unit {
        let document = MarkdownEngine.builder().build().parse("# Keep\n\nchange me").document
        let headingBefore = document.children()[0]
        let rewritten = TreeRewriter.rewrite(document, {
            node => match (node.kind) {
                case NodeKind.Text =>
                    if (node.asText().getOrThrow().value == "change me") {
                        RewriteAction.MapText("changed")
                    } else {
                        RewriteAction.Keep
                    }
                case _ => RewriteAction.Keep
            }
        })
        @Expect(PlainTextRenderer().render(document), "Keep\n\nchange me")
        @Expect(PlainTextRenderer().render(rewritten), "Keep\n\nchanged")
        @Expect(rewritten.children()[0].nodeId, headingBefore.nodeId)
    }

    @TestCase
    func removeInsertAndReplaceChildrenRemainValid(): Unit {
        let document = MarkdownEngine.builder().build().parse("one\n\ntwo").document
        let secondId = document.children()[1].nodeId
        let rewritten = TreeRewriter.rewrite(document, {
            node => if (node.nodeId == secondId) {
                RewriteAction.Remove
            } else {
                RewriteAction.Keep
            }
        })
        @Expect(rewritten.children().size, 1)
        AstInvariantValidator().validate(rewritten)
    }

    @TestCase
    func budgetAndCancellationApplyToTransform(): Unit {
        let document = MarkdownEngine.builder().build().parse("text").document
        try {
            TreeRewriter.rewrite(document, {_ => RewriteAction.Keep}, budget: OperationBudget(10, 10, 10, 0, 10, 10))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "transform_steps")
                case _ => @Expect(false)
            }
        }
    }
}
