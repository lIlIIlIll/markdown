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
        let ids = NodeIdAllocator()
        let text = Text(ids.next(), "标题", "标题", SourceSpan(2, 8))
        let heading = Heading(ids.next(), 1, [text], SourceSpan(0, 8))
        let original: Array<MarkdownNode> = [heading]
        let document = Document(
            ids.next(),
            original,
            SourceSpan(0, 8),
            MarkdownProfile.commonMark0312(),
            "test-fingerprint"
        )
        original[0] = Paragraph(ids.next(), [], SourceSpan(0, 8))
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
        let text = Text(NodeId(1), "x", "x", SourceSpan(0, 1))
        let paragraph = Paragraph(NodeId(1), [text], SourceSpan(0, 1))
        let document = Document(
            NodeId(2),
            [paragraph],
            SourceSpan(0, 1),
            MarkdownProfile.commonMark0312(),
            "test"
        )
        expectInvariantFailure(document)
    }

    @TestCase
    func rejectsChildSpanOutsideParent(): Unit {
        let text = Text(NodeId(1), "x", "x", SourceSpan(2, 3))
        let paragraph = Paragraph(NodeId(2), [text], SourceSpan(0, 1))
        let document = Document(
            NodeId(3),
            [paragraph],
            SourceSpan(0, 3),
            MarkdownProfile.commonMark0312(),
            "test"
        )
        expectInvariantFailure(document)
    }

    @TestCase
    func rejectsBlockInsideInlineContainer(): Unit {
        let nested = Paragraph(NodeId(1), [], SourceSpan(0, 1))
        let paragraph = Paragraph(NodeId(2), [nested], SourceSpan(0, 1))
        let document = Document(
            NodeId(3),
            [paragraph],
            SourceSpan(0, 1),
            MarkdownProfile.commonMark0312(),
            "test"
        )
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
        let node = CustomBlock(
            NodeId(2),
            "admonition",
            "1.0.0",
            "note",
            TestPayload(),
            [],
            Some(SourceSpan(0, 4)),
            origin
        )
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
