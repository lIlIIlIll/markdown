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
    public init() {}

    public func implementationId(): String {
        "markdown-c-scanner-v4"
    }

    public func recordFormatVersion(): Int64 {
        4
    }

    public func scanLines(input: Array<Byte>, capacity: Int64): ?Array<UInt64> {
        match (scanLineRecords(input, capacity)) {
            case Some(result) => Some(result.records.slice(0, result.count))
            case None => None
        }
    }

    public func scanLineRecords(input: Array<Byte>, capacity: Int64): ?LineScanRecords {
        if (capacity <= 0) {
            return None
        }
        let records = Array<UInt64>(capacity, repeat: 0u64)
        let scannedLines = unsafe {
            let inputHandle = acquireArrayRawData(input)
            let recordsHandle = acquireArrayRawData(records)
            try {
                MD_Markdown_ScanLines(inputHandle.pointer, input.size, recordsHandle.pointer, capacity)
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
}
