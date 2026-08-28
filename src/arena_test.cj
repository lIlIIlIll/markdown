package markdown

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private class ArenaTestPayload <: CustomPayload {
    public func payloadTypeId(): String {
        "arena-test"
    }
}

@Test
public class AstArenaTests {
    @TestCase
    public func storesPostorderNodesAndChildrenAcrossFixedChunks(): Unit {
        let builder = AstArenaBuilder()
        let leaves = ArrayList<Int64>()
        var index: Int64 = 0
        while (index < AST_NODE_CHUNK_SIZE + 1) {
            leaves.add(
                builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(index, index + 1)),
                    NodeOriginKind.Parsed, []))
            index++
        }
        let rootIndex = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, AST_NODE_CHUNK_SIZE + 1)),
            NodeOriginKind.Parsed, leaves.toArray())
        let snapshot = builder.freeze()

        @Expect(snapshot.nodeCount, AST_NODE_CHUNK_SIZE + 2)
        @Expect(snapshot.root().nodeId, NodeId(rootIndex + 1))
        @Expect(snapshot.root().children().size, AST_NODE_CHUNK_SIZE + 1)
        @Expect(snapshot.root().children()[AST_NODE_CHUNK_SIZE].span,
            Some(SourceSpan(AST_NODE_CHUNK_SIZE, AST_NODE_CHUNK_SIZE + 1)))
    }

    @TestCase
    public func rejectsCrossDocumentNodeRefs(): Unit {
        let firstBuilder = AstArenaBuilder()
        let _ = firstBuilder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 0)), NodeOriginKind.Parsed,
            [])
        let first = firstBuilder.freeze()
        let secondBuilder = AstArenaBuilder()
        let _ = secondBuilder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 0)),
            NodeOriginKind.Parsed, [])
        let second = secondBuilder.freeze()

        @ExpectThrows[IllegalArgumentException](second.children(first.root()))
        @Expect(first.root() == second.root(), false)
    }

    @TestCase
    public func rejectsForwardAndUnknownChildren(): Unit {
        let builder = AstArenaBuilder()
        @ExpectThrows[IllegalArgumentException](builder.append(NodeKind.Document, NodeCategory.Block,
            Some(SourceSpan(0, 0)), NodeOriginKind.Parsed, [0]))
    }

    @TestCase
    public func rejectsDuplicateAndMultipleParents(): Unit {
        let duplicateBuilder = AstArenaBuilder()
        let duplicateChild = duplicateBuilder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [])
        @ExpectThrows[IllegalArgumentException](duplicateBuilder.append(NodeKind.Paragraph, NodeCategory.Block,
            Some(SourceSpan(0, 1)), NodeOriginKind.Parsed, [duplicateChild, duplicateChild]))

        let multipleBuilder = AstArenaBuilder()
        let child = multipleBuilder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [])
        let firstParent = multipleBuilder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [child])
        @ExpectThrows[IllegalArgumentException](multipleBuilder.append(NodeKind.Heading, NodeCategory.Block,
            Some(SourceSpan(0, 1)), NodeOriginKind.Parsed, [child], payload: ArenaNodePayload.HeadingValue(1)))
        let _ = multipleBuilder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [firstParent])
        @Expect(multipleBuilder.freeze().root().children().toArray().size, 1)
    }

    @TestCase
    public func transformedSnapshotCopiesOnlyTheChangedChunkAndRejectsOldRefs(): Unit {
        let originalBuilder = AstArenaBuilder()
        let _ = originalBuilder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [])
        let _ = originalBuilder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [0])
        let original = originalBuilder.freeze()

        let transformedBuilder = AstArenaBuilder(original)
        transformedBuilder.replaceRecord(0, NodeKind.CodeSpan, NodeCategory.Inline, Some(SourceSpan(0, 1)),
            NodeOriginKind.Transformed, payload: Some(ArenaNodePayload.CodeSpanValue("x", "`")),
            origin: Some(NodeOrigin(NodeOriginKind.Transformed, sourceNodeIds: [NodeId(1)], transformId: Some("t"))))
        let transformed = transformedBuilder.freeze()

        @Expect(if (let NodeKind.Text <- original.nodeAt(0).kind) { true } else { false })
        @Expect(if (let NodeKind.CodeSpan <- transformed.nodeAt(0).kind) { true } else { false })
        @Expect(transformed.nodeAt(0).nodeId, original.nodeAt(0).nodeId)
        @Expect(transformed.nodeAt(0).asCodeSpan().getOrThrow().literal, "x")
        @Expect(transformed.nodeAt(0).origin.transformId, Some("t"))
        @ExpectThrows[IllegalArgumentException](transformed.children(original.root()))
    }

    @TestCase
    public func enforcesNodeLimitBeforeMutatingChildOwnership(): Unit {
        let builder = AstArenaBuilder(maximumNodes: 2)
        let child = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed, [])
        let parent = builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [child])
        @ExpectThrows[LimitExceededException](builder.append(NodeKind.Document, NodeCategory.Block,
            Some(SourceSpan(0, 1)), NodeOriginKind.Parsed, [parent]))
        @Expect(builder.freeze().nodeCount, 2)
    }

    @TestCase
    public func preservesCompactSpanBoundaryAndRejectsOverflow(): Unit {
        let builder = AstArenaBuilder()
        let boundary = builder.append(NodeKind.Text, NodeCategory.Inline,
            Some(SourceSpan(AST_SOURCE_OFFSET_MAX - 1, AST_SOURCE_OFFSET_MAX)), NodeOriginKind.Parsed, [])
        @Expect(builder.recordAt(boundary).span,
            Some(SourceSpan(AST_SOURCE_OFFSET_MAX - 1, AST_SOURCE_OFFSET_MAX)))
        @ExpectThrows[LimitExceededException](builder.append(NodeKind.Text, NodeCategory.Inline,
            Some(SourceSpan(AST_SOURCE_OFFSET_MAX, AST_SOURCE_OFFSET_MAX + 1)), NodeOriginKind.Parsed, []))
    }

    @TestCase
    public func rollbackDiscardsSpeculationAcrossChunkBoundaries(): Unit {
        let builder = AstArenaBuilder()
        let retained = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [], payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), None))
        let checkpoint = builder.checkpoint()
        var index: Int64 = 0
        while (index < AST_NODE_CHUNK_SIZE + 3) {
            let _ = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(index + 1, index + 2)),
                NodeOriginKind.Parsed, [],
                payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("discard"), LiteralStorage.Copy("discard"), None))
            index++
        }
        builder.rollback(checkpoint)
        let paragraph = builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [retained])
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [paragraph])
        let snapshot = builder.freeze()

        @Expect(snapshot.nodeCount, 3)
        @Expect(snapshot.nodeAt(0).asText().getOrThrow().value, "x")
        @Expect(snapshot.root().children()[0].nodeId, NodeId(2))
    }

    @TestCase
    public func trustedRollbackTruncatesSpeculationInsideCurrentChunk(): Unit {
        let builder = AstArenaBuilder(trustedParserConstruction: true)
        let retained = builder.appendParserOwned(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [],
            payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), None))
        let checkpoint = builder.checkpoint()
        let _ = builder.appendParserOwned(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(1, 2)),
            NodeOriginKind.Parsed, [],
            payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("discard"), LiteralStorage.Copy("discard"), None))
        builder.rollback(checkpoint)
        let paragraph = builder.appendParserOwned(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [retained])
        let _ = builder.appendParserOwned(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [paragraph])
        let snapshot = builder.freeze()

        @Expect(snapshot.nodeCount, 3)
        @Expect(snapshot.storedNodeCount, 3)
        @Expect(snapshot.nodeAt(0).asText().getOrThrow().value, "x")
    }

    @TestCase
    public func exposesKindSpecificDataThroughValueViews(): Unit {
        let builder = AstArenaBuilder()
        let text = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(2, 6)), NodeOriginKind.Parsed, [],
            payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("raw"), LiteralStorage.Copy("value"), None))
        let heading = builder.append(NodeKind.Heading, NodeCategory.Block, Some(SourceSpan(0, 6)), NodeOriginKind.Parsed,
            [text], payload: ArenaNodePayload.HeadingValue(2))
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 6)), NodeOriginKind.Parsed,
            [heading])
        let snapshot = builder.freeze()

        let headingView = snapshot.nodeAt(heading).asHeading().getOrThrow()
        let textView = headingView.node.children()[0].asText().getOrThrow()
        @Expect(headingView.level, 2)
        @Expect(textView.raw, "raw")
        @Expect(textView.value, "value")
        @Expect(textView.node.origin.sourceSpan, Some(SourceSpan(2, 6)))
        @Expect(snapshot.root().asHeading().isNone())
    }

    @TestCase
    public func requiresMetadataOnlyForNonParsedOrigins(): Unit {
        let builder = AstArenaBuilder()
        @ExpectThrows[IllegalArgumentException](builder.append(NodeKind.Text, NodeCategory.Inline,
            Some(SourceSpan(0, 1)), NodeOriginKind.ExtensionGenerated, []))
        let generated = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)),
            NodeOriginKind.ExtensionGenerated, [],
            origin: Some(
                NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(SourceSpan(0, 1)),
                    extensionId: Some("example"))))
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [generated])
        let snapshot = builder.freeze()
        @Expect(snapshot.nodeAt(generated).origin.extensionId, Some("example"))
    }

    @TestCase
    public func exposesEveryBlockPayloadThroughTypedViews(): Unit {
        let builder = AstArenaBuilder()
        let text = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed, [],
            payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), None))
        let item = builder.append(NodeKind.ListItem, NodeCategory.Block, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [text], payload: ArenaNodePayload.ListItemValue(TaskState.Checked, Some(SourceSpan(0, 1))))
        let thematic = builder.append(NodeKind.ThematicBreak, NodeCategory.Block, Some(SourceSpan(1, 4)),
            NodeOriginKind.Parsed, [], payload: ArenaNodePayload.ThematicBreakValue(b'*'))
        let html = builder.append(NodeKind.HtmlBlock, NodeCategory.Block, Some(SourceSpan(4, 11)), NodeOriginKind.Parsed,
            [], payload: ArenaNodePayload.HtmlBlockValue(LiteralStorage.Copy("<x></x>"), 7))
        let cellText = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(11, 12)),
            NodeOriginKind.Parsed, [],
            payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("y"), LiteralStorage.Copy("y"), None))
        let cell = builder.append(NodeKind.TableCell, NodeCategory.Block, Some(SourceSpan(11, 12)),
            NodeOriginKind.Parsed, [cellText], payload: ArenaNodePayload.TableCellValue(TableAlignment.Center))
        let row = builder.append(NodeKind.TableRow, NodeCategory.Block, Some(SourceSpan(11, 12)), NodeOriginKind.Parsed,
            [cell], payload: ArenaNodePayload.TableRowValue(true))
        let custom = builder.append(NodeKind.CustomBlock, NodeCategory.Block, Some(SourceSpan(12, 13)),
            NodeOriginKind.ExtensionGenerated, [],
            payload: ArenaNodePayload.CustomValue("ext", "1.0.0", "block", ArenaTestPayload()),
            origin: Some(NodeOrigin(NodeOriginKind.ExtensionGenerated, extensionId: Some("ext"))))
        let root = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 13)), NodeOriginKind.Parsed,
            [item, thematic, html, row, custom],
            payload: ArenaNodePayload.DocumentValue(MarkdownProfile.commonMark0312(), "fp",
                ImmutableArray<ReferenceDefinition>([])))
        let snapshot = builder.freeze()

        @Expect(if (let TaskState.Checked <- snapshot.nodeAt(item).asListItem().getOrThrow().taskState) {
            true
        } else {
            false
        })
        @Expect(snapshot.nodeAt(thematic).asThematicBreak().getOrThrow().marker, b'*')
        @Expect(snapshot.nodeAt(html).asHtmlBlock().getOrThrow().literal, "<x></x>")
        @Expect(if (let TableAlignment.Center <- snapshot.nodeAt(cell).asTableCell().getOrThrow().alignment) {
            true
        } else {
            false
        })
        @Expect(snapshot.nodeAt(row).asTableRow().getOrThrow().header, true)
        @Expect(snapshot.nodeAt(custom).asCustomBlock().getOrThrow().payload.payloadTypeId(), "arena-test")
        @Expect(snapshot.nodeAt(root).asDocument().getOrThrow().dialectFingerprint, "fp")
    }

    @TestCase
    public func exposesEveryInlinePayloadAndKeepsLinkAndImageDistinct(): Unit {
        let builder = AstArenaBuilder()
        let hardBreak = builder.append(NodeKind.HardBreak, NodeCategory.Inline, Some(SourceSpan(0, 2)),
            NodeOriginKind.Parsed, [], payload: ArenaNodePayload.HardBreakValue(HardBreakKind.Spaces))
        let codeSpan = builder.append(NodeKind.CodeSpan, NodeCategory.Inline, Some(SourceSpan(2, 5)),
            NodeOriginKind.Parsed, [], payload: ArenaNodePayload.CodeSpanValue("x", "`"))
        let html = builder.append(NodeKind.HtmlInline, NodeCategory.Inline, Some(SourceSpan(5, 9)),
            NodeOriginKind.Parsed, [], payload: ArenaNodePayload.HtmlInlineValue("<b>"))
        let linkPayload = ArenaNodePayload.LinkValue("/raw", "/dest", "raw title", "title", LinkSyntaxKind.Inline)
        let link = builder.append(NodeKind.Link, NodeCategory.Inline, Some(SourceSpan(9, 10)), NodeOriginKind.Parsed, [],
            payload: linkPayload)
        let image = builder.append(NodeKind.Image, NodeCategory.Inline, Some(SourceSpan(10, 11)), NodeOriginKind.Parsed,
            [], payload: linkPayload)
        let custom = builder.append(NodeKind.CustomInline, NodeCategory.Inline, Some(SourceSpan(11, 12)),
            NodeOriginKind.ExtensionGenerated, [],
            payload: ArenaNodePayload.CustomValue("ext", "1.0.0", "inline", ArenaTestPayload()),
            origin: Some(NodeOrigin(NodeOriginKind.ExtensionGenerated, extensionId: Some("ext"))))
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 12)), NodeOriginKind.Parsed,
            [hardBreak, codeSpan, html, link, image, custom])
        let snapshot = builder.freeze()

        @Expect(if (let HardBreakKind.Spaces <- snapshot.nodeAt(hardBreak).asHardBreak().getOrThrow().syntaxKind) {
            true
        } else {
            false
        })
        @Expect(snapshot.nodeAt(codeSpan).asCodeSpan().getOrThrow().delimiterRaw, "`")
        @Expect(snapshot.nodeAt(html).asHtmlInline().getOrThrow().literal, "<b>")
        @Expect(snapshot.nodeAt(link).asLink().isSome(), true)
        @Expect(snapshot.nodeAt(link).asImage().isNone(), true)
        @Expect(snapshot.nodeAt(image).asImage().isSome(), true)
        @Expect(snapshot.nodeAt(image).asLink().isNone(), true)
        @Expect(snapshot.nodeAt(custom).asCustomInline().getOrThrow().localKindId, "inline")
    }
}
