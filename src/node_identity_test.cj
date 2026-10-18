package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class NodeIdentityTests {
    @TestCase
    func priorExtensionSpiIsRejectedAtTheNewIdentityBoundary(): Unit {
        let old = MarkdownDialect
            .define("old-spi", "1")
            .enable(ExtensionManifest("old", "1.0.0", "fixture", requiredSpiVersion: "1"))
            .build()
        @ExpectThrows[MarkdownException](MarkdownEngine.builder().dialect(old).build())
        @Expect(MarkdownEngine.builder().build().capabilities().spiVersions[0], "2")
    }

    @TestCase
    func identicalDocumentsAndRepeatedTextHaveDistinctIdentities(): Unit {
        let first = Markdown.parse("same\n\nsame").document
        let second = Markdown.parse("same\n\nsame").document
        @Expect(first.lineage != second.lineage, true)
        @Expect(first.revision != second.revision, true)
        @Expect(first.children()[0].nodeId == first.children()[1].nodeId, false)
        @Expect(first.children()[0].nodeId == second.children()[0].nodeId, false)
        @Expect(AstQuery.byNodeId(second, first.children()[0].nodeId).isNone(), true)

        let channel = AnnotationStore().channel(AnnotationKey<String>("test.identity"))
        channel.put(first.nodeId, "first")
        channel.put(second.nodeId, "second")
        @Expect(channel.size, 2)
        @Expect(channel.get(first.nodeId), Some("first"))
        @Expect(channel.remove(second.nodeId), Some("second"))
        @Expect(channel.get(first.nodeId), Some("first"))
    }

    @TestCase
    func persistentForksShareRetainedNodesWithoutReusingNewIdentities(): Unit {
        let original = MarkdownEngine.builder().build().parseSnapshot("first\n\nsame\n\nsame")
        let first = original.result.document.children()[0]
        let retained = original.result.document.children()[2]
        let left = original.applyEdits([SourceEdit(SourceSpan(0, 5), "alpha")]).snapshot
        let right = original.applyEdits([SourceEdit(SourceSpan(0, 5), "bravo")]).snapshot
        @Expect(left.result.document.lineage, original.result.document.lineage)
        @Expect(right.result.document.lineage, original.result.document.lineage)
        @Expect(left.result.document.children()[2].nodeId, retained.nodeId)
        @Expect(right.result.document.children()[2].nodeId, retained.nodeId)
        @Expect(left.result.document.children()[0].nodeId == first.nodeId, false)
        @Expect(left.result.document.children()[0].nodeId == right.result.document.children()[0].nodeId, false)
        @Expect(left.result.document.revision != right.result.document.revision, true)
        @ExpectThrows[IllegalArgumentException](left.result.document.children(retained))
        @ExpectThrows[IllegalArgumentException](left.syntaxMap.originatingTokens(retained))
        @ExpectThrows[IllegalArgumentException](left.syntaxTree.originatingTokens(retained))
        @ExpectThrows[IllegalArgumentException](SyntaxToAstMap(original.syntaxTree, left.result.document))
        let oldSyntax = original.syntaxMap.originatingSyntaxNode(retained).getOrThrow()
        @Expect(left.syntaxMap.semanticNode(oldSyntax).isNone(), true)
        let oldToken = original.syntaxMap.originatingTokens(retained)[0]
        @Expect(left.syntaxMap.semanticNode(oldToken).isNone(), true)
        @Expect(left.syntaxMap.semanticNode(left.syntaxMap.originatingSyntaxNode(
            left.result.document.children()[2]).getOrThrow()).getOrThrow().nodeId, retained.nodeId)
    }

    @TestCase
    func lintFixCannotCrossEqualTextSnapshotsOrARevertedRevision(): Unit {
        let engine = MarkdownEngine.builder().build()
        let original = engine.parseSnapshot("<b>same</b>")
        let independent = engine.parseSnapshot("<b>same</b>")
        let fix = MarkdownLinter.lint(original)[0].fixes[0]
        @Expect(original.version, independent.version)
        @Expect(original.sourceDigest, independent.sourceDigest)
        @ExpectThrows[IllegalStateException](MarkdownLinter.applyFix(independent, fix))
        let edited = original.applyEdits([SourceEdit(SourceSpan(3, 7), "diff")]).snapshot
        let reverted = edited.applyEdits([SourceEdit(SourceSpan(3, 7), "same")]).snapshot
        @Expect(reverted.sourceDigest, original.sourceDigest)
        @ExpectThrows[IllegalStateException](MarkdownLinter.applyFix(reverted, fix))
        @Expect(MarkdownLinter.applyFix(original, fix).snapshot.result.source.text(), "&lt;b&gt;same</b>")
    }
}
