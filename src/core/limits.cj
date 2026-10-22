package markdown.core

import std.sync.AtomicBool

/** 在构造 literal 时累计字节上限、扫描预算和协作式取消检查。 */
protected class BoundedLiteralBuilder {
    private let builder = StringBuilder()
    private let maximumBytes: Int64
    private let budget: OperationBudget
    private let cancellation: CancellationToken
    private let phase: String
    private var bytes: Int64 = 0

    /** 创建单个 literal 的受限构造器。
     * @param maximumBytes 允许生成的最大 UTF-8 字节数。
     * @param budget 所属操作共享的预算；追加的每个字节计入扫描。
     * @param cancellation 追加与结束时检查的取消信号。
     * @param phase 取消及超限错误报告的阶段名。
     */
    protected init(maximumBytes: Int64, budget: OperationBudget, cancellation: CancellationToken, phase: String) {
        this.maximumBytes = maximumBytes
        this.budget = budget
        this.cancellation = cancellation
        this.phase = phase
    }

    /** 在检查 literal 上限和扫描预算后追加一段 UTF-8 文本。
     * @param value 待追加的文本；按字节数计费。
     */
    protected func append(value: String): Unit {
        consume(value.size)
        builder.append(value)
    }

    /** 追加一个可独立解码为 UTF-8 的字节并计入 literal 限制。
     * @param value 要追加的单字节 UTF-8 文本；不能用此方法逐字节追加多字节字符。
     */
    protected func appendByte(value: Byte): Unit {
        consume(1)
        builder.append(String.fromUtf8([value]))
    }

    /** 检查取消后读取累计 literal。
     * @return 所有已追加文本按顺序拼接的字符串。
     */
    protected func finish(): String {
        cancellation.throwIfCancelled(phase: phase)
        builder.toString()
    }

    private func consume(count: Int64): Unit {
        cancellation.throwIfCancelled(phase: phase)
        let observed = bytes + count
        if (observed > maximumBytes) {
            throw LimitExceededException("literal_bytes", maximumBytes, observed, phase)
        }
        // Literal construction is real parser work and must participate in the
        // same operation budget instead of becoming an unmetered copy loop.
        budget.consumeScan(steps: count)
        bytes = observed
    }
}

/**
 * 解析和渲染使用的结构上限集合。
 *
 * 所有构造参数必须为正数。`safe()` 是默认配置；`trusted()` 为可信、
 * 较大输入提供更高上限，但不会改变解析语义。
 */
public class ParseLimits {
    /** 输入的最大字节数。 */
    public let maximumInputBytes: Int64
    /** 单行的最大字节数。 */
    public let maximumLineBytes: Int64
    /** 最大嵌套深度。 */
    public let maximumNestingDepth: Int64
    /** AST 节点总数上限。 */
    public let maximumAstNodes: Int64
    /** 引用定义、脚注引用及生成的锚点/回链的累计上限。 */
    public let maximumReferences: Int64
    /** 表格列数上限。 */
    public let maximumTableColumns: Int64
    /** URL 的最大字节数。 */
    public let maximumUrlBytes: Int64
    /** 单个 literal 的最大字节数。 */
    public let maximumLiteralBytes: Int64
    /** 输出的最大字节数。 */
    public let maximumOutputBytes: Int64
    /** 扩展捕获内容的最大字节数。 */
    public let maximumExtensionCaptureBytes: Int64
    /** 扩展向前查看的最大字节数。 */
    public let maximumExtensionLookaheadBytes: Int64

    /**
     * 创建限制集合；任一参数非正时抛出 `IllegalArgumentException`。
     * @param maximumInputBytes 输入的最大字节数。
     * @param maximumLineBytes 单行的最大字节数。
     * @param maximumNestingDepth 最大嵌套深度。
     * @param maximumAstNodes AST 节点总数上限。
     * @param maximumReferences 引用定义、脚注引用及生成的锚点/回链的累计上限。
     * @param maximumTableColumns 表格列数上限。
     * @param maximumUrlBytes URL 的最大字节数。
     * @param maximumLiteralBytes 单个 literal 的最大字节数。
     * @param maximumOutputBytes 输出的最大字节数。
     * @param maximumExtensionCaptureBytes 扩展捕获内容的最大字节数。
     * @param maximumExtensionLookaheadBytes 扩展向前查看的最大字节数。
     */
    public init(
        maximumInputBytes: Int64,
        maximumLineBytes: Int64,
        maximumNestingDepth: Int64,
        maximumAstNodes: Int64,
        maximumReferences: Int64,
        maximumTableColumns: Int64,
        maximumUrlBytes: Int64,
        maximumLiteralBytes: Int64,
        maximumOutputBytes: Int64,
        maximumExtensionCaptureBytes: Int64,
        maximumExtensionLookaheadBytes: Int64
    ) {
        let values = [
            maximumInputBytes,
            maximumLineBytes,
            maximumNestingDepth,
            maximumAstNodes,
            maximumReferences,
            maximumTableColumns,
            maximumUrlBytes,
            maximumLiteralBytes,
            maximumOutputBytes,
            maximumExtensionCaptureBytes,
            maximumExtensionLookaheadBytes
        ]
        for (value in values) {
            if (value <= 0) {
                throw IllegalArgumentException("parse limits must be positive")
            }
        }
        this.maximumInputBytes = maximumInputBytes
        this.maximumLineBytes = maximumLineBytes
        this.maximumNestingDepth = maximumNestingDepth
        this.maximumAstNodes = maximumAstNodes
        this.maximumReferences = maximumReferences
        this.maximumTableColumns = maximumTableColumns
        this.maximumUrlBytes = maximumUrlBytes
        this.maximumLiteralBytes = maximumLiteralBytes
        this.maximumOutputBytes = maximumOutputBytes
        this.maximumExtensionCaptureBytes = maximumExtensionCaptureBytes
        this.maximumExtensionLookaheadBytes = maximumExtensionLookaheadBytes
    }

    /**
     * 返回面向不可信输入的默认限制。
     * @return 面向不可信输入的默认限制。
     */
    public static func safe(): ParseLimits {
        ParseLimits(
            32 * 1024 * 1024,
            8 * 1024 * 1024,
            256,
            1000000,
            100000,
            1024,
            1024 * 1024,
            16 * 1024 * 1024,
            128 * 1024 * 1024,
            1024 * 1024,
            64 * 1024
        )
    }

    /**
     * 返回面向可信大文档的宽松限制。
     * @return 面向可信大文档的宽松限制。
     */
    public static func trusted(): ParseLimits {
        ParseLimits(
            256 * 1024 * 1024,
            64 * 1024 * 1024,
            2048,
            8000000,
            800000,
            8192,
            8 * 1024 * 1024,
            128 * 1024 * 1024,
            1024 * 1024 * 1024,
            8 * 1024 * 1024,
            512 * 1024
        )
    }
}

/**
 * 按单次操作累计消耗的可变工作预算。
 *
 * 每次 parse、render 或 transform 应创建独立实例。该类型不是线程安全对象，
 * 不能并发使用或在不同操作间复用；同一操作的多个阶段应共享预算以累计真实工作量。
 */
public class OperationBudget {
    private let maximumScanSteps: Int64
    private let maximumDelimiterSteps: Int64
    private let maximumExtensionCallbacks: Int64
    private let maximumTransformSteps: Int64
    private let maximumRenderedNodes: Int64
    private let maximumOutputBytes: Int64
    private var remainingScanSteps: Int64
    private var remainingDelimiterSteps: Int64
    private var remainingExtensionCallbacks: Int64
    private var remainingTransformSteps: Int64
    private var remainingRenderedNodes: Int64
    private var remainingOutputBytes: Int64

    /**
     * 创建操作预算；任一参数为负时抛出 `IllegalArgumentException`。
     * @param maximumScanSteps 扫描步数上限。
     * @param maximumDelimiterSteps delimiter 处理步数上限。
     * @param maximumExtensionCallbacks 扩展回调次数上限。
     * @param maximumTransformSteps transform 步数上限。
     * @param maximumRenderedNodes 渲染节点数上限。
     * @param maximumOutputBytes 输出字节数上限。
     */
    public init(
        maximumScanSteps: Int64,
        maximumDelimiterSteps: Int64,
        maximumExtensionCallbacks: Int64,
        maximumTransformSteps: Int64,
        maximumRenderedNodes: Int64,
        maximumOutputBytes: Int64
    ) {
        let values = [maximumScanSteps, maximumDelimiterSteps, maximumExtensionCallbacks, maximumTransformSteps,
            maximumRenderedNodes, maximumOutputBytes]
        for (value in values) {
            if (value < 0) {
                throw IllegalArgumentException("operation budgets must be non-negative")
            }
        }
        this.maximumScanSteps = maximumScanSteps
        this.maximumDelimiterSteps = maximumDelimiterSteps
        this.maximumExtensionCallbacks = maximumExtensionCallbacks
        this.maximumTransformSteps = maximumTransformSteps
        this.maximumRenderedNodes = maximumRenderedNodes
        this.maximumOutputBytes = maximumOutputBytes
        remainingScanSteps = maximumScanSteps
        remainingDelimiterSteps = maximumDelimiterSteps
        remainingExtensionCallbacks = maximumExtensionCallbacks
        remainingTransformSteps = maximumTransformSteps
        remainingRenderedNodes = maximumRenderedNodes
        remainingOutputBytes = maximumOutputBytes
    }

    /**
     * 返回默认的非负操作预算；每个 parse、render 或 transform 应独立创建。
     * @return 默认的非负操作预算。
     */
    public static func safe(): OperationBudget {
        OperationBudget(268435456, 67108864, 1000000, 1000000, 4000000, 134217728)
    }

    /** 消费 scan 步数；超出剩余预算时抛出 `BudgetExceeded`。
     * @param steps 要消费的步数。
     * @throws IllegalArgumentException 消费量为负时。
     * @throws MarkdownException 超出剩余预算时。
     */
    public func consumeScan(steps!: Int64 = 1): Unit {
        if (steps < 0) {
            throw IllegalArgumentException("budget consumption must be non-negative")
        }
        if (steps > remainingScanSteps) {
            throw MarkdownException(MarkdownErrorCode.BudgetExceeded, "operation budget exceeded: scan_steps",
                phase: "scan_steps")
        }
        remainingScanSteps -= steps
    }

    /** 消费 delimiter 解析预算。
     * @param steps 要消费的步数。
     * @throws IllegalArgumentException 消费量为负时。
     * @throws MarkdownException 超出剩余预算时。
     */
    public func consumeDelimiter(steps!: Int64 = 1): Unit {
        remainingDelimiterSteps = consume("delimiter_steps", remainingDelimiterSteps, steps)
    }

    /** 消费扩展 callback 预算。
     * @param count 要消费的次数。
     * @throws IllegalArgumentException 消费量为负时。
     * @throws MarkdownException 超出剩余预算时。
     */
    public func consumeExtensionCallback(count!: Int64 = 1): Unit {
        remainingExtensionCallbacks = consume("extension_callbacks", remainingExtensionCallbacks, count)
    }

    /** 消费 AST transform 预算。
     * @param steps 要消费的步数。
     * @throws IllegalArgumentException 消费量为负时。
     * @throws MarkdownException 超出剩余预算时。
     */
    public func consumeTransform(steps!: Int64 = 1): Unit {
        remainingTransformSteps = consume("transform_steps", remainingTransformSteps, steps)
    }

    /** 消费 renderer 节点预算。
     * @param count 要消费的节点数。
     * @throws IllegalArgumentException 消费量为负时。
     * @throws MarkdownException 超出剩余预算时。
     */
    public func consumeRenderedNode(count!: Int64 = 1): Unit {
        remainingRenderedNodes = consume("rendered_nodes", remainingRenderedNodes, count)
    }

    /** 消费输出 byte 预算。
     * @param bytes 要消费的字节数。
     * @throws IllegalArgumentException 消费量为负时。
     * @throws MarkdownException 超出剩余预算时。
     */
    public func consumeOutput(bytes!: Int64 = 1): Unit {
        remainingOutputBytes = consume("output_bytes", remainingOutputBytes, bytes)
    }

    /**
     * 返回已使用的扫描步数。
     * @return 已使用的扫描步数。
     */
    public func usedScanSteps(): Int64 {
        maximumScanSteps - remainingScanSteps
    }
    /**
     * 返回已使用的 delimiter 步数。
     * @return 已使用的 delimiter 步数。
     */
    public func usedDelimiterSteps(): Int64 {
        maximumDelimiterSteps - remainingDelimiterSteps
    }
    /**
     * 返回已使用的扩展回调次数。
     * @return 已使用的扩展回调次数。
     */
    public func usedExtensionCallbacks(): Int64 {
        maximumExtensionCallbacks - remainingExtensionCallbacks
    }
    /**
     * 返回已使用的 transform 步数。
     * @return 已使用的 transform 步数。
     */
    public func usedTransformSteps(): Int64 {
        maximumTransformSteps - remainingTransformSteps
    }
    /**
     * 返回已渲染的节点数。
     * @return 已渲染的节点数。
     */
    public func usedRenderedNodes(): Int64 {
        maximumRenderedNodes - remainingRenderedNodes
    }
    /**
     * 返回已输出的字节数。
     * @return 已输出的字节数。
     */
    public func usedOutputBytes(): Int64 {
        maximumOutputBytes - remainingOutputBytes
    }

    private func consume(kind: String, remaining: Int64, amount: Int64): Int64 {
        if (amount < 0) {
            throw IllegalArgumentException("budget consumption must be non-negative")
        }
        if (amount > remaining) {
            throw MarkdownException(
                MarkdownErrorCode.BudgetExceeded,
                "operation budget exceeded: ${kind}",
                phase: kind
            )
        }
        remaining - amount
    }
}

/** 可在线程间观察的取消标记；取消后下一次检查会抛出 `Cancelled`。 */
public class CancellationToken {
    private let cancelled: AtomicBool

    /** 用共享原子标记创建取消观察端。
     * @param cancelled 与 CancellationSource 共享的取消标记；置位后不会由 token 清除。
     */
    protected init(cancelled: AtomicBool) {
        this.cancelled = cancelled
    }

    /**
     * 返回未取消的独立 token。
     * @return 未取消的独立 token。
     */
    public static func none(): CancellationToken {
        CancellationToken(AtomicBool(false))
    }

    /**
     * 查询当前是否已请求取消。
     * @return 已请求取消时为 `true`。
     */
    public func isCancelled(): Bool {
        cancelled.load()
    }

    /** 若已取消则以给定 phase 抛出 `MarkdownException`。
     * @param phase 异常中报告的阶段名称。
     * @throws MarkdownException 已取消时。
     */
    public func throwIfCancelled(phase!: String = ""): Unit {
        if (cancelled.load()) {
            throw MarkdownException(MarkdownErrorCode.Cancelled, "operation cancelled", phase: phase)
        }
    }
}

/** 创建并触发一个可共享的 `CancellationToken`。 */
public class CancellationSource {
    private let flag = AtomicBool(false)
    /** 由本 source 控制的取消 token。 */
    public let token: CancellationToken

    /** 创建 source 和关联 token。 */
    public init() {
        token = CancellationToken(flag)
    }

    /** 设置取消标记；重复调用保持幂等。 */
    public func cancel(): Unit {
        flag.store(true)
    }
}
