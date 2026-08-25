package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ProfileBehaviorSnapshotTest {
    @TestCase
    func gfmModernV1FreezesItsDeclaredExtensionComposition(): Unit {
        let source = "~~gone~~ www.example.com\n\n- [x] task\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\n<script>x</script>"
        let modern = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build().parse(source).document
        let html = HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(modern)
        @Expect(html.contains("<del>gone</del>"), true)
        @Expect(html.contains("href=\"http://www.example.com\""), true)
        @Expect(html.contains("task-list-item"), true)
        @Expect(html.contains("<table>"), true)
        @Expect(html.contains("&lt;script>x&lt;/script>"), true)

        let common = MarkdownEngine.builder().profile(MarkdownProfile.commonMark0312()).build().parse(source).document
        let commonHtml = HtmlRenderer(options: HtmlOptions.specCompatible()).render(common)
        @Expect(commonHtml.contains("<del>"), false)
        @Expect(commonHtml.contains("<table>"), false)
        @Expect(MarkdownProfile.gfm().sameIdentity(MarkdownProfile.gfmModernV1()), true)
        @Expect(MarkdownProfile.commonMark().sameIdentity(MarkdownProfile.commonMark0312()), true)
    }
}
