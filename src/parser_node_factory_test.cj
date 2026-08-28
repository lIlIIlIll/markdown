package markdown

import std.unittest.*
import std.unittest.testmacro.*

private class FactoryTestPayload <: CustomPayload {
    public func payloadTypeId(): String {
        "factory-test"
    }
}

@Test
public class ParserNodeFactoryTests {
    @TestCase
    public func buildsOneArenaDocumentWithDeterministicPostorderIds(): Unit {
        let nodes = ParserNodeFactory(16)
        let text = nodes.text(LiteralStorage.Copy("raw"), LiteralStorage.Copy("value"), SourceSpan(2, 7))
        let heading = nodes.heading(2, [text], SourceSpan(0, 7))
        let custom = nodes.customBlock("ext", "1.0.0", "box", FactoryTestPayload(), [], Some(SourceSpan(8, 9)),
            NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(SourceSpan(8, 9)), extensionId: Some("ext")))
        let snapshot = nodes.finishDocument([heading, custom], SourceSpan(0, 9), MarkdownProfile.commonMark0312(), "fp",
            [])

        @Expect(snapshot.nodeCount, 4)
        @Expect(snapshot.root().nodeId, NodeId(4))
        @Expect(snapshot.root().asDocument().getOrThrow().dialectFingerprint, "fp")
        @Expect(snapshot.nodeAt(heading).asHeading().getOrThrow().level, 2)
        @Expect(snapshot.nodeAt(text).asText().getOrThrow().value, "value")
        @Expect(snapshot.nodeAt(custom).asCustomBlock().getOrThrow().payload.payloadTypeId(), "factory-test")
    }

    @TestCase
    public func replacesTextInPlaceWithoutChangingNodeIdentity(): Unit {
        let nodes = ParserNodeFactory(4)
        let text = nodes.text(LiteralStorage.Copy("a"), LiteralStorage.Copy("a"), SourceSpan(0, 1))
        nodes.replaceText(text, LiteralStorage.Copy("ab"), LiteralStorage.Copy("AB"), SourceSpan(0, 2))
        let paragraph = nodes.paragraph([text], SourceSpan(0, 2))
        let snapshot = nodes.finishDocument([paragraph], SourceSpan(0, 2), MarkdownProfile.commonMark0312(), "fp", [])

        @Expect(snapshot.nodeAt(text).nodeId, NodeId(1))
        @Expect(snapshot.nodeAt(text).asText().getOrThrow().raw, "ab")
        @Expect(snapshot.nodeAt(text).asText().getOrThrow().value, "AB")
    }

    @TestCase
    public func appliesMaximumAstNodesToTheDocumentRoot(): Unit {
        let nodes = ParserNodeFactory(2)
        let text = nodes.text(LiteralStorage.Copy("x"), LiteralStorage.Copy("x"), SourceSpan(0, 1))
        let paragraph = nodes.paragraph([text], SourceSpan(0, 1))
        @ExpectThrows[LimitExceededException](nodes.finishDocument([paragraph], SourceSpan(0, 1),
            MarkdownProfile.commonMark0312(), "fp", []))
    }
}
