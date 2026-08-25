package markdown

import std.collection.*
import std.convert.*
import std.io.InputStream
import std.unicode.*

public enum Utf8Policy {
    | Strict
    | ReplaceInvalid
}

public class ParseResult {
    public let document: Document
    public let source: SourceBuffer
    public let diagnostics: ImmutableArray<Diagnostic>
    public let isComplete: Bool
    public let stoppedAt: ?SourceSpan
    public let unfinishedPhase: String
    public let errors: ImmutableArray<MarkdownException>

    public init(document: Document, source: SourceBuffer, diagnostics: Array<Diagnostic>, isComplete!: Bool = true,
        stoppedAt!: ?SourceSpan = None, unfinishedPhase!: String = "", errors!: Array<MarkdownException> = []) {
        this.document = document
        this.source = source
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
        this.isComplete = isComplete
        this.stoppedAt = stoppedAt
        this.unfinishedPhase = unfinishedPhase
        this.errors = ImmutableArray<MarkdownException>(errors)
    }
}

public class MarkdownEngineBuilder {
    private var profileValue = MarkdownProfile.commonMark0312()
    private var limitsValue = ParseLimits.safe()
    private var dialectValue: ?MarkdownDialect = None
    private var limitsExplicit = false
    private var nativeScannerEnabledValue = true

    public init() {}

    public func profile(profile: MarkdownProfile): MarkdownEngineBuilder {
        profileValue = profile
        dialectValue = None
        this
    }

    public func limits(limits: ParseLimits): MarkdownEngineBuilder {
        limitsValue = limits
        limitsExplicit = true
        this
    }

    public func dialect(dialect: MarkdownDialect): MarkdownEngineBuilder {
        dialectValue = Some(dialect)
        profileValue = dialect.baseProfile
        if (!limitsExplicit) {
            limitsValue = dialect.limits
        }
        this
    }

    public func nativeScannerEnabled(enabled: Bool): MarkdownEngineBuilder {
        nativeScannerEnabledValue = enabled
        this
    }

    public func build(): MarkdownEngine {
        let compiled = match (dialectValue) {
            case Some(dialect) => DialectCompiler.compile(dialect)
            case None => CompiledMarkdownDialect.builtin(profileValue)
        }
        MarkdownEngine(profileValue, limitsValue, compiled, nativeScannerEnabledValue)
    }
}

public class MarkdownEngine {
    public let profile: MarkdownProfile
    public let limits: ParseLimits
    public let dialect: CompiledMarkdownDialect
    internal let nativeScannerEnabledValue: Bool

    internal init(profile: MarkdownProfile, limits: ParseLimits, dialect: CompiledMarkdownDialect,
        nativeScannerEnabled: Bool) {
        this.profile = profile
        this.limits = limits
        this.dialect = dialect
        this.nativeScannerEnabledValue = nativeScannerEnabled
    }

    public static func builder(): MarkdownEngineBuilder {
        MarkdownEngineBuilder()
    }

    public func parse(
        value: String,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        cancellation.throwIfCancelled(phase: "input")
        if (value.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, value.size, "input")
        }
        let noAccelerator: ?LineScannerAccelerator = None
        parseSource(SourceBuffer(value), [], cancellation, budget, noAccelerator)
    }

    public func parsePartial(
        value: String,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        tryParse(value, cancellation: cancellation, budget: budget)
    }

    /**
     * Returns either a complete parse or a failure result with an empty
     * document. It does not expose a completed AST prefix.
     */
    public func tryParse(
        value: String,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        try {
            parse(value, cancellation: cancellation, budget: budget)
        } catch (error: MarkdownException) {
            let source = SourceBuffer(value)
            let document = Document(NodeId(1), [], SourceSpan(0, source.byteLength()), profile, dialect.fingerprint)
            ParseResult(document, source, [], isComplete: false, stoppedAt: error.span, unfinishedPhase: error.phase,
                errors: [error])
        }
    }

    public func parse(
        bytes: Array<Byte>,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        let noAccelerator: ?LineScannerAccelerator = None
        parseBytesWithAccelerator(bytes, utf8Policy, cancellation, budget, noAccelerator)
    }

    internal func parseBytesWithAccelerator(
        bytes: Array<Byte>,
        utf8Policy: Utf8Policy,
        cancellation: CancellationToken,
        budget: OperationBudget,
        accelerator: ?LineScannerAccelerator
    ): ParseResult {
        cancellation.throwIfCancelled(phase: "input")
        if (bytes.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, bytes.size, "input")
        }
        let decoded = decodeUtf8Input(bytes, utf8Policy)
        parseSource(decoded.source, decoded.diagnostics, cancellation, budget, accelerator)
    }

    public func parse(
        input: OwnedUtf8Input,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        let noAccelerator: ?LineScannerAccelerator = None
        parseOwnedWithAccelerator(input, cancellation, budget, noAccelerator)
    }

    internal func parseOwnedWithAccelerator(
        input: OwnedUtf8Input,
        cancellation: CancellationToken,
        budget: OperationBudget,
        accelerator: ?LineScannerAccelerator
    ): ParseResult {
        cancellation.throwIfCancelled(phase: "input")
        let bytes = input.consume()
        if (bytes.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, bytes.size, "input")
        }
        try {
            let value = String.fromUtf8(bytes)
            parseSource(SourceBuffer(value, bytes, true), [], cancellation, budget, accelerator)
        } catch (error: MarkdownException) {
            throw error
        } catch (_: Exception) {
            throw MarkdownException(MarkdownErrorCode.InvalidEncoding, "invalid UTF-8 input", phase: "input")
        }
    }

    public func parse(
        input: InputStream,
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ParseResult {
        let noAccelerator: ?LineScannerAccelerator = None
        parseStreamWithAccelerator(input, utf8Policy, cancellation, budget, noAccelerator)
    }

    internal func parseStreamWithAccelerator(
        input: InputStream,
        utf8Policy: Utf8Policy,
        cancellation: CancellationToken,
        budget: OperationBudget,
        accelerator: ?LineScannerAccelerator
    ): ParseResult {
        let bytes = ArrayList<Byte>()
        let buffer = Array<Byte>(8192, repeat: 0)
        try {
            while (true) {
                cancellation.throwIfCancelled(phase: "input")
                let count = input.read(buffer)
                if (count == 0) {
                    break
                }
                if (count < 0) {
                    throw IllegalStateException("InputStream returned a negative byte count")
                }
                if (bytes.size + count > limits.maximumInputBytes) {
                    throw LimitExceededException("input_bytes", limits.maximumInputBytes, bytes.size + count, "input")
                }
                for (index in 0..count) {
                    bytes.add(buffer[index])
                }
            }
        } catch (error: MarkdownException) {
            throw error
        } catch (error: Exception) {
            throw InputReadFailureException(error)
        }
        parseBytesWithAccelerator(bytes.toArray(), utf8Policy, cancellation, budget, accelerator)
    }

    public func newSession(
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): ChunkedParseSession {
        ChunkedParseSession(this, utf8Policy, cancellation, budget)
    }

    /** Creates a session that buffers all input and parses only at finish(). */
    public func newBufferedInputSession(
        utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()
    ): BufferedInputSession {
        BufferedInputSession(this, utf8Policy, cancellation, budget)
    }

    private func parseSource(
        source: SourceBuffer,
        inputDiagnostics: Array<Diagnostic>,
        cancellation: CancellationToken,
        budget: OperationBudget,
        accelerator: ?LineScannerAccelerator
    ): ParseResult {
        ParserSession(profile, limits, cancellation, budget, source, dialect, nativeScannerEnabledValue, accelerator)
            .parse(inputDiagnostics)
    }
}

public class ChunkedParseSession {
    private let engine: MarkdownEngine
    private let utf8Policy: Utf8Policy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let bytes = ArrayList<Byte>()
    private var finished = false

    internal init(
        engine: MarkdownEngine,
        utf8Policy: Utf8Policy,
        cancellation: CancellationToken,
        budget: OperationBudget
    ) {
        this.engine = engine
        this.utf8Policy = utf8Policy
        this.cancellation = cancellation
        this.budget = budget
    }

    public func feed(chunk: Array<Byte>): Unit {
        if (finished) {
            throw IllegalStateException("chunked session is already finished")
        }
        cancellation.throwIfCancelled(phase: "input")
        if (bytes.size + chunk.size > engine.limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", engine.limits.maximumInputBytes, bytes.size + chunk.size,
                "input")
        }
        bytes.add(all: chunk)
    }

    public func feed(chunk: String): Unit {
        feed(chunk.toArray())
    }

    public func finish(): ParseResult {
        if (finished) {
            throw IllegalStateException("chunked session is already finished")
        }
        finished = true
        engine.parse(bytes.toArray(), utf8Policy: utf8Policy, cancellation: cancellation, budget: budget)
    }
}

public class BufferedInputSession {
    private let engine: MarkdownEngine
    private let utf8Policy: Utf8Policy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let bytes = ArrayList<Byte>()
    private var finished = false

    internal init(
        engine: MarkdownEngine,
        utf8Policy: Utf8Policy,
        cancellation: CancellationToken,
        budget: OperationBudget
    ) {
        this.engine = engine
        this.utf8Policy = utf8Policy
        this.cancellation = cancellation
        this.budget = budget
    }

    public func feed(chunk: Array<Byte>): Unit {
        if (finished) {
            throw IllegalStateException("buffered input session is already finished")
        }
        cancellation.throwIfCancelled(phase: "input")
        if (bytes.size + chunk.size > engine.limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", engine.limits.maximumInputBytes, bytes.size + chunk.size,
                "input")
        }
        bytes.add(all: chunk)
    }

    public func feed(chunk: String): Unit {
        feed(chunk.toArray())
    }

    public func finish(): ParseResult {
        if (finished) {
            throw IllegalStateException("buffered input session is already finished")
        }
        finished = true
        engine.parse(bytes.toArray(), utf8Policy: utf8Policy, cancellation: cancellation, budget: budget)
    }
}

internal class DecodedInput {
    let source: SourceBuffer
    let diagnostics: Array<Diagnostic>

    init(source: SourceBuffer, diagnostics: Array<Diagnostic>) {
        this.source = source
        this.diagnostics = diagnostics
    }
}

internal struct LineRecord {
    let text: String
    let startByte: Int64
    let endByte: Int64
    let endWithNewline: Int64
    let allowSetext: Bool
    // Root lines record this while splitLines is already walking the input.
    // Nested/normalized lines conservatively retain the source value unless a
    // caller can prove that the transformed content is plain.
    let hasCoreInlineSpecial: Bool

    init(text: String, startByte: Int64, endByte: Int64, endWithNewline: Int64, allowSetext!: Bool = true,
        hasCoreInlineSpecial!: Bool = true) {
        this.text = text
        this.startByte = startByte
        this.endByte = endByte
        this.endWithNewline = endWithNewline
        this.allowSetext = allowSetext
        this.hasCoreInlineSpecial = hasCoreInlineSpecial
    }
}

internal struct ListMarkerInfo {
    let ordered: Bool
    let startNumber: Int64
    let delimiter: ListDelimiter
    let bullet: Byte
    let indent: Int64
    let contentStart: Int64
    let contentIndent: Int64
    let syntheticIndent: Int64

    init(ordered: Bool, startNumber: Int64, delimiter: ListDelimiter, bullet: Byte, indent: Int64, contentStart: Int64,
        contentIndent: Int64, syntheticIndent: Int64) {
        this.ordered = ordered
        this.startNumber = startNumber
        this.delimiter = delimiter
        this.bullet = bullet
        this.indent = indent
        this.contentStart = contentStart
        this.contentIndent = contentIndent
        this.syntheticIndent = syntheticIndent
    }
}

internal struct InlinePiece {
    var start: Int64
    var length: Int64
    let marker: Byte
    let canOpen: Bool
    let canClose: Bool
    let nodes: Array<MarkdownNode>

    init(start: Int64, length: Int64, marker: Byte, canOpen: Bool, canClose: Bool, nodes!: Array<MarkdownNode> = []) {
        this.start = start
        this.length = length
        this.marker = marker
        this.canOpen = canOpen
        this.canClose = canClose
        this.nodes = nodes
    }
}

internal class InlinePieceLink {
    let identity: Int64
    var piece: InlinePiece
    var previous: ?InlinePieceLink = None
    var next: ?InlinePieceLink = None
    var active: Bool = true

    init(identity: Int64, piece: InlinePiece) {
        this.identity = identity
        this.piece = piece
    }
}

internal enum BlockFrameCompletionKind {
    | Root
    | Quote
    | ListItemFrame
    | Extension
}

internal class PendingQuoteState {
    let lines: Array<LineRecord>
    let spans: Array<SourceSpan>
    let nextIndex: Int64

    init(lines: Array<LineRecord>, spans: Array<SourceSpan>, nextIndex: Int64) {
        this.lines = lines
        this.spans = spans
        this.nextIndex = nextIndex
    }
}

internal class PendingListItemState {
    let lines: Array<LineRecord>
    let span: SourceSpan
    let taskState: TaskState
    let markerSpan: ?SourceSpan

    init(lines: Array<LineRecord>, span: SourceSpan, taskState: TaskState, markerSpan: ?SourceSpan) {
        this.lines = lines
        this.span = span
        this.taskState = taskState
        this.markerSpan = markerSpan
    }
}

internal class PendingListState {
    let marker: ListMarkerInfo
    let tight: Bool
    let items: Array<PendingListItemState>
    let span: SourceSpan
    let nextIndex: Int64
    let nodes = ArrayList<MarkdownNode>()
    var itemIndex: Int64 = 0

    init(marker: ListMarkerInfo, tight: Bool, items: Array<PendingListItemState>, span: SourceSpan, nextIndex: Int64) {
        this.marker = marker
        this.tight = tight
        this.items = items
        this.span = span
        this.nextIndex = nextIndex
    }
}

internal class PendingExtensionState {
    let rule: BlockSyntaxRule
    let name: String
    let parameters: String
    let literal: String
    let values: HashMap<String, SyntaxParameterValue>
    let span: SourceSpan
    let kindId: String
    let lines: Array<LineRecord>
    let suppressedRule: String
    let nextIndex: Int64

    init(rule: BlockSyntaxRule, name: String, parameters: String, literal: String,
        values: HashMap<String, SyntaxParameterValue>, span: SourceSpan, kindId: String, lines: Array<LineRecord>,
        suppressedRule: String, nextIndex: Int64) {
        this.rule = rule
        this.name = name
        this.parameters = parameters
        this.literal = literal
        this.values = values
        this.span = span
        this.kindId = kindId
        this.lines = lines
        this.suppressedRule = suppressedRule
        this.nextIndex = nextIndex
    }
}

internal class ExtensionBlockScan {
    let node: ?MarkdownNode
    let pending: ?PendingExtensionState
    let nextIndex: Int64

    init(node: ?MarkdownNode, pending: ?PendingExtensionState, nextIndex: Int64) {
        this.node = node
        this.pending = pending
        this.nextIndex = nextIndex
    }
}

internal class BlockParseFrame {
    let lines: Array<LineRecord>
    let depth: Int64
    let suppressedRule: String
    let completion: BlockFrameCompletionKind
    let quoteState: ?PendingQuoteState
    let list: ?PendingListState
    let extension: ?PendingExtensionState
    let blocks = ArrayList<MarkdownNode>()
    var index: Int64 = 0

    init(lines: Array<LineRecord>, depth: Int64, suppressedRule: String,
        completion!: BlockFrameCompletionKind = BlockFrameCompletionKind.Root, quoteState!: ?PendingQuoteState = None,
        list!: ?PendingListState = None, extension!: ?PendingExtensionState = None) {
        this.lines = lines
        this.depth = depth
        this.suppressedRule = suppressedRule
        this.completion = completion
        this.quoteState = quoteState
        this.list = list
        this.extension = extension
    }
}

internal class ParserSession {
    private let profile: MarkdownProfile
    private let limits: ParseLimits
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let source: SourceBuffer
    private let dialect: CompiledMarkdownDialect
    private let ids: NodeIdAllocator
    private let nativeScannerEnabled: Bool
    private let lineScannerAccelerator: ?LineScannerAccelerator
    private let diagnostics = ArrayList<Diagnostic>()
    private var references: Array<ReferenceDefinition> = []
    private let referenceIndex = HashMap<String, ReferenceDefinition>()
    private let referenceLineStarts = HashSet<Int64>()
    private var checkpointSteps: Int64 = 0
    private var suppressedInlineRule = ""
    private var suppressedBlockRule = ""

    init(profile: MarkdownProfile, limits: ParseLimits, cancellation: CancellationToken, budget: OperationBudget,
        source: SourceBuffer, dialect: CompiledMarkdownDialect, nativeScannerEnabled: Bool,
        lineScannerAccelerator: ?LineScannerAccelerator) {
        this.profile = profile
        this.limits = limits
        this.cancellation = cancellation
        this.budget = budget
        this.source = source
        this.dialect = dialect
        this.ids = NodeIdAllocator(limits.maximumAstNodes)
        this.nativeScannerEnabled = nativeScannerEnabled
        this.lineScannerAccelerator = lineScannerAccelerator
    }

    func parse(inputDiagnostics: Array<Diagnostic>): ParseResult {
        for (diagnostic in inputDiagnostics) {
            diagnostics.add(diagnostic)
        }
        let lines = splitLines(source)
        references = if (source.text().contains("[")) {
            collectReferences(lines)
        } else {
            []
        }
        for (reference in references) {
            if (reference.isEffective) {
                referenceIndex.add(reference.labelNormalized, reference)
            }
        }
        let blocks = parseBlocks(lines)
        var document = Document(
            ids.next(),
            blocks,
            SourceSpan(0, source.byteLength()),
            profile,
            dialect.fingerprint,
            references: references
        )
        // Parser construction maintains dense NodeIds, category-safe children,
        // and nested spans as local invariants. Rewalking every node here would
        // duplicate the whole parse on the production hot path. Publicly
        // supplied and extension-transformed trees are still validated at their
        // trust boundaries below and by AstInvariantValidator.
        for (index in 0..dialect.documentProcessors.size) {
            let processor = dialect.documentProcessors[index]
            cancellation.throwIfCancelled(phase: "extension_process")
            budget.consumeExtensionCallback()
            budget.consumeTransform()
            try {
                document = processor.process(document, budget, cancellation)
            } catch (error: ExtensionFailureException) {
                throw error
            } catch (error: Exception) {
                let manifest = extensionManifest(processor.extensionId)
                throw ExtensionFailureException(processor.extensionId, manifest.semanticVersion,
                    manifest.implementationVersion, "extension_process", error, ruleId: Some(processor.processorId))
            }
            if (!document.profile.sameIdentity(profile) || document.dialectFingerprint != dialect.fingerprint) {
                throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                    "document processor changed profile or dialect identity", phase: "extension_process")
            }
            AstInvariantValidator().validate(document, limits: limits)
        }
        ParseResult(document, source, diagnostics.toArray())
    }

    private func splitLines(source: SourceBuffer): Array<LineRecord> {
        let value = source.text()
        if (nativeScannerEnabled) {
            if (let Some(accelerator) <- lineScannerAccelerator) {
                if (let Some(bytes) <- source.decodedBytesForNative()) {
                    if (let Some(acceleratedLines) <- splitLinesAccelerated(value, bytes, accelerator)) {
                        return acceleratedLines
                    }
                }
            }
        }
        splitLinesCangjie(value)
    }

    private func splitLinesAccelerated(
        value: String,
        bytes: Array<Byte>,
        accelerator: LineScannerAccelerator
    ): ?Array<LineRecord> {
        if (value.size == 0) {
            scanSteps(0)
            return Some([LineRecord("", 0, 0, 0, hasCoreInlineSpecial: false)])
        }
        // One packed UInt64 per line is bounded, compact, and lets the native
        // pass stop safely when unusually dense input exceeds the estimate.
        let capacity = max(16, bytes.size / 8 + 16)
        let records = match (accelerator.scanLines(bytes, capacity)) {
            case Some(value) => value
            case None => return None
        }
        if (records.size <= 0 || records.size > capacity) {
            throw IllegalStateException("line scanner accelerator returned an invalid record count")
        }
        scanSteps(value.size)
        let lines = ArrayList<LineRecord>()
        var start: Int64 = if (bytes.size >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
            3
        } else {
            0
        }
        for (lineIndex in 0..records.size) {
            let packed = records[lineIndex]
            let endWithNewline = Int64(packed >> 3)
            let newlineWidth = Int64(packed & 0x3u64)
            let end = endWithNewline - newlineWidth
            if (endWithNewline < start || endWithNewline > bytes.size || end < start || newlineWidth > 2 || (lineIndex +
                1 == records.size && (endWithNewline != bytes.size || newlineWidth != 0)) || (lineIndex + 1 < records
                .size && !validAcceleratedNewline(bytes, end, endWithNewline))) {
                throw IllegalStateException("line scanner accelerator returned an invalid packed record")
            }
            if (end - start > limits.maximumLineBytes) {
                throw LimitExceededException("line_bytes", limits.maximumLineBytes, end - start, "input",
                    span: Some(mappedSpan(start, end)))
            }
            lines.add(
                LineRecord(value[start..end], start, end, endWithNewline, hasCoreInlineSpecial: (packed & 0x4u64) != 0u64))
            start = endWithNewline
        }
        Some(lines.toArray())
    }

    private func validAcceleratedNewline(bytes: Array<Byte>, end: Int64, endWithNewline: Int64): Bool {
        let width = endWithNewline - end
        if (width == 1) {
            return bytes[end] == b'\n' || bytes[end] == b'\r'
        }
        width == 2 && bytes[end] == b'\r' && bytes[end + 1] == b'\n'
    }

    private func splitLinesCangjie(value: String): Array<LineRecord> {
        let lines = ArrayList<LineRecord>()
        var start: Int64 = 0
        var index: Int64 = 0
        var pendingScanSteps: Int64 = 0
        var lineHasCoreInlineSpecial = false
        if (value.size >= 3 && value[0] == 0xEF && value[1] == 0xBB && value[2] == 0xBF) {
            start = 3
            index = 3
        }
        while (index < value.size) {
            pendingScanSteps++
            if (pendingScanSteps == 1024) {
                scanSteps(pendingScanSteps)
                pendingScanSteps = 0
            }
            if (coreInlineSpecialByte(value[index])) {
                lineHasCoreInlineSpecial = true
            }
            if (value[index] == 10 || value[index] == 13) {
                let end = index
                if (end - start > limits.maximumLineBytes) {
                    throw LimitExceededException("line_bytes", limits.maximumLineBytes, end - start, "input",
                        span: Some(mappedSpan(start, end)))
                }
                if (value[index] == 13 && index + 1 < value.size && value[index + 1] == 10) {
                    index++
                }
                lines.add(
                    LineRecord(value[start..end], start, end, index + 1, hasCoreInlineSpecial: lineHasCoreInlineSpecial))
                start = index + 1
                lineHasCoreInlineSpecial = false
            }
            index++
        }
        if (pendingScanSteps > 0) {
            scanSteps(pendingScanSteps)
        }
        if (value.size - start > limits.maximumLineBytes) {
            throw LimitExceededException("line_bytes", limits.maximumLineBytes, value.size - start, "input",
                span: Some(mappedSpan(start, value.size)))
        }
        lines.add(LineRecord(value[start..], start, value.size, value.size,
            hasCoreInlineSpecial: lineHasCoreInlineSpecial))
        lines.toArray()
    }

    private func collectReferences(lines: Array<LineRecord>): Array<ReferenceDefinition> {
        let out = ArrayList<ReferenceDefinition>()
        let effectiveLabels = HashSet<String>()
        var index: Int64 = 0
        while (index < lines.size) {
            scanStep()
            if (isQuoteLine(lines[index].text)) {
                let marker = quoteMarker(lines[index].text)
                var contentStart = marker + 1
                if (contentStart < lines[index].text.size && lines[index].text[contentStart] == b' ') {
                    contentStart++
                }
                if (let Some((labelRaw, destinationRaw, titleRaw)) <- referenceParts(lines[index].text[contentStart..])) {
                    let label = labelRaw
                    let normalized = normalizeReferenceLabel(label)
                    out.add(
                        ReferenceDefinition(label, normalized, destinationRaw, decodeLinkValue(destinationRaw), titleRaw,
                            decodeLinkValue(titleRaw),
                            mappedSpan(lines[index].startByte + contentStart, lines[index].endByte),
                            isEffective: effectiveLabels.add(normalized)))
                    referenceLineStarts.add(lines[index].startByte + contentStart)
                    index++
                    continue
                }
            }
            if (index > 0) {
                let previous = lines[index - 1]
                var mayInspectPrevious = !isBlank(previous.text)
                if (mayInspectPrevious) {
                    mayInspectPrevious = !referenceLineStarts.contains(previous.startByte)
                }
                if (mayInspectPrevious) {
                    let leading = leadingSpaces(previous.text)
                    let mayInterruptReference = leading <= 3 && leading < previous.text.size && (previous.text[leading] ==
                        b'#' || previous.text[leading] == b'*' || previous.text[leading] == b'_' ||
                        previous.text[leading] == b'-')
                    var interruptsReference = false
                    if (mayInterruptReference) {
                        interruptsReference = isAtxHeading(previous.text)
                        if (!interruptsReference) {
                            interruptsReference = isThematicBreak(previous.text)
                        }
                    }
                    if (!interruptsReference) {
                        index++
                        continue
                    }
                }
            }
            let referenceIndent = leadingWhitespace(lines[index].text)
            let mayStartReference = referenceIndent <= 3 && referenceIndent < lines[index].text.size &&
                lines[index].text[referenceIndent] == b'['
            if (mayStartReference && let Some((label, destinationRaw, destination, titleRaw, title, next)) <- parseReferenceDefinitionAt(
                lines, index)) {
                if (out.size >= limits.maximumReferences) {
                    throw LimitExceededException("references", limits.maximumReferences, out.size + 1,
                        "reference_collection", span: Some(mappedSpan(lines[index].startByte, lines[next - 1].endByte)))
                }
                let normalized = normalizeReferenceLabel(label)
                let effective = effectiveLabels.add(normalized)
                out.add(
                    ReferenceDefinition(
                        label,
                        normalized,
                        destinationRaw,
                        destination,
                        titleRaw,
                        title,
                        mappedSpan(lines[index].startByte, lines[next - 1].endByte),
                        isEffective: effective
                    )
                )
                for (lineIndex in index..next) {
                    referenceLineStarts.add(lines[lineIndex].startByte)
                }
                index = next
            } else {
                index++
            }
        }
        out.toArray()
    }

    private func parseBlocks(lines: Array<LineRecord>, extensionDepth!: Int64 = 0): Array<MarkdownNode> {
        let frames = ArrayList<BlockParseFrame>()
        frames.add(BlockParseFrame(lines, extensionDepth, suppressedBlockRule))
        var result: Array<MarkdownNode> = []
        while (!frames.isEmpty()) {
            let frame = frames[frames.size - 1]
            suppressedBlockRule = frame.suppressedRule
            if (frame.index >= frame.lines.size) {
                frames.remove(at: frames.size - 1)
                let children = frame.blocks.toArray()
                match (frame.completion) {
                    case BlockFrameCompletionKind.Root => result = children
                    case BlockFrameCompletionKind.Quote =>
                        let state = frame.quoteState.getOrThrow()
                        var nested = children
                        var spanIndex = state.spans.size - 1
                        while (spanIndex >= 0) {
                            nested = [BlockQuote(ids.next(), nested, state.spans[spanIndex])]
                            spanIndex--
                        }
                        frames[frames.size - 1].blocks.add(nested[0])
                    case BlockFrameCompletionKind.ListItemFrame =>
                        let state = frame.list.getOrThrow()
                        let item = state.items[state.itemIndex]
                        state
                            .nodes
                            .add(
                                ListItem(ids.next(), children, item.span, taskState: item.taskState,
                                    markerSpan: item.markerSpan))
                        state.itemIndex++
                        if (state.itemIndex < state.items.size) {
                            let nextItem = state.items[state.itemIndex]
                            frames.add(
                                BlockParseFrame(nextItem.lines, frame.depth, frame.suppressedRule,
                                    completion: BlockFrameCompletionKind.ListItemFrame, list: Some(state)))
                        } else {
                            frames[frames
                                    .size - 1]
                                .blocks
                                .add(
                                    List(ids.next(), if (state.marker.ordered) {
                                        ListKind.Ordered
                                    } else {
                                        ListKind.Bullet
                                    }, state.marker.startNumber, state.marker.delimiter, state.tight,
                                        state.nodes.toArray(), state.span))
                        }
                    case BlockFrameCompletionKind.Extension =>
                        let state = frame.extension.getOrThrow()
                        let payload = emitBlockPayload(state.rule, state.kindId, state.parameters, state.literal,
                            state.span, children, state.values)
                        let origin = NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(state.span),
                            extensionId: Some(state.rule.extensionId))
                        frames[frames
                                .size - 1]
                            .blocks
                            .add(
                                CustomBlock(ids.next(), state.rule.extensionId, manifestVersion(state.rule.extensionId),
                                    state.kindId, payload, children, Some(state.span), origin))
                }
                continue
            }
            scanStep()
            let lines = frame.lines
            let index = frame.index
            let line = lines[index]
            if (isBlank(line.text) || referenceLineStarts.contains(line.startByte)) {
                frame.index++
                continue
            }
            if (dialect.parserOptions.extensionsEnabled && dialect.blockRules.size > 0) {
                if (let Some(scan) <- scanExtensionBlock(lines, index, frame.depth)) {
                    frame.index = scan.nextIndex
                    if (let Some(node) <- scan.node) {
                        frame.blocks.add(node)
                    } else if (let Some(state) <- scan.pending) {
                        frames.add(
                            BlockParseFrame(state.lines, frame.depth + 1, state.suppressedRule,
                                completion: BlockFrameCompletionKind.Extension, extension: Some(state)))
                    }
                    continue
                }
            }
            if (isIndentedCode(line.text)) {
                let (node, next) = parseIndentedCode(lines, index)
                frame.blocks.add(node)
                frame.index = next
                continue
            }
            let leading = leadingSpaces(line.text)
            let first: Byte = if (leading < line.text.size) {
                line.text[leading]
            } else {
                0
            }
            if (first == b'`' || first == b'~') {
                if (isFenceStart(line.text)) {
                    let (node, next) = parseFencedCode(lines, index)
                    frame.blocks.add(node)
                    frame.index = next
                    continue
                }
            }
            if (first == b'#') {
                if (isAtxHeading(line.text)) {
                    frame.blocks.add(parseAtxHeading(line))
                    frame.index++
                    continue
                }
            }
            if (first == b'*' || first == b'_' || first == b'-') {
                if (isThematicBreak(line.text)) {
                    frame
                        .blocks
                        .add(ThematicBreak(ids.next(), firstNonSpace(line.text), mappedSpan(line.startByte, line.endByte)))
                    frame.index++
                    continue
                }
            }
            if (first == b'>') {
                if (isQuoteLine(line.text)) {
                    let state = scanQuote(lines, index, frame.depth)
                    frame.index = state.nextIndex
                    frames.add(
                        BlockParseFrame(state.lines, frame.depth + 1, frame.suppressedRule,
                            completion: BlockFrameCompletionKind.Quote, quoteState: Some(state)))
                    continue
                }
            }
            let mayStartList = first == b'*' || first == b'-' || first == b'+' || (first >= b'0' && first <= b'9')
            if (mayStartList) {
                if (isListLine(line.text)) {
                    let state = scanList(lines, index, frame.depth)
                    frame.index = state.nextIndex
                    let item = state.items[0]
                    frames.add(
                        BlockParseFrame(item.lines, frame.depth + 1, frame.suppressedRule,
                            completion: BlockFrameCompletionKind.ListItemFrame, list: Some(state)))
                    continue
                }
            }
            if (isGfmProfile() && isTableStart(lines, index)) {
                let (node, next) = parseTable(lines, index)
                frame.blocks.add(node)
                frame.index = next
                continue
            }
            if (first == b'<') {
                if (isHtmlBlock(line.text)) {
                    let (node, next) = parseHtmlBlock(lines, index)
                    frame.blocks.add(node)
                    frame.index = next
                    continue
                }
            }
            let setextMarker = findSetextMarker(lines, index)
            if (setextMarker > index) {
                let markerStart = leadingWhitespace(lines[setextMarker].text)
                let level: Int64 = if (lines[setextMarker].text[markerStart] == b'=') {
                    1
                } else {
                    2
                }
                let children = parseInlineLineRange(lines, index, setextMarker)
                frame
                    .blocks
                    .add(Heading(ids.next(), level, children, mappedSpan(line.startByte, lines[setextMarker].endByte)))
                frame.index = setextMarker + 1
                continue
            }
            let (node, next) = parseParagraph(lines, index)
            frame.blocks.add(node)
            frame.index = next
        }
        suppressedBlockRule = ""
        result
    }

    private func parseAtxHeading(line: LineRecord): Heading {
        let leading = leadingSpaces(line.text)
        var level: Int64 = 0
        while (leading + level < line.text.size && level < 6 && line.text[leading + level] == b'#') {
            level++
        }
        var contentStart = leading + level
        while (contentStart < line.text.size && (line.text[contentStart] == b' ' || line.text[contentStart] == b'\t')) {
            contentStart++
        }
        let content = stripClosingAtx(line.text[contentStart..])
        Heading(ids.next(), level, parseInline(content, line.startByte + contentStart, 0),
            mappedSpan(line.startByte, line.endByte))
    }

    private func parseParagraph(lines: Array<LineRecord>, start: Int64): (Paragraph, Int64) {
        let children = ArrayList<MarkdownNode>()
        var index = start
        var last = lines[start]
        while (index < lines.size) {
            let line = lines[index]
            let contentStart = leadingWhitespace(line.text)
            var content = line.text[contentStart..]
            var breakKind: Int64 = 0
            let nextIndex = index + 1
            var hasContinuation = nextIndex < lines.size
            if (hasContinuation) {
                hasContinuation = !isBlank(lines[nextIndex].text)
            }
            if (hasContinuation) {
                hasContinuation = !isAnyBlockStart(lines, nextIndex)
            }
            if (hasContinuation && content.endsWith("\\")) {
                content = content[..content.size - 1]
                breakKind = 1
            } else if (hasContinuation && endsWithTwoSpaces(content)) {
                content = stripTrailingSpaces(content)
                breakKind = 2
            } else {
                content = stripTrailingSpaces(content)
            }
            for (child in parseInline(content, line.startByte + contentStart, 0, knownPlain: !line.hasCoreInlineSpecial)) {
                children.add(child)
            }
            last = line
            index = nextIndex
            if (hasContinuation) {
                let breakSpan = mappedSpan(line.startByte + contentStart + content.size, lines[nextIndex].startByte)
                if (breakKind == 1) {
                    children.add(HardBreak(ids.next(), HardBreakKind.Backslash, breakSpan))
                } else if (breakKind == 2) {
                    children.add(HardBreak(ids.next(), HardBreakKind.Spaces, breakSpan))
                } else {
                    children.add(SoftBreak(ids.next(), breakSpan))
                }
            } else {
                break
            }
        }
        if (index - start > 1) {
            let firstText = lines[start].text
            let sourceText = source.text()
            let paragraphStart = lines[start].startByte
            let paragraphEnd = last.endByte
            let needsCombinedInline = containsByteInRange(sourceText, b'`', paragraphStart, paragraphEnd) ||
                firstText.contains("*") || firstText.contains("_") || (firstText.contains("[") && containsByteInRange(
                sourceText, b')', paragraphStart, paragraphEnd)) || (firstText.contains("<") && containsByteInRange(
                sourceText, b'>', paragraphStart, paragraphEnd))
            if (needsCombinedInline) {
                let rawParagraph = sourceText[paragraphStart..paragraphEnd]
                children.clear()
                for (child in parseInline(rawParagraph, lines[start].startByte, 0)) {
                    children.add(child)
                }
            }
        }
        (Paragraph(ids.next(), children.toArray(), mappedSpan(lines[start].startByte, last.endByte)), index)
    }

    private func parseFencedCode(lines: Array<LineRecord>, start: Int64): (CodeBlock, Int64) {
        let opener = lines[start]
        let leading = leadingSpaces(opener.text)
        let marker = opener.text[leading]
        var fenceLength: Int64 = 0
        while (leading + fenceLength < opener.text.size && opener.text[leading + fenceLength] == marker) {
            fenceLength++
        }
        let infoStart = skipAsciiSpace(opener.text, leading + fenceLength)
        let infoRaw = opener.text[infoStart..]
        let language = decodeLinkValue(firstWord(infoRaw))
        var index = start + 1
        var closingSpan: ?SourceSpan = None
        var endByte = opener.endByte
        var contentStart: Int64 = -1
        var contentEnd: Int64 = -1
        var contentStop = start + 1
        var literalCanUseSourceSlice = leading == 0
        while (index < lines.size) {
            scanStep()
            if (isFenceClose(lines[index].text, marker, fenceLength)) {
                closingSpan = Some(mappedSpan(lines[index].startByte, lines[index].endByte))
                endByte = lines[index].endByte
                index++
                break
            }
            if (contentStart < 0) {
                contentStart = lines[index].startByte
            }
            if (lines[index].endWithNewline > lines[index].endByte) {
                if (source.text()[lines[index].endByte] != 10) {
                    literalCanUseSourceSlice = false
                }
            }
            endByte = lines[index].endByte
            contentEnd = lines[index].endWithNewline
            contentStop = index + 1
            index++
        }
        let literalStorage = if (contentStart >= 0 && literalCanUseSourceSlice) {
            ensureLiteralBytes(contentEnd - contentStart, "block_parse")
            LiteralStorage.Slice(source.sourceSlice(mappedSpan(contentStart, contentEnd)))
        } else {
            let literal = BoundedLiteralBuilder(limits.maximumLiteralBytes, budget, cancellation, "block_parse")
            for (lineIndex in start + 1..contentStop) {
                literal.append(stripUpToSpaces(lines[lineIndex].text, leading))
                if (lines[lineIndex].endWithNewline > lines[lineIndex].endByte) {
                    literal.appendByte(b'\n')
                }
            }
            LiteralStorage.Copy(literal.finish())
        }
        (CodeBlock(
                ids.next(),
                CodeBlockKind.Fenced,
                literalStorage,
                mappedSpan(opener.startByte, endByte),
                Some(marker),
                fenceLength,
                Some(mappedSpan(opener.startByte + leading, opener.startByte + leading + fenceLength)),
                closingSpan,
                infoRaw,
                language,
                ""
            ), index)
    }

    private func parseIndentedCode(lines: Array<LineRecord>, start: Int64): (CodeBlock, Int64) {
        let parts = ArrayList<String>()
        var index = start
        var last = lines[start]
        while (index < lines.size && (isIndentedCode(lines[index].text) || isBlank(lines[index].text))) {
            if (isIndentedCode(lines[index].text)) {
                parts.add(stripIndentColumns(lines[index].text, 4)[0])
            } else {
                parts.add("")
            }
            last = lines[index]
            index++
        }
        while (!parts.isEmpty() && parts[0].isEmpty()) {
            parts.remove(at: 0)
        }
        while (!parts.isEmpty() && parts[parts.size - 1].isEmpty()) {
            parts.remove(at: parts.size - 1)
        }
        let literal = joinStrings(parts.toArray(), "\n")
        ensureLiteralBytes(literal.size, "block_parse")
        (CodeBlock(ids.next(), CodeBlockKind.Indented, literal, mappedSpan(lines[start].startByte, last.endByte)), index)
    }

    private func scanQuote(lines: Array<LineRecord>, start: Int64, depth: Int64): PendingQuoteState {
        if (depth >= limits.maximumNestingDepth) {
            throw LimitExceededException("nesting_depth", limits.maximumNestingDepth, depth + 1, "block_parse",
                span: Some(mappedSpan(lines[start].startByte, lines[start].endByte)))
        }
        if (let Some(batched) <- scanSimpleNestedQuotes(lines, start, depth)) {
            return batched
        }
        let innerLines = ArrayList<LineRecord>()
        var index = start
        var last = lines[start]
        var canLazyContinue = false
        while (index < lines.size) {
            let line = lines[index]
            if (isQuoteLine(line.text)) {
                let marker = quoteMarker(line.text)
                var contentStart = marker + 1
                while (contentStart < line.text.size && (line.text[contentStart] == b' ' || line.text[contentStart] ==
                        b'\t')) {
                    contentStart++
                }
                let residualIndent = max(0,
                    visualColumnAt(line.text, contentStart) - (visualColumnAt(line.text, marker) + 2))
                let normalizedContent = repeatSpaces(residualIndent) + line.text[contentStart..]
                innerLines.add(
                    LineRecord(normalizedContent, line.startByte + max(0, contentStart - residualIndent), line.endByte,
                        line.endWithNewline, hasCoreInlineSpecial: line.hasCoreInlineSpecial))
                let content = normalizedContent
                canLazyContinue = !isBlank(content) && !isFenceStart(content) && !isIndentedCode(content) &&
                    !isHtmlBlock(content) && !isAtxHeading(content) && !isThematicBreak(content)
                last = line
                index++
                continue
            }
            let lazyBlank = isBlank(line.text)
            let lazyFence = isFenceStart(line.text)
            let lazyList = isListLine(line.text)
            let lazyHeading = isAtxHeading(line.text)
            let lazyBreak = isThematicBreak(line.text)
            if (canLazyContinue && !lazyBlank && !lazyFence && !lazyList && !lazyHeading && !lazyBreak) {
                innerLines.add(
                    LineRecord(line.text, line.startByte, line.endByte, line.endWithNewline, allowSetext: false,
                        hasCoreInlineSpecial: line.hasCoreInlineSpecial))
                last = line
                index++
                continue
            }
            break
        }
        PendingQuoteState(innerLines.toArray(), [mappedSpan(lines[start].startByte, last.endByte)], index)
    }

    private func scanSimpleNestedQuotes(
        lines: Array<LineRecord>,
        start: Int64,
        depth: Int64
    ): ?PendingQuoteState {
        var index = start
        var minimumDepth = Int64.Max
        while (index < lines.size && isQuoteLine(lines[index].text)) {
            let lineDepth = simpleQuotePrefixDepth(lines[index].text)
            if (lineDepth < 2) {
                return None
            }
            minimumDepth = min(minimumDepth, lineDepth)
            index++
        }
        if (index < lines.size && !isBlank(lines[index].text)) {
            return None
        }
        if (depth + minimumDepth > limits.maximumNestingDepth) {
            throw LimitExceededException("nesting_depth", limits.maximumNestingDepth, depth + minimumDepth,
                "block_parse", span: Some(mappedSpan(lines[start].startByte, lines[start].endByte)))
        }
        let innerLines = ArrayList<LineRecord>()
        for (lineIndex in start..index) {
            let line = lines[lineIndex]
            let contentStart = simpleQuoteContentStart(line.text, minimumDepth)
            innerLines.add(
                LineRecord(line.text[contentStart..], line.startByte + contentStart, line.endByte, line.endWithNewline,
                    hasCoreInlineSpecial: line.hasCoreInlineSpecial))
        }
        let spans = ArrayList<SourceSpan>()
        for (level in 0..minimumDepth) {
            let spanStart = simpleQuoteContentStart(lines[start].text, level)
            spans.add(mappedSpan(lines[start].startByte + spanStart, lines[index - 1].endByte))
        }
        Some(PendingQuoteState(innerLines.toArray(), spans.toArray(), index))
    }

    private func scanList(lines: Array<LineRecord>, start: Int64, depth: Int64): PendingListState {
        if (depth >= limits.maximumNestingDepth) {
            throw LimitExceededException("nesting_depth", limits.maximumNestingDepth, depth + 1, "block_parse",
                span: Some(mappedSpan(lines[start].startByte, lines[start].endByte)))
        }
        let items = ArrayList<PendingListItemState>()
        let firstMarker = detailedListMarker(lines[start].text).getOrThrow()
        var index = start
        var last = lines[start]
        var tight = true
        while (index < lines.size) {
            let markerOption = detailedListMarker(lines[index].text)
            if (markerOption.isNone()) {
                break
            }
            let marker = markerOption.getOrThrow()
            if (!sameListFamily(firstMarker, marker) || isThematicBreak(lines[index].text)) {
                break
            }
            let itemStart = index
            let firstLine = lines[index]
            last = firstLine
            var contentStart = marker.contentStart
            var state = TaskState.NotTask
            var taskSpan: ?SourceSpan = None
            if (isGfmProfile() && contentStart + 3 <= firstLine.text.size && firstLine.text[contentStart] == b'[' &&
                firstLine.text[contentStart + 2] == b']') {
                let flag = firstLine.text[contentStart + 1]
                if (flag == b' ' || flag == b'x' || flag == b'X') {
                    state = if (flag == b' ') {
                        TaskState.Unchecked
                    } else {
                        TaskState.Checked
                    }
                    taskSpan = Some(mappedSpan(firstLine.startByte + contentStart, firstLine.startByte + contentStart + 3))
                    contentStart = skipAsciiSpace(firstLine.text, contentStart + 3)
                }
            }
            let innerLines = ArrayList<LineRecord>()
            let firstContent = repeatSpaces(marker.syntheticIndent) + firstLine.text[contentStart..]
            innerLines.add(
                LineRecord(firstContent, firstLine.startByte + max(0, contentStart - marker.syntheticIndent),
                    firstLine.endByte, firstLine.endWithNewline, hasCoreInlineSpecial: firstLine.hasCoreInlineSpecial))
            index++
            var itemHadBlank = false
            while (index < lines.size) {
                let nextMarker = detailedListMarker(lines[index].text)
                if (let Some(nextInfo) <- nextMarker) {
                    if (nextInfo.indent == firstMarker.indent) {
                        break
                    }
                }
                let line = lines[index]
                if (isBlank(line.text)) {
                    var lookahead = index + 1
                    while (lookahead < lines.size && isBlank(lines[lookahead].text)) {
                        lookahead++
                    }
                    if (lookahead >= lines.size) {
                        break
                    }
                    let followingMarker = detailedListMarker(lines[lookahead].text)
                    let followingIndent = leadingIndentColumns(lines[lookahead].text)
                    let continuesItem = followingIndent >= marker.contentIndent
                    let continuesList = match (followingMarker) {
                        case Some(info) => info.indent <= 3 && sameListFamily(firstMarker, info)
                        case None => false
                    }
                    if (continuesList) {
                        itemHadBlank = true
                        last = line
                        index = lookahead
                        break
                    }
                    if (innerLines.size == 1 && isBlank(innerLines[0].text)) {
                        break
                    }
                    if (!continuesItem && !continuesList) {
                        break
                    }
                    innerLines.add(LineRecord("", line.endByte, line.endByte, line.endWithNewline))
                    if ((followingIndent <= marker.contentIndent || (followingMarker.isNone() &&
                        !hasNestedListMarker(innerLines))) && !hasOpenFence(innerLines)) {
                        itemHadBlank = true
                    }
                    last = line
                    index++
                    continue
                }
                let indentation = leadingIndentColumns(line.text)
                if (indentation >= marker.contentIndent) {
                    let stripped = stripIndentColumns(line.text, marker.contentIndent)
                    let normalizedStart = line.startByte + max(0, stripped[1] - stripped[2])
                    if (referenceLineStarts.contains(line.startByte)) {
                        referenceLineStarts.add(normalizedStart)
                    }
                    innerLines.add(
                        LineRecord(stripped[0], normalizedStart, line.endByte, line.endWithNewline,
                            hasCoreInlineSpecial: line.hasCoreInlineSpecial))
                    last = line
                    index++
                    continue
                }
                if (!isAnyBlockStart(lines, index) && !innerLines.isEmpty()) {
                    innerLines.add(line)
                    last = line
                    index++
                    continue
                }
                break
            }
            while (!innerLines.isEmpty() && isBlank(innerLines[innerLines.size - 1].text)) {
                innerLines.remove(at: innerLines.size - 1)
            }
            if (itemHadBlank) {
                tight = false
            }
            let itemEnd = if (index > itemStart + 1) {
                last.endByte
            } else {
                firstLine.endByte
            }
            items.add(PendingListItemState(innerLines.toArray(), mappedSpan(firstLine.startByte, itemEnd), state,
                taskSpan))
        }
        PendingListState(firstMarker, tight, items.toArray(), mappedSpan(lines[start].startByte, last.endByte), index)
    }

    private func parseHtmlBlock(lines: Array<LineRecord>, start: Int64): (HtmlBlock, Int64) {
        let literal = BoundedLiteralBuilder(limits.maximumLiteralBytes, budget, cancellation, "block_parse")
        let blockType = htmlBlockType(lines[start].text)
        var index = start
        var last = lines[start]
        while (index < lines.size) {
            if (index > start && (blockType == 6 || blockType == 7) && isBlank(lines[index].text)) {
                break
            }
            if (index > start) {
                literal.appendByte(b'\n')
            }
            literal.append(lines[index].text)
            last = lines[index]
            if (htmlBlockEnds(blockType, lines[index].text)) {
                index++;
                break
            }
            index++
        }
        let span = mappedSpan(lines[start].startByte, last.endByte)
        (HtmlBlock(ids.next(), storageForLiteral(literal.finish(), span), blockType, span), index)
    }

    private func parseTable(lines: Array<LineRecord>, start: Int64): (Table, Int64) {
        let alignments = tableAlignments(lines[start + 1].text)
        if (alignments.size > limits.maximumTableColumns) {
            throw LimitExceededException("table_columns", limits.maximumTableColumns, alignments.size, "block_parse",
                span: Some(mappedSpan(lines[start + 1].startByte, lines[start + 1].endByte)))
        }
        let rows = ArrayList<MarkdownNode>()
        rows.add(tableRow(lines[start], true, alignments))
        var index = start + 2
        var last = lines[start + 1]
        while (index < lines.size) {
            if (isBlank(lines[index].text)) {
                break
            }
            if (isAnyBlockStart(lines, index)) {
                break
            }
            rows.add(tableRow(lines[index], false, alignments))
            last = lines[index]
            index++
        }
        (Table(ids.next(), alignments, rows.toArray(), mappedSpan(lines[start].startByte, last.endByte)), index)
    }

    private func tableRow(line: LineRecord, header: Bool, alignments: Array<TableAlignment>): TableRow {
        let parts = splitTable(line.text)
        let cells = ArrayList<MarkdownNode>()
        for (index in 0..alignments.size) {
            let value = if (index < parts.size) {
                unescapeTablePipes(parts[index])
            } else {
                ""
            }
            cells.add(
                TableCell(ids.next(), alignments[index], parseInline(value, line.startByte, 1),
                    mappedSpan(line.startByte, line.endByte)))
        }
        TableRow(ids.next(), header, cells.toArray(), mappedSpan(line.startByte, line.endByte))
    }

    private func parseInline(text: String, baseOffset: Int64, depth: Int64, knownPlain!: Bool = false): Array<MarkdownNode> {
        if (depth > limits.maximumNestingDepth) {
            throw LimitExceededException("nesting_depth", limits.maximumNestingDepth, depth, "inline_parse",
                span: Some(mappedSpan(baseOffset, baseOffset + text.size)))
        }
        if (text.isEmpty()) {
            return []
        }
        let hasExtensionDispatch = dialect.parserOptions.extensionsEnabled && (dialect.inlineRules.size > 0 ||
            dialect.parserSpis.size > 0)
        let hasGfmAutolinkCandidate = isGfmProfile() && mayContainExtendedAutolink(text)
        if (knownPlain && !hasExtensionDispatch && !hasGfmAutolinkCandidate) {
            // splitLines already classified this line while finding its end.
            // Keep the accounting side effects of the old plain-text scan but
            // avoid walking the same bytes a second time.
            scanSteps(text.size)
            return [parsedText(text, text, baseOffset, baseOffset + text.size)]
        }
        if (!hasExtensionDispatch) {
            var plain = true
            var plainIndex: Int64 = 0
            while (plainIndex < text.size) {
                let byte = text[plainIndex]
                if (byte == 10 || byte == 13 || coreInlineSpecialByte(byte) || hasGfmAutolinkCandidate) {
                    plain = false
                    break
                }
                plainIndex++
            }
            if (plain) {
                scanSteps(text.size)
                return [parsedText(text, text, baseOffset, baseOffset + text.size)]
            }
        }
        // Avoid rescanning the remaining line for every unmatched link opener. A
        // closing bracket inside a code span may make this conservative (we may
        // still try a parse), but it can never suppress a valid link parse.
        let lastClosingBracket = lastUnescapedClosingBracket(text)
        let pieces = ArrayList<InlinePiece>()
        var plainStart: Int64 = 0
        var index: Int64 = 0
        var delimiterBytes: ?Array<Byte> = None
        var hasDelimiterPieces = false
        while (index < text.size) {
            if (!hasExtensionDispatch && text[index] < 0x80 && text[index] != 10 && text[index] != 13 &&
                !coreInlineSpecialByte(text[index])) {
                let runStart = index
                while (index < text.size && text[index] < 0x80 && text[index] != 10 && text[index] != 13 &&
                        !coreInlineSpecialByte(text[index])) {
                    index++
                }
                scanSteps(index - runStart)
                continue
            }
            scanStep()
            if (text[index] == b'*' || text[index] == b'_') {
                hasDelimiterPieces = true
                let bytes = match (delimiterBytes) {
                    case Some(value) => value
                    case None =>
                        let value = text.toArray()
                        delimiterBytes = Some(value)
                        value
                }
                flushPieceText(pieces, text, plainStart, index, baseOffset)
                let run = delimiterRunLength(text, index, text[index])
                pieces.add(
                    InlinePiece(baseOffset + index, run, text[index], delimiterCanOpenBytes(bytes, index, run,
                        text[index]), delimiterCanCloseBytes(bytes, index, run, text[index])))
                index += run
                plainStart = index
                continue
            }
            if (text[index] == 10 || text[index] == 13) {
                var contentEnd = index
                var hardKind: Int64 = 0
                if (contentEnd > plainStart && text[contentEnd - 1] == b'\\' && !isEscaped(text, contentEnd - 1)) {
                    contentEnd--
                    hardKind = 1
                } else {
                    var spaces: Int64 = 0
                    while (contentEnd > plainStart && text[contentEnd - 1] == b' ') {
                        contentEnd--;
                        spaces++
                    }
                    if (spaces >= 2) {
                        hardKind = 2
                    }
                }
                flushPieceText(pieces, text, plainStart, contentEnd, baseOffset)
                var next = index + 1
                if (text[index] == 13 && next < text.size && text[next] == 10) {
                    next++
                }
                let span = mappedSpan(baseOffset + contentEnd, baseOffset + next)
                let breakNode: MarkdownNode = if (hardKind == 1) {
                    HardBreak(ids.next(), HardBreakKind.Backslash, span)
                } else if (hardKind == 2) {
                    HardBreak(ids.next(), HardBreakKind.Spaces, span)
                } else {
                    SoftBreak(ids.next(), span)
                }
                pieces.add(InlinePiece(baseOffset + contentEnd, 0, 0, false, false, nodes: [breakNode]))
                index = next
                plainStart = index
                continue
            }
            let cannotCloseBracket = (text[index] == b'[' || (text[index] == b'!' && index + 1 < text.size &&
                text[index + 1] == b'[')) && lastClosingBracket <= index
            let special: ?(MarkdownNode, Int64) = if (!cannotCloseBracket && (hasExtensionDispatch ||
                coreInlineSpecialByte(text[index]))) {
                inlineSpecial(text, index, baseOffset, depth)
            } else {
                None
            }
            if (let Some((node, next)) <- special) {
                flushPieceText(pieces, text, plainStart, index, baseOffset)
                pieces.add(InlinePiece(baseOffset + index, 0, 0, false, false, nodes: [node]))
                index = next
                plainStart = index
            } else {
                index = nextRuneOffset(text, index)
            }
        }
        flushPieceText(pieces, text, plainStart, text.size, baseOffset)
        let resolved = coalesceTextNodes(if (hasDelimiterPieces) {
            resolveDelimiterPieces(pieces)
        } else {
            materializeUndelimitedPieces(pieces)
        })
        if (hasGfmAutolinkCandidate) {
            expandGfmAutolinks(resolved)
        } else {
            resolved
        }
    }

    private func inlineSpecial(text: String, start: Int64, baseOffset: Int64, depth: Int64): ?(MarkdownNode, Int64) {
        if (dialect.parserOptions.extensionsEnabled && (dialect.parserSpis.size > 0 || dialect.inlineRules.size > 0)) {
            for (spiIndex in 0..dialect.parserSpis.size) {
                let spi = dialect.parserSpis[spiIndex]
                cancellation.throwIfCancelled(phase: "extension_parse")
                budget.consumeExtensionCallback()
                let context = InlineParserSpiContext(text, start, spi.maximumLookahead, baseOffset, source, ids, budget,
                    cancellation)
                try {
                    match (spi.tryParse(context)) {
                        case InlineParserSpiResult.NoMatch => ()
                        case InlineParserSpiResult.Matched(node, nextOffset) =>
                            if (nextOffset <= start || nextOffset > text.size || nextOffset - start > spi
                                .maximumLookahead) {
                                throw IllegalStateException("parser SPI returned an invalid or unbounded next offset")
                            }
                            if (node.extensionId != spi.extensionId || node.localKindId != spi.ruleId) {
                                throw IllegalStateException("parser SPI returned a node with mismatched identity")
                            }
                            if (let Some(span) <- node.span) {
                                let allowed = context.sourceSpan(start, nextOffset)
                                if (!allowed.containsSpan(span)) {
                                    throw IllegalStateException("parser SPI node span is outside consumed input")
                                }
                            } else {
                                throw IllegalStateException("parser SPI parsed node must have a SourceSpan")
                            }
                            cancellation.throwIfCancelled(phase: "extension_parse")
                            return Some((node, nextOffset))
                    }
                } catch (error: ExtensionFailureException) {
                    throw error
                } catch (error: Exception) {
                    let manifest = extensionManifest(spi.extensionId)
                    throw ExtensionFailureException(spi.extensionId, manifest.semanticVersion,
                        manifest.implementationVersion, "extension_parse", error, ruleId: Some(spi.ruleId),
                        span: Some(context.sourceSpan(start, if (start + spi.maximumLookahead < text.size) {
                            start + spi.maximumLookahead
                        } else {
                            text.size
                        })))
                }
            }
            for (ruleIndex in 0..dialect.inlineRules.size) {
                let rule = dialect.inlineRules[ruleIndex]
                let identity = "${rule.extensionId}/${rule.ruleId}"
                if (identity == suppressedInlineRule || !startsAt(text, rule.opener, start)) {
                    continue
                }
                if (!customInlineOpenerAllowed(text, start, rule)) {
                    continue
                }
                if (let InlineSyntaxKind.SingleToken <- rule.syntaxKind) {
                    let next = start + rule.opener.size
                    if (!customInlineCloserAllowed(text, start, next, rule)) {
                        continue
                    }
                    budget.consumeExtensionCallback()
                    budget.consumeScan(steps: syntaxRuleCost(rule.resourceCost, rule.opener.size))
                    let span = mappedSpan(baseOffset + start, baseOffset + next)
                    let children: Array<MarkdownNode> = []
                    let payload = emitInlinePayload(rule, rule.opener, span, children)
                    let origin = NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(span),
                        extensionId: Some(rule.extensionId))
                    return Some(
                        (CustomInline(ids.next(), rule.extensionId, manifestVersion(rule.extensionId), rule.ruleId,
                                payload, children, Some(span), origin), next))
                }
                let bodyStart = start + rule.opener.size
                let end = findCustomInlineCloser(text, start, bodyStart, rule)
                if (end < 0 || end - start > rule.maximumLookahead) {
                    if (dialect.parserOptions.emitUnclosedExtensionDiagnostics) {
                        diagnostics.add(
                            Diagnostic("MD3002_UNCLOSED_EXTENSION", DiagnosticSeverity.Warning,
                                "unclosed inline extension rule ${rule.ruleId}",
                                mappedSpan(baseOffset + start,
                                    min(baseOffset + text.size, baseOffset + start + rule.maximumLookahead)),
                                extensionId: Some(rule.extensionId), ruleId: Some(rule.ruleId)))
                    }
                    return None
                }
                budget.consumeExtensionCallback()
                budget.consumeScan(steps: syntaxRuleCost(rule.resourceCost, end + rule.closer.size - start))
                let body = text[bodyStart..end]
                let children: Array<MarkdownNode>
                if (rule.parseChildren) {
                    if (rule.allowNesting) {
                        children = parseInline(body, baseOffset + bodyStart, depth + 1)
                    } else {
                        let previous = suppressedInlineRule
                        suppressedInlineRule = identity
                        children = parseInline(body, baseOffset + bodyStart, depth + 1)
                        suppressedInlineRule = previous
                    }
                } else if (!rule.emitContent || body.isEmpty()) {
                    children = []
                } else {
                    children = [parsedText(body, body, baseOffset + bodyStart, baseOffset + end)]
                }
                let span = mappedSpan(baseOffset + start, baseOffset + end + rule.closer.size)
                let payload = emitInlinePayload(rule, body, span, children)
                let origin = NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(span),
                    extensionId: Some(rule.extensionId))
                return Some(
                    (CustomInline(ids.next(), rule.extensionId, manifestVersion(rule.extensionId), rule.ruleId, payload,
                            children, Some(span), origin), end + rule.closer.size))
            }
        }
        if (text[start] == b'\\' && start + 1 < text.size && isAsciiPunctuation(text[start + 1])) {
            if (dialect.parserOptions.extensionsEnabled && dialect.inlineRules.size > 0) {
                if (hasLiteralBackslashRuleAt(text, start + 1)) {
                    return None
                }
            }
            return Some(
                (parsedText(text[start..start + 2], text[start + 1..start + 2], baseOffset + start, baseOffset + start +
                        2), start + 2))
        }
        if (text[start] == b'&') {
            let semicolon = findByte(text, b';', start + 1)
            if (semicolon > start) {
                let raw = text[start..semicolon + 1]
                let decoded = decodeEntity(raw)
                if (decoded != raw) {
                    return Some((parsedText(raw, decoded, baseOffset + start, baseOffset + semicolon + 1), semicolon + 1))
                }
            }
        }
        if (text[start] == b'`') {
            let marker = codeMarker(text, start)
            let end = findExactCodeCloser(text, start, marker.size)
            if (end >= 0) {
                let literal = normalizeCodeLiteral(text[start + marker.size..end])
                ensureLiteralBytes(literal.size, "inline_parse", consumeBudget: false)
                return Some(
                    (CodeSpan(ids.next(), literal, marker, mappedSpan(baseOffset + start, baseOffset + end + marker.size)),
                        end + marker.size))
            }
            return Some((parsedText(marker, marker, baseOffset + start, baseOffset + start + marker.size), start + marker
                    .size))
        }
        if (isGfmProfile() && startsAt(text, "~~", start)) {
            let end = findString(text, "~~", start + 2)
            if (end > start + 2) {
                return Some(
                    (Strikethrough(ids.next(), parseInline(text[start + 2..end], baseOffset + start + 2, depth + 1),
                            mappedSpan(baseOffset + start, baseOffset + end + 2)), end + 2))
            }
        }
        if ((startsAt(text, "***", start) || startsAt(text, "___", start)) && (start + 3 == text.size ||
            text[start + 3] != text[start])) {
            if (!delimiterCanOpen(text, start, 1, text[start])) {
                return None
            }
            let end = findMatchingDelimiter(text, start, 1, text[start], referenceIndex)
            if (end > start + 1) {
                return Some(
                    (Emphasis(ids.next(), parseInline(text[start + 1..end], baseOffset + start + 1, depth + 1),
                            mappedSpan(baseOffset + start, baseOffset + end + 1)), end + 1))
            }
        }
        if (startsAt(text, "**", start) || startsAt(text, "__", start)) {
            let run = delimiterRunLength(text, start, text[start])
            if (!delimiterCanOpen(text, start, 2, text[start])) {
                let raw = text[start..start + run]
                return Some((parsedText(raw, raw, baseOffset + start, baseOffset + start + run), start + run))
            }
            let end = findMatchingDelimiter(text, start, 2, text[start], referenceIndex)
            if (end > start + 2) {
                return Some(
                    (Strong(ids.next(), parseInline(text[start + 2..end], baseOffset + start + 2, depth + 1),
                            mappedSpan(baseOffset + start, baseOffset + end + 2)), end + 2))
            }
            if (run == 2) {
                let raw = text[start..start + run]
                return Some((parsedText(raw, raw, baseOffset + start, baseOffset + start + run), start + run))
            }
        }
        if (text[start] == b'*' || text[start] == b'_') {
            let run = delimiterRunLength(text, start, text[start])
            if (run != 1) {
                let raw = text[start..start + run]
                return Some((parsedText(raw, raw, baseOffset + start, baseOffset + start + run), start + run))
            }
            if (!delimiterCanOpen(text, start, 1, text[start])) {
                return None
            }
            let end = findMatchingDelimiter(text, start, 1, text[start], referenceIndex)
            if (end > start + 1) {
                return Some(
                    (Emphasis(ids.next(), parseInline(text[start + 1..end], baseOffset + start + 1, depth + 1),
                            mappedSpan(baseOffset + start, baseOffset + end + 1)), end + 1))
            }
        }
        if (text[start] == b'!' && start + 1 < text.size && text[start + 1] == b'[') {
            return parseLinkOrImage(text, start, true, baseOffset, depth)
        }
        if (text[start] == b'[') {
            return parseLinkOrImage(text, start, false, baseOffset, depth)
        }
        if (text[start] == b'<') {
            if (isLegacyGfmComment(text, start)) {
                return None
            }
            let end = findInlineHtmlEnd(text, start)
            if (end > start + 1) {
                let body = text[start + 1..end]
                let autolink = autolinkKind(body)
                if (autolink > 0) {
                    let destination = if (autolink == 2) {
                        "mailto:" + body
                    } else {
                        body
                    }
                    return Some(
                        (Link(ids.next(), body, destination, "", "", LinkSyntaxKind.Autolink,
                                [parsedText(body, body, baseOffset + start + 1, baseOffset + end)],
                                mappedSpan(baseOffset + start, baseOffset + end + 1)), end + 1))
                }
                if (isInlineHtml(body)) {
                    ensureLiteralBytes(end + 1 - start, "inline_parse", consumeBudget: false)
                    return Some(
                        (HtmlInline(ids.next(), text[start..end + 1], mappedSpan(baseOffset + start, baseOffset + end + 1)),
                            end + 1))
                }
            }
        }
        None
    }

    private func parseLinkOrImage(text: String, start: Int64, image: Bool, baseOffset: Int64, depth: Int64): ?(MarkdownNode, 
        Int64) {
        let labelStart = if (image) {
            start + 2
        } else {
            start + 1
        }
        let close = findClosingBracket(text, labelStart)
        if (close < 0) {
            return None
        }
        let label = text[labelStart..close]
        if (hasUnclosedCodeDelimiter(label)) {
            return None
        }
        if (close + 1 < text.size && text[close + 1] == b'(') {
            let parsedTarget = parseInlineLinkTarget(text, close + 2)
            if (let Some((end, destinationRaw, destination, titleRaw, title)) <- parsedTarget) {
                if (destination.size > limits.maximumUrlBytes) {
                    throw LimitExceededException("url_bytes", limits.maximumUrlBytes, destination.size, "inline_parse",
                        span: Some(mappedSpan(baseOffset + start, baseOffset + end + 1)))
                }
                let children = parseInline(label, baseOffset + labelStart, depth + 1)
                if (!image && containsLinkNode(children)) {
                    return None
                }
                if (image) {
                    return Some(
                        (Image(ids.next(), destinationRaw, destination, titleRaw, title, LinkSyntaxKind.Inline, children,
                                mappedSpan(baseOffset + start, baseOffset + end + 1)), end + 1))
                }
                return Some(
                    (Link(ids.next(), destinationRaw, destination, titleRaw, title, LinkSyntaxKind.Inline, children,
                            mappedSpan(baseOffset + start, baseOffset + end + 1)), end + 1))
            }
        }
        var refLabel = label
        var syntax = LinkSyntaxKind.ShortcutReference
        var endOffset = close + 1
        if (close + 1 < text.size && text[close + 1] == b'[') {
            let refEnd = findByte(text, b']', close + 2)
            if (refEnd < 0) {
                return None
            }
            refLabel = text[close + 2..refEnd]
            if (refLabel.isEmpty()) {
                refLabel = label
                syntax = LinkSyntaxKind.CollapsedReference
            } else {
                syntax = LinkSyntaxKind.FullReference
            }
            endOffset = refEnd + 1
        }
        if (let Some(reference) <- lookupReference(refLabel)) {
            let children = parseInline(label, baseOffset + labelStart, depth + 1)
            if (!image && containsLinkNode(children)) {
                return None
            }
            if (image) {
                return Some(
                    (Image(ids.next(), reference.destinationRaw, reference.destination, reference.titleRaw,
                            reference.title, syntax, children, mappedSpan(baseOffset + start, baseOffset + endOffset)),
                        endOffset))
            }
            return Some(
                (Link(ids.next(), reference.destinationRaw, reference.destination, reference.titleRaw, reference.title,
                        syntax, children, mappedSpan(baseOffset + start, baseOffset + endOffset)), endOffset))
        }
        None
    }

    private func lookupReference(label: String): ?ReferenceDefinition {
        let normalized = normalizeReferenceLabel(label)
        referenceIndex.get(normalized)
    }

    private func containsLinkNode(nodes: Array<MarkdownNode>): Bool {
        for (node in nodes) {
            for (event in node.walk()) {
                if (let WalkEvent.Enter(_: Link) <- event) {
                    return true
                }
            }
        }
        false
    }

    private func flushPieceText(out: ArrayList<InlinePiece>, text: String, start: Int64, end: Int64, baseOffset: Int64): Unit {
        if (end > start) {
            let raw = text[start..end]
            let node = parsedText(raw, raw, baseOffset + start, baseOffset + end)
            out.add(InlinePiece(baseOffset + start, 0, 0, false, false, nodes: [node]))
        }
    }

    private func resolveDelimiterPieces(input: ArrayList<InlinePiece>): Array<MarkdownNode> {
        if (input.isEmpty()) {
            return []
        }
        let links = ArrayList<InlinePieceLink>()
        var previous: ?InlinePieceLink = None
        for (index in 0..input.size) {
            let link = InlinePieceLink(index + 1, input[index])
            link.previous = previous
            if (let Some(value) <- previous) {
                value.next = Some(link)
            }
            links.add(link)
            previous = Some(link)
        }
        var head: ?InlinePieceLink = Some(links[0])
        let starOpeners = ArrayList<InlinePieceLink>()
        let underscoreOpeners = ArrayList<InlinePieceLink>()
        let starBottoms = Array<Int64>(6, repeat: 0)
        let underscoreBottoms = Array<Int64>(6, repeat: 0)
        var cursor = head
        var nextIdentity = input.size + 1
        while (let Some(closerLink) <- cursor) {
            let originalNext = closerLink.next
            var closer = closerLink.piece
            if (closer.marker != 0 && closer.length > 0 && closer.canClose) {
                let openers = if (closer.marker == b'*') {
                    starOpeners
                } else {
                    underscoreOpeners
                }
                let bottoms = if (closer.marker == b'*') {
                    starBottoms
                } else {
                    underscoreBottoms
                }
                var keepClosing = true
                while (keepClosing && closerLink.active && closer.length > 0) {
                    match (findDelimiterOpener(openers, bottoms, closerLink)) {
                        case Some(openerLink) =>
                            budget.consumeDelimiter()
                            var opener = openerLink.piece
                            let use = if (opener.length >= 2 && closer.length >= 2) {
                                2
                            } else {
                                1
                            }
                            let children = materializePieceLinks(openerLink.next, closerLink.identity)
                            let openerConsumedStart = opener.start + opener.length - use
                            let closerConsumedEnd = closer.start + use
                            let span = mappedSpan(openerConsumedStart, closerConsumedEnd)
                            let wrapped: MarkdownNode = if (use == 2) {
                                Strong(ids.next(), children, span)
                            } else {
                                Emphasis(ids.next(), children, span)
                            }
                            opener.length -= use
                            closer.start += use
                            closer.length -= use
                            openerLink.piece = opener
                            closerLink.piece = closer
                            head = replaceDelimitedRange(head, openerLink, closerLink,
                                InlinePieceLink(nextIdentity,
                                    InlinePiece(openerConsumedStart, 0, 0, false, false, nodes: [wrapped])))
                            nextIdentity++
                        case None => keepClosing = false
                    }
                }
            }
            if (closerLink.active && closer.length > 0 && closer.canOpen) {
                if (closer.marker == b'*') {
                    starOpeners.add(closerLink)
                } else if (closer.marker == b'_') {
                    underscoreOpeners.add(closerLink)
                }
            }
            cursor = originalNext
        }
        materializePieceLinks(head, -1)
    }

    private func materializeUndelimitedPieces(input: ArrayList<InlinePiece>): Array<MarkdownNode> {
        let nodes = ArrayList<MarkdownNode>()
        for (piece in input) {
            for (node in piece.nodes) {
                nodes.add(node)
            }
        }
        nodes.toArray()
    }

    private func findDelimiterOpener(openers: ArrayList<InlinePieceLink>, bottoms: Array<Int64>,
        closerLink: InlinePieceLink): ?InlinePieceLink {
        let closer = closerLink.piece
        let configuration = (if (closer.canOpen) {
            3
        } else {
            0
        }) + closer.length % 3
        var index = openers.size - 1
        while (index >= bottoms[configuration]) {
            let openerLink = openers[index]
            let opener = openerLink.piece
            if (!openerLink.active || opener.length == 0) {
                index--
                continue
            }
            let adjacent = match (openerLink.next) {
                case Some(value) => value.identity == closerLink.identity
                case None => false
            }
            if (!adjacent) {
                let ruleOfThreeBlocks = (opener.canClose || closer.canOpen) && (opener.length + closer.length) % 3 == 0 &&
                    (opener.length % 3 != 0 || closer.length % 3 != 0)
                if (!ruleOfThreeBlocks) {
                    return Some(openerLink)
                }
            }
            index--
        }
        bottoms[configuration] = openers.size
        None
    }

    private func replaceDelimitedRange(
        head: ?InlinePieceLink,
        opener: InlinePieceLink,
        closer: InlinePieceLink,
        wrapped: InlinePieceLink
    ): ?InlinePieceLink {
        var cursor = opener.next
        while (let Some(value) <- cursor) {
            if (value.identity == closer.identity) {
                break
            }
            value.active = false
            cursor = value.next
        }
        let left = if (opener.piece.length > 0) {
            Some(opener)
        } else {
            opener.active = false
            opener.previous
        }
        let right = if (closer.piece.length > 0) {
            Some(closer)
        } else {
            closer.active = false
            closer.next
        }
        wrapped.previous = left
        wrapped.next = right
        match (left) {
            case Some(value) => value.next = Some(wrapped)
            case None => ()
        }
        if (let Some(value) <- right) {
            value.previous = Some(wrapped)
        }
        match (left) {
            case Some(_) => head
            case None => Some(wrapped)
        }
    }

    private func materializePieceLinks(first: ?InlinePieceLink, stopIdentity: Int64): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        var cursor = first
        while (let Some(link) <- cursor) {
            if (link.identity == stopIdentity) {
                break
            }
            let piece = link.piece
            if (link.active) {
                if (piece.marker != 0 && piece.length > 0) {
                    let raw = repeatDelimiter(piece.marker, piece.length)
                    out.add(parsedText(raw, raw, piece.start, piece.start + piece.length))
                } else {
                    for (node in piece.nodes) {
                        out.add(node)
                    }
                }
            }
            cursor = link.next
        }
        out.toArray()
    }

    private func repeatDelimiter(marker: Byte, count: Int64): String {
        let out = StringBuilder()
        for (_ in 0..count) {
            out.appendFromUtf8([marker])
        }
        out.toString()
    }

    private func scanStep(): Unit {
        scanSteps(1)
    }

    private func scanSteps(steps: Int64): Unit {
        budget.consumeScan(steps: steps)
        checkpointSteps += steps
        if (checkpointSteps >= 1024) {
            cancellation.throwIfCancelled(phase: "parse")
            checkpointSteps %= 1024
        }
    }

    private func scanExtensionBlock(
        lines: Array<LineRecord>,
        start: Int64,
        extensionDepth: Int64
    ): ?ExtensionBlockScan {
        for (ruleIndex in 0..dialect.blockRules.size) {
            let rule = dialect.blockRules[ruleIndex]
            let identity = "${rule.extensionId}/${rule.ruleId}"
            if (identity == suppressedBlockRule) {
                continue
            }
            if (rule.documentStartOnly && lines[start].startByte > 3) {
                continue
            }
            let trimmed = trimAscii(lines[start].text)
            if (!trimmed.startsWith(rule.openerPrefix)) {
                continue
            }
            if (extensionDepth >= limits.maximumNestingDepth) {
                throw LimitExceededException("nesting_depth", limits.maximumNestingDepth, extensionDepth + 1,
                    "extension_parse", span: Some(mappedSpan(lines[start].startByte, lines[start].endByte)),
                    extensionId: Some(rule.extensionId))
            }
            let captured = trimAscii(trimmed[rule.openerPrefix.size..])
            if (captured.size > rule.maximumCaptureLength) {
                throw LimitExceededException("extension_capture", rule.maximumCaptureLength, captured.size,
                    "extension_parse", span: Some(mappedSpan(lines[start].startByte, lines[start].endByte)),
                    extensionId: Some(rule.extensionId))
            }
            let name = firstWord(captured)
            let parameters = trimAscii(captured[name.size..])
            let typedParameters = parseSyntaxParameters(parameters, rule.parameters)
            if (typedParameters.isNone()) {
                diagnostics.add(
                    Diagnostic(
                        "MD3003_INVALID_EXTENSION_PARAMETER",
                        DiagnosticSeverity.Warning,
                        "invalid parameters for block extension rule ${rule.ruleId}",
                        mappedSpan(lines[start].startByte, lines[start].endByte),
                        extensionId: Some(rule.extensionId),
                        ruleId: Some(rule.ruleId)
                    )
                )
                return None
            }
            if (let BlockSyntaxKind.SingleLine <- rule.syntaxKind) {
                budget.consumeExtensionCallback()
                budget.consumeScan(
                    steps: syntaxRuleCost(rule.resourceCost, lines[start].endByte - lines[start].startByte))
                let span = mappedSpan(lines[start].startByte, lines[start].endByte)
                ensureLiteralBytes(captured.size, "extension_parse", consumeBudget: false)
                let children: Array<MarkdownNode> = match (rule.contentMode) {
                    case BlockContentMode.Markdown =>
                        if (captured.isEmpty()) {
                            []
                        } else {
                            [Paragraph(ids.next(),
                                parseInline(captured, lines[start].startByte + rule.openerPrefix.size, extensionDepth + 1),
                                span)]
                        }
                    case BlockContentMode.Literal => []
                }
                let kindId = if (rule.kindFromFirstWord && !name.isEmpty()) {
                    name
                } else {
                    rule.ruleId
                }
                let values = match (typedParameters) {
                    case Some(found) => found
                    case None => HashMap<String, SyntaxParameterValue>()
                }
                let payload = emitBlockPayload(rule, name, parameters, captured, span, children, values)
                let origin = NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(span),
                    extensionId: Some(rule.extensionId))
                let noPending: ?PendingExtensionState = None
                return Some(
                    ExtensionBlockScan(
                        Some(
                            CustomBlock(ids.next(), rule.extensionId, manifestVersion(rule.extensionId), kindId, payload,
                                children, Some(span), origin)), noPending, start + 1))
            }
            var index = start + 1
            var totalBytes: Int64 = 0
            var nestedBlocks: Int64 = 0
            while (index < lines.size) {
                let candidate = trimAscii(lines[index].text)
                if (candidate == rule.closer) {
                    if (nestedBlocks == 0) {
                        break
                    }
                    nestedBlocks--
                } else if (rule.allowNesting && candidate.startsWith(rule.openerPrefix)) {
                    nestedBlocks++
                }
                totalBytes += lines[index].endWithNewline - lines[index].startByte
                if (totalBytes > rule.maximumBlockBytes) {
                    throw LimitExceededException("extension_block_bytes", rule.maximumBlockBytes, totalBytes,
                        "extension_parse", span: Some(mappedSpan(lines[start].startByte, lines[index].endByte)),
                        extensionId: Some(rule.extensionId))
                }
                index++
            }
            if (index >= lines.size) {
                if (dialect.parserOptions.emitUnclosedExtensionDiagnostics) {
                    diagnostics.add(
                        Diagnostic(
                            "MD3002_UNCLOSED_EXTENSION",
                            DiagnosticSeverity.Warning,
                            "unclosed block extension rule ${rule.ruleId}",
                            mappedSpan(lines[start].startByte, lines[start].endByte),
                            extensionId: Some(rule.extensionId),
                            ruleId: Some(rule.ruleId)
                        )
                    )
                }
                return None
            }
            budget.consumeExtensionCallback()
            budget.consumeScan(steps: syntaxRuleCost(rule.resourceCost, lines[index].endByte - lines[start].startByte))
            let literal = joinLineRecords(lines, start + 1, index)
            ensureLiteralBytes(literal.size, "extension_parse")
            let span = mappedSpan(lines[start].startByte, lines[index].endByte)
            let kindId = if (!rule.kindFromFirstWord || name.isEmpty()) {
                rule.ruleId
            } else {
                name
            }
            let values = match (typedParameters) {
                case Some(found) => found
                case None => HashMap<String, SyntaxParameterValue>()
            }
            match (rule.contentMode) {
                case BlockContentMode.Markdown =>
                    let childLines = lines.slice(start + 1, index - start - 1)
                    let childSuppression = if (rule.allowNesting) {
                        suppressedBlockRule
                    } else {
                        identity
                    }
                    let noNode: ?MarkdownNode = None
                    return Some(
                        ExtensionBlockScan(noNode,
                            Some(
                                PendingExtensionState(rule, name, parameters, literal, values, span, kindId, childLines,
                                    childSuppression, index + 1)), index + 1))
                case BlockContentMode.Literal =>
                    let children: Array<MarkdownNode> = []
                    let payload = emitBlockPayload(rule, kindId, parameters, literal, span, children, values)
                    let origin = NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(span),
                        extensionId: Some(rule.extensionId))
                    let noPending: ?PendingExtensionState = None
                    return Some(
                        ExtensionBlockScan(
                            Some(
                                CustomBlock(ids.next(), rule.extensionId, manifestVersion(rule.extensionId), kindId,
                                    payload, children, Some(span), origin)), noPending, index + 1))
            }
        }
        None
    }

    private func isAnyBlockStart(lines: Array<LineRecord>, index: Int64): Bool {
        if (referenceLineStarts.contains(lines[index].startByte)) {
            return true
        }
        if (isBlockStart(lines, index)) {
            return true
        }
        if (dialect.parserOptions.extensionsEnabled && dialect.blockRules.size > 0) {
            let trimmed = trimAscii(lines[index].text)
            for (ruleIndex in 0..dialect.blockRules.size) {
                let rule = dialect.blockRules[ruleIndex]
                let identity = "${rule.extensionId}/${rule.ruleId}"
                if (identity != suppressedBlockRule && trimmed.startsWith(rule.openerPrefix)) {
                    return true
                }
            }
        }
        false
    }

    private func manifestVersion(extensionId: String): String {
        for (manifestIndex in 0..dialect.manifests.size) {
            let manifest = dialect.manifests[manifestIndex]
            if (manifest.extensionId == extensionId) {
                return manifest.semanticVersion
            }
        }
        ""
    }

    private func emitInlinePayload(rule: InlineSyntaxRule, literal: String, span: SourceSpan,
        children: Array<MarkdownNode>): CustomPayload {
        match (rule.emitter) {
            case Some(emitter) => try {
                emitter.emit(InlineSyntaxMatch(rule.extensionId, rule.ruleId, literal, span, children))
            } catch (error: Exception) {
                let manifest = extensionManifest(rule.extensionId)
                throw ExtensionFailureException(rule.extensionId, manifest.semanticVersion,
                    manifest.implementationVersion, "extension_emit", error, ruleId: Some(rule.ruleId), span: Some(span))
            }
            case None => SyntaxPayload(rule.ruleId, "", literal)
        }
    }

    private func emitBlockPayload(rule: BlockSyntaxRule, name: String, parameters: String, literal: String,
        span: SourceSpan, children: Array<MarkdownNode>, values: HashMap<String, SyntaxParameterValue>): CustomPayload {
        match (rule.emitter) {
            case Some(emitter) => try {
                emitter.emit(
                    BlockSyntaxMatch(rule.extensionId, rule.ruleId, name, parameters, literal, span, children, values))
            } catch (error: Exception) {
                let manifest = extensionManifest(rule.extensionId)
                throw ExtensionFailureException(rule.extensionId, manifest.semanticVersion,
                    manifest.implementationVersion, "extension_emit", error, ruleId: Some(rule.ruleId), span: Some(span))
            }
            case None => SyntaxPayload(name, parameters, literal, typedValues: values)
        }
    }

    private func hasLiteralBackslashRuleAt(text: String, start: Int64): Bool {
        for (index in 0..dialect.inlineRules.size) {
            let rule = dialect.inlineRules[index]
            if (let InlineEscapePolicy.LiteralBackslash <- rule.escapePolicy) {
                if (startsAt(text, rule.opener, start)) {
                    return true
                }
            }
        }
        false
    }

    private func extensionManifest(extensionId: String): ExtensionManifest {
        for (manifestIndex in 0..dialect.manifests.size) {
            let manifest = dialect.manifests[manifestIndex]
            if (manifest.extensionId == extensionId) {
                return manifest
            }
        }
        throw IllegalStateException("compiled dialect is missing extension manifest")
    }

    private func hasOpenFence(lines: ArrayList<LineRecord>): Bool {
        var fenceLines: Int64 = 0
        for (line in lines) {
            if (isFenceStart(line.text)) {
                fenceLines++
            }
        }
        fenceLines % 2 == 1
    }

    private func hasNestedListMarker(lines: ArrayList<LineRecord>): Bool {
        for (line in lines) {
            if (detailedListMarker(line.text).isSome()) {
                return true
            }
        }
        false
    }

    private func parseReferenceDefinitionAt(
        lines: Array<LineRecord>,
        start: Int64
    ): ?(String, String, String, String, String, Int64) {
        if (leadingWhitespace(lines[start].text) > 3) {
            return None
        }
        let header = StringBuilder()
        header.append(trimAscii(lines[start].text))
        if (!header.toString().startsWith("[")) {
            return None
        }
        var next = start + 1
        var close = findReferenceLabelClose(header.toString())
        while (close < 0 && next < lines.size && !isBlank(lines[next].text)) {
            header.append("\n")
            header.append(lines[next].text)
            next++
            close = findReferenceLabelClose(header.toString())
        }
        let text = header.toString()
        if (close <= 1 || close + 1 >= text.size || text[close + 1] != b':') {
            return None
        }
        let label = text[1..close]
        if (label.size > 999 || containsUnescapedOpenBracket(label) || normalizeReferenceLabel(label).isEmpty()) {
            return None
        }
        let candidate = StringBuilder()
        candidate.append(text[close + 2..])
        while (next <= lines.size) {
            let source = candidate.toString()
            if (!trimAscii(source).isEmpty()) {
                if (let Some((end, destinationRaw, destination, titleRaw, title)) <- parseInlineLinkTarget(source + ")",
                    0)) {
                    if (end == source.size) {
                        if (titleRaw.isEmpty() && next < lines.size && !isBlank(lines[next].text) &&
                            standaloneReferenceTitle(trimAscii(lines[next].text))) {
                            candidate.append("\n")
                            candidate.append(lines[next].text)
                            next++
                            continue
                        }
                        return Some((label, destinationRaw, destination, titleRaw, title, next))
                    }
                }
            }
            if (next >= lines.size || isBlank(lines[next].text)) {
                break
            }
            candidate.append("\n")
            candidate.append(lines[next].text)
            next++
        }
        None
    }

    private func mappedSpan(decodedStart: Int64, decodedEnd: Int64): SourceSpan {
        SourceSpan(source.originalOffset(decodedStart), source.originalOffset(decodedEnd))
    }

    private func parsedText(raw: String, value: String, decodedStart: Int64, decodedEnd: Int64): Text {
        storedText(raw, value, mappedSpan(decodedStart, decodedEnd))
    }

    private func storedText(raw: String, value: String, span: SourceSpan): Text {
        ensureLiteralBytes(max(raw.size, value.size), "inline_parse", consumeBudget: false)
        let useSlice = if (span.length() >= 256) {
            source.matches(span, raw)
        } else {
            false
        }
        let rawStorage = if (useSlice) {
            LiteralStorage.Slice(source.sourceSlice(span))
        } else {
            LiteralStorage.Copy(raw)
        }
        let valueStorage = if (raw == value) {
            rawStorage
        } else {
            LiteralStorage.Copy(value)
        }
        let normalized: ?String = None
        Text(ids.next(), rawStorage, valueStorage, span, normalized, NodeOrigin.parsed(span))
    }

    private func storageForLiteral(value: String, span: SourceSpan): LiteralStorage {
        if (source.matches(span, value)) {
            LiteralStorage.Slice(source.sourceSlice(span))
        } else {
            LiteralStorage.Copy(value)
        }
    }

    private func coalesceTextNodes(nodes: Array<MarkdownNode>): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        for (node in nodes) {
            match (node) {
                case current: Text =>
                    if (!out.isEmpty()) {
                        match (out[out.size - 1]) {
                            case previous: Text =>
                                let previousSpan = requiredNodeSpan(previous)
                                let currentSpan = requiredNodeSpan(current)
                                if (previousSpan.endByte == currentSpan.startByte) {
                                    let mergedSpan = SourceSpan(previousSpan.startByte, currentSpan.endByte)
                                    let raw = previous.raw + current.raw
                                    let value = previous.value + current.value
                                    ensureLiteralBytes(max(raw.size, value.size), "inline_parse", consumeBudget: false)
                                    let useSlice = if (mergedSpan.length() >= 256) {
                                        source.matches(mergedSpan, raw)
                                    } else {
                                        false
                                    }
                                    let rawStorage = if (useSlice) {
                                        LiteralStorage.Slice(source.sourceSlice(mergedSpan))
                                    } else {
                                        LiteralStorage.Copy(raw)
                                    }
                                    let valueStorage = if (raw == value) {
                                        rawStorage
                                    } else {
                                        LiteralStorage.Copy(value)
                                    }
                                    out[out.size - 1] = Text(previous.nodeId, rawStorage, valueStorage, mergedSpan,
                                        previous.normalized, NodeOrigin.parsed(mergedSpan))
                                    continue
                                }
                            case _ => ()
                        }
                    }
                    out.add(current)
                case _ => out.add(node)
            }
        }
        out.toArray()
    }

    private func expandGfmAutolinks(nodes: Array<MarkdownNode>): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        for (node in nodes) {
            match (node) {
                case text: Text => for (expanded in expandGfmText(text)) {
                    out.add(expanded)
                }
                case _ => out.add(node)
            }
        }
        out.toArray()
    }

    private func expandGfmText(textNode: Text): Array<MarkdownNode> {
        let value = textNode.value
        let span = requiredNodeSpan(textNode)
        let out = ArrayList<MarkdownNode>()
        var plainStart: Int64 = 0
        var index: Int64 = 0
        while (index < value.size) {
            let kind = extendedAutolinkStart(value, index)
            if (kind > 0) {
                let end = extendedAutolinkEnd(value, index, kind)
                if (end > index) {
                    if (index > plainStart) {
                        out.add(
                            storedText(value[plainStart..index], value[plainStart..index],
                                SourceSpan(span.startByte + plainStart, span.startByte + index)))
                    }
                    let label = value[index..end]
                    let destination = if (kind == 1) {
                        "http://" + label
                    } else if (kind == 3) {
                        "mailto:" + label
                    } else {
                        label
                    }
                    let linkSpan = SourceSpan(span.startByte + index, span.startByte + end)
                    out.add(
                        Link(ids.next(), label, destination, "", "", LinkSyntaxKind.ExtendedAutolink,
                            [storedText(label, label, linkSpan)], linkSpan))
                    index = end
                    plainStart = end
                    continue
                }
            }
            index = nextRuneOffset(value, index)
        }
        if (plainStart < value.size) {
            out.add(
                storedText(value[plainStart..], value[plainStart..], SourceSpan(span.startByte + plainStart,
                    span.endByte)))
        }
        if (out.isEmpty()) {
            [textNode]
        } else {
            out.toArray()
        }
    }

    private func requiredNodeSpan(node: MarkdownNode): SourceSpan {
        match (node.span) {
            case Some(span) => span
            case None => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "parsed inline node is missing span", phase: "inline_parse")
        }
    }

    private func parseInlineLineRange(lines: Array<LineRecord>, start: Int64, end: Int64): Array<MarkdownNode> {
        let combined = StringBuilder()
        var hasDelimiter = false
        for (index in start..end) {
            if (index > start) {
                combined.append("\n")
            }
            let content = stripTrailingSpaces(lines[index].text[leadingWhitespace(lines[index].text)..])
            if (content.contains("*") || content.contains("_") || content.contains("`")) {
                hasDelimiter = true
            }
            combined.append(content)
        }
        if (hasDelimiter) {
            return parseInline(combined.toString(), lines[start].startByte + leadingWhitespace(lines[start].text), 0)
        }
        let out = ArrayList<MarkdownNode>()
        for (index in start..end) {
            let contentStart = leadingWhitespace(lines[index].text)
            let content = stripTrailingSpaces(lines[index].text[contentStart..])
            for (child in parseInline(content, lines[index].startByte + contentStart, 0)) {
                out.add(child)
            }
            if (index + 1 < end) {
                out.add(SoftBreak(ids.next(), mappedSpan(lines[index].endByte, lines[index + 1].startByte)))
            }
        }
        out.toArray()
    }

    private func isGfmProfile(): Bool {
        match (profile.kind) {
            case ProfileKind.Gfm029 => true
            case ProfileKind.GfmModernV1 => true
            case _ => false
        }
    }

    private func ensureLiteralBytes(observed: Int64, phase: String, consumeBudget!: Bool = true): Unit {
        cancellation.throwIfCancelled(phase: phase)
        if (observed > limits.maximumLiteralBytes) {
            throw LimitExceededException("literal_bytes", limits.maximumLiteralBytes, observed, phase)
        }
        if (consumeBudget) {
            budget.consumeScan(steps: observed)
        }
    }

    private func isLegacyGfmComment(text: String, start: Int64): Bool {
        if (profile.standardVersion != "0.29-gfm" || !startsAt(text, "<!--", start)) {
            return false
        }
        let end = findString(text, "-->", start + 4)
        if (end < 0) {
            return false
        }
        let body = text[start + 4..end]
        body.isEmpty() || body.startsWith(">") || body.startsWith("->") || body.contains("--") || body.endsWith("-")
    }
}

private func startsReferenceTitle(value: String): Bool {
    !value.isEmpty() && (value[0] == b'"' || value[0] == b'\'' || value[0] == b'(')
}

private func standaloneReferenceTitle(value: String): Bool {
    if (!startsReferenceTitle(value)) {
        return false
    }
    let opener = value[0]
    let closer: Byte = if (opener == b'(') {
        b')'
    } else {
        opener
    }
    var index: Int64 = 1
    while (index < value.size && value[index] != closer) {
        if (value[index] == b'\\' && index + 1 < value.size) {
            index += 2
        } else {
            index = nextRuneOffset(value, index)
        }
    }
    index < value.size && trimAscii(value[index + 1..]).isEmpty()
}

private func referenceParts(line: String): ?(String, String, String) {
    let text = trimAscii(line)
    if (!text.startsWith("[")) {
        return None
    }
    let close = findString(text, "]:", 1)
    if (close <= 1) {
        return None
    }
    let label = text[1..close]
    let rest = trimAscii(text[close + 2..])
    if (rest.isEmpty()) {
        return None
    }
    let target = splitLinkTarget(rest)
    Some((label, target[0], target[1]))
}

private func findReferenceLabelClose(text: String): Int64 {
    var index: Int64 = 1
    while (index < text.size) {
        if (text[index] == b'\\' && index + 1 < text.size) {
            index += 2
            continue
        }
        if (text[index] == b']') {
            return index
        }
        index = nextRuneOffset(text, index)
    }
    -1
}

private func normalizeReferenceLabel(label: String): String {
    let text = trimAscii(label)
    var needsNormalization = false
    var index: Int64 = 0
    while (index < text.size) {
        let byte = text[index]
        if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13 || (byte >= b'A' && byte <= b'Z') || byte >= 0x80) {
            needsNormalization = true
            break
        }
        index++
    }
    if (!needsNormalization) {
        return text
    }
    let out = StringBuilder()
    var pendingSpace = false
    index = 0
    while (index < text.size) {
        let byte = text[index]
        if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13) {
            pendingSpace = true
            index++
        } else {
            if (pendingSpace && index > 0) {
                out.append(" ")
            }
            pendingSpace = false
            if (byte >= b'A' && byte <= b'Z') {
                out.appendFromUtf8([byte + 32])
                index++
            } else {
                let next = nextRuneOffset(text, index)
                out.append(text[index..next])
                index = next
            }
        }
    }
    out.toString().toLower().replace("ß", "ss")
}

private func isBlank(text: String): Bool {
    var index: Int64 = 0
    while (index < text.size) {
        if (text[index] != b' ' && text[index] != b'\t') {
            return false
        }
        index++
    }
    true
}

private func leadingSpaces(text: String): Int64 {
    var index: Int64 = 0
    while (index < text.size && index < 4 && text[index] == b' ') {
        index++
    }
    index
}

private func skipAsciiSpace(text: String, start: Int64): Int64 {
    var index = start
    while (index < text.size && (text[index] == b' ' || text[index] == b'\t')) {
        index++
    }
    index
}

private func trimAscii(text: String): String {
    var start: Int64 = 0
    var end = text.size
    while (start < end && (text[start] == b' ' || text[start] == b'\t')) {
        start++
    }
    while (end > start && (text[end - 1] == b' ' || text[end - 1] == b'\t')) {
        end--
    }
    text[start..end]
}

private func stripTrailingSpaces(text: String): String {
    var end = text.size
    while (end > 0 && (text[end - 1] == b' ' || text[end - 1] == b'\t')) {
        end--
    }
    text[..end]
}

private func endsWithTwoSpaces(text: String): Bool {
    text.size >= 2 && text[text.size - 1] == b' ' && text[text.size - 2] == b' '
}

private func isAtxHeading(text: String): Bool {
    let leading = leadingSpaces(text)
    if (leading > 3 || leading >= text.size || text[leading] != b'#') {
        return false
    }
    var level: Int64 = 0
    while (leading + level < text.size && text[leading + level] == b'#') {
        level++
    }
    level >= 1 && level <= 6 && (leading + level == text.size || text[leading + level] == b' ' ||
        text[leading + level] == b'\t')
}

private func stripClosingAtx(text: String): String {
    var end = text.size
    while (end > 0 && (text[end - 1] == b' ' || text[end - 1] == b'\t')) {
        end--
    }
    var marker = end
    while (marker > 0 && text[marker - 1] == b'#') {
        marker--
    }
    if (marker == 0 && end > 0) {
        return ""
    }
    if (marker < end && marker > 0 && (text[marker - 1] == b' ' || text[marker - 1] == b'\t')) {
        end = marker - 1
        while (end > 0 && (text[end - 1] == b' ' || text[end - 1] == b'\t')) {
            end--
        }
    }
    text[..end]
}

private func isSetextHeading(lines: Array<LineRecord>, index: Int64): Bool {
    if (index + 1 >= lines.size || isBlank(lines[index].text)) {
        return false
    }
    let first = lines[index].text
    if (isThematicBreak(first)) {
        return false
    }
    if (isAtxHeading(first)) {
        return false
    }
    if (isFenceStart(first)) {
        return false
    }
    if (isQuoteLine(first)) {
        return false
    }
    if (isListLine(first)) {
        return false
    }
    if (isHtmlBlock(first)) {
        return false
    }
    if (isIndentedCode(first)) {
        return false
    }
    isSetextMarkerLine(lines[index + 1])
}

private func isSetextMarkerLine(line: LineRecord): Bool {
    if (!line.allowSetext) {
        return false
    }
    let start = leadingSpaces(line.text)
    if (start > 3 || start >= line.text.size) {
        return false
    }
    let byte = line.text[start]
    if (byte != b'=' && byte != b'-') {
        return false
    }
    var index = start
    while (index < line.text.size && line.text[index] == byte) {
        index++
    }
    while (index < line.text.size) {
        if (line.text[index] != b' ' && line.text[index] != b'\t') {
            return false
        }
        index++
    }
    true
}

private func findSetextMarker(lines: Array<LineRecord>, start: Int64): Int64 {
    var index = start
    while (index + 1 < lines.size && !isBlank(lines[index].text)) {
        if (index > start) {
            let text = lines[index].text
            if (isFenceStart(text) || isAtxHeading(text) || isThematicBreak(text) || isQuoteLine(text)) {
                return -1
            }
            if (isParagraphInterruptingList(text)) {
                return -1
            }
            let htmlType = htmlBlockType(text)
            if (htmlType > 0 && htmlType != 7) {
                return -1
            }
        }
        if (isSetextMarkerLine(lines[index + 1])) {
            return index + 1
        }
        index++
    }
    -1
}

private func firstNonSpace(text: String): Byte {
    text[leadingSpaces(text)]
}

private func isThematicBreak(text: String): Bool {
    let start = leadingSpaces(text)
    if (start > 3 || text.size - start < 3) {
        return false
    }
    let marker = text[start]
    if (marker != b'-' && marker != b'*' && marker != b'_') {
        return false
    }
    var count: Int64 = 0
    var index = start
    while (index < text.size) {
        if (text[index] == marker) {
            count++
        } else if (text[index] != b' ' && text[index] != b'\t') {
            return false
        }
        index++
    }
    count >= 3
}

private func isFenceStart(text: String): Bool {
    let leading = leadingSpaces(text)
    if (leading > 3 || leading >= text.size) {
        return false
    }
    let marker = text[leading]
    if (marker != b'`' && marker != b'~') {
        return false
    }
    var count: Int64 = 0
    while (leading + count < text.size && text[leading + count] == marker) {
        count++
    }
    if (count < 3) {
        return false
    }
    if (marker == b'`' && text[leading + count..].contains("`")) {
        return false
    }
    true
}

private func isFenceClose(text: String, marker: Byte, minimum: Int64): Bool {
    let leading = leadingSpaces(text)
    if (leading > 3) {
        return false
    }
    var count: Int64 = 0
    while (leading + count < text.size && text[leading + count] == marker) {
        count++
    }
    if (count < minimum) {
        return false
    }
    trimAscii(text[leading + count..]).isEmpty()
}

private func isQuoteLine(text: String): Bool {
    let leading = leadingSpaces(text)
    leading <= 3 && leading < text.size && text[leading] == b'>'
}

private func quoteMarker(text: String): Int64 {
    leadingSpaces(text)
}

private func simpleQuotePrefixDepth(text: String): Int64 {
    var depth: Int64 = 0
    var index: Int64 = 0
    while (index < text.size && text[index] == b'>') {
        depth++
        index++
        if (index < text.size && text[index] == b' ') {
            index++
        } else if (index < text.size && text[index] == b'\t') {
            return 0
        }
    }
    depth
}

private func simpleQuoteContentStart(text: String, levels: Int64): Int64 {
    var level: Int64 = 0
    var index: Int64 = 0
    while (level < levels) {
        index++
        if (index < text.size && text[index] == b' ') {
            index++
        }
        level++
    }
    index
}

private func isIndentedCode(text: String): Bool {
    leadingIndentColumns(text) >= 4
}

private func detailedListMarker(text: String): ?ListMarkerInfo {
    let indent = leadingIndentColumns(text)
    let indentBytes = leadingWhitespace(text)
    if (indent > 3 || indentBytes >= text.size) {
        return None
    }
    var ordered = false
    var startNumber: Int64 = 0
    var delimiter = ListDelimiter.None
    var bullet: Byte = 0
    var markerEnd = indentBytes
    if (text[indentBytes] == b'-' || text[indentBytes] == b'+' || text[indentBytes] == b'*') {
        bullet = text[indentBytes]
        markerEnd = indentBytes + 1
    } else {
        var index = indentBytes
        var digits: Int64 = 0
        while (index < text.size && text[index] >= b'0' && text[index] <= b'9' && digits < 9) {
            startNumber = startNumber * 10 + Int64(text[index] - b'0')
            index++;
            digits++
        }
        if (digits == 0 || index >= text.size || (text[index] != b'.' && text[index] != b')')) {
            return None
        }
        ordered = true
        delimiter = if (text[index] == b'.') {
            ListDelimiter.Period
        } else {
            ListDelimiter.Parenthesis
        }
        markerEnd = index + 1
    }
    if (markerEnd < text.size && text[markerEnd] != b' ' && text[markerEnd] != b'\t') {
        return None
    }
    let markerColumn = indent + (markerEnd - indentBytes)
    var paddingColumns: Int64 = 0
    var column = markerColumn
    var contentStart = markerEnd
    while (contentStart < text.size && (text[contentStart] == b' ' || text[contentStart] == b'\t')) {
        let nextColumn = if (text[contentStart] == b'\t') {
            column + (4 - column % 4)
        } else {
            column + 1
        }
        paddingColumns += nextColumn - column
        column = nextColumn
        contentStart++
    }
    let contentIndent: Int64 = if (paddingColumns >= 1 && paddingColumns <= 4) {
        column
    } else {
        markerColumn + 1
    }
    let syntheticIndent = if (paddingColumns > 4) {
        max(0, column - contentIndent)
    } else {
        0
    }
    ListMarkerInfo(ordered, startNumber, delimiter, bullet, indent, contentStart, contentIndent, syntheticIndent)
}

private func sameListFamily(left: ListMarkerInfo, right: ListMarkerInfo): Bool {
    if (left.ordered != right.ordered) {
        return false
    }
    if (left.ordered) {
        match (left.delimiter) {
            case ListDelimiter.Period =>
                if (let ListDelimiter.Period <- right.delimiter) {
                    true
                } else {
                    false
                }
            case ListDelimiter.Parenthesis =>
                if (let ListDelimiter.Parenthesis <- right.delimiter) {
                    true
                } else {
                    false
                }
            case _ => false
        }
    } else {
        left.bullet == right.bullet
    }
}

private func isListLine(text: String): Bool {
    detailedListMarker(text).isSome()
}

private func isHtmlBlock(text: String): Bool {
    htmlBlockType(text) > 0
}

private func htmlBlockType(text: String): Int64 {
    let leading = leadingSpaces(text)
    if (leading > 3 || leading >= text.size || text[leading] != b'<') {
        return 0
    }
    let trimmed = trimAscii(text)
    if (!trimmed.startsWith("<")) {
        return 0
    }
    let lower = lowerAsciiValue(trimmed)
    if (lower.startsWith("<script") || lower.startsWith("<pre") || lower.startsWith("<style") || lower.startsWith(
        "<textarea")) {
        return 1
    }
    if (trimmed.startsWith("<!--")) {
        return 2
    }
    if (trimmed.startsWith("<?")) {
        return 3
    }
    if (trimmed.startsWith("<![CDATA[")) {
        return 5
    }
    if (trimmed.startsWith("<!") && trimmed.size > 2 && trimmed[2] >= b'A' && trimmed[2] <= b'Z') {
        return 4
    }
    var start: Int64 = 1
    if (start < trimmed.size && trimmed[start] == b'/') {
        start++
    }
    var end = start
    while (end < trimmed.size && ((trimmed[end] >= b'A' && trimmed[end] <= b'Z') || (trimmed[end] >= b'a' &&
            trimmed[end] <= b'z') || (trimmed[end] >= b'0' && trimmed[end] <= b'9'))) {
        end++
    }
    if (end == start) {
        return 0
    }
    if (end < trimmed.size && trimmed[end] != b' ' && trimmed[end] != b'\t' && trimmed[end] != b'/' && trimmed[end] !=
        b'>') {
        return 0
    }
    if (isBlockTag(lowerAsciiValue(trimmed[start..end]))) {
        return 6
    }
    if (trimmed.endsWith(">")) {
        let firstClose = findByte(trimmed, b'>', end)
        if (firstClose == trimmed.size - 1 && isInlineHtml(trimmed[1..trimmed.size - 1])) {
            return 7
        }
    }
    0
}

private func htmlBlockEnds(blockType: Int64, line: String): Bool {
    let lower = lowerAsciiValue(line)
    match (blockType) {
        case 1 => lower.contains("</script>") || lower.contains("</pre>") || lower.contains("</style>") ||
            lower.contains("</textarea>")
        case 2 => line.contains("-->")
        case 3 => line.contains("?>")
        case 4 => line.contains(">")
        case 5 => line.contains("]]>")
        case _ => false
    }
}

private func isBlockTag(name: String): Bool {
    let tags = ["address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col",
        "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer",
        "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe",
        "legend", "li", "link", "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param",
        "section", "source", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"]
    for (tag in tags) {
        if (tag == name) {
            return true
        }
    }
    false
}

private func lowerAsciiValue(value: String): String {
    let bytes = value.toArray()
    for (index in 0..bytes.size) {
        if (bytes[index] >= b'A' && bytes[index] <= b'Z') {
            bytes[index] += 32
        }
    }
    String.fromUtf8(bytes)
}

private func isBlockStart(lines: Array<LineRecord>, index: Int64): Bool {
    if (index >= lines.size) {
        return false
    }
    let text = lines[index].text
    let leading = leadingSpaces(text)
    if (leading > 3 || leading >= text.size || text[leading] == b'\t') {
        return false
    }
    let first = text[leading]
    let mayStartSpecial = first == b'`' || first == b'~' || first == b'#' || first == b'*' || first == b'_' || first ==
        b'-' || first == b'+' || first == b'>' || first == b'<' || (first >= b'0' && first <= b'9')
    if (!mayStartSpecial) {
        if (index + 1 < lines.size) {
            return isSetextMarkerLine(lines[index + 1])
        }
        return false
    }
    if (isFenceStart(text)) {
        return true
    }
    if (isAtxHeading(text)) {
        return true
    }
    if (isThematicBreak(text)) {
        return true
    }
    if (isQuoteLine(text)) {
        return true
    }
    if (isParagraphInterruptingList(text)) {
        return true
    }
    let htmlType = htmlBlockType(text)
    if (htmlType > 0 && htmlType != 7) {
        return true
    }
    isSetextHeading(lines, index)
}

private func isParagraphInterruptingList(text: String): Bool {
    match (detailedListMarker(text)) {
        case Some(marker) =>
            let hasContent = marker.contentStart < text.size
            hasContent && (!marker.ordered || marker.startNumber == 1)
        case None => false
    }
}

private func leadingWhitespace(text: String): Int64 {
    var index: Int64 = 0
    while (index < text.size && (text[index] == b' ' || text[index] == b'\t')) {
        index++
    }
    index
}

private func leadingIndentColumns(text: String): Int64 {
    var column: Int64 = 0
    var index: Int64 = 0
    while (index < text.size && (text[index] == b' ' || text[index] == b'\t')) {
        column = if (text[index] == b'\t') {
            column + (4 - column % 4)
        } else {
            column + 1
        }
        index++
    }
    column
}

private func visualColumnAt(text: String, end: Int64): Int64 {
    var column: Int64 = 0
    var index: Int64 = 0
    while (index < end && index < text.size) {
        column = if (text[index] == b'\t') {
            column + (4 - column % 4)
        } else {
            column + 1
        }
        index++
    }
    column
}

// Returns normalized text, consumed source bytes, and synthetic leading spaces.
private func stripIndentColumns(text: String, target: Int64): (String, Int64, Int64) {
    var column: Int64 = 0
    var index: Int64 = 0
    while (index < text.size && (text[index] == b' ' || text[index] == b'\t')) {
        if (text[index] == b'\t') {
            column += 4 - column % 4
        } else {
            column++
        }
        index++
    }
    let residual = max(0, column - target)
    (repeatSpaces(residual) + text[index..], index, residual)
}

private func repeatSpaces(count: Int64): String {
    let out = StringBuilder()
    for (_ in 0..count) {
        out.append(" ")
    }
    out.toString()
}

private func stripUpToSpaces(text: String, count: Int64): String {
    var index: Int64 = 0
    while (index < text.size && index < count && text[index] == b' ') {
        index++
    }
    text[index..]
}

private func unescapeBackslashes(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'\\' && index + 1 < value.size && isAsciiPunctuation(value[index + 1])) {
            out.append(value[index + 1..index + 2])
            index += 2
        } else {
            let next = nextRuneOffset(value, index)
            out.append(value[index..next])
            index = next
        }
    }
    out.toString()
}

private func joinLineRecords(lines: Array<LineRecord>, start: Int64, end: Int64): String {
    let out = StringBuilder()
    for (index in start..end) {
        if (index > start) {
            out.append("\n")
        }
        out.append(lines[index].text)
    }
    out.toString()
}

private func joinStrings(values: Array<String>, separator: String): String {
    let out = StringBuilder()
    for (index in 0..values.size) {
        if (index > 0) {
            out.append(separator)
        }
        out.append(values[index])
    }
    out.toString()
}

private func isTableRow(text: String): Bool {
    text.contains("|") && !isBlank(text)
}

private func isTableStart(lines: Array<LineRecord>, index: Int64): Bool {
    if (index + 1 >= lines.size || !isTableRow(lines[index].text)) {
        return false
    }
    let cells = splitTable(lines[index + 1].text)
    if (splitTable(lines[index].text).size != cells.size) {
        return false
    }
    if (cells.isEmpty()) {
        return false
    }
    for (cell in cells) {
        let stripped = stripColons(trimAscii(cell))
        if (stripped.isEmpty()) {
            return false
        }
        for (i in 0..stripped.size) {
            if (stripped[i] != b'-') {
                return false
            }
        }
    }
    true
}

private func splitTable(text: String): Array<String> {
    let out = ArrayList<String>()
    var start: Int64 = if (text.startsWith("|")) {
        1
    } else {
        0
    }
    let endLimit = if (text.endsWith("|")) {
        text.size - 1
    } else {
        text.size
    }
    var index = start
    while (index <= endLimit) {
        if (index == endLimit || (text[index] == b'|' && !isEscaped(text, index))) {
            out.add(trimAscii(text[start..index]))
            start = index + 1
        }
        index++
    }
    out.toArray()
}

private func unescapeTablePipes(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'\\' && index + 1 < value.size && value[index + 1] == b'|') {
            out.append("|")
            index += 2
        } else {
            let next = nextRuneOffset(value, index)
            out.append(value[index..next])
            index = next
        }
    }
    out.toString()
}

private func tableAlignments(text: String): Array<TableAlignment> {
    let out = ArrayList<TableAlignment>()
    for (cell in splitTable(text)) {
        let trimmed = trimAscii(cell)
        let left = trimmed.startsWith(":")
        let right = trimmed.endsWith(":")
        out.add(if (left && right) {
            TableAlignment.Center
        } else if (left) {
            TableAlignment.Left
        } else if (right) {
            TableAlignment.Right
        } else {
            TableAlignment.None
        })
    }
    out.toArray()
}

private func stripColons(text: String): String {
    var start: Int64 = 0
    var end = text.size
    if (start < end && text[start] == b':') {
        start++
    }
    if (end > start && text[end - 1] == b':') {
        end--
    }
    text[start..end]
}

private func firstWord(text: String): String {
    var index: Int64 = 0
    while (index < text.size && text[index] != b' ' && text[index] != b'\t') {
        index++
    }
    text[..index]
}

private func parseSyntaxParameters(raw: String, specs: ImmutableArray<SyntaxParameterSpec>): ?HashMap<String,
    SyntaxParameterValue> {
    let values = HashMap<String, SyntaxParameterValue>()
    if (specs.isEmpty()) {
        return Some(values)
    }
    let tokens = splitSyntaxParameterTokens(raw)
    if (tokens.isNone()) {
        return None
    }
    let actualTokens: Array<String> = match (tokens) {
        case Some(found) => found;
        case None => []
    }
    for (token in actualTokens) {
        let equals = findByte(token, b'=', 0)
        if (equals <= 0) {
            return None
        }
        let name = token[..equals]
        let rawValue = token[equals + 1..]
        var specIndex: Int64 = -1
        for (index in 0..specs.size) {
            if (specs[index].name == name) {
                specIndex = index
                break
            }
        }
        if (specIndex < 0 || values.get(name).isSome()) {
            return None
        }
        let parsed: SyntaxParameterValue
        match (specs[specIndex].parameterType) {
            case SyntaxParameterType.StringValue => parsed = SyntaxParameterValue.StringValue(rawValue)
            case SyntaxParameterType.IntegerValue => try {
                parsed = SyntaxParameterValue.IntegerValue(Int64.parse(rawValue))
            } catch (_: Exception) {
                return None
            }
            case SyntaxParameterType.BooleanValue =>
                if (rawValue == "true") {
                    parsed = SyntaxParameterValue.BooleanValue(true)
                } else if (rawValue == "false") {
                    parsed = SyntaxParameterValue.BooleanValue(false)
                } else {
                    return None
                }
            case SyntaxParameterType.IdentifierValue =>
                if (!isSyntaxIdentifier(rawValue)) {
                    return None
                }
                parsed = SyntaxParameterValue.IdentifierValue(rawValue)
        }
        values.add(name, parsed)
    }
    for (index in 0..specs.size) {
        if (specs[index].required && values.get(specs[index].name).isNone()) {
            return None
        }
    }
    Some(values)
}

private func splitSyntaxParameterTokens(raw: String): ?Array<String> {
    let tokens = ArrayList<String>()
    var current = StringBuilder()
    var quoteByte: Byte = 0
    var index: Int64 = 0
    while (index < raw.size) {
        let byte = raw[index]
        if (byte == b'\\') {
            if (index + 1 >= raw.size) {
                return None
            }
            let next = nextRuneOffset(raw, index + 1)
            current.append(raw[index + 1..next])
            index = next
            continue
        }
        if (quoteByte != 0) {
            if (byte == quoteByte) {
                quoteByte = 0
                index++;
                continue
            }
            let next = nextRuneOffset(raw, index)
            current.append(raw[index..next]);
            index = next
            continue
        }
        if (byte == b'"' || byte == b'\'') {
            quoteByte = byte
            index++;
            continue
        }
        if (byte == b' ' || byte == b'\t') {
            if (current.size > 0) {
                tokens.add(current.toString());
                current = StringBuilder()
            }
            index++;
            continue
        }
        let next = nextRuneOffset(raw, index)
        current.append(raw[index..next]);
        index = next
    }
    if (quoteByte != 0) {
        return None
    }
    if (current.size > 0) {
        tokens.add(current.toString())
    }
    Some(tokens.toArray())
}

private func isSyntaxIdentifier(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (index in 0..value.size) {
        let byte = value[index]
        let valid = (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || byte == b'_' || byte == b'-' || (index >
            0 && byte >= b'0' && byte <= b'9')
        if (!valid) {
            return false
        }
    }
    true
}

private func splitLinkTarget(text: String): (String, String) {
    let trimmed = trimAscii(text)
    let quoteIndex = findByte(trimmed, b'"', 0)
    if (quoteIndex < 0) {
        return (trimmed, "")
    }
    let end = findByte(trimmed, b'"', quoteIndex + 1)
    if (end < 0) {
        return (trimmed, "")
    }
    (trimAscii(trimmed[..quoteIndex]), trimmed[quoteIndex + 1..end])
}

private func parseInlineLinkTarget(text: String, start: Int64): ?(Int64, String, String, String, String) {
    var index = skipLinkWhitespace(text, start)
    var destinationRaw = ""
    if (index < text.size && text[index] == b'<') {
        let destinationStart = index + 1
        index = destinationStart
        while (index < text.size && text[index] != b'>') {
            if (text[index] == 10 || text[index] == 13 || text[index] == b'<') {
                return None
            }
            if (text[index] == b'\\' && index + 1 < text.size) {
                index += 2
            } else {
                index = nextRuneOffset(text, index)
            }
        }
        if (index >= text.size) {
            return None
        }
        destinationRaw = text[destinationStart..index]
        index++
    } else {
        let destinationStart = index
        var depth: Int64 = 0
        while (index < text.size) {
            let byte = text[index]
            if (byte == b'\\' && index + 1 < text.size) {
                index += 2
                continue
            }
            if (byte == b'(') {
                depth++;
                if (depth > 32) {
                    return None
                };
                index++;
                continue
            }
            if (byte == b')') {
                if (depth == 0) {
                    break
                }
                depth--;
                index++;
                continue
            }
            if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13) {
                break
            }
            index = nextRuneOffset(text, index)
        }
        if (depth != 0) {
            return None
        }
        destinationRaw = text[destinationStart..index]
    }
    let afterDestination = index
    index = skipLinkWhitespace(text, index)
    var titleRaw = ""
    if (index < text.size && text[index] != b')') {
        if (index == afterDestination) {
            return None
        }
        let opener = text[index]
        let closer: Byte = if (opener == b'"') {
            b'"'
        } else if (opener == b'\'') {
            b'\''
        } else if (opener == b'(') {
            b')'
        } else {
            return None
        }
        let titleStart = index + 1
        index = titleStart
        while (index < text.size && text[index] != closer) {
            if (text[index] == b'\\' && index + 1 < text.size) {
                index += 2
            } else {
                index = nextRuneOffset(text, index)
            }
        }
        if (index >= text.size) {
            return None
        }
        titleRaw = text[titleStart..index]
        index++
        index = skipLinkWhitespace(text, index)
    }
    if (index >= text.size || text[index] != b')') {
        return None
    }
    Some((index, destinationRaw, decodeLinkValue(destinationRaw), titleRaw, decodeLinkValue(titleRaw)))
}

private func skipLinkWhitespace(text: String, start: Int64): Int64 {
    var index = start
    while (index < text.size && (text[index] == b' ' || text[index] == b'\t' || text[index] == 10 || text[index] == 13)) {
        index++
    }
    index
}

private func decodeLinkValue(value: String): String {
    if (!value.contains("\\") && !value.contains("&")) {
        return value
    }
    let unescaped = unescapeBackslashes(value)
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < unescaped.size) {
        if (unescaped[index] == b'&') {
            let end = findByte(unescaped, b';', index + 1)
            if (end > index) {
                let raw = unescaped[index..end + 1]
                let decoded = decodeEntity(raw)
                out.append(decoded)
                index = end + 1
                continue
            }
        }
        let next = nextRuneOffset(unescaped, index)
        out.append(unescaped[index..next])
        index = next
    }
    out.toString()
}

private func mayContainExtendedAutolink(value: String): Bool {
    value.contains("www.") || value.contains("://") || value.contains("@")
}

private func decodeEntity(raw: String): String {
    if (!raw.startsWith("&") || !raw.endsWith(";") || raw.size < 3) {
        return raw
    }
    if (raw.startsWith("&#")) {
        let hex = raw.size > 3 && (raw[2] == b'x' || raw[2] == b'X')
        let start: Int64 = if (hex) {
            3
        } else {
            2
        }
        let digitCount = raw.size - 1 - start
        if ((hex && digitCount > 6) || (!hex && digitCount > 7)) {
            return raw
        }
        let value = parseEntityNumber(raw, start, raw.size - 1, if (hex) {
            16
        } else {
            10
        })
        if (value < 0) {
            return raw
        }
        return entityCodePoint(value)
    }
    if (let Some(value) <- lookupHtml5Entity(raw[1..raw.size - 1])) {
        return value
    }
    raw
}

private func parseEntityNumber(value: String, start: Int64, end: Int64, radix: Int64): Int64 {
    if (start >= end) {
        return -1
    }
    var result: Int64 = 0
    for (index in start..end) {
        let byte = value[index]
        let digit: Int64 = if (byte >= b'0' && byte <= b'9') {
            Int64(byte - b'0')
        } else if (byte >= b'a' && byte <= b'f') {
            Int64(byte - b'a') + 10
        } else if (byte >= b'A' && byte <= b'F') {
            Int64(byte - b'A') + 10
        } else {
            return -1
        }
        if (digit >= radix) {
            return -1
        }
        if (result > (0x110000 - digit) / radix) {
            return 0x110000
        }
        result = result * radix + digit
    }
    result
}

private func entityCodePoint(input: Int64): String {
    var value = input
    if (value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
        value = 0xFFFD
    }
    value = windows1252Replacement(value)
    Rune(UInt32(value)).toString()
}

private func windows1252Replacement(value: Int64): Int64 {
    match (value) {
        case 0x80 => 0x20AC
        case 0x82 => 0x201A
        case 0x83 => 0x0192
        case 0x84 => 0x201E
        case 0x85 => 0x2026
        case 0x86 => 0x2020
        case 0x87 => 0x2021
        case 0x88 => 0x02C6
        case 0x89 => 0x2030
        case 0x8A => 0x0160
        case 0x8B => 0x2039
        case 0x8C => 0x0152
        case 0x8E => 0x017D
        case 0x91 => 0x2018
        case 0x92 => 0x2019
        case 0x93 => 0x201C
        case 0x94 => 0x201D
        case 0x95 => 0x2022
        case 0x96 => 0x2013
        case 0x97 => 0x2014
        case 0x98 => 0x02DC
        case 0x99 => 0x2122
        case 0x9A => 0x0161
        case 0x9B => 0x203A
        case 0x9C => 0x0153
        case 0x9E => 0x017E
        case 0x9F => 0x0178
        case _ => value
    }
}

private func isAsciiPunctuation(byte: Byte): Bool {
    (byte >= 33 && byte <= 47) || (byte >= 58 && byte <= 64) || (byte >= 91 && byte <= 96) || (byte >= 123 && byte <= 126)
}

private func coreInlineSpecialByte(byte: Byte): Bool {
    byte == b'\\' || byte == b'&' || byte == b'`' || byte == b'~' || byte == b'*' || byte == b'_' || byte == b'!' ||
        byte == b'[' || byte == b'<'
}

private func autolinkKind(body: String): Int64 {
    if (body.isEmpty() || body.contains(" ") || body.contains("\t") || body.contains("<") || body.contains("\n") ||
        body.contains("\r")) {
        return 0
    }
    let colon = findByte(body, b':', 0)
    if (colon >= 2 && colon <= 32 && isAsciiLetterByte(body[0])) {
        var valid = true
        for (index in 1..colon) {
            let byte = body[index]
            if (!(isAsciiLetterByte(byte) || (byte >= b'0' && byte <= b'9') || byte == b'+' || byte == b'.' || byte ==
                b'-')) {
                valid = false
                break
            }
        }
        if (valid) {
            return 1
        }
    }
    if (isEmailAutolink(body)) {
        return 2
    }
    0
}

// 1 = www, 2 = URI scheme, 3 = email.
private func extendedAutolinkStart(value: String, index: Int64): Int64 {
    if (index > 0 && isExtendedWordByte(value[index - 1])) {
        return 0
    }
    if (startsAt(value, "www.", index)) {
        return 1
    }
    if (startsAt(value, "http://", index) || startsAt(value, "https://", index) || startsAt(value, "ftp://", index)) {
        return 2
    }
    var end = index
    while (end < value.size && !isExtendedTerminator(value[end])) {
        end++
    }
    if (end > index && isEmailAutolink(trimExtendedEmail(value[index..end]))) {
        return 3
    }
    0
}

private func extendedAutolinkEnd(value: String, start: Int64, kind: Int64): Int64 {
    var end = start
    while (end < value.size && !isExtendedTerminator(value[end])) {
        if (value[end] == b'&') {
            let semicolon = findByte(value, b';', end + 1)
            let equals = findByte(value, b'=', end + 1)
            if (semicolon > end && (equals < 0 || semicolon < equals)) {
                break
            }
        }
        end++
    }
    if (kind == 3) {
        return start + trimExtendedEmail(value[start..end]).size
    }
    while (end > start && (value[end - 1] == b'.' || value[end - 1] == b',' || value[end - 1] == b':' ||
            value[end - 1] == b';' || value[end - 1] == b'!' || value[end - 1] == b'?')) {
        end--
    }
    while (end > start && value[end - 1] == b')' && unmatchedClosingParen(value[start..end])) {
        end--
    }
    end
}

private func trimExtendedEmail(value: String): String {
    var end = value.size
    if (end > 0 && value[end - 1] == b'.') {
        end--
    }
    value[..end]
}

private func isExtendedTerminator(byte: Byte): Bool {
    byte == b' ' || byte == b'\t' || byte == 10 || byte == 13 || byte == b'<'
}

private func isExtendedWordByte(byte: Byte): Bool {
    isAsciiLetterByte(byte) || (byte >= b'0' && byte <= b'9') || byte == b'_'
}

private func unmatchedClosingParen(value: String): Bool {
    var balance: Int64 = 0
    for (byte in value.toArray()) {
        if (byte == b'(') {
            balance++
        } else if (byte == b')') {
            balance--
        }
    }
    balance < 0
}

private func isEmailAutolink(body: String): Bool {
    let at = findByte(body, b'@', 0)
    if (at <= 0 || at + 1 >= body.size || findByte(body, b'@', at + 1) >= 0) {
        return false
    }
    for (index in 0..at) {
        let byte = body[index]
        if (!(isAsciiLetterByte(byte) || (byte >= b'0' && byte <= b'9') || isEmailLocalPunctuationByte(byte))) {
            return false
        }
    }
    var hasDot = false
    for (index in at + 1..body.size) {
        let byte = body[index]
        if (byte == b'.') {
            hasDot = true
        } else if (!(isAsciiLetterByte(byte) || (byte >= b'0' && byte <= b'9') || byte == b'-')) {
            return false
        }
    }
    hasDot && body[at + 1] != b'.' && body[body.size - 1] != b'.' && body[body.size - 1] != b'-'
}

private func isEmailLocalPunctuationByte(byte: Byte): Bool {
    byte == 33 || byte == 35 || byte == 36 || byte == 37 || byte == 38 || byte == 39 || byte == 42 || byte == 43 ||
        byte == 45 || byte == 46 || byte == 47 || byte == 61 || byte == 63 || byte == 94 || byte == 95 || byte == 96 ||
        byte == 123 || byte == 124 || byte == 125 || byte == 126
}

private func isAsciiLetterByte(byte: Byte): Bool {
    (byte >= b'A' && byte <= b'Z') || (byte >= b'a' && byte <= b'z')
}

internal func isInlineHtml(body: String): Bool {
    if (body.startsWith("!--") || body.startsWith("?") || body.startsWith("![CDATA[") || body.startsWith("!")) {
        return true
    }
    var index: Int64 = 0
    let closing = index < body.size && body[index] == b'/'
    if (closing) {
        index++
    }
    if (index >= body.size || !isAsciiLetterByte(body[index])) {
        return false
    }
    while (index < body.size && (isAsciiLetterByte(body[index]) || (body[index] >= b'0' && body[index] <= b'9') ||
            body[index] == b'-')) {
        index++
    }
    if (closing) {
        return trimAscii(body[index..]).isEmpty()
    }
    while (index < body.size) {
        let beforeWhitespace = index
        index = skipInlineHtmlWhitespace(body, index)
        if (index >= body.size) {
            return true
        }
        if (body[index] == b'/') {
            return index + 1 == body.size
        }
        if (index == beforeWhitespace || !isHtmlAttributeStart(body[index])) {
            return false
        }
        index++
        while (index < body.size && isHtmlAttributeContinuation(body[index])) {
            index++
        }
        let afterName = index
        let equalsIndex = skipInlineHtmlWhitespace(body, index)
        if (equalsIndex < body.size && body[equalsIndex] == b'=') {
            index = skipInlineHtmlWhitespace(body, equalsIndex + 1)
            if (index >= body.size) {
                return false
            }
            if (body[index] == b'"' || body[index] == b'\'') {
                let quoteByte = body[index]
                index++
                while (index < body.size && body[index] != quoteByte) {
                    index = nextRuneOffset(body, index)
                }
                if (index >= body.size) {
                    return false
                }
                index++
            } else {
                let valueStart = index
                while (index < body.size && !isInlineHtmlWhitespace(body[index]) && body[index] != b'"' &&
                        body[index] != b'\'' && body[index] != b'=' && body[index] != b'<' && body[index] != b'>' &&
                        body[index] != b'`') {
                    index = nextRuneOffset(body, index)
                }
                if (index == valueStart) {
                    return false
                }
            }
        } else {
            index = afterName
        }
    }
    true
}

private func findInlineHtmlEnd(text: String, start: Int64): Int64 {
    if (startsAt(text, "<!--", start)) {
        if (startsAt(text, "<!-->", start)) {
            return start + 4
        }
        if (startsAt(text, "<!--->", start)) {
            return start + 5
        }
        let found = findString(text, "-->", start + 4)
        return if (found < 0) {
            -1
        } else {
            found + 2
        }
    }
    if (startsAt(text, "<![CDATA[", start)) {
        let found = findString(text, "]]>", start + 9)
        return if (found < 0) {
            -1
        } else {
            found + 2
        }
    }
    if (startsAt(text, "<?", start)) {
        let found = findString(text, "?>", start + 2)
        return if (found < 0) {
            -1
        } else {
            found + 1
        }
    }
    var quoteByte: Byte = 0
    var index = start + 1
    while (index < text.size) {
        if (quoteByte == 0 && (text[index] == b'"' || text[index] == b'\'')) {
            quoteByte = text[index]
        } else if (quoteByte != 0 && text[index] == quoteByte) {
            quoteByte = 0
        } else if (quoteByte == 0 && text[index] == b'>') {
            return index
        }
        index = nextRuneOffset(text, index)
    }
    -1
}

private func isInlineHtmlWhitespace(byte: Byte): Bool {
    byte == b' ' || byte == b'\t' || byte == 10 || byte == 13
}

private func skipInlineHtmlWhitespace(value: String, start: Int64): Int64 {
    var index = start
    while (index < value.size && isInlineHtmlWhitespace(value[index])) {
        index++
    }
    index
}

private func isHtmlAttributeStart(byte: Byte): Bool {
    isAsciiLetterByte(byte) || byte == b'_' || byte == b':'
}

private func isHtmlAttributeContinuation(byte: Byte): Bool {
    isHtmlAttributeStart(byte) || (byte >= b'0' && byte <= b'9') || byte == b'.' || byte == b'-'
}

private func codeMarker(text: String, start: Int64): String {
    var end = start
    while (end < text.size && text[end] == b'`') {
        end++
    }
    text[start..end]
}

private func delimiterRunLength(text: String, start: Int64, marker: Byte): Int64 {
    var length: Int64 = 0
    while (start + length < text.size && text[start + length] == marker) {
        length++
    }
    length
}

private func hasUnclosedCodeDelimiter(value: String): Bool {
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'`') {
            let width = codeMarker(value, index).size
            let close = findExactCodeCloser(value, index, width)
            if (close < 0) {
                return true
            }
            index = close + width
        } else {
            index = nextRuneOffset(value, index)
        }
    }
    false
}

private func findByte(text: String, byte: Byte, start: Int64): Int64 {
    var index = start
    while (index < text.size) {
        if (text[index] == byte) {
            return index
        }
        index++
    }
    -1
}

private func containsByteInRange(text: String, byte: Byte, start: Int64, end: Int64): Bool {
    var index = start
    while (index < end) {
        if (text[index] == byte) {
            return true
        }
        index++
    }
    false
}

private func findClosingBracket(text: String, contentStart: Int64): Int64 {
    var depth: Int64 = 1
    var index = contentStart
    while (index < text.size) {
        if (text[index] == b'\\' && index + 1 < text.size) {
            index += 2
            continue
        }
        if (text[index] == b'`') {
            let width = codeMarker(text, index).size
            let close = findExactCodeCloser(text, index, width)
            if (close >= 0) {
                index = close + width
                continue
            }
        }
        if (text[index] == b'<') {
            let close = findByte(text, b'>', index + 1)
            if (close >= 0) {
                index = close + 1
                continue
            }
        }
        if (text[index] == b'[') {
            depth++;
            index++;
            continue
        }
        if (text[index] == b']') {
            depth--
            if (depth == 0) {
                return index
            }
            index++
            continue
        }
        index = nextRuneOffset(text, index)
    }
    -1
}

private func lastUnescapedClosingBracket(text: String): Int64 {
    var last: Int64 = -1
    var backslashes: Int64 = 0
    var index: Int64 = 0
    while (index < text.size) {
        if (text[index] == b'\\') {
            backslashes++
        } else {
            if (text[index] == b']' && backslashes % 2 == 0) {
                last = index
            }
            backslashes = 0
        }
        index++
    }
    last
}

private func bracketFormsLink(
    text: String,
    labelStart: Int64,
    close: Int64,
    referenceIndex: HashMap<String, ReferenceDefinition>
): Bool {
    if (close + 1 < text.size && (text[close + 1] == b'(' || text[close + 1] == b'[')) {
        return true
    }
    let normalized = normalizeReferenceLabel(text[labelStart..close])
    if (referenceIndex.get(normalized).isSome()) {
        return true
    }
    false
}

private func containsUnescapedOpenBracket(value: String): Bool {
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'\\' && index + 1 < value.size) {
            index += 2
            continue
        }
        if (value[index] == b'[') {
            return true
        }
        index = nextRuneOffset(value, index)
    }
    false
}

private func findString(text: String, needle: String, start: Int64): Int64 {
    var index = start
    while (index + needle.size <= text.size) {
        if (startsAt(text, needle, index)) {
            return index
        }
        index++
    }
    -1
}

private func findMatchingDelimiter(
    text: String,
    opener: Int64,
    width: Int64,
    marker: Byte,
    referenceIndex: HashMap<String, ReferenceDefinition>
): Int64 {
    var depth: Int64 = 1
    var nestedStrong: Int64 = 0
    let openerCanClose = delimiterCanClose(text, opener, width, marker)
    var index = opener + width
    while (index < text.size) {
        if (text[index] == b'`') {
            let run = codeMarker(text, index).size
            let close = findExactCodeCloser(text, index, run)
            if (close >= 0) {
                index = close + run
                continue
            }
        }
        if (text[index] == b'[') {
            let close = findClosingBracket(text, index + 1)
            if (close >= 0 && bracketFormsLink(text, index + 1, close, referenceIndex)) {
                index = close + 1
                continue
            }
            index++
            continue
        }
        if (text[index] == marker) {
            var run: Int64 = 0
            while (index + run < text.size && text[index + run] == marker) {
                run++
            }
            if (run >= width) {
                var candidateIndex = index
                var candidateRun = run
                let canOpen = delimiterCanOpen(text, candidateIndex, width, marker)
                let canClose = delimiterCanClose(text, candidateIndex, width, marker)
                if (width == 1 && candidateRun >= 2) {
                    if (nestedStrong > 0 && canClose) {
                        nestedStrong--
                        candidateIndex += 2
                        candidateRun -= 2
                        if (candidateRun == 0) {
                            index += run
                            continue
                        }
                    } else if (canOpen) {
                        nestedStrong += candidateRun / 2
                        if (candidateRun % 2 == 0) {
                            index += run
                            continue
                        }
                        candidateIndex += candidateRun - 1
                        candidateRun = 1
                    }
                }
                let candidateCanOpen = delimiterCanOpen(text, candidateIndex, width, marker)
                let candidateCanClose = delimiterCanClose(text, candidateIndex, width, marker)
                let ruleOfThreeBlocks = (candidateCanOpen || openerCanClose) && (width + candidateRun) % 3 == 0 && (width %
                    3 != 0 || candidateRun % 3 != 0)
                if (candidateCanClose && !ruleOfThreeBlocks) {
                    depth--
                    if (depth == 0) {
                        return candidateIndex + candidateRun - width
                    }
                }
                if (candidateCanOpen && !candidateCanClose) {
                    depth++
                }
            }
            index += run
        } else {
            index = nextRuneOffset(text, index)
        }
    }
    -1
}

private func findExactCodeCloser(text: String, opener: Int64, width: Int64): Int64 {
    var index = opener + width
    while (index < text.size) {
        if (text[index] == b'`') {
            var run: Int64 = 0
            while (index + run < text.size && text[index + run] == b'`') {
                run++
            }
            if (run == width) {
                return index
            }
            index += run
        } else {
            index = nextRuneOffset(text, index)
        }
    }
    -1
}

private func normalizeCodeLiteral(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == 10 || value[index] == 13) {
            if (value[index] == 13 && index + 1 < value.size && value[index + 1] == 10) {
                index++
            }
            out.append(" ")
            index++
        } else {
            let next = nextRuneOffset(value, index)
            out.append(value[index..next])
            index = next
        }
    }
    let normalized = out.toString()
    if (normalized.size >= 2 && normalized.startsWith(" ") && normalized.endsWith(" ") &&
        !trimAscii(normalized).isEmpty()) {
        normalized[1..normalized.size - 1]
    } else {
        normalized
    }
}

private func findCustomInlineCloser(text: String, openerStart: Int64, bodyStart: Int64, rule: InlineSyntaxRule): Int64 {
    if (rule.allowNesting && rule.opener != rule.closer) {
        var depth: Int64 = 0
        var cursor = bodyStart
        while (cursor <= text.size) {
            let nextOpen = findString(text, rule.opener, cursor)
            let nextClose = findString(text, rule.closer, cursor)
            if (nextClose < 0 || nextClose - openerStart > rule.maximumLookahead) {
                return -1
            }
            let nestedOpener = if (nextOpen >= 0 && nextOpen < nextClose) {
                customInlineOpenerAllowed(text, nextOpen, rule)
            } else {
                false
            }
            if (nestedOpener) {
                depth++
                cursor = nextOpen + rule.opener.size
            } else if (depth > 0) {
                depth--
                cursor = nextClose + rule.closer.size
            } else if (customInlineCloserAllowed(text, openerStart, nextClose + rule.closer.size, rule)) {
                return nextClose
            } else {
                cursor = nextClose + rule.closer.size
            }
        }
        return -1
    }
    var search = bodyStart
    while (search <= text.size) {
        let found = findString(text, rule.closer, search)
        if (found < 0 || found - openerStart > rule.maximumLookahead) {
            return -1
        }
        if (customInlineCloserAllowed(text, openerStart, found + rule.closer.size, rule)) {
            return found
        }
        search = found + rule.closer.size
    }
    -1
}

private func customInlineOpenerAllowed(text: String, start: Int64, rule: InlineSyntaxRule): Bool {
    var metadata = false
    if (let InlineSyntaxKind.MetadataSuffix <- rule.syntaxKind) {
        metadata = true
        if (!hasNonWhitespaceBefore(text, start)) {
            return false
        }
    }
    match (rule.flankingRule) {
        case InlineFlankingRule.Any => true
        case InlineFlankingRule.CommonMark => customLeftFlanking(text, start, start + rule.opener.size)
        case InlineFlankingRule.WordBoundary => metadata || !customWordRune(previousRune(text, start))
    }
}

private func hasNonWhitespaceBefore(text: String, start: Int64): Bool {
    var index = start
    while (index > 0) {
        let previous = previousRune(text, index)
        if (!runeIsWhitespace(previous)) {
            return true
        }
        index--
        while (index > 0 && (text[index] & 0b1100_0000) == 0b1000_0000) {
            index--
        }
    }
    false
}

private func customInlineCloserAllowed(text: String, openerStart: Int64, nextOffset: Int64, rule: InlineSyntaxRule): Bool {
    match (rule.flankingRule) {
        case InlineFlankingRule.Any => true
        case InlineFlankingRule.CommonMark =>
            if (let InlineSyntaxKind.SingleToken <- rule.syntaxKind) {
                customLeftFlanking(text, openerStart, nextOffset) && customRightFlanking(text, openerStart, nextOffset)
            } else {
                customRightFlanking(text, nextOffset - rule.closer.size, nextOffset)
            }
        case InlineFlankingRule.WordBoundary => !customWordRune(nextRune(text, nextOffset))
    }
}

private func customLeftFlanking(text: String, start: Int64, nextOffset: Int64): Bool {
    let previous = previousRune(text, start)
    let next = nextRune(text, nextOffset)
    let previousWhitespace = runeIsWhitespace(previous)
    let nextWhitespace = runeIsWhitespace(next)
    let previousPunctuation = runeIsPunctuationOrSymbol(previous)
    let nextPunctuation = runeIsPunctuationOrSymbol(next)
    !nextWhitespace && (!nextPunctuation || previousWhitespace || previousPunctuation)
}

private func customRightFlanking(text: String, start: Int64, nextOffset: Int64): Bool {
    let previous = previousRune(text, start)
    let next = nextRune(text, nextOffset)
    let previousWhitespace = runeIsWhitespace(previous)
    let nextWhitespace = runeIsWhitespace(next)
    let previousPunctuation = runeIsPunctuationOrSymbol(previous)
    let nextPunctuation = runeIsPunctuationOrSymbol(next)
    !previousWhitespace && (!previousPunctuation || nextWhitespace || nextPunctuation)
}

private func customWordRune(value: ?Rune): Bool {
    match (value) {
        case Some(_) => !runeIsWhitespace(value) && !runeIsPunctuationOrSymbol(value)
        case None => false
    }
}

private func syntaxRuleCost(cost: SyntaxResourceCost, bytes: Int64): Int64 {
    if (cost.perByteCost > 0 && bytes > (Int64.Max - cost.baseCost) / cost.perByteCost) {
        throw MarkdownException(MarkdownErrorCode.BudgetExceeded, "syntax resource cost overflow",
            phase: "extension_parse")
    }
    cost.baseCost + cost.perByteCost * bytes
}

private func delimiterCanOpen(text: String, start: Int64, width: Int64, marker: Byte): Bool {
    let previous = previousRune(text, start)
    let next = nextRune(text, start + width)
    let previousWhitespace = runeIsWhitespace(previous)
    let nextWhitespace = runeIsWhitespace(next)
    let previousPunctuation = runeIsPunctuationOrSymbol(previous)
    let nextPunctuation = runeIsPunctuationOrSymbol(next)
    let leftFlanking = !nextWhitespace && (!nextPunctuation || previousWhitespace || previousPunctuation)
    let rightFlanking = !previousWhitespace && (!previousPunctuation || nextWhitespace || nextPunctuation)
    if (marker == b'_') {
        leftFlanking && (!rightFlanking || previousPunctuation)
    } else {
        leftFlanking
    }
}

private func delimiterCanOpenBytes(bytes: Array<Byte>, start: Int64, width: Int64, marker: Byte): Bool {
    let previous = previousRuneBytes(bytes, start)
    let next = nextRuneBytes(bytes, start + width)
    let previousWhitespace = runeIsWhitespace(previous)
    let nextWhitespace = runeIsWhitespace(next)
    let previousPunctuation = runeIsPunctuationOrSymbol(previous)
    let nextPunctuation = runeIsPunctuationOrSymbol(next)
    let leftFlanking = !nextWhitespace && (!nextPunctuation || previousWhitespace || previousPunctuation)
    let rightFlanking = !previousWhitespace && (!previousPunctuation || nextWhitespace || nextPunctuation)
    if (marker == b'_') {
        leftFlanking && (!rightFlanking || previousPunctuation)
    } else {
        leftFlanking
    }
}

private func delimiterCanClose(text: String, start: Int64, width: Int64, marker: Byte): Bool {
    let previous = previousRune(text, start)
    let next = nextRune(text, start + width)
    let previousWhitespace = runeIsWhitespace(previous)
    let nextWhitespace = runeIsWhitespace(next)
    let previousPunctuation = runeIsPunctuationOrSymbol(previous)
    let nextPunctuation = runeIsPunctuationOrSymbol(next)
    let leftFlanking = !nextWhitespace && (!nextPunctuation || previousWhitespace || previousPunctuation)
    let rightFlanking = !previousWhitespace && (!previousPunctuation || nextWhitespace || nextPunctuation)
    if (marker == b'_') {
        rightFlanking && (!leftFlanking || nextPunctuation)
    } else {
        rightFlanking
    }
}

private func delimiterCanCloseBytes(bytes: Array<Byte>, start: Int64, width: Int64, marker: Byte): Bool {
    let previous = previousRuneBytes(bytes, start)
    let next = nextRuneBytes(bytes, start + width)
    let previousWhitespace = runeIsWhitespace(previous)
    let nextWhitespace = runeIsWhitespace(next)
    let previousPunctuation = runeIsPunctuationOrSymbol(previous)
    let nextPunctuation = runeIsPunctuationOrSymbol(next)
    let leftFlanking = !nextWhitespace && (!nextPunctuation || previousWhitespace || previousPunctuation)
    let rightFlanking = !previousWhitespace && (!previousPunctuation || nextWhitespace || nextPunctuation)
    if (marker == b'_') {
        rightFlanking && (!leftFlanking || nextPunctuation)
    } else {
        rightFlanking
    }
}

private func previousRuneBytes(bytes: Array<Byte>, offset: Int64): ?Rune {
    if (offset <= 0) {
        return None
    }
    var start = offset - 1
    while (start > 0 && (bytes[start] & 0b1100_0000) == 0b1000_0000) {
        start--
    }
    let (rune, _) = Rune.fromUtf8(bytes, start)
    Some(rune)
}

private func nextRuneBytes(bytes: Array<Byte>, offset: Int64): ?Rune {
    if (offset >= bytes.size) {
        return None
    }
    let (rune, _) = Rune.fromUtf8(bytes, offset)
    Some(rune)
}

private func previousRune(text: String, offset: Int64): ?Rune {
    if (offset <= 0) {
        return None
    }
    let bytes = text.toArray()
    var start = offset - 1
    while (start > 0 && (bytes[start] & 0b1100_0000) == 0b1000_0000) {
        start--
    }
    let (rune, _) = Rune.fromUtf8(bytes, start)
    Some(rune)
}

private func nextRune(text: String, offset: Int64): ?Rune {
    if (offset >= text.size) {
        return None
    }
    let (rune, _) = Rune.fromUtf8(text.toArray(), offset)
    Some(rune)
}

private func runeIsWhitespace(value: ?Rune): Bool {
    match (value) {
        case Some(rune) => rune.isWhiteSpace();
        case None => true
    }
}

private func runeIsPunctuationOrSymbol(value: ?Rune): Bool {
    match (value) {
        case Some(rune) => !rune.isWhiteSpace() && !rune.isLetter() && !rune.isNumber()
        case None => false
    }
}

private func startsAt(text: String, needle: String, start: Int64): Bool {
    if (start < 0 || start + needle.size > text.size) {
        return false
    }
    for (index in 0..needle.size) {
        if (text[start + index] != needle[index]) {
            return false
        }
    }
    true
}

private func isEscaped(text: String, index: Int64): Bool {
    var count: Int64 = 0
    var current = index - 1
    while (current >= 0 && text[current] == b'\\') {
        count++;
        current--
    }
    count % 2 == 1
}

private func nextRuneOffset(text: String, offset: Int64): Int64 {
    if (offset >= text.size) {
        return text.size
    }
    let first = text[offset]
    let width: Int64 = if ((first & 0b1000_0000) == 0) {
        1
    } else if ((first & 0b1110_0000) == 0b1100_0000) {
        2
    } else if ((first & 0b1111_0000) == 0b1110_0000) {
        3
    } else if ((first & 0b1111_1000) == 0b1111_0000) {
        4
    } else {
        1
    }
    let end = offset + width
    if (end < text.size) {
        end
    } else {
        text.size
    }
}

private func decodeUtf8Input(bytes: Array<Byte>, policy: Utf8Policy): DecodedInput {
    match (policy) {
        case Utf8Policy.Strict => try {
            let value = String.fromUtf8(bytes)
            return DecodedInput(SourceBuffer(value, bytes), [])
        } catch (_: Exception) {
            throw MarkdownException(MarkdownErrorCode.InvalidEncoding, "invalid UTF-8 input", phase: "input")
        }
        case Utf8Policy.ReplaceInvalid =>
            let decoded = ArrayList<Byte>()
            let mapping = ArrayList<Int64>()
            let diagnostics = ArrayList<Diagnostic>()
            mapping.add(0)
            var index: Int64 = 0
            while (index < bytes.size) {
                let width = validUtf8Width(bytes, index)
                if (width > 0) {
                    for (offset in 0..width) {
                        decoded.add(bytes[index + offset])
                        mapping.add(index + offset + 1)
                    }
                    index += width
                } else {
                    decoded.add(0xEF)
                    mapping.add(index)
                    decoded.add(0xBF)
                    mapping.add(index)
                    decoded.add(0xBD)
                    mapping.add(index + 1)
                    diagnostics.add(
                        Diagnostic(
                            "MD1001_INVALID_UTF8_REPLACED",
                            DiagnosticSeverity.Warning,
                            "invalid UTF-8 byte replaced with U+FFFD",
                            SourceSpan(index, index + 1),
                            fixes: [DiagnosticFix("Replace invalid byte with U+FFFD", SourceSpan(index, index + 1),
                                "\u{FFFD}")]
                        )
                    )
                    index++
                }
            }
            DecodedInput(SourceBuffer(String.fromUtf8(decoded.toArray()), bytes, mapping.toArray()),
                diagnostics.toArray())
    }
}

private func validUtf8Width(bytes: Array<Byte>, index: Int64): Int64 {
    let first = bytes[index]
    if (first <= 0x7F) {
        return 1
    }
    if (first >= 0xC2 && first <= 0xDF) {
        if (index + 1 < bytes.size && isContinuation(bytes[index + 1])) {
            return 2
        }
        return 0
    }
    if (first >= 0xE0 && first <= 0xEF) {
        if (index + 2 >= bytes.size || !isContinuation(bytes[index + 2])) {
            return 0
        }
        let second = bytes[index + 1]
        if (first == 0xE0) {
            return if (second >= 0xA0 && second <= 0xBF) {
                3
            } else {
                0
            }
        }
        if (first == 0xED) {
            return if (second >= 0x80 && second <= 0x9F) {
                3
            } else {
                0
            }
        }
        return if (isContinuation(second)) {
            3
        } else {
            0
        }
    }
    if (first >= 0xF0 && first <= 0xF4) {
        if (index + 3 >= bytes.size || !isContinuation(bytes[index + 2]) || !isContinuation(bytes[index + 3])) {
            return 0
        }
        let second = bytes[index + 1]
        if (first == 0xF0) {
            return if (second >= 0x90 && second <= 0xBF) {
                4
            } else {
                0
            }
        }
        if (first == 0xF4) {
            return if (second >= 0x80 && second <= 0x8F) {
                4
            } else {
                0
            }
        }
        return if (isContinuation(second)) {
            4
        } else {
            0
        }
    }
    0
}

private func isContinuation(byte: Byte): Bool {
    byte >= 0x80 && byte <= 0xBF
}
