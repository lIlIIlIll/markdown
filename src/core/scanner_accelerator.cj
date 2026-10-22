package markdown.core

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
     * 返回 packed record 格式版本；当前只支持 4。
     * @return packed record 格式版本。
     */
    func recordFormatVersion(): Int64 {
        4
    }
    /**
     * 返回 v4 packed-record buffer 和有效前缀长度。
     * 高位为含换行的行末 byte offset（左移 6）；低位依次为换行宽度（2 bits）、
     * core inline special、delimiter、text lowering 与 reference opener 标志。
     * 不支持当前输入或容量不足时返回 `None`，由纯 Cangjie scanner 完成扫描。
     * @param input 待扫描的 UTF-8 字节输入。
     * @param capacity 本次扫描允许的容量上限。
     * @return packed records 及有效前缀；不受支持时为 `None`。
     */
    func scanLineRecords(input: Array<Byte>, capacity: Int64): ?LineScanRecords
}
