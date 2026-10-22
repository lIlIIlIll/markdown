package markdown.render

import markdown.core.{CancellationToken, ImmutableArray, NodeId, NodeRef, OperationBudget, SourceSpan}
import std.collection.*

/** 显式可选的三种富内容；不包含任意脚本或自定义命令。 */
public enum RichContentKind {
    /**
     * 数学表达式的 MathML 展示。
     */
    | Math
    /**
     * 图表的 PNG 展示。
     */
    | Diagram
    /**
     * 保留代码原文的 token 高亮展示。
     */
    | Highlight

    /**
     * 返回准备协议中的固定名称。
     * @return math、diagram 或 highlight。
     */
    public func id(): String {
        match (this) {
            case Math => "math"
            case Diagram => "diagram"
            case Highlight => "highlight"
        }
    }
}

/** 准备失败的可观察原因；默认 renderer 继续输出完整源语义。 */
public enum RichContentFailure {
    /**
     * 宿主没有开启该种富内容准备。
     */
    | Disabled
    /**
     * 没有配置后端，或后端运行时不可用。
     */
    | Missing
    /**
     * 后端或请求参数不受支持。
     */
    | Unsupported
    /**
     * 后端超过本次准备的时间上限。
     */
    | TimedOut
    /**
     * 后端失败或产物未通过结构校验。
     */
    | Failed
    /**
     * 产物或后端工作超过富内容上限。
     */
    | Limited

    /**
     * 返回不含后端日志、路径或作者内容的原因码。
     * @return disabled、missing、unsupported、timed-out、failed 或 limited。
     */
    public func code(): String {
        match (this) {
            case Disabled => "disabled"
            case Missing => "missing"
            case Unsupported => "unsupported"
            case TimedOut => "timed-out"
            case Failed => "failed"
            case Limited => "limited"
        }
    }
}

/** 后端只收到源语义；没有 Document、NodeRef、命令、路径或 Front Matter 配置。 */
public class RichContentRequest {
    /**
     * 本次请求的产物类别；请求与返回产物类别必须一致。
     */
    public let kind: RichContentKind
    /**
     * 请求原文；数学表达式或代码正文，不含整个 Document。
     */
    public let source: String
    /**
     * 代码语言标记；默认为空，准备器拒绝超过 128 UTF-8 bytes 的标记。
     */
    public let language: String
    /**
     * 数学表达式是否使用块级展示；默认 false，其他类别不依赖此标记。
     */
    public let display: Bool

    /**
     * 保存富内容请求的源语义，不执行后端或验证产物。
     * @param kind 需要准备的富内容类别。
     * @param source 数学表达式或代码正文。
     * @param language 代码语言标记；默认空字符串。
     * @param display 数学表达式是否为块级展示；默认 false。
     */
    public init(kind: RichContentKind, source: String, language!: String = "", display!: Bool = false) {
        this.kind = kind
        this.source = source
        this.language = language
        this.display = display
    }
}

/** MathML 属性；最终渲染前必须通过固定名称和值域白名单。 */
public class MathMlAttribute {
    /**
     * 候选 MathML 属性名；准备器只接受固定白名单，并拒绝同节点上的重复属性。
     */
    public let name: String
    /**
     * 候选属性值；准备器按属性名和值域校验，不接受任意 HTML、URL 或样式。
     */
    public let value: String

    /**
     * 创建待校验的 MathML 属性，不在构造时授予可信 HTML 能力。
     * @param name 候选 MathML 属性名。
     * @param value 候选属性值。
     */
    public init(name: String, value: String) {
        this.name = name
        this.value = value
    }
}

/** 不可变 MathML 树；空 tag 表示文本，其余 tag 由准备器验证。 */
public class MathMlNode {
    /**
     * MathML 标签名；空字符串表示文本节点，整棵产物的根必须为 math。
     */
    public let tag: String
    /**
     * 文本节点的文字，默认空；标签节点必须保持空字符串。
     */
    public let text: String
    /**
     * 复制保存的候选属性；文本节点不得有属性，标签节点最多 32 个且名称不能重复。
     */
    public let attributes: ImmutableArray<MathMlAttribute>
    /**
     * 按展示顺序复制保存的子节点；文本节点不得有子节点。
     */
    public let children: ImmutableArray<MathMlNode>

    /**
     * 复制数组并创建不可变的候选 MathML 节点。
     *
     * 构造不运行白名单或树上限校验；只有准备器校验成功的产物才能参与富内容渲染。
     * @param tag 标签名；空字符串表示文本节点。
     * @param text 文本节点的文字；默认空字符串。
     * @param attributes 候选属性；默认空数组，输入数组会被复制。
     * @param children 有序子节点；默认空数组，输入数组会被复制。
     */
    public init(tag: String, text!: String = "", attributes!: Array<MathMlAttribute> = [],
        children!: Array<MathMlNode> = []) {
        this.tag = tag
        this.text = text
        this.attributes = ImmutableArray<MathMlAttribute>(attributes)
        this.children = ImmutableArray<MathMlNode>(children)
    }
}

/** 相对请求 source 的 UTF-8 token 范围；未覆盖的间隙仍原样输出。 */
public class CodeHighlightToken {
    /**
     * 相对请求 source 的非空 UTF-8 半开字节范围；token 必须有序、不重叠且端点位于字符边界。
     */
    public let span: SourceSpan
    /**
     * 前景色，必须为 # 加六位十六进制数字；准备器不接受任意 CSS。
     */
    public let color: String
    /**
     * Shiki 字体样式位：italic=1、bold=2、underline=4，可组合为 0..7；默认 0。
     */
    public let fontStyle: Int64

    /**
     * 创建待校验的高亮 token，未覆盖的代码间隙仍按原文输出。
     * @param span 相对请求 source 的非空字节范围。
     * @param color #RRGGBB 形式的前景色。
     * @param fontStyle italic、bold、underline 组合位；默认 0。
     */
    public init(span: SourceSpan, color: String, fontStyle!: Int64 = 0) {
        this.span = span
        this.color = color
        this.fontStyle = fontStyle
    }
}

/** 受控 PNG 字节；复制输入，不将 SVG/HTML 当作可信内容。 */
public class RichPngImage {
    /**
     * 复制保存的候选 PNG 字节；准备器仍须验证 PNG 结构、校验和、尺寸和资源上限。
     */
    public let data: ImmutableArray<Byte>

    /**
     * 复制 PNG 候选字节，不把图片提升为 HTML 或 SVG。
     * @param data 待校验的 PNG 文件字节。
     */
    public init(data: Array<Byte>) {
        this.data = ImmutableArray<Byte>(data)
    }

    /**
     * 读取 PNG IHDR 位置的候选宽度。
     * @return 候选宽度；字节不足时为 0，准备器校验前不能视为有效图片尺寸。
     */
    public prop width: Int64 {
        get() {
            richPngInteger(data, 16)
        }
    }

    /**
     * 读取 PNG IHDR 位置的候选高度。
     * @return 候选高度；字节不足时为 0，准备器校验前不能视为有效图片尺寸。
     */
    public prop height: Int64 {
        get() {
            richPngInteger(data, 20)
        }
    }
}

/** 三种封闭的派生产物；不存在接收第三方 TrustedHtml 的分支。 */
public enum RichContentProduct {
    /**
     * 候选 MathML 树；必须与 Math 请求匹配并通过标签、属性和树上限校验。
     */
    | MathMl(MathMlNode)
    /**
     * 候选高亮 token 数组；必须与 Highlight 请求匹配并通过范围、颜色和数量校验。
     */
    | Highlight(ImmutableArray<CodeHighlightToken>)
    /**
     * 候选 PNG 图片；必须与 Diagram 请求匹配并通过 PNG 与像素上限校验。
     */
    | Diagram(RichPngImage)
}

/** Ready 仍须通过准备器校验；失败不是成功缓存项。 */
public enum RichContentOutcome {
    /**
     * 后端提供了候选产物；准备器校验成功后才会缓存和展示。
     */
    | Ready(RichContentProduct)
    /**
     * 该请求不可用，并携带可观察的失败原因；不会作为成功项缓存。
     */
    | Unavailable(RichContentFailure)
}

/**
 * 显式注入的可信、协作式准备端口；本接口不是操作系统沙箱。
 * @see markdown.render.RichContentPreparer.prepare
 */
public interface RichContentBackend {
    /**
     * 返回固定协议、引擎版本及影响指定产物的配置身份。
     *
     * 身份必须稳定、非空且不超过 1024 UTF-8 bytes；实现或有效配置变化时同步更新，以免缓存复用旧产物。
     * @param kind 需要标识的产物类别。
     * @return 指定类别的语义身份，不应包含本机路径或请求正文。
     */
    func identity(kind: RichContentKind): String
    /**
     * 按请求顺序准备一批候选产物。
     *
     * 实现是可信、协作式宿主代码，须遵守预算、取消和整体时间上限；接口本身不提供操作系统沙箱。返回的 Ready 仍由准备器校验。
     * @param requests 本批请求，结果必须等长且保持顺序。
     * @param limits 本次准备允许的输入、产物和工作集上限。
     * @param budget 与收集、校验阶段共用的累计操作预算。
     * @param cancellation 本次操作的取消 token。
     * @return 每个请求对应的候选产物或失败原因。
     */
    func prepare(requests: Array<RichContentRequest>, limits: RichContentLimits, budget: OperationBudget,
        cancellation: CancellationToken): Array<RichContentOutcome>
}

/** 宿主的显式选择；Markdown 内容不能开启后端或改变配置。 */
public class RichContentOptions {
    /**
     * 是否准备数学表达式；默认 false。
     */
    public let math: Bool
    /**
     * 是否准备代码组之外的 mermaid 图表；默认 false。
     */
    public let diagrams: Bool
    /**
     * 是否准备带语言标记的代码高亮；默认 false。
     */
    public let highlight: Bool
    /**
     * 是否将已启用类别的 Unavailable 转为 prepare 阶段 RenderFailure；默认 false。
     */
    public let strict: Bool

    /**
     * 设置宿主显式选择的能力；Markdown 内容不能自行开启后端。
     * @param math 是否开启 MathML 准备；默认 false。
     * @param diagrams 是否开启图表准备；默认 false。
     * @param highlight 是否开启代码高亮；默认 false。
     * @param strict 已启用类别不可用时是否抛错；默认 false，渲染保留源语义。
     * @example
     * ```cangjie
     * let options = RichContentOptions(math: true, highlight: true)
     * let limits = RichContentLimits(maximumRequests: 16)
     * ```
     */
    public init(math!: Bool = false, diagrams!: Bool = false, highlight!: Bool = false, strict!: Bool = false) {
        this.math = math
        this.diagrams = diagrams
        this.highlight = highlight
        this.strict = strict
    }

    /**
     * 查询宿主是否启用了指定类别。
     * @param kind 待查询的富内容类别。
     * @return 对应 math、diagrams 或 highlight 开关的值。
     */
    protected func enabled(kind: RichContentKind): Bool {
        match (kind) {
            case RichContentKind.Math => math
            case RichContentKind.Diagram => diagrams
            case RichContentKind.Highlight => highlight
        }
    }
}

/** 富内容独立的有界工作集；取消和 OperationBudget 仍由同一操作传递。 */
public class RichContentLimits {
    /**
     * 整份文档收集的请求数上限，包含未启用类别；默认 128，最大 4096。
     */
    public let maximumRequests: Int64
    /**
     * 每个请求 source 的 UTF-8 字节上限；默认 1048576。
     */
    public let maximumInputBytes: Int64
    /**
     * 整份文档请求 source 的累计 UTF-8 字节上限；默认 4194304。
     */
    public let maximumTotalInputBytes: Int64
    /**
     * 每个校验后产物的计量字节上限；默认 8388608，不等于最终 HTML 长度或进程内存。
     */
    public let maximumOutputBytes: Int64
    /**
     * 本次准备中成功产物的累计计量字节上限；默认 33554432，不是最终渲染输出预算。
     */
    public let maximumTotalOutputBytes: Int64
    /**
     * 每个 MathML 产物的节点数上限，包含文本节点；默认 65536。
     */
    public let maximumTreeNodes: Int64
    /**
     * MathML 树深度上限，根深度为 1；默认 128，最大 1024。
     */
    public let maximumTreeDepth: Int64
    /**
     * 每个高亮产物的 token 数上限；默认 131072。
     */
    public let maximumTokens: Int64
    /**
     * 每张 PNG 的宽乘高像素数上限；默认 4194304。
     */
    public let maximumImagePixels: Int64
    /**
     * 传递给后端的整体作业毫秒上限；默认 30000，最大 300000，通用接口依赖后端协作执行。
     */
    public let maximumTimeMilliseconds: Int64

    /**
     * 创建正整数富内容上限；与解析和最终 HTML 输出的预算分开计量。
     *
     * 所有参数范围为 1..2147483647，另外请求数最多 4096、树深最多 1024、时间最多 300000 毫秒。后端可以施加更小的能力上限。
     * @param maximumRequests 整份文档请求数上限；默认 128。
     * @param maximumInputBytes 单请求 source 字节上限；默认 1048576。
     * @param maximumTotalInputBytes 累计 source 字节上限；默认 4194304。
     * @param maximumOutputBytes 单产物计量字节上限；默认 8388608。
     * @param maximumTotalOutputBytes 成功产物累计计量字节上限；默认 33554432。
     * @param maximumTreeNodes 单 MathML 树节点数上限；默认 65536。
     * @param maximumTreeDepth MathML 根为 1 的深度上限；默认 128。
     * @param maximumTokens 单高亮产物 token 数上限；默认 131072。
     * @param maximumImagePixels 单 PNG 像素数上限；默认 4194304。
     * @param maximumTimeMilliseconds 后端整体时间毫秒上限；默认 30000。
     * @throws IllegalArgumentException 参数超出上述范围时。
     */
    public init(maximumRequests!: Int64 = 128, maximumInputBytes!: Int64 = 1048576,
        maximumTotalInputBytes!: Int64 = 4194304, maximumOutputBytes!: Int64 = 8388608,
        maximumTotalOutputBytes!: Int64 = 33554432, maximumTreeNodes!: Int64 = 65536, maximumTreeDepth!: Int64 = 128,
        maximumTokens!: Int64 = 131072, maximumImagePixels!: Int64 = 4194304, maximumTimeMilliseconds!: Int64 = 30000) {
        for (value in [maximumRequests, maximumInputBytes, maximumTotalInputBytes, maximumOutputBytes,
            maximumTotalOutputBytes, maximumTreeNodes, maximumTreeDepth, maximumTokens, maximumImagePixels,
            maximumTimeMilliseconds]) {
            if (value <= 0 || value > 2147483647) {
                throw IllegalArgumentException("rich content limits must be in 1..2147483647")
            }
        }
        if (maximumRequests > 4096 || maximumTreeDepth > 1024 || maximumTimeMilliseconds > 300000) {
            throw IllegalArgumentException("rich content request, depth or time limit is too large")
        }
        this.maximumRequests = maximumRequests
        this.maximumInputBytes = maximumInputBytes
        this.maximumTotalInputBytes = maximumTotalInputBytes
        this.maximumOutputBytes = maximumOutputBytes
        this.maximumTotalOutputBytes = maximumTotalOutputBytes
        this.maximumTreeNodes = maximumTreeNodes
        this.maximumTreeDepth = maximumTreeDepth
        this.maximumTokens = maximumTokens
        this.maximumImagePixels = maximumImagePixels
        this.maximumTimeMilliseconds = maximumTimeMilliseconds
    }
}

internal class RichCacheValue {
    protected let product: RichContentProduct
    protected let bytes: Int64
    protected init(product: RichContentProduct, bytes: Int64) {
        this.product = product
        this.bytes = bytes
    }
}

/**
 * 宿主拥有的有界 Ready 缓存；不保存 Document、NodeRef 或 SourceBuffer，不可并发使用。
 * @see markdown.render.RichContentPreparer.prepare
 */
public class RichContentCache {
    private let maximumEntries: Int64
    private let maximumBytes: Int64
    private let values = HashMap<String, RichCacheValue>()
    private var bytes: Int64 = 0

    /**
     * 创建由宿主持有的有界成功产物缓存。
     *
     * 达到条目或累计字节容量时整体清空；单产物超过容量时不缓存。不保存 Document、NodeRef 或 SourceBuffer，也不支持并发使用。
     * @param maximumEntries 最大缓存条目数，范围 1..4096；默认 128。
     * @param maximumBytes 产物数据的累计计量字节容量，范围 1..2147483647；默认 8388608，不代表进程堆或 RSS。
     * @throws IllegalArgumentException 容量不在允许范围时。
     * @example
     * ```cangjie
     * let cache = RichContentCache(maximumEntries: 2, maximumBytes: 4096)
     * cache.clear()
     * let remaining = cache.entryCount
     * ```
     */
    public init(maximumEntries!: Int64 = 128, maximumBytes!: Int64 = 8388608) {
        if (maximumEntries < 1 || maximumEntries > 4096 || maximumBytes < 1 || maximumBytes > 2147483647) {
            throw IllegalArgumentException("invalid rich content cache limits")
        }
        this.maximumEntries = maximumEntries
        this.maximumBytes = maximumBytes
    }

    /**
     * 读取当前成功产物缓存的条目数。
     * @return 当前缓存条目数；新建或 clear 后为 0。
     */
    public prop entryCount: Int64 {
        get() {
            values.size
        }
    }
    /**
     * 读取当前缓存的产物数据计量字节总数。
     * @return 缓存产物数据字节数；不包含进程内存、源文档或最终 HTML。
     */
    public prop productBytes: Int64 {
        get() {
            bytes
        }
    }

    /**
     * 移除全部成功产物并将累计计量字节数归零。
     */
    public func clear(): Unit {
        values.clear()
        bytes = 0
    }

    internal func find(key: String): ?RichContentProduct {
        match (values.get(key)) {
            case Some(value) => Some(value.product)
            case None => None
        }
    }

    internal func insert(key: String, product: RichContentProduct, size: Int64): Unit {
        if (size > maximumBytes || values.get(key).isSome()) {
            return
        }
        if (values.size == maximumEntries || size > maximumBytes - bytes) {
            clear()
        }
        values.add(key, RichCacheValue(product, size))
        bytes += size
    }
}

/** 不持有源文档的准备注解；sourceParts 表示粗粒度表达式来源。 */
public class RichPreparedEntry {
    /**
     * 该准备项在所属 Document revision 中的节点身份。
     */
    public let nodeId: NodeId
    /**
     * 该节点请求的富内容类别。
     */
    public let kind: RichContentKind
    /**
     * 复制保存的表达式或代码来源范围；表示粗粒度来源，不保证逐字符映射。
     */
    public let sourceParts: ImmutableArray<SourceSpan>
    /**
     * 已校验成功产物或不可用原因；渲染器只使用 Ready 产物。
     */
    public let outcome: RichContentOutcome
    /**
     * 请求种类、源语义和后端身份的缓存 key；被禁用或无法形成有效身份时可为空。
     */
    protected let key: String

    /**
     * 保存一个节点的准备结果，不持有原始文档。
     * @param nodeId 结果所属节点的身份。
     * @param kind 请求的富内容类别。
     * @param sourceParts 粗粒度来源范围；输入数组会被复制。
     * @param outcome 已校验产物或失败原因。
     * @param key 请求源语义与后端配置形成的缓存 key。
     */
    protected init(nodeId: NodeId, kind: RichContentKind, sourceParts: Array<SourceSpan>, outcome: RichContentOutcome,
        key: String) {
        this.nodeId = nodeId
        this.kind = kind
        this.sourceParts = ImmutableArray<SourceSpan>(sourceParts)
        this.outcome = outcome
        this.key = key
    }
}

/**
 * 仅适用于一个不可变 Document revision 的派生展示，不能写回 AST 或 artifact。
 * 通过 `HtmlRenderer` 的 prepared 参数显式传入，富内容能力由宿主选项开启。
 * @see markdown.render.RichContentOptions
 */
public class RichContentPreparation {
    /**
     * 唯一允许使用该准备结果的不可变 Document revision；相同文本不意味着相同 revision。
     */
    public let documentRevision: Int64
    /**
     * 按准备遍历顺序保存的节点结果；输入数组会被复制。
     */
    public let entries: ImmutableArray<RichPreparedEntry>
    /**
     * 源语义和配置 key、失败原因及校验后产物的 SHA-256 身份；不包含运行时 NodeId。
     */
    public let fingerprint: String
    private let index = HashMap<NodeId, RichPreparedEntry>()

    /**
     * 建立属于一个 Document revision 的准备结果索引。
     * @param revision 结果所属不可变文档的 revision。
     * @param entries 已收集并校验的节点准备项；NodeId 应在该文档内唯一。
     * @param fingerprint 源语义、配置和产物状态的稳定身份。
     */
    protected init(revision: Int64, entries: Array<RichPreparedEntry>, fingerprint: String) {
        documentRevision = revision
        this.fingerprint = fingerprint
        this.entries = ImmutableArray<RichPreparedEntry>(entries)
        for (entry in entries) {
            index.add(entry.nodeId, entry)
        }
    }

    /**
     * 查询当前文档中某节点的准备结果。
     * @param node 与准备结果具有相同 revision 的节点引用。
     * @return 对应准备项；该节点没有准备请求时为 None。
     * @throws IllegalArgumentException 引用来自其他或旧 Document revision 时，即使文本与 NodeId 相同。
     */
    public func entry(node: NodeRef): ?RichPreparedEntry {
        requireRevision(node.revision)
        index.get(node.nodeId)
    }

    internal func requireRevision(revision: Int64): Unit {
        if (revision != documentRevision) {
            throw IllegalArgumentException("rich content preparation belongs to another document revision")
        }
    }
}

internal func richPngInteger(data: ImmutableArray<Byte>, offset: Int64): Int64 {
    if (offset < 0 || offset + 4 > data.size) {
        return 0
    }
    (Int64(data[offset]) << 24) | (Int64(data[offset + 1]) << 16) | (Int64(data[offset + 2]) << 8) | Int64(data[offset +
            3])
}
