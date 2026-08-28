package markdown

import std.collection.*

/** Non-recursive traversal over the canonical arena AST. */
public enum NodeRefWalkEvent {
    | Enter(NodeRef)
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

public class NodeRefWalker <: Iterator<NodeRefWalkEvent> {
    private let stack = ArrayList<NodeRefWalkFrame>()

    public init(root: NodeRef) {
        stack.add(NodeRefWalkFrame(root, false))
    }

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
    public func walk(): NodeRefWalker {
        NodeRefWalker(this)
    }
}

extend Document {
    public func walk(): NodeRefWalker {
        NodeRefWalker(root())
    }
}

public open class MarkdownVisitor {
    public init() {}

    public func traverse(root: NodeRef): Unit {
        for (event in root.walk()) {
            match (event) {
                case NodeRefWalkEvent.Enter(node) => enter(node)
                case NodeRefWalkEvent.Exit(node) => exit(node)
            }
        }
    }

    public func traverse(document: Document): Unit {
        traverse(document.root())
    }

    protected open func enter(_: NodeRef): Unit {}
    protected open func exit(_: NodeRef): Unit {}
}

public class AstQuery {
    public static func descendants(document: Document): Array<NodeRef> {
        descendants(document.root())
    }

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

    public static func headings(document: Document): Array<HeadingNodeView> {
        let out = ArrayList<HeadingNodeView>()
        for (node in byKind(document, NodeKind.Heading)) {
            out.add(node.asHeading().getOrThrow())
        }
        out.toArray()
    }

    public static func links(document: Document): Array<LinkNodeView> {
        let out = ArrayList<LinkNodeView>()
        for (node in byKind(document, NodeKind.Link)) {
            out.add(node.asLink().getOrThrow())
        }
        out.toArray()
    }

    public static func images(document: Document): Array<ImageNodeView> {
        let out = ArrayList<ImageNodeView>()
        for (node in byKind(document, NodeKind.Image)) {
            out.add(node.asImage().getOrThrow())
        }
        out.toArray()
    }

    public static func codeBlocks(document: Document): Array<CodeBlockNodeView> {
        let out = ArrayList<CodeBlockNodeView>()
        for (node in byKind(document, NodeKind.CodeBlock)) {
            out.add(node.asCodeBlock().getOrThrow())
        }
        out.toArray()
    }

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
        case NodeKind.Document =>
            if (let NodeKind.Document <- right) {
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
