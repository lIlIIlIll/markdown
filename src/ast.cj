package markdown

import std.collection.*

public class ImmutableArray<T> {
    private let values: Array<T>

    public init(values: Array<T>) {
        // Cangjie arrays have a fixed length. An empty array exposes no slot a
        // caller could mutate, so cloning it cannot strengthen immutability and
        // only allocates once per leaf node/origin during parsing.
        this.values = if (values.isEmpty()) {
            values
        } else {
            values.clone()
        }
    }

    public prop size: Int64 {
        get() {
            values.size
        }
    }

    public func isEmpty(): Bool {
        values.isEmpty()
    }

    public operator func [](index: Int64): T {
        values[index]
    }

    public func toArray(): Array<T> {
        values.clone()
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

public class NodeIdAllocator {
    private var nextValue: Int64 = 1

    public init() {}

    public func next(): NodeId {
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

public class NodeOrigin {
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

public enum NodeCategory {
    | Block
    | Inline
}

// cjlint-ignore -start !G.ENU.01 Stable public NodeKind names intentionally mirror node type names.
public enum NodeKind {
    | Document
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

public open class MarkdownNode {
    private static let EMPTY_CHILDREN = ImmutableArray<MarkdownNode>([])
    public let nodeId: NodeId
    public let kind: NodeKind
    public let category: NodeCategory
    public let span: ?SourceSpan
    public let origin: NodeOrigin
    private let childValues: ImmutableArray<MarkdownNode>
    internal let childrenPolicy: ChildrenPolicy

    internal init(
        nodeId: NodeId,
        kind: NodeKind,
        category: NodeCategory,
        span: ?SourceSpan,
        origin: NodeOrigin,
        children: Array<MarkdownNode>,
        childrenPolicy: ChildrenPolicy
    ) {
        this.nodeId = nodeId
        this.kind = kind
        this.category = category
        this.span = span
        this.origin = origin
        this.childValues = if (children.isEmpty()) {
            EMPTY_CHILDREN
        } else {
            ImmutableArray<MarkdownNode>(children)
        }
        this.childrenPolicy = childrenPolicy
    }

    public func children(): ImmutableArray<MarkdownNode> {
        childValues
    }
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

    public init(
        labelRaw: String,
        labelNormalized: String,
        destinationRaw: String,
        destination: String,
        titleRaw: String,
        title: String,
        sourceSpan: SourceSpan,
        isEffective!: Bool = true,
        shadowedBy!: ?SourceSpan = None
    ) {
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

public class Document <: MarkdownNode {
    public let profile: MarkdownProfile
    public let dialectFingerprint: String
    public let references: ImmutableArray<ReferenceDefinition>

    public init(
        nodeId: NodeId,
        children: Array<MarkdownNode>,
        span: SourceSpan,
        profile: MarkdownProfile,
        dialectFingerprint: String,
        references!: Array<ReferenceDefinition> = []
    ) {
        super(
            nodeId,
            NodeKind.Document,
            NodeCategory.Block,
            Some(span),
            NodeOrigin.parsed(span),
            children,
            ChildrenPolicy.Blocks
        )
        this.profile = profile
        this.dialectFingerprint = dialectFingerprint
        this.references = ImmutableArray<ReferenceDefinition>(references)
    }
}

public class BlockQuote <: MarkdownNode {
    public init(nodeId: NodeId, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.BlockQuote, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), children,
            ChildrenPolicy.Blocks)
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

public class List <: MarkdownNode {
    public let listKind: ListKind
    public let start: Int64
    public let delimiter: ListDelimiter
    public let tight: Bool

    public init(
        nodeId: NodeId,
        listKind: ListKind,
        start: Int64,
        delimiter: ListDelimiter,
        tight: Bool,
        children: Array<MarkdownNode>,
        span: SourceSpan
    ) {
        super(nodeId, NodeKind.List, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), children,
            ChildrenPolicy.Blocks)
        if (start < 0) {
            throw IllegalArgumentException("list start must be non-negative")
        }
        this.listKind = listKind
        this.start = start
        this.delimiter = delimiter
        this.tight = tight
    }
}

public enum TaskState {
    | NotTask
    | Checked
    | Unchecked
}

public class ListItem <: MarkdownNode {
    public let taskState: TaskState
    public let markerSpan: ?SourceSpan

    public init(
        nodeId: NodeId,
        children: Array<MarkdownNode>,
        span: SourceSpan,
        taskState!: TaskState = TaskState.NotTask,
        markerSpan!: ?SourceSpan = None
    ) {
        super(nodeId, NodeKind.ListItem, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), children,
            ChildrenPolicy.Blocks)
        this.taskState = taskState
        this.markerSpan = markerSpan
    }
}

public class Paragraph <: MarkdownNode {
    public init(nodeId: NodeId, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.Paragraph, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), children,
            ChildrenPolicy.Inlines)
    }
}

public class Heading <: MarkdownNode {
    public let level: Int64

    public init(nodeId: NodeId, level: Int64, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.Heading, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), children,
            ChildrenPolicy.Inlines)
        if (level < 1 || level > 6) {
            throw IllegalArgumentException("heading level must be 1 through 6")
        }
        this.level = level
    }
}

public class ThematicBreak <: MarkdownNode {
    public let marker: Byte

    public init(nodeId: NodeId, marker: Byte, span: SourceSpan) {
        super(nodeId, NodeKind.ThematicBreak, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.marker = marker
    }
}

public enum CodeBlockKind {
    | Indented
    | Fenced
}

public class CodeBlock <: MarkdownNode {
    public let codeKind: CodeBlockKind
    private let literalStorageValue: LiteralStorage
    public prop literal: String {
        get() {
            literalStorageValue.text()
        }
    }
    public prop literalStorage: LiteralStorage {
        get() {
            literalStorageValue
        }
    }
    public let fenceCharacter: ?Byte
    public let fenceLength: Int64
    public let openingFenceSpan: ?SourceSpan
    public let closingFenceSpan: ?SourceSpan
    public let infoRaw: String
    public let language: String
    public let attributesRaw: String

    public init(
        nodeId: NodeId,
        codeKind: CodeBlockKind,
        literal: String,
        span: SourceSpan,
        fenceCharacter!: ?Byte = None,
        fenceLength!: Int64 = 0,
        openingFenceSpan!: ?SourceSpan = None,
        closingFenceSpan!: ?SourceSpan = None,
        infoRaw!: String = "",
        language!: String = "",
        attributesRaw!: String = ""
    ) {
        super(nodeId, NodeKind.CodeBlock, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.codeKind = codeKind
        this.literalStorageValue = LiteralStorage.Copy(literal)
        this.fenceCharacter = fenceCharacter
        this.fenceLength = fenceLength
        this.openingFenceSpan = openingFenceSpan
        this.closingFenceSpan = closingFenceSpan
        this.infoRaw = infoRaw
        this.language = language
        this.attributesRaw = attributesRaw
    }

    internal init(nodeId: NodeId, codeKind: CodeBlockKind, literalStorage: LiteralStorage, span: SourceSpan,
        fenceCharacter: ?Byte, fenceLength: Int64, openingFenceSpan: ?SourceSpan, closingFenceSpan: ?SourceSpan,
        infoRaw: String, language: String, attributesRaw: String) {
        super(nodeId, NodeKind.CodeBlock, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.codeKind = codeKind
        this.literalStorageValue = literalStorage
        this.fenceCharacter = fenceCharacter
        this.fenceLength = fenceLength
        this.openingFenceSpan = openingFenceSpan
        this.closingFenceSpan = closingFenceSpan
        this.infoRaw = infoRaw
        this.language = language
        this.attributesRaw = attributesRaw
    }
}

public class HtmlBlock <: MarkdownNode {
    private let literalStorageValue: LiteralStorage
    public prop literal: String {
        get() {
            literalStorageValue.text()
        }
    }
    public prop literalStorage: LiteralStorage {
        get() {
            literalStorageValue
        }
    }
    public let blockType: Int64

    public init(nodeId: NodeId, literal: String, blockType: Int64, span: SourceSpan) {
        super(nodeId, NodeKind.HtmlBlock, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.literalStorageValue = LiteralStorage.Copy(literal)
        this.blockType = blockType
    }

    internal init(nodeId: NodeId, literalStorage: LiteralStorage, blockType: Int64, span: SourceSpan) {
        super(nodeId, NodeKind.HtmlBlock, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.literalStorageValue = literalStorage
        this.blockType = blockType
    }
}

public enum TableAlignment {
    | None
    | Left
    | Center
    | Right
}

public class Table <: MarkdownNode {
    public let alignments: ImmutableArray<TableAlignment>

    public init(nodeId: NodeId, alignments: Array<TableAlignment>, rows: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.Table, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), rows, ChildrenPolicy.Rows)
        this.alignments = ImmutableArray<TableAlignment>(alignments)
    }
}

public class TableRow <: MarkdownNode {
    public let header: Bool

    public init(nodeId: NodeId, header: Bool, cells: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.TableRow, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), cells,
            ChildrenPolicy.Cells)
        this.header = header
    }
}

public class TableCell <: MarkdownNode {
    public let alignment: TableAlignment

    public init(
        nodeId: NodeId,
        alignment: TableAlignment,
        children: Array<MarkdownNode>,
        span: SourceSpan
    ) {
        super(nodeId, NodeKind.TableCell, NodeCategory.Block, Some(span), NodeOrigin.parsed(span), children,
            ChildrenPolicy.Inlines)
        this.alignment = alignment
    }
}

public interface CustomPayload {
    func payloadTypeId(): String
}

public class CustomBlock <: MarkdownNode {
    public let extensionId: String
    public let extensionSemanticVersion: String
    public let localKindId: String
    public let payload: CustomPayload

    public init(
        nodeId: NodeId,
        extensionId: String,
        extensionSemanticVersion: String,
        localKindId: String,
        payload: CustomPayload,
        children: Array<MarkdownNode>,
        span: ?SourceSpan,
        origin: NodeOrigin
    ) {
        super(nodeId, NodeKind.CustomBlock, NodeCategory.Block, span, origin, children, ChildrenPolicy.Blocks)
        this.extensionId = extensionId
        this.extensionSemanticVersion = extensionSemanticVersion
        this.localKindId = localKindId
        this.payload = payload
    }
}

public class Text <: MarkdownNode {
    private let rawStorageValue: LiteralStorage
    private let valueStorageValue: LiteralStorage
    public prop raw: String {
        get() {
            rawStorageValue.text()
        }
    }
    public prop value: String {
        get() {
            valueStorageValue.text()
        }
    }
    public prop rawStorage: LiteralStorage {
        get() {
            rawStorageValue
        }
    }
    public prop valueStorage: LiteralStorage {
        get() {
            valueStorageValue
        }
    }
    public let normalized: ?String

    public init(
        nodeId: NodeId,
        raw: String,
        value: String,
        span: SourceSpan,
        normalized!: ?String = None
    ) {
        super(nodeId, NodeKind.Text, NodeCategory.Inline, Some(span), NodeOrigin.parsed(span), [], ChildrenPolicy.None)
        this.rawStorageValue = LiteralStorage.Copy(raw)
        this.valueStorageValue = LiteralStorage.Copy(value)
        this.normalized = normalized
    }

    internal init(nodeId: NodeId, raw: String, value: String, span: SourceSpan, normalized: ?String, origin: NodeOrigin) {
        super(nodeId, NodeKind.Text, NodeCategory.Inline, Some(span), origin, [], ChildrenPolicy.None)
        this.rawStorageValue = LiteralStorage.Copy(raw)
        this.valueStorageValue = LiteralStorage.Copy(value)
        this.normalized = normalized
    }

    internal init(nodeId: NodeId, rawStorage: LiteralStorage, valueStorage: LiteralStorage, span: SourceSpan,
        normalized: ?String, origin: NodeOrigin) {
        super(nodeId, NodeKind.Text, NodeCategory.Inline, Some(span), origin, [], ChildrenPolicy.None)
        this.rawStorageValue = rawStorage
        this.valueStorageValue = valueStorage
        this.normalized = normalized
    }
}

public class SoftBreak <: MarkdownNode {
    public init(nodeId: NodeId, span: SourceSpan) {
        super(nodeId, NodeKind.SoftBreak, NodeCategory.Inline, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
    }
}

public enum HardBreakKind {
    | Backslash
    | Spaces
}

public class HardBreak <: MarkdownNode {
    public let syntaxKind: HardBreakKind

    public init(nodeId: NodeId, syntaxKind: HardBreakKind, span: SourceSpan) {
        super(nodeId, NodeKind.HardBreak, NodeCategory.Inline, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.syntaxKind = syntaxKind
    }
}

public class CodeSpan <: MarkdownNode {
    public let literal: String
    public let delimiterRaw: String

    public init(nodeId: NodeId, literal: String, delimiterRaw: String, span: SourceSpan) {
        super(nodeId, NodeKind.CodeSpan, NodeCategory.Inline, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.literal = literal
        this.delimiterRaw = delimiterRaw
    }
}

public open class InlineContainer <: MarkdownNode {
    protected init(nodeId: NodeId, kind: NodeKind, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, kind, NodeCategory.Inline, Some(span), NodeOrigin.parsed(span), children, ChildrenPolicy.Inlines)
    }
}

public class Emphasis <: InlineContainer {
    public init(nodeId: NodeId, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.Emphasis, children, span)
    }
}

public class Strong <: InlineContainer {
    public init(nodeId: NodeId, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.Strong, children, span)
    }
}

public class Strikethrough <: InlineContainer {
    public init(nodeId: NodeId, children: Array<MarkdownNode>, span: SourceSpan) {
        super(nodeId, NodeKind.Strikethrough, children, span)
    }
}

public enum LinkSyntaxKind {
    | Inline
    | FullReference
    | CollapsedReference
    | ShortcutReference
    | Autolink
    | ExtendedAutolink
}

public class Link <: InlineContainer {
    public let destinationRaw: String
    public let destination: String
    public let titleRaw: String
    public let title: String
    public let syntaxKind: LinkSyntaxKind

    public init(
        nodeId: NodeId,
        destinationRaw: String,
        destination: String,
        titleRaw: String,
        title: String,
        syntaxKind: LinkSyntaxKind,
        children: Array<MarkdownNode>,
        span: SourceSpan
    ) {
        super(nodeId, NodeKind.Link, children, span)
        this.destinationRaw = destinationRaw
        this.destination = destination
        this.titleRaw = titleRaw
        this.title = title
        this.syntaxKind = syntaxKind
    }
}

public class Image <: InlineContainer {
    public let destinationRaw: String
    public let destination: String
    public let titleRaw: String
    public let title: String
    public let syntaxKind: LinkSyntaxKind

    public init(
        nodeId: NodeId,
        destinationRaw: String,
        destination: String,
        titleRaw: String,
        title: String,
        syntaxKind: LinkSyntaxKind,
        children: Array<MarkdownNode>,
        span: SourceSpan
    ) {
        super(nodeId, NodeKind.Image, children, span)
        this.destinationRaw = destinationRaw
        this.destination = destination
        this.titleRaw = titleRaw
        this.title = title
        this.syntaxKind = syntaxKind
    }
}

public class HtmlInline <: MarkdownNode {
    public let literal: String

    public init(nodeId: NodeId, literal: String, span: SourceSpan) {
        super(nodeId, NodeKind.HtmlInline, NodeCategory.Inline, Some(span), NodeOrigin.parsed(span), [],
            ChildrenPolicy.None)
        this.literal = literal
    }
}

public class CustomInline <: MarkdownNode {
    public let extensionId: String
    public let extensionSemanticVersion: String
    public let localKindId: String
    public let payload: CustomPayload

    public init(
        nodeId: NodeId,
        extensionId: String,
        extensionSemanticVersion: String,
        localKindId: String,
        payload: CustomPayload,
        children: Array<MarkdownNode>,
        span: ?SourceSpan,
        origin: NodeOrigin
    ) {
        super(nodeId, NodeKind.CustomInline, NodeCategory.Inline, span, origin, children, ChildrenPolicy.Inlines)
        this.extensionId = extensionId
        this.extensionSemanticVersion = extensionSemanticVersion
        this.localKindId = localKindId
        this.payload = payload
    }
}

// cjlint-ignore -end Stable public NodeKind names intentionally mirror node type names.
public class AstInvariantValidator {
    public init() {}

    public func validate(document: Document, limits!: ParseLimits = ParseLimits.safe()): Unit {
        let seen = HashSet<Int64>()
        let stack = ArrayList<(MarkdownNode, ?SourceSpan)>()
        stack.add((document, None))
        var nodeCount: Int64 = 0
        while (!stack.isEmpty()) {
            let entry = stack.remove(at: stack.size - 1)
            let node = entry[0]
            let parentSpan = entry[1]
            nodeCount++
            if (nodeCount > limits.maximumAstNodes) {
                throw LimitExceededException("ast_nodes", limits.maximumAstNodes, nodeCount, "ast_validation")
            }
            if (!seen.add(node.nodeId.value)) {
                fail("duplicate NodeId ${node.nodeId.value}", node.span)
            }
            validateSpan(node, parentSpan)
            validateChildren(node)
            let children = node.children()
            var index: Int64 = children.size - 1
            while (index >= 0) {
                stack.add((children[index], node.span))
                index--
            }
        }
    }

    private func validateSpan(node: MarkdownNode, parentSpan: ?SourceSpan): Unit {
        match (node.origin.kind) {
            case NodeOriginKind.Parsed =>
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
            case _ => ()
        }
    }

    private func validateChildren(node: MarkdownNode): Unit {
        let children = node.children()
        for (index in 0..children.size) {
            let child = children[index]
            match (node.childrenPolicy) {
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
        match (node.kind) {
            case NodeKind.Document => match (node.category) {
                case NodeCategory.Block => ()
                case _ => fail("Document category must be block", node.span)
            }
            case _ => ()
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
