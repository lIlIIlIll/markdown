package markdown.core

import std.collection.*

/**
 * arena rewrite 的动作集合。
 *
 * 作为参数的 `NodeRef` 必须属于输入 Document；插入和替换的 subtree 会复制到结果
 * 中，`MapText` 和 `ReplaceText` 只适用于 Text 节点。
 *
 * `Keep`、`Replace`、`Remove`、`InsertBefore`、`InsertAfter`、`ReplaceChildren`、
 * `MapText`、`ReplaceText` 和 `DetachLiteral` 分别表达保留、替换、删除、插入、
 * 子树替换、文本映射和 literal ownership 转移。
 */
public enum RewriteAction {
    /** 保留当前节点不变。 */
    | Keep
    /** 用给定 subtree 副本替换当前节点。 */
    | Replace(NodeRef)
    /** 删除当前节点。 */
    | Remove
    /** 在当前节点之前插入给定 subtree 副本集合。 */
    | InsertBefore(Array<NodeRef>)
    /** 在当前节点之后插入给定 subtree 副本集合。 */
    | InsertAfter(Array<NodeRef>)
    /** 用给定 subtree 副本集合替换当前节点的全部子节点。 */
    | ReplaceChildren(Array<NodeRef>)
    /** 以映射结果替换 Text 节点文本；仅适用于 Text 节点。 */
    | MapText(String)
    /** 以（匹配文本，替换文本）对替换 Text 节点内容；仅适用于 Text 节点。 */
    | ReplaceText(String, String)
    /** 解除节点的 literal ownership，使原始文本不再进入输出。 */
    | DetachLiteral
}

private class ArenaRewriteFrame {
    protected let node: NodeRef
    protected let exiting: Bool
    protected init(node: NodeRef, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

// A persistent rewrite retains the old payload arena, including unreachable
// source slices. Detachment needs a compact arena with no source owner instead.
internal func detachDocument(document: Document): Document {
    let builder = AstArenaBuilder(maximumNodes: document.nodeCount, trustedParserConstruction: true,
        lineage: Some(document.nodeLineage()))
    let indexes = HashMap<Int64, Int64>()
    for (event in document.walk()) {
        if (let NodeRefWalkEvent.Exit(node) <- event) {
            let children = node.children()
            let mapped = Array<Int64>(children.size, {index => indexes[children[index].index]})
            let payload = detachedPayload(node)
            indexes.add(node.index, builder.appendSessionNode(node, mapped, node.span, payload, Some(node.origin)))
        }
    }
    builder.freeze(indexes[document.root().index]).withBindings(document.bindings.relocatedDefinitions(indexes))
}

private func detachedPayload(node: NodeRef): ArenaNodePayload {
    match (node.kind) {
        case NodeKind.Text =>
            let value = node.asText().getOrThrow()
            ArenaNodePayload.TextValue(LiteralStorage.Copy(value.raw), LiteralStorage.Copy(value.value),
                value.normalized)
        case NodeKind.CodeBlock =>
            let value = node.asCodeBlock().getOrThrow()
            ArenaNodePayload.CodeBlockValue(value.codeKind, LiteralStorage.Copy(value.literal), value.fenceCharacter,
                value.fenceLength, value.openingFenceSpan, value.closingFenceSpan, value.infoRaw, value.language,
                value.attributesRaw)
        case NodeKind.HtmlBlock =>
            let value = node.asHtmlBlock().getOrThrow()
            ArenaNodePayload.HtmlBlockValue(LiteralStorage.Copy(value.literal), value.blockType)
        case NodeKind.CustomBlock | NodeKind.CustomInline =>
            let value = if (let NodeKind.CustomBlock <- node.kind) {
                node.asCustomBlock().getOrThrow()
            } else {
                node.asCustomInline().getOrThrow()
            }
            if (!knownOwnedCustomPayload(value.payload)) {
                throw MarkdownException(MarkdownErrorCode.UnsupportedNode, "cannot detach an opaque custom payload",
                    phase: "detach", span: node.span)
            }
            node.snapshotPayload()
        case _ => node.snapshotPayload()
    }
}

internal func knownOwnedCustomPayload(payload: CustomPayload): Bool {
    match (payload) {
        case _: CodeGroupPayload | _: MathPayload | _: DefinitionListPayload | _: HeadingIdPayload
            | _: FootnoteDefinitionPayload | _: FootnoteReferencePayload | _: SyntaxPayload => true
        case _ => false
    }
}

/** 对 arena AST 执行后序、非递归 transform 并重新验证结果。 */
public class TreeRewriter {
    /**
     * 按每个节点的 RewriteAction 生成新 Document。
     *
     * 没有变化时可以返回原 Document；结果会经过 `AstInvariantValidator` 验证，并受
     * transform budget 与 cancellation 约束。
     * @param document 输入 Document。
     * @param transform 为每个节点返回 rewrite action 的 callback。
     * @param limits 构造和验证输出 AST 的结构上限。
     * @param budget 可选 transform budget。
     * @param cancellation 可选取消 token。
     * @return 重写后的 Document。
     */
    public static func rewrite(
        document: Document,
        transform: (NodeRef) -> RewriteAction,
        limits!: ParseLimits = ParseLimits.safe(),
        budget!: OperationBudget = OperationBudget.safe(),
        cancellation!: CancellationToken = CancellationToken.none()
    ): Document {
        let builder = AstArenaBuilder(document, maximumNodes: limits.maximumAstNodes)
        let outputs = HashMap<Int64, Array<Int64>>()
        let stack = ArrayList<ArenaRewriteFrame>()
        stack.add(ArenaRewriteFrame(document.root(), false))
        var anyChange = false
        while (!stack.isEmpty()) {
            cancellation.throwIfCancelled(phase: "transform")
            let frame = stack.remove(at: stack.size - 1)
            if (!frame.exiting) {
                stack.add(ArenaRewriteFrame(frame.node, true))
                let children = frame.node.children()
                var index = children.size - 1
                while (index >= 0) {
                    stack.add(ArenaRewriteFrame(children[index], false))
                    index--
                }
                continue
            }
            budget.consumeTransform()
            let rewrittenChildren = ArrayList<Int64>()
            var childrenChanged = false
            let sourceChildren = frame.node.children()
            var childOffset: Int64 = 0
            while (childOffset < sourceChildren.size) {
                let child = sourceChildren[childOffset]
                let values = outputs[child.index]
                if (values.size != 1 || values[0] != child.index) {
                    childrenChanged = true
                }
                rewrittenChildren.add(all: values)
                childOffset++
            }
            let base = if (childrenChanged) {
                anyChange = true
                builder.appendPersistentCopy(frame.node, rewrittenChildren.toArray(), "tree-rewriter/children")
            } else {
                frame.node.index
            }
            let action = transform(frame.node)
            let result = applyAction(document, builder, frame.node, base, action, budget, cancellation)
            if (!isIdentityAction(frame.node, base, result, action)) {
                anyChange = true
            }
            outputs.add(frame.node.index, result)
        }
        let documentRootIndex = document.root().index
        let roots = outputs[documentRootIndex]
        if (roots.size != 1) {
            throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "document rewrite must produce exactly one root", phase: "transform")
        }
        if (!anyChange) {
            if (roots[0] == documentRootIndex) {
                return document
            }
        }
        let result = builder.freeze(roots[0])
        AstInvariantValidator().validate(result, limits: limits, budget: budget, cancellation: cancellation)
        if (document.bindings.footnotesEnabled) {
            return DocumentBinder.bind(result, document.bindings.options, document.bindings.limits, budget, cancellation,
                headingsEnabled: document.bindings.headingsEnabled)
        }
        result
    }
}

private func applyAction(document: Document, builder: AstArenaBuilder, node: NodeRef, base: Int64,
    action: RewriteAction, budget: OperationBudget, cancellation: CancellationToken): Array<Int64> {
    match (action) {
        case RewriteAction.Keep => [base]
        case RewriteAction.Remove => []
        case RewriteAction.MapText(value) =>
            if (let NodeKind.Text <- node.kind) {
                [appendMappedText(builder, node, value)]
            } else {
                throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "MapText applies only to Text",
                    phase: "transform", span: node.span)
            }
        case RewriteAction.ReplaceText(raw, value) =>
            if (let NodeKind.Text <- node.kind) {
                [appendReplacedText(builder, node, raw, value, "tree-rewriter/replace-text")]
            } else {
                throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "ReplaceText applies only to Text",
                    phase: "transform", span: node.span)
            }
        case RewriteAction.DetachLiteral => [appendDetachedLiteral(builder, node)]
        case RewriteAction.Replace(value) =>
            document.requireOwned(value)
            if (value == node) {
                [base]
            } else {
                [cloneSubtree(value, builder, budget, cancellation)]
            }
        case RewriteAction.InsertBefore(values) => concatenateIndexes(
            cloneSubtrees(document, values, builder, budget, cancellation), [base])
        case RewriteAction.InsertAfter(values) => concatenateIndexes([base],
            cloneSubtrees(document, values, builder, budget, cancellation))
        case RewriteAction.ReplaceChildren(values) =>
            let children = cloneSubtrees(document, values, builder, budget, cancellation)
            [builder.appendPersistentCopy(node, children, "tree-rewriter/replace-children")]
    }
}

private func appendDetachedLiteral(builder: AstArenaBuilder, node: NodeRef): Int64 {
    let payload = match (node.kind) {
        case NodeKind.Text =>
            let value = node.asText().getOrThrow()
            ArenaNodePayload.TextValue(LiteralStorage.Copy(value.raw), LiteralStorage.Copy(value.value),
                value.normalized)
        case NodeKind.CodeBlock =>
            let value = node.asCodeBlock().getOrThrow()
            ArenaNodePayload.CodeBlockValue(value.codeKind, LiteralStorage.Copy(value.literal), value.fenceCharacter,
                value.fenceLength, value.openingFenceSpan, value.closingFenceSpan, value.infoRaw, value.language,
                value.attributesRaw)
        case NodeKind.HtmlBlock =>
            let value = node.asHtmlBlock().getOrThrow()
            ArenaNodePayload.HtmlBlockValue(LiteralStorage.Copy(value.literal), value.blockType)
        case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
            "DetachLiteral applies only to source-backed literal nodes", phase: "transform", span: node.span)
    }
    let origin = NodeOrigin(NodeOriginKind.Transformed, sourceNodeIds: [node.nodeId], sourceSpan: node.span,
        transformId: Some("document/detach"))
    builder.append(node.kind, node.category, node.span, NodeOriginKind.Transformed, [], payload: payload,
        origin: Some(origin))
}

private func appendMappedText(builder: AstArenaBuilder, node: NodeRef, value: String): Int64 {
    let text = node.asText().getOrThrow()
    appendReplacedText(builder, node, text.raw, value, "tree-rewriter/map-text")
}

private func appendReplacedText(builder: AstArenaBuilder, node: NodeRef, raw: String, value: String, transformId: String): Int64 {
    let text = node.asText().getOrThrow()
    let origin = NodeOrigin(NodeOriginKind.Transformed, sourceNodeIds: [node.nodeId], sourceSpan: node.span,
        transformId: Some(transformId))
    builder.append(NodeKind.Text, NodeCategory.Inline, node.span, NodeOriginKind.Transformed, [],
        payload: ArenaNodePayload.TextValue(LiteralStorage.Copy(raw), LiteralStorage.Copy(value), text.normalized),
        origin: Some(origin))
}

private func cloneSubtrees(document: Document, values: Array<NodeRef>, builder: AstArenaBuilder,
    budget: OperationBudget, cancellation: CancellationToken): Array<Int64> {
    let out = ArrayList<Int64>()
    for (value in values) {
        document.requireOwned(value)
        out.add(cloneSubtree(value, builder, budget, cancellation))
    }
    out.toArray()
}

private func cloneSubtree(root: NodeRef, builder: AstArenaBuilder, budget: OperationBudget,
    cancellation: CancellationToken): Int64 {
    let stack = ArrayList<ArenaRewriteFrame>()
    let outputs = HashMap<Int64, Int64>()
    stack.add(ArenaRewriteFrame(root, false))
    while (!stack.isEmpty()) {
        cancellation.throwIfCancelled(phase: "transform")
        let frame = stack.remove(at: stack.size - 1)
        if (!frame.exiting) {
            stack.add(ArenaRewriteFrame(frame.node, true))
            let children = frame.node.children()
            var index = children.size - 1
            while (index >= 0) {
                stack.add(ArenaRewriteFrame(children[index], false))
                index--
            }
            continue
        }
        budget.consumeTransform()
        let children = ArrayList<Int64>()
        for (child in frame.node.children().toArray()) {
            children.add(outputs[child.index])
        }
        outputs.add(frame.node.index, builder.appendPersistentCopy(frame.node, children.toArray(), "tree-rewriter/clone"))
    }
    outputs[root.index]
}

private func isIdentityAction(node: NodeRef, base: Int64, result: Array<Int64>, action: RewriteAction): Bool {
    match (action) {
        case RewriteAction.Keep => result.size == 1 && result[0] == base
        case RewriteAction.Replace(value) => value == node && result.size == 1 && result[0] == base
        case _ => false
    }
}

private func concatenateIndexes(left: Array<Int64>, right: Array<Int64>): Array<Int64> {
    let out = ArrayList<Int64>()
    out.add(all: left)
    out.add(all: right)
    out.toArray()
}
