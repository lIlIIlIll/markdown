package markdown

/** Caller-selected execution policy for the Markdown-to-HTML convenience path. */
public enum HtmlExecutionMode {
    | FullAst
    | PreferFused
    | RequireFused
}

/** Execution path that actually produced an HtmlExecutionResult. */
public enum HtmlExecutionPath {
    | FullAst
    | Fused
}

public class HtmlExecutionResult {
    public let html: String
    public let path: HtmlExecutionPath

    public init(html: String, path: HtmlExecutionPath) {
        this.html = html
        this.path = path
    }
}

extend MarkdownEngine {
    /**
     * Renders source with an explicit execution policy. The fused path is used
     * only when a conservative preflight proves that direct lowering is
     * semantically identical. It never silently disables processors or syntax.
     */
    public func renderHtml(source: String, mode!: HtmlExecutionMode = HtmlExecutionMode.FullAst,
        options!: HtmlOptions = HtmlOptions.safe(), cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()): HtmlExecutionResult {
        match (mode) {
            case HtmlExecutionMode.FullAst => HtmlExecutionResult(
                htmlRenderer(options: options).render(parse(source, cancellation: cancellation, budget: budget).document,
                    cancellation: cancellation, budget: budget), HtmlExecutionPath.FullAst)
            case HtmlExecutionMode.PreferFused => match (renderFusedPlain(source, cancellation, budget)) {
                case Some(value) => HtmlExecutionResult(value, HtmlExecutionPath.Fused)
                case None => HtmlExecutionResult(
                    htmlRenderer(options: options).render(parse(source, cancellation: cancellation, budget: budget).document,
                        cancellation: cancellation, budget: budget), HtmlExecutionPath.FullAst)
            }
            case HtmlExecutionMode.RequireFused => match (renderFusedPlain(source, cancellation, budget)) {
                case Some(value) => HtmlExecutionResult(value, HtmlExecutionPath.Fused)
                case None => throw MarkdownException(MarkdownErrorCode.RenderFailure,
                    "source or configured dialect requires the full AST execution path", phase: "fused_preflight")
            }
        }
    }

    private func renderFusedPlain(source: String, cancellation: CancellationToken,
        budget: OperationBudget): ?String {
        if (dialect.parserHotPlan.hasInlineDsl || dialect.parserHotPlan.hasBlockDsl ||
            dialect.parserHotPlan.hasInlineSpi || dialect.parserHotPlan.hasDocumentProcessors ||
            dialect.rendererHotPlan.hasCustomRules) {
            return None
        }
        if (source.size > limits.maximumInputBytes) {
            throw LimitExceededException("input_bytes", limits.maximumInputBytes, source.size, "input")
        }
        budget.consumeScan(steps: source.size)
        if (!fusedPlainPreflight(source, limits.maximumLineBytes)) {
            return None
        }
        cancellation.throwIfCancelled(phase: "fused_render")
        let out = StringBuilder()
        var paragraphOpen = false
        var lineStart: Int64 = 0
        var index: Int64 = 0
        while (index <= source.size) {
            if (index < source.size && source[index] != 10 && source[index] != 13) {
                index++
                continue
            }
            let line = source[lineStart..index]
            if (line.isEmpty()) {
                if (paragraphOpen) {
                    fusedWrite(out, "</p>\n", budget)
                    paragraphOpen = false
                }
            } else {
                if (!paragraphOpen) {
                    budget.consumeRenderedNode(count: 2)
                    fusedWrite(out, "<p>", budget)
                    paragraphOpen = true
                } else {
                    fusedWrite(out, "\n", budget)
                }
                fusedWrite(out, fusedEscapeText(line), budget)
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
            fusedWrite(out, "</p>\n", budget)
        }
        Some(out.toString())
    }
}

private func fusedPlainPreflight(source: String, maximumLineBytes: Int64): Bool {
    var lineStart: Int64 = 0
    var index: Int64 = 0
    while (index < source.size) {
        let byte = source[index]
        if (byte == 0 || fusedMarkdownSpecial(byte)) {
            return false
        }
        if (byte == 10 || byte == 13) {
            if (index - lineStart > maximumLineBytes) {
                throw LimitExceededException("line_bytes", maximumLineBytes, index - lineStart, "line_scan")
            }
            if (index > lineStart && (source[lineStart] == b' ' || source[lineStart] == 9 ||
                source[index - 1] == b' ' || source[index - 1] == 9)) {
                return false
            }
            if (byte == 13 && index + 1 < source.size && source[index + 1] != 10) {
                return false
            }
            if (byte == 13) {
                index++
            }
            index++
            lineStart = index
            continue
        }
        index++
    }
    if (source.size - lineStart > maximumLineBytes) {
        throw LimitExceededException("line_bytes", maximumLineBytes, source.size - lineStart, "line_scan")
    }
    if (source.size > lineStart && (source[lineStart] == b' ' || source[lineStart] == 9 ||
        source[source.size - 1] == b' ' || source[source.size - 1] == 9)) {
        return false
    }
    true
}

private func fusedMarkdownSpecial(byte: Byte): Bool {
    byte == b'\\' || byte == b'`' || byte == b'*' || byte == b'_' || byte == b'{' || byte == b'}' ||
        byte == b'[' || byte == b']' || byte == b'(' || byte == b')' || byte == b'<' || byte == b'>' ||
        byte == b'&' || byte == b'#' || byte == b'+' || byte == b'-' || byte == b'.' || byte == b'!' ||
        byte == b'|' || byte == b'~' || byte == b':'
}

private func fusedWrite(out: StringBuilder, value: String, budget: OperationBudget): Unit {
    budget.consumeOutput(bytes: value.size)
    out.append(value)
}

private func fusedEscapeText(value: String): String {
    let out = StringBuilder()
    var start: Int64 = 0
    var index: Int64 = 0
    while (index < value.size) {
        let replacement = match (value[index]) {
            case b'&' => "&amp;"
            case b'<' => "&lt;"
            case b'>' => "&gt;"
            case b'\"' => "&quot;"
            case _ => ""
        }
        if (!replacement.isEmpty()) {
            if (start < index) {
                out.append(value[start..index])
            }
            out.append(replacement)
            index++
            start = index
        } else {
            index++
        }
    }
    if (start < value.size) {
        out.append(value[start..value.size])
    }
    out.toString()
}
