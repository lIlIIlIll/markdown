package markdown

import std.collection.*

/** Source-driven event semantics. Resolved mode performs a reference-index
 * pass before semantic lowering; raw block mode intentionally does not promise
 * reference resolution and is available incrementally through a session. */
public enum MarkdownEventMode {
    | ResolvedEventMode
    | RawBlockEventMode
}

public enum MarkdownSourceEventKind {
    | DocumentStart
    | DocumentEnd
    | BlockStart
    | BlockEnd
    | InlineStart
    | InlineEnd
    | Text
}

public struct MarkdownEventAttribute {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        if (name.isEmpty()) {
            throw IllegalArgumentException("event attribute name must not be empty")
        }
        this.name = name
        this.value = value
    }
}

/** Immutable event value. It contains source identity and semantic values but
 * deliberately cannot retain a Document, NodeRef, or parser-owned node. */
public class MarkdownSourceEvent {
    public let kind: MarkdownSourceEventKind
    public let nodeKind: ?NodeKind
    public let sourceRange: ?SourceSpan
    public let textSourceRange: ?SourceSpan
    public let semanticValue: ?String
    public let attributes: ImmutableArray<MarkdownEventAttribute>
    public let finalSemantics: Bool

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

/** Streaming consumer for source events. Implementations are called in source
 * order and may process each event without retaining the full event sequence. */
public interface MarkdownEventSink {
    func onEvent(event: MarkdownSourceEvent): Unit
}

public class EventParseSummary {
    public let mode: MarkdownEventMode
    public let diagnostics: ImmutableArray<Diagnostic>
    public let emittedEvents: Int64

    public init(mode: MarkdownEventMode, diagnostics: Array<Diagnostic>, emittedEvents: Int64) {
        this.mode = mode
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
        this.emittedEvents = emittedEvents
    }
}

public class EventParseResult {
    public let mode: MarkdownEventMode
    public let events: ImmutableArray<MarkdownSourceEvent>
    public let diagnostics: ImmutableArray<Diagnostic>

    public init(mode: MarkdownEventMode, events: Array<MarkdownSourceEvent>, diagnostics: Array<Diagnostic>) {
        this.mode = mode
        this.events = ImmutableArray<MarkdownSourceEvent>(events)
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
    }
}

internal class CollectingMarkdownEventSink <: MarkdownEventSink {
    private let values = ArrayList<MarkdownSourceEvent>()

    public func onEvent(event: MarkdownSourceEvent): Unit {
        values.add(event)
    }

    func toArray(): Array<MarkdownSourceEvent> {
        values.toArray()
    }
}

internal class CountingForwardEventSink <: MarkdownEventSink {
    private let target: MarkdownEventSink
    var count: Int64 = 0

    init(target: MarkdownEventSink) {
        this.target = target
    }

    public func onEvent(event: MarkdownSourceEvent): Unit {
        count++
        target.onEvent(event)
    }
}

internal struct EventTraversalFrame {
    let node: Int64
    let exiting: Bool

    init(node: Int64, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

internal class ParserEventGroup {
    let kind: NodeKind
    let span: SourceSpan
    let explicitlyClosed: Bool
    let nodeCount: Int64
    let events: Array<MarkdownSourceEvent>

    init(kind: NodeKind, span: SourceSpan, explicitlyClosed: Bool, nodeCount: Int64, events: Array<MarkdownSourceEvent>) {
        this.kind = kind
        this.span = span
        this.explicitlyClosed = explicitlyClosed
        this.nodeCount = nodeCount
        this.events = events
    }
}

/** Low-level lowering target used by ParserSession. It reads the transient
 * parser arena directly and completes before the parser rolls that block back. */
internal class ParserEventEmitter {
    private let sink: ?MarkdownEventSink
    private let collectGroups: Bool
    private let sourceOffsetBase: Int64
    private let finalSemantics: Bool
    private let maximumNodes: Int64
    private let groups = ArrayList<ParserEventGroup>()
    private var nodeCount: Int64
    private var eventCount: Int64 = 0

    init(sink: ?MarkdownEventSink, collectGroups: Bool, sourceOffsetBase: Int64, finalSemantics: Bool,
        maximumNodes: Int64, initialNodeCount!: Int64 = 0) {
        this.sink = sink
        this.collectGroups = collectGroups
        this.sourceOffsetBase = sourceOffsetBase
        this.finalSemantics = finalSemantics
        this.maximumNodes = maximumNodes
        this.nodeCount = initialNodeCount
    }

    func emitTopLevel(nodes: ParserNodeFactory, root: Int64): Unit {
        let record = nodes.eventRecord(root)
        let span = record.span.getOrThrow()
        let before = nodeCount
        if (collectGroups) {
            let blockSink = CollectingMarkdownEventSink()
            emitSubtree(nodes, root, blockSink)
            let events = blockSink.toArray()
            groups.add(
                ParserEventGroup(record.kind, shifted(span), explicitlyClosed(nodes.eventPayload(root)),
                    nodeCount - before, events))
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

    prop emittedEvents: Int64 {
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
    /** Convenience collector. Use emitEvents() when event-array retention is
     * undesirable. Resolved mode is the default semantic contract. */
    public func parseEvents(source: String, mode!: MarkdownEventMode = MarkdownEventMode.ResolvedEventMode,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): EventParseResult {
        let sink = CollectingMarkdownEventSink()
        let summary = emitEvents(source, sink, mode: mode, cancellation: cancellation, budget: budget)
        EventParseResult(mode, sink.toArray(), summary.diagnostics.toArray())
    }

    /** Emits events directly from transient parser blocks. Resolved mode first
     * builds the reference index; raw mode intentionally skips that pass. */
    public func emitEvents(source: String, sink: MarkdownEventSink,
        mode!: MarkdownEventMode = MarkdownEventMode.ResolvedEventMode,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): EventParseSummary {
        cancellation.throwIfCancelled(phase: "input")
        if (source.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, source.size, "input")
        }
        if (dialect.parserHotPlan.hasDocumentProcessors) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure,
                "document processors require the full AST execution path", phase: "event_preflight")
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
            nativeScannerEnabledValue, noAccelerator, eventEmitter: Some(emitter)).parseEvents([], finalSemantics)
        sink.onEvent(
            MarkdownSourceEvent(MarkdownSourceEventKind.DocumentEnd, nodeKind: Some(NodeKind.DocumentNode),
                sourceRange: Some(fullSpan), finalSemantics: finalSemantics))
        EventParseSummary(mode, diagnostics, emitter.emittedEvents + 2)
    }

    /** Starts true incremental raw-block execution. feed() may return events
     * for blocks proven closed by subsequent source; finish() emits the final
     * buffered block and DocumentEnd. */
    public func newRawBlockEventSession(utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe()): RawBlockEventSession {
        RawBlockEventSession(this, utf8Policy, cancellation, budget)
    }
}

public class RawBlockEventSession {
    private let engine: MarkdownEngine
    private let utf8Policy: Utf8Policy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private var pending = ArrayList<Byte>()
    private var sourceOffset: Int64 = 0
    private var totalBytes: Int64 = 0
    private var emittedNodes: Int64 = 0
    private var started = false
    private var finished = false

    internal init(engine: MarkdownEngine, utf8Policy: Utf8Policy, cancellation: CancellationToken,
        budget: OperationBudget) {
        this.engine = engine
        this.utf8Policy = utf8Policy
        this.cancellation = cancellation
        this.budget = budget
    }

    public func feed(chunk: String): Array<MarkdownSourceEvent> {
        feed(chunk.toArray())
    }

    public func feed(chunk: Array<Byte>): Array<MarkdownSourceEvent> {
        ensureOpen()
        cancellation.throwIfCancelled(phase: "input")
        if (totalBytes + chunk.size > engine.limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", engine.limits.maximumInputBytes, totalBytes + chunk.size,
                "input")
        }
        pending.add(all: chunk)
        totalBytes += chunk.size
        drain(false)
    }

    public func finish(): Array<MarkdownSourceEvent> {
        ensureOpen()
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
        let out = ArrayList<MarkdownSourceEvent>()
        if (!started) {
            out.add(documentStart())
            started = true
        }
        let bytes = pending.toArray()
        let parseLength = if (finishing) {
            bytes.size
        } else {
            lastCompleteLineEnd(bytes)
        }
        if (parseLength <= 0) {
            return out.toArray()
        }
        if (!finishing && !rawClosureCandidate(bytes, parseLength)) {
            return out.toArray()
        }
        let parseBytes = bytes[..parseLength]
        let decoded = decodeUtf8Input(parseBytes, utf8Policy)
        let noSink: ?MarkdownEventSink = None
        let emitter = ParserEventEmitter(noSink, true, sourceOffset, false, engine.limits.maximumAstNodes,
            initialNodeCount: emittedNodes)
        let noAccelerator: ?LineScannerAccelerator = None
        let _ = ParserSession(engine.profile, engine.limits, cancellation, budget, decoded.source, engine.dialect,
            engine.nativeScannerEnabledValue, noAccelerator, eventEmitter: Some(emitter)).parseEvents(
            decoded.diagnostics, false)
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
        for (index in 0..emitCount) {
            out.add(all: groups[index].events)
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
            let retained = ArrayList<Byte>()
            var index = discard
            while (index < bytes.size) {
                retained.add(bytes[index])
                index++
            }
            pending = retained
            sourceOffset += discard
        }
        out.toArray()
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
        case ArenaNodePayload.ThematicBreakValue(_) => true
        case ArenaNodePayload.HeadingValue(_) => true
        case _ => false
    }
}

private func rawTailCloses(group: ParserEventGroup, bytes: Array<Byte>, localEnd: Int64): Bool {
    if (group.explicitlyClosed && lineBreakCount(bytes, localEnd) > 0) {
        return true
    }
    match (group.kind) {
        case NodeKind.Paragraph => lineBreakCount(bytes, localEnd) >= 2 && tailIsWhitespace(bytes, localEnd)
        case NodeKind.Table => lineBreakCount(bytes, localEnd) >= 2 && tailIsWhitespace(bytes, localEnd)
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

private func lastCompleteLineEnd(bytes: Array<Byte>): Int64 {
    var index = bytes.size - 1
    while (index >= 0) {
        if (bytes[index] == b'\n' || bytes[index] == b'\r') {
            return index + 1
        }
        index--
    }
    0
}

/** Cheap conservative trigger that prevents reparsing an unfinished long
 * paragraph on every chunk. False means no block can yet be proven closed;
 * true only requests a semantic parse and does not itself authorize emission. */
private func rawClosureCandidate(bytes: Array<Byte>, end: Int64): Bool {
    var lineStart: Int64 = 0
    var index: Int64 = 0
    while (index < end) {
        if (bytes[index] != b'\n' && bytes[index] != b'\r') {
            index++
            continue
        }
        let lineEnd = index
        var next = index + 1
        if (bytes[index] == b'\r' && next < end && bytes[next] == b'\n') {
            next++
        }
        var content = lineStart
        while (content < lineEnd && content - lineStart < 4 && bytes[content] == b' ') {
            content++
        }
        if (content == lineEnd) {
            return true
        }
        if (content - lineStart <= 3) {
            let first = bytes[content]
            if (first == b'#' || first == b'`' || first == b'~') {
                return true
            }
            if (first == b'*' || first == b'-' || first == b'_') {
                var markerCount: Int64 = 0
                var markerIndex = content
                while (markerIndex < lineEnd) {
                    if (bytes[markerIndex] == first) {
                        markerCount++
                    } else if (bytes[markerIndex] != b' ' && bytes[markerIndex] != b'\t') {
                        markerCount = 0
                        break
                    }
                    markerIndex++
                }
                if (markerCount >= 3) {
                    return true
                }
            }
        }
        lineStart = next
        index = next
    }
    false
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
