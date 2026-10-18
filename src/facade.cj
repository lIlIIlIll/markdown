package markdown

// cjlint-ignore -start !G.ENU.01 Public Markdown facade is frozen despite the DSL enum sugar name.
/**
 * 无状态的 Markdown 便利门面。
 *
 * 所有方法默认使用 `MarkdownProfile.commonMark0312()`。需要自定义
 * `ParseLimits`、方言、取消或 operation budget 时，请使用 `MarkdownEngine`。
 *
 * ## Example
 *
 * ```cj
 * let result = Markdown.parse("# title")
 * let html = Markdown.toSafeHtml("<em>safe</em>")
 * ```
 */
public class Markdown {
    /**
     * 构造完整 AST、源码缓冲区和诊断；失败会抛出 `MarkdownException`。
     * @param source 要解析的 Markdown 文本。
     * @param profile 使用的语法 profile，默认是 CommonMark 0.31.2。
     * @return 完整的 `ParseResult`。
     */
    public static func parse(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): ParseResult {
        MarkdownEngine.builder().profile(profile).build().parse(source)
    }

    /**
     * 使用 `HtmlOptions.safe()` 将输入渲染为安全 HTML。
     * @param source 要渲染的 Markdown 文本。
     * @param profile 使用的语法 profile。
     * @return 转义 raw HTML 后的 HTML 文本。
     */
    public static func toSafeHtml(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        HtmlRenderer().render(parse(source, profile: profile).ast)
    }

    /**
     * 使用规范兼容的 raw HTML 行为渲染输入。
     *
     * 这是 unsafe 入口；调用方必须确认输入可信，或在更高层提供隔离和清洗。
     * @param source 要渲染的 Markdown 文本。
     * @param profile 使用的语法 profile。
     * @return 规范兼容的 HTML 文本。
     */
    public static unsafe func toSpecHtml(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        HtmlRenderer(options: HtmlOptions.specCompatible()).render(parse(source, profile: profile).ast)
    }

    /**
     * 从完整 AST 提取纯文本；链接 destination 默认不附加到链接文本后。
     * @param source 要解析的 Markdown 文本。
     * @param profile 使用的语法 profile。
     * @return 纯文本结果。
     */
    public static func toText(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        PlainTextRenderer().render(parse(source, profile: profile).document)
    }

    /**
     * 将输入解析后输出确定性的 canonical Markdown。
     * @param source 要格式化的 Markdown 文本。
     * @param profile 使用的语法 profile。
     * @return canonical Markdown 文本。
     */
    public static func format(source: String, profile!: MarkdownProfile = MarkdownProfile.commonMark0312()): String {
        CanonicalMarkdownRenderer().render(parse(source, profile: profile).document)
    }
}
// cjlint-ignore -end Public Markdown facade is frozen despite the DSL enum sugar name.

extend Document {
    /**
     * 将 source-backed 的文本、代码块和 raw HTML literal 转为拥有独立存储的文本，
     * 并返回新的文档；其他节点保持语义和 origin 关系。
     * @return 独立于 source buffer 的 `Document` 副本。
     */
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
