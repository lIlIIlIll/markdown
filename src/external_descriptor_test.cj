package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ExternalDialectDescriptorTest {
    @TestCase
    func jsonAndYamlDescriptorsCompileToTheSameDataOnlyDialect(): Unit {
        let json = """
        {"schemaVersion":"1","id":"external","version":"1.0.0","baseProfile":"commonmark-0.31.2",
         "inlineRules":["mark|==|==|128|true|true"],"blockRules":[],
         "rendererRules":["mark|mark|highlight|==|=="]}
        """
        let yaml = """
        schemaVersion: "1"
        id: external
        version: 1.0.0
        baseProfile: commonmark-0.31.2
        inlineRules:
          - "mark|==|==|128|true|true"
        blockRules:
        rendererRules:
          - "mark|mark|highlight|==|=="
        """
        let fromJson = ExternalDialectDescriptor.fromJson(json)
        let fromYaml = ExternalDialectDescriptor.fromYaml(yaml)
        @Expect(fromJson.compile().fingerprint, fromYaml.compile().fingerprint)
        let engine = MarkdownEngine.builder().dialect(fromJson.toDialect()).build()
        let parsed = engine.parse("A ==safe== value")
        @Expect(AstQuery.customNodes(parsed.document).size, 1)
        @Expect(engine.htmlRenderer().render(parsed.document).contains("<mark class=\"highlight\">safe</mark>"), true)
    }

    @TestCase
    func descriptorsRejectCallbacksUnknownFieldsInvalidSchemaAndUnboundedRules(): Unit {
        expectExternalFailure({
            => ExternalDialectDescriptor.fromJson(
                "{\"schemaVersion\":\"1\",\"id\":\"x\",\"version\":\"1\",\"baseProfile\":\"commonmark-0.31.2\",\"callback\":{}}")
        })
        expectExternalFailure({
            => ExternalDialectDescriptor.fromYaml(
                "schemaVersion: 1\nid: x\nversion: 1\nbaseProfile: commonmark-0.31.2\ncallback: execute")
        })
        expectExternalFailure({
            => ExternalDialectDescriptor.fromJson(
                "{\"schemaVersion\":\"2\",\"id\":\"x\",\"version\":\"1\",\"baseProfile\":\"commonmark-0.31.2\"}")
        })

        let unbounded = ExternalDialectDescriptor.fromJson(
            "{\"schemaVersion\":\"1\",\"id\":\"x\",\"version\":\"1\",\"baseProfile\":\"commonmark-0.31.2\",\"inlineRules\":[\"mark|==|==|0|true|true\"]}")
        try {
            unbounded.compile()
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.ExtensionConflict => @Expect(true)
                case _ => @Expect(false)
            }
        }
    }
}

private func expectExternalFailure(body: () -> ExternalDialectDescriptor): Unit {
    try {
        body();
        @Expect(false)
    } catch (_: IllegalArgumentException) {
        @Expect(true)
    }
}
