package markdown.integration

import markdown.artifact.{ArtifactLoadResult, MarkdownParseArtifact}
import markdown.core.{AST_NODE_CHUNK_SIZE, AnnotationKey, AnnotationStore, AstQuery, LiteralStorage, MarkdownException, 
    MarkdownProfile, NodeId, NodeLineage, SourceBuffer, SourceSpan}
import markdown.editor.{DocumentSnapshot, MarkdownLinter, SourceEdit, SyntaxToAstMap}
import markdown.core.ParserNodeFactory
import markdown.engine.{MarkdownEngine}
import markdown.extensions.{ExtensionManifest, MarkdownDialect}
import markdown.render.HtmlRenderer
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class NodeIdentityTests {
    @TestCase
    func shortSharedLineageArenasKeepSerialConsumptionProportionalToActualNodes(): Unit {
        let lineage = NodeLineage()
        let identities = HashSet<NodeId>()
        var last: Int64 = 0
        for (_ in 0..2048) {
            let nodes = ParserNodeFactory(4, lineage: Some(lineage))
            let text = nodes.text(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), SourceSpan(0, 1))
            let paragraph = nodes.paragraph([text], SourceSpan(0, 1))
            let document = nodes.finishDocument([paragraph], SourceSpan(0, 1), MarkdownProfile.commonMark0312(), "test",
                [])
            for (node in [document.root(), document.nodeAt(paragraph), document.nodeAt(text)]) {
                @Expect(identities.add(node.nodeId), true)
                last = max(last, node.nodeId.value)
            }
        }
        @Expect(identities.size, 2048 * 3)
        @Expect(last <= identities.size * 2, true)
        @ExpectThrows[IllegalArgumentException](lineage.reserve(requested: 0))
        @ExpectThrows[IllegalArgumentException](lineage.reserve(requested: AST_NODE_CHUNK_SIZE + 1))
    }

    @TestCase
    func sparseSerialsAndIndependentLineagesHaveDistributedHashes(): Unit {
        for (shape in [0, 1]) {
            let buckets = HashSet<Int64>()
            let values = HashMap<NodeId, Int64>()
            for (index in 1..4097) {
                let node = if (shape == 0) {
                    NodeId(1, index * 4096)
                } else {
                    NodeId(index, index)
                }
                buckets.add(node.hashCode() & 1023)
                values.add(node, index)
            }
            @Expect(buckets.size >= 768, true)
            @Expect(values.size, 4096)
            for (index in 1..4097) {
                let node = if (shape == 0) {
                    NodeId(1, index * 4096)
                } else {
                    NodeId(index, index)
                }
                @Expect(values[node], index)
            }
        }
    }

    @TestCase
    func obsoleteExtensionSpiVersionsAreRejected(): Unit {
        for (version in ["1", "2"]) {
            let old = MarkdownDialect
                .define("old-spi", "0")
                .enable(ExtensionManifest("old", "1.0.0", "fixture", requiredSpiVersion: version))
                .build()
            @ExpectThrows[MarkdownException](MarkdownEngine.builder().dialect(old).build())
        }
        @Expect(MarkdownEngine.builder().build().capabilities().spiVersions[0], "3")
    }

    @TestCase
    func sourceViewsAndIncrementalArtifactsRemainBoundToTheirActualSnapshot(): Unit {
        let engine = MarkdownEngine.builder().build()
        let original = DocumentSnapshot.parse(engine, "first\n\nlast")
        let old = original.result.document.children()[1]
        let changed = original.applyEdits([SourceEdit(SourceSpan(0, 5), "other")]).snapshot
        let retained = AstQuery.byNodeId(changed.result.document, old.nodeId).getOrThrow()
        @Expect(changed.result.source.text(retained), "last")
        @Expect(changed.result.source.text(changed.result.document), "other\n\nlast")
        @ExpectThrows[IllegalArgumentException](changed.result.source.text(old))
        @ExpectThrows[IllegalArgumentException](SourceBuffer("other\n\nlast").text(retained))
        let artifact = MarkdownParseArtifact.create(engine, changed.result)
        match (artifact.load(engine, "other\n\nlast")) {
            case ArtifactLoadResult.Hit(document) => @Expect(HtmlRenderer().render(document), "<p>other</p>\n<p>last</p>\n")
            case _ => @Expect(false)
        }
    }

    @TestCase
    func identicalDocumentsAndRepeatedTextHaveDistinctIdentities(): Unit {
        let first = MarkdownEngine.builder().build().parse("same\n\nsame").document
        let second = MarkdownEngine.builder().build().parse("same\n\nsame").document
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
        let original = DocumentSnapshot.parse(MarkdownEngine.builder().build(), "first\n\nsame\n\nsame")
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
        let original = DocumentSnapshot.parse(engine, "<b>same</b>")
        let independent = DocumentSnapshot.parse(engine, "<b>same</b>")
        let fix = MarkdownLinter(original.engine).lint(original)[0].fixes[0]
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
