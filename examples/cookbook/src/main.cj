package markdown_cookbook

import markdown.core.{AppendReplica, AppendState, Markdown, MarkdownEngine, MarkdownProfile}
import markdown.editor.AstQuery
import markdown.extensions.{DefinitionListPayload, DefinitionListRole, BlockSyntax, ExtensionCapabilities, 
    ExtensionManifest, MarkdownDialect, OfficialExtensions, RendererRule}
import markdown.render.{AsyncRenderState, AsyncSinkWriteResult, AsyncTextSink, HtmlOptions, HtmlRenderer}

class CookbookOutputSink <: AsyncTextSink {
    private let out = StringBuilder()
    public func write(value: String): AsyncSinkWriteResult {
        out.append(value)
        AsyncSinkWriteResult.Continue
    }
    func content(): String {
        out.toString()
    }
}

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
        "docs",
        "1.0.0",
        "cookbook-1",
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

    println("== append ==")
    let appendEngine = MarkdownEngine.builder().build()
    let session = appendEngine.newAppendSession()
    let replica = AppendReplica()
    for (chunk in ["[name][id]\n\n", "[id]: /guide\n"]) {
        let update = session.feed(chunk)
        replica.apply(update)
        if (let AppendState.Failed(error) <- update.state) {
            println(error.message)
            return 1
        }
    }
    let finalUpdate = session.finish()
    replica.apply(finalUpdate)
    match (finalUpdate.state) {
        case AppendState.Complete => println(HtmlRenderer().render(replica.result.getOrThrow().document))
        case AppendState.Failed(error) =>
            println(error.message);
            return 1
        case AppendState.AwaitingInput => return 1
    }

    println("== resumable-output ==")
    let output = HtmlRenderer().newOutputSession(replica.result.getOrThrow().document, chunkBytes: 7)
    let outputSink = CookbookOutputSink()
    match (output.resume(outputSink)) {
        case AsyncRenderState.Complete => println(outputSink.content())
        case AsyncRenderState.Failed(error) =>
            println(error.message);
            return 1
        case AsyncRenderState.Paused => return 1
    }

    println("== definition-list ==")
    let definitionEngine = MarkdownEngine
        .builder()
        .dialect(OfficialExtensions.definitionLists(MarkdownDialect.define("glossary", "2")).build())
        .build()
    let glossary = definitionEngine.parse("Term one\nTerm two\n: First definition\n\n  Second paragraph\n")
    let listPayload = glossary.document.root().children()[0].asCustomBlock().getOrThrow().payload as DefinitionListPayload
    if (let DefinitionListRole.List <- listPayload.getOrThrow().role) {
        ()
    } else {
        return 1
    }
    println(definitionEngine.htmlRenderer().render(glossary.document))

    println("== format ==")
    println(Markdown.format("#  Title\n\n* item"))
    0
}
