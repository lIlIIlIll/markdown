package markdown

import std.sync.AtomicBool

public class ParseLimits {
    public let maximumInputBytes: Int64
    public let maximumLineBytes: Int64
    public let maximumNestingDepth: Int64
    public let maximumAstNodes: Int64
    public let maximumReferences: Int64
    public let maximumTableColumns: Int64
    public let maximumUrlBytes: Int64
    public let maximumLiteralBytes: Int64
    public let maximumOutputBytes: Int64
    public let maximumExtensionCaptureBytes: Int64
    public let maximumExtensionLookaheadBytes: Int64

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

    public static func safe(): OperationBudget {
        OperationBudget(268435456, 67108864, 1000000, 1000000, 4000000, 134217728)
    }

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

    public func consumeDelimiter(steps!: Int64 = 1): Unit {
        remainingDelimiterSteps = consume("delimiter_steps", remainingDelimiterSteps, steps)
    }

    public func consumeExtensionCallback(count!: Int64 = 1): Unit {
        remainingExtensionCallbacks = consume("extension_callbacks", remainingExtensionCallbacks, count)
    }

    public func consumeTransform(steps!: Int64 = 1): Unit {
        remainingTransformSteps = consume("transform_steps", remainingTransformSteps, steps)
    }

    public func consumeRenderedNode(count!: Int64 = 1): Unit {
        remainingRenderedNodes = consume("rendered_nodes", remainingRenderedNodes, count)
    }

    public func consumeOutput(bytes!: Int64 = 1): Unit {
        remainingOutputBytes = consume("output_bytes", remainingOutputBytes, bytes)
    }

    public func usedScanSteps(): Int64 {
        maximumScanSteps - remainingScanSteps
    }
    public func usedDelimiterSteps(): Int64 {
        maximumDelimiterSteps - remainingDelimiterSteps
    }
    public func usedExtensionCallbacks(): Int64 {
        maximumExtensionCallbacks - remainingExtensionCallbacks
    }
    public func usedTransformSteps(): Int64 {
        maximumTransformSteps - remainingTransformSteps
    }
    public func usedRenderedNodes(): Int64 {
        maximumRenderedNodes - remainingRenderedNodes
    }
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

public class CancellationToken {
    private let cancelled: AtomicBool

    internal init(cancelled: AtomicBool) {
        this.cancelled = cancelled
    }

    public static func none(): CancellationToken {
        CancellationToken(AtomicBool(false))
    }

    public func isCancelled(): Bool {
        cancelled.load()
    }

    public func throwIfCancelled(phase!: String = ""): Unit {
        if (cancelled.load()) {
            throw MarkdownException(MarkdownErrorCode.Cancelled, "operation cancelled", phase: phase)
        }
    }
}

public class CancellationSource {
    private let flag = AtomicBool(false)
    public let token: CancellationToken

    public init() {
        token = CancellationToken(flag)
    }

    public func cancel(): Unit {
        flag.store(true)
    }
}
