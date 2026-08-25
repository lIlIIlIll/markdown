package markdown

import std.unittest.*
import std.unittest.testmacro.*

private class FallbackScannerAccelerator <: LineScannerAccelerator {
    public func implementationId(): String {
        "test-fallback"
    }

    public func scanLines(_: Array<Byte>, _: Int64): ?Array<UInt64> {
        None
    }
}

@Test
class CapabilitiesTest {
    @TestCase
    func reportsActualDialectAndVersionedOptionalSupport(): Unit {
        let dialect = MarkdownDialect
            .define("docs", "1")
            .enable(
                ExtensionManifest("docs", "1.0.0", "impl-1", capabilities: ExtensionCapabilities(safeHtml: true),
                    shareable: false))
            .inline(InlineSyntax.define("docs", "mark").delimiter("=="))
            .renderer(RendererRule("docs", "mark", "mark"))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let accelerated = engine.acceleratedBy(FallbackScannerAccelerator())
        let capabilities = accelerated.capabilities()
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
        @Expect(capabilities.nativeScannerAvailable, true)
        @Expect(capabilities.nativeScannerEnabled, true)
        @Expect(capabilities.nativeScannerUsedForStringInput, false)
        let executionModels = accelerated.executionModels()
        @Expect(executionModels.nativeScannerImplementation, "test-fallback")
        @Expect(executionModels.streamInput, "buffered-before-parse")
        @Expect(executionModels.chunkInput, "buffered-until-finish")
        @Expect(executionModels.partialParse, "failure-result-without-completed-prefix")
        @Expect(executionModels.asyncHtml, "pre-rendered-buffered-output")
        let pureCapabilities = MarkdownEngine.builder().nativeScannerEnabled(false).build().capabilities()
        @Expect(pureCapabilities.nativeScannerAvailable, false)
        @Expect(pureCapabilities.nativeScannerEnabled, false)
        match (capabilities.extension("docs")) {
            case Some(report) =>
                @Expect(report.semanticVersion, "1.0.0")
                @Expect(report.implementationVersion, "impl-1")
                @Expect(report.capabilities.safeHtml, true)
                @Expect(report.shareable, false)
            case None => @Expect(false)
        }
    }
}
