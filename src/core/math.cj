package markdown.core

/** 公式来源片段；记录容器把部分 tab 展开为空格时的精确来源。 */
public class MathSourcePart {
    /** 原始 UTF-8 范围，包含该行属于公式的换行。 */
    public let span: SourceSpan
    /** 容器规范化的原始行首空白字节数；其余字节只规范化 CRLF/CR。 */
    public let expandedPrefixBytes: Int64
    /** 上述行首空白在表达式中保留的空格数。 */
    public let expandedPrefixSpaces: Int64

    /** 创建不可变片段；非空展开只允许有界的空白前缀。
     * @param span 包含此行公式内容及所属换行的原始 UTF-8 半开范围。
     * @param expandedPrefixBytes 被容器展开的行首空白字节数，默认 0，不能超过 span 长度。
     * @param expandedPrefixSpaces 上述前缀在表达式中保留的空格数，默认 0，至多为原字节数的四倍。
     */
    public init(span: SourceSpan, expandedPrefixBytes!: Int64 = 0, expandedPrefixSpaces!: Int64 = 0) {
        if (expandedPrefixBytes < 0 || expandedPrefixBytes > span.length() || expandedPrefixSpaces < 0 ||
            (expandedPrefixSpaces / 4 + (if (expandedPrefixSpaces % 4 == 0) {
            0
        } else {
            1
        })) > expandedPrefixBytes || (expandedPrefixBytes == 0 && expandedPrefixSpaces != 0)) {
            throw IllegalArgumentException("invalid math source prefix layout")
        }
        this.span = span
        this.expandedPrefixBytes = expandedPrefixBytes
        this.expandedPrefixSpaces = expandedPrefixSpaces
    }
}

/** Math 2.0 的源语义；不包含第三方 HTML、主题或准备结果。 */
public class MathPayload <: CustomPayload {
    /** true 表示独占 block 的公式，false 表示行内公式。 */
    public let display: Bool
    /** 保留 TeX，容器前缀已移除，正文换行统一为 LF。 */
    public let expression: String
    /** 表达式各源片段的原始 UTF-8 范围；容器前缀可使片段不相邻。 */
    public let expressionSource: ImmutableArray<MathSourcePart>
    /** 原始 `$` 或 `$$` opener。 */
    public let openerSpan: SourceSpan
    /** 原始 `$` 或 `$$` closer。 */
    public let closerSpan: SourceSpan

    /** 创建公式语义；绑定器验证类型、原文、片段顺序与 delimiter。
     * @param display true 为块公式，false 为行内公式。
     * @param expression 移除容器前缀并将换行统一为 LF 的 TeX 原文。
     * @param expressionSource 按原文顺序排列的表达式片段；数组被防御性复制。
     * @param openerSpan 原文 $ 或 $$ 起始 delimiter 范围。
     * @param closerSpan 原文对应结束 delimiter 范围。
     */
    public init(display: Bool, expression: String, expressionSource: Array<MathSourcePart>, openerSpan: SourceSpan,
        closerSpan: SourceSpan) {
        this.display = display
        this.expression = expression
        this.expressionSource = ImmutableArray<MathSourcePart>(expressionSource)
        this.openerSpan = openerSpan
        this.closerSpan = closerSpan
    }

    /** 返回不依赖第三方后端的 payload schema。
     * @return 公式源语义的 schema 身份 markdown.math/2。
     */
    public func payloadTypeId(): String {
        "markdown.math/2"
    }
}

/** 读取自定义块或行内节点携带的公式源语义。
 * @param node 待检查的节点。
 * @return MathPayload；非自定义节点或 payload 类型不符时为 None。
 */
protected func mathPayload(node: NodeRef): ?MathPayload {
    let payload: CustomPayload = match (node.kind) {
        case NodeKind.CustomBlock => node.asCustomBlock().getOrThrow().payload
        case NodeKind.CustomInline => node.asCustomInline().getOrThrow().payload
        case _ => return None
    }
    payload as MathPayload
}

/** 核对公式类型、delimiter 和分片规范化后的表达式是否与原始来源一致。
 * @param document 节点所属且持有原始 SourceBuffer 的文档。
 * @param node 当前待检查节点；没有公式 payload 时直接跳过。
 * @param limits 表达式 literal 字节上限。
 * @param budget 来源和表达式校验的共享扫描预算。
 * @param cancellation 绑定阶段的取消信号。
 */
protected func validateMathNode(document: Document, node: NodeRef, limits: ParseLimits, budget: OperationBudget,
    cancellation: CancellationToken): Unit {
    if (let Some(value) <- mathPayload(node)) {
        let span = match (node.span) {
            case Some(found) => found
            case None => invalidMath(node)
        }
        let source = match (document.parserSourceBuffer()) {
            case Some(found) => found
            case None => invalidMath(node)
        }
        let block = if (let NodeKind.CustomBlock <- node.kind) {
            true
        } else {
            false
        }
        if (value.display != block || node.children().size != 0 || !span.containsSpan(value.openerSpan) ||
            !span.containsSpan(value.closerSpan) || value.openerSpan.endByte > value.closerSpan.startByte ||
            span.endByte > source.byteLength()) {
            invalidMath(node)
        }
        let delimiter = if (value.display) {
            "$$"
        } else {
            "$"
        }
        validateMathSpan(value.openerSpan, source, node)
        validateMathSpan(value.closerSpan, source, node)
        if (source.slice(value.openerSpan) != delimiter || source.slice(value.closerSpan) != delimiter) {
            invalidMath(node)
        }
        if (value.expression.size > limits.maximumLiteralBytes) {
            throw LimitExceededException("literal_bytes", limits.maximumLiteralBytes, value.expression.size, "bind",
                span: node.span)
        }
        var matched: Int64 = 0
        var previous = value.openerSpan.endByte
        for (index in 0..value.expressionSource.size) {
            cancellation.throwIfCancelled(phase: "bind")
            budget.consumeScan()
            let part = value.expressionSource[index].span
            let layout = value.expressionSource[index]
            if (part.startByte < previous || part.endByte > value.closerSpan.startByte) {
                invalidMath(node)
            }
            validateMathSpan(part, source, node)
            budget.consumeScan(steps: part.length() + layout.expandedPrefixSpaces)
            let prefixEnd = part.startByte + layout.expandedPrefixBytes
            validateMathSpan(SourceSpan(part.startByte, prefixEnd), source, node)
            var prefixCursor = source.decodedOffset(part.startByte)
            let decodedPrefixEnd = source.decodedOffset(prefixEnd)
            while (prefixCursor < decodedPrefixEnd) {
                let byte = source.decodedByte(prefixCursor)
                if (byte != b' ' && byte != b'\t') {
                    invalidMath(node)
                }
                prefixCursor++
                if (prefixCursor % 256 == 0) {
                    cancellation.throwIfCancelled(phase: "bind")
                }
            }
            for (_ in 0..layout.expandedPrefixSpaces) {
                if (matched >= value.expression.size || value.expression[matched] != b' ') {
                    invalidMath(node)
                }
                matched++
                if (matched % 256 == 0) {
                    cancellation.throwIfCancelled(phase: "bind")
                }
            }
            var cursor = decodedPrefixEnd
            let end = source.decodedOffset(part.endByte)
            while (cursor < end) {
                if (cursor % 256 == 0) {
                    cancellation.throwIfCancelled(phase: "bind")
                }
                var byte = source.decodedByte(cursor)
                cursor++
                if (byte == b'\r') {
                    byte = b'\n'
                    if (cursor < end && source.decodedByte(cursor) == b'\n') {
                        cursor++
                    }
                }
                if (matched >= value.expression.size || value.expression[matched] != byte) {
                    invalidMath(node)
                }
                matched++
            }
            previous = part.endByte
        }
        if (matched != value.expression.size || (!value.display && (value.expression.contains("\n") ||
            value.expressionSource.size != 1))) {
            invalidMath(node)
        }
    }
}

private func invalidMath(node: NodeRef): Nothing {
    throw MarkdownException(MarkdownErrorCode.ExtensionFailure, "math payload does not match its source or structure",
        phase: "bind", span: node.span)
}

private func validateMathSpan(span: SourceSpan, source: SourceBuffer, node: NodeRef): Unit {
    for (offset in [span.startByte, span.endByte]) {
        let decoded = source.decodedOffset(offset)
        if (decoded < source.decodedLength() && (source.decodedByte(decoded) & 0xC0) == 0x80) {
            invalidMath(node)
        }
    }
}
