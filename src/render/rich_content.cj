package markdown.render

import markdown.core.{CancellationToken, ImmutableArray, NodeId, NodeRef, OperationBudget, SourceSpan}
import std.collection.*

/** 显式可选的三种富内容；不包含任意脚本或自定义命令。 */
public enum RichContentKind {
    | Math
    | Diagram
    | Highlight

    /** 返回准备协议中的固定名称。 */
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
    | Disabled
    | Missing
    | Unsupported
    | TimedOut
    | Failed
    | Limited

    /** 返回不含后端日志、路径或作者内容的原因码。 */
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
    public let kind: RichContentKind
    public let source: String
    public let language: String
    public let display: Bool

    /** 创建不可变请求；准备器另行应用累计上限。 */
    public init(kind: RichContentKind, source: String, language!: String = "", display!: Bool = false) {
        this.kind = kind
        this.source = source
        this.language = language
        this.display = display
    }
}

/** MathML 属性；最终渲染前必须通过固定名称和值域白名单。 */
public class MathMlAttribute {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        this.name = name
        this.value = value
    }
}

/** 不可变 MathML 树；空 tag 表示文本，其余 tag 由准备器验证。 */
public class MathMlNode {
    public let tag: String
    public let text: String
    public let attributes: ImmutableArray<MathMlAttribute>
    public let children: ImmutableArray<MathMlNode>

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
    public let span: SourceSpan
    public let color: String
    /** Shiki 的 italic/bold/underline 位，范围 0..7。 */
    public let fontStyle: Int64

    public init(span: SourceSpan, color: String, fontStyle!: Int64 = 0) {
        this.span = span
        this.color = color
        this.fontStyle = fontStyle
    }
}

/** 受控 PNG 字节；复制输入，不将 SVG/HTML 当作可信内容。 */
public class RichPngImage {
    public let data: ImmutableArray<Byte>

    public init(data: Array<Byte>) {
        this.data = ImmutableArray<Byte>(data)
    }

    /** IHDR 宽度；验证前只表示候选值。 */
    public prop width: Int64 {
        get() {
            richPngInteger(data, 16)
        }
    }

    /** IHDR 高度；验证前只表示候选值。 */
    public prop height: Int64 {
        get() {
            richPngInteger(data, 20)
        }
    }
}

/** 三种封闭的派生产物；不存在接收第三方 TrustedHtml 的分支。 */
public enum RichContentProduct {
    | MathMl(MathMlNode)
    | Highlight(ImmutableArray<CodeHighlightToken>)
    | Diagram(RichPngImage)
}

/** Ready 仍须通过准备器校验；失败不是成功缓存项。 */
public enum RichContentOutcome {
    | Ready(RichContentProduct)
    | Unavailable(RichContentFailure)
}

/** 显式注入的可信、协作式准备端口；本接口不是操作系统沙箱。 */
public interface RichContentBackend {
    /** 包含固定引擎/协议版本及实际影响该种产物的配置。 */
    func identity(kind: RichContentKind): String
    /** 按请求顺序返回等长数组，遵守操作预算、取消和整体时间上限。 */
    func prepare(requests: Array<RichContentRequest>, limits: RichContentLimits, budget: OperationBudget,
        cancellation: CancellationToken): Array<RichContentOutcome>
}

/** 宿主的显式选择；Markdown 内容不能开启后端或改变配置。 */
public class RichContentOptions {
    public let math: Bool
    public let diagrams: Bool
    public let highlight: Bool
    public let strict: Bool

    public init(math!: Bool = false, diagrams!: Bool = false, highlight!: Bool = false, strict!: Bool = false) {
        this.math = math
        this.diagrams = diagrams
        this.highlight = highlight
        this.strict = strict
    }

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
    public let maximumRequests: Int64
    public let maximumInputBytes: Int64
    public let maximumTotalInputBytes: Int64
    public let maximumOutputBytes: Int64
    public let maximumTotalOutputBytes: Int64
    public let maximumTreeNodes: Int64
    public let maximumTreeDepth: Int64
    public let maximumTokens: Int64
    public let maximumImagePixels: Int64
    public let maximumTimeMilliseconds: Int64

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

/** 宿主拥有的有界 Ready 缓存；不保存 Document/NodeRef/SourceBuffer，不可并发使用。 */
public class RichContentCache {
    private let maximumEntries: Int64
    private let maximumBytes: Int64
    private let values = HashMap<String, RichCacheValue>()
    private var bytes: Int64 = 0

    /** 容量满时整体清空；字节值统计产物数据，不表示进程堆/RSS。 */
    public init(maximumEntries!: Int64 = 128, maximumBytes!: Int64 = 8388608) {
        if (maximumEntries < 1 || maximumEntries > 4096 || maximumBytes < 1 || maximumBytes > 2147483647) {
            throw IllegalArgumentException("invalid rich content cache limits")
        }
        this.maximumEntries = maximumEntries
        this.maximumBytes = maximumBytes
    }

    public prop entryCount: Int64 {
        get() {
            values.size
        }
    }
    public prop productBytes: Int64 {
        get() {
            bytes
        }
    }

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
    public let nodeId: NodeId
    public let kind: RichContentKind
    public let sourceParts: ImmutableArray<SourceSpan>
    public let outcome: RichContentOutcome
    protected let key: String

    protected init(nodeId: NodeId, kind: RichContentKind, sourceParts: Array<SourceSpan>, outcome: RichContentOutcome,
        key: String) {
        this.nodeId = nodeId
        this.kind = kind
        this.sourceParts = ImmutableArray<SourceSpan>(sourceParts)
        this.outcome = outcome
        this.key = key
    }
}

/** 仅适用于一个不可变 Document revision 的派生展示，不能写回 AST 或 artifact。 */
public class RichContentPreparation {
    public let documentRevision: Int64
    public let entries: ImmutableArray<RichPreparedEntry>
    /** 包含源/配置 key、状态和已校验产物，不包含运行时节点身份。 */
    public let fingerprint: String
    private let index = HashMap<NodeId, RichPreparedEntry>()

    protected init(revision: Int64, entries: Array<RichPreparedEntry>, fingerprint: String) {
        documentRevision = revision
        this.fingerprint = fingerprint
        this.entries = ImmutableArray<RichPreparedEntry>(entries)
        for (entry in entries) {
            index.add(entry.nodeId, entry)
        }
    }

    /** 拒绝旧/外来 NodeRef，即使文本和 NodeId 相同。 */
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
