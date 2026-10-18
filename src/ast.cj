package markdown

import std.collection.*

/** 不可变、可按索引访问的数组视图；构造时复制输入值。 */
public class ImmutableArray<T> {
    private let values: Array<T>
    private let startIndex: Int64
    private let valueCount: Int64

    /**
     * 构造时复制输入值。
     * @param values 初始元素列表。
     */
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

    /** 返回元素数量。 */
    public prop size: Int64 {
        get() {
            valueCount
        }
    }

    /**
     * 返回是否没有元素。
     * @return 没有元素时为 `true`。
     */
    public func isEmpty(): Bool {
        valueCount == 0
    }

    /** 按索引读取元素；越界时抛出 `IndexOutOfBoundsException`。
     * @param index 目标索引。
     * @return 对应元素。
     * @throws IndexOutOfBoundsException 索引越界时。
     */
    public operator func [](index: Int64): T {
        if (index < 0 || index >= valueCount) {
            throw IndexOutOfBoundsException("immutable array index is outside the view")
        }
        values[startIndex + index]
    }

    /**
     * 返回可变数组副本。
     * @return 可变数组副本。
     */
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

/** 文档 lineage 内不回收的节点身份；与 snapshot revision 分开。 */
public struct NodeId <: Equatable<NodeId> & Hashable {
    /** 分配节点的文档 lineage；独立解析具有不同 lineage。 */
    public let lineage: Int64
    /** lineage 内不回收的正数编号，不是 arena 下标。 */
    public let value: Int64

    /**
     * 创建节点 id；lineage 或编号非法时抛出 `IllegalArgumentException`。
     * @param lineage 分配节点的文档 lineage。
     * @param value lineage 内的正数编号。
     */
    public init(lineage: Int64, value: Int64) {
        if (lineage <= 0 || value <= 0 || value > Int64(UInt32.Max)) {
            throw IllegalArgumentException("NodeId requires a positive lineage and a 32-bit positive serial")
        }
        this.lineage = lineage
        this.value = value
    }

    /** 比较 lineage 与节点编号。
     * @param other 参与比较的另一个节点 id。
     * @return 两个 id 数值是否相等。
     */
    public operator func ==(other: NodeId): Bool {
        lineage == other.lineage && value == other.value
    }

    /** 返回包含 lineage 的哈希值。
     * @return 节点身份的哈希值。
     */
    public func hashCode(): Int64 {
        lineage ^ value
    }
}

/** 节点来源类别，用于区分 parsed、extension、transform 和 synthetic 节点。 */
public enum NodeOriginKind {
    /** 来自源码解析的节点。 */
    | Parsed
    /** 由扩展生成的节点。 */
    | ExtensionGenerated
    /** 由 transform 生成的节点。 */
    | Transformed
    /** 合成的辅助节点。 */
    | Synthetic
    /** 反序列化得到的节点。 */
    | Deserialized
}

/** 节点来源及其输入节点、span、transform 或 extension 身份。 */
public struct NodeOrigin {
    private static let EMPTY_SOURCE_NODE_IDS = ImmutableArray<NodeId>([])
    /** 节点来源类别。 */
    public let kind: NodeOriginKind
    /** 来源输入节点 id 列表。 */
    public let sourceNodeIds: ImmutableArray<NodeId>
    /** 来源 source span。 */
    public let sourceSpan: ?SourceSpan
    /** 生成该节点的 transform id。 */
    public let transformId: ?String
    /** 生成该节点的扩展 id。 */
    public let extensionId: ?String

    /**
     * 创建节点来源。
     * @param kind 节点来源类别。
     * @param sourceNodeIds 来源输入节点 id 列表。
     * @param sourceSpan 来源 source span。
     * @param transformId 生成该节点的 transform id。
     * @param extensionId 生成该节点的扩展 id。
     */
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

    /** 创建带 source span 的普通 parsed origin。
     * @param span 来源 source span。
     * @return 带 source span 的 parsed origin。
     */
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

/** AST 节点的 block/inline 分类。 */
public enum NodeCategory {
    /** block 级节点。 */
    | Block
    /** inline 级节点。 */
    | Inline
}

// cjlint-ignore -start !G.ENU.01 Stable public NodeKind names intentionally mirror node type names.
/** canonical arena AST 支持的节点种类。 */
public enum NodeKind {
    /** 文档根节点。 */
    | DocumentNode
    /** block quote 容器。 */
    | BlockQuote
    /** bullet 或 ordered list 容器。 */
    | List
    /** list item 容器。 */
    | ListItem
    /** paragraph 容器。 */
    | Paragraph
    /** ATX 或 setext 标题。 */
    | Heading
    /** 水平分割线。 */
    | ThematicBreak
    /** fenced 或 indented 代码块。 */
    | CodeBlock
    /** raw HTML block。 */
    | HtmlBlock
    /** GFM table。 */
    | Table
    /** table 行容器。 */
    | TableRow
    /** table 单元格。 */
    | TableCell
    /** 扩展定义的自定义 block 节点。 */
    | CustomBlock
    /** 文本叶子节点。 */
    | Text
    /** 软换行。 */
    | SoftBreak
    /** 硬换行。 */
    | HardBreak
    /** 行内代码。 */
    | CodeSpan
    /** emphasis（`*` 或 `_`）容器。 */
    | Emphasis
    /** strong（`**` 或 `__`）容器。 */
    | Strong
    /** GFM 删除线容器。 */
    | Strikethrough
    /** 行内链接。 */
    | Link
    /** 行内图片。 */
    | Image
    /** 行内 raw HTML。 */
    | HtmlInline
    /** 扩展定义的自定义 inline 节点。 */
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

/** Markdown reference definition 的 raw/normalized 字段和生效状态。 */
public class ReferenceDefinition {
    /** 原始 label 文本。 */
    public let labelRaw: String
    /** 规范化后的 label。 */
    public let labelNormalized: String
    /** 原始 destination 文本。 */
    public let destinationRaw: String
    /** 解析后的 destination。 */
    public let destination: String
    /** 原始 title 文本。 */
    public let titleRaw: String
    /** 解析后的 title。 */
    public let title: String
    /** 定义所在的 source span。 */
    public let sourceSpan: SourceSpan
    /** 该定义是否生效。 */
    public let isEffective: Bool
    /** 遮蔽该定义的重复定义 span。 */
    public let shadowedBy: ?SourceSpan

    /**
     * 创建引用定义。
     * @param labelRaw 原始 label 文本。
     * @param labelNormalized 规范化后的 label。
     * @param destinationRaw 原始 destination 文本。
     * @param destination 解析后的 destination。
     * @param titleRaw 原始 title 文本。
     * @param title 解析后的 title。
     * @param sourceSpan 定义所在的 source span。
     * @param isEffective 该定义是否生效。
     * @param shadowedBy 遮蔽该定义的重复定义 span。
     */
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

/** list 的 bullet 或 ordered 类别。 */
public enum ListKind {
    /** bullet list。 */
    | Bullet
    /** ordered list。 */
    | Ordered
}

/** ordered/bullet list 使用的 delimiter。 */
public enum ListDelimiter {
    /** `1.` 形式。 */
    | Period
    /** `1)` 形式。 */
    | Parenthesis
    /** bullet list 无 delimiter。 */
    | None
}

/** GFM task list item 的状态。 */
public enum TaskState {
    /** 普通列表项，非 task。 */
    | NotTask
    /** 已勾选。 */
    | Checked
    /** 未勾选。 */
    | Unchecked
}

/** code block 的 fenced 或 indented 形态。 */
public enum CodeBlockKind {
    /** 缩进代码块。 */
    | Indented
    /** 围栏代码块。 */
    | Fenced
}

/** GFM table cell 的对齐方式。 */
public enum TableAlignment {
    /** 未指定对齐。 */
    | None
    /** 左对齐。 */
    | Left
    /** 居中对齐。 */
    | Center
    /** 右对齐。 */
    | Right
}

/** custom node payload 的最小稳定类型接口。 */
public interface CustomPayload {
    /**
     * 返回 payload 实现的稳定类型 id。
     * @return 稳定的 payload type 标识。
     */
    func payloadTypeId(): String
}

/** hard break 的反斜杠或空格语法来源。 */
public enum HardBreakKind {
    /** 行尾反斜杠硬换行。 */
    | Backslash
    /** 行尾两个以上空格硬换行。 */
    | Spaces
}

/** link/image destination 的 inline、reference 或 autolink 语法来源。 */
public enum LinkSyntaxKind {
    /** `[text](dest "title")` inline 形式。 */
    | Inline
    /** `[label][reference]` full reference 形式。 */
    | FullReference
    /** `[label][]` collapsed reference 形式。 */
    | CollapsedReference
    /** `[label]` shortcut reference 形式。 */
    | ShortcutReference
    /** `<uri>` autolink 形式。 */
    | Autolink
    /** GFM extended autolink 形式。 */
    | ExtendedAutolink
}

/** 检查 AST 节点、child edge、span、origin 和 payload 一致性的验证器。 */
public class AstInvariantValidator {
    /** 创建验证器。 */
    public init() {}

    /** 验证 document；超出结构限制或破坏 invariant 时抛出异常。
     * @param document 待验证的 Document。
     * @param limits 结构限制；节点数超过上限时失败。
     * @throws LimitExceededException 节点数超过上限时。
     * @throws MarkdownException 破坏 AST invariant 时。
     */
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
