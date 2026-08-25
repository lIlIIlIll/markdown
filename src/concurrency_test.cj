package markdown

import std.collection.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ConcurrencyContractTest {
    @TestCase
    func immutableEngineAndDocumentSupportConcurrentReadOnlyUse(): Unit {
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        let source = "# Shared\n\n- [x] **safe**\n\n| a | b |\n| - | - |\n| 1 | 2 |"
        let expected = HtmlRenderer().render(engine.parse(source).document)
        let parses = ArrayList<Future<String>>()
        for (_ in 0..16) {
            parses.add(spawn {HtmlRenderer().render(engine.parse(source).document)})
        }
        for (future in parses) {
            @Expect(future.get(), expected)
        }

        let document = engine.parse(source).document
        let readers = ArrayList<Future<Int64>>()
        for (_ in 0..16) {
            readers.add(spawn {AstQuery.descendants(document).size})
        }
        let expectedNodes = AstQuery.descendants(document).size
        for (future in readers) {
            @Expect(future.get(), expectedNodes)
        }
    }

    @TestCase
    func cancellationRaceStopsAnAlreadyStartedParse(): Unit {
        let sourceText = StringBuilder()
        for (_ in 0..400000) {
            sourceText.append("[*_~<")
        }
        let source = sourceText.toString()
        let engine = MarkdownEngine.builder().limits(ParseLimits.trusted()).build()
        let cancellation = CancellationSource()
        let started = AtomicBool(false)
        let future: Future<Bool> = spawn {
            started.store(true)
            try {
                engine.parse(source, cancellation: cancellation.token)
                false
            } catch (error: MarkdownException) {
                match (error.code) {
                    case MarkdownErrorCode.Cancelled => true;
                    case _ => false
                }
            }
        }
        while (!started.load()) {}
        cancellation.cancel()
        @Expect(future.get(), true)
    }
}
