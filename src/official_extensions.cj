package markdown

public class OfficialExtensionDescriptor {
    public let extensionId: String
    public let targetVersion: String
    public let defaultEnabled: Bool
    public let defaultProfiles: ImmutableArray<String>
    public init(extensionId: String, targetVersion: String, defaultEnabled: Bool, defaultProfiles!: Array<String> = []) {
        this.extensionId = extensionId
        this.targetVersion = targetVersion
        this.defaultEnabled = defaultEnabled
        this.defaultProfiles = ImmutableArray<String>(defaultProfiles)
    }
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
    public prop extensionId: String {
        get() {
            "smart-punctuation"
        }
    }
    public prop processorId: String {
        get() {
            "smart-punctuation"
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public prop phase: ExtensionProcessingPhase {
        get() {
            ExtensionProcessingPhase.AstTransform
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop deterministic: Bool {
        get() {
            true
        }
    }
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

public class OfficialExtensions {
    public static func catalog(): Array<OfficialExtensionDescriptor> {
        [
            OfficialExtensionDescriptor("gfm-tables", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("gfm-task-lists", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("gfm-strikethrough", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("gfm-autolink", "1.0", true, defaultProfiles: ["gfm-0.29", "gfm-modern-v1"]),
            OfficialExtensionDescriptor("footnotes", "1.1", false),
            OfficialExtensionDescriptor("front-matter", "1.1", false),
            OfficialExtensionDescriptor("math", "1.1", false),
            OfficialExtensionDescriptor("definition-lists", "1.1", false),
            OfficialExtensionDescriptor("heading-ids", "1.1", false),
            OfficialExtensionDescriptor("smart-punctuation", "1.1", false),
            OfficialExtensionDescriptor("github-alerts", "future", false),
            OfficialExtensionDescriptor("wikilinks", "future", false)
        ]
    }

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

    public static func footnotes(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("footnotes", "1.0.0", "builtin-1", capabilities: renderCapabilities()))
            .inline(
                InlineSyntax
                    .define("footnotes", "footnote-reference")
                    .delimiter("[^", closer: "]")
                    .content(false)
                    .nesting(false)
                    .flanking(InlineFlankingRule.WordBoundary))
            .block(
                BlockSyntax
                    .define("footnotes", "footnote-definition")
                    .linePrefix("[^")
                    .content(BlockContentMode.Markdown)
                    .kindFromFirstWord(false))
            .renderer(
                RendererRule("footnotes", "footnote-reference", "sup", classToken: "footnote-ref", markdownOpener: "[^",
                    markdownCloser: "]"))
            .renderer(
                RendererRule("footnotes", "footnote-definition", "aside", classToken: "footnote-definition",
                    markdownOpener: "[^", markdownBlockLowering: MarkdownBlockLowering.Line))
    }

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

    public static func definitionLists(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("definition-lists", "1.0.0", "builtin-1", capabilities: renderCapabilities()))
            .block(
                BlockSyntax
                    .define("definition-lists", "definition")
                    .linePrefix(": ")
                    .content(BlockContentMode.Markdown)
                    .kindFromFirstWord(false))
            .renderer(
                RendererRule("definition-lists", "definition", "dd", classToken: "definition", markdownOpener: ": ",
                    markdownBlockLowering: MarkdownBlockLowering.Line))
    }

    public static func headingIds(builder: MarkdownDialectBuilder): MarkdownDialectBuilder {
        builder
            .enable(ExtensionManifest("heading-ids", "1.0.0", "builtin-1", capabilities: renderCapabilities()))
            .inline(
                InlineSyntax
                    .define("heading-ids", "heading-id")
                    .metadataSuffix("{#", "}")
                    .emitContent(false)
                    .flanking(InlineFlankingRule.WordBoundary))
            .renderer(
                RendererRule("heading-ids", "heading-id", "span", classToken: "heading-id", markdownOpener: "{#",
                    markdownCloser: "}",
                    attributes: [RendererAttributeSpec("id", RendererAttributeKind.Text,
                        RendererAttributeSource.PayloadLiteral)]))
    }

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
