package markdown.native

import markdown.{LineScanRecords, LineScannerAccelerator}

foreign func MD_Markdown_ScanLines(
    input: CPointer<UInt8>,
    length: Int64,
    records: CPointer<UInt64>,
    capacity: Int64
): Int64

/** Optional C accelerator. Importing this package requires the native archive. */
public class NativeLineScanner <: LineScannerAccelerator {
    /** 创建 native accelerator 实例。 */
    public init() {}

    /**
     * 返回加速器的稳定实现身份。
     * @return 稳定实现身份。
     */
    public func implementationId(): String {
        "markdown-c-scanner-v4"
    }

    /**
     * 返回 packed record 格式版本。
     * @return packed record 格式版本。
     */
    public func recordFormatVersion(): Int64 {
        4
    }

    /** 将输入按行扫描为 packed records；不受支持时返回 `None`。
     * @param input 待扫描的 UTF-8 字节输入。
     * @param capacity 本次扫描允许的容量上限。
     * @return packed records；不受支持时为 `None`。
     * @throws IllegalStateException 返回的 record 数量非法时。
     */
    public func scanLines(input: Array<Byte>, capacity: Int64): ?Array<UInt64> {
        match (scanLineRecords(input, capacity)) {
            case Some(result) => Some(result.records.slice(0, result.count))
            case None => None
        }
    }

    /** 返回 packed-record buffer 和有效前缀长度；不受支持时返回 `None`。
     * @param input 待扫描的 UTF-8 字节输入。
     * @param capacity 本次扫描允许的容量上限。
     * @return packed records 及有效前缀；不受支持时为 `None`。
     * @throws IllegalStateException 返回的 record 数量非法时。
     */
    public func scanLineRecords(input: Array<Byte>, capacity: Int64): ?LineScanRecords {
        if (capacity <= 0) {
            return None
        }
        let effectiveCapacity = sparseLineRecordCapacity(input, capacity)
        let records = Array<UInt64>(effectiveCapacity, repeat: 0u64)
        let scannedLines = unsafe {
            let inputHandle = acquireArrayRawData(input)
            let recordsHandle = acquireArrayRawData(records)
            try {
                MD_Markdown_ScanLines(inputHandle.pointer, input.size, recordsHandle.pointer, effectiveCapacity)
            } finally {
                releaseArrayRawData(recordsHandle)
                releaseArrayRawData(inputHandle)
            }
        }
        if (scannedLines == -2) {
            return None
        }
        if (scannedLines <= 0 || scannedLines > capacity) {
            throw IllegalStateException("native line scanner returned an invalid record count")
        }
        Some(LineScanRecords(records, scannedLines))
    }

    private func sparseLineRecordCapacity(input: Array<Byte>, upperBound: Int64): Int64 {
        if (input.size < 4096) {
            return upperBound
        }
        var index: Int64 = 0
        while (index < 64) {
            if (input[index] == b'\n' || input[index] == b'\r') {
                return upperBound
            }
            index++
        }
        min(upperBound, max(16, input.size / 128 + 16))
    }
}
