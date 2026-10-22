package markdown.engine

import markdown.core.{ImmutableArray, LineScannerAccelerator}
import markdown.extensions.{CompiledMarkdownDialect, ExtensionCapabilities, ExtensionManifest}
import std.collection.*

/** 单个 extension manifest 的能力和稳定身份报告。 */
public class ExtensionCapabilityReport {
    /** 扩展的稳定 id。 */
    public let extensionId: String
    /** manifest 的语义版本。 */
    public let semanticVersion: String
    /** 实现版本标识。 */
    public let implementationVersion: String
    /** 要求的 SPI 版本。 */
    public let requiredSpiVersion: String
    /** 该扩展声明的能力集合。 */
    public let capabilities: ExtensionCapabilities
    /** 是否允许在进程间共享。 */
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

/** 当前 engine 支持的 profile、扩展、renderer、序列化和位置编码能力。 */
public class EngineCapabilities {
    /** 支持的 profile id 列表。 */
    public let supportedProfiles: ImmutableArray<String>
    /** 当前 dialect 启用的扩展 id 列表。 */
    public let supportedExtensions: ImmutableArray<String>
    /** 支持的 renderer 名称列表。 */
    public let supportedRenderers: ImmutableArray<String>
    /** 当前 dialect 启用的 inline/block 语法规则标识列表。 */
    public let supportedSyntaxKinds: ImmutableArray<String>
    /** 支持的 DSL schema 版本列表。 */
    public let dslSchemaVersions: ImmutableArray<String>
    /** 支持的扩展 SPI 版本列表。 */
    public let spiVersions: ImmutableArray<String>
    /** 支持的位置编码名称列表。 */
    public let positionEncodings: ImmutableArray<String>
    /** 支持的序列化格式版本列表。 */
    public let serializationVersions: ImmutableArray<String>
    /** 是否支持增量解析。 */
    public let incrementalSupport: Bool
    /** 增量解析模式的说明文本。 */
    public let incrementalMode: String
    /** 是否支持无损 CST 文本。 */
    public let losslessSupport: Bool
    /** 每个 extension manifest 的能力报告。 */
    public let extensionCapabilities: ImmutableArray<ExtensionCapabilityReport>
    /** 是否支持多文档。 */
    public let multiDocumentSupport: Bool
    /** 是否支持 HTML 到 Markdown 转换。 */
    public let htmlToMarkdownSupport: Bool
    /** 是否支持虚拟树（virtual tree）操作。 */
    public let virtualTreeSupport: Bool
    /** 插件隔离端口协议版本。 */
    public let pluginIsolationPortVersion: String
    /** 内建插件是否使用 OS 级沙箱。 */
    public let builtInPluginOsSandbox: Bool
    /** native line scanner 是否可用。 */
    public let nativeScannerAvailable: Bool
    /** native line scanner 是否已启用。 */
    public let nativeScannerEnabled: Bool
    /** 字符串输入是否实际使用 native scanner。 */
    public let nativeScannerUsedForStringInput: Bool

    internal init(
        dialect: CompiledMarkdownDialect,
        lineScannerAccelerator: ?LineScannerAccelerator
    ) {
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
                "resumable-html"])
        let syntax = ArrayList<String>()
        for (rule in dialect.inlineRules.toArray()) {
            syntax.add("inline:${rule.extensionId}/${rule.ruleId}")
        }
        for (rule in dialect.blockRules.toArray()) {
            syntax.add("block:${rule.extensionId}/${rule.ruleId}")
        }
        supportedSyntaxKinds = ImmutableArray<String>(syntax.toArray())
        dslSchemaVersions = ImmutableArray<String>(["1"])
        spiVersions = ImmutableArray<String>(["3"])
        positionEncodings = ImmutableArray<String>(
            ["utf-8-byte", "utf-16-code-unit", "visual-scalar", "visual-scalar-with-tab-stops"])
        serializationVersions = ImmutableArray<String>(["parse-artifact-3", "markdown-snapshot-binary-3"])
        incrementalSupport = true
        incrementalMode = "block-local-with-full-fallback"
        losslessSupport = true
        multiDocumentSupport = true
        htmlToMarkdownSupport = true
        virtualTreeSupport = true
        pluginIsolationPortVersion = "markdown-isolation-ipc-1"
        builtInPluginOsSandbox = false
        nativeScannerAvailable = lineScannerAccelerator.isSome()
        this.nativeScannerEnabled = nativeScannerAvailable
        nativeScannerUsedForStringInput = false
    }

    /** 按 extension ID 查找能力报告。
     * @param extensionId 目标扩展 id。
     * @return 对应的能力报告；不存在时为 `None`。
     */
    public func extension(extensionId: String): ?ExtensionCapabilityReport {
        for (index in 0..extensionCapabilities.size) {
            if (extensionCapabilities[index].extensionId == extensionId) {
                return Some(extensionCapabilities[index])
            }
        }
        None
    }
}

/** 各公开入口的 buffering、增量和 native scanner 执行模型说明。 */
public class ExecutionModelCapabilities {
    /** native scanner 的实现身份；未配置时为空字符串。 */
    public let nativeScannerImplementation: String
    /** stream 输入的执行模型说明。 */
    public let streamInput: String
    /** chunk 输入的执行模型说明。 */
    public let chunkInput: String
    /** tryParse 的失败语义说明。 */
    public let parseOutcome: String
    /** async HTML 输出的执行模型说明。 */
    public let asyncHtml: String

    internal init(lineScannerAccelerator: ?LineScannerAccelerator) {
        nativeScannerImplementation = match (lineScannerAccelerator) {
            case Some(accelerator) => accelerator.implementationId()
            case None => ""
        }
        streamInput = "buffered-before-parse"
        chunkInput = "append-closed-blocks-with-final-binding"
        parseOutcome = "success-result-or-failure-without-document"
        asyncHtml = "resumable-traversal-with-utf8-prefix-acknowledgement"
    }
}

extend MarkdownEngine {
    /**
     * 返回当前 engine 的功能能力和 schema 版本报告。
     * @return 当前 engine 的能力报告。
     */
    public func capabilities(): EngineCapabilities {
        EngineCapabilities(dialect, lineScannerAcceleratorValue)
    }

    /**
     * 返回 stream、chunk、tryParse 和 async HTML 的执行模型。
     * @return 当前 engine 的执行模型报告。
     */
    public func executionModels(): ExecutionModelCapabilities {
        ExecutionModelCapabilities(lineScannerAcceleratorValue)
    }
}
