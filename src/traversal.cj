package markdown

import std.collection.*

/** canonical arena AST 的非递归深度优先遍历事件。 */
public enum NodeRefWalkEvent {
    /** 进入节点时触发，携带该节点。 */
    | Enter(NodeRef)
    /** 离开节点时触发，携带该节点。 */
    | Exit(NodeRef)
}

internal struct NodeRefWalkFrame {
    let node: NodeRef
    let exiting: Bool
    init(node: NodeRef, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

/** 返回 Enter/Exit 事件的非递归 AST iterator。 */
public class NodeRefWalker <: Iterator<NodeRefWalkEvent> {
    private let stack = ArrayList<NodeRefWalkFrame>()

    /**
     * 创建从 root 开始的遍历器。
     * @param root 遍历起点节点。
     */
    public init(root: NodeRef) {
        stack.add(NodeRefWalkFrame(root, false))
    }

    /**
     * 返回下一个遍历事件；遍历结束时返回 `None`。
     * @return 下一个事件；结束时为 `None`。
     */
    public func next(): ?NodeRefWalkEvent {
        if (stack.isEmpty()) {
            return None
        }
        let frame = stack.remove(at: stack.size - 1)
        if (frame.exiting) {
            return Some(NodeRefWalkEvent.Exit(frame.node))
        }
        stack.add(NodeRefWalkFrame(frame.node, true))
        let children = frame.node.children()
        var index = children.size - 1
        while (index >= 0) {
            stack.add(NodeRefWalkFrame(children[index], false))
            index--
        }
        Some(NodeRefWalkEvent.Enter(frame.node))
    }
}

extend NodeRef {
    /**
     * 从当前节点开始深度优先遍历。
     * @return 非递归深度优先遍历器。
     */
    public func walk(): NodeRefWalker {
        NodeRefWalker(this)
    }
}

extend Document {
    /**
     * 从 document root 开始深度优先遍历。
     * @return 非递归深度优先遍历器。
     */
    public func walk(): NodeRefWalker {
        NodeRefWalker(root())
    }
}

/** 通过可覆盖 `enter`/`exit` callback 消费 AST 遍历事件。 */
public open class MarkdownVisitor {
    /** 创建 visitor。 */
    public init() {}

    /** 遍历指定节点，并依次调用 enter/exit。
     * @param root 遍历起点节点。
     */
    public func traverse(root: NodeRef): Unit {
        for (event in root.walk()) {
            match (event) {
                case NodeRefWalkEvent.Enter(node) => enter(node)
                case NodeRefWalkEvent.Exit(node) => exit(node)
            }
        }
    }

    /** 遍历 document root。
     * @param document 目标 Document。
     */
    public func traverse(document: Document): Unit {
        traverse(document.root())
    }

    /** 进入节点时回调；默认无操作。 */
    protected open func enter(_: NodeRef): Unit {}
    /** 离开节点时回调；默认无操作。 */
    protected open func exit(_: NodeRef): Unit {}
}

/**
 * 面向常见节点、span、identity 和 ancestry 的 AST 查询工具。
 *
 * ```cj
 * let headings = AstQuery.headings(document)
 * let links = AstQuery.links(document)
 * ```
 */
public class AstQuery {
    /** 返回 document root 之外的所有后代节点。
     * @param document 目标 Document。
     * @return root 之外的全部后代。
     */
    public static func descendants(document: Document): Array<NodeRef> {
        descendants(document.root())
    }

    /**
     * 按 NodeId 查找节点；不存在时返回 None。
     * @param document 要查询的 Document。
     * @param id 目标 NodeId。
     * @return 匹配的 NodeRef 或 None。
     */
    public static func byNodeId(document: Document, id: NodeId): ?NodeRef {
        var index: Int64 = 0
        while (index < document.nodeCount) {
            let node = document.nodeAt(index)
            if (node.nodeId == id) {
                return Some(node)
            }
            index++
        }
        None
    }

    /** 返回指定 NodeKind 的所有节点。
     * @param document 目标 Document。
     * @param kind 要匹配的节点类别。
     * @return 匹配类别的全部节点。
     */
    public static func byKind(document: Document, kind: NodeKind): Array<NodeRef> {
        let out = ArrayList<NodeRef>()
        for (event in document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                if (sameNodeKind(node.kind, kind)) {
                    out.add(node)
                }
            }
        }
        out.toArray()
    }

    /** 返回 source span 完全包含查询 span 的节点。
     * @param document 目标 Document。
     * @param span 要匹配的 source span。
     * @return 包含查询 span 的节点。
     */
    public static func containing(document: Document, span: SourceSpan): Array<NodeRef> {
        let out = ArrayList<NodeRef>()
        for (event in document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                if (let Some(nodeSpan) <- node.span) {
                    if (nodeSpan.containsSpan(span)) {
                        out.add(node)
                    }
                }
            }
        }
        out.toArray()
    }

    /** 按从 root 到 parent 的顺序返回指定节点的 ancestry。
     * @param document 目标 Document。
     * @param id 目标 NodeId。
     * @return 从 root 到 parent 的祖先链；未找到时为空数组。
     */
    public static func ancestors(document: Document, id: NodeId): Array<NodeRef> {
        let path = ArrayList<NodeRef>()
        for (event in document.walk()) {
            match (event) {
                case NodeRefWalkEvent.Enter(node) =>
                    if (node.nodeId == id) {
                        return path.toArray()
                    }
                    path.add(node)
                case NodeRefWalkEvent.Exit(_) =>
                    if (!path.isEmpty()) {
                        path.remove(at: path.size - 1)
                    }
            }
        }
        []
    }

    /** 返回指定节点的后代，不包含节点本身。
     * @param node 遍历起点节点。
     * @return 不含节点自身的后代数组。
     */
    public static func descendants(node: NodeRef): Array<NodeRef> {
        let out = ArrayList<NodeRef>()
        var first = true
        for (event in node.walk()) {
            if (let NodeRefWalkEvent.Enter(value) <- event) {
                if (first) {
                    first = false
                } else {
                    out.add(value)
                }
            }
        }
        out.toArray()
    }

    /** 返回全部 Heading typed views。
     * @param document 目标 Document。
     * @return 全部 Heading typed view。
     */
    public static func headings(document: Document): Array<HeadingNodeView> {
        let out = ArrayList<HeadingNodeView>()
        for (node in byKind(document, NodeKind.Heading)) {
            out.add(node.asHeading().getOrThrow())
        }
        out.toArray()
    }

    /** 返回全部 Link typed views。
     * @param document 目标 Document。
     * @return 全部 Link typed view。
     */
    public static func links(document: Document): Array<LinkNodeView> {
        let out = ArrayList<LinkNodeView>()
        for (node in byKind(document, NodeKind.Link)) {
            out.add(node.asLink().getOrThrow())
        }
        out.toArray()
    }

    /** 返回全部 Image typed views。
     * @param document 目标 Document。
     * @return 全部 Image typed view。
     */
    public static func images(document: Document): Array<ImageNodeView> {
        let out = ArrayList<ImageNodeView>()
        for (node in byKind(document, NodeKind.Image)) {
            out.add(node.asImage().getOrThrow())
        }
        out.toArray()
    }

    /** 返回全部 CodeBlock typed views。
     * @param document 目标 Document。
     * @return 全部 CodeBlock typed view。
     */
    public static func codeBlocks(document: Document): Array<CodeBlockNodeView> {
        let out = ArrayList<CodeBlockNodeView>()
        for (node in byKind(document, NodeKind.CodeBlock)) {
            out.add(node.asCodeBlock().getOrThrow())
        }
        out.toArray()
    }

    /** 返回全部 CustomBlock 和 CustomInline 节点。
     * @param document 目标 Document。
     * @return 全部 custom 节点。
     */
    public static func customNodes(document: Document): Array<NodeRef> {
        let out = ArrayList<NodeRef>()
        for (event in document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                match (node.kind) {
                    case NodeKind.CustomBlock => out.add(node)
                    case NodeKind.CustomInline => out.add(node)
                    case _ => ()
                }
            }
        }
        out.toArray()
    }
}

private func sameNodeKind(left: NodeKind, right: NodeKind): Bool {
    match (left) {
        case NodeKind.DocumentNode =>
            if (let NodeKind.DocumentNode <- right) {
                true
            } else {
                false
            }
        case NodeKind.BlockQuote =>
            if (let NodeKind.BlockQuote <- right) {
                true
            } else {
                false
            }
        case NodeKind.List =>
            if (let NodeKind.List <- right) {
                true
            } else {
                false
            }
        case NodeKind.ListItem =>
            if (let NodeKind.ListItem <- right) {
                true
            } else {
                false
            }
        case NodeKind.Paragraph =>
            if (let NodeKind.Paragraph <- right) {
                true
            } else {
                false
            }
        case NodeKind.Heading =>
            if (let NodeKind.Heading <- right) {
                true
            } else {
                false
            }
        case NodeKind.ThematicBreak =>
            if (let NodeKind.ThematicBreak <- right) {
                true
            } else {
                false
            }
        case NodeKind.CodeBlock =>
            if (let NodeKind.CodeBlock <- right) {
                true
            } else {
                false
            }
        case NodeKind.HtmlBlock =>
            if (let NodeKind.HtmlBlock <- right) {
                true
            } else {
                false
            }
        case NodeKind.Table =>
            if (let NodeKind.Table <- right) {
                true
            } else {
                false
            }
        case NodeKind.TableRow =>
            if (let NodeKind.TableRow <- right) {
                true
            } else {
                false
            }
        case NodeKind.TableCell =>
            if (let NodeKind.TableCell <- right) {
                true
            } else {
                false
            }
        case NodeKind.CustomBlock =>
            if (let NodeKind.CustomBlock <- right) {
                true
            } else {
                false
            }
        case NodeKind.Text =>
            if (let NodeKind.Text <- right) {
                true
            } else {
                false
            }
        case NodeKind.SoftBreak =>
            if (let NodeKind.SoftBreak <- right) {
                true
            } else {
                false
            }
        case NodeKind.HardBreak =>
            if (let NodeKind.HardBreak <- right) {
                true
            } else {
                false
            }
        case NodeKind.CodeSpan =>
            if (let NodeKind.CodeSpan <- right) {
                true
            } else {
                false
            }
        case NodeKind.Emphasis =>
            if (let NodeKind.Emphasis <- right) {
                true
            } else {
                false
            }
        case NodeKind.Strong =>
            if (let NodeKind.Strong <- right) {
                true
            } else {
                false
            }
        case NodeKind.Strikethrough =>
            if (let NodeKind.Strikethrough <- right) {
                true
            } else {
                false
            }
        case NodeKind.Link =>
            if (let NodeKind.Link <- right) {
                true
            } else {
                false
            }
        case NodeKind.Image =>
            if (let NodeKind.Image <- right) {
                true
            } else {
                false
            }
        case NodeKind.HtmlInline =>
            if (let NodeKind.HtmlInline <- right) {
                true
            } else {
                false
            }
        case NodeKind.CustomInline =>
            if (let NodeKind.CustomInline <- right) {
                true
            } else {
                false
            }
    }
}
