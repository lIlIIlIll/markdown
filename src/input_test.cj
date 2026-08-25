package markdown

import std.io.InputStream
import std.unittest.*
import std.unittest.testmacro.*

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
        match (result.document.children()[0]) {
            case heading: Heading =>
                @Expect(heading.span, Some(SourceSpan(0, 4)))
                match (heading.children()[0]) {
                    case text: Text =>
                        @Expect(text.value, "\u{FFFD}x")
                        @Expect(text.span, Some(SourceSpan(2, 4)))
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
        match (result.document.children()[0]) {
            case heading: Heading =>
                @Expect(heading.span, Some(SourceSpan(3, 6)))
                match (heading.children()[0]) {
                    case text: Text => @Expect(text.span, Some(SourceSpan(5, 6)))
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
        match (result.document.children()[0]) {
            case heading: Heading => @Expect(heading.level, 1)
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
}
