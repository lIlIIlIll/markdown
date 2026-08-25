package markdown

import std.unittest.*
import std.unittest.testmacro.*

// Generated from pinned official spec.txt; do not edit by hand.
@Test
class Gfm029ConformanceTest {
    @TestCase
    func example0001(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\tfoo\tbaz\t\tbim\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n")
    }

    @TestCase
    func example0002(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  \tfoo\tbaz\t\tbim\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo\tbaz\t\tbim\n</code></pre>\n")
    }

    @TestCase
    func example0003(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    a\ta\n    ὐ\ta\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>a\ta\nὐ\ta\n</code></pre>\n")
    }

    @TestCase
    func example0004(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  - foo\n\n\tbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0005(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n\n\t\tbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<pre><code>  bar\n</code></pre>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0006(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">\t\tfoo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<pre><code>  foo\n</code></pre>\n</blockquote>\n")
    }

    @TestCase
    func example0007(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-\t\tfoo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<pre><code>  foo\n</code></pre>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0008(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    foo\n\tbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo\nbar\n</code></pre>\n")
    }

    @TestCase
    func example0009(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" - foo\n   - bar\n\t - baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo\n<ul>\n<li>bar\n<ul>\n<li>baz</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0010(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("#\tFoo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>Foo</h1>\n")
    }

    @TestCase
    func example0011(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*\t*\t*\t\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n")
    }

    @TestCase
    func example0012(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- `one\n- two`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>`one</li>\n<li>two`</li>\n</ul>\n")
    }

    @TestCase
    func example0013(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("***\n---\n___\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n<hr />\n<hr />\n")
    }

    @TestCase
    func example0014(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("+++\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>+++</p>\n")
    }

    @TestCase
    func example0015(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("===\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>===</p>\n")
    }

    @TestCase
    func example0016(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("--\n**\n__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>--\n**\n__</p>\n")
    }

    @TestCase
    func example0017(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" ***\n  ***\n   ***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n<hr />\n<hr />\n")
    }

    @TestCase
    func example0018(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    ***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>***\n</code></pre>\n")
    }

    @TestCase
    func example0019(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n    ***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\n***</p>\n")
    }

    @TestCase
    func example0020(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_____________________________________\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n")
    }

    @TestCase
    func example0021(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" - - -\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n")
    }

    @TestCase
    func example0022(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" **  * ** * ** * **\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n")
    }

    @TestCase
    func example0023(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-     -      -      -\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n")
    }

    @TestCase
    func example0024(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- - - -    \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n")
    }

    @TestCase
    func example0025(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_ _ _ _ a\n\na------\n\n---a---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_ _ _ _ a</p>\n<p>a------</p>\n<p>---a---</p>\n")
    }

    @TestCase
    func example0026(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" *-*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>-</em></p>\n")
    }

    @TestCase
    func example0027(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n***\n- bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n</ul>\n<hr />\n<ul>\n<li>bar</li>\n</ul>\n")
    }

    @TestCase
    func example0028(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n***\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo</p>\n<hr />\n<p>bar</p>\n")
    }

    @TestCase
    func example0029(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n---\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo</h2>\n<p>bar</p>\n")
    }

    @TestCase
    func example0030(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("* Foo\n* * *\n* Bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>Foo</li>\n</ul>\n<hr />\n<ul>\n<li>Bar</li>\n</ul>\n")
    }

    @TestCase
    func example0031(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- Foo\n- * * *\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>Foo</li>\n<li>\n<hr />\n</li>\n</ul>\n")
    }

    @TestCase
    func example0032(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("# foo\n## foo\n### foo\n#### foo\n##### foo\n###### foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>foo</h1>\n<h2>foo</h2>\n<h3>foo</h3>\n<h4>foo</h4>\n<h5>foo</h5>\n<h6>foo</h6>\n")
    }

    @TestCase
    func example0033(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("####### foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>####### foo</p>\n")
    }

    @TestCase
    func example0034(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("#5 bolt\n\n#hashtag\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>#5 bolt</p>\n<p>#hashtag</p>\n")
    }

    @TestCase
    func example0035(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\\## foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>## foo</p>\n")
    }

    @TestCase
    func example0036(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("# foo *bar* \\*baz\\*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>foo <em>bar</em> *baz*</h1>\n")
    }

    @TestCase
    func example0037(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("#                  foo                     \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>foo</h1>\n")
    }

    @TestCase
    func example0038(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" ### foo\n  ## foo\n   # foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h3>foo</h3>\n<h2>foo</h2>\n<h1>foo</h1>\n")
    }

    @TestCase
    func example0039(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    # foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code># foo\n</code></pre>\n")
    }

    @TestCase
    func example0040(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\n    # bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo\n# bar</p>\n")
    }

    @TestCase
    func example0041(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("## foo ##\n  ###   bar    ###\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>foo</h2>\n<h3>bar</h3>\n")
    }

    @TestCase
    func example0042(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("# foo ##################################\n##### foo ##\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>foo</h1>\n<h5>foo</h5>\n")
    }

    @TestCase
    func example0043(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("### foo ###     \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h3>foo</h3>\n")
    }

    @TestCase
    func example0044(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("### foo ### b\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h3>foo ### b</h3>\n")
    }

    @TestCase
    func example0045(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("# foo#\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>foo#</h1>\n")
    }

    @TestCase
    func example0046(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("### foo \\###\n## foo #\\##\n# foo \\#\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h3>foo ###</h3>\n<h2>foo ###</h2>\n<h1>foo #</h1>\n")
    }

    @TestCase
    func example0047(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("****\n## foo\n****\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n<h2>foo</h2>\n<hr />\n")
    }

    @TestCase
    func example0048(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo bar\n# baz\nBar foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo bar</p>\n<h1>baz</h1>\n<p>Bar foo</p>\n")
    }

    @TestCase
    func example0049(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("## \n#\n### ###\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2></h2>\n<h1></h1>\n<h3></h3>\n")
    }

    @TestCase
    func example0050(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo *bar*\n=========\n\nFoo *bar*\n---------\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>Foo <em>bar</em></h1>\n<h2>Foo <em>bar</em></h2>\n")
    }

    @TestCase
    func example0051(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo *bar\nbaz*\n====\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>Foo <em>bar\nbaz</em></h1>\n")
    }

    @TestCase
    func example0052(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  Foo *bar\nbaz*\t\n====\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>Foo <em>bar\nbaz</em></h1>\n")
    }

    @TestCase
    func example0053(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n-------------------------\n\nFoo\n=\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo</h2>\n<h1>Foo</h1>\n")
    }

    @TestCase
    func example0054(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   Foo\n---\n\n  Foo\n-----\n\n  Foo\n  ===\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo</h2>\n<h2>Foo</h2>\n<h1>Foo</h1>\n")
    }

    @TestCase
    func example0055(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    Foo\n    ---\n\n    Foo\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>Foo\n---\n\nFoo\n</code></pre>\n<hr />\n")
    }

    @TestCase
    func example0056(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n   ----      \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo</h2>\n")
    }

    @TestCase
    func example0057(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n    ---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\n---</p>\n")
    }

    @TestCase
    func example0058(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n= =\n\nFoo\n--- -\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\n= =</p>\n<p>Foo</p>\n<hr />\n")
    }

    @TestCase
    func example0059(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo  \n-----\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo</h2>\n")
    }

    @TestCase
    func example0060(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\\\n----\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo\\</h2>\n")
    }

    @TestCase
    func example0061(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`Foo\n----\n`\n\n<a title=\"a lot\n---\nof dashes\"/>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>`Foo</h2>\n<p>`</p>\n<h2>&lt;a title=&quot;a lot</h2>\n<p>of dashes&quot;/&gt;</p>\n")
    }

    @TestCase
    func example0062(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> Foo\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>Foo</p>\n</blockquote>\n<hr />\n")
    }

    @TestCase
    func example0063(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\nbar\n===\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo\nbar\n===</p>\n</blockquote>\n")
    }

    @TestCase
    func example0064(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- Foo\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>Foo</li>\n</ul>\n<hr />\n")
    }

    @TestCase
    func example0065(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\nBar\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>Foo\nBar</h2>\n")
    }

    @TestCase
    func example0066(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("---\nFoo\n---\nBar\n---\nBaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n<h2>Foo</h2>\n<h2>Bar</h2>\n<p>Baz</p>\n")
    }

    @TestCase
    func example0067(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\n====\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>====</p>\n")
    }

    @TestCase
    func example0068(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("---\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<hr />\n<hr />\n")
    }

    @TestCase
    func example0069(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n-----\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n</ul>\n<hr />\n")
    }

    @TestCase
    func example0070(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    foo\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo\n</code></pre>\n<hr />\n")
    }

    @TestCase
    func example0071(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\n-----\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo</p>\n</blockquote>\n<hr />\n")
    }

    @TestCase
    func example0072(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\\> foo\n------\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>&gt; foo</h2>\n")
    }

    @TestCase
    func example0073(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n\nbar\n---\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo</p>\n<h2>bar</h2>\n<p>baz</p>\n")
    }

    @TestCase
    func example0074(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\nbar\n\n---\n\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\nbar</p>\n<hr />\n<p>baz</p>\n")
    }

    @TestCase
    func example0075(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\nbar\n* * *\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\nbar</p>\n<hr />\n<p>baz</p>\n")
    }

    @TestCase
    func example0076(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\nbar\n\\---\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\nbar\n---\nbaz</p>\n")
    }

    @TestCase
    func example0077(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    a simple\n      indented code block\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>a simple\n  indented code block\n</code></pre>\n")
    }

    @TestCase
    func example0078(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  - foo\n\n    bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0079(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1.  foo\n\n    - bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>foo</p>\n<ul>\n<li>bar</li>\n</ul>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0080(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    <a/>\n    *hi*\n\n    - one\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>&lt;a/&gt;\n*hi*\n\n- one\n</code></pre>\n")
    }

    @TestCase
    func example0081(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    chunk1\n\n    chunk2\n  \n \n \n    chunk3\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>chunk1\n\nchunk2\n\n\n\nchunk3\n</code></pre>\n")
    }

    @TestCase
    func example0082(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    chunk1\n      \n      chunk2\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>chunk1\n  \n  chunk2\n</code></pre>\n")
    }

    @TestCase
    func example0083(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n    bar\n\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\nbar</p>\n")
    }

    @TestCase
    func example0084(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    foo\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo\n</code></pre>\n<p>bar</p>\n")
    }

    @TestCase
    func example0085(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("# Heading\n    foo\nHeading\n------\n    foo\n----\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>Heading</h1>\n<pre><code>foo\n</code></pre>\n<h2>Heading</h2>\n<pre><code>foo\n</code></pre>\n<hr />\n")
    }

    @TestCase
    func example0086(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("        foo\n    bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>    foo\nbar\n</code></pre>\n")
    }

    @TestCase
    func example0087(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\n    \n    foo\n    \n\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo\n</code></pre>\n")
    }

    @TestCase
    func example0088(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    foo  \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>foo  \n</code></pre>\n")
    }

    @TestCase
    func example0089(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\n<\n >\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>&lt;\n &gt;\n</code></pre>\n")
    }

    @TestCase
    func example0090(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~\n<\n >\n~~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>&lt;\n &gt;\n</code></pre>\n")
    }

    @TestCase
    func example0091(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``\nfoo\n``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo</code></p>\n")
    }

    @TestCase
    func example0092(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\naaa\n~~~\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n~~~\n</code></pre>\n")
    }

    @TestCase
    func example0093(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~\naaa\n```\n~~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n```\n</code></pre>\n")
    }

    @TestCase
    func example0094(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("````\naaa\n```\n``````\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n```\n</code></pre>\n")
    }

    @TestCase
    func example0095(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~~\naaa\n~~~\n~~~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n~~~\n</code></pre>\n")
    }

    @TestCase
    func example0096(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code></code></pre>\n")
    }

    @TestCase
    func example0097(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`````\n\n```\naaa\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>\n```\naaa\n</code></pre>\n")
    }

    @TestCase
    func example0098(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> ```\n> aaa\n\nbbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<pre><code>aaa\n</code></pre>\n</blockquote>\n<p>bbb</p>\n")
    }

    @TestCase
    func example0099(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\n\n  \n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>\n  \n</code></pre>\n")
    }

    @TestCase
    func example0100(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code></code></pre>\n")
    }

    @TestCase
    func example0101(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" ```\n aaa\naaa\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\naaa\n</code></pre>\n")
    }

    @TestCase
    func example0102(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  ```\naaa\n  aaa\naaa\n  ```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\naaa\naaa\n</code></pre>\n")
    }

    @TestCase
    func example0103(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   ```\n   aaa\n    aaa\n  aaa\n   ```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n aaa\naaa\n</code></pre>\n")
    }

    @TestCase
    func example0104(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    ```\n    aaa\n    ```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>```\naaa\n```\n</code></pre>\n")
    }

    @TestCase
    func example0105(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\naaa\n  ```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n</code></pre>\n")
    }

    @TestCase
    func example0106(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   ```\naaa\n  ```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n</code></pre>\n")
    }

    @TestCase
    func example0107(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\naaa\n    ```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n    ```\n</code></pre>\n")
    }

    @TestCase
    func example0108(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``` ```\naaa\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code> </code>\naaa</p>\n")
    }

    @TestCase
    func example0109(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~~~~\naaa\n~~~ ~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n~~~ ~~\n</code></pre>\n")
    }

    @TestCase
    func example0110(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\n```\nbar\n```\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo</p>\n<pre><code>bar\n</code></pre>\n<p>baz</p>\n")
    }

    @TestCase
    func example0111(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\n---\n~~~\nbar\n~~~\n# baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h2>foo</h2>\n<pre><code>bar\n</code></pre>\n<h1>baz</h1>\n")
    }

    @TestCase
    func example0112(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```ruby\ndef foo(x)\n  return 3\nend\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code class=\"language-ruby\">def foo(x)\n  return 3\nend\n</code></pre>\n")
    }

    @TestCase
    func example0113(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~~    ruby startline=3 $%@#$\ndef foo(x)\n  return 3\nend\n~~~~~~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code class=\"language-ruby\">def foo(x)\n  return 3\nend\n</code></pre>\n")
    }

    @TestCase
    func example0114(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("````;\n````\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code class=\"language-;\"></code></pre>\n")
    }

    @TestCase
    func example0115(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``` aa ```\nfoo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>aa</code>\nfoo</p>\n")
    }

    @TestCase
    func example0116(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~ aa ``` ~~~\nfoo\n~~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code class=\"language-aa\">foo\n</code></pre>\n")
    }

    @TestCase
    func example0117(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\n``` aaa\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>``` aaa\n</code></pre>\n")
    }

    @TestCase
    func example0118(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<table><tr><td>\n<pre>\n**Hello**,\n\n_world_.\n</pre>\n</td></tr></table>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<table><tr><td>\n<pre>\n**Hello**,\n<p><em>world</em>.\n</pre></p>\n</td></tr></table>\n")
    }

    @TestCase
    func example0119(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<table>\n  <tr>\n    <td>\n           hi\n    </td>\n  </tr>\n</table>\n\nokay.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<table>\n  <tr>\n    <td>\n           hi\n    </td>\n  </tr>\n</table>\n<p>okay.</p>\n")
    }

    @TestCase
    func example0120(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" <div>\n  *hello*\n         <foo><a>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), " <div>\n  *hello*\n         <foo><a>\n")
    }

    @TestCase
    func example0121(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("</div>\n*foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "</div>\n*foo*\n")
    }

    @TestCase
    func example0122(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<DIV CLASS=\"foo\">\n\n*Markdown*\n\n</DIV>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<DIV CLASS=\"foo\">\n<p><em>Markdown</em></p>\n</DIV>\n")
    }

    @TestCase
    func example0123(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div id=\"foo\"\n  class=\"bar\">\n</div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div id=\"foo\"\n  class=\"bar\">\n</div>\n")
    }

    @TestCase
    func example0124(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div id=\"foo\" class=\"bar\n  baz\">\n</div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div id=\"foo\" class=\"bar\n  baz\">\n</div>\n")
    }

    @TestCase
    func example0125(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div>\n*foo*\n\n*bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div>\n*foo*\n<p><em>bar</em></p>\n")
    }

    @TestCase
    func example0126(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div id=\"foo\"\n*hi*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div id=\"foo\"\n*hi*\n")
    }

    @TestCase
    func example0127(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div class\nfoo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div class\nfoo\n")
    }

    @TestCase
    func example0128(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div *???-&&&-<---\n*foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div *???-&&&-<---\n*foo*\n")
    }

    @TestCase
    func example0129(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div><a href=\"bar\">*foo*</a></div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div><a href=\"bar\">*foo*</a></div>\n")
    }

    @TestCase
    func example0130(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<table><tr><td>\nfoo\n</td></tr></table>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<table><tr><td>\nfoo\n</td></tr></table>\n")
    }

    @TestCase
    func example0131(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div></div>\n``` c\nint x = 33;\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div></div>\n``` c\nint x = 33;\n```\n")
    }

    @TestCase
    func example0132(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"foo\">\n*bar*\n</a>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<a href=\"foo\">\n*bar*\n</a>\n")
    }

    @TestCase
    func example0133(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<Warning>\n*bar*\n</Warning>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<Warning>\n*bar*\n</Warning>\n")
    }

    @TestCase
    func example0134(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<i class=\"foo\">\n*bar*\n</i>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<i class=\"foo\">\n*bar*\n</i>\n")
    }

    @TestCase
    func example0135(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("</ins>\n*bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "</ins>\n*bar*\n")
    }

    @TestCase
    func example0136(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<del>\n*foo*\n</del>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<del>\n*foo*\n</del>\n")
    }

    @TestCase
    func example0137(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<del>\n\n*foo*\n\n</del>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<del>\n<p><em>foo</em></p>\n</del>\n")
    }

    @TestCase
    func example0138(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<del>*foo*</del>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><del><em>foo</em></del></p>\n")
    }

    @TestCase
    func example0139(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "<pre language=\"haskell\"><code>\nimport Text.HTML.TagSoup\n\nmain :: IO ()\nmain = print $ parseTags tags\n</code></pre>\nokay\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre language=\"haskell\"><code>\nimport Text.HTML.TagSoup\n\nmain :: IO ()\nmain = print $ parseTags tags\n</code></pre>\n<p>okay</p>\n")
    }

    @TestCase
    func example0140(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "<script type=\"text/javascript\">\n// JavaScript example\n\ndocument.getElementById(\"demo\").innerHTML = \"Hello JavaScript!\";\n</script>\nokay\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<script type=\"text/javascript\">\n// JavaScript example\n\ndocument.getElementById(\"demo\").innerHTML = \"Hello JavaScript!\";\n</script>\n<p>okay</p>\n")
    }

    @TestCase
    func example0141(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<style\n  type=\"text/css\">\nh1 {color:red;}\n\np {color:blue;}\n</style>\nokay\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<style\n  type=\"text/css\">\nh1 {color:red;}\n\np {color:blue;}\n</style>\n<p>okay</p>\n")
    }

    @TestCase
    func example0142(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<style\n  type=\"text/css\">\n\nfoo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<style\n  type=\"text/css\">\n\nfoo\n")
    }

    @TestCase
    func example0143(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> <div>\n> foo\n\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<div>\nfoo\n</blockquote>\n<p>bar</p>\n")
    }

    @TestCase
    func example0144(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- <div>\n- foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<div>\n</li>\n<li>foo</li>\n</ul>\n")
    }

    @TestCase
    func example0145(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<style>p{color:red;}</style>\n*foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<style>p{color:red;}</style>\n<p><em>foo</em></p>\n")
    }

    @TestCase
    func example0146(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<!-- foo -->*bar*\n*baz*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<!-- foo -->*bar*\n<p><em>baz</em></p>\n")
    }

    @TestCase
    func example0147(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<script>\nfoo\n</script>1. *bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<script>\nfoo\n</script>1. *bar*\n")
    }

    @TestCase
    func example0148(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<!-- Foo\n\nbar\n   baz -->\nokay\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<!-- Foo\n\nbar\n   baz -->\n<p>okay</p>\n")
    }

    @TestCase
    func example0149(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<?php\n\n  echo '>';\n\n?>\nokay\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<?php\n\n  echo '>';\n\n?>\n<p>okay</p>\n")
    }

    @TestCase
    func example0150(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<!DOCTYPE html>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<!DOCTYPE html>\n")
    }

    @TestCase
    func example0151(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "<![CDATA[\nfunction matchwo(a,b)\n{\n  if (a < b && a < 0) then {\n    return 1;\n\n  } else {\n\n    return 0;\n  }\n}\n]]>\nokay\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<![CDATA[\nfunction matchwo(a,b)\n{\n  if (a < b && a < 0) then {\n    return 1;\n\n  } else {\n\n    return 0;\n  }\n}\n]]>\n<p>okay</p>\n")
    }

    @TestCase
    func example0152(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  <!-- foo -->\n\n    <!-- foo -->\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "  <!-- foo -->\n<pre><code>&lt;!-- foo --&gt;\n</code></pre>\n")
    }

    @TestCase
    func example0153(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  <div>\n\n    <div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "  <div>\n<pre><code>&lt;div&gt;\n</code></pre>\n")
    }

    @TestCase
    func example0154(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n<div>\nbar\n</div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo</p>\n<div>\nbar\n</div>\n")
    }

    @TestCase
    func example0155(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div>\nbar\n</div>\n*foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div>\nbar\n</div>\n*foo*\n")
    }

    @TestCase
    func example0156(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n<a href=\"bar\">\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\n<a href=\"bar\">\nbaz</p>\n")
    }

    @TestCase
    func example0157(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div>\n\n*Emphasized* text.\n\n</div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div>\n<p><em>Emphasized</em> text.</p>\n</div>\n")
    }

    @TestCase
    func example0158(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<div>\n*Emphasized* text.\n</div>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<div>\n*Emphasized* text.\n</div>\n")
    }

    @TestCase
    func example0159(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<table>\n\n<tr>\n\n<td>\nHi\n</td>\n\n</tr>\n\n</table>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<table>\n<tr>\n<td>\nHi\n</td>\n</tr>\n</table>\n")
    }

    @TestCase
    func example0160(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<table>\n\n  <tr>\n\n    <td>\n      Hi\n    </td>\n\n  </tr>\n\n</table>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<table>\n  <tr>\n<pre><code>&lt;td&gt;\n  Hi\n&lt;/td&gt;\n</code></pre>\n  </tr>\n</table>\n")
    }

    @TestCase
    func example0161(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url \"title\"\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">foo</a></p>\n")
    }

    @TestCase
    func example0162(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   [foo]: \n      /url  \n           'the title'  \n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"the title\">foo</a></p>\n")
    }

    @TestCase
    func example0163(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[Foo*bar\\]]:my_(url) 'title (with parens)'\n\n[Foo*bar\\]]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"my_(url)\" title=\"title (with parens)\">Foo*bar]</a></p>\n")
    }

    @TestCase
    func example0164(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[Foo bar]:\n<my url>\n'title'\n\n[Foo bar]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"my%20url\" title=\"title\">Foo bar</a></p>\n")
    }

    @TestCase
    func example0165(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url '\ntitle\nline1\nline2\n'\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"\ntitle\nline1\nline2\n\">foo</a></p>\n")
    }

    @TestCase
    func example0166(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url 'title\n\nwith blank line'\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]: /url 'title</p>\n<p>with blank line'</p>\n<p>[foo]</p>\n")
    }

    @TestCase
    func example0167(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]:\n/url\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\">foo</a></p>\n")
    }

    @TestCase
    func example0168(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]:\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]:</p>\n<p>[foo]</p>\n")
    }

    @TestCase
    func example0169(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: <>\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"\">foo</a></p>\n")
    }

    @TestCase
    func example0170(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: <bar>(baz)\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]: <bar>(baz)</p>\n<p>[foo]</p>\n")
    }

    @TestCase
    func example0171(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url\\bar\\*baz \"foo\\\"bar\\baz\"\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url%5Cbar*baz\" title=\"foo&quot;bar\\baz\">foo</a></p>\n")
    }

    @TestCase
    func example0172(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n\n[foo]: url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"url\">foo</a></p>\n")
    }

    @TestCase
    func example0173(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n\n[foo]: first\n[foo]: second\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"first\">foo</a></p>\n")
    }

    @TestCase
    func example0174(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[FOO]: /url\n\n[Foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\">Foo</a></p>\n")
    }

    @TestCase
    func example0175(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[ΑΓΩ]: /φου\n\n[αγω]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/%CF%86%CE%BF%CF%85\">αγω</a></p>\n")
    }

    @TestCase
    func example0176(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "")
    }

    @TestCase
    func example0177(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[\nfoo\n]: /url\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>bar</p>\n")
    }

    @TestCase
    func example0178(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url \"title\" ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]: /url &quot;title&quot; ok</p>\n")
    }

    @TestCase
    func example0179(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url\n\"title\" ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&quot;title&quot; ok</p>\n")
    }

    @TestCase
    func example0180(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    [foo]: /url \"title\"\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>[foo]: /url &quot;title&quot;\n</code></pre>\n<p>[foo]</p>\n")
    }

    @TestCase
    func example0181(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```\n[foo]: /url\n```\n\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>[foo]: /url\n</code></pre>\n<p>[foo]</p>\n")
    }

    @TestCase
    func example0182(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n[bar]: /baz\n\n[bar]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo\n[bar]: /baz</p>\n<p>[bar]</p>\n")
    }

    @TestCase
    func example0183(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("# [Foo]\n[foo]: /url\n> bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1><a href=\"/url\">Foo</a></h1>\n<blockquote>\n<p>bar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0184(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url\nbar\n===\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h1>bar</h1>\n<p><a href=\"/url\">foo</a></p>\n")
    }

    @TestCase
    func example0185(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url\n===\n[foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>===\n<a href=\"/url\">foo</a></p>\n")
    }

    @TestCase
    func example0186(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /foo-url \"foo\"\n[bar]: /bar-url\n  \"bar\"\n[baz]: /baz-url\n\n[foo],\n[bar],\n[baz]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/foo-url\" title=\"foo\">foo</a>,\n<a href=\"/bar-url\" title=\"bar\">bar</a>,\n<a href=\"/baz-url\">baz</a></p>\n")
    }

    @TestCase
    func example0187(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n\n> [foo]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\">foo</a></p>\n<blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0188(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "")
    }

    @TestCase
    func example0189(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("aaa\n\nbbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa</p>\n<p>bbb</p>\n")
    }

    @TestCase
    func example0190(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("aaa\nbbb\n\nccc\nddd\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa\nbbb</p>\n<p>ccc\nddd</p>\n")
    }

    @TestCase
    func example0191(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("aaa\n\n\nbbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa</p>\n<p>bbb</p>\n")
    }

    @TestCase
    func example0192(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  aaa\n bbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa\nbbb</p>\n")
    }

    @TestCase
    func example0193(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("aaa\n             bbb\n                                       ccc\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa\nbbb\nccc</p>\n")
    }

    @TestCase
    func example0194(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   aaa\nbbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa\nbbb</p>\n")
    }

    @TestCase
    func example0195(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    aaa\nbbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>aaa\n</code></pre>\n<p>bbb</p>\n")
    }

    @TestCase
    func example0196(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("aaa     \nbbb     \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa<br />\nbbb</p>\n")
    }

    @TestCase
    func example0197(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  \n\naaa\n  \n\n# aaa\n\n  \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aaa</p>\n<h1>aaa</h1>\n")
    }

    @TestCase
    func example0198(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| foo | bar |\n| --- | --- |\n| baz | bim |\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th>foo</th>\n<th>bar</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>baz</td>\n<td>bim</td>\n</tr>\n</tbody>\n</table>\n")
    }

    @TestCase
    func example0199(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| abc | defghi |\n:-: | -----------:\nbar | baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th align=\"center\">abc</th>\n<th align=\"right\">defghi</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"center\">bar</td>\n<td align=\"right\">baz</td>\n</tr>\n</tbody>\n</table>\n")
    }

    @TestCase
    func example0200(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| f\\|oo  |\n| ------ |\n| b `\\|` az |\n| b **\\|** im |\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th>f|oo</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b <code>|</code> az</td>\n</tr>\n<tr>\n<td>b <strong>|</strong> im</td>\n</tr>\n</tbody>\n</table>\n")
    }

    @TestCase
    func example0201(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| abc | def |\n| --- | --- |\n| bar | baz |\n> bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>bar</td>\n<td>baz</td>\n</tr>\n</tbody>\n</table>\n<blockquote>\n<p>bar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0202(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| abc | def |\n| --- | --- |\n| bar | baz |\nbar\n\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>bar</td>\n<td>baz</td>\n</tr>\n<tr>\n<td>bar</td>\n<td></td>\n</tr>\n</tbody>\n</table>\n<p>bar</p>\n")
    }

    @TestCase
    func example0203(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| abc | def |\n| --- |\n| bar |\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p>| abc | def |\n| --- |\n| bar |</p>\n")
    }

    @TestCase
    func example0204(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| abc | def |\n| --- | --- |\n| bar |\n| bar | baz | boo |\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>bar</td>\n<td></td>\n</tr>\n<tr>\n<td>bar</td>\n<td>baz</td>\n</tr>\n</tbody>\n</table>\n")
    }

    @TestCase
    func example0205(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("| abc | def |\n| --- | --- |\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<table>\n<thead>\n<tr>\n<th>abc</th>\n<th>def</th>\n</tr>\n</thead>\n</table>\n")
    }

    @TestCase
    func example0206(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> # Foo\n> bar\n> baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n")
    }

    @TestCase
    func example0207(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("># Foo\n>bar\n> baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n")
    }

    @TestCase
    func example0208(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   > # Foo\n   > bar\n > baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n")
    }

    @TestCase
    func example0209(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    > # Foo\n    > bar\n    > baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>&gt; # Foo\n&gt; bar\n&gt; baz\n</code></pre>\n")
    }

    @TestCase
    func example0210(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> # Foo\n> bar\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n")
    }

    @TestCase
    func example0211(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> bar\nbaz\n> foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>bar\nbaz\nfoo</p>\n</blockquote>\n")
    }

    @TestCase
    func example0212(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\n---\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo</p>\n</blockquote>\n<hr />\n")
    }

    @TestCase
    func example0213(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> - foo\n- bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<ul>\n<li>foo</li>\n</ul>\n</blockquote>\n<ul>\n<li>bar</li>\n</ul>\n")
    }

    @TestCase
    func example0214(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">     foo\n    bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<pre><code>foo\n</code></pre>\n</blockquote>\n<pre><code>bar\n</code></pre>\n")
    }

    @TestCase
    func example0215(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> ```\nfoo\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<pre><code></code></pre>\n</blockquote>\n<p>foo</p>\n<pre><code></code></pre>\n")
    }

    @TestCase
    func example0216(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\n    - bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo\n- bar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0217(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0218(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">\n>  \n> \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0219(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">\n> foo\n>  \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo</p>\n</blockquote>\n")
    }

    @TestCase
    func example0220(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\n\n> bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo</p>\n</blockquote>\n<blockquote>\n<p>bar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0221(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\n> bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo\nbar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0222(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> foo\n>\n> bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>foo</p>\n<p>bar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0223(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\n> bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo</p>\n<blockquote>\n<p>bar</p>\n</blockquote>\n")
    }

    @TestCase
    func example0224(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> aaa\n***\n> bbb\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>aaa</p>\n</blockquote>\n<hr />\n<blockquote>\n<p>bbb</p>\n</blockquote>\n")
    }

    @TestCase
    func example0225(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> bar\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>bar\nbaz</p>\n</blockquote>\n")
    }

    @TestCase
    func example0226(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> bar\n\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>bar</p>\n</blockquote>\n<p>baz</p>\n")
    }

    @TestCase
    func example0227(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> bar\n>\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<p>bar</p>\n</blockquote>\n<p>baz</p>\n")
    }

    @TestCase
    func example0228(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> > > foo\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<blockquote>\n<blockquote>\n<p>foo\nbar</p>\n</blockquote>\n</blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0229(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">>> foo\n> bar\n>>baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<blockquote>\n<blockquote>\n<p>foo\nbar\nbaz</p>\n</blockquote>\n</blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0230(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">     code\n\n>    not code\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n<blockquote>\n<p>not code</p>\n</blockquote>\n")
    }

    @TestCase
    func example0231(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("A paragraph\nwith two lines.\n\n    indented code\n\n> A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n")
    }

    @TestCase
    func example0232(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1.  A paragraph\n    with two lines.\n\n        indented code\n\n    > A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0233(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- one\n\n two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>one</li>\n</ul>\n<p>two</p>\n")
    }

    @TestCase
    func example0234(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- one\n\n  two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0235(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" -    one\n\n     two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>one</li>\n</ul>\n<pre><code> two\n</code></pre>\n")
    }

    @TestCase
    func example0236(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" -    one\n\n      two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0237(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   > > 1.  one\n>>\n>>     two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<blockquote>\n<ol>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ol>\n</blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0238(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(">>- one\n>>\n  >  > two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<blockquote>\n<ul>\n<li>one</li>\n</ul>\n<p>two</p>\n</blockquote>\n</blockquote>\n")
    }

    @TestCase
    func example0239(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-one\n\n2.two\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>-one</p>\n<p>2.two</p>\n")
    }

    @TestCase
    func example0240(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n\n\n  bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0241(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1.  foo\n\n    ```\n    bar\n    ```\n\n    baz\n\n    > bam\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>foo</p>\n<pre><code>bar\n</code></pre>\n<p>baz</p>\n<blockquote>\n<p>bam</p>\n</blockquote>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0242(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- Foo\n\n      bar\n\n\n      baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>Foo</p>\n<pre><code>bar\n\n\nbaz\n</code></pre>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0243(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("123456789. ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol start=\"123456789\">\n<li>ok</li>\n</ol>\n")
    }

    @TestCase
    func example0244(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1234567890. not ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>1234567890. not ok</p>\n")
    }

    @TestCase
    func example0245(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("0. ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol start=\"0\">\n<li>ok</li>\n</ol>\n")
    }

    @TestCase
    func example0246(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("003. ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol start=\"3\">\n<li>ok</li>\n</ol>\n")
    }

    @TestCase
    func example0247(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-1. not ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>-1. not ok</p>\n")
    }

    @TestCase
    func example0248(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n\n      bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<pre><code>bar\n</code></pre>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0249(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  10.  foo\n\n           bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol start=\"10\">\n<li>\n<p>foo</p>\n<pre><code>bar\n</code></pre>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0250(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    indented code\n\nparagraph\n\n    more code\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>indented code\n</code></pre>\n<p>paragraph</p>\n<pre><code>more code\n</code></pre>\n")
    }

    @TestCase
    func example0251(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1.     indented code\n\n   paragraph\n\n       more code\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<pre><code>indented code\n</code></pre>\n<p>paragraph</p>\n<pre><code>more code\n</code></pre>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0252(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1.      indented code\n\n   paragraph\n\n       more code\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<pre><code> indented code\n</code></pre>\n<p>paragraph</p>\n<pre><code>more code\n</code></pre>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0253(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("   foo\n\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo</p>\n<p>bar</p>\n")
    }

    @TestCase
    func example0254(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-    foo\n\n  bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n</ul>\n<p>bar</p>\n")
    }

    @TestCase
    func example0255(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-  foo\n\n   bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0256(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-\n  foo\n-\n  ```\n  bar\n  ```\n-\n      baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n<li>\n<pre><code>bar\n</code></pre>\n</li>\n<li>\n<pre><code>baz\n</code></pre>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0257(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-   \n  foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n</ul>\n")
    }

    @TestCase
    func example0258(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-\n\n  foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li></li>\n</ul>\n<p>foo</p>\n")
    }

    @TestCase
    func example0259(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n-\n- bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n<li></li>\n<li>bar</li>\n</ul>\n")
    }

    @TestCase
    func example0260(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n-   \n- bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n<li></li>\n<li>bar</li>\n</ul>\n")
    }

    @TestCase
    func example0261(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1. foo\n2.\n3. bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>foo</li>\n<li></li>\n<li>bar</li>\n</ol>\n")
    }

    @TestCase
    func example0262(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li></li>\n</ul>\n")
    }

    @TestCase
    func example0263(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\n*\n\nfoo\n1.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo\n*</p>\n<p>foo\n1.</p>\n")
    }

    @TestCase
    func example0264(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(" 1.  A paragraph\n     with two lines.\n\n         indented code\n\n     > A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0265(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  1.  A paragraph\n      with two lines.\n\n          indented code\n\n      > A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0266(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "   1.  A paragraph\n       with two lines.\n\n           indented code\n\n       > A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0267(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "    1.  A paragraph\n        with two lines.\n\n            indented code\n\n        > A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>1.  A paragraph\n    with two lines.\n\n        indented code\n\n    &gt; A block quote.\n</code></pre>\n")
    }

    @TestCase
    func example0268(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  1.  A paragraph\nwith two lines.\n\n          indented code\n\n      > A block quote.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>A paragraph\nwith two lines.</p>\n<pre><code>indented code\n</code></pre>\n<blockquote>\n<p>A block quote.</p>\n</blockquote>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0269(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("  1.  A paragraph\n    with two lines.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>A paragraph\nwith two lines.</li>\n</ol>\n")
    }

    @TestCase
    func example0270(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> 1. > Blockquote\ncontinued here.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<ol>\n<li>\n<blockquote>\n<p>Blockquote\ncontinued here.</p>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n")
    }

    @TestCase
    func example0271(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("> 1. > Blockquote\n> continued here.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<blockquote>\n<ol>\n<li>\n<blockquote>\n<p>Blockquote\ncontinued here.</p>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n")
    }

    @TestCase
    func example0272(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n  - bar\n    - baz\n      - boo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo\n<ul>\n<li>bar\n<ul>\n<li>baz\n<ul>\n<li>boo</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0273(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n - bar\n  - baz\n   - boo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n<li>bar</li>\n<li>baz</li>\n<li>boo</li>\n</ul>\n")
    }

    @TestCase
    func example0274(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("10) foo\n    - bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol start=\"10\">\n<li>foo\n<ul>\n<li>bar</li>\n</ul>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0275(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("10) foo\n   - bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol start=\"10\">\n<li>foo</li>\n</ol>\n<ul>\n<li>bar</li>\n</ul>\n")
    }

    @TestCase
    func example0276(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- - foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<ul>\n<li>foo</li>\n</ul>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0277(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1. - 2. foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<ul>\n<li>\n<ol start=\"2\">\n<li>foo</li>\n</ol>\n</li>\n</ul>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0278(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- # Foo\n- Bar\n  ---\n  baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<h1>Foo</h1>\n</li>\n<li>\n<h2>Bar</h2>\nbaz</li>\n</ul>\n")
    }

    @TestCase
    func example0281(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n- bar\n+ baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n<li>bar</li>\n</ul>\n<ul>\n<li>baz</li>\n</ul>\n")
    }

    @TestCase
    func example0282(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1. foo\n2. bar\n3) baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>foo</li>\n<li>bar</li>\n</ol>\n<ol start=\"3\">\n<li>baz</li>\n</ol>\n")
    }

    @TestCase
    func example0283(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo\n- bar\n- baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo</p>\n<ul>\n<li>bar</li>\n<li>baz</li>\n</ul>\n")
    }

    @TestCase
    func example0284(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("The number of windows in my house is\n14.  The number of doors is 6.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>The number of windows in my house is\n14.  The number of doors is 6.</p>\n")
    }

    @TestCase
    func example0285(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("The number of windows in my house is\n1.  The number of doors is 6.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>The number of windows in my house is</p>\n<ol>\n<li>The number of doors is 6.</li>\n</ol>\n")
    }

    @TestCase
    func example0286(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n\n- bar\n\n\n- baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n</li>\n<li>\n<p>bar</p>\n</li>\n<li>\n<p>baz</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0287(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n  - bar\n    - baz\n\n\n      bim\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo\n<ul>\n<li>bar\n<ul>\n<li>\n<p>baz</p>\n<p>bim</p>\n</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0288(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- foo\n- bar\n\n<!-- -->\n\n- baz\n- bim\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>foo</li>\n<li>bar</li>\n</ul>\n<!-- -->\n<ul>\n<li>baz</li>\n<li>bim</li>\n</ul>\n")
    }

    @TestCase
    func example0289(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("-   foo\n\n    notcode\n\n-   foo\n\n<!-- -->\n\n    code\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<p>notcode</p>\n</li>\n<li>\n<p>foo</p>\n</li>\n</ul>\n<!-- -->\n<pre><code>code\n</code></pre>\n")
    }

    @TestCase
    func example0290(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n - b\n  - c\n   - d\n  - e\n - f\n- g\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n<li>d</li>\n<li>e</li>\n<li>f</li>\n<li>g</li>\n</ul>\n")
    }

    @TestCase
    func example0291(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1. a\n\n  2. b\n\n   3. c\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0292(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n - b\n  - c\n   - d\n    - e\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n<li>d\n- e</li>\n</ul>\n")
    }

    @TestCase
    func example0293(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1. a\n\n  2. b\n\n    3. c\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ol>\n<pre><code>3. c\n</code></pre>\n")
    }

    @TestCase
    func example0294(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n- b\n\n- c\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0295(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("* a\n*\n\n* c\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>a</p>\n</li>\n<li></li>\n<li>\n<p>c</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0296(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n- b\n\n  c\n- d\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0297(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n- b\n\n  [ref]: /url\n- d\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0298(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n- ```\n  b\n\n\n  ```\n- c\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a</li>\n<li>\n<pre><code>b\n\n\n</code></pre>\n</li>\n<li>c</li>\n</ul>\n")
    }

    @TestCase
    func example0299(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n  - b\n\n    c\n- d\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a\n<ul>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n</ul>\n</li>\n<li>d</li>\n</ul>\n")
    }

    @TestCase
    func example0300(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("* a\n  > b\n  >\n* c\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a\n<blockquote>\n<p>b</p>\n</blockquote>\n</li>\n<li>c</li>\n</ul>\n")
    }

    @TestCase
    func example0301(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n  > b\n  ```\n  c\n  ```\n- d\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a\n<blockquote>\n<p>b</p>\n</blockquote>\n<pre><code>c\n</code></pre>\n</li>\n<li>d</li>\n</ul>\n")
    }

    @TestCase
    func example0302(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a</li>\n</ul>\n")
    }

    @TestCase
    func example0303(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n  - b\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0304(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("1. ```\n   foo\n   ```\n\n   bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ol>\n<li>\n<pre><code>foo\n</code></pre>\n<p>bar</p>\n</li>\n</ol>\n")
    }

    @TestCase
    func example0305(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("* foo\n  * bar\n\n  baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>foo</p>\n<ul>\n<li>bar</li>\n</ul>\n<p>baz</p>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0306(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("- a\n  - b\n  - c\n\n- d\n  - e\n  - f\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<ul>\n<li>\n<p>a</p>\n<ul>\n<li>b</li>\n<li>c</li>\n</ul>\n</li>\n<li>\n<p>d</p>\n<ul>\n<li>e</li>\n<li>f</li>\n</ul>\n</li>\n</ul>\n")
    }

    @TestCase
    func example0307(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`hi`lo`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>hi</code>lo`</p>\n")
    }

    @TestCase
    func example0308(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "\\!\\\"\\#\\$\\%\\&\\'\\(\\)\\*\\+\\,\\-\\.\\/\\:\\;\\<\\=\\>\\?\\@\\[\\\\\\]\\^\\_\\`\\{\\|\\}\\~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>!&quot;#$%&amp;'()*+,-./:;&lt;=&gt;?@[\\]^_`{|}~</p>\n")
    }

    @TestCase
    func example0309(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\\\t\\A\\a\\ \\3\\φ\\«\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>\\\t\\A\\a\\ \\3\\φ\\«</p>\n")
    }

    @TestCase
    func example0310(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "\\*not emphasized*\n\\<br/> not a tag\n\\[not a link](/foo)\n\\`not code`\n1\\. not a list\n\\* not a list\n\\# not a heading\n\\[foo]: /url \"not a reference\"\n\\&ouml; not a character entity\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*not emphasized*\n&lt;br/&gt; not a tag\n[not a link](/foo)\n`not code`\n1. not a list\n* not a list\n# not a heading\n[foo]: /url &quot;not a reference&quot;\n&amp;ouml; not a character entity</p>\n")
    }

    @TestCase
    func example0311(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\\\\*emphasis*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>\\<em>emphasis</em></p>\n")
    }

    @TestCase
    func example0312(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\\\nbar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<br />\nbar</p>\n")
    }

    @TestCase
    func example0313(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`` \\[\\` ``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>\\[\\`</code></p>\n")
    }

    @TestCase
    func example0314(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    \\[\\]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>\\[\\]\n</code></pre>\n")
    }

    @TestCase
    func example0315(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("~~~\n\\[\\]\n~~~\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>\\[\\]\n</code></pre>\n")
    }

    @TestCase
    func example0316(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://example.com?find=\\*>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"http://example.com?find=%5C*\">http://example.com?find=\\*</a></p>\n")
    }

    @TestCase
    func example0317(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"/bar\\/)\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<a href=\"/bar\\/)\">\n")
    }

    @TestCase
    func example0318(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo](/bar\\* \"ti\\*tle\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/bar*\" title=\"ti*tle\">foo</a></p>\n")
    }

    @TestCase
    func example0319(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n\n[foo]: /bar\\* \"ti\\*tle\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/bar*\" title=\"ti*tle\">foo</a></p>\n")
    }

    @TestCase
    func example0320(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``` foo\\+bar\nfoo\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code class=\"language-foo+bar\">foo\n</code></pre>\n")
    }

    @TestCase
    func example0321(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "&nbsp; &amp; &copy; &AElig; &Dcaron;\n&frac34; &HilbertSpace; &DifferentialD;\n&ClockwiseContourIntegral; &ngE;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>  &amp; © Æ Ď\n¾ ℋ ⅆ\n∲ ≧̸</p>\n")
    }

    @TestCase
    func example0322(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&#35; &#1234; &#992; &#0;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p># Ӓ Ϡ \u{FFFD}</p>\n")
    }

    @TestCase
    func example0323(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&#X22; &#XD06; &#xcab;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&quot; ആ ಫ</p>\n")
    }

    @TestCase
    func example0324(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&nbsp &x; &#; &#x;\n&#987654321;\n&#abcdef0;\n&ThisIsNotDefined; &hi?;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&amp;nbsp &amp;x; &amp;#; &amp;#x;\n&amp;#987654321;\n&amp;#abcdef0;\n&amp;ThisIsNotDefined; &amp;hi?;</p>\n")
    }

    @TestCase
    func example0325(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&copy\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&amp;copy</p>\n")
    }

    @TestCase
    func example0326(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&MadeUpEntity;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&amp;MadeUpEntity;</p>\n")
    }

    @TestCase
    func example0327(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"&ouml;&ouml;.html\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<a href=\"&ouml;&ouml;.html\">\n")
    }

    @TestCase
    func example0328(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo](/f&ouml;&ouml; \"f&ouml;&ouml;\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/f%C3%B6%C3%B6\" title=\"föö\">foo</a></p>\n")
    }

    @TestCase
    func example0329(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n\n[foo]: /f&ouml;&ouml; \"f&ouml;&ouml;\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/f%C3%B6%C3%B6\" title=\"föö\">foo</a></p>\n")
    }

    @TestCase
    func example0330(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``` f&ouml;&ouml;\nfoo\n```\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code class=\"language-föö\">foo\n</code></pre>\n")
    }

    @TestCase
    func example0331(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`f&ouml;&ouml;`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>f&amp;ouml;&amp;ouml;</code></p>\n")
    }

    @TestCase
    func example0332(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("    f&ouml;f&ouml;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<pre><code>f&amp;ouml;f&amp;ouml;\n</code></pre>\n")
    }

    @TestCase
    func example0333(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&#42;foo&#42;\n*foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*foo*\n<em>foo</em></p>\n")
    }

    @TestCase
    func example0334(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&#42; foo\n\n* foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>* foo</p>\n<ul>\n<li>foo</li>\n</ul>\n")
    }

    @TestCase
    func example0335(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo&#10;&#10;bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo\n\nbar</p>\n")
    }

    @TestCase
    func example0336(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("&#9;foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>\tfoo</p>\n")
    }

    @TestCase
    func example0337(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[a](url &quot;tit&quot;)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[a](url &quot;tit&quot;)</p>\n")
    }

    @TestCase
    func example0338(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`foo`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo</code></p>\n")
    }

    @TestCase
    func example0339(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`` foo ` bar ``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo ` bar</code></p>\n")
    }

    @TestCase
    func example0340(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("` `` `\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>``</code></p>\n")
    }

    @TestCase
    func example0341(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`  ``  `\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code> `` </code></p>\n")
    }

    @TestCase
    func example0342(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("` a`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code> a</code></p>\n")
    }

    @TestCase
    func example0343(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("` b `\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code> b </code></p>\n")
    }

    @TestCase
    func example0344(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("` `\n`  `\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code> </code>\n<code>  </code></p>\n")
    }

    @TestCase
    func example0345(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``\nfoo\nbar  \nbaz\n``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo bar   baz</code></p>\n")
    }

    @TestCase
    func example0346(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``\nfoo \n``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo </code></p>\n")
    }

    @TestCase
    func example0347(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`foo   bar \nbaz`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo   bar  baz</code></p>\n")
    }

    @TestCase
    func example0348(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`foo\\`bar`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo\\</code>bar`</p>\n")
    }

    @TestCase
    func example0349(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("``foo`bar``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo`bar</code></p>\n")
    }

    @TestCase
    func example0350(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("` foo `` bar `\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>foo `` bar</code></p>\n")
    }

    @TestCase
    func example0351(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo`*`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*foo<code>*</code></p>\n")
    }

    @TestCase
    func example0352(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[not a `link](/foo`)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[not a <code>link](/foo</code>)</p>\n")
    }

    @TestCase
    func example0353(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`<a href=\"`\">`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>&lt;a href=&quot;</code>&quot;&gt;`</p>\n")
    }

    @TestCase
    func example0354(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"`\">`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"`\">`</p>\n")
    }

    @TestCase
    func example0355(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`<http://foo.bar.`baz>`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>&lt;http://foo.bar.</code>baz&gt;`</p>\n")
    }

    @TestCase
    func example0356(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://foo.bar.`baz>`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"http://foo.bar.%60baz\">http://foo.bar.`baz</a>`</p>\n")
    }

    @TestCase
    func example0357(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("```foo``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>```foo``</p>\n")
    }

    @TestCase
    func example0358(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`foo\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>`foo</p>\n")
    }

    @TestCase
    func example0359(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`foo``bar``\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>`foo<code>bar</code></p>\n")
    }

    @TestCase
    func example0360(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo bar</em></p>\n")
    }

    @TestCase
    func example0361(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("a * foo bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>a * foo bar*</p>\n")
    }

    @TestCase
    func example0362(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("a*\"foo\"*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>a*&quot;foo&quot;*</p>\n")
    }

    @TestCase
    func example0363(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("* a *\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>* a *</p>\n")
    }

    @TestCase
    func example0364(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo*bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<em>bar</em></p>\n")
    }

    @TestCase
    func example0365(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("5*6*78\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>5<em>6</em>78</p>\n")
    }

    @TestCase
    func example0366(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo bar_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo bar</em></p>\n")
    }

    @TestCase
    func example0367(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_ foo bar_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_ foo bar_</p>\n")
    }

    @TestCase
    func example0368(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("a_\"foo\"_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>a_&quot;foo&quot;_</p>\n")
    }

    @TestCase
    func example0369(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo_bar_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo_bar_</p>\n")
    }

    @TestCase
    func example0370(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("5_6_78\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>5_6_78</p>\n")
    }

    @TestCase
    func example0371(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("пристаням_стремятся_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>пристаням_стремятся_</p>\n")
    }

    @TestCase
    func example0372(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("aa_\"bb\"_cc\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>aa_&quot;bb&quot;_cc</p>\n")
    }

    @TestCase
    func example0373(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo-_(bar)_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo-<em>(bar)</em></p>\n")
    }

    @TestCase
    func example0374(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_foo*</p>\n")
    }

    @TestCase
    func example0375(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo bar *\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*foo bar *</p>\n")
    }

    @TestCase
    func example0376(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo bar\n*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*foo bar\n*</p>\n")
    }

    @TestCase
    func example0377(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*(*foo)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*(*foo)</p>\n")
    }

    @TestCase
    func example0378(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*(*foo*)*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>(<em>foo</em>)</em></p>\n")
    }

    @TestCase
    func example0379(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo*bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo</em>bar</p>\n")
    }

    @TestCase
    func example0380(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo bar _\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_foo bar _</p>\n")
    }

    @TestCase
    func example0381(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_(_foo)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_(_foo)</p>\n")
    }

    @TestCase
    func example0382(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_(_foo_)_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>(<em>foo</em>)</em></p>\n")
    }

    @TestCase
    func example0383(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo_bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_foo_bar</p>\n")
    }

    @TestCase
    func example0384(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_пристаням_стремятся\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_пристаням_стремятся</p>\n")
    }

    @TestCase
    func example0385(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo_bar_baz_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo_bar_baz</em></p>\n")
    }

    @TestCase
    func example0386(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_(bar)_.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>(bar)</em>.</p>\n")
    }

    @TestCase
    func example0387(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo bar**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo bar</strong></p>\n")
    }

    @TestCase
    func example0388(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("** foo bar**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>** foo bar**</p>\n")
    }

    @TestCase
    func example0389(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("a**\"foo\"**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>a**&quot;foo&quot;**</p>\n")
    }

    @TestCase
    func example0390(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo**bar**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<strong>bar</strong></p>\n")
    }

    @TestCase
    func example0391(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo bar__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo bar</strong></p>\n")
    }

    @TestCase
    func example0392(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__ foo bar__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__ foo bar__</p>\n")
    }

    @TestCase
    func example0393(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__\nfoo bar__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__\nfoo bar__</p>\n")
    }

    @TestCase
    func example0394(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("a__\"foo\"__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>a__&quot;foo&quot;__</p>\n")
    }

    @TestCase
    func example0395(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo__bar__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo__bar__</p>\n")
    }

    @TestCase
    func example0396(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("5__6__78\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>5__6__78</p>\n")
    }

    @TestCase
    func example0397(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("пристаням__стремятся__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>пристаням__стремятся__</p>\n")
    }

    @TestCase
    func example0398(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo, __bar__, baz__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo, <strong>bar</strong>, baz</strong></p>\n")
    }

    @TestCase
    func example0399(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo-__(bar)__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo-<strong>(bar)</strong></p>\n")
    }

    @TestCase
    func example0400(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo bar **\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>**foo bar **</p>\n")
    }

    @TestCase
    func example0401(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**(**foo)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>**(**foo)</p>\n")
    }

    @TestCase
    func example0402(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*(**foo**)*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>(<strong>foo</strong>)</em></p>\n")
    }

    @TestCase
    func example0403(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**Gomphocarpus (*Gomphocarpus physocarpus*, syn.\n*Asclepias physocarpa*)**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>Gomphocarpus (<em>Gomphocarpus physocarpus</em>, syn.\n<em>Asclepias physocarpa</em>)</strong></p>\n")
    }

    @TestCase
    func example0404(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo \"*bar*\" foo**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo &quot;<em>bar</em>&quot; foo</strong></p>\n")
    }

    @TestCase
    func example0405(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo**bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo</strong>bar</p>\n")
    }

    @TestCase
    func example0406(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo bar __\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__foo bar __</p>\n")
    }

    @TestCase
    func example0407(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__(__foo)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__(__foo)</p>\n")
    }

    @TestCase
    func example0408(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_(__foo__)_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>(<strong>foo</strong>)</em></p>\n")
    }

    @TestCase
    func example0409(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo__bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__foo__bar</p>\n")
    }

    @TestCase
    func example0410(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__пристаням__стремятся\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__пристаням__стремятся</p>\n")
    }

    @TestCase
    func example0411(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo__bar__baz__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo__bar__baz</strong></p>\n")
    }

    @TestCase
    func example0412(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__(bar)__.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>(bar)</strong>.</p>\n")
    }

    @TestCase
    func example0413(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo [bar](/url)*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <a href=\"/url\">bar</a></em></p>\n")
    }

    @TestCase
    func example0414(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo\nbar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo\nbar</em></p>\n")
    }

    @TestCase
    func example0415(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo __bar__ baz_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <strong>bar</strong> baz</em></p>\n")
    }

    @TestCase
    func example0416(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo _bar_ baz_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <em>bar</em> baz</em></p>\n")
    }

    @TestCase
    func example0417(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo_ bar_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em><em>foo</em> bar</em></p>\n")
    }

    @TestCase
    func example0418(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo *bar**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <em>bar</em></em></p>\n")
    }

    @TestCase
    func example0419(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo **bar** baz*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <strong>bar</strong> baz</em></p>\n")
    }

    @TestCase
    func example0420(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo**bar**baz*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo<strong>bar</strong>baz</em></p>\n")
    }

    @TestCase
    func example0421(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo**bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo**bar</em></p>\n")
    }

    @TestCase
    func example0422(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("***foo** bar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em><strong>foo</strong> bar</em></p>\n")
    }

    @TestCase
    func example0423(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo **bar***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <strong>bar</strong></em></p>\n")
    }

    @TestCase
    func example0424(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo**bar***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo<strong>bar</strong></em></p>\n")
    }

    @TestCase
    func example0425(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo***bar***baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<em><strong>bar</strong></em>baz</p>\n")
    }

    @TestCase
    func example0426(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo******bar*********baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<strong><strong><strong>bar</strong></strong></strong>***baz</p>\n")
    }

    @TestCase
    func example0427(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo **bar *baz* bim** bop*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <strong>bar <em>baz</em> bim</strong> bop</em></p>\n")
    }

    @TestCase
    func example0428(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo [*bar*](/url)*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <a href=\"/url\"><em>bar</em></a></em></p>\n")
    }

    @TestCase
    func example0429(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("** is not an empty emphasis\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>** is not an empty emphasis</p>\n")
    }

    @TestCase
    func example0430(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**** is not an empty strong emphasis\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>**** is not an empty strong emphasis</p>\n")
    }

    @TestCase
    func example0431(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo [bar](/url)**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <a href=\"/url\">bar</a></strong></p>\n")
    }

    @TestCase
    func example0432(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo\nbar**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo\nbar</strong></p>\n")
    }

    @TestCase
    func example0433(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo _bar_ baz__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <em>bar</em> baz</strong></p>\n")
    }

    @TestCase
    func example0434(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo __bar__ baz__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <strong>bar</strong> baz</strong></p>\n")
    }

    @TestCase
    func example0435(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("____foo__ bar__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong><strong>foo</strong> bar</strong></p>\n")
    }

    @TestCase
    func example0436(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo **bar****\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <strong>bar</strong></strong></p>\n")
    }

    @TestCase
    func example0437(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo *bar* baz**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <em>bar</em> baz</strong></p>\n")
    }

    @TestCase
    func example0438(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo*bar*baz**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo<em>bar</em>baz</strong></p>\n")
    }

    @TestCase
    func example0439(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("***foo* bar**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong><em>foo</em> bar</strong></p>\n")
    }

    @TestCase
    func example0440(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo *bar***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <em>bar</em></strong></p>\n")
    }

    @TestCase
    func example0441(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo *bar **baz**\nbim* bop**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <em>bar <strong>baz</strong>\nbim</em> bop</strong></p>\n")
    }

    @TestCase
    func example0442(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo [*bar*](/url)**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo <a href=\"/url\"><em>bar</em></a></strong></p>\n")
    }

    @TestCase
    func example0443(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__ is not an empty emphasis\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__ is not an empty emphasis</p>\n")
    }

    @TestCase
    func example0444(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("____ is not an empty strong emphasis\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>____ is not an empty strong emphasis</p>\n")
    }

    @TestCase
    func example0445(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo ***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo ***</p>\n")
    }

    @TestCase
    func example0446(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo *\\**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <em>*</em></p>\n")
    }

    @TestCase
    func example0447(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo *_*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <em>_</em></p>\n")
    }

    @TestCase
    func example0448(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo *****\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo *****</p>\n")
    }

    @TestCase
    func example0449(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo **\\***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <strong>*</strong></p>\n")
    }

    @TestCase
    func example0450(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo **_**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <strong>_</strong></p>\n")
    }

    @TestCase
    func example0451(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<em>foo</em></p>\n")
    }

    @TestCase
    func example0452(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo</em>*</p>\n")
    }

    @TestCase
    func example0453(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("***foo**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<strong>foo</strong></p>\n")
    }

    @TestCase
    func example0454(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("****foo*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>***<em>foo</em></p>\n")
    }

    @TestCase
    func example0455(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo</strong>*</p>\n")
    }

    @TestCase
    func example0456(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo****\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo</em>***</p>\n")
    }

    @TestCase
    func example0457(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo ___\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo ___</p>\n")
    }

    @TestCase
    func example0458(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo _\\__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <em>_</em></p>\n")
    }

    @TestCase
    func example0459(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo _*_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <em>*</em></p>\n")
    }

    @TestCase
    func example0460(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo _____\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo _____</p>\n")
    }

    @TestCase
    func example0461(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo __\\___\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <strong>_</strong></p>\n")
    }

    @TestCase
    func example0462(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo __*__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <strong>*</strong></p>\n")
    }

    @TestCase
    func example0463(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_<em>foo</em></p>\n")
    }

    @TestCase
    func example0464(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo</em>_</p>\n")
    }

    @TestCase
    func example0465(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("___foo__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_<strong>foo</strong></p>\n")
    }

    @TestCase
    func example0466(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("____foo_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>___<em>foo</em></p>\n")
    }

    @TestCase
    func example0467(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo___\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo</strong>_</p>\n")
    }

    @TestCase
    func example0468(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo____\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo</em>___</p>\n")
    }

    @TestCase
    func example0469(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo</strong></p>\n")
    }

    @TestCase
    func example0470(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*_foo_*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em><em>foo</em></em></p>\n")
    }

    @TestCase
    func example0471(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__foo__\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong>foo</strong></p>\n")
    }

    @TestCase
    func example0472(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_*foo*_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em><em>foo</em></em></p>\n")
    }

    @TestCase
    func example0473(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("****foo****\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong><strong>foo</strong></strong></p>\n")
    }

    @TestCase
    func example0474(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("____foo____\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong><strong>foo</strong></strong></p>\n")
    }

    @TestCase
    func example0475(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("******foo******\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><strong><strong><strong>foo</strong></strong></strong></p>\n")
    }

    @TestCase
    func example0476(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("***foo***\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em><strong>foo</strong></em></p>\n")
    }

    @TestCase
    func example0477(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_____foo_____\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em><strong><strong>foo</strong></strong></em></p>\n")
    }

    @TestCase
    func example0478(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo _bar* baz_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo _bar</em> baz_</p>\n")
    }

    @TestCase
    func example0479(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo __bar *baz bim__ bam*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo <strong>bar *baz bim</strong> bam</em></p>\n")
    }

    @TestCase
    func example0480(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**foo **bar baz**\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>**foo <strong>bar baz</strong></p>\n")
    }

    @TestCase
    func example0481(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo *bar baz*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*foo <em>bar baz</em></p>\n")
    }

    @TestCase
    func example0482(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*[bar*](/url)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<a href=\"/url\">bar*</a></p>\n")
    }

    @TestCase
    func example0483(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_foo [bar_](/url)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>_foo <a href=\"/url\">bar_</a></p>\n")
    }

    @TestCase
    func example0484(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*<img src=\"foo\" title=\"*\"/>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<img src=\"foo\" title=\"*\"/></p>\n")
    }

    @TestCase
    func example0485(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**<a href=\"**\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>**<a href=\"**\"></p>\n")
    }

    @TestCase
    func example0486(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__<a href=\"__\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__<a href=\"__\"></p>\n")
    }

    @TestCase
    func example0487(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*a `*`*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>a <code>*</code></em></p>\n")
    }

    @TestCase
    func example0488(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("_a `_`_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>a <code>_</code></em></p>\n")
    }

    @TestCase
    func example0489(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("**a<http://foo.bar/?q=**>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>**a<a href=\"http://foo.bar/?q=**\">http://foo.bar/?q=**</a></p>\n")
    }

    @TestCase
    func example0490(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("__a<http://foo.bar/?q=__>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>__a<a href=\"http://foo.bar/?q=__\">http://foo.bar/?q=__</a></p>\n")
    }

    @TestCase
    func example0491(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("~~Hi~~ Hello, world!\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><del>Hi</del> Hello, world!</p>\n")
    }

    @TestCase
    func example0492(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("This ~~has a\n\nnew paragraph~~.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p>This ~~has a</p>\n<p>new paragraph~~.</p>\n")
    }

    @TestCase
    func example0493(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/uri \"title\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\" title=\"title\">link</a></p>\n")
    }

    @TestCase
    func example0494(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link</a></p>\n")
    }

    @TestCase
    func example0495(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link]()\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"\">link</a></p>\n")
    }

    @TestCase
    func example0496(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](<>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"\">link</a></p>\n")
    }

    @TestCase
    func example0497(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/my uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link](/my uri)</p>\n")
    }

    @TestCase
    func example0498(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](</my uri>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/my%20uri\">link</a></p>\n")
    }

    @TestCase
    func example0499(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](foo\nbar)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link](foo\nbar)</p>\n")
    }

    @TestCase
    func example0500(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](<foo\nbar>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link](<foo\nbar>)</p>\n")
    }

    @TestCase
    func example0501(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[a](<b)c>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"b)c\">a</a></p>\n")
    }

    @TestCase
    func example0502(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](<foo\\>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link](&lt;foo&gt;)</p>\n")
    }

    @TestCase
    func example0503(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[a](<b)c\n[a](<b)c>\n[a](<b>c)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[a](&lt;b)c\n[a](&lt;b)c&gt;\n[a](<b>c)</p>\n")
    }

    @TestCase
    func example0504(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](\\(foo\\))\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"(foo)\">link</a></p>\n")
    }

    @TestCase
    func example0505(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](foo(and(bar)))\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo(and(bar))\">link</a></p>\n")
    }

    @TestCase
    func example0506(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](foo\\(and\\(bar\\))\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo(and(bar)\">link</a></p>\n")
    }

    @TestCase
    func example0507(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](<foo(and(bar)>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo(and(bar)\">link</a></p>\n")
    }

    @TestCase
    func example0508(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](foo\\)\\:)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo):\">link</a></p>\n")
    }

    @TestCase
    func example0509(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse(
                "[link](#fragment)\n\n[link](http://example.com#fragment)\n\n[link](http://example.com?foo=3#frag)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"#fragment\">link</a></p>\n<p><a href=\"http://example.com#fragment\">link</a></p>\n<p><a href=\"http://example.com?foo=3#frag\">link</a></p>\n")
    }

    @TestCase
    func example0510(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](foo\\bar)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo%5Cbar\">link</a></p>\n")
    }

    @TestCase
    func example0511(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](foo%20b&auml;)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo%20b%C3%A4\">link</a></p>\n")
    }

    @TestCase
    func example0512(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](\"title\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"%22title%22\">link</a></p>\n")
    }

    @TestCase
    func example0513(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/url \"title\")\n[link](/url 'title')\n[link](/url (title))\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">link</a>\n<a href=\"/url\" title=\"title\">link</a>\n<a href=\"/url\" title=\"title\">link</a></p>\n")
    }

    @TestCase
    func example0514(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/url \"title \\\"&quot;\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title &quot;&quot;\">link</a></p>\n")
    }

    @TestCase
    func example0515(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/url \"title\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url%C2%A0%22title%22\">link</a></p>\n")
    }

    @TestCase
    func example0516(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/url \"title \"and\" title\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link](/url &quot;title &quot;and&quot; title&quot;)</p>\n")
    }

    @TestCase
    func example0517(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](/url 'title \"and\" title')\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title &quot;and&quot; title\">link</a></p>\n")
    }

    @TestCase
    func example0518(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link](   /uri\n  \"title\"  )\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\" title=\"title\">link</a></p>\n")
    }

    @TestCase
    func example0519(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link] (/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link] (/uri)</p>\n")
    }

    @TestCase
    func example0520(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link [foo [bar]]](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link [foo [bar]]</a></p>\n")
    }

    @TestCase
    func example0521(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link] bar](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link] bar](/uri)</p>\n")
    }

    @TestCase
    func example0522(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link [bar](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[link <a href=\"/uri\">bar</a></p>\n")
    }

    @TestCase
    func example0523(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link \\[bar](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link [bar</a></p>\n")
    }

    @TestCase
    func example0524(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link *foo **bar** `#`*](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link <em>foo <strong>bar</strong> <code>#</code></em></a></p>\n")
    }

    @TestCase
    func example0525(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[![moon](moon.jpg)](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\"><img src=\"moon.jpg\" alt=\"moon\" /></a></p>\n")
    }

    @TestCase
    func example0526(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo [bar](/uri)](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo <a href=\"/uri\">bar</a>](/uri)</p>\n")
    }

    @TestCase
    func example0527(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo *[bar [baz](/uri)](/uri)*](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo <em>[bar <a href=\"/uri\">baz</a>](/uri)</em>](/uri)</p>\n")
    }

    @TestCase
    func example0528(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![[[foo](uri1)](uri2)](uri3)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"uri3\" alt=\"[foo](uri2)\" /></p>\n")
    }

    @TestCase
    func example0529(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*[foo*](/uri)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<a href=\"/uri\">foo*</a></p>\n")
    }

    @TestCase
    func example0530(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo *bar](baz*)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"baz*\">foo *bar</a></p>\n")
    }

    @TestCase
    func example0531(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo [bar* baz]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo [bar</em> baz]</p>\n")
    }

    @TestCase
    func example0532(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo <bar attr=\"](baz)\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo <bar attr=\"](baz)\"></p>\n")
    }

    @TestCase
    func example0533(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo`](/uri)`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo<code>](/uri)</code></p>\n")
    }

    @TestCase
    func example0534(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo<http://example.com/?search=](uri)>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo<a href=\"http://example.com/?search=%5D(uri)\">http://example.com/?search=](uri)</a></p>\n")
    }

    @TestCase
    func example0535(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][bar]\n\n[bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">foo</a></p>\n")
    }

    @TestCase
    func example0536(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link [foo [bar]]][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link [foo [bar]]</a></p>\n")
    }

    @TestCase
    func example0537(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link \\[bar][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link [bar</a></p>\n")
    }

    @TestCase
    func example0538(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[link *foo **bar** `#`*][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">link <em>foo <strong>bar</strong> <code>#</code></em></a></p>\n")
    }

    @TestCase
    func example0539(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[![moon](moon.jpg)][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\"><img src=\"moon.jpg\" alt=\"moon\" /></a></p>\n")
    }

    @TestCase
    func example0540(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo [bar](/uri)][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo <a href=\"/uri\">bar</a>]<a href=\"/uri\">ref</a></p>\n")
    }

    @TestCase
    func example0541(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo *bar [baz][ref]*][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo <em>bar <a href=\"/uri\">baz</a></em>]<a href=\"/uri\">ref</a></p>\n")
    }

    @TestCase
    func example0542(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*[foo*][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<a href=\"/uri\">foo*</a></p>\n")
    }

    @TestCase
    func example0543(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo *bar][ref]\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">foo *bar</a></p>\n")
    }

    @TestCase
    func example0544(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo <bar attr=\"][ref]\">\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo <bar attr=\"][ref]\"></p>\n")
    }

    @TestCase
    func example0545(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo`][ref]`\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo<code>][ref]</code></p>\n")
    }

    @TestCase
    func example0546(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo<http://example.com/?search=][ref]>\n\n[ref]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo<a href=\"http://example.com/?search=%5D%5Bref%5D\">http://example.com/?search=][ref]</a></p>\n")
    }

    @TestCase
    func example0547(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][BaR]\n\n[bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">foo</a></p>\n")
    }

    @TestCase
    func example0548(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[Толпой][Толпой] is a Russian word.\n\n[ТОЛПОЙ]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\">Толпой</a> is a Russian word.</p>\n")
    }

    @TestCase
    func example0549(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[Foo\n  bar]: /url\n\n[Baz][Foo bar]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\">Baz</a></p>\n")
    }

    @TestCase
    func example0550(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo] [bar]\n\n[bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo] <a href=\"/url\" title=\"title\">bar</a></p>\n")
    }

    @TestCase
    func example0551(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n[bar]\n\n[bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]\n<a href=\"/url\" title=\"title\">bar</a></p>\n")
    }

    @TestCase
    func example0552(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]: /url1\n\n[foo]: /url2\n\n[bar][foo]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url1\">bar</a></p>\n")
    }

    @TestCase
    func example0553(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[bar][foo\\!]\n\n[foo!]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[bar][foo!]</p>\n")
    }

    @TestCase
    func example0554(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][ref[]\n\n[ref[]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo][ref[]</p>\n<p>[ref[]: /uri</p>\n")
    }

    @TestCase
    func example0555(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][ref[bar]]\n\n[ref[bar]]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo][ref[bar]]</p>\n<p>[ref[bar]]: /uri</p>\n")
    }

    @TestCase
    func example0556(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[[[foo]]]\n\n[[[foo]]]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[[[foo]]]</p>\n<p>[[[foo]]]: /url</p>\n")
    }

    @TestCase
    func example0557(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][ref\\[]\n\n[ref\\[]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">foo</a></p>\n")
    }

    @TestCase
    func example0558(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[bar\\\\]: /uri\n\n[bar\\\\]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/uri\">bar\\</a></p>\n")
    }

    @TestCase
    func example0559(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[]\n\n[]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[]</p>\n<p>[]: /uri</p>\n")
    }

    @TestCase
    func example0560(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[\n ]\n\n[\n ]: /uri\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[\n]</p>\n<p>[\n]: /uri</p>\n")
    }

    @TestCase
    func example0561(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">foo</a></p>\n")
    }

    @TestCase
    func example0562(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[*foo* bar][]\n\n[*foo* bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\"><em>foo</em> bar</a></p>\n")
    }

    @TestCase
    func example0563(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[Foo][]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">Foo</a></p>\n")
    }

    @TestCase
    func example0564(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo] \n[]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">foo</a>\n[]</p>\n")
    }

    @TestCase
    func example0565(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">foo</a></p>\n")
    }

    @TestCase
    func example0566(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[*foo* bar]\n\n[*foo* bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\"><em>foo</em> bar</a></p>\n")
    }

    @TestCase
    func example0567(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[[*foo* bar]]\n\n[*foo* bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[<a href=\"/url\" title=\"title\"><em>foo</em> bar</a>]</p>\n")
    }

    @TestCase
    func example0568(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[[bar [foo]\n\n[foo]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[[bar <a href=\"/url\">foo</a></p>\n")
    }

    @TestCase
    func example0569(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[Foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\" title=\"title\">Foo</a></p>\n")
    }

    @TestCase
    func example0570(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo] bar\n\n[foo]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url\">foo</a> bar</p>\n")
    }

    @TestCase
    func example0571(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\\[foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]</p>\n")
    }

    @TestCase
    func example0572(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo*]: /url\n\n*[foo*]\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>*<a href=\"/url\">foo*</a></p>\n")
    }

    @TestCase
    func example0573(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][bar]\n\n[foo]: /url1\n[bar]: /url2\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url2\">foo</a></p>\n")
    }

    @TestCase
    func example0574(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][]\n\n[foo]: /url1\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url1\">foo</a></p>\n")
    }

    @TestCase
    func example0575(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo]()\n\n[foo]: /url1\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"\">foo</a></p>\n")
    }

    @TestCase
    func example0576(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo](not a link)\n\n[foo]: /url1\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url1\">foo</a>(not a link)</p>\n")
    }

    @TestCase
    func example0577(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][bar][baz]\n\n[baz]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]<a href=\"/url\">bar</a></p>\n")
    }

    @TestCase
    func example0578(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][bar][baz]\n\n[baz]: /url1\n[bar]: /url2\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"/url2\">foo</a><a href=\"/url1\">baz</a></p>\n")
    }

    @TestCase
    func example0579(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("[foo][bar][baz]\n\n[baz]: /url1\n[foo]: /url2\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>[foo]<a href=\"/url1\">bar</a></p>\n")
    }

    @TestCase
    func example0580(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo](/url \"title\")\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0581(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo *bar*]\n\n[foo *bar*]: train.jpg \"train & tracks\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"train.jpg\" alt=\"foo bar\" title=\"train &amp; tracks\" /></p>\n")
    }

    @TestCase
    func example0582(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo ![bar](/url)](/url2)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n")
    }

    @TestCase
    func example0583(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo [bar](/url)](/url2)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n")
    }

    @TestCase
    func example0584(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo *bar*][]\n\n[foo *bar*]: train.jpg \"train & tracks\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"train.jpg\" alt=\"foo bar\" title=\"train &amp; tracks\" /></p>\n")
    }

    @TestCase
    func example0585(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo *bar*][foobar]\n\n[FOOBAR]: train.jpg \"train & tracks\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"train.jpg\" alt=\"foo bar\" title=\"train &amp; tracks\" /></p>\n")
    }

    @TestCase
    func example0586(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo](train.jpg)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"train.jpg\" alt=\"foo\" /></p>\n")
    }

    @TestCase
    func example0587(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("My ![foo bar](/path/to/train.jpg  \"title\"   )\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>My <img src=\"/path/to/train.jpg\" alt=\"foo bar\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0588(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo](<url>)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"url\" alt=\"foo\" /></p>\n")
    }

    @TestCase
    func example0589(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![](/url)\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"\" /></p>\n")
    }

    @TestCase
    func example0590(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo][bar]\n\n[bar]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo\" /></p>\n")
    }

    @TestCase
    func example0591(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo][bar]\n\n[BAR]: /url\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo\" /></p>\n")
    }

    @TestCase
    func example0592(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo][]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0593(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![*foo* bar][]\n\n[*foo* bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo bar\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0594(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![Foo][]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"Foo\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0595(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo] \n[]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo\" title=\"title\" />\n[]</p>\n")
    }

    @TestCase
    func example0596(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0597(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![*foo* bar]\n\n[*foo* bar]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"foo bar\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0598(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![[foo]]\n\n[[foo]]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>![[foo]]</p>\n<p>[[foo]]: /url &quot;title&quot;</p>\n")
    }

    @TestCase
    func example0599(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("![Foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><img src=\"/url\" alt=\"Foo\" title=\"title\" /></p>\n")
    }

    @TestCase
    func example0600(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("!\\[foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>![foo]</p>\n")
    }

    @TestCase
    func example0601(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("\\![foo]\n\n[foo]: /url \"title\"\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>!<a href=\"/url\" title=\"title\">foo</a></p>\n")
    }

    @TestCase
    func example0602(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://foo.bar.baz>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"http://foo.bar.baz\">http://foo.bar.baz</a></p>\n")
    }

    @TestCase
    func example0603(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://foo.bar.baz/test?q=hello&id=22&boolean>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"http://foo.bar.baz/test?q=hello&amp;id=22&amp;boolean\">http://foo.bar.baz/test?q=hello&amp;id=22&amp;boolean</a></p>\n")
    }

    @TestCase
    func example0604(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<irc://foo.bar:2233/baz>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"irc://foo.bar:2233/baz\">irc://foo.bar:2233/baz</a></p>\n")
    }

    @TestCase
    func example0605(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<MAILTO:FOO@BAR.BAZ>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"MAILTO:FOO@BAR.BAZ\">MAILTO:FOO@BAR.BAZ</a></p>\n")
    }

    @TestCase
    func example0606(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a+b+c:d>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"a+b+c:d\">a+b+c:d</a></p>\n")
    }

    @TestCase
    func example0607(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<made-up-scheme://foo,bar>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"made-up-scheme://foo,bar\">made-up-scheme://foo,bar</a></p>\n")
    }

    @TestCase
    func example0608(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://../>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"http://../\">http://../</a></p>\n")
    }

    @TestCase
    func example0609(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<localhost:5001/foo>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"localhost:5001/foo\">localhost:5001/foo</a></p>\n")
    }

    @TestCase
    func example0610(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://foo.bar/baz bim>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;http://foo.bar/baz bim&gt;</p>\n")
    }

    @TestCase
    func example0611(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<http://example.com/\\[\\>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"http://example.com/%5C%5B%5C\">http://example.com/\\[\\</a></p>\n")
    }

    @TestCase
    func example0612(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<foo@bar.example.com>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"mailto:foo@bar.example.com\">foo@bar.example.com</a></p>\n")
    }

    @TestCase
    func example0613(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<foo+special@Bar.baz-bar0.com>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"mailto:foo+special@Bar.baz-bar0.com\">foo+special@Bar.baz-bar0.com</a></p>\n")
    }

    @TestCase
    func example0614(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<foo\\+@bar.example.com>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;foo+@bar.example.com&gt;</p>\n")
    }

    @TestCase
    func example0615(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;&gt;</p>\n")
    }

    @TestCase
    func example0616(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("< http://foo.bar >\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt; http://foo.bar &gt;</p>\n")
    }

    @TestCase
    func example0617(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<m:abc>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;m:abc&gt;</p>\n")
    }

    @TestCase
    func example0618(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<foo.bar.baz>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;foo.bar.baz&gt;</p>\n")
    }

    @TestCase
    func example0619(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("http://example.com\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>http://example.com</p>\n")
    }

    @TestCase
    func example0620(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo@bar.example.com\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo@bar.example.com</p>\n")
    }

    @TestCase
    func example0621(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("www.commonmark.org\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"http://www.commonmark.org\">www.commonmark.org</a></p>\n")
    }

    @TestCase
    func example0622(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("Visit www.commonmark.org/help for more information.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p>Visit <a href=\"http://www.commonmark.org/help\">www.commonmark.org/help</a> for more information.</p>\n")
    }

    @TestCase
    func example0623(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("Visit www.commonmark.org.\n\nVisit www.commonmark.org/a.b.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p>Visit <a href=\"http://www.commonmark.org\">www.commonmark.org</a>.</p>\n<p>Visit <a href=\"http://www.commonmark.org/a.b\">www.commonmark.org/a.b</a>.</p>\n")
    }

    @TestCase
    func example0624(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("www.google.com/search?q=Markup+(business)\n\n(www.google.com/search?q=Markup+(business))\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"http://www.google.com/search?q=Markup+(business)\">www.google.com/search?q=Markup+(business)</a></p>\n<p>(<a href=\"http://www.google.com/search?q=Markup+(business)\">www.google.com/search?q=Markup+(business)</a>)</p>\n")
    }

    @TestCase
    func example0625(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("www.google.com/search?q=(business))+ok\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"http://www.google.com/search?q=(business))+ok\">www.google.com/search?q=(business))+ok</a></p>\n")
    }

    @TestCase
    func example0626(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("www.google.com/search?q=commonmark&hl=en\n\nwww.google.com/search?q=commonmark&hl;\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"http://www.google.com/search?q=commonmark&amp;hl=en\">www.google.com/search?q=commonmark&amp;hl=en</a></p>\n<p><a href=\"http://www.google.com/search?q=commonmark\">www.google.com/search?q=commonmark</a>&amp;hl;</p>\n")
    }

    @TestCase
    func example0627(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("www.commonmark.org/he<lp\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"http://www.commonmark.org/he\">www.commonmark.org/he</a>&lt;lp</p>\n")
    }

    @TestCase
    func example0628(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse(
                "http://commonmark.org\n\n(Visit https://encrypted.google.com/search?q=Markup+(business))\n\nAnonymous FTP is available at ftp://foo.bar.baz.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"http://commonmark.org\">http://commonmark.org</a></p>\n<p>(Visit <a href=\"https://encrypted.google.com/search?q=Markup+(business)\">https://encrypted.google.com/search?q=Markup+(business)</a>)</p>\n<p>Anonymous FTP is available at <a href=\"ftp://foo.bar.baz\">ftp://foo.bar.baz</a>.</p>\n")
    }

    @TestCase
    func example0629(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("foo@bar.baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"mailto:foo@bar.baz\">foo@bar.baz</a></p>\n")
    }

    @TestCase
    func example0630(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("hello@mail+xyz.example isn't valid, but hello+xyz@mail.example is.\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p>hello@mail+xyz.example isn't valid, but <a href=\"mailto:hello+xyz@mail.example\">hello+xyz@mail.example</a> is.</p>\n")
    }

    @TestCase
    func example0631(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse("a.b-c_d@a.b\n\na.b-c_d@a.b.\n\na.b-c_d@a.b-\n\na.b-c_d@a.b_\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><a href=\"mailto:a.b-c_d@a.b\">a.b-c_d@a.b</a></p>\n<p><a href=\"mailto:a.b-c_d@a.b\">a.b-c_d@a.b</a>.</p>\n<p>a.b-c_d@a.b-</p>\n<p>a.b-c_d@a.b_</p>\n")
    }

    @TestCase
    func example0632(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a><bab><c2c>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a><bab><c2c></p>\n")
    }

    @TestCase
    func example0633(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a/><b2/>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a/><b2/></p>\n")
    }

    @TestCase
    func example0634(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a  /><b2\ndata=\"foo\" >\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a  /><b2\ndata=\"foo\" ></p>\n")
    }

    @TestCase
    func example0635(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 />\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a foo=\"bar\" bam = 'baz <em>\"</em>'\n_boolean zoop:33=zoop:33 /></p>\n")
    }

    @TestCase
    func example0636(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo <responsive-image src=\"foo.jpg\" />\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo <responsive-image src=\"foo.jpg\" /></p>\n")
    }

    @TestCase
    func example0637(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<33> <__>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;33&gt; &lt;__&gt;</p>\n")
    }

    @TestCase
    func example0638(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a h*#ref=\"hi\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;a h*#ref=&quot;hi&quot;&gt;</p>\n")
    }

    @TestCase
    func example0639(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"hi'> <a href=hi'>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;a href=&quot;hi'&gt; &lt;a href=hi'&gt;</p>\n")
    }

    @TestCase
    func example0640(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("< a><\nfoo><bar/ >\n<foo bar=baz\nbim!bop />\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt; a&gt;&lt;\nfoo&gt;&lt;bar/ &gt;\n&lt;foo bar=baz\nbim!bop /&gt;</p>\n")
    }

    @TestCase
    func example0641(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href='bar'title=title>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;a href='bar'title=title&gt;</p>\n")
    }

    @TestCase
    func example0642(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("</a></foo >\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p></a></foo ></p>\n")
    }

    @TestCase
    func example0643(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("</a href=\"foo\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;/a href=&quot;foo&quot;&gt;</p>\n")
    }

    @TestCase
    func example0644(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <!-- this is a\ncomment - with hyphen -->\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <!-- this is a\ncomment - with hyphen --></p>\n")
    }

    @TestCase
    func example0645(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <!-- not a comment -- two hyphens -->\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo &lt;!-- not a comment -- two hyphens --&gt;</p>\n")
    }

    @TestCase
    func example0646(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <!--> foo -->\n\nfoo <!-- foo--->\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo &lt;!--&gt; foo --&gt;</p>\n<p>foo &lt;!-- foo---&gt;</p>\n")
    }

    @TestCase
    func example0647(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <?php echo $a; ?>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <?php echo $a; ?></p>\n")
    }

    @TestCase
    func example0648(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <!ELEMENT br EMPTY>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <!ELEMENT br EMPTY></p>\n")
    }

    @TestCase
    func example0649(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <![CDATA[>&<]]>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <![CDATA[>&<]]></p>\n")
    }

    @TestCase
    func example0650(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <a href=\"&ouml;\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <a href=\"&ouml;\"></p>\n")
    }

    @TestCase
    func example0651(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo <a href=\"\\*\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo <a href=\"\\*\"></p>\n")
    }

    @TestCase
    func example0652(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"\\\"\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>&lt;a href=&quot;&quot;&quot;&gt;</p>\n")
    }

    @TestCase
    func example0653(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029())
            .build()
            .parse(
                "<strong> <title> <style> <em>\n\n<blockquote>\n  <xmp> is disallowed.  <XMP> is also disallowed.\n</blockquote>\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.gfmCompatible()).render(document), "<p><strong> &lt;title> &lt;style> <em></p>\n<blockquote>\n  &lt;xmp> is disallowed.  &lt;XMP> is also disallowed.\n</blockquote>\n")
    }

    @TestCase
    func example0654(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo  \nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<br />\nbaz</p>\n")
    }

    @TestCase
    func example0655(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\\\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<br />\nbaz</p>\n")
    }

    @TestCase
    func example0656(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo       \nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<br />\nbaz</p>\n")
    }

    @TestCase
    func example0657(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo  \n     bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<br />\nbar</p>\n")
    }

    @TestCase
    func example0658(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\\\n     bar\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo<br />\nbar</p>\n")
    }

    @TestCase
    func example0659(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo  \nbar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo<br />\nbar</em></p>\n")
    }

    @TestCase
    func example0660(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("*foo\\\nbar*\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><em>foo<br />\nbar</em></p>\n")
    }

    @TestCase
    func example0661(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`code \nspan`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>code  span</code></p>\n")
    }

    @TestCase
    func example0662(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("`code\\\nspan`\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><code>code\\ span</code></p>\n")
    }

    @TestCase
    func example0663(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"foo  \nbar\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo  \nbar\"></p>\n")
    }

    @TestCase
    func example0664(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("<a href=\"foo\\\nbar\">\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p><a href=\"foo\\\nbar\"></p>\n")
    }

    @TestCase
    func example0665(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\\\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo\\</p>\n")
    }

    @TestCase
    func example0666(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo  \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo</p>\n")
    }

    @TestCase
    func example0667(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("### foo\\\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h3>foo\\</h3>\n")
    }

    @TestCase
    func example0668(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("### foo  \n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<h3>foo</h3>\n")
    }

    @TestCase
    func example0669(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo\nbaz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo\nbaz</p>\n")
    }

    @TestCase
    func example0670(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("foo \n baz\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>foo\nbaz</p>\n")
    }

    @TestCase
    func example0671(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("hello $.;'there\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>hello $.;'there</p>\n")
    }

    @TestCase
    func example0672(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Foo χρῆν\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Foo χρῆν</p>\n")
    }

    @TestCase
    func example0673(): Unit {
        let document = MarkdownEngine
            .builder()
            .profile(MarkdownProfile.gfm029CommonMarkBase())
            .build()
            .parse("Multiple     spaces\n")
            .document
        @Expect(HtmlRenderer(options: HtmlOptions.specCompatible()).render(document), "<p>Multiple     spaces</p>\n")
    }
}
