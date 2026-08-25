package markdown

public enum ProfileKind {
    | CommonMark0312
    | Gfm029
    | GfmModernV1
    | Custom
}

public class MarkdownProfile {
    public let kind: ProfileKind
    public let id: String
    public let standardVersion: String

    private init(kind: ProfileKind, id: String, standardVersion: String) {
        this.kind = kind
        this.id = id
        this.standardVersion = standardVersion
    }

    public static func commonMark0312(): MarkdownProfile {
        MarkdownProfile(ProfileKind.CommonMark0312, "commonmark-0.31.2", "0.31.2")
    }

    public static func commonMark(): MarkdownProfile {
        commonMark0312()
    }

    public static func gfm029(): MarkdownProfile {
        MarkdownProfile(ProfileKind.Gfm029, "gfm-0.29", "0.29-gfm")
    }

    internal static func gfm029CommonMarkBase(): MarkdownProfile {
        MarkdownProfile(ProfileKind.Custom, "gfm-0.29-commonmark-base", "0.29-gfm")
    }

    public static func gfm(): MarkdownProfile {
        gfmModernV1()
    }

    public static func gfmModernV1(): MarkdownProfile {
        MarkdownProfile(ProfileKind.GfmModernV1, "gfm-modern-v1", "commonmark-0.31.2+gfm-extensions-v1")
    }

    public static func custom(id: String, version: String): MarkdownProfile {
        if (id.isEmpty()) {
            throw IllegalArgumentException("custom profile id must not be empty")
        }
        if (version.isEmpty()) {
            throw IllegalArgumentException("custom profile version must not be empty")
        }
        MarkdownProfile(ProfileKind.Custom, id, version)
    }

    public func sameIdentity(other: MarkdownProfile): Bool {
        id == other.id && standardVersion == other.standardVersion
    }
}

public enum HtmlPolicyKind {
    | SpecCompatible
    | GfmCompatible
    | Safe
}

public class HtmlPolicy {
    public let kind: HtmlPolicyKind
    public let rawHtmlPassThrough: Bool

    private init(kind: HtmlPolicyKind, rawHtmlPassThrough: Bool) {
        this.kind = kind
        this.rawHtmlPassThrough = rawHtmlPassThrough
    }

    public static func specCompatible(): HtmlPolicy {
        HtmlPolicy(HtmlPolicyKind.SpecCompatible, true)
    }

    public static func gfmCompatible(): HtmlPolicy {
        HtmlPolicy(HtmlPolicyKind.GfmCompatible, true)
    }

    public static func safe(): HtmlPolicy {
        HtmlPolicy(HtmlPolicyKind.Safe, false)
    }
}
