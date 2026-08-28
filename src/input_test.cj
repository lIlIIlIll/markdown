package markdown

import std.collection.*
import std.io.InputStream
import std.unittest.*
import std.unittest.testmacro.*

private class InvalidScannerAccelerator <: LineScannerAccelerator {
    public func implementationId(): String {
        "invalid-test-scanner"
    }

    public func scanLines(_: Array<Byte>, _: Int64): ?Array<UInt64> {
        Some([UInt64.Max])
    }
}

private class LegacyV1ScannerAccelerator <: LineScannerAccelerator {
    public func implementationId(): String {
        "legacy-v1-test-scanner"
    }

    public func scanLines(bytes: Array<Byte>, _: Int64): ?Array<UInt64> {
        Some([(UInt64(bytes.size) << 3) | 0x4u64])
    }
}

private class LegacyV2ScannerAccelerator <: LineScannerAccelerator {
    public func implementationId(): String {
        "legacy-v2-test-scanner"
    }

    public func recordFormatVersion(): Int64 {
        2
    }

    public func scanLines(bytes: Array<Byte>, _: Int64): ?Array<UInt64> {
        Some([(UInt64(bytes.size) << 4) | 0x4u64])
    }
}

private class UnsupportedScannerAccelerator <: LineScannerAccelerator {
    public func implementationId(): String {
        "unsupported-test-scanner"
    }

    public func recordFormatVersion(): Int64 {
        99
    }

    public func scanLines(_: Array<Byte>, _: Int64): ?Array<UInt64> {
        Some([])
    }
}

private class InvalidScannerCountAccelerator <: LineScannerAccelerator {
    public func implementationId(): String {
        "invalid-count-test-scanner"
    }

    public func scanLines(_: Array<Byte>, _: Int64): ?Array<UInt64> {
        Some([])
    }

    public func scanLineRecords(bytes: Array<Byte>, _: Int64): ?LineScanRecords {
        Some(LineScanRecords([(UInt64(bytes.size) << 3) | 0x4u64], 2))
    }
}

class ArrayInputStream <: InputStream {
    private let bytes: Array<Byte>
    private var offset: Int64 = 0

    init(bytes: Array<Byte>) {
        this.bytes = bytes.clone()
    }

    public func read(buffer: Array<Byte>): Int64 {
        if (offset >= bytes.size) {
            return 0
        }
        let count = min(buffer.size, bytes.size - offset)
        for (index in 0..count) {
            buffer[index] = bytes[offset + index]
        }
        offset += count
        count
    }
}

class FailingInputStream <: InputStream {
    public func read(_: Array<Byte>): Int64 {
        throw IllegalStateException("read failed")
    }
}

@Test
class InputBehaviorTest {
    @TestCase
    func strictRejectsInvalidUtf8AndReplacePreservesOriginalOffsets(): Unit {
        let bytes: Array<Byte> = [b'#', b' ', 0xFF, b'x']
        try {
            MarkdownEngine.builder().build().parse(bytes)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.InvalidEncoding => @Expect(error.phase, "input")
                case _ => @Expect(false)
            }
        }

        let result = MarkdownEngine.builder().build().parse(bytes, utf8Policy: Utf8Policy.ReplaceInvalid)
        @Expect(result.source.byteLength(), 4)
        @Expect(result.diagnostics.size, 1)
        @Expect(result.diagnostics[0].code, "MD1001_INVALID_UTF8_REPLACED")
        @Expect(result.diagnostics[0].span, SourceSpan(2, 3))
        @Expect(result.diagnostics[0].fixes.size, 1)
        @Expect(result.diagnostics[0].fixes[0].replacement, "\u{FFFD}")
        let headingNode = result.document.children()[0]
        match (headingNode.kind) {
            case NodeKind.Heading =>
                @Expect(headingNode.span, Some(SourceSpan(0, 4)))
                let textNode = headingNode.children()[0]
                match (textNode.kind) {
                    case NodeKind.Text =>
                        let text = textNode.asText().getOrThrow()
                        @Expect(text.value, "\u{FFFD}x")
                        @Expect(textNode.span, Some(SourceSpan(2, 4)))
                        @Expect(result.source.slice(SourceSpan(2, 4)), "\u{FFFD}x")
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
    }

    @TestCase
    func bomDoesNotBecomeMarkdownTextButOffsetsRemainOriginal(): Unit {
        let bytes: Array<Byte> = [0xEF, 0xBB, 0xBF, b'#', b' ', b'x']
        let result = MarkdownEngine.builder().build().parse(bytes)
        let headingNode = result.document.children()[0]
        match (headingNode.kind) {
            case NodeKind.Heading =>
                @Expect(headingNode.span, Some(SourceSpan(3, 6)))
                let textNode = headingNode.children()[0]
                match (textNode.kind) {
                    case NodeKind.Text => @Expect(textNode.span, Some(SourceSpan(5, 6)))
                    case _ => @Expect(false)
                }
            case _ => @Expect(false)
        }
    }

    @TestCase
    func arbitraryChunkBoundariesMatchAllAtOnce(): Unit {
        let input = "# 😀\r\n\r\nA **bold**"
        let engine = MarkdownEngine.builder().build()
        let expected = HtmlRenderer(options: HtmlOptions.specCompatible()).render(engine.parse(input).document)
        let session = engine.newSession()
        for (byte in input.toArray()) {
            session.feed([byte])
        }
        let actual = HtmlRenderer(options: HtmlOptions.specCompatible()).render(session.finish().document)
        @Expect(actual, expected)
    }

    @TestCase
    func streamInputUsesSameParserAndPreservesReadFailuresAsTypedCause(): Unit {
        let input = ArrayInputStream("# stream".toArray())
        let result = MarkdownEngine.builder().build().parse(input)
        let headingNode = result.document.children()[0]
        match (headingNode.kind) {
            case NodeKind.Heading => @Expect(headingNode.asHeading().getOrThrow().level, 1)
            case _ => @Expect(false)
        }
        try {
            MarkdownEngine.builder().build().parse(FailingInputStream())
            @Expect(false)
        } catch (error: InputReadFailureException) {
            @Expect(error.cause.message, "read failed")
        }
    }

    @TestCase
    func sourceSlicesPositionMapAndDetachHaveExplicitOwnershipSemantics(): Unit {
        let result = Markdown.parse("\t😀 x\nnext")
        let slice = result.source.sourceSlice(SourceSpan(1, 5))
        @Expect(slice.text(), "😀")
        @Expect(LiteralStorage.Slice(slice).text(), "😀")
        match (LiteralStorage.Slice(slice).detach()) {
            case LiteralStorage.Copy(value) => @Expect(value, "😀")
            case _ => @Expect(false)
        }
        let positions = SourcePositionMap(result.source, tabStop: 4)
        @Expect(positions.visualPosition(1), VisualPosition(1, 5))
        @Expect(positions.utf16Position(5), Utf16Position(0, 3))
        @Expect(positions.byteOffset(Utf16Position(0, 3)), 5)
        @Expect(result.source.text(result.document), result.source.text())
        @Expect(result.document.detach().children().size, result.document.children().size)
    }

    @TestCase
    func explicitOwnedByteInputTransfersStorageWithoutIdentityMap(): Unit {
        let input = unsafe { OwnedUtf8Input.take("# owned 😀".toArray()) }
        let result = MarkdownEngine.builder().build().parse(input)
        @Expect(PlainTextRenderer().render(result.document), "owned 😀")
        @Expect(result.source.byteLength(), 12)
        try {
            MarkdownEngine.builder().build().parse(input)
            @Expect(false)
        } catch (_: IllegalStateException) {
            @Expect(true)
        }
    }

    @TestCase
    func reusableUtf8InputValidatesOnceAndSupportsRepeatedParsing(): Unit {
        let original = "# reusable 😀".toArray()
        let input = ReusableUtf8Input(original)
        original[2] = b'X'
        let engine = MarkdownEngine.builder().build()
        let first = engine.parse(input)
        let second = engine.parse(input)
        @Expect(PlainTextRenderer().render(first.document), "reusable 😀")
        @Expect(PlainTextRenderer().render(second.document), "reusable 😀")
        @Expect(first.source.byteLength(), second.source.byteLength())

        try {
            ReusableUtf8Input([0xff])
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }

        let tiny = ParseLimits(3, 3, 8, 16, 4, 4, 4, 4, 8, 4, 4)
        try {
            MarkdownEngine.builder().limits(tiny).build().parse(input)
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "input_bytes")
            @Expect(error.observedValue, 15)
        }
    }

    @TestCase
    func nativeScannerCanBeDisabledWithoutChangingPublicParseSemantics(): Unit {
        let input = "# title\r\n\r\nText *em* 😀".toArray()
        let nativeEngine = MarkdownEngine.builder().nativeScannerEnabled(true).build()
        let cangjieEngine = MarkdownEngine.builder().nativeScannerEnabled(false).build()
        let renderer = HtmlRenderer(options: HtmlOptions.specCompatible())
        let nativeHtml = renderer.render(nativeEngine.parse(input).document)
        let cangjieHtml = renderer.render(cangjieEngine.parse(input).document)
        @Expect(cangjieHtml, nativeHtml)
        @Expect(cangjieEngine.capabilities().nativeScannerEnabled, false)

        // Average line width below the packed-record estimate must safely
        // fall back to the Cangjie scanner without changing semantics.
        let dense = StringBuilder()
        for (_ in 0..1024) {
            dense.append("x\n")
        }
        let denseBytes = dense.toString().toArray()
        @Expect(renderer.render(nativeEngine.parse(denseBytes).document),
            renderer.render(cangjieEngine.parse(denseBytes).document))
    }

    @TestCase
    func explicitBufferedInputSessionParsesOnlyAtFinish(): Unit {
        let engine = MarkdownEngine.builder().build()
        let session = engine.newBufferedInputSession()
        session.feed("# buffered")
        let result = session.finish()
        @Expect(PlainTextRenderer().render(result.document), "buffered")
        try {
            session.feed("late")
            @Expect(false)
        } catch (_: IllegalStateException) {
            @Expect(true)
        }
    }

    @TestCase
    func rejectsMalformedThirdPartyScannerRecordsBeforeSlicing(): Unit {
        let engine = MarkdownEngine.builder().build().acceleratedBy(InvalidScannerAccelerator())
        try {
            engine.parse("x".toArray())
            @Expect(false)
        } catch (error: IllegalStateException) {
            @Expect(error.message.contains("invalid packed record"), true)
        }

        let invalidCount = MarkdownEngine.builder().build().acceleratedBy(InvalidScannerCountAccelerator())
        try {
            invalidCount.parse("x".toArray())
            @Expect(false)
        } catch (error: IllegalStateException) {
            @Expect(error.message.contains("invalid record count"), true)
        }
    }

    @TestCase
    func preservesLegacyScannerSemanticsAndRejectsUnknownFormats(): Unit {
        let legacy = MarkdownEngine.builder().build().acceleratedBy(LegacyV1ScannerAccelerator())
        let document = legacy.parse("*legacy*".toArray()).document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>legacy</em></p>\n")

        // Version 2 has no text-lowering bit. It must therefore retain the
        // conservative coalescing path for escape/entity/code markers.
        let legacyV2 = MarkdownEngine.builder().build().acceleratedBy(LegacyV2ScannerAccelerator())
        let entity = legacyV2.parse("a&amp;b".toArray())
        @Expect(entity.document.children()[0].children().size, 1)
        @Expect(entity.document.children()[0].children()[0].asText().getOrThrow().value, "a&b")
        @Expect(entity.document.storedNodeCount, entity.document.nodeCount)

        let unsupported = MarkdownEngine.builder().build().acceleratedBy(UnsupportedScannerAccelerator())
        try {
            unsupported.parse("x".toArray())
            @Expect(false)
        } catch (error: IllegalStateException) {
            @Expect(error.message.contains("unsupported record format"), true)
        }
    }

    @TestCase
    func indexedPositionMapMatchesSourceAcrossCrlfUnicodeAndReplacement(): Unit {
        let result = Markdown.parse("\t😀\r\nx\n")
        let positions = SourcePositionMap(result.source, tabStop: 4)
        for (offset in 0..result.source.byteLength() + 1) {
            @Expect(positions.sourcePosition(offset), result.source.position(offset))
        }
        for (offset in [0, 1, 5, 6, 7, 8, 9]) {
            @Expect(positions.utf16Position(offset), result.source.utf16Position(offset))
            @Expect(positions.visualPosition(offset), result.source.visualPosition(offset, tabStop: 4))
        }
        @Expect(positions.byteOffset(Utf16Position(1, 0)), 7)
        @Expect(positions.byteOffset(Utf16Position(1, 1)), 8)
        @Expect(positions.byteOffset(Utf16Position(2, 0)), 9)
        let scalarPositions = SourcePositionMap(result.source, 4, DisplayWidthPolicy.UnicodeScalar)
        @Expect(scalarPositions.visualPosition(1), VisualPosition(1, 2))
        @Expect(positions.visualPosition(1), VisualPosition(1, 5))

        let replaced = MarkdownEngine.builder().build().parse([b'a', 0xFF, b'b'], utf8Policy: Utf8Policy.ReplaceInvalid)
        let replacementPositions = SourcePositionMap(replaced.source)
        @Expect(replacementPositions.utf16Position(0), Utf16Position(0, 0))
        @Expect(replacementPositions.utf16Position(1), Utf16Position(0, 1))
        @Expect(replacementPositions.utf16Position(2), Utf16Position(0, 2))
        @Expect(replacementPositions.utf16Position(3), Utf16Position(0, 3))
        @Expect(replacementPositions.byteOffset(Utf16Position(0, 2)), 2)

        let longLine = StringBuilder()
        for (_ in 0..200) {
            longLine.append("a")
        }
        longLine.append("😀\tend")
        let longResult = Markdown.parse(longLine.toString())
        let longPositions = SourcePositionMap(longResult.source, tabStop: 4)
        for (offset in [0, 63, 64, 65, 127, 128, 129, 200, 204, 205, 208]) {
            @Expect(longPositions.utf16Position(offset), longResult.source.utf16Position(offset))
            @Expect(longPositions.visualPosition(offset), longResult.source.visualPosition(offset, tabStop: 4))
        }
    }
}
