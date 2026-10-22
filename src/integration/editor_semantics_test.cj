package markdown.integration

import markdown.artifact.BinaryArtifactCodec
import markdown.core.{SourceSpan, Utf16Position}
import markdown.editor.{DocumentSnapshot, SourceEdit}
import markdown.engine.MarkdownEngine
import markdown.extensions.OfficialExtensions
import markdown.render.CanonicalMarkdownRenderer
import std.unittest.*
import std.unittest.testmacro.*

private func expectEditedSnapshot(engine: MarkdownEngine, actual: DocumentSnapshot, source: String): Unit {
    let expected = DocumentSnapshot.parse(engine, source)
    @Expect(actual.result.source.text(), source)
    @Expect(actual.syntaxTree.losslessText(), source)
    @Expect(actual.result.document.nodeCount, expected.result.document.nodeCount)
    let renderer = engine.htmlRenderer()
    let rendered = renderer.renderWithSourceMap(actual.result.document)
    let wanted = renderer.renderWithSourceMap(expected.result.document)
    @Expect(rendered.content, wanted.content)
    @Expect(rendered.sourceMap.size, wanted.sourceMap.size)
    for (index in 0..rendered.sourceMap.size) {
        @Expect(rendered.sourceMap[index].sourceSpan, wanted.sourceMap[index].sourceSpan)
        @Expect(rendered.sourceMap[index].outputRange, wanted.sourceMap[index].outputRange)
        @Expect(rendered.sourceMap[index].generated, wanted.sourceMap[index].generated)
    }
    @Expect(CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(actual.result.document),
        CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(expected.result.document))
    @Expect(actual.result.diagnostics.size, expected.result.diagnostics.size)
    for (index in 0..actual.result.diagnostics.size) {
        @Expect(actual.result.diagnostics[index].code, expected.result.diagnostics[index].code)
        @Expect(actual.result.diagnostics[index].span, expected.result.diagnostics[index].span)
    }
    let left = actual.syntaxTree.root.tokens
    let right = expected.syntaxTree.root.tokens
    @Expect(left.size, right.size)
    for (index in 0..left.size) {
        @Expect(left[index].raw, right[index].raw)
        @Expect(left[index].span, right[index].span)
        let owner = actual.syntaxMap.semanticNode(left[index])
        let expectedOwner = expected.syntaxMap.semanticNode(right[index])
        @Expect(owner.isSome(), expectedOwner.isSome())
        if (let Some(node) <- owner) {
            @Expect(node.span, expectedOwner.getOrThrow().span)
        }
    }
    @Expect(actual.result.document.bindings.headings.size, expected.result.document.bindings.headings.size)
    for (index in 0..actual.result.document.bindings.headings.size) {
        let heading = actual.result.document.bindings.headings[index]
        let wantedHeading = expected.result.document.bindings.headings[index]
        @Expect(heading.id, wantedHeading.id)
        @Expect(heading.text, wantedHeading.text)
        @Expect(heading.span, wantedHeading.span)
    }
    let bytes = source.toArray()
    for (offset in 0..bytes.size + 1) {
        if (offset < bytes.size && ((bytes[offset] & 0xC0) == 0x80 || (offset > 0 && bytes[offset] == 10 &&
            bytes[offset - 1] == 13))) {
            continue
        }
        let position = actual.result.source.utf16Position(offset)
        let wantedPosition = expected.result.source.utf16Position(offset)
        @Expect(position.line, wantedPosition.line)
        @Expect(position.character, wantedPosition.character)
        @Expect(actual.result.source.byteOffset(position), expected.result.source.byteOffset(wantedPosition))
    }
    let encoded = BinaryArtifactCodec.encode(actual).bytes()
    let expectedBytes = BinaryArtifactCodec.encode(expected).bytes()
    @Expect(encoded.size, expectedBytes.size)
    for (index in 0..encoded.size) {
        @Expect(encoded[index], expectedBytes[index])
    }
}

@Test
class EditorSemanticAcceptanceTest {
    @TestCase
    func paragraphHeadingUnicodeAndBlockEditsMatchFullSnapshots(): Unit {
        let engine = MarkdownEngine.builder().build()
        let cases: Array<(String, Int64, Int64, String, String, Bool)> = [
            ("alpha\n\nomega", 2, 2, "中", "al中pha\n\nomega", false),
            ("# Title\r\n\r\nbody😀\r\n", 2, 7, "中文😀", "# 中文😀\r\n\r\nbody😀\r\n", false),
            ("😀alpha\r\n\r\nend", 4, 9, "", "😀\r\n\r\nend", false),
            ("alpha", 0, 0, "中😀 ", "中😀 alpha", false),
            ("alpha", 5, 5, "😀", "alpha😀", false),
            ("one\n\ntwo", 0, 8, "x\n\ny\n\nz", "x\n\ny\n\nz", false),
            ("# Title\n\nbody", 2, 7, "Other", "# Other\n\nbody", true),
            ("A中文B", 1, 4, "文", "A文文B", true),
            ("A😀B", 1, 5, "🙂", "A🙂B", true),
            ("one\n\ntwo", 1, 6, "X", "oXwo", false)
        ]
        for (fixture in cases) {
            let original = DocumentSnapshot.parse(engine, fixture[0])
            let oldNode = original.result.document.children()[0]
            let changed = original.applyEdits([SourceEdit(SourceSpan(fixture[1], fixture[2]), fixture[3])])
            @Expect(changed.wasIncremental, fixture[5])
            expectEditedSnapshot(engine, changed.snapshot, fixture[4])
            @ExpectThrows[IllegalArgumentException](changed.snapshot.syntaxTree.originatingTokens(oldNode))
            @Expect(original.syntaxTree.losslessText(), fixture[0])
        }
    }

    @TestCase
    func referenceFootnoteHeadingAndTocDependenciesUseHonestFullFallback(): Unit {
        let engine = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        let cases: Array<(String, Int64, Int64, String, String)> = [
            ("x[^n]\n\n[^n]: body", 9, 10, "m", "x[^n]\n\n[^m]: body"),
            ("# Name {#id}\n\n[go](#id)", 9, 11, "new", "# Name {#new}\n\n[go](#id)"),
            ("[go][id]\n\n[id]: /old", 16, 20, "/new", "[go][id]\n\n[id]: /new"),
            ("# A\n\n# A\n\n[go](#a-2)", 0, 5, "", "# A\n\n[go](#a-2)")
        ]
        for (fixture in cases) {
            let original = DocumentSnapshot.parse(engine, fixture[0])
            let changed = original.applyEdits([SourceEdit(SourceSpan(fixture[1], fixture[2]), fixture[3])])
            @Expect(changed.wasIncremental, false)
            expectEditedSnapshot(engine, changed.snapshot, fixture[4])
            @Expect(original.result.source.text(), fixture[0])
        }
    }

    @TestCase
    func byteAndUtf16EditsRejectInteriorUnicodeBoundariesWithoutChangingSnapshot(): Unit {
        let engine = MarkdownEngine.builder().build()
        let original = DocumentSnapshot.parse(engine, "A😀B\r\n中文")
        for (replacement in ["x", "xx"]) {
            @ExpectThrows[IllegalArgumentException](original.applyEdits([SourceEdit(SourceSpan(2, 3), replacement)]))
        }
        @ExpectThrows[IllegalArgumentException](original.applyUtf16Edit(Utf16Position(0, 2), Utf16Position(0, 3), "x"))
        let changed = original.applyUtf16Edit(Utf16Position(0, 1), Utf16Position(0, 3), "中")
        expectEditedSnapshot(engine, changed.snapshot, "A中B\r\n中文")
        @Expect(original.result.source.text(), "A😀B\r\n中文")
    }
}
