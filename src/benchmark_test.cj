package markdown

import std.unittest.*
import std.unittest.testmacro.*

// Release benchmark smoke suite. Cross-implementation threshold measurement is
// driven by benchmarks/measure.py so production code has no reference
// implementation dependency.
@Test
class MarkdownReleaseBenchmarks {
    private let commonmark = benchmarkCorpus(64)
    private let gfm = benchmarkGfmCorpus(64)
    private let large = benchmarkCorpus(4096)
    private let commonmarkEngine = MarkdownEngine.builder().profile(MarkdownProfile.commonMark0312()).build()
    private let gfmEngine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
    private var observed: Int64 = 0

    @Bench
    @Configure[batchSize: 1, minBatches: 3, warmup: 0]
    func commonmarkParseOnly(): Unit {
        observed = commonmarkEngine.parse(commonmark).document.children().size
    }

    @Bench
    @Configure[batchSize: 1, minBatches: 3, warmup: 0]
    func gfmParseAndHtml(): Unit {
        observed = HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(gfmEngine.parse(gfm).document).size
    }

    @Bench
    @Configure[batchSize: 1, minBatches: 3, warmup: 0]
    func linearGrowthCorpus(): Unit {
        observed = commonmarkEngine.parse(large).document.children().size
    }
}

private func benchmarkCorpus(repetitions: Int64): String {
    let out = StringBuilder()
    for (index in 0..repetitions) {
        out.append("## Section ${index}\n\n")
        out.append("CJK 中文 😀 text with [link](https://example.com/${index}) and `code`.\n\n")
        out.append("> quote\n> - nested item\n\n")
        out.append("```cj\nlet value = ${index}\n```\n\n")
    }
    out.toString()
}

private func benchmarkGfmCorpus(repetitions: Int64): String {
    let out = StringBuilder()
    for (index in 0..repetitions) {
        out.append("| name | value |\n| :--- | ---: |\n| row ${index} | ${index} |\n\n")
        out.append("- [x] task ${index}\n- [ ] pending\n\n")
        out.append("~~strike~~ https://example.com/${index}\n\n")
    }
    out.toString()
}
