package markdown.render

/** HTML 输出策略的类别。 */
public enum HtmlPolicyKind {
    /** 规范兼容：raw HTML 原样通过。 */
    | SpecCompatible
    /** GFM 兼容：raw HTML 通过并采用 GFM 行为。 */
    | GfmCompatible
    /** 安全模式：转义 raw HTML。 */
    | Safe
}

/** HTML 策略的不可变描述；`rawHtmlPassThrough` 表示是否原样保留 raw HTML。 */
public class HtmlPolicy {
    /** 策略类别。 */
    public let kind: HtmlPolicyKind
    /** 是否原样保留 raw HTML。 */
    public let rawHtmlPassThrough: Bool

    private init(kind: HtmlPolicyKind, rawHtmlPassThrough: Bool) {
        this.kind = kind
        this.rawHtmlPassThrough = rawHtmlPassThrough
    }

    /**
     * 返回允许 raw HTML 原样通过的规范兼容策略。
     * @return 规范兼容的 HTML policy。
     */
    public static func specCompatible(): HtmlPolicy {
        HtmlPolicy(HtmlPolicyKind.SpecCompatible, true)
    }

    /**
     * 返回允许 raw HTML 通过并采用 GFM 兼容行为的策略。
     * @return GFM 兼容的 HTML policy。
     */
    public static func gfmCompatible(): HtmlPolicy {
        HtmlPolicy(HtmlPolicyKind.GfmCompatible, true)
    }

    /**
     * 返回转义 raw HTML 的安全策略。
     * @return 转义 raw HTML 的安全策略。
     */
    public static func safe(): HtmlPolicy {
        HtmlPolicy(HtmlPolicyKind.Safe, false)
    }
}
