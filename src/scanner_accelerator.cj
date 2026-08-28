package markdown

import std.io.InputStream

/** Packed line records plus the valid prefix length.
 *
 * The backing array may have spare capacity after `count`. Consumers must not
 * inspect that tail. This lets trusted accelerators transfer their output
 * buffer without copying it merely to trim unused capacity.
 */
public struct LineScanRecords {
    public let records: Array<UInt64>
    public let count: Int64

    public init(records: Array<UInt64>, count: Int64) {
        this.records = records
        this.count = count
    }
}

/**
 * Optional line-scanner acceleration boundary.
 *
 * The core parser never requires a foreign library. Implementations return the
 * packed line records consumed by the parser, or `None` to request the pure
 * Cangjie fallback. Invalid records are rejected by the parser before use.
 */
public interface LineScannerAccelerator {
    func implementationId(): String
    /** Packed record version. Version 1 stores end-with-newline above three
     * low flag bits. Version 2 adds delimiter classification and uses four.
     * Version 3 adds text-lowering classification and uses five. Version 4
     * adds reference-opener classification and uses six. */
    func recordFormatVersion(): Int64 {
        1
    }
    func scanLines(input: Array<Byte>, capacity: Int64): ?Array<UInt64>

    /** Returns a packed-record buffer and its valid prefix length.
     *
     * Existing accelerators need only implement `scanLines`; the default
     * adapter treats the complete returned array as valid. Implementations
     * that allocate to `capacity` can override this method to avoid trimming
     * the array before the parser consumes it.
     */
    func scanLineRecords(input: Array<Byte>, capacity: Int64): ?LineScanRecords {
        match (scanLines(input, capacity)) {
            case Some(records) => Some(LineScanRecords(records, records.size))
            case None => None
        }
    }
}

/**
 * A Markdown engine view with an explicitly supplied line scanner.
 *
 * Keeping acceleration in this additive wrapper preserves the pure-Cangjie
 * engine ABI and makes the foreign implementation an opt-in dependency.
 */
public class AcceleratedMarkdownEngine {
    private let engine: MarkdownEngine
    private let accelerator: LineScannerAccelerator

    internal init(engine: MarkdownEngine, accelerator: LineScannerAccelerator) {
        this.engine = engine
        this.accelerator = accelerator
    }

    public func parse(
        bytes: Array<Byte>,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseBytesWithAccelerator(bytes, utf8Policy, cancellation, budget, Some(accelerator))
    }

    public func parse(
        input: OwnedUtf8Input,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseOwnedWithAccelerator(input, cancellation, budget, Some(accelerator))
    }

    public func parse(
        input: ReusableUtf8Input,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseReusableWithAccelerator(input, cancellation, budget, Some(accelerator))
    }

    public func parse(
        input: InputStream,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        engine.parseStreamWithAccelerator(input, utf8Policy, cancellation, budget, Some(accelerator))
    }

    public func capabilities(): EngineCapabilities {
        EngineCapabilities(engine.dialect, engine.nativeScannerEnabledValue, Some(accelerator))
    }

    public func executionModels(): ExecutionModelCapabilities {
        ExecutionModelCapabilities(Some(accelerator))
    }
}

extend MarkdownEngine {
    /** Opts byte-oriented parse entry points into a scanner accelerator. */
    public func acceleratedBy(accelerator: LineScannerAccelerator): AcceleratedMarkdownEngine {
        AcceleratedMarkdownEngine(this, accelerator)
    }
}
