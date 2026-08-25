package markdown

import std.collection.*

public enum WalkEvent {
    | Enter(MarkdownNode)
    | Exit(MarkdownNode)
}

internal class WalkFrame {
    let node: MarkdownNode
    let exiting: Bool
    init(node: MarkdownNode, exiting: Bool) {
        this.node = node
        this.exiting = exiting
    }
}

public class NodeWalker <: Iterator<WalkEvent> {
    private let stack = ArrayList<WalkFrame>()

    public init(root: MarkdownNode) {
        stack.add(WalkFrame(root, false))
    }

    public func next(): ?WalkEvent {
        if (stack.isEmpty()) {
            return None
        }
        let frame = stack.remove(at: stack.size - 1)
        if (frame.exiting) {
            return Some(WalkEvent.Exit(frame.node))
        }
        stack.add(WalkFrame(frame.node, true))
        let children = frame.node.children()
        var index = children.size - 1
        while (index >= 0) {
            stack.add(WalkFrame(children[index], false));
            index--
        }
        Some(WalkEvent.Enter(frame.node))
    }
}

extend MarkdownNode {
    public func walk(): NodeWalker {
        NodeWalker(this)
    }
}

public open class MarkdownVisitor {
    public init() {}

    public func traverse(root: MarkdownNode): Unit {
        for (event in root.walk()) {
            match (event) {
                case WalkEvent.Enter(node) => dispatchEnter(node)
                case WalkEvent.Exit(node) => exit(node)
            }
        }
    }

    protected open func enter(_: Document): Unit {}
    protected open func enter(_: BlockQuote): Unit {}
    protected open func enter(_: List): Unit {}
    protected open func enter(_: ListItem): Unit {}
    protected open func enter(_: Paragraph): Unit {}
    protected open func enter(_: Heading): Unit {}
    protected open func enter(_: ThematicBreak): Unit {}
    protected open func enter(_: CodeBlock): Unit {}
    protected open func enter(_: HtmlBlock): Unit {}
    protected open func enter(_: Table): Unit {}
    protected open func enter(_: TableRow): Unit {}
    protected open func enter(_: TableCell): Unit {}
    protected open func enter(_: CustomBlock): Unit {}
    protected open func enter(_: Text): Unit {}
    protected open func enter(_: SoftBreak): Unit {}
    protected open func enter(_: HardBreak): Unit {}
    protected open func enter(_: CodeSpan): Unit {}
    protected open func enter(_: Emphasis): Unit {}
    protected open func enter(_: Strong): Unit {}
    protected open func enter(_: Strikethrough): Unit {}
    protected open func enter(_: Link): Unit {}
    protected open func enter(_: Image): Unit {}
    protected open func enter(_: HtmlInline): Unit {}
    protected open func enter(_: CustomInline): Unit {}
    protected open func enter(_: MarkdownNode): Unit {}
    protected open func exit(_: MarkdownNode): Unit {}

    private func dispatchEnter(node: MarkdownNode): Unit {
        match (node) {
            case value: Document => enter(value)
            case value: BlockQuote => enter(value)
            case value: List => enter(value)
            case value: ListItem => enter(value)
            case value: Paragraph => enter(value)
            case value: Heading => enter(value)
            case value: ThematicBreak => enter(value)
            case value: CodeBlock => enter(value)
            case value: HtmlBlock => enter(value)
            case value: Table => enter(value)
            case value: TableRow => enter(value)
            case value: TableCell => enter(value)
            case value: CustomBlock => enter(value)
            case value: Text => enter(value)
            case value: SoftBreak => enter(value)
            case value: HardBreak => enter(value)
            case value: CodeSpan => enter(value)
            case value: Emphasis => enter(value)
            case value: Strong => enter(value)
            case value: Strikethrough => enter(value)
            case value: Link => enter(value)
            case value: Image => enter(value)
            case value: HtmlInline => enter(value)
            case value: CustomInline => enter(value)
            case _ => enter(node)
        }
    }
}

public class AstQuery {
    public static func byNodeId(root: MarkdownNode, id: NodeId): ?MarkdownNode {
        for (event in root.walk()) {
            match (event) {
                case WalkEvent.Enter(node) =>
                    if (node.nodeId == id) {
                        return Some(node)
                    }
                case _ => ()
            }
        }
        None
    }

    public static func byKind(root: MarkdownNode, kind: NodeKind): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        for (event in root.walk()) {
            match (event) {
                case WalkEvent.Enter(node) =>
                    if (sameNodeKind(node.kind, kind)) {
                        out.add(node)
                    }
                case _ => ()
            }
        }
        out.toArray()
    }

    public static func containing(root: MarkdownNode, span: SourceSpan): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        for (event in root.walk()) {
            match (event) {
                case WalkEvent.Enter(node) =>
                    if (let Some(nodeSpan) <- node.span) {
                        if (nodeSpan.containsSpan(span)) {
                            out.add(node)
                        }
                    }
                case _ => ()
            }
        }
        out.toArray()
    }

    public static func ancestors(root: MarkdownNode, id: NodeId): Array<MarkdownNode> {
        let path = ArrayList<MarkdownNode>()
        for (event in root.walk()) {
            match (event) {
                case WalkEvent.Enter(node) =>
                    if (node.nodeId == id) {
                        return path.toArray()
                    }
                    path.add(node)
                case WalkEvent.Exit(_) =>
                    if (!path.isEmpty()) {
                        path.remove(at: path.size - 1)
                    }
            }
        }
        []
    }

    public static func descendants(node: MarkdownNode): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        var first = true
        for (event in node.walk()) {
            match (event) {
                case WalkEvent.Enter(value) =>
                    if (first) {
                        first = false
                    } else {
                        out.add(value)
                    }
                case _ => ()
            }
        }
        out.toArray()
    }

    public static func headings(root: MarkdownNode): Array<Heading> {
        let out = ArrayList<Heading>()
        for (event in root.walk()) {
            if (let WalkEvent.Enter(value: Heading) <- event) {
                out.add(value)
            }
        }
        out.toArray()
    }
    public static func links(root: MarkdownNode): Array<Link> {
        let out = ArrayList<Link>()
        for (event in root.walk()) {
            if (let WalkEvent.Enter(value: Link) <- event) {
                out.add(value)
            }
        }
        out.toArray()
    }
    public static func images(root: MarkdownNode): Array<Image> {
        let out = ArrayList<Image>()
        for (event in root.walk()) {
            if (let WalkEvent.Enter(value: Image) <- event) {
                out.add(value)
            }
        }
        out.toArray()
    }
    public static func codeBlocks(root: MarkdownNode): Array<CodeBlock> {
        let out = ArrayList<CodeBlock>()
        for (event in root.walk()) {
            if (let WalkEvent.Enter(value: CodeBlock) <- event) {
                out.add(value)
            }
        }
        out.toArray()
    }
    public static func customNodes(root: MarkdownNode): Array<MarkdownNode> {
        let out = ArrayList<MarkdownNode>()
        for (event in root.walk()) {
            match (event) {
                case WalkEvent.Enter(value: CustomBlock) => out.add(value)
                case WalkEvent.Enter(value: CustomInline) => out.add(value)
                case _ => ()
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
