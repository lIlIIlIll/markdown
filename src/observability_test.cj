package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ObservabilityTest {
    @TestCase
    func statisticsAreExplicitLocalAndContentFree(): Unit {
        let engine = MarkdownEngine.builder().build()
        let observed = engine.parseObserved("# secret\n\n[text](https://private.invalid)")
        @Expect(observed.statistics.inputBytes > 0, true)
        @Expect(observed.statistics.nodeCount > 0, true)
        @Expect(observed.statistics.maxDepth > 0, true)
        @Expect(observed.statistics.scanSteps > 0, true)
        @Expect(observed.statistics.parseDurationNanos.isNone(), true)
        @Expect(observed.statistics.profileId, "commonmark-0.31.2")

        let timed = engine.parseObserved("x", options: StatisticsOptions(timing: true))
        @Expect(timed.statistics.parseDurationNanos.isSome(), true)
        let rendered = HtmlRenderer().renderObserved(timed.result.document, options: StatisticsOptions(timing: true))
        @Expect(rendered.statistics.outputBytes, rendered.content.size)
        @Expect(rendered.statistics.renderedNodes > 0, true)
        @Expect(rendered.statistics.renderDurationNanos.isSome(), true)
        @Expect(rendered.statistics.rendererFingerprint.size, 64)
    }
}
