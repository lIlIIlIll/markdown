package markdown

private let FUSED_SCAN_CANCELLATION_BYTES: Int64 = 1024

/** Internal deterministic observation point for bounded fused execution scans.
 * Production cancellation remains owned by the CancellationToken. */
internal interface FusedScanCheckpointObserver {
    /** 在 fused scan checkpoint 处回调，用于测试注入观察点。
     * @param phase 当前扫描阶段名称。
     * @param bytesProcessed 已处理的字节数。
     */
    func onFusedScanCheckpoint(phase: String, bytesProcessed: Int64): Unit
}

/** Markdown source 到 HTML convenience path 的调用方执行策略。 */
public enum HtmlExecutionMode {
    /** 总是构建完整 AST 后渲染。 */
    | FullAst
    /** 保守 preflight 通过时优先 fused path，否则回退完整 AST。 */
    | PreferFused
    /** 只接受 fused path；无法证明等价时抛出 `RenderFailure`。 */
    | RequireFused
}

/** 实际生成 `HtmlExecutionResult` 的执行路径。 */
public enum HtmlExecutionPath {
    /** 完整 AST 渲染路径。 */
    | FullAst
    /** fused scan 直接 lowering 路径。 */
    | Fused
}

/** 包含 HTML 文本和实际执行路径的结果。 */
public class HtmlExecutionResult {
    /** 渲染得到的 HTML 文本。 */
    public let html: String
    /** 实际采用的执行路径。 */
    public let path: HtmlExecutionPath

    /**
     * 创建执行结果。
     * @param html 渲染得到的 HTML 文本。
     * @param path 实际采用的执行路径。
     */
    public init(html: String, path: HtmlExecutionPath) {
        this.html = html
        this.path = path
    }
}

extend MarkdownEngine {
    /**
     * 按显式策略将 source 渲染为 HTML。
     *
     * `PreferFused` 只有在保守 preflight 证明直接 lowering 与完整 AST 路径等价时才
     * 使用 fused path；否则回退 `FullAst`。`RequireFused` 在无法证明等价时抛出
     * `RenderFailure`，不会静默禁用 syntax 或 document processor。
     * @param source 待渲染的 Markdown 文本。
     * @param mode 执行策略，默认完整 AST。
     * @param options HTML 渲染选项，默认安全策略。
     * @param cancellation 协作式取消信号。
     * @param budget 单次渲染的操作预算。
     * @return 包含 HTML 与实际执行路径的结果。
     * @throws LimitExceededException 输入或输出超过上限时。
     * @throws MarkdownException 取消、预算耗尽，或 `RequireFused` 无法证明等价时。
     */
    public func renderHtml(source: String, mode!: HtmlExecutionMode = HtmlExecutionMode.FullAst,
        options!: HtmlOptions = HtmlOptions.safe(), cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()): HtmlExecutionResult {
        let noObserver: ?FusedScanCheckpointObserver = None
        renderHtmlInternal(source, mode, options, cancellation, budget, noObserver)
    }

    internal func renderHtmlWithFusedScanObserver(source: String, mode: HtmlExecutionMode, options: HtmlOptions,
        cancellation: CancellationToken, budget: OperationBudget, observer: FusedScanCheckpointObserver): HtmlExecutionResult {
        renderHtmlInternal(source, mode, options, cancellation, budget, Some(observer))
    }

    private func renderHtmlInternal(source: String, mode: HtmlExecutionMode, options: HtmlOptions,
        cancellation: CancellationToken, budget: OperationBudget, observer: ?FusedScanCheckpointObserver): HtmlExecutionResult {
        match (mode) {
            case HtmlExecutionMode.FullAst => HtmlExecutionResult(
                htmlRenderer(options: options).render(parse(source, cancellation: cancellation, budget: budget).document,
                    cancellation: cancellation, budget: budget), HtmlExecutionPath.FullAst)
            case HtmlExecutionMode.PreferFused => match (renderFusedPlain(source, cancellation, budget, observer)) {
                case Some(value) => HtmlExecutionResult(value, HtmlExecutionPath.Fused)
                case None => HtmlExecutionResult(
                    htmlRenderer(options: options).render(
                        parse(source, cancellation: cancellation, budget: budget).document, cancellation: cancellation,
                        budget: budget), HtmlExecutionPath.FullAst)
            }
            case HtmlExecutionMode.RequireFused => match (renderFusedPlain(source, cancellation, budget, observer)) {
                case Some(value) => HtmlExecutionResult(value, HtmlExecutionPath.Fused)
                case None => throw MarkdownException(MarkdownErrorCode.RenderFailure,
                    "source or configured dialect requires the full AST execution path", phase: "fused_preflight")
            }
        }
    }

    private func renderFusedPlain(source: String, cancellation: CancellationToken, budget: OperationBudget,
        observer: ?FusedScanCheckpointObserver): ?String {
        cancellation.throwIfCancelled(phase: "fused_render")
        if (dialect.parserHotPlan.hasInlineDsl || dialect.parserHotPlan.hasBlockDsl || dialect
            .parserHotPlan
            .hasInlineSpi || dialect.requiresFullAst() || dialect.rendererHotPlan.hasCustomRules) {
            return None
        }
        if (source.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, source.size, "input")
        }
        if (!fusedPlainPreflight(source, limits.maximumLineBytes, cancellation, budget, observer)) {
            return None
        }
        let out = StringBuilder()
        var paragraphOpen = false
        var lineStart: Int64 = 0
        var index: Int64 = 0
        var lineScanCheckpoint: Int64 = 0
        while (index <= source.size) {
            if (index < source.size && source[index] != 10 && source[index] != 13) {
                index++
                if (index - lineScanCheckpoint >= FUSED_SCAN_CANCELLATION_BYTES) {
                    fusedObserveScanCheckpoint("line_scan", index, cancellation, observer)
                    lineScanCheckpoint = index
                }
                continue
            }
            cancellation.throwIfCancelled(phase: "fused_render")
            let lineBytes = index - lineStart
            if (lineBytes > limits.maximumLiteralBytes) {
                throw LimitExceededException("literal_bytes", limits.maximumLiteralBytes, lineBytes, "fused_render")
            }
            if (lineBytes == 0) {
                if (paragraphOpen) {
                    fusedWrite(out, "</p>\n", budget, limits.maximumOutputBytes)
                    paragraphOpen = false
                }
            } else {
                if (!paragraphOpen) {
                    budget.consumeRenderedNode(count: 2)
                    fusedWrite(out, "<p>", budget, limits.maximumOutputBytes)
                    paragraphOpen = true
                } else {
                    fusedWrite(out, "\n", budget, limits.maximumOutputBytes)
                }
                fusedWriteEscapedTextRange(out, source, lineStart, index, cancellation, budget,
                    limits.maximumOutputBytes, observer)
            }
            if (index == source.size) {
                break
            }
            if (source[index] == 13 && index + 1 < source.size && source[index + 1] == 10) {
                index++
            }
            index++
            lineStart = index
            cancellation.throwIfCancelled(phase: "fused_render")
        }
        if (paragraphOpen) {
            cancellation.throwIfCancelled(phase: "fused_render")
            fusedWrite(out, "</p>\n", budget, limits.maximumOutputBytes)
        }
        Some(out.toString())
    }
}

private func fusedPlainPreflight(source: String, maximumLineBytes: Int64, cancellation: CancellationToken,
    budget: OperationBudget, observer: ?FusedScanCheckpointObserver): Bool {
    var lineStart: Int64 = 0
    var index: Int64 = 0
    var accounted: Int64 = 0
    while (index < source.size) {
        let byte = source[index]
        if (byte == 0 || fusedMarkdownSpecial(byte)) {
            index++
            let _ = fusedAccountPreflightScan(index, accounted, true, cancellation, budget, observer)
            return false
        }
        if (byte == 10 || byte == 13) {
            if (index - lineStart > maximumLineBytes) {
                let _ = fusedAccountPreflightScan(index + 1, accounted, true, cancellation, budget, observer)
                throw LimitExceededException("line_bytes", maximumLineBytes, index - lineStart, "line_scan")
            }
            if (index > lineStart && (source[lineStart] == b' ' || source[lineStart] == 9 || source[index - 1] == b' ' ||
                source[index - 1] == 9)) {
                let _ = fusedAccountPreflightScan(index + 1, accounted, true, cancellation, budget, observer)
                return false
            }
            if (byte == 13) {
                // Account/check the carriage return before inspecting the
                // lookahead byte, keeping every cancellation interval bounded.
                accounted = fusedAccountPreflightScan(index + 1, accounted, false, cancellation, budget, observer)
                if (index + 1 < source.size) {
                    if (source[index + 1] != 10) {
                        let _ = fusedAccountPreflightScan(index + 2, accounted, true, cancellation, budget, observer)
                        return false
                    }
                    index += 2
                } else {
                    index++
                }
            } else {
                index++
            }
            lineStart = index
            accounted = fusedAccountPreflightScan(index, accounted, false, cancellation, budget, observer)
            continue
        }
        index++
        accounted = fusedAccountPreflightScan(index, accounted, false, cancellation, budget, observer)
    }
    accounted = fusedAccountPreflightScan(source.size, accounted, true, cancellation, budget, observer)
    if (source.size - lineStart > maximumLineBytes) {
        throw LimitExceededException("line_bytes", maximumLineBytes, source.size - lineStart, "line_scan")
    }
    if (source.size > lineStart && (source[lineStart] == b' ' || source[lineStart] == 9 || source[source.size - 1] ==
        b' ' || source[source.size - 1] == 9)) {
        return false
    }
    true
}

private func fusedAccountPreflightScan(processed: Int64, accounted: Int64, force: Bool, cancellation: CancellationToken,
    budget: OperationBudget, observer: ?FusedScanCheckpointObserver): Int64 {
    let pending = processed - accounted
    if (pending <= 0 || (!force && pending < FUSED_SCAN_CANCELLATION_BYTES)) {
        return accounted
    }
    budget.consumeScan(steps: pending)
    if (pending >= FUSED_SCAN_CANCELLATION_BYTES) {
        fusedObserveScanCheckpoint("preflight", processed, cancellation, observer)
    } else {
        cancellation.throwIfCancelled(phase: "fused_render")
    }
    processed
}

private func fusedObserveScanCheckpoint(phase: String, processed: Int64, cancellation: CancellationToken,
    observer: ?FusedScanCheckpointObserver): Unit {
    if (let Some(value) <- observer) {
        value.onFusedScanCheckpoint(phase, processed)
    }
    cancellation.throwIfCancelled(phase: "fused_render")
}

private func fusedMarkdownSpecial(byte: Byte): Bool {
    byte == b'\\' || byte == b'`' || byte == b'*' || byte == b'_' || byte == b'{' || byte == b'}' || byte == b'[' ||
        byte == b']' || byte == b'(' || byte == b')' || byte == b'<' || byte == b'>' || byte == b'&' || byte == b'#' ||
        byte == b'+' || byte == b'-' || byte == b'.' || byte == b'!' || byte == b'|' || byte == b'~' || byte == b':'
}

private func fusedWrite(out: StringBuilder, value: String, budget: OperationBudget, maximumOutputBytes: Int64): Unit {
    let observed = budget.usedOutputBytes() + value.size
    if (observed > maximumOutputBytes) {
        throw LimitExceededException("output_bytes", maximumOutputBytes, observed, "fused_render")
    }
    budget.consumeOutput(bytes: value.size)
    out.append(value)
}

private func fusedWriteRange(out: StringBuilder, value: String, start: Int64, end: Int64, budget: OperationBudget,
    maximumOutputBytes: Int64): Unit {
    let bytes = end - start
    let observed = budget.usedOutputBytes() + bytes
    if (observed > maximumOutputBytes) {
        throw LimitExceededException("output_bytes", maximumOutputBytes, observed, "fused_render")
    }
    budget.consumeOutput(bytes: bytes)
    out.append(value[start..end])
}

private func fusedWriteEscapedTextRange(out: StringBuilder, value: String, rangeStart: Int64, rangeEnd: Int64,
    cancellation: CancellationToken, budget: OperationBudget, maximumOutputBytes: Int64,
    observer: ?FusedScanCheckpointObserver): Unit {
    var start = rangeStart
    var index = rangeStart
    var checkpoint = rangeStart
    while (index < rangeEnd) {
        let replacement = match (value[index]) {
            case b'&' => "&amp;"
            case b'<' => "&lt;"
            case b'>' => "&gt;"
            case b'\"' => "&quot;"
            case _ => ""
        }
        if (!replacement.isEmpty()) {
            if (start < index) {
                fusedWriteRange(out, value, start, index, budget, maximumOutputBytes)
            }
            fusedWrite(out, replacement, budget, maximumOutputBytes)
            index++
            start = index
        } else {
            index++
        }
        if (index - checkpoint >= FUSED_SCAN_CANCELLATION_BYTES) {
            fusedObserveScanCheckpoint("output_scan", index - rangeStart, cancellation, observer)
            checkpoint = index
        }
    }
    cancellation.throwIfCancelled(phase: "fused_render")
    if (start < rangeEnd) {
        fusedWriteRange(out, value, start, rangeEnd, budget, maximumOutputBytes)
    }
}
