package markdown.render

import markdown.core.{CodeLineRange, ImmutableArray, NodeRef}

/** 显式为可选 code-groups.js 输出渐进增强数据；不会加载脚本。 */
public class CodeGroupHtmlOptions {
    private static let DEFAULT = CodeGroupHtmlOptions()
    /** 是否输出 tabs/copy 增强所需数据；没有脚本时所有代码仍可见。 */
    public let interactive: Bool
    /** 代码组和 tablist 的可访问名称。 */
    public let groupLabel: String
    /** 复制按钮文本。 */
    public let copyLabel: String
    /** 复制成功的 live status。 */
    public let copiedLabel: String
    /** Clipboard API 失败的 live status。 */
    public let copyFailedLabel: String
    /** 复制超限或不可用的按钮说明。 */
    public let copyUnavailableLabel: String
    /** 单块复制数据上限；最大为 4 MiB，超限仍完整显示代码。 */
    public let maximumCopyBytes: Int64

    /** 返回共享的不可变默认选项，避免普通 renderer 为关闭的功能重复分配。 */
    public static func defaults(): CodeGroupHtmlOptions {
        DEFAULT
    }

    /** 创建独立于 parser 和后端主题的 HTML 选项；文本必须非空且不超过 1024 bytes。 */
    public init(interactive!: Bool = false, groupLabel!: String = "Code examples", copyLabel!: String = "Copy code",
        copiedLabel!: String = "Copied", copyFailedLabel!: String = "Copy failed",
        copyUnavailableLabel!: String = "Copy unavailable", maximumCopyBytes!: Int64 = 1048576) {
        if (maximumCopyBytes < 0 || maximumCopyBytes > 4194304) {
            throw IllegalArgumentException("code copy limit must be between zero and 4 MiB")
        }
        for (label in [groupLabel, copyLabel, copiedLabel, copyFailedLabel, copyUnavailableLabel]) {
            if (label.isEmpty() || label.size > 1024) {
                throw IllegalArgumentException("code group labels must contain 1..1024 bytes")
            }
        }
        this.interactive = interactive
        this.groupLabel = groupLabel
        this.copyLabel = copyLabel
        this.copiedLabel = copiedLabel
        this.copyFailedLabel = copyFailedLabel
        this.copyUnavailableLabel = copyUnavailableLabel
        this.maximumCopyBytes = maximumCopyBytes
    }
}

/** One immutable code String and a bounded mutable traversal cursor per item. */
internal class CodeGroupLineState {
    protected let node: NodeRef
    protected let code: String
    protected let ranges: ImmutableArray<CodeLineRange>
    protected var offset: Int64 = 0
    protected var line: Int64 = 1
    var rangeIndex: Int64 = 0
    protected init(node: NodeRef, code: String, ranges: ImmutableArray<CodeLineRange>) {
        this.node = node
        this.code = code
        this.ranges = ranges
    }
}
