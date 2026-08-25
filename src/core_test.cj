package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class CoreContractTest {
    @TestCase
    func freezesVersionedProfilesAndSafeDefault(): Unit {
        @Expect(MarkdownProfile.commonMark().id, "commonmark-0.31.2")
        @Expect(MarkdownProfile.gfm029().id, "gfm-0.29")
        @Expect(MarkdownProfile.gfm().id, "gfm-modern-v1")
        @Expect(HtmlPolicy.safe().rawHtmlPassThrough, false)
    }

    @TestCase
    func sourceSpansAreUtf8HalfOpenIntervals(): Unit {
        let source = SourceBuffer("A😀\r\n中\n")
        @Expect(source.byteLength(), 11)
        @Expect(source.slice(SourceSpan(1, 5)), "😀")
        @Expect(source.line(1), "A😀")
        @Expect(source.line(2), "中")
        @Expect(source.lineCount(), 3)
        @Expect(SourceSpan(0, 5).containsSpan(SourceSpan(1, 5)), true)
        @Expect(SourceSpan(1, 1).isEmpty(), true)
    }

    @TestCase
    func mapsUtf8OffsetsToSourceAndUtf16Positions(): Unit {
        let source = SourceBuffer("A😀\r\n中")
        @Expect(source.position(5), SourcePosition(1, 6))
        @Expect(source.utf16Position(5), Utf16Position(0, 3))
        @Expect(source.utf16Position(7), Utf16Position(1, 0))
        @Expect(source.utf16Position(10), Utf16Position(1, 1))
    }

    @TestCase
    func safeAndTrustedLimitsRemainBounded(): Unit {
        let safe = ParseLimits.safe()
        let trusted = ParseLimits.trusted()
        @Expect(safe.maximumInputBytes, 32 * 1024 * 1024)
        @Expect(safe.maximumNestingDepth, 256)
        @Expect(safe.maximumOutputBytes, 128 * 1024 * 1024)
        @Expect(trusted.maximumInputBytes > safe.maximumInputBytes, true)
    }

    @TestCase
    func cancellationAndBudgetUseStructuredErrors(): Unit {
        let source = CancellationSource()
        @Expect(source.token.isCancelled(), false)
        source.cancel()
        @Expect(source.token.isCancelled(), true)
        try {
            source.token.throwIfCancelled(phase: "parse")
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled => @Expect(error.phase, "parse")
                case _ => @Expect(false)
            }
        }

        let budget = OperationBudget(1, 0, 0, 0, 0, 0)
        budget.consumeScan()
        try {
            budget.consumeScan()
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(error.phase, "scan_steps")
                case _ => @Expect(false)
            }
        }
    }
}
