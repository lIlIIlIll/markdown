package markdown.core

import std.collection.*

/** 定义列表节点的结构归属；entry 内先放 term，再放 definition。 */
public enum DefinitionListRole {
    /** 包含 entry 的完整定义列表。 */
    | List
    /** 共享一组 term 和 definition 的条目。 */
    | Entry
    /** children 为行内内容的术语。 */
    | Term
    /** children 为普通 Markdown blocks 的定义正文。 */
    | Definition
}

/** 定义列表的 typed 结构；原文仍由节点 SourceSpan 和 SourceBuffer 保存。 */
public class DefinitionListPayload <: CustomPayload {
    /** 节点在定义列表中的角色。 */
    public let role: DefinitionListRole
    /** 定义正文的原始冒号位置；生成节点可没有标记来源。 */
    public let markerSpan: ?SourceSpan

    /** 创建结构 payload；仅 Definition 角色可以携带 markerSpan。 */
    public init(role: DefinitionListRole, markerSpan!: ?SourceSpan = None) {
        if (markerSpan.isSome()) {
            if (let DefinitionListRole.Definition <- role) {
                ()
            } else {
                throw IllegalArgumentException("only a definition body may have a marker span")
            }
        }
        this.role = role
        this.markerSpan = markerSpan
    }

    /** 返回 payload schema 身份。 */
    public func payloadTypeId(): String {
        "markdown.definition-list/1"
    }
}

protected func definitionListKind(role: DefinitionListRole): String {
    match (role) {
        case DefinitionListRole.List => "definition-list"
        case DefinitionListRole.Entry => "definition-entry"
        case DefinitionListRole.Term => "definition-term"
        case DefinitionListRole.Definition => "definition-body"
    }
}

internal func definitionListPayload(node: NodeRef): ?DefinitionListPayload {
    if (let NodeKind.CustomBlock <- node.kind) {
        if (let value: DefinitionListPayload <- node.asCustomBlock().getOrThrow().payload) {
            return Some(value)
        }
    }
    None
}

protected func validateDefinitionListNode(document: Document, node: NodeRef, parents: ArrayList<NodeRef>,
    budget: OperationBudget, cancellation: CancellationToken): Unit {
    if (let NodeKind.CustomInline <- node.kind) {
        if (node.asCustomInline().getOrThrow().payload is DefinitionListPayload) {
            invalidDefinitionList(node, "definition list roles must be block nodes")
        }
        return
    }
    let payload = definitionListPayload(node)
    if (payload.isNone()) {
        return
    }
    let value = payload.getOrThrow()
    if (node.asCustomBlock().getOrThrow().localKindId != definitionListKind(value.role)) {
        invalidDefinitionList(node, "definition list role does not match its node kind")
    }
    let children = node.children()
    match (value.role) {
        case DefinitionListRole.List =>
            if (children.isEmpty()) {
                invalidDefinitionList(node, "definition list requires an entry")
            }
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                let child = definitionListPayload(children[index])
                if (child.isNone()) {
                    invalidDefinitionList(children[index], "definition list children must be entries")
                }
                if (let DefinitionListRole.Entry <- child.getOrThrow().role) {
                    ()
                } else {
                    invalidDefinitionList(children[index], "definition list children must be entries")
                }
            }
        case DefinitionListRole.Entry =>
            requireDefinitionParent(node, parents, DefinitionListRole.List)
            var terms: Int64 = 0
            var definitions: Int64 = 0
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                let child = definitionListPayload(children[index])
                if (child.isNone()) {
                    invalidDefinitionList(children[index], "entry children must be terms or definitions")
                }
                match (child.getOrThrow().role) {
                    case DefinitionListRole.Term =>
                        if (definitions > 0) {
                            invalidDefinitionList(children[index], "entry terms must precede definitions")
                        }
                        terms++
                    case DefinitionListRole.Definition => definitions++
                    case _ => invalidDefinitionList(children[index], "entry children must be terms or definitions")
                }
            }
            if (terms == 0 || definitions == 0) {
                invalidDefinitionList(node, "entry requires terms and definitions")
            }
        case DefinitionListRole.Term =>
            requireDefinitionParent(node, parents, DefinitionListRole.Entry)
            if (children.isEmpty()) {
                invalidDefinitionList(node, "term requires inline content")
            }
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                if (let NodeCategory.Inline <- children[index].category) {
                    ()
                } else {
                    invalidDefinitionList(children[index], "term children must be inline nodes")
                }
            }
        case DefinitionListRole.Definition =>
            requireDefinitionParent(node, parents, DefinitionListRole.Entry)
            for (index in 0..children.size) {
                budget.consumeScan()
                cancellation.throwIfCancelled(phase: "bind")
                if (let NodeCategory.Block <- children[index].category) {
                    ()
                } else {
                    invalidDefinitionList(children[index], "definition children must be block nodes")
                }
            }
            match (value.markerSpan) {
                case Some(marker) =>
                    budget.consumeScan()
                    let span = node.span
                    if (marker.endByte - marker.startByte != 1 || span.isNone() ||
                        !span.getOrThrow().containsSpan(marker)) {
                        invalidDefinitionList(node, "definition marker must belong to its body span")
                    }
                    if (let Some(source) <- document.parserSourceBuffer()) {
                        if (marker.endByte > source.byteLength() || source.slice(marker) != ":") {
                            invalidDefinitionList(node, "definition marker does not match source")
                        }
                    } else {
                        invalidDefinitionList(node, "definition marker requires its original source")
                    }
                case None =>
                    if (node.span.isSome()) {
                        invalidDefinitionList(node, "source-backed definition requires a marker span")
                    }
            }
    }
}

private func requireDefinitionParent(node: NodeRef, parents: ArrayList<NodeRef>, expected: DefinitionListRole): Unit {
    if (parents.isEmpty()) {
        invalidDefinitionList(node, "definition role has no owner")
    }
    let parent = definitionListPayload(parents[parents.size - 1])
    if (parent.isNone()) {
        invalidDefinitionList(node, "definition role has an invalid owner")
    }
    let valid = match (expected) {
        case DefinitionListRole.List =>
            if (let DefinitionListRole.List <- parent.getOrThrow().role) {
                true
            } else {
                false
            }
        case DefinitionListRole.Entry =>
            if (let DefinitionListRole.Entry <- parent.getOrThrow().role) {
                true
            } else {
                false
            }
        case _ => false
    }
    if (!valid) {
        invalidDefinitionList(node, "definition role has an invalid owner")
    }
}

private func invalidDefinitionList(node: NodeRef, message: String): Nothing {
    throw MarkdownException(MarkdownErrorCode.ExtensionFailure, message, phase: "bind", span: node.span)
}

protected func requireDefinitionListBinding(node: NodeRef): Unit {
    if (!node.documentBindings.semanticPayloadsValidated) {
        throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
            "definition list rendering requires a validated complete document", phase: "render", span: node.span)
    }
}
