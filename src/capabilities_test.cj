package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class CapabilitiesTest {
    @TestCase
    func reportsActualDialectAndVersionedOptionalSupport(): Unit {
        let dialect = MarkdownDialect
            .define("docs", "1")
            .enable(
                ExtensionManifest("docs", "1", "impl-1", capabilities: ExtensionCapabilities(safeHtml: true),
                    shareable: false))
            .inline(InlineSyntax.define("docs", "mark").delimiter("=="))
            .renderer(RendererRule("docs", "mark", "mark"))
            .build()
        let capabilities = MarkdownEngine.builder().dialect(dialect).build().capabilities()
        @Expect(capabilities.supportedExtensions.size, 1)
        @Expect(capabilities.supportedExtensions[0], "docs")
        @Expect(capabilities.supportedSyntaxKinds[0], "inline:docs/mark")
        @Expect(capabilities.incrementalSupport, true)
        @Expect(capabilities.incrementalMode, "block-local-with-full-fallback")
        @Expect(capabilities.losslessSupport, true)
        @Expect(capabilities.serializationVersions[0], "parse-artifact-1")
        @Expect(capabilities.multiDocumentSupport, true)
        @Expect(capabilities.htmlToMarkdownSupport, true)
        @Expect(capabilities.virtualTreeSupport, true)
        @Expect(capabilities.pluginIsolationPortVersion, "markdown-isolation-ipc-1")
        @Expect(capabilities.builtInPluginOsSandbox, false)
        match (capabilities.extension("docs")) {
            case Some(report) =>
                @Expect(report.semanticVersion, "1")
                @Expect(report.implementationVersion, "impl-1")
                @Expect(report.capabilities.safeHtml, true)
                @Expect(report.shareable, false)
            case None => @Expect(false)
        }
    }
}
