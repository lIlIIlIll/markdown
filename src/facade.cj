package markdown

// cjlint-ignore -start !G.ENU.01 Public Markdown facade is frozen despite the DSL enum sugar name.
public class Markdown {
    public static func parse(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): ParseResult {
        MarkdownEngine.builder().profile(profile).build().parse(source)
    }

    public static func toSafeHtml(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        HtmlRenderer().render(parse(source, profile: profile).document)
    }

    public static func toSpecHtml(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        HtmlRenderer(options: HtmlOptions.specCompatible()).render(parse(source, profile: profile).document)
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
            node => match (node) {
                case code: CodeBlock =>
                    let span = match (code.span) {
                        case Some(value) => value;
                        case None => SourceSpan(0, 0)
                    }
                    RewriteAction.Replace(
                        CodeBlock(code.nodeId, code.codeKind, code.literal, span, fenceCharacter: code.fenceCharacter,
                            fenceLength: code.fenceLength, openingFenceSpan: code.openingFenceSpan,
                            closingFenceSpan: code.closingFenceSpan, infoRaw: code.infoRaw, language: code.language,
                            attributesRaw: code.attributesRaw))
                case html: HtmlBlock =>
                    let span = match (html.span) {
                        case Some(value) => value;
                        case None => SourceSpan(0, 0)
                    }
                    RewriteAction.Replace(HtmlBlock(html.nodeId, html.literal, html.blockType, span))
                case text: Text =>
                    let span = match (text.span) {
                        case Some(value) => value;
                        case None => SourceSpan(0, 0)
                    }
                    RewriteAction.Replace(Text(text.nodeId, text.raw, text.value, span, text.normalized, text.origin))
                case _ => RewriteAction.Keep
            }
        })
    }
}
