package markdown

import std.collection.*

public enum RewriteAction {
    | Keep
    | Replace(MarkdownNode)
    | Remove
    | InsertBefore(Array<MarkdownNode>)
    | InsertAfter(Array<MarkdownNode>)
    | ReplaceChildren(Array<MarkdownNode>)
    | MapText(String)
}

internal class RewriteFrame {
    let node: MarkdownNode
    let exiting: Bool
    init(node: MarkdownNode, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

public class TreeRewriter {
    public static func rewrite(
        document: Document,
        transform: (MarkdownNode) -> RewriteAction,
        budget!: OperationBudget = OperationBudget.safe(),
        cancellation!: CancellationToken = CancellationToken.none()
    ): Document {
        let stack = ArrayList<RewriteFrame>()
        let outputs = HashMap<Int64, Array<MarkdownNode>>()
        let changed = HashSet<Int64>()
        stack.add(RewriteFrame(document, false))
        while (!stack.isEmpty()) {
            cancellation.throwIfCancelled(phase: "transform")
            let frame = stack.remove(at: stack.size - 1)
            if (!frame.exiting) {
                stack.add(RewriteFrame(frame.node, true))
                let children = frame.node.children()
                var index = children.size - 1
                while (index >= 0) {
                    stack.add(RewriteFrame(children[index], false));
                    index--
                }
                continue
            }
            budget.consumeTransform()
            let rewrittenChildren = ArrayList<MarkdownNode>()
            var childrenChanged = false
            for (child in frame.node.children().toArray()) {
                if (changed.contains(child.nodeId.value)) {
                    childrenChanged = true
                }
                if (let Some(items) <- outputs.get(child.nodeId.value)) {
                    for (item in items) {
                        rewrittenChildren.add(item)
                    }
                }
            }
            let base = rebuildIfNeeded(frame.node, rewrittenChildren.toArray(), childrenChanged)
            let action = transform(base)
            if (childrenChanged || rewriteActionChanges(action)) {
                changed.add(frame.node.nodeId.value)
            }
            outputs.add(frame.node.nodeId.value, applyRewrite(base, action))
        }
        let roots = outputs[document.nodeId.value]
        if (roots.size != 1) {
            throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "document rewrite must produce exactly one root", phase: "transform")
        }
        match (roots[0]) {
            case result: Document =>
                AstInvariantValidator().validate(result);
                result
            case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "document rewrite root must remain Document", phase: "transform")
        }
    }
}

private func applyRewrite(node: MarkdownNode, action: RewriteAction): Array<MarkdownNode> {
    match (action) {
        case RewriteAction.Keep => [node]
        case RewriteAction.Replace(value) => [value]
        case RewriteAction.Remove => []
        case RewriteAction.InsertBefore(values) => concatenate(values, [node])
        case RewriteAction.InsertAfter(values) => concatenate([node], values)
        case RewriteAction.ReplaceChildren(values) => [cloneWithChildren(node, values)]
        case RewriteAction.MapText(value) => match (node) {
            case text: Text =>
                let span = requiredSpan(text)
                let origin = NodeOrigin(NodeOriginKind.Transformed, sourceNodeIds: [text.nodeId], sourceSpan: Some(span),
                    transformId: Some("tree-rewriter/map-text"))
                [Text(text.nodeId, text.rawStorage, LiteralStorage.Copy(value), span, text.normalized, origin)]
            case _ => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "MapText applies only to Text", phase: "transform", span: node.span)
        }
    }
}

private func rebuildIfNeeded(node: MarkdownNode, children: Array<MarkdownNode>, childrenChanged: Bool): MarkdownNode {
    if (childrenChanged) {
        return cloneWithChildren(node, children)
    }
    let old = node.children()
    if (old.size == children.size) {
        var same = true
        for (index in 0..children.size) {
            if (old[index].nodeId != children[index].nodeId) {
                same = false
                break
            }
        }
        if (same) {
            return node
        }
    }
    cloneWithChildren(node, children)
}

private func rewriteActionChanges(action: RewriteAction): Bool {
    match (action) {
        case RewriteAction.Keep => false
        case _ => true
    }
}

private func cloneWithChildren(node: MarkdownNode, children: Array<MarkdownNode>): MarkdownNode {
    match (node) {
        case value: Document => Document(value.nodeId, children, requiredSpan(value), value.profile,
            value.dialectFingerprint, references: value.references.toArray())
        case value: BlockQuote => BlockQuote(value.nodeId, children, requiredSpan(value))
        case value: List => List(value.nodeId, value.listKind, value.start, value.delimiter, value.tight, children,
            requiredSpan(value))
        case value: ListItem => ListItem(value.nodeId, children, requiredSpan(value), taskState: value.taskState,
            markerSpan: value.markerSpan)
        case value: Paragraph => Paragraph(value.nodeId, children, requiredSpan(value))
        case value: Heading => Heading(value.nodeId, value.level, children, requiredSpan(value))
        case value: Table => Table(value.nodeId, value.alignments.toArray(), children, requiredSpan(value))
        case value: TableRow => TableRow(value.nodeId, value.header, children, requiredSpan(value))
        case value: TableCell => TableCell(value.nodeId, value.alignment, children, requiredSpan(value))
        case value: Emphasis => Emphasis(value.nodeId, children, requiredSpan(value))
        case value: Strong => Strong(value.nodeId, children, requiredSpan(value))
        case value: Strikethrough => Strikethrough(value.nodeId, children, requiredSpan(value))
        case value: Link => Link(value.nodeId, value.destinationRaw, value.destination, value.titleRaw, value.title,
            value.syntaxKind, children, requiredSpan(value))
        case value: Image => Image(value.nodeId, value.destinationRaw, value.destination, value.titleRaw, value.title,
            value.syntaxKind, children, requiredSpan(value))
        case value: CustomBlock => CustomBlock(value.nodeId, value.extensionId, value.extensionSemanticVersion,
            value.localKindId, value.payload, children, value.span, value.origin)
        case value: CustomInline => CustomInline(value.nodeId, value.extensionId, value.extensionSemanticVersion,
            value.localKindId, value.payload, children, value.span, value.origin)
        case _ =>
            if (children.isEmpty()) {
                node
            } else {
                throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "leaf rewrite produced children",
                    phase: "transform", span: node.span)
            }
    }
}

private func requiredSpan(node: MarkdownNode): SourceSpan {
    match (node.span) {
        case Some(span) => span
        case None => throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation, "node requires SourceSpan",
            phase: "transform")
    }
}

private func concatenate(left: Array<MarkdownNode>, right: Array<MarkdownNode>): Array<MarkdownNode> {
    let out = ArrayList<MarkdownNode>()
    out.add(all: left);
    out.add(all: right);
    out.toArray()
}
