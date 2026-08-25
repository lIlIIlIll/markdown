package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class DocumentSystemTest {
    @TestCase
    func documentGraphUsesOnlyHostSuppliedInputsAndResolvesEdgesAndReferences(): Unit {
        let graph = DocumentGraph.build(
            MarkdownEngine.builder().build(),
            [
                DocumentInput("a.md", "# A\n\n[to B](b.md#heading)"),
                DocumentInput("b.md", "# B\n\n[shared]: /target")
            ]
        )
        @Expect(graph.documentIds.size, 2)
        @Expect(graph.edges.size, 1)
        @Expect(graph.edges[0].sourceDocumentId, "a.md")
        @Expect(graph.edges[0].destination, "b.md#heading")
        match (graph.resolveReference(" SHARED ")) {
            case Some(value) =>
                @Expect(value.documentId, "b.md")
                @Expect(value.definition.destination, "/target")
            case None => @Expect(false)
        }
    }

    @TestCase
    func htmlToMarkdownHasExplicitSafetyAndFidelityPolicies(): Unit {
        let converter = HtmlToMarkdownConverter()
        let markdown = converter.convert("<h1>Title</h1><p><strong>bold</strong> <a href=\"/x\">link</a></p>")
        @Expect(markdown, "# Title\n\n**bold** [link](/x)\n")
        try {
            converter.convert("<script>alert(1)</script>")
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.RenderFailure => @Expect(true)
                case _ => @Expect(false)
            }
        }
        let preserving = HtmlToMarkdownConverter(
            options: HtmlToMarkdownOptions(inputPolicy: HtmlInputPolicy.Trusted,
                fidelityPolicy: HtmlFidelityPolicy.PreserveUnknownHtml))
        @Expect(preserving.convert("<widget>x</widget>"), "<widget>x</widget>\n")
    }

    @TestCase
    func binarySnapshotIsVersionedStrictAndFuzzSafe(): Unit {
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        let snapshot = engine.parseSnapshot("# H\n\n- [x] task\n\n| a |\n| - |\n| b |")
        let artifact = BinaryArtifactCodec.encode(snapshot)
        match (BinaryArtifactCodec.decode(engine, artifact)) {
            case BinaryArtifactLoadResult.Hit(value) => @Expect(HtmlRenderer().render(value.result.document), HtmlRenderer().render(snapshot.result.document))
            case _ => @Expect(false)
        }
        let bytes = artifact.bytes()
        for (length in 0..min(bytes.size, 64)) {
            match (BinaryArtifactCodec.decode(engine, BinarySnapshotArtifact(bytes[..length]))) {
                case BinaryArtifactLoadResult.CacheMiss(_) => ()
                case _ => @Expect(false)
            }
        }
        let corrupt = bytes.clone();
        corrupt[0] = b'X'
        match (BinaryArtifactCodec.decode(engine, BinarySnapshotArtifact(corrupt))) {
            case BinaryArtifactLoadResult.CacheMiss(reason) => @Expect(reason, "schema magic")
            case _ => @Expect(false)
        }
        @Expect(engine.capabilities().serializationVersions[1], "markdown-snapshot-binary-1")
    }

    @TestCase
    func virtualTreePagesPreserveRangesCancellationAndBudgets(): Unit {
        let source = "# A\n\nparagraph one\n\nparagraph two\n\nparagraph three"
        let tree = VirtualSyntaxTree(MarkdownEngine.builder().build().parseSnapshot(source), pageBytes: 16)
        @Expect(tree.pageCount > 1, true)
        let first = tree.page(0)
        @Expect(first.sourceRange, SourceSpan(0, 16))
        @Expect(first.tokens.size > 0, true)
        @Expect(first.nodeIds.size > 0, true)
        let cancelled = CancellationSource();
        cancelled.cancel()
        try {
            tree.page(0, cancellation: cancelled.token);
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled => @Expect(true)
                case _ => @Expect(false)
            }
        }
        try {
            tree.page(0, budget: OperationBudget(0, 0, 0, 0, 0, 0));
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(true)
                case _ => @Expect(false)
            }
        }
    }
}
