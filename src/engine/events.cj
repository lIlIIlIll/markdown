package markdown.engine

import markdown.core.ParserNodeFactory
import markdown.core.{ArenaNodePayload, CancellationToken, CodeBlockKind, DefinitionListPayload, DefinitionListRole, 
    Diagnostic, HardBreakKind, ImmutableArray, LimitExceededException, LineScannerAccelerator, LinkSyntaxKind, 
    ListDelimiter, ListKind, MarkdownErrorCode, MarkdownException, MarkdownProfile, NodeCategory, NodeConstructionBudget, 
    NodeKind, NodeLineage, OperationBudget, ReferenceDefinition, SourceBuffer, SourceSpan, TableAlignment, TaskState, 
    Utf8Policy}
import markdown.extensions.{BlockSyntaxKind, BlockSyntaxRule}
import std.collection.*

private let RAW_BLOCK_INPUT_CANCELLATION_BYTES: Int64 = 1024

/**
 * source event 的语义模式。
 *
 * `ResolvedEventMode` 先建立 reference index；`RawBlockEventMode` 不承诺全局
 * reference resolution，并可通过 session 增量消费。
 */
public enum MarkdownEventMode {
    /** 先建立 reference index 的完整语义模式。 */
    | ResolvedEventMode
    /** 不承诺全局 reference resolution、可增量消费的 raw block 模式。 */
    | RawBlockEventMode
}

/** source event 的生命周期或节点事件类别。 */
public enum MarkdownSourceEventKind {
    /** 文档开始。 */
    | DocumentStart
    /** 文档结束。 */
    | DocumentEnd
    /** block 节点开始。 */
    | BlockStart
    /** block 节点结束。 */
    | BlockEnd
    /** inline 节点开始。 */
    | InlineStart
    /** inline 节点结束。 */
    | InlineEnd
    /** 文本叶子事件。 */
    | Text
}

/** 事件携带的稳定字符串属性。 */
public struct MarkdownEventAttribute {
    /** 属性名称，不能为空。 */
    public let name: String
    /** 属性值。 */
    public let value: String

    /**
     * 创建事件属性。
     * @param name 属性名称，不能为空。
     * @param value 属性值。
     */
    public init(name: String, value: String) {
        if (name.isEmpty()) {
            throw IllegalArgumentException("event attribute name must not be empty")
        }
        this.name = name
        this.value = value
    }
}

/**
 * 不持有 `Document` 或 `NodeRef` 的不可变 source event。
 *
 * `sourceRange` 和 `textSourceRange` 使用半开 UTF-8 byte range；在 raw mode 中
 * `finalSemantics` 为 false。
 */
public class MarkdownSourceEvent {
    /** 事件类别。 */
    public let kind: MarkdownSourceEventKind
    /** 对应的 AST 节点类别；未知时为 `None`。 */
    public let nodeKind: ?NodeKind
    /** 事件覆盖的 source span。 */
    public let sourceRange: ?SourceSpan
    /** 事件文本覆盖的 source span。 */
    public let textSourceRange: ?SourceSpan
    /** 文本事件的语义值。 */
    public let semanticValue: ?String
    /** 稳定字符串属性列表。 */
    public let attributes: ImmutableArray<MarkdownEventAttribute>
    /** 语义是否最终确定；raw mode 中为 `false`。 */
    public let finalSemantics: Bool

    /**
     * 创建 source event。
     * @param kind 事件类别。
     * @param nodeKind 对应的 AST 节点类别。
     * @param sourceRange 事件覆盖的 source span。
     * @param textSourceRange 事件文本覆盖的 source span。
     * @param semanticValue 文本事件的语义值。
     * @param attributes 稳定字符串属性列表。
     * @param finalSemantics 语义是否最终确定。
     */
    public init(kind: MarkdownSourceEventKind, nodeKind!: ?NodeKind = None, sourceRange!: ?SourceSpan = None,
        textSourceRange!: ?SourceSpan = None, semanticValue!: ?String = None,
        attributes!: Array<MarkdownEventAttribute> = [], finalSemantics!: Bool = true) {
        this.kind = kind
        this.nodeKind = nodeKind
        this.sourceRange = sourceRange
        this.textSourceRange = textSourceRange
        this.semanticValue = semanticValue
        this.attributes = ImmutableArray<MarkdownEventAttribute>(attributes)
        this.finalSemantics = finalSemantics
    }
}

/** 按 source 顺序消费事件的 sink；实现可以不保留完整事件序列。 */
public interface MarkdownEventSink {
    /** 处理一个 source event。
     * @param event 按 source 顺序到来的事件。
     */
    func onEvent(event: MarkdownSourceEvent): Unit
}

/** `emitEvents` 完成后的模式、诊断和事件计数。 */
public class EventParseSummary {
    /** 实际使用的解析模式。 */
    public let mode: MarkdownEventMode
    /** 解析诊断。 */
    public let diagnostics: ImmutableArray<Diagnostic>
    /** 发出的事件总数。 */
    public let emittedEvents: Int64

    /**
     * 创建解析摘要。
     * @param mode 实际使用的解析模式。
     * @param diagnostics 解析诊断。
     * @param emittedEvents 发出的事件总数。
     */
    public init(mode: MarkdownEventMode, diagnostics: Array<Diagnostic>, emittedEvents: Int64) {
        this.mode = mode
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
        this.emittedEvents = emittedEvents
    }
}

/** `parseEvents` 收集的事件数组及其诊断。 */
public class EventParseResult {
    /** 实际使用的解析模式。 */
    public let mode: MarkdownEventMode
    /** 按 source 顺序收集的事件数组。 */
    public let events: ImmutableArray<MarkdownSourceEvent>
    /** 解析诊断。 */
    public let diagnostics: ImmutableArray<Diagnostic>

    /**
     * 创建事件解析结果。
     * @param mode 实际使用的解析模式。
     * @param events 按 source 顺序收集的事件数组。
     * @param diagnostics 解析诊断。
     */
    public init(mode: MarkdownEventMode, events: Array<MarkdownSourceEvent>, diagnostics: Array<Diagnostic>) {
        this.mode = mode
        this.events = ImmutableArray<MarkdownSourceEvent>(events)
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
    }
}

/** Internal deterministic observation point for bounded RawBlock input work.
 * Production cancellation remains owned by the session's CancellationToken;
 * this observer only lets same-package tests trigger cancellation at an exact
 * byte checkpoint without relying on scheduler timing. */
protected interface RawBlockScanCheckpointObserver {
    /** 在 raw block 扫描 checkpoint 处回调，用于测试注入取消点。
     * @param phase 当前扫描阶段名称。
     * @param bytesProcessed 已处理的字节数。
     */
    func onRawBlockScanCheckpoint(phase: String, bytesProcessed: Int64): Unit
}

/** Transactional checkpoint for the lexical state advanced by a single raw
 * block feed. A literal limit can be discovered only after a completed line
 * reveals its normalized value; restoring this state keeps a rejected chunk
 * out of both the source buffer and all incremental counters. */
private class RawBlockScanState {
    let pendingSize: Int64
    protected let totalBytes: Int64
    let scanCursor: Int64
    let scanLineStart: Int64
    let lastCompleteLineEnd: Int64
    let currentLineBytes: Int64
    let previousByteWasCarriageReturn: Bool
    let openFenceMarker: ?Byte
    let openFenceLength: Int64
    let openFenceIndent: Int64
    let openFenceLiteralBytes: Int64
    let currentFenceCloserStage: Int64
    let currentFenceCloserMarkerCount: Int64
    let currentFenceCloserLeadingSpaces: Int64
    let openHtmlBlockType: Int64
    let openHtmlLiteralBytes: Int64
    let currentHtmlCandidateType: Int64
    let currentHtmlLineHasNonWhitespace: Bool
    let openIndentedCode: Bool
    let indentedCodeMayStart: Bool
    let openIndentedLiteralBytes: Int64
    let openIndentedHasContent: Bool
    let openIndentedPendingEmptyLines: Int64
    let currentIndentedLineState: Int64
    let currentIndentedContentBytes: Int64
    let openBlockDslRule: ?BlockSyntaxRule
    let openBlockDslDepth: Int64
    let openBlockDslStart: Int64
    let openBlockDslSourceStart: Int64
    let openBlockDslBodyBytes: Int64
    let openBlockDslCurrentLineCharged: Bool
    let openBlockDslCloserMatchLength: Int64
    let openBlockDslCloserInTrailingWhitespace: Bool
    let openBlockDslCloserCandidatePossible: Bool
    let completedBlockDslBodyLine: Bool
    let previousBlockDslBodyLineEndedWithCarriageReturn: Bool
    let previousBlockDslBodyLineEnd: Int64
    let closureCandidate: Bool
    let strongBoundary: Bool
    let previousLineBlank: Bool

    protected init(pendingSize: Int64, totalBytes: Int64, scanCursor: Int64, scanLineStart: Int64,
        lastCompleteLineEnd: Int64, currentLineBytes: Int64, previousByteWasCarriageReturn: Bool,
        openFenceMarker: ?Byte, openFenceLength: Int64, openFenceIndent: Int64, openFenceLiteralBytes: Int64,
        currentFenceCloserStage: Int64, currentFenceCloserMarkerCount: Int64, currentFenceCloserLeadingSpaces: Int64,
        openHtmlBlockType: Int64, openHtmlLiteralBytes: Int64, currentHtmlCandidateType: Int64,
        currentHtmlLineHasNonWhitespace: Bool, openIndentedCode: Bool, indentedCodeMayStart: Bool,
        openIndentedLiteralBytes: Int64, openIndentedHasContent: Bool, openIndentedPendingEmptyLines: Int64,
        currentIndentedLineState: Int64, currentIndentedContentBytes: Int64, openBlockDslRule: ?BlockSyntaxRule,
        openBlockDslDepth: Int64, openBlockDslStart: Int64, openBlockDslSourceStart: Int64,
        openBlockDslBodyBytes: Int64, openBlockDslCurrentLineCharged: Bool, openBlockDslCloserMatchLength: Int64,
        openBlockDslCloserInTrailingWhitespace: Bool, openBlockDslCloserCandidatePossible: Bool,
        completedBlockDslBodyLine: Bool, previousBlockDslBodyLineEndedWithCarriageReturn: Bool,
        previousBlockDslBodyLineEnd: Int64, closureCandidate: Bool, strongBoundary!: Bool = false,
        previousLineBlank!: Bool = false) {
        this.pendingSize = pendingSize
        this.totalBytes = totalBytes
        this.scanCursor = scanCursor
        this.scanLineStart = scanLineStart
        this.lastCompleteLineEnd = lastCompleteLineEnd
        this.currentLineBytes = currentLineBytes
        this.previousByteWasCarriageReturn = previousByteWasCarriageReturn
        this.openFenceMarker = openFenceMarker
        this.openFenceLength = openFenceLength
        this.openFenceIndent = openFenceIndent
        this.openFenceLiteralBytes = openFenceLiteralBytes
        this.currentFenceCloserStage = currentFenceCloserStage
        this.currentFenceCloserMarkerCount = currentFenceCloserMarkerCount
        this.currentFenceCloserLeadingSpaces = currentFenceCloserLeadingSpaces
        this.openHtmlBlockType = openHtmlBlockType
        this.openHtmlLiteralBytes = openHtmlLiteralBytes
        this.currentHtmlCandidateType = currentHtmlCandidateType
        this.currentHtmlLineHasNonWhitespace = currentHtmlLineHasNonWhitespace
        this.openIndentedCode = openIndentedCode
        this.indentedCodeMayStart = indentedCodeMayStart
        this.openIndentedLiteralBytes = openIndentedLiteralBytes
        this.openIndentedHasContent = openIndentedHasContent
        this.openIndentedPendingEmptyLines = openIndentedPendingEmptyLines
        this.currentIndentedLineState = currentIndentedLineState
        this.currentIndentedContentBytes = currentIndentedContentBytes
        this.openBlockDslRule = openBlockDslRule
        this.openBlockDslDepth = openBlockDslDepth
        this.openBlockDslStart = openBlockDslStart
        this.openBlockDslSourceStart = openBlockDslSourceStart
        this.openBlockDslBodyBytes = openBlockDslBodyBytes
        this.openBlockDslCurrentLineCharged = openBlockDslCurrentLineCharged
        this.openBlockDslCloserMatchLength = openBlockDslCloserMatchLength
        this.openBlockDslCloserInTrailingWhitespace = openBlockDslCloserInTrailingWhitespace
        this.openBlockDslCloserCandidatePossible = openBlockDslCloserCandidatePossible
        this.completedBlockDslBodyLine = completedBlockDslBodyLine
        this.previousBlockDslBodyLineEndedWithCarriageReturn = previousBlockDslBodyLineEndedWithCarriageReturn
        this.previousBlockDslBodyLineEnd = previousBlockDslBodyLineEnd
        this.closureCandidate = closureCandidate
        this.strongBoundary = strongBoundary
        this.previousLineBlank = previousLineBlank
    }
}

internal class CollectingMarkdownEventSink <: MarkdownEventSink {
    private let values = ArrayList<MarkdownSourceEvent>()

    /** 将事件追加到内部数组。
     * @param event 到达的事件。
     */
    public func onEvent(event: MarkdownSourceEvent): Unit {
        values.add(event)
    }

    protected func toArray(): Array<MarkdownSourceEvent> {
        values.toArray()
    }
}

internal class CountingForwardEventSink <: MarkdownEventSink {
    private let target: MarkdownEventSink
    protected var count: Int64 = 0

    protected init(target: MarkdownEventSink) {
        this.target = target
    }

    /** 计数并转发事件到目标 sink。
     * @param event 到达的事件。
     */
    public func onEvent(event: MarkdownSourceEvent): Unit {
        count++
        target.onEvent(event)
    }
}

internal struct EventTraversalFrame {
    protected let node: Int64
    protected let exiting: Bool

    protected init(node: Int64, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

internal class ParserEventGroup {
    protected let kind: NodeKind
    protected let span: SourceSpan
    let explicitlyClosed: Bool
    protected let definitionList: Bool
    let htmlBlockType: Int64
    let isIndentedCode: Bool
    protected let fenceMarker: ?Byte
    protected let fenceLength: Int64
    protected let nodeCount: Int64
    protected let events: Array<MarkdownSourceEvent>
    let draft: ?ParsedDraft

    protected init(kind: NodeKind, span: SourceSpan, explicitlyClosed: Bool, htmlBlockType: Int64, isIndentedCode: Bool,
        fenceMarker: ?Byte, fenceLength: Int64, nodeCount: Int64, events: Array<MarkdownSourceEvent>,
        draft!: ?ParsedDraft = None, definitionList!: Bool = false) {
        this.kind = kind
        this.span = span
        this.explicitlyClosed = explicitlyClosed
        this.definitionList = definitionList
        this.htmlBlockType = htmlBlockType
        this.isIndentedCode = isIndentedCode
        this.fenceMarker = fenceMarker
        this.fenceLength = fenceLength
        this.nodeCount = nodeCount
        this.events = events
        this.draft = draft
    }
}

/** Low-level lowering target used by ParserSession. It reads the transient
 * parser arena directly and completes before the parser rolls that block back. */
internal class ParserEventEmitter {
    let captureDrafts: Bool
    private let sink: ?MarkdownEventSink
    private let collectGroups: Bool
    private let sourceOffsetBase: Int64
    private let finalSemantics: Bool
    private let maximumNodes: Int64
    private let groups = ArrayList<ParserEventGroup>()
    private var nodeCount: Int64
    private var eventCount: Int64 = 0

    protected init(sink: ?MarkdownEventSink, collectGroups: Bool, sourceOffsetBase: Int64, finalSemantics: Bool,
        maximumNodes: Int64, initialNodeCount!: Int64 = 0, captureDrafts!: Bool = false) {
        this.sink = sink
        this.collectGroups = collectGroups
        this.sourceOffsetBase = sourceOffsetBase
        this.finalSemantics = finalSemantics
        this.maximumNodes = maximumNodes
        this.nodeCount = initialNodeCount
        this.captureDrafts = captureDrafts
    }

    func emitDraft(nodes: ParserNodeFactory, root: Int64, source: SourceBuffer, profile: MarkdownProfile,
        fingerprint: String, references: Array<ReferenceDefinition>, diagnostics: Array<Diagnostic>,
        budget: OperationBudget, cancellation: CancellationToken): Unit {
        if (!captureDrafts) {
            throw IllegalStateException("draft capture is disabled")
        }
        let record = nodes.eventRecord(root)
        let span = record.span.getOrThrow()
        let stack = ArrayList<Int64>()
        stack.add(root)
        var count: Int64 = 0
        while (!stack.isEmpty()) {
            budget.consumeScan()
            cancellation.throwIfCancelled(phase: "append_capture")
            let current = nodes.eventRecord(stack.remove(at: stack.size - 1))
            count++
            if (count > maximumNodes - nodeCount) {
                throw LimitExceededException("ast_nodes", maximumNodes, nodeCount + count, "append_capture",
                    span: Some(span))
            }
            for (index in 0..current.childCount) {
                stack.add(nodes.eventChildIndex(current.firstChild + index))
            }
        }
        let payload = nodes.eventPayload(root)
        let document = nodes.finishDocument([root], span, profile, fingerprint, references)
        let draft = ParsedDraft(document, source, diagnostics)
        groups.add(
            ParserEventGroup(record.kind, shifted(span), explicitlyClosed(payload), eventHtmlBlockType(payload),
                eventIsIndentedCode(payload), eventFenceMarker(payload), eventFenceLength(payload), count, [],
                draft: Some(draft), definitionList: eventIsDefinitionList(payload)))
        nodeCount += count
    }

    func emitDraftReference(nodes: ParserNodeFactory, reference: ReferenceDefinition, source: SourceBuffer,
        profile: MarkdownProfile, fingerprint: String): Unit {
        if (!captureDrafts) {
            throw IllegalStateException("draft capture is disabled")
        }
        let document = nodes.finishDocument([], reference.sourceSpan, profile, fingerprint, [reference])
        let draft = ParsedDraft(document, source, [])
        let noFence: ?Byte = None
        groups.add(
            ParserEventGroup(NodeKind.DocumentNode, shifted(reference.sourceSpan), false, 0, false, noFence, 0, 0, [],
                draft: Some(draft)))
    }

    func emitTopLevel(nodes: ParserNodeFactory, root: Int64): Unit {
        let record = nodes.eventRecord(root)
        let span = record.span.getOrThrow()
        let before = nodeCount
        if (collectGroups) {
            let blockSink = CollectingMarkdownEventSink()
            emitSubtree(nodes, root, blockSink)
            let events = blockSink.toArray()
            let payload = nodes.eventPayload(root)
            groups.add(
                ParserEventGroup(record.kind, shifted(span), explicitlyClosed(payload), eventHtmlBlockType(payload),
                    eventIsIndentedCode(payload), eventFenceMarker(payload), eventFenceLength(payload),
                    nodeCount - before, events, definitionList: eventIsDefinitionList(payload)))
            eventCount += events.size
        } else {
            let forwarding = CountingForwardEventSink(sink.getOrThrow())
            emitSubtree(nodes, root, forwarding)
            eventCount += forwarding.count
        }
    }

    func collectedGroups(): Array<ParserEventGroup> {
        groups.toArray()
    }

    protected prop emittedEvents: Int64 {
        get() {
            eventCount
        }
    }

    private func emitSubtree(nodes: ParserNodeFactory, root: Int64, target: MarkdownEventSink): Unit {
        let stack = ArrayList<EventTraversalFrame>()
        stack.add(EventTraversalFrame(root, false))
        while (!stack.isEmpty()) {
            let frame = stack.remove(at: stack.size - 1)
            let record = nodes.eventRecord(frame.node)
            let span = record.span.getOrThrow()
            if (frame.exiting) {
                target.onEvent(
                    MarkdownSourceEvent(if (let NodeCategory.Block <- record.category) {
                        MarkdownSourceEventKind.BlockEnd
                    } else {
                        MarkdownSourceEventKind.InlineEnd
                    }, nodeKind: Some(record.kind), sourceRange: Some(shifted(span)), finalSemantics: finalSemantics))
                continue
            }
            nodeCount++
            if (nodeCount > maximumNodes) {
                throw LimitExceededException("ast_nodes", maximumNodes, nodeCount, "event_allocation",
                    span: Some(shifted(span)))
            }
            let payload = nodes.eventPayload(frame.node)
            if (let NodeKind.Text <- record.kind) {
                let text = match (payload) {
                    case ArenaNodePayload.TextValue(_, value, _) => value.text()
                    case ArenaNodePayload.TextSourceValue => nodes.eventSourceText(span)
                    case _ => throw IllegalStateException("Text event is missing text payload")
                }
                target.onEvent(
                    MarkdownSourceEvent(MarkdownSourceEventKind.Text, nodeKind: Some(NodeKind.Text),
                        sourceRange: Some(shifted(span)), textSourceRange: Some(shifted(span)),
                        semanticValue: Some(text), attributes: eventAttributes(payload), finalSemantics: finalSemantics))
                continue
            }
            target.onEvent(
                MarkdownSourceEvent(if (let NodeCategory.Block <- record.category) {
                    MarkdownSourceEventKind.BlockStart
                } else {
                    MarkdownSourceEventKind.InlineStart
                }, nodeKind: Some(record.kind), sourceRange: Some(shifted(span)), attributes: eventAttributes(payload),
                    finalSemantics: finalSemantics))
            stack.add(EventTraversalFrame(frame.node, true))
            var childOffset = record.childCount - 1
            while (childOffset >= 0) {
                stack.add(EventTraversalFrame(nodes.eventChildIndex(record.firstChild + childOffset), false))
                childOffset--
            }
            if (record.childCount == 0) {
                if (let Some(value) <- literalSemanticValue(payload)) {
                    target.onEvent(
                        MarkdownSourceEvent(MarkdownSourceEventKind.Text, nodeKind: Some(NodeKind.Text),
                            sourceRange: Some(shifted(span)), textSourceRange: Some(shifted(span)),
                            semanticValue: Some(value), attributes: [MarkdownEventAttribute("role", "literal")],
                            finalSemantics: finalSemantics))
                }
            }
        }
    }

    private func shifted(span: SourceSpan): SourceSpan {
        SourceSpan(span.startByte + sourceOffsetBase, span.endByte + sourceOffsetBase)
    }
}

extend MarkdownEngine {
    /** 收集 source events；需要降低事件数组保留时请使用 `emitEvents()`。
     * @param source 待解析的 Markdown 文本。
     * @param mode 事件语义模式。
     * @param cancellation 协作式取消信号。
     * @param budget 单次解析的操作预算。
     * @return 收集的事件数组与诊断。
     * @throws LimitExceededException 输入超过上限时。
     * @throws MarkdownException 取消或预算耗尽时。
     */
    public func parseEvents(source: String, mode!: MarkdownEventMode = MarkdownEventMode.ResolvedEventMode,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): EventParseResult {
        let sink = CollectingMarkdownEventSink()
        let summary = emitEvents(source, sink, mode: mode, cancellation: cancellation, budget: budget)
        EventParseResult(mode, sink.toArray(), summary.diagnostics.toArray())
    }

    /** 直接向 sink 发出 transient parser block 的事件，不构造完整 AST。
     * @param source 待解析的 Markdown 文本。
     * @param sink 事件接收 sink。
     * @param mode 事件语义模式。
     * @param cancellation 协作式取消信号。
     * @param budget 单次解析的操作预算。
     * @return 模式、诊断和事件计数摘要。
     * @throws LimitExceededException 输入超过上限时。
     * @throws MarkdownException 取消、预算耗尽或 dialect 含 document processors 时。
     */
    public func emitEvents(source: String, sink: MarkdownEventSink,
        mode!: MarkdownEventMode = MarkdownEventMode.ResolvedEventMode,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): EventParseSummary {
        cancellation.throwIfCancelled(phase: "input")
        if (source.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, source.size, "input")
        }
        if (dialect.requiresFullAst()) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure,
                "document-wide processors and binding require the full AST execution path", phase: "event_preflight")
        }
        let finalSemantics = if (let MarkdownEventMode.ResolvedEventMode <- mode) {
            true
        } else {
            false
        }
        let fullSpan = SourceSpan(0, source.size)
        sink.onEvent(
            MarkdownSourceEvent(MarkdownSourceEventKind.DocumentStart, nodeKind: Some(NodeKind.DocumentNode),
                sourceRange: Some(fullSpan), finalSemantics: finalSemantics))
        let emitter = ParserEventEmitter(Some(sink), false, 0, finalSemantics, limits.maximumAstNodes)
        let noAccelerator: ?LineScannerAccelerator = None
        let diagnostics = ParserSession(profile, limits, cancellation, budget, SourceBuffer(source), dialect,
            noAccelerator, eventEmitter: Some(emitter)).parseEvents([], finalSemantics)
        sink.onEvent(
            MarkdownSourceEvent(MarkdownSourceEventKind.DocumentEnd, nodeKind: Some(NodeKind.DocumentNode),
                sourceRange: Some(fullSpan), finalSemantics: finalSemantics))
        EventParseSummary(mode, diagnostics, emitter.emittedEvents + 2)
    }

    /**
     * 创建真正增量的 raw-block session。
     *
     * 后续输入证明 block 已闭合时，`feed` 可以返回该 block 的事件；`finish` 发出
     * 最后的缓冲 block 和 `DocumentEnd`。
     * @param utf8Policy 输入解码策略。
     * @param cancellation 协作式取消信号。
     * @param budget 会话操作预算。
     * @return 新的 raw-block 事件 session。
     */
    public func newRawBlockEventSession(utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): RawBlockEventSession {
        RawBlockEventSession(this, utf8Policy, cancellation, budget)
    }
}

/**
 * 真正增量的 raw-block 事件 session；`feed` 返回已证明闭合 block 的事件，
 * `finish` 发出剩余缓冲 block 和 `DocumentEnd`。
 */
public class RawBlockEventSession {
    private let engine: MarkdownEngine
    private let utf8Policy: Utf8Policy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let scanCheckpointObserver: ?RawBlockScanCheckpointObserver
    private let draftLineage: ?NodeLineage
    private var capturedDrafts = ArrayList<CapturedDraft>()
    private var pending = ArrayList<Byte>()
    private let constructionBudget: ?NodeConstructionBudget
    private var pendingStart: Int64 = 0
    private var sourceOffset: Int64 = 0
    private var totalBytes: Int64 = 0
    private var emittedNodes: Int64 = 0
    // These cursors describe the current pending buffer. feed() advances them
    // over only the newly appended bytes; an unfinished block therefore does
    // not cause the complete buffered prefix to be copied and rescanned.
    private var scanCursor: Int64 = 0
    private var scanLineStart: Int64 = 0
    private var lastCompleteLineEnd: Int64 = 0
    private var currentLineBytes: Int64 = 0
    private var previousByteWasCarriageReturn = false
    // A lexical fence state suppresses generic block-boundary probes inside
    // fenced code. Without it, candidate-looking body lines (for example `#`
    // or `---`) repeatedly parse and copy the complete growing tail.
    private var openFenceMarker: ?Byte = None
    private var openFenceLength: Int64 = 0
    private var openFenceIndent: Int64 = 0
    private var openFenceLiteralBytes: Int64 = 0
    // 0 = leading spaces, 1 = marker run, 2 = trailing whitespace,
    // 3 = proven body line. This keeps closer recognition linear while an
    // unfinished line is split across arbitrarily small feed() calls.
    private var currentFenceCloserStage: Int64 = 0
    private var currentFenceCloserMarkerCount: Int64 = 0
    private var currentFenceCloserLeadingSpaces: Int64 = 0
    // CommonMark HTML block types 1-5 have explicit terminators. Track them
    // lexically so blank body lines do not request a semantic parse of the
    // complete growing prefix. Types 6-7 end at the first blank line.
    private var openHtmlBlockType: Int64 = 0
    private var openHtmlLiteralBytes: Int64 = 0
    // HTML start recognized before its first line ending. Keeping the type
    // avoids rescanning a growing tag on every bytewise feed.
    private var currentHtmlCandidateType: Int64 = 0
    private var currentHtmlLineHasNonWhitespace = false
    // Indented code remains open across blank and further indented lines. The
    // state is entered only at a proven top-level boundary or synchronized
    // from a semantic parse, avoiding a false positive for lazy paragraph or
    // list continuation lines.
    private var openIndentedCode = false
    private var indentedCodeMayStart = true
    private var openIndentedLiteralBytes: Int64 = 0
    private var openIndentedHasContent = false
    private var openIndentedPendingEmptyLines: Int64 = 0
    // 0 = undecided/blank, 1 = normalized indented content, 2 = not an
    // indented-code line. Content bytes exclude the stripped four columns.
    private var currentIndentedLineState: Int64 = 0
    private var currentIndentedContentBytes: Int64 = 0
    // A block DSL rule only shadows built-in Markdown on a line whose trimmed
    // bytes match that rule's opener. Keep the possible rule open until its
    // lexical closer so unrelated DSL registrations do not disable the fence,
    // HTML, and indented-code states for the entire session.
    private var openBlockDslRule: ?BlockSyntaxRule = None
    private var openBlockDslDepth: Int64 = 0
    private var openBlockDslStart: Int64 = -1
    private var openBlockDslSourceStart: Int64 = -1
    private var openBlockDslBodyBytes: Int64 = 0
    private var openBlockDslCurrentLineCharged = false
    // Incremental matcher for trimAscii(currentLine) == rule.closer. Keeping
    // the matched prefix and trailing-whitespace phase avoids rescanning a
    // possible closer from its first byte after every fine-grained feed.
    private var openBlockDslCloserMatchLength: Int64 = 0
    private var openBlockDslCloserInTrailingWhitespace = false
    private var openBlockDslCloserCandidatePossible = true
    private var completedBlockDslBodyLine = false
    private var previousBlockDslBodyLineEndedWithCarriageReturn = false
    private var previousBlockDslBodyLineEnd: Int64 = -1
    private var closureCandidate = false
    private var strongBoundaryCandidate = false
    private var previousRawLineBlank = false
    private var lastSemanticParseLength: Int64 = 0
    private var retainedTailKind: ?NodeKind = None
    private var retainedDefinitionList = false
    private var started = false
    private var finished = false

    protected init(engine: MarkdownEngine, utf8Policy: Utf8Policy, cancellation: CancellationToken,
        budget: OperationBudget, scanCheckpointObserver!: ?RawBlockScanCheckpointObserver = None,
        draftLineage!: ?NodeLineage = None, constructionBudget!: ?NodeConstructionBudget = None) {
        if (draftLineage.isNone() && engine.dialect.requiresFullAst()) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure,
                "document-wide processors and binding require the full AST execution path", phase: "event_preflight")
        }
        this.engine = engine
        this.utf8Policy = utf8Policy
        this.cancellation = cancellation
        this.budget = budget
        this.scanCheckpointObserver = scanCheckpointObserver
        this.draftLineage = draftLineage
        this.constructionBudget = constructionBudget
    }

    internal func abandonDrafts(): Unit {
        if (draftLineage.isNone()) {
            throw IllegalStateException("only internal drafts can be abandoned")
        }
        finished = true
        pending = ArrayList<Byte>()
        pendingStart = 0
        capturedDrafts.clear()
    }

    internal func pendingByteCount(): Int64 {
        pending.size - pendingStart
    }

    internal func takeDrafts(): Array<CapturedDraft> {
        let result = capturedDrafts.toArray()
        capturedDrafts = ArrayList<CapturedDraft>()
        result
    }

    /** 追加 String chunk，并返回本次已证明闭合的 raw-block events。
     * @param chunk 要追加的文本块。
     * @return 本次已证明闭合 block 的事件数组。
     * @throws IllegalStateException session 已 finish 后调用时。
     * @throws LimitExceededException 输入总量超过上限时。
     * @throws MarkdownException 取消时。
     */
    public func feed(chunk: String): Array<MarkdownSourceEvent> {
        prepareFeed(chunk.size)
        // Lifecycle, cancellation, and input-limit failures must occur before
        // materializing a second copy of a potentially large String.
        acceptPreparedChunk(chunk.toArray())
    }

    /** 追加 UTF-8 byte chunk，并返回可安全发出的 raw-block events。
     * @param chunk 要追加的字节块。
     * @return 本次已证明闭合 block 的事件数组。
     * @throws IllegalStateException session 已 finish 后调用时。
     * @throws LimitExceededException 输入总量超过上限时。
     * @throws MarkdownException 取消时。
     */
    public func feed(chunk: Array<Byte>): Array<MarkdownSourceEvent> {
        acceptPreparedChunk(chunk)
    }

    private func prepareFeed(chunkBytes: Int64): Unit {
        ensureOpen()
        cancellation.throwIfCancelled(phase: "input")
        let maximum = engine.limits.maximumInputBytes
        if (chunkBytes > maximum - totalBytes) {
            let observed = if (chunkBytes > Int64.Max - totalBytes) {
                Int64.Max
            } else {
                totalBytes + chunkBytes
            }
            throw LimitExceededException("input_bytes", maximum, observed, "input")
        }
    }

    private func acceptPreparedChunk(chunk: Array<Byte>): Array<MarkdownSourceEvent> {
        // String conversion can be substantial and cancellation may race with
        // it, so repeat all state checks before touching session buffers.
        prepareFeed(chunk.size)
        validateAppendedLineBytes(chunk)
        // The incremental closure probe is real source scanning work. Charge
        // it once per new byte so a fine-grained producer cannot bypass the
        // operation budget or turn an unmetered copy loop into a CPU sink.
        budget.consumeScan(steps: chunk.size)
        cancellation.throwIfCancelled(phase: "input")
        let scanState = checkpointRawBlockScan()
        pending.add(all: chunk)
        totalBytes += chunk.size
        try {
            scanAppendedBytes()
        } catch (error: LimitExceededException) {
            if (error.limitKind == "literal_bytes") {
                rollbackRawBlockScan(scanState)
            }
            throw error
        }
        cancellation.throwIfCancelled(phase: "input")
        drain(false)
    }

    private func checkpointRawBlockScan(): RawBlockScanState {
        RawBlockScanState(pending.size, totalBytes, scanCursor, scanLineStart, lastCompleteLineEnd, currentLineBytes,
            previousByteWasCarriageReturn, openFenceMarker, openFenceLength, openFenceIndent, openFenceLiteralBytes,
            currentFenceCloserStage, currentFenceCloserMarkerCount, currentFenceCloserLeadingSpaces, openHtmlBlockType,
            openHtmlLiteralBytes, currentHtmlCandidateType, currentHtmlLineHasNonWhitespace, openIndentedCode,
            indentedCodeMayStart, openIndentedLiteralBytes, openIndentedHasContent, openIndentedPendingEmptyLines,
            currentIndentedLineState, currentIndentedContentBytes, openBlockDslRule, openBlockDslDepth,
            openBlockDslStart, openBlockDslSourceStart, openBlockDslBodyBytes, openBlockDslCurrentLineCharged,
            openBlockDslCloserMatchLength, openBlockDslCloserInTrailingWhitespace, openBlockDslCloserCandidatePossible,
            completedBlockDslBodyLine, previousBlockDslBodyLineEndedWithCarriageReturn, previousBlockDslBodyLineEnd,
            closureCandidate, strongBoundary: strongBoundaryCandidate, previousLineBlank: previousRawLineBlank)
    }

    private func rollbackRawBlockScan(state: RawBlockScanState): Unit {
        while (pending.size > state.pendingSize) {
            pending.remove(at: pending.size - 1)
        }
        totalBytes = state.totalBytes
        scanCursor = state.scanCursor
        scanLineStart = state.scanLineStart
        lastCompleteLineEnd = state.lastCompleteLineEnd
        currentLineBytes = state.currentLineBytes
        previousByteWasCarriageReturn = state.previousByteWasCarriageReturn
        openFenceMarker = state.openFenceMarker
        openFenceLength = state.openFenceLength
        openFenceIndent = state.openFenceIndent
        openFenceLiteralBytes = state.openFenceLiteralBytes
        currentFenceCloserStage = state.currentFenceCloserStage
        currentFenceCloserMarkerCount = state.currentFenceCloserMarkerCount
        currentFenceCloserLeadingSpaces = state.currentFenceCloserLeadingSpaces
        openHtmlBlockType = state.openHtmlBlockType
        openHtmlLiteralBytes = state.openHtmlLiteralBytes
        currentHtmlCandidateType = state.currentHtmlCandidateType
        currentHtmlLineHasNonWhitespace = state.currentHtmlLineHasNonWhitespace
        openIndentedCode = state.openIndentedCode
        indentedCodeMayStart = state.indentedCodeMayStart
        openIndentedLiteralBytes = state.openIndentedLiteralBytes
        openIndentedHasContent = state.openIndentedHasContent
        openIndentedPendingEmptyLines = state.openIndentedPendingEmptyLines
        currentIndentedLineState = state.currentIndentedLineState
        currentIndentedContentBytes = state.currentIndentedContentBytes
        openBlockDslRule = state.openBlockDslRule
        openBlockDslDepth = state.openBlockDslDepth
        openBlockDslStart = state.openBlockDslStart
        openBlockDslSourceStart = state.openBlockDslSourceStart
        openBlockDslBodyBytes = state.openBlockDslBodyBytes
        openBlockDslCurrentLineCharged = state.openBlockDslCurrentLineCharged
        openBlockDslCloserMatchLength = state.openBlockDslCloserMatchLength
        openBlockDslCloserInTrailingWhitespace = state.openBlockDslCloserInTrailingWhitespace
        openBlockDslCloserCandidatePossible = state.openBlockDslCloserCandidatePossible
        completedBlockDslBodyLine = state.completedBlockDslBodyLine
        previousBlockDslBodyLineEndedWithCarriageReturn = state.previousBlockDslBodyLineEndedWithCarriageReturn
        previousBlockDslBodyLineEnd = state.previousBlockDslBodyLineEnd
        closureCandidate = state.closureCandidate
        strongBoundaryCandidate = state.strongBoundary
        previousRawLineBlank = state.previousLineBlank
    }

    /**
     * 结束 session，发出剩余 block、DocumentEnd，并禁止后续 feed。
     * @return 剩余 block 事件和 `DocumentEnd`。
     * @throws IllegalStateException session 已 finish 后调用时。
     * @throws MarkdownException 取消时。
     */
    public func finish(): Array<MarkdownSourceEvent> {
        ensureOpen()
        cancellation.throwIfCancelled(phase: "input")
        finished = true
        let out = ArrayList<MarkdownSourceEvent>()
        out.add(all: drain(true))
        if (!started) {
            out.add(documentStart())
            started = true
        }
        out.add(
            MarkdownSourceEvent(MarkdownSourceEventKind.DocumentEnd, nodeKind: Some(NodeKind.DocumentNode),
                sourceRange: Some(SourceSpan(0, totalBytes)), finalSemantics: false))
        out.toArray()
    }

    private func drain(finishing: Bool): Array<MarkdownSourceEvent> {
        cancellation.throwIfCancelled(phase: "input")
        let out = ArrayList<MarkdownSourceEvent>()
        if (!started) {
            out.add(documentStart())
            started = true
        }
        var parseEnd = if (finishing) {
            pending.size - pendingStart
        } else {
            lastCompleteLineEnd - pendingStart
        }
        if (!finishing && openBlockDslStart >= pendingStart) {
            parseEnd = min(parseEnd, openBlockDslStart - pendingStart)
        }
        let parseLength = parseEnd
        if (parseLength <= 0) {
            return out.toArray()
        }
        if (!finishing && !closureCandidate) {
            return out.toArray()
        }
        // Ambiguous container tails can contain arbitrarily many blank lines.
        // Retry at geometric growth unless a new source boundary can close the
        // retained root. The total replayed prefix length is then linear.
        if (!finishing && !strongBoundaryCandidate && lastSemanticParseLength > 0 &&
            parseLength - lastSemanticParseLength < lastSemanticParseLength) {
            return out.toArray()
        }
        // Materialize only when a completed-line probe has found a possible
        // block boundary (or once at finish). Ordinary fine-grained chunks do
        // not allocate an ever-growing copy of pending.
        cancellation.throwIfCancelled(phase: "input")
        let bytes = pending.toArray()
        let parseBytes = bytes[pendingStart..pendingStart + parseLength]
        let decoded = decodeUtf8Input(parseBytes, utf8Policy)
        let noSink: ?MarkdownEventSink = None
        let emitter = ParserEventEmitter(noSink, true, sourceOffset, false, engine.limits.maximumAstNodes,
            initialNodeCount: emittedNodes, captureDrafts: draftLineage.isSome())
        let noAccelerator: ?LineScannerAccelerator = None
        try {
            let _ = ParserSession(engine.profile, engine.limits, cancellation, budget, decoded.source, engine.dialect,
                noAccelerator, eventEmitter: Some(emitter), documentOffset: sourceOffset, lineage: draftLineage,
                deferReferenceInlines: draftLineage.isSome(), constructionBudget: constructionBudget).parseEvents(
                decoded.diagnostics, draftLineage.isSome())
        } catch (error: MarkdownException) {
            if (draftLineage.isSome()) {
                throw shiftAppendException(error, sourceOffset)
            }
            throw error
        }
        let groups = emitter.collectedGroups()
        var emitCount = if (finishing) {
            groups.size
        } else if (groups.isEmpty()) {
            0
        } else {
            groups.size - 1
        }
        if (!finishing && !groups.isEmpty()) {
            let last = groups[groups.size - 1]
            let localEnd = last.span.endByte - sourceOffset
            if (rawTailCloses(last, parseBytes, localEnd)) {
                emitCount = groups.size
            }
        }
        if (!finishing && !groups.isEmpty() && engine.dialect.parserOptions.extensionsEnabled &&
            engine.dialect.parserHotPlan.definitionListRule.isSome()) {
            let last = groups[groups.size - 1]
            if (let NodeKind.Paragraph <- last.kind) {
                let after = last.span.endByte - sourceOffset
                let canBecomeTerm = rawBoundedLineBreaks(parseBytes, after, parseBytes.size) < 3
                if (canBecomeTerm) {
                    emitCount = min(emitCount, groups.size - 1)
                    if (groups.size > 1 && groups[groups.size - 2].definitionList) {
                        let previous = groups[groups.size - 2]
                        if (rawBoundedLineBreaks(parseBytes, previous.span.endByte - sourceOffset,
                            last.span.startByte - sourceOffset) < 3) {
                            emitCount = min(emitCount, groups.size - 2)
                        }
                    }
                }
            }
        }
        for (index in 0..emitCount) {
            out.add(all: groups[index].events)
            if (let Some(draft) <- groups[index].draft) {
                capturedDrafts.add(CapturedDraft(draft, sourceOffset, groups[index].span))
            }
            emittedNodes += groups[index].nodeCount
        }
        let discard = if (finishing || emitCount == groups.size) {
            parseLength
        } else if (emitCount > 0) {
            groups[emitCount].span.startByte - sourceOffset
        } else {
            0
        }
        if (discard > 0) {
            sourceOffset += discard
            discardPendingPrefix(discard)
        }
        if (!finishing && emitCount < groups.size) {
            lastSemanticParseLength = parseLength - discard
            retainedTailKind = Some(groups[emitCount].kind)
            retainedDefinitionList = groups[emitCount].definitionList
            synchronizeRetainedTail(groups[emitCount])
        } else {
            lastSemanticParseLength = 0
            retainedTailKind = None
            retainedDefinitionList = false
        }
        if (!finishing) {
            // Every candidate through scanCursor participated in the parse.
            // If it did not close the tail, reparsing that same prefix on the
            // next feed cannot change the answer; wait for a new candidate.
            closureCandidate = false
            strongBoundaryCandidate = false
        }
        out.toArray()
    }

    private func rawBoundedLineBreaks(bytes: Array<Byte>, start: Int64, end: Int64): Int64 {
        var index = start
        var count: Int64 = 0
        while (index < end && count < 3) {
            budget.consumeScan()
            if ((index - start) % 1024 == 0) {
                cancellation.throwIfCancelled(phase: "input")
            }
            if (bytes[index] == b'\r') {
                count++
                if (index + 1 < end && bytes[index + 1] == b'\n') {
                    index++
                }
            } else if (bytes[index] == b'\n') {
                count++
            }
            index++
        }
        count
    }

    private func validateAppendedLineBytes(chunk: Array<Byte>): Unit {
        cancellation.throwIfCancelled(phase: "input")
        var lineBytes = currentLineBytes
        var lineStart = totalBytes - currentLineBytes
        var index: Int64 = 0
        var workSinceCancellation: Int64 = 0
        while (index < chunk.size) {
            let byte = chunk[index]
            if (byte == b'\r' || byte == b'\n') {
                lineBytes = 0
                lineStart = totalBytes + index + 1
            } else {
                lineBytes++
                if (lineBytes > engine.limits.maximumLineBytes) {
                    throw LimitExceededException("line_bytes", engine.limits.maximumLineBytes, lineBytes, "input",
                        span: Some(SourceSpan(lineStart, totalBytes + index + 1)))
                }
            }
            index++
            workSinceCancellation++
            if (workSinceCancellation >= RAW_BLOCK_INPUT_CANCELLATION_BYTES) {
                observeScanCheckpoint("line_validation", index)
                workSinceCancellation = 0
            }
        }
        cancellation.throwIfCancelled(phase: "input")
    }

    private func scanAppendedBytes(): Unit {
        cancellation.throwIfCancelled(phase: "input")
        var processed: Int64 = 0
        var workSinceCancellation: Int64 = 0
        while (scanCursor < pending.size) {
            let byte = pending[scanCursor]
            if (previousByteWasCarriageReturn && byte != b'\n') {
                previousBlockDslBodyLineEndedWithCarriageReturn = false
            }
            if (byte == b'\r') {
                previousBlockDslBodyLineEndedWithCarriageReturn = false
                if (observeCompletedRawLine(scanLineStart, scanCursor)) {
                    closureCandidate = true
                }
                previousBlockDslBodyLineEndedWithCarriageReturn = completedBlockDslBodyLine
                lastCompleteLineEnd = scanCursor + 1
                scanLineStart = scanCursor + 1
                currentLineBytes = 0
                resetCurrentLiteralLineState()
                previousByteWasCarriageReturn = true
            } else if (byte == b'\n') {
                if (previousByteWasCarriageReturn) {
                    if (previousBlockDslBodyLineEndedWithCarriageReturn) {
                        consumeOpenBlockDslBodyBytes(1, previousBlockDslBodyLineEnd)
                    }
                } else {
                    if (observeCompletedRawLine(scanLineStart, scanCursor)) {
                        closureCandidate = true
                    }
                }
                previousBlockDslBodyLineEndedWithCarriageReturn = false
                lastCompleteLineEnd = scanCursor + 1
                scanLineStart = scanCursor + 1
                currentLineBytes = 0
                resetCurrentLiteralLineState()
                previousByteWasCarriageReturn = false
            } else {
                previousByteWasCarriageReturn = false
                observeOpenBlockDslBodyByte(scanLineStart, scanCursor)
                currentLineBytes++
                observeUnfinishedLiteralByte(byte)
            }
            scanCursor++
            processed++
            workSinceCancellation++
            if (workSinceCancellation >= RAW_BLOCK_INPUT_CANCELLATION_BYTES) {
                observeScanCheckpoint("append_scan", processed)
                workSinceCancellation = 0
            }
        }
        cancellation.throwIfCancelled(phase: "input")
    }

    /** Enforces literal limits against the normalized value represented by an
     * unfinished source line. Completed-line accounting alone is insufficient:
     * a producer may retain a very large final line forever without calling
     * finish(). This method advances only compact lexical state, so bytewise
     * feeds remain linear and fail at the same semantic byte as a whole feed. */
    private func observeUnfinishedLiteralByte(byte: Byte): Unit {
        match (openFenceMarker) {
            case Some(marker) =>
                observeFenceCloserByte(byte, marker)
                if (currentFenceCloserStage == 3) {
                    let content = rawFencedLiteralContentBytes(pending, scanLineStart, scanCursor + 1, openFenceIndent)
                    ensureRawLiteralObserved(openFenceLiteralBytes + content)
                }
                return
            case None => ()
        }

        if (openHtmlBlockType > 0) {
            let lineBytes = scanCursor + 1 - scanLineStart
            if (openHtmlBlockType > 5 && lineBytes > 0) {
                if (!currentHtmlLineHasNonWhitespace) {
                    if (byte == b' ' || byte == b'\t') {
                        // A whitespace-only line terminates type 6/7 and is
                        // not part of the literal. Defer charging until a
                        // non-whitespace byte proves this is a body line.
                        return
                    }
                    currentHtmlLineHasNonWhitespace = true
                }
                // parseHtmlBlock appends the normalized separator before the
                // next line. Preserve that append order so observedValue is
                // independent of feed partitioning when the separator itself
                // is the first byte over budget.
                ensureRawLiteralObserved(openHtmlLiteralBytes + 1)
                ensureRawLiteralObserved(openHtmlLiteralBytes + 1 + lineBytes)
            } else {
                ensureRawLiteralObserved(openHtmlLiteralBytes + lineBytes)
            }
            return
        }

        if (openIndentedCode) {
            observeCurrentIndentedByte(byte)
            if (currentIndentedLineState == 1) {
                let separators = if (openIndentedHasContent) {
                    openIndentedPendingEmptyLines + 1
                } else {
                    0
                }
                ensureRawLiteralObserved(openIndentedLiteralBytes + separators + currentIndentedContentBytes)
                return
            }
            if (currentIndentedLineState == 2) {
                observeCurrentHtmlCandidate(byte, true)
            }
            return
        }

        observeCurrentHtmlCandidate(byte, indentedCodeMayStart)
        if (currentHtmlCandidateType > 0) {
            ensureRawLiteralObserved(scanCursor + 1 - scanLineStart)
            return
        }

        if (indentedCodeMayStart) {
            observeCurrentIndentedByte(byte)
            if (currentIndentedLineState == 1) {
                ensureRawLiteralObserved(currentIndentedContentBytes)
            }
        }
    }

    private func observeCurrentHtmlCandidate(byte: Byte, atBlockBoundary: Bool): Unit {
        if (currentHtmlCandidateType > 0) {
            ensureRawLiteralObserved(scanCursor + 1 - scanLineStart)
            return
        }
        let lineBytes = scanCursor + 1 - scanLineStart
        // Types 1-6 are recognized from short fixed prefixes. A type-7 tag
        // can have an arbitrarily long attribute list, but becomes valid only
        // at `>`, so probing at that byte avoids quadratic prefix rescans.
        if (lineBytes > 16 && byte != b'>') {
            return
        }
        let candidate = rawHtmlBlockType(pending, scanLineStart, scanCursor + 1)
        if (candidate > 0 && (candidate != 7 || atBlockBoundary)) {
            currentHtmlCandidateType = candidate
            ensureRawLiteralObserved(lineBytes)
        }
    }

    private func observeCurrentIndentedByte(byte: Byte): Unit {
        if (currentIndentedLineState == 1) {
            currentIndentedContentBytes++
            return
        }
        if (currentIndentedLineState == 2 || byte == b' ' || byte == b'\t') {
            return
        }
        if (rawLineIsIndentedCode(pending, scanLineStart, scanCursor + 1)) {
            currentIndentedLineState = 1
            currentIndentedContentBytes = rawIndentedLiteralContentBytes(pending, scanLineStart, scanCursor + 1)
        } else {
            currentIndentedLineState = 2
        }
    }

    private func observeFenceCloserByte(byte: Byte, marker: Byte): Unit {
        match (currentFenceCloserStage) {
            case 0 =>
                if (byte == b' ' && currentFenceCloserLeadingSpaces < 3) {
                    currentFenceCloserLeadingSpaces++
                } else if (byte == marker) {
                    currentFenceCloserStage = 1
                    currentFenceCloserMarkerCount = 1
                } else {
                    currentFenceCloserStage = 3
                }
            case 1 =>
                if (byte == marker) {
                    currentFenceCloserMarkerCount++
                } else if ((byte == b' ' || byte == b'\t') && currentFenceCloserMarkerCount >= openFenceLength) {
                    currentFenceCloserStage = 2
                } else {
                    currentFenceCloserStage = 3
                }
            case 2 =>
                if (byte != b' ' && byte != b'\t') {
                    currentFenceCloserStage = 3
                }
            case _ => ()
        }
    }

    private func resetCurrentLiteralLineState(): Unit {
        currentFenceCloserStage = 0
        currentFenceCloserMarkerCount = 0
        currentFenceCloserLeadingSpaces = 0
        currentHtmlCandidateType = 0
        currentHtmlLineHasNonWhitespace = false
        currentIndentedLineState = 0
        currentIndentedContentBytes = 0
    }

    private func ensureRawLiteralObserved(observed: Int64): Unit {
        if (observed > engine.limits.maximumLiteralBytes) {
            throw LimitExceededException("literal_bytes", engine.limits.maximumLiteralBytes, observed, "block_parse")
        }
    }

    private func observeScanCheckpoint(phase: String, bytesProcessed: Int64): Unit {
        if (let Some(observer) <- scanCheckpointObserver) {
            observer.onRawBlockScanCheckpoint(phase, bytesProcessed)
        }
        cancellation.throwIfCancelled(phase: "input")
    }

    private func observeCompletedRawLine(lineStart: Int64, lineEnd: Int64): Bool {
        let blank = rawTrimmedLineStart(pending, lineStart, lineEnd) == lineEnd
        let tailProtected = openFenceMarker.isSome() || openBlockDslRule.isSome() || openHtmlBlockType > 0 ||
            openIndentedCode
        var strong = false
        if (!tailProtected && retainedTailKind.isSome()) {
            let kind = retainedTailKind.getOrThrow()
            match (kind) {
                case NodeKind.Paragraph | NodeKind.Table | NodeKind.DocumentNode => strong = blank
                case _ => ()
            }
            if (!blank && rawTrimmedLineStart(pending, lineStart, lineEnd) == lineStart) {
                if (rawLineIsClosureCandidate(pending, lineStart, lineEnd)) {
                    strong = true
                }
                if (previousRawLineBlank && !retainedDefinitionList && pending[lineStart] != b'>' &&
                    !rawMayStartList(lineStart, lineEnd)) {
                    strong = true
                }
            }
        }
        let wasFence = openFenceMarker.isSome()
        let wasHtml = openHtmlBlockType > 0
        let wasIndented = openIndentedCode
        let wasDsl = openBlockDslRule.isSome()
        let candidate = classifyCompletedRawLine(lineStart, lineEnd)
        let literalClosed = (wasFence && openFenceMarker.isNone()) || (wasHtml && openHtmlBlockType == 0) || (wasIndented &&
            !openIndentedCode) || (wasDsl && openBlockDslRule.isNone())
        // A literal nested inside a definition does not close its surrounding
        // list. Keep geometric retries for indented/blank inner closers.
        if (literalClosed && (!retainedDefinitionList || (!blank && rawTrimmedLineStart(pending, lineStart, lineEnd) ==
            lineStart))) {
            strong = true
        }
        if (!tailProtected && lineStart < lineEnd && rawTrimmedLineStart(pending, lineStart, lineEnd) == lineStart && (openFenceMarker
            .isSome() || openHtmlBlockType > 0)) {
            strong = true
        }
        previousRawLineBlank = blank
        if (strong) {
            strongBoundaryCandidate = true
        }
        candidate || strong
    }

    private func rawMayStartList(start: Int64, end: Int64): Bool {
        var cursor = start
        if (cursor >= end) {
            return false
        }
        let first = pending[cursor]
        if (first == b'-' || first == b'+' || first == b'*') {
            cursor++
        } else {
            while (cursor < end && cursor - start < 9 && pending[cursor] >= b'0' && pending[cursor] <= b'9') {
                cursor++
            }
            if (cursor == start || cursor >= end || (pending[cursor] != b'.' && pending[cursor] != b')')) {
                return false
            }
            cursor++
        }
        cursor == end || pending[cursor] == b' ' || pending[cursor] == b'\t'
    }

    private func classifyCompletedRawLine(lineStart: Int64, lineEnd: Int64): Bool {
        completedBlockDslBodyLine = false
        if (let Some(rule) <- openBlockDslRule) {
            if (let BlockSyntaxKind.CodeGroup <- rule.syntaxKind) {
                if (let Some(marker) <- openFenceMarker) {
                    completeOpenBlockDslBodyLine(lineStart, lineEnd)
                    if (rawLineClosesFence(pending, lineStart, lineEnd, marker, openFenceLength)) {
                        clearOpenFenceState()
                    } else {
                        consumeOpenFenceLiteralBytes(
                            rawFencedLiteralContentBytes(pending, lineStart, lineEnd, openFenceIndent) + 1)
                    }
                    resetOpenBlockDslCloserCandidate(rule)
                    return false
                }
                let length = rawFenceOpenerLength(pending, lineStart, lineEnd)
                if (length > 0) {
                    completeOpenBlockDslBodyLine(lineStart, lineEnd)
                    var marker = lineStart
                    while (marker < lineEnd && pending[marker] == b' ') {
                        marker++
                    }
                    openFenceMarker = Some(pending[marker])
                    openFenceLength = length
                    openFenceIndent = marker - lineStart
                    openFenceLiteralBytes = 0
                    resetOpenBlockDslCloserCandidate(rule)
                    return false
                }
            }
            if (openBlockDslCloserCandidatePossible && openBlockDslCloserInTrailingWhitespace) {
                if (openBlockDslDepth == 0) {
                    clearOpenBlockDslState()
                    indentedCodeMayStart = true
                    return true
                }
                completeOpenBlockDslBodyLine(lineStart, lineEnd)
                openBlockDslDepth--
                resetOpenBlockDslCloserCandidate(rule)
                return false
            }
            completeOpenBlockDslBodyLine(lineStart, lineEnd)
            if (rule.allowNesting) {
                // The nesting probe is a second pass over this completed line;
                // charge its bounded comparisons separately from the main scan.
                budget.consumeScan(steps: lineEnd - lineStart)
                if (rawTrimmedLineStartsWith(pending, lineStart, lineEnd, rule.openerPrefix)) {
                    openBlockDslDepth++
                }
            }
            resetOpenBlockDslCloserCandidate(rule)
            return false
        }
        match (openFenceMarker) {
            case Some(marker) =>
                if (rawLineClosesFence(pending, lineStart, lineEnd, marker, openFenceLength)) {
                    clearOpenFenceState()
                    indentedCodeMayStart = true
                    return true
                }
                consumeOpenFenceLiteralBytes(rawFencedLiteralContentBytes(pending, lineStart, lineEnd, openFenceIndent) +
                    1)
                return false
            case None => ()
        }
        if (openHtmlBlockType > 0) {
            if ((openHtmlBlockType == 6 || openHtmlBlockType == 7) && rawLineIsBlank(pending, lineStart, lineEnd)) {
                clearOpenHtmlState()
                indentedCodeMayStart = true
                return true
            }
            if (openHtmlBlockType <= 5) {
                // The preceding completed line already contributed the
                // normalized separator that begins this line.
                consumeOpenHtmlLiteralBytes(lineEnd - lineStart)
            } else {
                consumeOpenHtmlLine(lineEnd - lineStart)
            }
            if (rawLineClosesHtmlBlock(pending, lineStart, lineEnd, openHtmlBlockType)) {
                clearOpenHtmlState()
                indentedCodeMayStart = true
                return true
            }
            if (openHtmlBlockType <= 5) {
                // Type 1-5 includes the normalized line ending after every
                // non-closing line, including an empty final line.
                consumeOpenHtmlLiteralBytes(1)
            }
            return false
        }
        if (openIndentedCode) {
            if (rawLineIsBlank(pending, lineStart, lineEnd)) {
                if (openIndentedHasContent) {
                    openIndentedPendingEmptyLines++
                }
                return false
            }
            if (rawLineIsIndentedCode(pending, lineStart, lineEnd)) {
                consumeOpenIndentedLine(rawIndentedLiteralContentBytes(pending, lineStart, lineEnd))
                return false
            }
            clearOpenIndentedState()
            indentedCodeMayStart = true
            // This line both proves the indented block closed and may open the
            // next explicitly delimited block. Observe it before requesting
            // the semantic checkpoint parse.
            let _ = observeRawBlockStart(lineStart, lineEnd)
            return true
        }
        observeRawBlockStart(lineStart, lineEnd)
    }

    private func observeRawBlockStart(lineStart: Int64, lineEnd: Int64): Bool {
        if (let Some(rule) <- matchingBlockDslRule(lineStart, lineEnd)) {
            match (rule.syntaxKind) {
                case BlockSyntaxKind.DefinitionList => return false
                case BlockSyntaxKind.FootnoteDefinition =>
                    if (draftLineage.isSome()) {
                        return false
                    }
                    throw MarkdownException(MarkdownErrorCode.ExtensionFailure,
                        "footnote definitions require document binding", phase: "event_preflight")
                case BlockSyntaxKind.SingleLine =>
                    indentedCodeMayStart = true
                    return true
                case BlockSyntaxKind.PairedContainer | BlockSyntaxKind.DisplayMath | BlockSyntaxKind.CodeGroup =>
                    openBlockDslRule = Some(rule)
                    openBlockDslDepth = 0
                    openBlockDslStart = lineStart
                    openBlockDslSourceStart = sourceOffset + lineStart - pendingStart
                    openBlockDslBodyBytes = 0
                    openBlockDslCurrentLineCharged = false
                    resetOpenBlockDslCloserCandidate(rule)
                    completedBlockDslBodyLine = false
                    previousBlockDslBodyLineEndedWithCarriageReturn = false
                    previousBlockDslBodyLineEnd = -1
                    indentedCodeMayStart = false
                    return false
            }
        }
        let htmlType = rawHtmlBlockType(pending, lineStart, lineEnd)
        // CommonMark type 7 HTML cannot interrupt an existing paragraph. The
        // same boundary flag that gates indented code distinguishes a proven
        // block boundary from a lazy paragraph continuation here.
        if (htmlType > 0 && (htmlType != 7 || indentedCodeMayStart)) {
            indentedCodeMayStart = false
            consumeOpenHtmlFirstLine(lineEnd - lineStart)
            if (rawLineClosesHtmlBlock(pending, lineStart, lineEnd, htmlType)) {
                clearOpenHtmlState()
                indentedCodeMayStart = true
                return true
            }
            openHtmlBlockType = htmlType
            if (htmlType <= 5) {
                consumeOpenHtmlLiteralBytes(1)
            }
            return false
        }
        let fenceLength = rawFenceOpenerLength(pending, lineStart, lineEnd)
        if (fenceLength > 0) {
            var markerOffset = lineStart
            while (markerOffset < lineEnd && pending[markerOffset] == b' ') {
                markerOffset++
            }
            openFenceMarker = Some(pending[markerOffset])
            openFenceLength = fenceLength
            openFenceIndent = markerOffset - lineStart
            openFenceLiteralBytes = 0
            indentedCodeMayStart = false
            return true
        }
        if (indentedCodeMayStart && rawLineIsIndentedCode(pending, lineStart, lineEnd)) {
            openIndentedCode = true
            indentedCodeMayStart = false
            consumeOpenIndentedFirstLine(rawIndentedLiteralContentBytes(pending, lineStart, lineEnd))
            return false
        }
        let blank = rawLineIsBlank(pending, lineStart, lineEnd)
        if (!blank) {
            indentedCodeMayStart = false
        }
        rawLineIsClosureCandidate(pending, lineStart, lineEnd)
    }

    private func consumeOpenHtmlFirstLine(bytes: Int64): Unit {
        openHtmlLiteralBytes = 0
        consumeOpenHtmlLiteralBytes(bytes)
    }

    private func consumeOpenFenceLiteralBytes(bytes: Int64): Unit {
        let observed = openFenceLiteralBytes + bytes
        ensureRawLiteralObserved(observed)
        openFenceLiteralBytes = observed
    }

    private func clearOpenFenceState(): Unit {
        openFenceMarker = None
        openFenceLength = 0
        openFenceIndent = 0
        openFenceLiteralBytes = 0
    }

    private func consumeOpenHtmlLine(bytes: Int64): Unit {
        // parseHtmlBlock normalizes every source line ending to one LF and
        // appends that separator before appending the next complete line.
        consumeOpenHtmlLiteralBytes(1)
        consumeOpenHtmlLiteralBytes(bytes)
    }

    private func consumeOpenHtmlLiteralBytes(bytes: Int64): Unit {
        let observed = openHtmlLiteralBytes + bytes
        if (observed > engine.limits.maximumLiteralBytes) {
            throw LimitExceededException("literal_bytes", engine.limits.maximumLiteralBytes, observed, "block_parse")
        }
        openHtmlLiteralBytes = observed
    }

    private func clearOpenHtmlState(): Unit {
        openHtmlBlockType = 0
        openHtmlLiteralBytes = 0
    }

    private func consumeOpenIndentedFirstLine(bytes: Int64): Unit {
        openIndentedLiteralBytes = 0
        openIndentedHasContent = false
        openIndentedPendingEmptyLines = 0
        consumeOpenIndentedLine(bytes)
    }

    private func consumeOpenIndentedLine(bytes: Int64): Unit {
        if (bytes <= 0) {
            return
        }
        let separators = if (openIndentedHasContent) {
            openIndentedPendingEmptyLines + 1
        } else {
            0
        }
        let observed = openIndentedLiteralBytes + separators + bytes
        if (observed > engine.limits.maximumLiteralBytes) {
            throw LimitExceededException("literal_bytes", engine.limits.maximumLiteralBytes, observed, "block_parse")
        }
        openIndentedLiteralBytes = observed
        openIndentedHasContent = true
        openIndentedPendingEmptyLines = 0
    }

    private func clearOpenIndentedState(): Unit {
        openIndentedCode = false
        openIndentedLiteralBytes = 0
        openIndentedHasContent = false
        openIndentedPendingEmptyLines = 0
    }

    private func matchingBlockDslRule(lineStart: Int64, lineEnd: Int64): ?BlockSyntaxRule {
        if (!engine.dialect.parserOptions.extensionsEnabled || !engine.dialect.parserHotPlan.hasBlockDsl) {
            return None
        }
        let leadingBom = sourceOffset == 0 && pendingStart == 0 && lineStart == 0 && lineEnd >= 3 && pending[0] == 0xEF &&
            pending[1] == 0xBB && pending[2] == 0xBF
        let contentStart = rawTrimmedLineStart(pending, if (leadingBom) {
            lineStart + 3
        } else {
            lineStart
        }, lineEnd)
        let contentEnd = rawTrimmedLineEnd(pending, contentStart, lineEnd)
        if (contentStart == contentEnd) {
            return None
        }
        let absoluteStart = sourceOffset + contentStart - pendingStart
        let rules = engine.dialect.parserHotPlan.blockRules(pending[contentStart])
        for (index in 0..rules.size) {
            let rule = rules[index]
            if (rule.documentStartOnly && !(absoluteStart == 0 || (absoluteStart == 3 && leadingBom))) {
                continue
            }
            if (let BlockSyntaxKind.CodeGroup <- rule.syntaxKind) {
                if (contentEnd - contentStart != rule.openerPrefix.size ||
                    contentStart - lineStart - (if (leadingBom) {
                    3
                } else {
                    0
                }) > 3) {
                    continue
                }
                var tab = false
                for (prefix in (lineStart + (if (leadingBom) {
                    3
                } else {
                    0
                }))..contentStart) {
                    if (pending[prefix] == b'\t') {
                        tab = true
                    }
                }
                if (tab) {
                    continue
                }
            }
            if (let BlockSyntaxKind.DisplayMath <- rule.syntaxKind) {
                if (contentEnd - contentStart != 2 || contentStart - lineStart - (if (leadingBom) {
                    3
                } else {
                    0
                }) > 3) {
                    continue
                }
                var tab = false
                for (prefix in (lineStart + (if (leadingBom) {
                    3
                } else {
                    0
                }))..contentStart) {
                    if (pending[prefix] == b'\t') {
                        tab = true
                    }
                }
                if (tab) {
                    continue
                }
            }
            if (rawListStartsWith(pending, contentStart, contentEnd, rule.openerPrefix, false)) {
                return Some(rule)
            }
        }
        None
    }

    private func observeOpenBlockDslBodyByte(lineStart: Int64, byteIndex: Int64): Unit {
        if (let Some(rule) <- openBlockDslRule) {
            advanceOpenBlockDslCloserCandidate(rule, pending[byteIndex])
            if (openBlockDslCurrentLineCharged) {
                consumeOpenBlockDslBodyBytes(1, absolutePendingOffset(byteIndex + 1))
            } else if (openBlockDslDepth > 0 || !openBlockDslCloserCandidatePossible) {
                consumeOpenBlockDslBodyBytes(byteIndex + 1 - lineStart, absolutePendingOffset(byteIndex + 1))
                openBlockDslCurrentLineCharged = true
            }
        }
    }

    private func advanceOpenBlockDslCloserCandidate(rule: BlockSyntaxRule, byte: Byte): Unit {
        if (!openBlockDslCloserCandidatePossible) {
            return
        }
        // This byte is inspected by the DSL matcher in addition to the main
        // line scan, so meter that real comparison explicitly.
        budget.consumeScan()
        if (openBlockDslCloserInTrailingWhitespace) {
            if (byte != b' ' && byte != b'\t') {
                openBlockDslCloserCandidatePossible = false
            }
            return
        }
        if (openBlockDslCloserMatchLength == 0 && (byte == b' ' || byte == b'\t')) {
            return
        }
        if (openBlockDslCloserMatchLength >= rule.closer.size || byte != rule.closer[openBlockDslCloserMatchLength]) {
            openBlockDslCloserCandidatePossible = false
            return
        }
        openBlockDslCloserMatchLength++
        if (openBlockDslCloserMatchLength == rule.closer.size) {
            openBlockDslCloserInTrailingWhitespace = true
        }
    }

    private func resetOpenBlockDslCloserCandidate(rule: BlockSyntaxRule): Unit {
        openBlockDslCloserMatchLength = 0
        openBlockDslCloserInTrailingWhitespace = rule.closer.isEmpty()
        openBlockDslCloserCandidatePossible = true
        if (let BlockSyntaxKind.CodeGroup <- rule.syntaxKind) {
            if (openFenceMarker.isSome()) {
                openBlockDslCloserCandidatePossible = false
            }
        }
    }

    private func completeOpenBlockDslBodyLine(lineStart: Int64, lineEnd: Int64): Unit {
        if (!openBlockDslCurrentLineCharged) {
            consumeOpenBlockDslBodyBytes(lineEnd - lineStart, absolutePendingOffset(lineEnd))
        }
        consumeOpenBlockDslBodyBytes(1, absolutePendingOffset(lineEnd))
        openBlockDslCurrentLineCharged = false
        completedBlockDslBodyLine = true
        previousBlockDslBodyLineEnd = absolutePendingOffset(lineEnd)
    }

    private func consumeOpenBlockDslBodyBytes(bytes: Int64, lineEnd: Int64): Unit {
        if (bytes <= 0) {
            return
        }
        if (let Some(rule) <- openBlockDslRule) {
            openBlockDslBodyBytes += bytes
            if (openBlockDslBodyBytes > rule.maximumBlockBytes) {
                throw LimitExceededException("extension_block_bytes", rule.maximumBlockBytes, openBlockDslBodyBytes,
                    "extension_parse", span: Some(SourceSpan(openBlockDslSourceStart, lineEnd)),
                    extensionId: Some(rule.extensionId))
            }
        }
    }

    private func absolutePendingOffset(offset: Int64): Int64 {
        sourceOffset + offset - pendingStart
    }

    private func clearOpenBlockDslState(): Unit {
        openBlockDslRule = None
        openBlockDslDepth = 0
        openBlockDslStart = -1
        openBlockDslSourceStart = -1
        openBlockDslBodyBytes = 0
        openBlockDslCurrentLineCharged = false
        openBlockDslCloserMatchLength = 0
        openBlockDslCloserInTrailingWhitespace = false
        openBlockDslCloserCandidatePossible = true
        completedBlockDslBodyLine = false
        previousBlockDslBodyLineEndedWithCarriageReturn = false
        previousBlockDslBodyLineEnd = -1
    }

    private func synchronizeRetainedTail(group: ParserEventGroup): Unit {
        if (let Some(marker) <- group.fenceMarker) {
            if (!group.explicitlyClosed) {
                openFenceMarker = Some(marker)
                openFenceLength = group.fenceLength
                // Lexical observation normally established these values before
                // semantic synchronization. If a future parser path reaches
                // here first, zero indentation is the conservative source-slice
                // representation and the next completed line remains bounded.
                indentedCodeMayStart = false
            }
        } else if (group.isIndentedCode) {
            openIndentedCode = true
            indentedCodeMayStart = false
        } else if (group.htmlBlockType > 0 && group.htmlBlockType <= 5 && !group.explicitlyClosed) {
            openHtmlBlockType = group.htmlBlockType
            indentedCodeMayStart = false
        }
    }

    private func discardPendingPrefix(discard: Int64): Unit {
        pendingStart += discard
        if (pendingStart == pending.size) {
            // Dropping the complete buffer requires no retained-tail copy.
            pending = ArrayList<Byte>()
            pendingStart = 0
            scanCursor = 0
            scanLineStart = 0
            lastCompleteLineEnd = 0
            clearOpenFenceState()
            clearOpenHtmlState()
            clearOpenIndentedState()
            indentedCodeMayStart = true
            clearOpenBlockDslState()
            return
        }
        // Compact only after a sizeable prefix is at least half the backing
        // buffer. This keeps feed/discard amortized while bounding stale bytes
        // retained by long-running sessions.
        if (pendingStart >= 4096 && pendingStart >= pending.size - pendingStart) {
            let oldStart = pendingStart
            let retained = ArrayList<Byte>()
            var index = oldStart
            while (index < pending.size) {
                retained.add(pending[index])
                index++
            }
            pending = retained
            pendingStart = 0
            scanCursor -= oldStart
            scanLineStart = max(0, scanLineStart - oldStart)
            lastCompleteLineEnd = max(0, lastCompleteLineEnd - oldStart)
            if (openBlockDslStart >= 0) {
                openBlockDslStart -= oldStart
            }
        }
    }

    private func documentStart(): MarkdownSourceEvent {
        MarkdownSourceEvent(MarkdownSourceEventKind.DocumentStart, nodeKind: Some(NodeKind.DocumentNode),
            finalSemantics: false)
    }

    private func ensureOpen(): Unit {
        if (finished) {
            throw IllegalStateException("raw block event session is already finished")
        }
    }
}

private func eventAttributes(payload: ArenaNodePayload): Array<MarkdownEventAttribute> {
    let out = ArrayList<MarkdownEventAttribute>()
    match (payload) {
        case ArenaNodePayload.DocumentValue(_, fingerprint, _) => out.add(
            MarkdownEventAttribute("dialectFingerprint", fingerprint))
        case ArenaNodePayload.HeadingValue(level) => out.add(MarkdownEventAttribute("level", "${level}"))
        case ArenaNodePayload.TextValue(raw, _, normalized) =>
            out.add(MarkdownEventAttribute("raw", raw.text()))
            if (let Some(value) <- normalized) {
                out.add(MarkdownEventAttribute("normalized", value))
            }
        case ArenaNodePayload.ListValue(kind, start, delimiter, tight) =>
            out.add(MarkdownEventAttribute("listKind", listKindName(kind)))
            out.add(MarkdownEventAttribute("start", "${start}"))
            out.add(MarkdownEventAttribute("delimiter", listDelimiterName(delimiter)))
            out.add(MarkdownEventAttribute("tight", "${tight}"))
        case ArenaNodePayload.ListItemValue(task, markerSpan) =>
            out.add(MarkdownEventAttribute("taskState", taskStateName(task)))
            if (let Some(span) <- markerSpan) {
                out.add(MarkdownEventAttribute("markerRange", "${span.startByte}:${span.endByte}"))
            }
        case ArenaNodePayload.ThematicBreakValue(marker) => out.add(MarkdownEventAttribute("marker", "${marker}"))
        case ArenaNodePayload.CodeBlockValue(kind, _, fence, length, _, closing, info, language, attributes) =>
            out.add(MarkdownEventAttribute("codeKind", codeBlockKindName(kind)))
            if (let Some(value) <- fence) {
                out.add(MarkdownEventAttribute("fence", "${value}"))
            }
            out.add(MarkdownEventAttribute("fenceLength", "${length}"))
            out.add(MarkdownEventAttribute("closed", "${closing.isSome()}"))
            out.add(MarkdownEventAttribute("infoRaw", info))
            out.add(MarkdownEventAttribute("language", language))
            out.add(MarkdownEventAttribute("attributesRaw", attributes))
        case ArenaNodePayload.HtmlBlockValue(_, blockType) => out.add(
            MarkdownEventAttribute("blockType", "${blockType}"))
        case ArenaNodePayload.LinkValue(destinationRaw, destination, titleRaw, title, syntax) =>
            out.add(MarkdownEventAttribute("destinationRaw", destinationRaw))
            out.add(MarkdownEventAttribute("destination", destination))
            out.add(MarkdownEventAttribute("titleRaw", titleRaw))
            out.add(MarkdownEventAttribute("title", title))
            out.add(MarkdownEventAttribute("syntax", linkSyntaxName(syntax)))
        case ArenaNodePayload.TableValue(alignments) => out.add(MarkdownEventAttribute("columns", "${alignments.size}"))
        case ArenaNodePayload.TableRowValue(header) => out.add(MarkdownEventAttribute("header", "${header}"))
        case ArenaNodePayload.TableCellValue(alignment) => out.add(
            MarkdownEventAttribute("alignment", tableAlignmentName(alignment)))
        case ArenaNodePayload.HardBreakValue(kind) => out.add(
            MarkdownEventAttribute("breakKind", hardBreakKindName(kind)))
        case ArenaNodePayload.CodeSpanValue(_, delimiter) => out.add(MarkdownEventAttribute("delimiterRaw", delimiter))
        case ArenaNodePayload.CustomValue(extensionId, version, localKind, _) =>
            out.add(MarkdownEventAttribute("extensionId", extensionId))
            out.add(MarkdownEventAttribute("extensionVersion", version))
            out.add(MarkdownEventAttribute("localKindId", localKind))
        case _ => ()
    }
    out.toArray()
}

private func literalSemanticValue(payload: ArenaNodePayload): ?String {
    match (payload) {
        case ArenaNodePayload.CodeBlockValue(_, literal, _, _, _, _, _, _, _) => Some(literal.text())
        case ArenaNodePayload.HtmlBlockValue(literal, _) => Some(literal.text())
        case ArenaNodePayload.CodeSpanValue(literal, _) => Some(literal)
        case ArenaNodePayload.HtmlInlineValue(literal) => Some(literal)
        case _ => None
    }
}

private func explicitlyClosed(payload: ArenaNodePayload): Bool {
    match (payload) {
        case ArenaNodePayload.CodeBlockValue(CodeBlockKind.Fenced, _, _, _, _, closing, _, _, _) => closing.isSome()
        case ArenaNodePayload.HtmlBlockValue(literal, blockType) => rawHtmlLiteralIsClosed(literal.text(), blockType)
        case ArenaNodePayload.ThematicBreakValue(_) => true
        case ArenaNodePayload.HeadingValue(_) => true
        case _ => false
    }
}

private func eventHtmlBlockType(payload: ArenaNodePayload): Int64 {
    match (payload) {
        case ArenaNodePayload.HtmlBlockValue(_, blockType) => blockType
        case _ => 0
    }
}

private func eventIsIndentedCode(payload: ArenaNodePayload): Bool {
    match (payload) {
        case ArenaNodePayload.CodeBlockValue(CodeBlockKind.Indented, _, _, _, _, _, _, _, _) => true
        case _ => false
    }
}

private func eventFenceMarker(payload: ArenaNodePayload): ?Byte {
    match (payload) {
        case ArenaNodePayload.CodeBlockValue(CodeBlockKind.Fenced, _, marker, _, _, _, _, _, _) => marker
        case _ => None
    }
}

private func eventFenceLength(payload: ArenaNodePayload): Int64 {
    match (payload) {
        case ArenaNodePayload.CodeBlockValue(CodeBlockKind.Fenced, _, _, length, _, _, _, _, _) => length
        case _ => 0
    }
}

private func rawTailCloses(group: ParserEventGroup, bytes: Array<Byte>, localEnd: Int64): Bool {
    if (group.explicitlyClosed && lineBreakCount(bytes, localEnd) > 0) {
        return true
    }
    match (group.kind) {
        case NodeKind.DocumentNode | NodeKind.Paragraph => lineBreakCount(bytes, localEnd) >= 2 && tailIsWhitespace(
            bytes, localEnd)
        case NodeKind.Table => lineBreakCount(bytes, localEnd) >= 2 && tailIsWhitespace(bytes, localEnd)
        case NodeKind.HtmlBlock => (group.htmlBlockType == 6 || group.htmlBlockType == 7) &&
            lineBreakCount(bytes, localEnd) >= 2 && tailIsWhitespace(bytes, localEnd)
        case _ => false
    }
}

private func tailIsWhitespace(bytes: Array<Byte>, start: Int64): Bool {
    var index = start
    while (index < bytes.size) {
        let byte = bytes[index]
        if (byte != b' ' && byte != b'\t' && byte != b'\r' && byte != b'\n') {
            return false
        }
        index++
    }
    true
}

private func lineBreakCount(bytes: Array<Byte>, start: Int64): Int64 {
    var count: Int64 = 0
    var index = max(0, start)
    while (index < bytes.size) {
        if (bytes[index] == b'\r') {
            count++
            if (index + 1 < bytes.size && bytes[index + 1] == b'\n') {
                index++
            }
        } else if (bytes[index] == b'\n') {
            count++
        }
        index++
    }
    count
}

private func rawHtmlBlockType(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Int64 {
    var content = lineStart
    while (content < lineEnd && content - lineStart < 4 && bytes[content] == b' ') {
        content++
    }
    if (content == lineEnd || content - lineStart > 3 || bytes[content] != b'<') {
        return 0
    }
    if (rawListStartsHtmlTypeOneTag(bytes, content, lineEnd, "<script") || rawListStartsHtmlTypeOneTag(bytes, content,
        lineEnd, "<pre") || rawListStartsHtmlTypeOneTag(bytes, content, lineEnd, "<style") ||
        rawListStartsHtmlTypeOneTag(bytes, content, lineEnd, "<textarea")) {
        return 1
    }
    if (rawListStartsWith(bytes, content, lineEnd, "<!--", false)) {
        return 2
    }
    if (rawListStartsWith(bytes, content, lineEnd, "<?", false)) {
        return 3
    }
    if (rawListStartsWith(bytes, content, lineEnd, "<![CDATA[", false)) {
        return 5
    }
    if (rawListStartsWith(bytes, content, lineEnd, "<!", false) && content + 2 < lineEnd && bytes[content + 2] >= b'A' &&
        bytes[content + 2] <= b'Z') {
        return 4
    }
    let trimmedEnd = rawTrimmedLineEnd(bytes, content, lineEnd)
    var nameStart = content + 1
    if (nameStart < trimmedEnd && bytes[nameStart] == b'/') {
        nameStart++
    }
    var nameEnd = nameStart
    while (nameEnd < trimmedEnd && rawIsAsciiLetterOrDigit(bytes[nameEnd])) {
        nameEnd++
    }
    if (nameEnd == nameStart) {
        return 0
    }
    if (nameEnd < trimmedEnd && bytes[nameEnd] != b' ' && bytes[nameEnd] != b'\t' && bytes[nameEnd] != b'/' &&
        bytes[nameEnd] != b'>') {
        return 0
    }
    if (rawIsBlockTag(bytes, nameStart, nameEnd)) {
        return 6
    }
    if (trimmedEnd > content && bytes[trimmedEnd - 1] == b'>') {
        let firstClose = rawFindByte(bytes, b'>', nameEnd, trimmedEnd)
        if (firstClose == trimmedEnd - 1 && rawIsInlineHtml(bytes, content + 1, trimmedEnd - 1)) {
            return 7
        }
    }
    0
}

private func rawIsAsciiLetterOrDigit(byte: Byte): Bool {
    (byte >= b'A' && byte <= b'Z') || (byte >= b'a' && byte <= b'z') || (byte >= b'0' && byte <= b'9')
}

private func rawRangeEqualsAsciiCase(bytes: ArrayList<Byte>, start: Int64, end: Int64, value: String): Bool {
    if (end - start != value.size) {
        return false
    }
    var index: Int64 = 0
    while (index < value.size) {
        if (!rawAsciiByteEqual(bytes[start + index], value[index], true)) {
            return false
        }
        index++
    }
    true
}

private func rawIsBlockTag(bytes: ArrayList<Byte>, start: Int64, end: Int64): Bool {
    for (tag in [
        "address",
        "article",
        "aside",
        "base",
        "basefont",
        "blockquote",
        "body",
        "caption",
        "center",
        "col",
        "colgroup",
        "dd",
        "details",
        "dialog",
        "dir",
        "div",
        "dl",
        "dt",
        "fieldset",
        "figcaption",
        "figure",
        "footer",
        "form",
        "frame",
        "frameset",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "head",
        "header",
        "hr",
        "html",
        "iframe",
        "legend",
        "li",
        "link",
        "main",
        "menu",
        "menuitem",
        "nav",
        "noframes",
        "ol",
        "optgroup",
        "option",
        "p",
        "param",
        "section",
        "source",
        "summary",
        "table",
        "tbody",
        "td",
        "tfoot",
        "th",
        "thead",
        "title",
        "tr",
        "track",
        "ul"
    ]) {
        if (rawRangeEqualsAsciiCase(bytes, start, end, tag)) {
            return true
        }
    }
    false
}

private func rawFindByte(bytes: ArrayList<Byte>, expected: Byte, start: Int64, end: Int64): Int64 {
    var index = start
    while (index < end) {
        if (bytes[index] == expected) {
            return index
        }
        index++
    }
    -1
}

private func rawIsInlineHtml(bytes: ArrayList<Byte>, start: Int64, end: Int64): Bool {
    var index = start
    let closing = index < end && bytes[index] == b'/'
    if (closing) {
        index++
    }
    if (index >= end || !rawIsAsciiLetter(bytes[index])) {
        return false
    }
    while (index < end && (rawIsAsciiLetterOrDigit(bytes[index]) || bytes[index] == b'-')) {
        index++
    }
    if (closing) {
        return rawSkipInlineHtmlWhitespace(bytes, index, end) == end
    }
    while (index < end) {
        let beforeWhitespace = index
        index = rawSkipInlineHtmlWhitespace(bytes, index, end)
        if (index >= end) {
            return true
        }
        if (bytes[index] == b'/') {
            return index + 1 == end
        }
        if (index == beforeWhitespace || !rawIsHtmlAttributeStart(bytes[index])) {
            return false
        }
        index++
        while (index < end && rawIsHtmlAttributeContinuation(bytes[index])) {
            index++
        }
        let afterName = index
        let equalsIndex = rawSkipInlineHtmlWhitespace(bytes, index, end)
        if (equalsIndex < end && bytes[equalsIndex] == b'=') {
            index = rawSkipInlineHtmlWhitespace(bytes, equalsIndex + 1, end)
            if (index >= end) {
                return false
            }
            if (bytes[index] == b'"' || bytes[index] == b'\'') {
                let quoteByte = bytes[index]
                index++
                while (index < end && bytes[index] != quoteByte) {
                    index++
                }
                if (index >= end) {
                    return false
                }
                index++
            } else {
                let valueStart = index
                while (index < end && !rawIsInlineHtmlWhitespace(bytes[index]) && bytes[index] != b'"' &&
                        bytes[index] != b'\'' && bytes[index] != b'=' && bytes[index] != b'<' && bytes[index] != b'>' &&
                        bytes[index] != b'`') {
                    index++
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

private func rawIsAsciiLetter(byte: Byte): Bool {
    (byte >= b'A' && byte <= b'Z') || (byte >= b'a' && byte <= b'z')
}

private func rawIsInlineHtmlWhitespace(byte: Byte): Bool {
    byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r'
}

private func rawSkipInlineHtmlWhitespace(bytes: ArrayList<Byte>, start: Int64, end: Int64): Int64 {
    var index = start
    while (index < end && rawIsInlineHtmlWhitespace(bytes[index])) {
        index++
    }
    index
}

private func rawIsHtmlAttributeStart(byte: Byte): Bool {
    rawIsAsciiLetter(byte) || byte == b'_' || byte == b':'
}

private func rawIsHtmlAttributeContinuation(byte: Byte): Bool {
    rawIsHtmlAttributeStart(byte) || (byte >= b'0' && byte <= b'9') || byte == b'.' || byte == b'-'
}

private func rawListStartsHtmlTypeOneTag(bytes: ArrayList<Byte>, start: Int64, end: Int64, tag: String): Bool {
    if (!rawListStartsWith(bytes, start, end, tag, true)) {
        return false
    }
    let boundary = start + tag.size
    boundary == end || isHtmlTypeOneTagBoundary(bytes[boundary])
}

private func rawLineClosesHtmlBlock(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64, blockType: Int64): Bool {
    match (blockType) {
        case 1 => rawListContains(bytes, lineStart, lineEnd, "</script>", true) || rawListContains(bytes, lineStart,
            lineEnd, "</pre>", true) || rawListContains(bytes, lineStart, lineEnd, "</style>", true) || rawListContains(
            bytes, lineStart, lineEnd, "</textarea>", true)
        case 2 => rawListContains(bytes, lineStart, lineEnd, "-->", false)
        case 3 => rawListContains(bytes, lineStart, lineEnd, "?>", false)
        case 4 => rawListContains(bytes, lineStart, lineEnd, ">", false)
        case 5 => rawListContains(bytes, lineStart, lineEnd, "]]>", false)
        case _ => false
    }
}

private func rawHtmlLiteralIsClosed(literal: String, blockType: Int64): Bool {
    match (blockType) {
        case 1 => rawStringContains(literal, "</script>", true) || rawStringContains(literal, "</pre>", true) ||
            rawStringContains(literal, "</style>", true) || rawStringContains(literal, "</textarea>", true)
        case 2 => literal.contains("-->")
        case 3 => literal.contains("?>")
        case 4 => literal.contains(">")
        case 5 => literal.contains("]]>")
        case _ => false
    }
}

private func rawLineIsBlank(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Bool {
    var index = lineStart
    while (index < lineEnd) {
        if (bytes[index] != b' ' && bytes[index] != b'\t') {
            return false
        }
        index++
    }
    true
}

private func rawTrimmedLineStart(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Int64 {
    var start = lineStart
    while (start < lineEnd && (bytes[start] == b' ' || bytes[start] == b'\t')) {
        start++
    }
    start
}

private func rawTrimmedLineEnd(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Int64 {
    var end = lineEnd
    while (end > lineStart && (bytes[end - 1] == b' ' || bytes[end - 1] == b'\t')) {
        end--
    }
    end
}

private func rawTrimmedLineStartsWith(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64, prefix: String): Bool {
    let contentStart = rawTrimmedLineStart(bytes, lineStart, lineEnd)
    let contentEnd = rawTrimmedLineEnd(bytes, contentStart, lineEnd)
    rawListStartsWith(bytes, contentStart, contentEnd, prefix, false)
}

private func rawLineIsIndentedCode(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Bool {
    var columns: Int64 = 0
    var index = lineStart
    while (index < lineEnd && (bytes[index] == b' ' || bytes[index] == b'\t')) {
        columns = if (bytes[index] == b'\t') {
            columns + (4 - columns % 4)
        } else {
            columns + 1
        }
        index++
    }
    index < lineEnd && columns >= 4
}

/** Returns the normalized byte count produced by stripping four indentation
 * columns. A tab that crosses the four-column boundary contributes synthetic
 * spaces exactly like ParserSession.strippedIndentLayout(). */
private func rawIndentedLiteralContentBytes(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Int64 {
    var columns: Int64 = 0
    var index = lineStart
    while (index < lineEnd && (bytes[index] == b' ' || bytes[index] == b'\t')) {
        columns = if (bytes[index] == b'\t') {
            columns + (4 - columns % 4)
        } else {
            columns + 1
        }
        index++
    }
    max(0, columns - 4) + lineEnd - index
}

/** Normalized fenced-code body bytes after stripping up to the opener's
 * indentation from the current line. Fence indentation is at most three ASCII
 * spaces, so this remains constant work per appended byte. */
private func rawFencedLiteralContentBytes(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64, openerIndent: Int64): Int64 {
    var stripped: Int64 = 0
    var index = lineStart
    while (index < lineEnd && stripped < openerIndent && bytes[index] == b' ') {
        stripped++
        index++
    }
    lineEnd - index
}

private func rawListStartsWith(bytes: ArrayList<Byte>, start: Int64, end: Int64, pattern: String, ignoreAsciiCase: Bool): Bool {
    if (pattern.size > end - start) {
        return false
    }
    var index: Int64 = 0
    while (index < pattern.size) {
        if (!rawAsciiByteEqual(bytes[start + index], pattern[index], ignoreAsciiCase)) {
            return false
        }
        index++
    }
    true
}

private func rawListContains(bytes: ArrayList<Byte>, start: Int64, end: Int64, pattern: String, ignoreAsciiCase: Bool): Bool {
    var offset = start
    while (offset + pattern.size <= end) {
        if (rawListStartsWith(bytes, offset, end, pattern, ignoreAsciiCase)) {
            return true
        }
        offset++
    }
    false
}

private func rawStringContains(value: String, pattern: String, ignoreAsciiCase: Bool): Bool {
    var offset: Int64 = 0
    while (offset + pattern.size <= value.size) {
        var patternIndex: Int64 = 0
        while (patternIndex < pattern.size && rawAsciiByteEqual(value[offset + patternIndex], pattern[patternIndex],
                ignoreAsciiCase)) {
            patternIndex++
        }
        if (patternIndex == pattern.size) {
            return true
        }
        offset++
    }
    false
}

private func rawAsciiByteEqual(left: Byte, right: Byte, ignoreAsciiCase: Bool): Bool {
    if (left == right) {
        return true
    }
    if (!ignoreAsciiCase) {
        return false
    }
    if (left >= b'A' && left <= b'Z' && right >= b'a' && right <= b'z') {
        return left - b'A' == right - b'a'
    }
    if (left >= b'a' && left <= b'z' && right >= b'A' && right <= b'Z') {
        return left - b'a' == right - b'A'
    }
    false
}

/** Cheap conservative trigger that prevents reparsing an unfinished long
 * paragraph on every chunk. False means no block can yet be proven closed;
 * true only requests a semantic parse and does not itself authorize emission. */
private func rawLineIsClosureCandidate(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Bool {
    var content = lineStart
    while (content < lineEnd && content - lineStart < 4 && bytes[content] == b' ') {
        content++
    }
    if (content == lineEnd) {
        return true
    }
    if (content - lineStart > 3) {
        return false
    }
    let first = bytes[content]
    if (first == b'#') {
        return rawLineStartsAtxHeading(bytes, content, lineEnd)
    }
    if (first == b'`' || first == b'~') {
        // Valid fences were already recognized by rawFenceOpenerLength() in
        // observeRawBlockStart. The remaining marker-prefixed lines are plain
        // paragraph text and must not trigger a retained-tail semantic parse.
        return false
    }
    if (first != b'*' && first != b'-' && first != b'_') {
        return false
    }
    var markerCount: Int64 = 0
    var markerIndex = content
    while (markerIndex < lineEnd) {
        if (bytes[markerIndex] == first) {
            markerCount++
        } else if (bytes[markerIndex] != b' ' && bytes[markerIndex] != b'\t') {
            return false
        }
        markerIndex++
    }
    markerCount >= 3
}

/** CommonMark ATX openers contain one through six `#` bytes and require a
 * space, tab, or line end after the opening run. A `#x` paragraph line is not
 * a block boundary; treating it as one makes an incremental raw session parse
 * and copy its complete retained paragraph after every such line. */
private func rawLineStartsAtxHeading(bytes: ArrayList<Byte>, content: Int64, lineEnd: Int64): Bool {
    var end = content
    while (end < lineEnd && bytes[end] == b'#') {
        end++
        if (end - content > 6) {
            return false
        }
    }
    end == lineEnd || bytes[end] == b' ' || bytes[end] == b'\t'
}

/** Returns the delimiter run length for a CommonMark fence opener, or zero
 * when the completed line cannot open a fence. */
private func rawFenceOpenerLength(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64): Int64 {
    var content = lineStart
    while (content < lineEnd && content - lineStart < 4 && bytes[content] == b' ') {
        content++
    }
    if (content == lineEnd || content - lineStart > 3) {
        return 0
    }
    let marker = bytes[content]
    if (marker != b'`' && marker != b'~') {
        return 0
    }
    var count: Int64 = 0
    while (content + count < lineEnd && bytes[content + count] == marker) {
        count++
    }
    if (count < 3) {
        return 0
    }
    if (marker == b'`') {
        var tail = content + count
        while (tail < lineEnd) {
            if (bytes[tail] == b'`') {
                return 0
            }
            tail++
        }
    }
    count
}

private func rawLineClosesFence(bytes: ArrayList<Byte>, lineStart: Int64, lineEnd: Int64, marker: Byte, minimum: Int64): Bool {
    var content = lineStart
    while (content < lineEnd && content - lineStart < 4 && bytes[content] == b' ') {
        content++
    }
    if (content - lineStart > 3) {
        return false
    }
    var count: Int64 = 0
    while (content + count < lineEnd && bytes[content + count] == marker) {
        count++
    }
    if (count < minimum) {
        return false
    }
    var tail = content + count
    while (tail < lineEnd) {
        if (bytes[tail] != b' ' && bytes[tail] != b'\t') {
            return false
        }
        tail++
    }
    true
}

private func listKindName(value: ListKind): String {
    match (value) {
        case ListKind.Bullet => "bullet"
        case ListKind.Ordered => "ordered"
    }
}

private func listDelimiterName(value: ListDelimiter): String {
    match (value) {
        case ListDelimiter.Period => "period"
        case ListDelimiter.Parenthesis => "parenthesis"
        case ListDelimiter.None => "none"
    }
}

private func taskStateName(value: TaskState): String {
    match (value) {
        case TaskState.NotTask => "not-task"
        case TaskState.Unchecked => "unchecked"
        case TaskState.Checked => "checked"
    }
}

private func codeBlockKindName(value: CodeBlockKind): String {
    match (value) {
        case CodeBlockKind.Indented => "indented"
        case CodeBlockKind.Fenced => "fenced"
    }
}

private func linkSyntaxName(value: LinkSyntaxKind): String {
    match (value) {
        case LinkSyntaxKind.Inline => "inline"
        case LinkSyntaxKind.FullReference => "full-reference"
        case LinkSyntaxKind.CollapsedReference => "collapsed-reference"
        case LinkSyntaxKind.ShortcutReference => "shortcut-reference"
        case LinkSyntaxKind.Autolink => "autolink"
        case LinkSyntaxKind.ExtendedAutolink => "extended-autolink"
    }
}

private func tableAlignmentName(value: TableAlignment): String {
    match (value) {
        case TableAlignment.None => "none"
        case TableAlignment.Left => "left"
        case TableAlignment.Center => "center"
        case TableAlignment.Right => "right"
    }
}

private func hardBreakKindName(value: HardBreakKind): String {
    match (value) {
        case HardBreakKind.Backslash => "backslash"
        case HardBreakKind.Spaces => "spaces"
    }
}

private func eventIsDefinitionList(payload: ArenaNodePayload): Bool {
    if (let ArenaNodePayload.CustomValue(_, _, _, custom) <- payload) {
        if (let value: DefinitionListPayload <- custom) {
            if (let DefinitionListRole.List <- value.role) {
                return true
            }
        }
    }
    false
}
