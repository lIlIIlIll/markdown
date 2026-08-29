package markdown_cookbook

import markdown.core.{Markdown, MarkdownEngine, MarkdownProfile}
import markdown.editor.AstQuery
import markdown.extensions.{BlockSyntax, ExtensionCapabilities, ExtensionManifest, MarkdownDialect, RendererRule}
import markdown.render.{HtmlOptions, HtmlRenderer}

main(): Int64 {
    println("== safe-html ==")
    println(Markdown.toSafeHtml("# Hello\n\n<script>blocked</script>"))

    println("== gfm ==")
    println(Markdown.toSafeHtml("- [x] shipped\n\n~~old~~", profile: MarkdownProfile.gfm029()))

    println("== ast ==")
    let parsed = Markdown.parse("# Install\n\nSee [API](api).")
    for (heading in AstQuery.headings(parsed.document)) {
        let span = heading.node.span.getOrThrow()
        let position = parsed.source.utf16Position(span.startByte)
        println("heading=${parsed.source.slice(span)}, line=${position.line}, character=${position.character}")
    }
    for (link in AstQuery.links(parsed.document)) {
        println("link=${link.destination}")
    }

    println("== lint ==")
    let lintEngine = MarkdownEngine.builder().build()
    let snapshot = lintEngine.parseSnapshot("# Title\n\n### Skipped level")
    for (diagnostic in lintEngine.lint(snapshot)) {
        println("${diagnostic.code}: ${diagnostic.message}")
    }

    println("== extension ==")
    let manifest = ExtensionManifest(
        "docs", "1.0.0", "cookbook-1",
        capabilities: ExtensionCapabilities(safeHtml: true)
    )
    let dialect = MarkdownDialect
        .define("docs-v1", "1.0.0")
        .enable(manifest)
        .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
        .renderer(RendererRule("docs", "note", "aside", classToken: "note"))
        .build()
    let extensionEngine = MarkdownEngine.builder().dialect(dialect).build()
    let custom = extensionEngine.parse(":::note\n**important**\n:::").document
    println(extensionEngine.htmlRenderer(options: HtmlOptions.safe()).render(custom))

    println("== format ==")
    println(Markdown.format("#  Title\n\n* item"))
    0
}
