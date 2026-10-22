package markdown.core

/** Parser 采用的内建或调用方定义的 profile 身份。 */
public enum ProfileKind {
    /** 内建 CommonMark 0.31.2 profile。 */
    | CommonMark0312
    /** 内建 GFM 0.29 profile。 */
    | Gfm029
    /** 仓库版本化的 modern GFM profile。 */
    | GfmModernV1
    /** 调用方自定义身份的 profile。 */
    | Custom
}

// ProfileKind is part of the parser semantics, so identity must use a stable
// tag rather than an enum debug representation. In particular, a custom
// profile is not an alias for a built-in profile merely because callers choose
// the same id and version strings.
protected func profileKindIdentityTag(kind: ProfileKind): String {
    match (kind) {
        case ProfileKind.CommonMark0312 => "commonmark-0312"
        case ProfileKind.Gfm029 => "gfm-029"
        case ProfileKind.GfmModernV1 => "gfm-modern-v1"
        case ProfileKind.Custom => "custom"
    }
}

protected func profileIdentityDescriptor(profile: MarkdownProfile): String {
    let descriptor = CanonicalDescriptor()
    descriptor.append("profile-identity-v1")
    descriptor.append(profileKindIdentityTag(profile.kind))
    descriptor.append(profile.id)
    descriptor.append(profile.standardVersion)
    descriptor.toString()
}

/**
 * 描述 Markdown 语法方言的稳定身份。
 *
 * `id` 和 `standardVersion` 会进入文档、artifact 和 dialect 身份判断；
 * `custom` 不会因为字符串相同而被当作内建 profile。
 */
public class MarkdownProfile {
    /** profile 类别。 */
    public let kind: ProfileKind
    /** profile 的稳定唯一 id。 */
    public let id: String
    /** 对齐的标准版本号。 */
    public let standardVersion: String

    private init(kind: ProfileKind, id: String, standardVersion: String) {
        this.kind = kind
        this.id = id
        this.standardVersion = standardVersion
    }

    /**
     * 返回默认的 CommonMark 0.31.2 profile。
     * @return CommonMark 0.31.2 profile。
     */
    public static func commonMark0312(): MarkdownProfile {
        MarkdownProfile(ProfileKind.CommonMark0312, "commonmark-0.31.2", "0.31.2")
    }

    /**
     * 返回 GFM 0.29 profile，用于与该版本语料对齐。
     * @return GFM 0.29 profile。
     */
    public static func gfm029(): MarkdownProfile {
        MarkdownProfile(ProfileKind.Gfm029, "gfm-0.29", "0.29-gfm")
    }

    protected static func gfm029CommonMarkBase(): MarkdownProfile {
        MarkdownProfile(ProfileKind.Custom, "gfm-0.29-commonmark-base", "0.29-gfm")
    }

    /**
     * 返回仓库版本化的 modern GFM profile。
     * @return modern GFM profile。
     */
    public static func gfmModernV1(): MarkdownProfile {
        MarkdownProfile(ProfileKind.GfmModernV1, "gfm-modern-v1", "commonmark-0.31.2+gfm-extensions-v1")
    }

    /** 创建调用方提供身份的 profile；`id` 和 `version` 不能为空。
     * @param id 自定义 profile 的稳定唯一 id。
     * @param version 自定义 profile 的版本字符串。
     * @return 自定义身份的 profile。
     */
    public static func custom(id: String, version: String): MarkdownProfile {
        if (id.isEmpty()) {
            throw IllegalArgumentException("custom profile id must not be empty")
        }
        if (version.isEmpty()) {
            throw IllegalArgumentException("custom profile version must not be empty")
        }
        MarkdownProfile(ProfileKind.Custom, id, version)
    }

    /** 比较 profile kind、ID 和标准版本是否完全一致。
     * @param other 参与比较的另一个 profile。
     * @return 身份完全一致时为 `true`。
     */
    public func sameIdentity(other: MarkdownProfile): Bool {
        profileKindIdentityTag(kind) == profileKindIdentityTag(other.kind) && id == other.id && standardVersion == other
            .standardVersion
    }
}
