package markdown.integration

import markdown.artifact.{BinaryArtifactCodec, BinaryArtifactLoadResult}
import markdown.core.{CustomPayload, MarkdownErrorCode, MarkdownException, SyntaxParameterValue, SyntaxPayload}
import markdown.editor.DocumentSnapshot
import markdown.engine.MarkdownEngine
import markdown.extensions.{ExtensionManifest, InlinePayloadEmitter, InlineSyntax, InlineSyntaxMatch, MarkdownDialect}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

class OpaqueArtifactPayload <: CustomPayload {
    public func payloadTypeId(): String {
        "fixture.opaque/1"
    }
}

class OpaqueArtifactEmitter <: InlinePayloadEmitter {
    var opaque = true
    protected var number: Int64 = 1
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        if (opaque) {
            OpaqueArtifactPayload()
        } else {
            let parameters = HashMap<String, SyntaxParameterValue>()
            parameters.add("count", SyntaxParameterValue.IntegerValue(number))
            SyntaxPayload("fixture", "", value.literal, typedValues: parameters)
        }
    }
}

func opaqueArtifactEngine(emitter: OpaqueArtifactEmitter): MarkdownEngine {
    MarkdownEngine
        .builder()
        .dialect(
            MarkdownDialect
                .define("opaque-fixture", "1")
                .enable(ExtensionManifest("opaque-fixture", "1.0.0", "1"))
                .inline(InlineSyntax.define("opaque-fixture", "value").delimiter("%%").emit(emitter))
                .build())
        .build()
}

@Test
class OpaqueArtifactTest {
    @TestCase
    func typedPayloadValuesAreOwnedAndParticipateInArtifactIdentity(): Unit {
        let parameters = HashMap<String, SyntaxParameterValue>()
        parameters.add("count", SyntaxParameterValue.IntegerValue(1))
        let payload = SyntaxPayload("fixture", "", "text", typedValues: parameters)
        parameters.add("count", SyntaxParameterValue.IntegerValue(2))
        match (payload.parameter("count")) {
            case Some(SyntaxParameterValue.IntegerValue(value)) => @Expect(value, 1)
            case _ => @Expect(false)
        }
        let emitter = OpaqueArtifactEmitter()
        emitter.opaque = false
        let engine = opaqueArtifactEngine(emitter)
        let artifact = BinaryArtifactCodec.encode(DocumentSnapshot.parse(engine, "%%text%%"))
        emitter.number = 2
        match (BinaryArtifactCodec.decode(engine, artifact)) {
            case BinaryArtifactLoadResult.CacheMiss(reason) => @Expect(reason, "AST digest")
            case _ => @Expect(false)
        }
    }

    @TestCase
    func opaquePayloadCannotBeEncodedOrRestoredByTypeNameAlone(): Unit {
        let emitter = OpaqueArtifactEmitter()
        let engine = opaqueArtifactEngine(emitter)
        try {
            BinaryArtifactCodec.encode(DocumentSnapshot.parse(engine, "%%text%%"))
            @Expect(false)
        } catch (error: MarkdownException) {
            @Expect(error.phase, "artifact_encode")
            @Expect(if (let MarkdownErrorCode.InvalidArtifact <- error.code) { true } else { false })
        }
        emitter.opaque = false
        let artifact = BinaryArtifactCodec.encode(DocumentSnapshot.parse(engine, "%%text%%"))
        emitter.opaque = true
        match (BinaryArtifactCodec.decode(engine, artifact)) {
            case BinaryArtifactLoadResult.CacheMiss(_) => @Expect(true)
            case _ => @Expect(false)
        }
    }
}
