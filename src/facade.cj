package markdown

// cjlint-ignore -start !G.ENU.01 Public Markdown facade is frozen despite the DSL enum sugar name.
public class Markdown {
    public static func parse(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): ParseResult {
        MarkdownEngine.builder().profile(profile).build().parse(source)
    }

    public static func toSafeHtml(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        HtmlRenderer().render(parse(source, profile: profile).ast)
    }

    public static func toSpecHtml(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        HtmlRenderer(options: HtmlOptions.specCompatible()).render(parse(source, profile: profile).ast)
    }

    public static func toText(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        PlainTextRenderer().render(parse(source, profile: profile).document)
    }

    public static func format(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        CanonicalMarkdownRenderer().render(parse(source, profile: profile).document)
    }
}
// cjlint-ignore -end Public Markdown facade is frozen despite the DSL enum sugar name.

extend Document {
    public func detach(): Document {
        TreeRewriter.rewrite(this, {
            node => match (node.kind) {
                case NodeKind.CodeBlock => RewriteAction.DetachLiteral
                case NodeKind.HtmlBlock => RewriteAction.DetachLiteral
                case NodeKind.Text => RewriteAction.DetachLiteral
                case _ => RewriteAction.Keep
            }
        })
    }
}
