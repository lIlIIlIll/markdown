package markdown

import std.unittest.*
import std.unittest.testmacro.*

class TestPayload <: CustomPayload {
    public func payloadTypeId(): String {
        "test-payload-v1"
    }
}

@Test
class AstContractTest {
    @TestCase
    func constructsImmutableTypedAstAndValidatesIt(): Unit {
        let builder = AstArenaBuilder()
        let text = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(2, 8)), NodeOriginKind.Parsed,
            [], payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("标题"), LiteralStorage.Copy("标题"), None))
        let original: Array<Int64> = [text]
        let heading = builder.append(NodeKind.Heading, NodeCategory.Block, Some(SourceSpan(0, 8)),
            NodeOriginKind.Parsed, original, payload: ArenaNodePayload.HeadingValue(1))
        original[0] = heading
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 8)), NodeOriginKind.Parsed,
            [heading], payload: ArenaNodePayload.DocumentValue(MarkdownProfile.commonMark0312(), "test-fingerprint",
                ImmutableArray<ReferenceDefinition>([])))
        let document = builder.freeze()
        match (document.children()[0].kind) {
            case NodeKind.Heading => @Expect(true)
            case _ => @Expect(false)
        }
        AstInvariantValidator().validate(document)
        @Expect(document.children().size, 1)
        @Expect(document.nodeId.value, 3)
    }

    @TestCase
    func rejectsDuplicateNodeIdsWithoutRecursingForever(): Unit {
        let builder = AstArenaBuilder()
        let text = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [], payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), None))
        try {
            builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
                [text, text])
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }
    }

    @TestCase
    func rejectsChildSpanOutsideParent(): Unit {
        let builder = AstArenaBuilder()
        let text = builder.append(NodeKind.Text, NodeCategory.Inline, Some(SourceSpan(2, 3)), NodeOriginKind.Parsed,
            [], payload: ArenaNodePayload.TextValue(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), None))
        let paragraph = builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [text])
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 3)), NodeOriginKind.Parsed,
            [paragraph], payload: ArenaNodePayload.DocumentValue(MarkdownProfile.commonMark0312(), "test",
                ImmutableArray<ReferenceDefinition>([])))
        let document = builder.freeze()
        expectInvariantFailure(document)
    }

    @TestCase
    func rejectsBlockInsideInlineContainer(): Unit {
        let builder = AstArenaBuilder()
        let nested = builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [])
        let paragraph = builder.append(NodeKind.Paragraph, NodeCategory.Block, Some(SourceSpan(0, 1)),
            NodeOriginKind.Parsed, [nested])
        let _ = builder.append(NodeKind.Document, NodeCategory.Block, Some(SourceSpan(0, 1)), NodeOriginKind.Parsed,
            [paragraph], payload: ArenaNodePayload.DocumentValue(MarkdownProfile.commonMark0312(), "test",
                ImmutableArray<ReferenceDefinition>([])))
        let document = builder.freeze()
        expectInvariantFailure(document)
    }

    @TestCase
    func customNodesKeepTypedPayloadAndOrigin(): Unit {
        let origin = NodeOrigin(
            NodeOriginKind.ExtensionGenerated,
            sourceNodeIds: [NodeId(1)],
            sourceSpan: Some(SourceSpan(0, 4)),
            extensionId: Some("admonition")
        )
        let builder = AstArenaBuilder()
        let index = builder.append(NodeKind.CustomBlock, NodeCategory.Block, Some(SourceSpan(0, 4)),
            NodeOriginKind.ExtensionGenerated, [],
            payload: ArenaNodePayload.CustomValue("admonition", "1.0.0", "note", TestPayload()), origin: Some(origin))
        let node = builder.snapshotView().nodeAt(index).asCustomBlock().getOrThrow()
        @Expect(node.payload.payloadTypeId(), "test-payload-v1")
        @Expect(node.extensionId, "admonition")
    }

    private func expectInvariantFailure(document: Document): Unit {
        try {
            AstInvariantValidator().validate(document)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InternalInvariantViolation => @Expect(error.phase, "ast_validation")
                case _ => @Expect(false)
            }
        }
    }
}
