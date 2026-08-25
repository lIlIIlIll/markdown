package markdown

import std.collection.*

public class ExtensionCapabilityReport {
    public let extensionId: String
    public let semanticVersion: String
    public let implementationVersion: String
    public let requiredSpiVersion: String
    public let capabilities: ExtensionCapabilities
    public let shareable: Bool
    internal init(manifest: ExtensionManifest) {
        extensionId = manifest.extensionId
        semanticVersion = manifest.semanticVersion
        implementationVersion = manifest.implementationVersion
        requiredSpiVersion = manifest.requiredSpiVersion
        capabilities = manifest.capabilities
        shareable = manifest.shareable
    }
}

public class EngineCapabilities {
    public let supportedProfiles: ImmutableArray<String>
    public let supportedExtensions: ImmutableArray<String>
    public let supportedRenderers: ImmutableArray<String>
    public let supportedSyntaxKinds: ImmutableArray<String>
    public let dslSchemaVersions: ImmutableArray<String>
    public let spiVersions: ImmutableArray<String>
    public let positionEncodings: ImmutableArray<String>
    public let serializationVersions: ImmutableArray<String>
    public let incrementalSupport: Bool
    public let incrementalMode: String
    public let losslessSupport: Bool
    public let extensionCapabilities: ImmutableArray<ExtensionCapabilityReport>
    public let multiDocumentSupport: Bool
    public let htmlToMarkdownSupport: Bool
    public let virtualTreeSupport: Bool
    public let pluginIsolationPortVersion: String
    public let builtInPluginOsSandbox: Bool

    internal init(dialect: CompiledMarkdownDialect) {
        supportedProfiles = ImmutableArray<String>(["commonmark-0.31.2", "gfm-0.29", "gfm-modern-v1", "custom"])
        let extensions = ArrayList<String>()
        let reports = ArrayList<ExtensionCapabilityReport>()
        for (manifest in dialect.manifests.toArray()) {
            extensions.add(manifest.extensionId)
            reports.add(ExtensionCapabilityReport(manifest))
        }
        supportedExtensions = ImmutableArray<String>(extensions.toArray())
        extensionCapabilities = ImmutableArray<ExtensionCapabilityReport>(reports.toArray())
        supportedRenderers = ImmutableArray<String>(
            ["spec-html", "gfm-html", "safe-html", "plain-text", "canonical-markdown", "html-source-map",
                "async-html-adapter"])
        let syntax = ArrayList<String>()
        for (rule in dialect.inlineRules.toArray()) {
            syntax.add("inline:${rule.extensionId}/${rule.ruleId}")
        }
        for (rule in dialect.blockRules.toArray()) {
            syntax.add("block:${rule.extensionId}/${rule.ruleId}")
        }
        supportedSyntaxKinds = ImmutableArray<String>(syntax.toArray())
        dslSchemaVersions = ImmutableArray<String>(["1"])
        spiVersions = ImmutableArray<String>(["1"])
        positionEncodings = ImmutableArray<String>(["utf-8-byte", "utf-16-code-unit", "visual"])
        serializationVersions = ImmutableArray<String>(["parse-artifact-1", "markdown-snapshot-binary-1"])
        incrementalSupport = true
        incrementalMode = "block-local-with-full-fallback"
        losslessSupport = true
        multiDocumentSupport = true
        htmlToMarkdownSupport = true
        virtualTreeSupport = true
        pluginIsolationPortVersion = "markdown-isolation-ipc-1"
        builtInPluginOsSandbox = false
    }

    public func extension(extensionId: String): ?ExtensionCapabilityReport {
        for (index in 0..extensionCapabilities.size) {
            if (extensionCapabilities[index].extensionId == extensionId) {
                return Some(extensionCapabilities[index])
            }
        }
        None
    }
}

extend MarkdownEngine {
    public func capabilities(): EngineCapabilities {
        EngineCapabilities(dialect)
    }
}
