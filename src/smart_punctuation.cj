package markdown

import std.collection.*

internal class SmartPunctuationProcessor <: ExtensionDocumentProcessor {
    /** 返回扩展 id。 */
    public prop extensionId: String {
        get() {
            "smart-punctuation"
        }
    }
    /** 返回 processor id。 */
    public prop processorId: String {
        get() {
            "smart-punctuation"
        }
    }
    /** 返回 processor 版本。 */
    public prop version: String {
        get() {
            "2"
        }
    }
    /** 返回处理阶段：AST transform。 */
    public prop phase: ExtensionProcessingPhase {
        get() {
            ExtensionProcessingPhase.AstTransform
        }
    }
    /** 返回处理优先级。 */
    public prop priority: Int64 {
        get() {
            100
        }
    }
    /** 返回转换是否确定性。 */
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    /** 将 Text 节点中的省略号和 em/en dash 替换为对应 Unicode 标点。
     * @param document 输入 Document。
     * @param budget transform 操作预算。
     * @param cancellation 协作式取消信号。
     * @return 处理后的 `Document`。
     */
    public func process(document: Document, budget: OperationBudget, cancellation: CancellationToken): Document {
        let protected = automaticLinkTextNodes(document, budget, cancellation)
        TreeRewriter.rewrite(
            document,
            {
                node =>
                    if (let NodeKind.Text <- node.kind) {
                        if (!protected.contains(node.nodeId)) {
                            if (let Some(value) <- punctuateText(node.asText().getOrThrow().value, budget, cancellation)) {
                                return RewriteAction.MapText(value)
                            }
                        }
                    }
                    RewriteAction.Keep
            },
            budget: budget,
            cancellation: cancellation
        )
    }
}

private func isAutomaticLink(node: NodeRef): Bool {
    if (let NodeKind.Link <- node.kind) {
        match (node.asLink().getOrThrow().syntaxKind) {
            case LinkSyntaxKind.Autolink | LinkSyntaxKind.ExtendedAutolink => return true
            case _ => ()
        }
    }
    false
}

private func automaticLinkTextNodes(document: Document, budget: OperationBudget, cancellation: CancellationToken): HashSet<NodeId> {
    let protected = HashSet<NodeId>()
    var depth: Int64 = 0
    for (event in document.walk()) {
        budget.consumeScan()
        cancellation.throwIfCancelled(phase: "smart_punctuation")
        match (event) {
            case NodeRefWalkEvent.Enter(node) =>
                if (isAutomaticLink(node)) {
                    depth++
                }
                if (depth > 0 && let NodeKind.Text <- node.kind) {
                    protected.add(node.nodeId)
                }
            case NodeRefWalkEvent.Exit(node) =>
                if (isAutomaticLink(node)) {
                    depth--
                }
        }
    }
    protected
}

// The parser already decoded entities and escapes. Match within each semantic
// Text value; do not join across inline nodes or reinterpret raw source syntax.
private func punctuateText(text: String, budget: OperationBudget, cancellation: CancellationToken): ?String {
    budget.consumeScan(steps: text.size)
    var output: ?StringBuilder = None
    var copied: Int64 = 0
    var index: Int64 = 0
    var nextCheck: Int64 = 0
    while (index < text.size) {
        if (index >= nextCheck) {
            cancellation.throwIfCancelled(phase: "smart_punctuation")
            nextCheck = index + 256
        }
        var width: Int64 = 0
        var replacement = ""
        if (text[index] == b'-' && index + 1 < text.size && text[index + 1] == b'-') {
            width = if (index + 2 < text.size && text[index + 2] == b'-') {
                3
            } else {
                2
            }
            replacement = if (width == 3) {
                "—"
            } else {
                "–"
            }
        } else if (text[index] == b'.' && index + 2 < text.size && text[index + 1] == b'.' && text[index + 2] == b'.') {
            width = 3
            replacement = "…"
        }
        if (width == 0) {
            index++
            continue
        }
        if (output.isNone()) {
            output = Some(StringBuilder())
        }
        let out = output.getOrThrow()
        out.append(text[copied..index])
        out.append(replacement)
        index += width
        copied = index
    }
    cancellation.throwIfCancelled(phase: "smart_punctuation")
    if (let Some(out) <- output) {
        out.append(text[copied..])
        return Some(out.toString())
    }
    None
}
