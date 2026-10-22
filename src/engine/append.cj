package markdown.engine

import markdown.core.{CancellationToken, Diagnostic, DiagnosticFix, ImmutableArray, LimitExceededException, 
    MarkdownException, NodeConstructionBudget, NodeId, NodeLineage, NodeRef, OperationBudget, ParseResult, 
    ReferenceDefinition, SourceBuffer, SourceSpan, Utf8Policy}
import std.collection.*
import std.sort.sort

/** 追加会话的累计上限；不承诺常量内存，也不保留历史更新。 */
public class AppendLimits {
    /** 尚未结构闭合的原始输入字节上限。 */
    public let maximumPendingBytes: Int64
    /** 会话保留的原始输入字节上限；解码与 AST 存储另受节点/扫描限制。 */
    public let maximumRetainedInputBytes: Int64
    /** 包含推测、回滚、行内解析与最终组装的节点构造步数上限。 */
    public let maximumNodeConstructionSteps: Int64
    /** 累计 patch 构造步数上限。 */
    public let maximumPatchSteps: Int64
    /** 更新批次数上限；最后一个名额留给 Complete 或 Failed。 */
    public let maximumUpdateBatches: Int64

    /**
     * 创建会话上限；每个参数必须为正数。
     * @param maximumPendingBytes 尚未结构闭合的原始输入 byte 上限，必须为正。
     * @param maximumRetainedInputBytes 会话保留的原始输入 byte 上限，必须为正。
     * @param maximumNodeConstructionSteps 包含推测和回滚的累计节点构造步数上限，必须为正。
     * @param maximumPatchSteps 累计构造更新操作的步数上限，必须为正。
     * @param maximumUpdateBatches 累计更新批次数上限，必须为正；最后一个名额留给终态。
     */
    public init(maximumPendingBytes!: Int64 = 32 * 1024 * 1024, maximumRetainedInputBytes!: Int64 = 32 * 1024 * 1024,
        maximumNodeConstructionSteps!: Int64 = 16000000, maximumPatchSteps!: Int64 = 4000000,
        maximumUpdateBatches!: Int64 = 4000000) {
        for (value in [maximumPendingBytes, maximumRetainedInputBytes, maximumNodeConstructionSteps, maximumPatchSteps,
            maximumUpdateBatches]) {
            if (value <= 0) {
                throw IllegalArgumentException("append limits must be positive")
            }
        }
        this.maximumPendingBytes = maximumPendingBytes
        this.maximumRetainedInputBytes = maximumRetainedInputBytes
        this.maximumNodeConstructionSteps = maximumNodeConstructionSteps
        this.maximumPatchSteps = maximumPatchSteps
        this.maximumUpdateBatches = maximumUpdateBatches
    }
}

/** 一个结构闭合的顶层块。临时块尚未完成全局引用和扩展处理，不是 ParseResult。 */
public class AppendBlockView {
    /** 局部不可变 fragment 或最终 Document 内的节点。 */
    public let node: NodeRef
    /** 与 node 同属一个来源视图的输入。 */
    public let source: SourceBuffer
    /** 局部来源在整个输入中的 byte 偏移；最终视图为 0。 */
    public let sourceOffset: Int64
    /** 是否已经完成全部文档处理和绑定。 */
    public let finalSemantics: Bool
    /**
     * 节点的全局原始 byte 范围；生成节点可以没有范围。
     * @return 换算为全文原始 byte 坐标的半开范围；生成节点为 None。
     */
    public prop sourceSpan: ?SourceSpan {
        get() {
            node.span.map({span => SourceSpan(span.startByte + sourceOffset, span.endByte + sourceOffset)})
        }
    }
    /**
     * 关联块节点、局部来源及全局偏移，创建不可变块视图。
     * @param node 属于局部 fragment 或最终文档的块节点。
     * @param source 与当前节点或解析输入归属一致的来源缓冲。
     * @param offset 局部来源起点在全文原始输入中的 byte 偏移。
     * @param finalSemantics 节点是否已完成全局引用、整文扩展与绑定。
     */
    protected init(node: NodeRef, source: SourceBuffer, offset: Int64, finalSemantics: Bool) {
        this.node = node
        this.source = source
        sourceOffset = offset
        this.finalSemantics = finalSemantics
    }
}

/** 原子批次中的顶层块操作。Replace/Remove 的目标从 fromVersion 查找。 */
public enum AppendChange {
    /** 将块追加到剩余块之后。 */
    | Append(AppendBlockView)
    /** 用一个块替换目标在旧版本中的位置；新块可具有不同身份。 */
    | Replace(NodeId, AppendBlockView)
    /** 删除旧版本中的目标。 */
    | Remove(NodeId)
    /** 只在 Complete 批次最后出现；包含唯一的完整成功结果。 */
    | Bind(ParseResult)
}

/** 待定输入与终态；Failed 不包含伪造的成功文档。 */
public enum AppendState {
    /** 可以继续追加；已交付的块仍可在 finish 时修订。 */
    | AwaitingInput
    /** 全部块已经完成处理与绑定。 */
    | Complete
    /** 致命失败，会话不可继续。 */
    | Failed(MarkdownException)
}

/** 真实工作计数；节点构造步数不等同于堆分配次数。 */
public class AppendProgress {
    /** 已接受的原始输入字节数。 */
    public let inputBytes: Int64
    /** 尚待结构闭合的输入字节数。 */
    public let pendingBytes: Int64
    /** 累计节点构造步数，回滚不退还。 */
    public let nodeConstructionSteps: Int64
    /** 累计扫描步数。 */
    public let scanSteps: Int64
    /** 已经最终解析的待定行内单元数。 */
    public let resolvedInlineTasks: Int64
    /** 累计 patch 构造步数。 */
    public let patchSteps: Int64
    /**
     * 记录追加驱动已完成工作的累计计数。
     * @param inputBytes 已经接受的原始输入 byte 总数。
     * @param pendingBytes 尚未结构闭合的原始输入 byte 数。
     * @param nodeConstructionSteps 累计节点构造步数，回滚不退还。
     * @param scanSteps 累计扫描工作步数。
     * @param resolvedInlineTasks 已最终解析的待定行内单元数量。
     * @param patchSteps 累计更新操作构造步数。
     */
    protected init(inputBytes: Int64, pendingBytes: Int64, nodeConstructionSteps: Int64, scanSteps: Int64,
        resolvedInlineTasks: Int64, patchSteps: Int64) {
        this.inputBytes = inputBytes
        this.pendingBytes = pendingBytes
        this.nodeConstructionSteps = nodeConstructionSteps
        this.scanSteps = scanSteps
        this.resolvedInlineTasks = resolvedInlineTasks
        this.patchSteps = patchSteps
    }
}

/** 单会话内按序消费的不可变原子更新；缺失、重复或过期批次必须拒绝并重新开始会话。 */
public class AppendUpdateBatch {
    /** 进程内原子更新契约版本；当前为 1。 */
    public let protocolVersion: Int64 = 1
    /** 进程内唯一会话身份，不是跨进程持久化或网络协议。 */
    public let sessionId: Int64
    /** 此批次依赖的版本。 */
    public let fromVersion: Int64
    /** 应用此批次后的版本，协议 1 中总是 fromVersion + 1。 */
    public let toVersion: Int64
    /** 从 1 开始连续递增；每次 feed/finish 产生一批。 */
    public let sequence: Int64
    /** 更新后的待定或终结状态。 */
    public let state: AppendState
    /** 有序操作，必须整体应用。 */
    public let changes: ImmutableArray<AppendChange>
    /** 本次操作完成后的累计计数。 */
    public let progress: AppendProgress
    /**
     * 构造紧接给定版本的原子更新，并复制操作数组。
     * @param sessionId 进程内唯一的追加会话身份。
     * @param version 此批更新依赖的旧版本，目标版本和序号均为该值加一。
     * @param state 此批更新后的待定或终态。
     * @param changes 必须按顺序作为整体应用的更新操作。
     * @param progress 此批操作完成后的累计工作计数。
     */
    protected init(sessionId: Int64, version: Int64, state: AppendState, changes: Array<AppendChange>,
        progress: AppendProgress) {
        this.sessionId = sessionId
        fromVersion = version
        toVersion = version + 1
        sequence = version + 1
        this.state = state
        this.changes = ImmutableArray<AppendChange>(changes)
        this.progress = progress
    }
}

/**
 * 为 engine 提供有版本更新协议的追加输入入口。
 */
extend MarkdownEngine {
    /**
     *  创建实际在 feed 中解析并交付结构闭合块的追加会话。所有上限跨 feed 累计。
     * 全局引用、文档处理器和绑定在 finish 时完成；不重新执行全文块解析。
     * @param utf8Policy 跨块 UTF-8 解码策略；默认 Strict，未完成序列在 finish 时处理。
     * @param cancellation 本次操作共用的协作式取消信号。
     * @param budget 本次操作跨阶段累计使用的预算；不与其他操作共享。
     * @param limits 会话的累计资源上限。
     * @return 新的顺序追加会话；feed 可返回临时块，完整结果仅由最终 Bind 提供。
     */
    public func newAppendSession(utf8Policy!: Utf8Policy = Utf8Policy.Strict,
        cancellation!: CancellationToken = CancellationToken.none(), budget!: OperationBudget = OperationBudget.safe(),
        limits!: AppendLimits = AppendLimits()): AppendInputSession {
        AppendInputSession(this, utf8Policy, cancellation, budget, limits)
    }
}

/**
 * 顺序使用的追加会话；feed 在有界工作下解析结构闭合的顶层块。
 *
 * 临时块尚未完成全局引用、整文扩展与绑定，可以在 finish 时被替换或删除。
 * 完整 ParseResult 只出现在所有阶段成功后的 Complete 批次末尾 Bind 中。
 * MarkdownException 通过 Failed 更新返回；终态后的调用抛出 IllegalStateException。
 * 资源上限与预算跨 feed 累计，不承诺常量内存；同一会话不支持并发调用。
 *
 * @example 原子消费追加更新 {run}
 * ```cangjie
 * let session = MarkdownEngine.builder().build().newAppendSession()
 * let replica = AppendReplica()
 * replica.apply(session.feed("# title\n\n"))
 * replica.apply(session.finish())
 * println(replica.result.getOrThrow().diagnostics.size)
 * ```
 * ```output
 * 0
 * ```
 */
public class AppendInputSession {
    private let engine: MarkdownEngine
    private let utf8Policy: Utf8Policy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let limits: AppendLimits
    private let lineage = NodeLineage()
    private let construction: NodeConstructionBudget
    private let raw: RawBlockEventSession
    private var input = ArrayList<Byte>()
    private let fragments = ArrayList<CapturedDraft>()
    private let blockIds = ArrayList<NodeId>()
    private let definitions = ArrayList<ReferenceDefinition>()
    private let effectiveLabels = HashSet<String>()
    private var acceptedInputBytes: Int64 = 0
    private var version: Int64 = 0
    private var patchSteps: Int64 = 0
    private var resolvedTasks: Int64 = 0
    private var terminal = false

    /**
     * 以固定 engine、解码策略和累计预算启动追加驱动。
     * @param engine 固定 profile、dialect 和结构上限的 engine。
     * @param utf8Policy 跨块 UTF-8 解码策略；默认 Strict，未完成序列在 finish 时处理。
     * @param cancellation 本次操作共用的协作式取消信号。
     * @param budget 本次操作跨阶段累计使用的预算；不与其他操作共享。
     * @param limits 会话的累计资源上限。
     */
    protected init(engine: MarkdownEngine, utf8Policy: Utf8Policy, cancellation: CancellationToken,
        budget: OperationBudget, limits: AppendLimits) {
        this.engine = engine
        this.utf8Policy = utf8Policy
        this.cancellation = cancellation
        this.budget = budget
        this.limits = limits
        construction = NodeConstructionBudget(limits.maximumNodeConstructionSteps)
        raw = RawBlockEventSession(engine, utf8Policy, cancellation, budget, draftLineage: Some(lineage),
            constructionBudget: Some(construction))
    }

    /**
     * 追加文本。String 和 byte 路径使用同一驱动。
     * @param chunk 本次追加的文本或 UTF-8 byte 片段。
     * @return 本次原子更新；MarkdownException 以 Failed 终态返回，不附带成功结果。
     */
    public func feed(chunk: String): AppendUpdateBatch {
        ensureOpen()
        try {
            preflightFeed(chunk.size)
            feedPrepared(chunk.toArray())
        } catch (error: MarkdownException) {
            failed(error)
        }
    }

    /**
     * 追加任意 UTF-8 字节片段；未完成序列可跨 feed，finish 才要求收尾。
     * @param chunk 本次追加的文本或 UTF-8 byte 片段。
     * @return 本次原子更新；MarkdownException 以 Failed 终态返回，不附带成功结果。
     */
    public func feed(chunk: Array<Byte>): AppendUpdateBatch {
        ensureOpen()
        try {
            preflightFeed(chunk.size)
            feedPrepared(chunk)
        } catch (error: MarkdownException) {
            failed(error)
        }
    }

    private func preflightFeed(count: Int64): Unit {
        cancellation.throwIfCancelled(phase: "append_input")
        if (version >= limits.maximumUpdateBatches - 1) {
            throw LimitExceededException("update_batches", limits.maximumUpdateBatches, version + 1, "append")
        }
        let maximum = min(engine.limits.maximumInputBytes, limits.maximumRetainedInputBytes)
        if (count > maximum - input.size) {
            throw LimitExceededException("retained_input_bytes", maximum, boundedAdd(input.size, count), "append_input")
        }
    }

    private func feedPrepared(chunk: Array<Byte>): AppendUpdateBatch {
        let changes = ArrayList<AppendChange>()
        var start: Int64 = 0
        var index: Int64 = 0
        // Split large caller chunks at the same line boundaries seen by byte
        // producers. Check pending before allocation, independent of chunking.
        while (index < chunk.size) {
            cancellation.throwIfCancelled(phase: "append_input")
            let available = limits.maximumPendingBytes - raw.pendingByteCount()
            if (index - start >= available) {
                throw LimitExceededException("pending_bytes", limits.maximumPendingBytes, limits.maximumPendingBytes + 1,
                    "append_input")
            }
            let byte = chunk[index]
            index++
            if (byte == b'\n' || byte == b'\r') {
                acceptSegment(chunk[start..index], changes)
                start = index
            }
        }
        if (start < chunk.size) {
            acceptSegment(chunk[start..], changes)
        }
        emit(AppendState.AwaitingInput, changes.toArray())
    }

    private func acceptSegment(bytes: Array<Byte>, changes: ArrayList<AppendChange>): Unit {
        input.add(all: bytes)
        acceptedInputBytes += bytes.size
        let _ = raw.feed(bytes)
        capture(changes)
    }

    private func capture(changes: ArrayList<AppendChange>, exposeDrafts!: Bool = true): Unit {
        for (captured in raw.takeDrafts()) {
            fragments.add(captured)
            for (definition in captured.draft.document.references.toArray()) {
                if (definitions.size >= engine.limits.maximumReferences) {
                    throw LimitExceededException("references", engine.limits.maximumReferences, definitions.size + 1,
                        "append_references")
                }
                definitions.add(
                    ReferenceDefinition(definition.labelRaw, definition.labelNormalized, definition.destinationRaw,
                        definition.destination, definition.titleRaw, definition.title,
                        shiftAppendSpan(definition.sourceSpan, captured.offset),
                        isEffective: effectiveLabels.add(definition.labelNormalized)))
            }
            if (!exposeDrafts) {
                continue
            }
            for (node in captured.draft.document.root().children().toArray()) {
                consumePatch()
                blockIds.add(node.nodeId)
                changes.add(AppendChange.Append(AppendBlockView(node, captured.draft.source, captured.offset, false)))
            }
        }
    }

    /**
     * 关闭输入，解析待定行内单元一次，组装 AST，并运行共享的完整文档处理与绑定。
     * @return 包含最终修订和唯一 Bind 的 Complete 批次，或不含成功文档的 Failed 批次。
     */
    public func finish(): AppendUpdateBatch {
        ensureOpen()
        try {
            cancellation.throwIfCancelled(phase: "append_finish")
            let changes = ArrayList<AppendChange>()
            let _ = raw.finish()
            // Newly closed blocks need not first be exposed provisionally in
            // the terminal update; reconcile all old targets against its base.
            let oldCount = blockIds.size
            capture(changes, exposeDrafts: false)
            let decoded = decodeUtf8Input(input.toArray(), utf8Policy)
            let assembler = AppendTreeAssembler(engine, decoded.source, lineage, budget, cancellation,
                definitions.toArray(), constructionBudget: Some(construction))
            let diagnostics = ArrayList<Diagnostic>()
            for (captured in fragments) {
                assembler.append(captured.draft, captured.offset)
                for (diagnostic in captured.draft.diagnostics) {
                    diagnostics.add(shiftAppendDiagnostic(diagnostic, captured.offset))
                }
            }
            let document = assembler.finish()
            resolvedTasks = assembler.resolvedInlineTasks()
            diagnostics.add(all: assembler.inlineDiagnostics())
            sortAppendDiagnostics(diagnostics)
            let completeDiagnostics = ArrayList<Diagnostic>(decoded.diagnostics)
            completeDiagnostics.add(all: diagnostics)
            let result = finishParsedDocument(document, decoded.source, completeDiagnostics, engine.profile,
                engine.dialect, engine.bindingOptions, engine.limits, budget, cancellation, requiresBinding: true)
            let roots = result.document.root().children()
            for (index in 0..min(oldCount, roots.size)) {
                consumePatch()
                changes.add(AppendChange.Replace(blockIds[index], AppendBlockView(roots[index], result.source, 0, true)))
            }
            for (index in roots.size..oldCount) {
                consumePatch();
                changes.add(AppendChange.Remove(blockIds[index]))
            }
            for (index in oldCount..roots.size) {
                consumePatch()
                changes.add(AppendChange.Append(AppendBlockView(roots[index], result.source, 0, true)))
            }
            consumePatch()
            changes.add(AppendChange.Bind(result))
            terminal = true
            releaseDrafts()
            emit(AppendState.Complete, changes.toArray())
        } catch (error: MarkdownException) {
            failed(error)
        }
    }

    private func consumePatch(): Unit {
        if (patchSteps >= limits.maximumPatchSteps) {
            throw LimitExceededException("patch_steps", limits.maximumPatchSteps, patchSteps + 1, "append")
        }
        patchSteps++
    }

    private func emit(state: AppendState, changes: Array<AppendChange>): AppendUpdateBatch {
        let batch = AppendUpdateBatch(lineage.identity, version, state, changes,
            AppendProgress(acceptedInputBytes, if (terminal) {
                0
            } else {
                raw.pendingByteCount()
            }, construction.used, budget.usedScanSteps(), resolvedTasks, patchSteps))
        version++
        batch
    }

    private func failed(error: MarkdownException): AppendUpdateBatch {
        terminal = true
        releaseDrafts()
        emit(AppendState.Failed(error), [])
    }

    private func releaseDrafts(): Unit {
        input = ArrayList<Byte>()
        raw.abandonDrafts()
        fragments.clear()
        definitions.clear()
        effectiveLabels.clear()
        blockIds.clear()
    }

    private func ensureOpen(): Unit {
        if (terminal) {
            throw IllegalStateException("append session is already terminal")
        }
    }
}

private func boundedAdd(left: Int64, right: Int64): Int64 {
    if (right > Int64.Max - left) {
        Int64.Max
    } else {
        left + right
    }
}

internal func shiftAppendSpan(span: SourceSpan, offset: Int64): SourceSpan {
    SourceSpan(span.startByte + offset, span.endByte + offset)
}

internal func shiftAppendDiagnostic(value: Diagnostic, offset: Int64): Diagnostic {
    let related = ArrayList<SourceSpan>()
    for (span in value.relatedSpans) {
        related.add(shiftAppendSpan(span, offset))
    }
    let fixes = ArrayList<DiagnosticFix>()
    for (fix in value.fixes.toArray()) {
        fixes.add(DiagnosticFix(fix.title, shiftAppendSpan(fix.span, offset), fix.replacement))
    }
    Diagnostic(value.code, value.severity, value.message, shiftAppendSpan(value.span, offset),
        relatedSpans: related.toArray(), extensionId: value.extensionId, ruleId: value.ruleId, fixes: fixes.toArray())
}

private func sortAppendDiagnostics(values: ArrayList<Diagnostic>): Unit {
    // Parser diagnostics are emitted in source order. Deferred inline tasks
    // finish later; restore that order before appending binder diagnostics.
    sort(values, lessThan: {left, right => left.span.startByte < right.span.startByte}, stable: true)
}

internal func shiftAppendException(error: MarkdownException, offset: Int64): MarkdownException {
    if (offset == 0 || error.span.isNone()) {
        return error
    }
    let span = error.span.map({value => shiftAppendSpan(value, offset)})
    if (let limit: LimitExceededException <- error) {
        return LimitExceededException(limit.limitKind, limit.configuredLimit, limit.observedValue, limit.phase,
            span: span, extensionId: limit.extensionId)
    }
    MarkdownException(error.code, error.message, phase: error.phase, span: span)
}
