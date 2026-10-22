package markdown_quickstart

import markdown.core.{AstQuery, CancellationSource, MarkdownException}
import markdown.engine.MarkdownEngine
import markdown.extensions.{BlockSyntax, ExtensionCapabilities, ExtensionManifest, MarkdownDialect, RendererRule}
import markdown.render.HtmlRenderer

main(): Int64 {
    let safe = MarkdownEngine.builder().build().renderHtml("# Hello\n\n<script>blocked</script>").html
    println(safe)

    let document = MarkdownEngine.builder().build().parse("# One\n\n## Two").document
    for (heading in AstQuery.headings(document)) {
        println("heading level=${heading.level}")
    }

    let manifest = ExtensionManifest("docs", "1.0.0", "example-1", capabilities: ExtensionCapabilities(safeHtml: true))
    let dialect = MarkdownDialect
        .define("docs-v1", "1.0.0")
        .enable(manifest)
        .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
        .renderer(RendererRule("docs", "note", "aside", classToken: "note"))
        .build()
    let engine = MarkdownEngine.builder().dialect(dialect).build()
    let custom = engine.parse(":::note title=Read\n**important**\n:::").document
    println(HtmlRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(custom))

    let cancellation = CancellationSource()
    cancellation.cancel()
    try {
        engine.parse("large input", cancellation: cancellation.token)
    } catch (error: MarkdownException) {
        println("cancelled=${error.phase}")
    }
    0
}
