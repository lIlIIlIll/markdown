package markdown.extensions

import markdown.core.{ImmutableArray, MarkdownProfile}

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

/**
 * 提供版本化、可选启用的官方扩展和组合 dialect。
 *
 * Footnotes 2.0、Heading IDs 2.0 和 Definition Lists 2.0 使用结构化 payload 与最终绑定。
 * Math 2.0 保留 TeX 和精确来源，默认不调用外部数学引擎；Front Matter 1.0 只保留 literal，
 * 不执行配置。Smart Punctuation 2.0 只注册绑定前 transform。Code Groups 1.0 必须单独启用，
 * 保留标题、行高亮与原始 copyText，不执行代码。catalog 还包含 future 条目，不能据目录
 * 中存在名称推断其语法已可用。
 */
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
            OfficialExtensionDescriptor("front-matter", "1.0", false),
            OfficialExtensionDescriptor("math", "2.0", false),
            OfficialExtensionDescriptor("code-groups", "1.0", false),
            OfficialExtensionDescriptor("definition-lists", "2.0", false),
            OfficialExtensionDescriptor("heading-ids", "2.0", false),
            OfficialExtensionDescriptor("smart-punctuation", "2.0", false),
            OfficialExtensionDescriptor("github-alerts", "future", false),
            OfficialExtensionDescriptor("wikilinks", "future", false)
        ]
    }

    /** 创建组合脚注、front matter、数学、定义列表、标题 ID 和智能标点的 dialect。
     * 不包含 Code Groups；添加扩展前仍须核对所选基础 profile 的支持声明。
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

    /**
     * 添加结构化 Math 2.0；默认输出可读 TeX，不调用外部后端。
     * @param builder 要添加 Math 2.0 规则的目标 dialect builder。
     * @return 添加 Math 2.0 规则和安全 lowering 后的同一 builder。
     */
    public static func math(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("math", "2.0.0", "builtin-2", capabilities: renderCapabilities()))
            .inline(
                InlineSyntax
                    .define("math", "math-inline")
                    .delimiter("$")
                    .content(false)
                    .emitContent(false)
                    .nesting(false)
                    .lineBreaks(false)
                    .emit(MathInlineEmitter())
                    .flanking(InlineFlankingRule.CommonMark))
            .block(BlockSyntax.define("math", "math-block").displayMath())
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
                ExtensionManifest("smart-punctuation", "2.0.0", "builtin-2",
                    capabilities: ExtensionCapabilities(parse: false, transform: true)))
            .astTransform(SmartPunctuationTransform())
    }

    /**
     * 显式添加 Code Groups 1.0；不属于 p1Dialect 的默认组合。
     * @param builder 要添加 Code Groups 1.0 规则的目标 dialect builder。
     * @return 添加 Code Groups 1.0 规则后的同一 builder。
     */
    public static func codeGroups(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("code-groups", "1.0.0", "builtin-1", capabilities: renderCapabilities()))
            .block(BlockSyntax.define("code-groups", "code-group").codeGroup())
    }

    private static func renderCapabilities(): ExtensionCapabilities {
        ExtensionCapabilities(specHtml: true, safeHtml: true, plainText: true, markdown: true, format: true)
    }
}
