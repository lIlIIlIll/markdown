package markdown

/** 官方扩展目录中的版本、默认 enablement 和支持 profile 信息。 */
public class OfficialExtensionDescriptor {
    /** 官方扩展的稳定 id。 */
    public let extensionId: String
    /** 扩展的目标版本。 */
    public let targetVersion: String
    /** 是否默认启用。 */
    public let defaultEnabled: Bool
    /** 默认启用该扩展的 profile id 列表。 */
    public let defaultProfiles: ImmutableArray<String>
    /**
     * 创建目录条目。
     * @param extensionId 官方扩展的稳定 id。
     * @param targetVersion 扩展的目标版本。
     * @param defaultEnabled 是否默认启用。
     * @param defaultProfiles 默认启用该扩展的 profile id 列表。
     */
    public init(extensionId: String, targetVersion: String, defaultEnabled: Bool, defaultProfiles!: Array<String> = []) {
        this.extensionId = extensionId
        this.targetVersion = targetVersion
        this.defaultEnabled = defaultEnabled
        this.defaultProfiles = ImmutableArray<String>(defaultProfiles)
    }
    /** 判断该扩展是否对指定 profile 默认启用。
     * @param profileId 目标 profile id。
     * @return 对该 profile 默认启用时为 `true`。
     */
    public func isDefaultFor(profileId: String): Bool {
        for (profile in defaultProfiles.toArray()) {
            if (profile == profileId) {
                return true
            }
        }
        false
    }
}

internal class SmartPunctuationProcessor <: ExtensionDocumentProcessor {
    /** 返回扩展 id。 */
    public prop extensionId: String {
        get() {
            "smart-punctuation"
        }
    }
    /** 返回 processor id。 */
    public prop processorId: String {
        get() {
            "smart-punctuation"
        }
    }
    /** 返回 processor 版本。 */
    public prop version: String {
        get() {
            "1"
        }
    }
    /** 返回处理阶段：AST transform。 */
    public prop phase: ExtensionProcessingPhase {
        get() {
            ExtensionProcessingPhase.AstTransform
        }
    }
    /** 返回处理优先级。 */
    public prop priority: Int64 {
        get() {
            100
        }
    }
    /** 返回转换是否确定性。 */
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    /** 将 Text 节点中的省略号和 em/en dash 替换为对应 Unicode 标点。
     * @param document 输入 Document。
     * @param budget transform 操作预算。
     * @param cancellation 协作式取消信号。
     * @return 处理后的 `Document`。
     */
    public func process(document: Document, budget: OperationBudget, cancellation: CancellationToken): Document {
        TreeRewriter.rewrite(document, {
            node => match (node.kind) {
                case NodeKind.Text =>
                    let text = node.asText().getOrThrow()
                    RewriteAction.MapText(text.value.replace("...", "…").replace("---", "—").replace("--", "–"))
                case _ => RewriteAction.Keep
            }
        }, budget: budget, cancellation: cancellation)
    }
}

/** 提供版本化、可选启用的官方扩展和组合 dialect。 */
public class OfficialExtensions {
    /**
     * 返回官方扩展目录；Footnotes、Front Matter、Math 等默认关闭。
     * @return 官方扩展目录。
     */
    public static func catalog(): Array<OfficialExtensionDescriptor> {
        [
            OfficialExtensionDescriptor("gfm-tables", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("gfm-task-lists", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("gfm-strikethrough", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("gfm-autolink", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("footnotes", "2.0", false),
            OfficialExtensionDescriptor("front-matter", "1.1", false),
            OfficialExtensionDescriptor("math", "1.1", false),
            OfficialExtensionDescriptor("definition-lists", "2.0", false),
            OfficialExtensionDescriptor("heading-ids", "2.0", false),
            OfficialExtensionDescriptor("smart-punctuation", "1.1", false),
            OfficialExtensionDescriptor("github-alerts", "future", false),
            OfficialExtensionDescriptor("wikilinks", "future", false)
        ]
    }

    /** 创建包含 P1 官方扩展的组合 dialect。
     * @param profile 作为基础语法的 profile。
     * @return 组合后的 `MarkdownDialect`。
     */
    public static func p1Dialect(profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): MarkdownDialect {
        let builder = MarkdownDialect.define("official-p1", "1").base(profile)
        footnotes(builder)
        frontMatter(builder)
        math(builder)
        definitionLists(builder)
        headingIds(builder)
        smartPunctuation(builder)
        builder.build()
    }

    /** 向 builder 添加 footnotes syntax 和 renderer。
     * @param builder 目标 dialect builder。
     * @return 已启用对应扩展的 builder。
     */
    public static func footnotes(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(
                ExtensionManifest("footnotes", "2.0.0", "builtin-2",
                    capabilities: ExtensionCapabilities(specHtml: true, safeHtml: true, plainText: true, markdown: true,
                        cst: true, format: true, serialize: true, lint: true)))
            .inline(
                InlineSyntax
                    .define("footnotes", "footnote-reference")
                    .delimiter("[^", closer: "]")
                    .content(false)
                    .emitContent(false)
                    .nesting(false)
                    .lineBreaks(false)
                    .emit(FootnoteReferenceEmitter())
                    .flanking(InlineFlankingRule.Any))
            .block(BlockSyntax.define("footnotes", "footnote-definition").footnoteDefinition())
    }

    /** 向 builder 添加仅保留 literal 的 front matter。
     * @param builder 目标 dialect builder。
     * @return 已启用对应扩展的 builder。
     */
    public static func frontMatter(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("front-matter", "1.0.0", "builtin-1", capabilities: renderCapabilities()))
            .block(
                BlockSyntax
                    .define("front-matter", "front-matter")
                    .opener("---")
                    .closer("---")
                    .content(BlockContentMode.Literal)
                    .nesting(false)
                    .kindFromFirstWord(false)
                    .documentStartOnly())
            .renderer(
                RendererRule("front-matter", "front-matter", "pre", classToken: "front-matter", markdownOpener: "---",
                    markdownCloser: "---", renderPayloadLiteral: true))
    }

    /** 向 builder 添加仅保留 literal 的 math syntax。
     * @param builder 目标 dialect builder。
     * @return 已启用对应扩展的 builder。
     */
    public static func math(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("math", "1.0.0", "builtin-1", capabilities: renderCapabilities()))
            .inline(
                InlineSyntax
                    .define("math", "math-inline")
                    .delimiter("$")
                    .content(false)
                    .emitContent(false)
                    .nesting(false)
                    .flanking(InlineFlankingRule.CommonMark))
            .block(
                BlockSyntax
                    .define("math", "math-block")
                    .opener("$$")
                    .closer("$$")
                    .content(BlockContentMode.Literal)
                    .nesting(false)
                    .kindFromFirstWord(false))
            .renderer(
                RendererRule("math", "math-inline", "span", classToken: "math-inline", markdownOpener: "$",
                    markdownCloser: "$", renderPayloadLiteral: true))
            .renderer(
                RendererRule("math", "math-block", "div", classToken: "math-block", markdownOpener: "$$",
                    markdownCloser: "$$", renderPayloadLiteral: true))
    }

    /** 向 builder 添加 definition-list block syntax。
     * @param builder 目标 dialect builder。
     * @return 已启用对应扩展的 builder。
     */
    public static func definitionLists(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("definition-lists", "2.0.0", "builtin-2", capabilities: renderCapabilities()))
            .block(BlockSyntax.define("definition-lists", "definition-list").definitionList())
    }

    /** 向 builder 添加 heading-id metadata syntax。
     * @param builder 目标 dialect builder。
     * @return 已启用对应扩展的 builder。
     */
    public static func headingIds(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(
                ExtensionManifest("heading-ids", "2.0.0", "builtin-2",
                    capabilities: ExtensionCapabilities(specHtml: true, safeHtml: true, plainText: true, markdown: true,
                        cst: true, format: true, serialize: true, lint: true)))
            .inline(InlineSyntax.define("heading-ids", "heading-id").headingIdSuffix())
    }

    /** 向 builder 添加确定性的 smart punctuation transform。
     * @param builder 目标 dialect builder。
     * @return 已启用对应扩展的 builder。
     */
    public static func smartPunctuation(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(
                ExtensionManifest("smart-punctuation", "1.0.0", "builtin-1",
                    capabilities: ExtensionCapabilities(transform: true)))
            .documentProcessor(SmartPunctuationProcessor())
    }

    private static func renderCapabilities(): ExtensionCapabilities {
        ExtensionCapabilities(specHtml: true, safeHtml: true, plainText: true, markdown: true, format: true)
    }
}
