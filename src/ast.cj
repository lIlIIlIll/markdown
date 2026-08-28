package markdown

import std.collection.*

public class ImmutableArray<T> {
    private let values: Array<T>
    private let startIndex: Int64
    private let valueCount: Int64

    public init(values: Array<T>) {
        // Cangjie arrays have a fixed length. An empty array exposes no slot a
        // caller could mutate, so cloning it cannot strengthen immutability and
        // only allocates once per leaf node/origin during parsing.
        this.values = if (values.isEmpty()) {
            values
        } else {
            values.clone()
        }
        startIndex = 0
        valueCount = values.size
    }

    // Parser-owned immutable arenas can expose non-overlapping or nested views
    // without copying the backing references for every semantic node. This is
    // internal so public callers retain the defensive-copy constructor.
    internal init(sharedValues: Array<T>, startIndex: Int64, valueCount: Int64) {
        if (startIndex < 0 || valueCount < 0 || startIndex + valueCount > sharedValues.size) {
            throw IllegalArgumentException("immutable array view is outside its backing storage")
        }
        values = sharedValues
        this.startIndex = startIndex
        this.valueCount = valueCount
    }

    public prop size: Int64 {
        get() {
            valueCount
        }
    }

    public func isEmpty(): Bool {
        valueCount == 0
    }

    public operator func [](index: Int64): T {
        if (index < 0 || index >= valueCount) {
            throw IndexOutOfBoundsException("immutable array index is outside the view")
        }
        values[startIndex + index]
    }

    public func toArray(): Array<T> {
        if (valueCount == 0) {
            return []
        }
        let copy = ArrayList<T>()
        var index: Int64 = 0
        while (index < valueCount) {
            copy.add(values[startIndex + index])
            index++
        }
        copy.toArray()
    }
}

public struct NodeId <: Equatable<NodeId> {
    public let value: Int64

    public init(value: Int64) {
        if (value <= 0) {
            throw IllegalArgumentException("NodeId must be positive")
        }
        this.value = value
    }

    public operator func ==(other: NodeId): Bool {
        value == other.value
    }
}

internal class NodeIdAllocator {
    private var nextValue: Int64 = 1
    private var maximumNodes: Int64 = Int64.Max

    internal init() {}

    internal init(maximumNodes: Int64) {
        if (maximumNodes <= 0) {
            throw IllegalArgumentException("maximum AST nodes must be positive")
        }
        this.maximumNodes = maximumNodes
    }

    internal func next(): NodeId {
        if (nextValue > maximumNodes) {
            throw LimitExceededException("ast_nodes", maximumNodes, nextValue, "ast_allocation")
        }
        let result = NodeId(nextValue)
        if (nextValue == Int64.Max) {
            throw MarkdownException(
                MarkdownErrorCode.LimitExceeded,
                "NodeId space exhausted",
                phase: "ast"
            )
        }
        nextValue++
        result
    }
}

public enum NodeOriginKind {
    | Parsed
    | ExtensionGenerated
    | Transformed
    | Synthetic
    | Deserialized
}

public struct NodeOrigin {
    private static let EMPTY_SOURCE_NODE_IDS = ImmutableArray<NodeId>([])
    public let kind: NodeOriginKind
    public let sourceNodeIds: ImmutableArray<NodeId>
    public let sourceSpan: ?SourceSpan
    public let transformId: ?String
    public let extensionId: ?String

    public init(
        kind: NodeOriginKind,
        sourceNodeIds!: Array<NodeId> = [],
        sourceSpan!: ?SourceSpan = None,
        transformId!: ?String = None,
        extensionId!: ?String = None
    ) {
        this.kind = kind
        this.sourceNodeIds = if (sourceNodeIds.isEmpty()) {
            EMPTY_SOURCE_NODE_IDS
        } else {
            ImmutableArray<NodeId>(sourceNodeIds)
        }
        this.sourceSpan = sourceSpan
        this.transformId = transformId
        this.extensionId = extensionId
    }

    public static func parsed(span: SourceSpan): NodeOrigin {
        NodeOrigin(NodeOriginKind.Parsed, sourceSpan: Some(span))
    }
}

internal class NodeOriginMetadata {
    let value: NodeOrigin

    init(value: NodeOrigin) {
        this.value = value
    }
}

public enum NodeCategory {
    | Block
    | Inline
}

// cjlint-ignore -start !G.ENU.01 Stable public NodeKind names intentionally mirror node type names.
public enum NodeKind {
    | DocumentNode
    | BlockQuote
    | List
    | ListItem
    | Paragraph
    | Heading
    | ThematicBreak
    | CodeBlock
    | HtmlBlock
    | Table
    | TableRow
    | TableCell
    | CustomBlock
    | Text
    | SoftBreak
    | HardBreak
    | CodeSpan
    | Emphasis
    | Strong
    | Strikethrough
    | Link
    | Image
    | HtmlInline
    | CustomInline
}

internal enum ChildrenPolicy {
    | None
    | Blocks
    | Inlines
    | Rows
    | Cells
    | Any
}

public class ReferenceDefinition {
    public let labelRaw: String
    public let labelNormalized: String
    public let destinationRaw: String
    public let destination: String
    public let titleRaw: String
    public let title: String
    public let sourceSpan: SourceSpan
    public let isEffective: Bool
    public let shadowedBy: ?SourceSpan

    public init(labelRaw: String, labelNormalized: String, destinationRaw: String, destination: String,
        titleRaw: String, title: String, sourceSpan: SourceSpan, isEffective!: Bool = true,
        shadowedBy!: ?SourceSpan = None) {
        this.labelRaw = labelRaw
        this.labelNormalized = labelNormalized
        this.destinationRaw = destinationRaw
        this.destination = destination
        this.titleRaw = titleRaw
        this.title = title
        this.sourceSpan = sourceSpan
        this.isEffective = isEffective
        this.shadowedBy = shadowedBy
    }
}

public enum ListKind {
    | Bullet
    | Ordered
}

public enum ListDelimiter {
    | Period
    | Parenthesis
    | None
}

public enum TaskState {
    | NotTask
    | Checked
    | Unchecked
}

public enum CodeBlockKind {
    | Indented
    | Fenced
}

public enum TableAlignment {
    | None
    | Left
    | Center
    | Right
}

public interface CustomPayload {
    func payloadTypeId(): String
}

public enum HardBreakKind {
    | Backslash
    | Spaces
}

public enum LinkSyntaxKind {
    | Inline
    | FullReference
    | CollapsedReference
    | ShortcutReference
    | Autolink
    | ExtendedAutolink
}

public class AstInvariantValidator {
    public init() {}

    public func validate(document: Document, limits!: ParseLimits = ParseLimits.safe()): Unit {
        if (document.nodeCount > limits.maximumAstNodes) {
            throw LimitExceededException("ast_nodes", limits.maximumAstNodes, document.nodeCount, "ast_validation")
        }
        let seen = HashSet<Int64>()
        let stack = ArrayList<(NodeRef, ?SourceSpan)>()
        stack.add((document.root(), None))
        var visited: Int64 = 0
        while (!stack.isEmpty()) {
            let entry = stack.remove(at: stack.size - 1)
            let node = entry[0]
            let parentSpan = entry[1]
            visited++
            if (!seen.add(node.nodeId.value)) {
                fail("duplicate NodeId ${node.nodeId.value}", node.span)
            }
            validateArenaSpan(node, parentSpan)
            validateArenaChildren(node)
            let children = node.children()
            var index = children.size - 1
            while (index >= 0) {
                stack.add((children[index], node.span))
                index--
            }
        }
        let nodeCount = document.nodeCount
        if (visited != nodeCount) {
            var missing: Int64 = 0
            while (missing < nodeCount) {
                let missingNodeId = document.nodeAt(missing).nodeId.value
                if (!seen.contains(missingNodeId)) {
                    break
                }
                missing++
            }
            let detail = if (missing < nodeCount) {
                let node = document.nodeAt(missing)
                match (node.span) {
                    case Some(span) => "AST arena contains unreachable node ${node.nodeId.value} at ${span.startByte}..${span.endByte}"
                    case None => "AST arena contains unreachable node ${node.nodeId.value}"
                }
            } else {
                "AST arena contains unreachable nodes"
            }
            fail(detail, document.root().span)
        }
    }

    private func validateArenaSpan(node: NodeRef, parentSpan: ?SourceSpan): Unit {
        if (let NodeOriginKind.Parsed <- node.originKind) {
            if (let Some(span) <- node.span) {
                match (parentSpan) {
                    case Some(parent) =>
                        if (!parent.containsSpan(span)) {
                            fail("child SourceSpan is outside parent", node.span)
                        }
                    case None => ()
                }
            } else {
                fail("parsed node is missing SourceSpan", node.span)
            }
        }
    }

    private func validateArenaChildren(node: NodeRef): Unit {
        let children = node.children()
        for (index in 0..children.size) {
            let child = children[index]
            match (arenaChildrenPolicy(node.kind)) {
                case ChildrenPolicy.None => fail("leaf node has children", node.span)
                case ChildrenPolicy.Blocks => match (child.category) {
                    case NodeCategory.Block => ()
                    case NodeCategory.Inline => fail("block container has inline child", child.span)
                }
                case ChildrenPolicy.Inlines => match (child.category) {
                    case NodeCategory.Inline => ()
                    case NodeCategory.Block => fail("inline container has block child", child.span)
                }
                case ChildrenPolicy.Rows => match (child.kind) {
                    case NodeKind.TableRow => ()
                    case _ => fail("table has non-row child", child.span)
                }
                case ChildrenPolicy.Cells => match (child.kind) {
                    case NodeKind.TableCell => ()
                    case _ => fail("table row has non-cell child", child.span)
                }
                case ChildrenPolicy.Any => ()
            }
        }
        if (let NodeKind.DocumentNode <- node.kind) {
            if (let NodeCategory.Inline <- node.category) {
                fail("Document category must be block", node.span)
            }
        }
    }

    private func arenaChildrenPolicy(kind: NodeKind): ChildrenPolicy {
        match (kind) {
            case NodeKind.DocumentNode | NodeKind.BlockQuote | NodeKind.List | NodeKind.ListItem => ChildrenPolicy
                .Blocks
            case NodeKind.Paragraph | NodeKind.Heading | NodeKind.TableCell | NodeKind.Emphasis | NodeKind.Strong
                | NodeKind.Strikethrough | NodeKind.Link | NodeKind.Image => ChildrenPolicy.Inlines
            case NodeKind.Table => ChildrenPolicy.Rows
            case NodeKind.TableRow => ChildrenPolicy.Cells
            case NodeKind.CustomBlock | NodeKind.CustomInline => ChildrenPolicy.Any
            case _ => ChildrenPolicy.None
        }
    }

    private func fail(message: String, span: ?SourceSpan): Nothing {
        throw MarkdownException(
            MarkdownErrorCode.InternalInvariantViolation,
            message,
            phase: "ast_validation",
            span: span
        )
    }
}
