package markdown

import std.io.InputStream

/** packed line records 及其有效前缀长度；`count` 之后的容量不可读取。 */
public struct LineScanRecords {
    /** packed record 数组本体，仅前 `count` 个有效。 */
    public let records: Array<UInt64>
    /** 数组中有效的 packed record 数量。 */
    public let count: Int64

    /**
     * 创建 packed record 集合。
     * @param records packed record 数组本体。
     * @param count 数组中有效的 record 数量。
     */
    public init(records: Array<UInt64>, count: Int64) {
        this.records = records
        this.count = count
    }
}

/**
 * 可选的 line-scanner 加速边界。
 *
 * core parser 不依赖 foreign library；返回 None 时使用纯 Cangjie fallback，
 * 无效 records 会在使用前被拒绝。
 */
public interface LineScannerAccelerator {
    /**
     * 返回加速器的稳定实现身份。
     * @return 稳定实现身份。
     */
    func implementationId(): String
    /**
     * 返回 packed record 格式版本；默认是 1。
     * @return packed record 格式版本。
     */
    func recordFormatVersion(): Int64 {
        1
    }
    /**
     * 将输入按行扫描为 packed records；不受支持或失败时返回 `None`。
     * @param input 待扫描的 UTF-8 字节输入。
     * @param capacity 本次扫描允许的容量上限。
     * @return packed records；不受支持时为 `None`。
     */
    func scanLines(input: Array<Byte>, capacity: Int64): ?Array<UInt64>

    /** 返回 packed-record buffer 和有效前缀长度；默认把 scanLines 全部视为有效。
     * @param input 待扫描的 UTF-8 字节输入。
     * @param capacity 本次扫描允许的容量上限。
     * @return packed records 及有效前缀；不受支持时为 `None`。
     */
    func scanLineRecords(input: Array<Byte>, capacity: Int64): ?LineScanRecords {
        match (scanLines(input, capacity)) {
            case Some(records) => Some(LineScanRecords(records, records.size))
            case None => None
        }
    }
}

/** 使用显式 line scanner 的 engine view；foreign 加速是可选依赖。 */
public class AcceleratedMarkdownEngine {
    private let engine: MarkdownEngine
    private let accelerator: LineScannerAccelerator

    internal init(engine: MarkdownEngine, accelerator: LineScannerAccelerator) {
        this.engine = engine
        this.accelerator = accelerator
    }

    /** 使用 accelerator 解析 byte input。
     * @param bytes 待解析的 UTF-8 字节输入。
     * @param utf8Policy 无效字节序列的处理策略。
     * @param cancellation 协作式取消信号。
     * @param budget 单次解析的操作预算。
     * @return 解析结果。
     */
    public func parse(
        bytes: Array<Byte>,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseBytesWithAccelerator(bytes, utf8Policy, cancellation, budget, Some(accelerator))
    }

    /** 使用 accelerator 解析一次性 OwnedUtf8Input。
     * @param input 待解析的一次性 UTF-8 输入。
     * @param cancellation 协作式取消信号。
     * @param budget 单次解析的操作预算。
     * @return 解析结果。
     */
    public func parse(
        input: OwnedUtf8Input,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseOwnedWithAccelerator(input, cancellation, budget, Some(accelerator))
    }

    /** 使用 accelerator 解析可重复 ReusableUtf8Input。
     * @param input 可重复使用的 UTF-8 输入。
     * @param cancellation 协作式取消信号。
     * @param budget 单次解析的操作预算。
     * @return 解析结果。
     */
    public func parse(
        input: ReusableUtf8Input,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseReusableWithAccelerator(input, cancellation, budget, Some(accelerator))
    }

    /** 使用 accelerator 读取并解析 InputStream。
     * @param input 待读取并解析的输入流。
     * @param utf8Policy 无效字节序列的处理策略。
     * @param cancellation 协作式取消信号。
     * @param budget 单次解析的操作预算。
     * @return 解析结果。
     */
    public func parse(
        input: InputStream,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseStreamWithAccelerator(input, utf8Policy, cancellation, budget, Some(accelerator))
    }

    /**
     * 返回包含 accelerator 状态的能力报告。
     * @return 包含 accelerator 状态的能力报告。
     */
    public func capabilities(): EngineCapabilities {
        EngineCapabilities(engine.dialect, engine.nativeScannerEnabledValue, Some(accelerator))
    }

    /**
     * 返回包含 accelerator 的执行模型报告。
     * @return 包含 accelerator 的执行模型报告。
     */
    public func executionModels(): ExecutionModelCapabilities {
        ExecutionModelCapabilities(Some(accelerator))
    }
}

extend MarkdownEngine {
    /** 将 byte-oriented parse 入口切换到指定 scanner accelerator。
     * @param accelerator 提供 packed line records 的加速器实现。
     * @return 绑定 accelerator 的 engine view。
     */
    public func acceleratedBy(accelerator: LineScannerAccelerator): AcceleratedMarkdownEngine {
        AcceleratedMarkdownEngine(this, accelerator)
    }
}
