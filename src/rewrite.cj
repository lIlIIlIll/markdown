package markdown

import std.collection.*

/** Arena rewrite decisions. NodeRef operands must belong to the input
 * Document; inserted and replacement subtrees are cloned into the result. */
public enum RewriteAction {
    | Keep
    | Replace(NodeRef)
    | Remove
    | InsertBefore(Array<NodeRef>)
    | InsertAfter(Array<NodeRef>)
    | ReplaceChildren(Array<NodeRef>)
    | MapText(String)
    | ReplaceText(String, String)
    | DetachLiteral
}

private class ArenaRewriteFrame {
    let node: NodeRef
    let exiting: Bool
    init(node: NodeRef, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

public class TreeRewriter {
    public static func rewrite(
        document: Document,
        transform: (NodeRef) -> RewriteAction,
        budget!: OperationBudget = OperationBudget.safe(),
        cancellation!: CancellationToken = CancellationToken.none()
    ): Document {
        let builder = AstArenaBuilder(document)
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
        AstInvariantValidator().validate(result)
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
