package markdown

import std.collection.*

// cjlint-ignore -start !G.ENU.01 Stable syntax kinds intentionally mirror semantic type names.
/** lossless CST 中的 token、节点、trivia 和无效输入类别。 */
public enum SyntaxKind {
    /** 文档根节点。 */
    | DocumentNode
    /** 文本 token。 */
    | Text
    /** 空白 token。 */
    | Whitespace
    /** 换行 token。 */
    | Newline
    /** ATX 标题 marker。 */
    | HeadingMarker
    /** 列表 marker。 */
    | ListMarker
    /** block quote marker。 */
    | BlockQuoteMarker
    /** 代码围栏行。 */
    | Fence
    /** 围栏 info string。 */
    | InfoString
    /** emphasis/delimiter run。 */
    | Delimiter
    /** link label。 */
    | LinkLabel
    /** link destination。 */
    | LinkDestination
    /** raw HTML 片段。 */
    | Html
    /** 字符实体。 */
    | Entity
    /** 扩展注册的 token。 */
    | ExtensionToken
    /** 无法分类的无效输入。 */
    | Invalid
    /** block 语法节点。 */
    | BlockNode
    /** inline 语法节点。 */
    | InlineNode
    /** 不参与语义的 trivia token。 */
    | Trivia
}

/** 保留 raw text 和原始 source span 的 CST token。 */
public class SyntaxToken {
    /** token 类别。 */
    public let kind: SyntaxKind
    /** token 原文。 */
    public let raw: String
    /** token 覆盖的 source span。 */
    public let span: SourceSpan
    /**
     * 创建 token。
     * @param kind token 类别。
     * @param raw token 原文。
     * @param span token 覆盖的 source span。
     */
    public init(kind: SyntaxKind, raw: String, span: SourceSpan) {
        this.kind = kind
        this.raw = raw
        this.span = span
    }
}

/** 不参与语义树的空白或换行 token。 */
public class Trivia {
    /** trivia 原文。 */
    public let raw: String
    /** trivia 覆盖的 source span。 */
    public let span: SourceSpan
    /**
     * 创建 trivia。
     * @param raw trivia 原文。
     * @param span trivia 覆盖的 source span。
     */
    public init(raw: String, span: SourceSpan) {
        this.raw = raw
        this.span = span
    }
}
// cjlint-ignore -end Stable syntax kinds intentionally mirror semantic type names.

/**
 * lossless CST 节点。
 *
 * 节点保留 token range、children、leading/trailing trivia，并可选地绑定 semantic
 * `NodeId`；不会复制共享 token arena。
 */
public class SyntaxNode {
    /** 语法节点类别。 */
    public let kind: SyntaxKind
    /** 节点覆盖的 source span。 */
    public let span: SourceSpan
    /** 节点包含的 token 列表。 */
    public let tokens: ImmutableArray<SyntaxToken>
    /** 子语法节点列表。 */
    public let children: ImmutableArray<SyntaxNode>
    /** 节点前的 trivia。 */
    public let leadingTrivia: ImmutableArray<Trivia>
    /** 节点后的 trivia。 */
    public let trailingTrivia: ImmutableArray<Trivia>
    /** 关联的 semantic NodeId。 */
    public let semanticNodeId: ?NodeId
    internal let firstTokenIndex: Int64
    internal let tokenCount: Int64
    /**
     * 创建拥有独立 token 列表的语法节点。
     * @param kind 语法节点类别。
     * @param span 节点覆盖的 source span。
     * @param tokens 节点包含的 token 列表。
     * @param children 子语法节点列表。
     * @param leadingTrivia 节点前的 trivia。
     * @param trailingTrivia 节点后的 trivia。
     * @param semanticNodeId 关联的 semantic NodeId。
     */
    public init(kind: SyntaxKind, span: SourceSpan, tokens: Array<SyntaxToken>, children!: Array<SyntaxNode> = [],
        leadingTrivia!: Array<Trivia> = [], trailingTrivia!: Array<Trivia> = [], semanticNodeId!: ?NodeId = None) {
        this.kind = kind
        this.span = span
        this.tokens = ImmutableArray<SyntaxToken>(tokens)
        this.children = ImmutableArray<SyntaxNode>(children)
        this.leadingTrivia = ImmutableArray<Trivia>(leadingTrivia)
        this.trailingTrivia = ImmutableArray<Trivia>(trailingTrivia)
        this.semanticNodeId = semanticNodeId
        firstTokenIndex = 0
        tokenCount = tokens.size
    }

    internal init(kind: SyntaxKind, span: SourceSpan, sharedTokens: Array<SyntaxToken>, firstTokenIndex: Int64,
        tokenCount: Int64, children!: Array<SyntaxNode> = [], semanticNodeId!: ?NodeId = None) {
        this.kind = kind
        this.span = span
        tokens = ImmutableArray<SyntaxToken>(sharedTokens, firstTokenIndex, tokenCount)
        this.children = ImmutableArray<SyntaxNode>(children)
        leadingTrivia = ImmutableArray<Trivia>(leadingTriviaInRange(sharedTokens, firstTokenIndex, tokenCount))
        trailingTrivia = ImmutableArray<Trivia>(trailingTriviaInRange(sharedTokens, firstTokenIndex, tokenCount))
        this.semanticNodeId = semanticNodeId
        this.firstTokenIndex = firstTokenIndex
        this.tokenCount = tokenCount
    }
}

/**
 * 从 `SourceBuffer` 构造的 lossless concrete syntax tree。
 *
 * `losslessText()` 应与输入文本相同；传入 Document 时会建立带 semantic NodeId 的树。
 *
 * ## Example
 *
 * ```cj
 * let syntax = SyntaxTree.parse(result.source, document: Some(result.document))
 * let original = syntax.losslessText()
 * ```
 */
public class SyntaxTree {
    /** 构造树的 source buffer。 */
    public let source: SourceBuffer
    /** CST 根节点。 */
    public let root: SyntaxNode
    private let tokenArena: Array<SyntaxToken>
    private let semanticDocument: ?Document

    private init(source: SourceBuffer, root: SyntaxNode, tokenArena: Array<SyntaxToken>, document: ?Document) {
        this.source = source
        this.root = root
        this.tokenArena = tokenArena
        this.semanticDocument = document
    }

    /**
     * 词法化 source；可选绑定一个 semantic Document。
     * @param source 要词法化的 source buffer。
     * @param document 可选的 semantic Document。
     * @return lossless `SyntaxTree`。
     */
    public static func parse(source: SourceBuffer, document!: ?Document = None): SyntaxTree {
        let value = source.text()
        let tokens = ArrayList<SyntaxToken>()
        var index: Int64 = 0
        var lineStart = true
        var fenceInfo = false
        while (index < value.size) {
            let start = index
            let kind: SyntaxKind
            if (value[index] == 10 || value[index] == 13) {
                if (value[index] == 13 && index + 1 < value.size && value[index + 1] == 10) {
                    index++
                }
                index++
                kind = SyntaxKind.Newline
                lineStart = true
                fenceInfo = false
            } else if (value[index] == b' ' || value[index] == b'\t') {
                while (index < value.size && (value[index] == b' ' || value[index] == b'\t')) {
                    index++
                }
                kind = SyntaxKind.Whitespace
            } else if (fenceInfo) {
                while (index < value.size && value[index] != 10 && value[index] != 13) {
                    index = editorNextRune(value, index)
                }
                kind = SyntaxKind.InfoString
                lineStart = false
            } else if (index + 3 <= value.size && value[index] == b':' && value[index + 1] == b':' && value[index + 2] ==
                b':') {
                index += 3
                kind = SyntaxKind.ExtensionToken
                lineStart = false
            } else if (value[index] == b'\\' && index + 1 == value.size) {
                index++
                kind = SyntaxKind.Invalid
                lineStart = false
            } else if (value[index] == b'`' || value[index] == b'~') {
                let marker = value[index]
                while (index < value.size && value[index] == marker) {
                    index++
                }
                kind = if (index - start >= 3) {
                    SyntaxKind.Fence
                } else {
                    SyntaxKind.Delimiter
                }
                if (lineStart && index - start >= 3) {
                    fenceInfo = true
                }
                lineStart = false
            } else if (value[index] == b'<') {
                while (index < value.size && value[index] != b'>') {
                    index = editorNextRune(value, index)
                }
                if (index < value.size) {
                    index++
                    kind = SyntaxKind.Html
                } else {
                    kind = SyntaxKind.Invalid
                }
                lineStart = false
            } else if (value[index] == b'&') {
                while (index < value.size && value[index] != b';' && value[index] != 10 && value[index] != 13) {
                    index = editorNextRune(value, index)
                }
                if (index < value.size && value[index] == b';') {
                    index++
                    kind = SyntaxKind.Entity
                } else {
                    kind = SyntaxKind.Invalid
                }
                lineStart = false
            } else {
                index = editorNextRune(value, index)
                kind = classifySyntaxByte(value[start], lineStart)
                lineStart = false
            }
            tokens.add(
                SyntaxToken(kind, value[start..index],
                    SourceSpan(source.originalOffset(start), source.originalOffset(index))))
        }
        let tokenValues = tokens.toArray()
        let flatRoot = SyntaxNode(SyntaxKind.DocumentNode, SourceSpan(0, source.byteLength()), tokenValues, 0,
            tokenValues.size)
        match (document) {
            case Some(value) => SyntaxTree(source, syntaxRootForDocument(value, tokenValues), tokenValues, document)
            case None => SyntaxTree(source, flatRoot, tokenValues, document)
        }
    }

    /**
     * 按 token 原文重建输入文本。
     * @return 按 token 原文重建的输入文本。
     */
    public func losslessText(): String {
        let out = StringBuilder()
        for (token in tokenArena) {
            out.append(token.raw)
        }
        out.toString()
    }

    /** 返回 semantic node 对应的原始 token。
     * @param node 目标 semantic 节点。
     * @return 节点对应的原始 token 数组；无 span 时为空数组。
     */
    public func originatingTokens(node: NodeRef): Array<SyntaxToken> {
        if (let Some(document) <- semanticDocument) {
            document.requireOwned(node)
        }
        match (node.span) {
            case Some(span) =>
                let range = syntaxTokenRangeInSpan(tokenArena, span)
                ImmutableArray<SyntaxToken>(tokenArena, range.first, range.count).toArray()
            case None => []
        }
    }

    /** 查询包含原始 byte offset 的 token；空白区或越界返回 None。
     * @param byteOffset 原始输入中的字节偏移。
     * @return 覆盖该偏移的 token；空白区或越界为 `None`。
     */
    public func tokenAt(byteOffset: Int64): ?SyntaxToken {
        if (byteOffset < 0 || byteOffset >= source.byteLength()) {
            return None
        }
        var low: Int64 = 0
        var high = tokenArena.size
        while (low < high) {
            let middle = low + (high - low) / 2
            if (tokenArena[middle].span.endByte <= byteOffset) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        if (low < tokenArena.size && byteOffset >= tokenArena[low].span.startByte && byteOffset < tokenArena[low]
            .span
            .endByte) {
            Some(tokenArena[low])
        } else {
            None
        }
    }

    internal func tokenIndex(token: SyntaxToken): ?Int64 {
        let range = syntaxTokenRangeInSpan(tokenArena, token.span)
        var index = range.first
        let end = range.first + range.count
        while (index < end) {
            if (refEq(tokenArena[index], token)) {
                return Some(index)
            }
            index++
        }
        None
    }

    internal func tokenArenaSize(): Int64 {
        tokenArena.size
    }

    internal func requireDocument(document: Document): Unit {
        if (let Some(bound) <- semanticDocument) {
            if (bound.revision != document.revision) {
                throw IllegalArgumentException("syntax tree belongs to a different Document snapshot")
            }
        }
    }
}

/** 在 lossless CST 和 semantic AST 之间建立双向关联的映射。 */
public class SyntaxToAstMap {
    /** 关联的 lossless CST。 */
    public let syntaxTree: SyntaxTree
    /** 关联的 semantic Document。 */
    public let document: Document
    private let syntaxNodesById: HashMap<Int64, SyntaxNode>
    private let semanticNodesById: HashMap<Int64, NodeRef>
    private let semanticNodeIdsByToken: Array<Int64>
    /**
     * 构建双向映射。
     * @param syntaxTree 关联的 lossless CST。
     * @param document 关联的 semantic Document。
     */
    public init(syntaxTree: SyntaxTree, document: Document) {
        syntaxTree.requireDocument(document)
        this.syntaxTree = syntaxTree
        this.document = document
        syntaxNodesById = HashMap<Int64, SyntaxNode>()
        semanticNodesById = HashMap<Int64, NodeRef>()
        semanticNodeIdsByToken = Array<Int64>(syntaxTree.tokenArenaSize(), repeat: -1)
        let ownerLengths = Array<Int64>(syntaxTree.tokenArenaSize(), repeat: Int64.Max)
        for (event in document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                semanticNodesById.add(node.nodeId.value, node)
            }
        }
        let pending = ArrayList<SyntaxNode>()
        pending.add(syntaxTree.root)
        while (!pending.isEmpty()) {
            let current = pending.remove(at: pending.size - 1)
            if (let Some(id) <- current.semanticNodeId) {
                syntaxNodesById.add(id.value, current)
                if (let Some(semantic) <- semanticNodesById.get(id.value)) {
                    let length = current.span.length()
                    var tokenIndex = current.firstTokenIndex
                    let end = tokenIndex + current.tokenCount
                    while (tokenIndex < end) {
                        if (length < ownerLengths[tokenIndex]) {
                            semanticNodeIdsByToken[tokenIndex] = semantic.nodeId.value
                            ownerLengths[tokenIndex] = length
                        }
                        tokenIndex++
                    }
                }
            }
            for (child in current.children.toArray()) {
                pending.add(child)
            }
        }
    }
    /** 返回 semantic node 对应的原始 token。
     * @param node 目标 semantic 节点。
     * @return 节点对应的原始 token 数组。
     */
    public func originatingTokens(node: NodeRef): Array<SyntaxToken> {
        document.requireOwned(node)
        syntaxTree.originatingTokens(node)
    }
    /** 返回 semantic node 对应的最小 syntax node。
     * @param node 目标 semantic 节点。
     * @return 对应的最小 syntax node；无绑定时为 `None`。
     */
    public func originatingSyntaxNode(node: NodeRef): ?SyntaxNode {
        document.requireOwned(node)
        syntaxNodesById.get(node.nodeId.value)
    }
    /** 将带 semantic id 的 syntax node 映射回 NodeRef。
     * @param node 目标 syntax 节点。
     * @return 对应的 `NodeRef`；无绑定时为 `None`。
     */
    public func semanticNode(node: SyntaxNode): ?NodeRef {
        match (node.semanticNodeId) {
            case Some(id) =>
                if (id.lineage != document.lineage) {
                    return None
                }
                match (semanticNodesById.get(id.value)) {
                    case Some(value) =>
                        if (let Some(expected) <- syntaxNodesById.get(id.value)) {
                            if (refEq(expected, node)) {
                                return Some(value)
                            }
                        }
                        None
                    case None => None
                }
            case None => None
        }
    }
    /** 将 token 映射到其最小拥有 semantic node。
     * @param token 目标 token。
     * @return 拥有该 token 的最小 semantic 节点；无归属时为 `None`。
     */
    public func semanticNode(token: SyntaxToken): ?NodeRef {
        match (syntaxTree.tokenIndex(token)) {
            case Some(index) =>
                let id = semanticNodeIdsByToken[index]
                if (id >= 0) {
                    semanticNodesById.get(id)
                } else {
                    None
                }
            case None => None
        }
    }
}

private struct SyntaxTokenRange {
    let first: Int64
    let count: Int64
    init(first: Int64, count: Int64) {
        this.first = first
        this.count = count
    }
}

private func syntaxRootForDocument(document: Document, tokens: Array<SyntaxToken>): SyntaxNode {
    let built = HashMap<Int64, SyntaxNode>()
    for (event in document.walk()) {
        if (let NodeRefWalkEvent.Exit(node) <- event) {
            let span = match (node.span) {
                case Some(value) => value;
                case None => SourceSpan(0, 0)
            }
            let tokenRange = syntaxTokenRangeInSpan(tokens, span)
            let children = ArrayList<SyntaxNode>()
            for (child in node.children().toArray()) {
                if (let Some(value) <- built.get(child.nodeId.value)) {
                    children.add(value)
                }
            }
            let kind = match (node.kind) {
                case NodeKind.DocumentNode => SyntaxKind.DocumentNode
                case _ => match (node.category) {
                    case NodeCategory.Block => SyntaxKind.BlockNode
                    case NodeCategory.Inline => SyntaxKind.InlineNode
                }
            }
            built.add(node.nodeId.value,
                SyntaxNode(kind, span, tokens, tokenRange.first, tokenRange.count, children: children.toArray(),
                    semanticNodeId: Some(node.nodeId)))
        }
    }
    match (built.get(document.root().nodeId.value)) {
        case Some(value) => value
        case None => SyntaxNode(SyntaxKind.DocumentNode, SourceSpan(0, 0), tokens, 0, 0)
    }
}

private func syntaxTokenRangeInSpan(tokens: Array<SyntaxToken>, span: SourceSpan): SyntaxTokenRange {
    var low: Int64 = 0
    var high = tokens.size
    while (low < high) {
        let middle = low + (high - low) / 2
        if (tokens[middle].span.startByte < span.startByte) {
            low = middle + 1
        } else {
            high = middle
        }
    }
    let first = low
    var index = first
    while (index < tokens.size && tokens[index].span.endByte <= span.endByte) {
        index++
    }
    SyntaxTokenRange(first, index - first)
}

private func leadingTriviaInRange(tokens: Array<SyntaxToken>, first: Int64, count: Int64): Array<Trivia> {
    let values = ArrayList<Trivia>()
    var index = first
    let end = first + count
    while (index < end && isTriviaToken(tokens[index])) {
        values.add(Trivia(tokens[index].raw, tokens[index].span))
        index++
    }
    values.toArray()
}

private func trailingTriviaInRange(tokens: Array<SyntaxToken>, first: Int64, count: Int64): Array<Trivia> {
    let values = ArrayList<Trivia>()
    var index = first + count - 1
    while (index >= first && isTriviaToken(tokens[index])) {
        values.add(Trivia(tokens[index].raw, tokens[index].span))
        index--
    }
    let ordered = ArrayList<Trivia>()
    var reverse = values.size - 1
    while (reverse >= 0) {
        ordered.add(values[reverse])
        reverse--
    }
    ordered.toArray()
}

private func isTriviaToken(token: SyntaxToken): Bool {
    match (token.kind) {
        case SyntaxKind.Whitespace => true
        case SyntaxKind.Newline => true
        case SyntaxKind.Trivia => true
        case _ => false
    }
}

/** 使用原始 UTF-8 byte range 描述的一次文本替换。 */
public class SourceEdit {
    /** 被替换的原始 UTF-8 byte range。 */
    public let range: SourceSpan
    /** 替换后的文本。 */
    public let replacement: String
    /**
     * 创建文本替换。
     * @param range 被替换的原始 UTF-8 byte range。
     * @param replacement 替换后的文本。
     */
    public init(range: SourceSpan, replacement: String) {
        this.range = range
        this.replacement = replacement
    }
}

/** 一次 reparse 中受影响的 NodeId 集合。 */
public class ChangedNodeSet {
    /** 受影响的 NodeId 列表。 */
    public let nodeIds: ImmutableArray<NodeId>
    /**
     * 创建受影响节点集合。
     * @param nodeIds 受影响的 NodeId 列表。
     */
    public init(nodeIds: Array<NodeId>) {
        this.nodeIds = ImmutableArray<NodeId>(nodeIds)
    }
}

/** 编辑后的 snapshot、changed range、节点集合和增量路径标记。 */
public class ReparseResult {
    /** 编辑后的 snapshot。 */
    public let snapshot: DocumentSnapshot
    /** 本次编辑影响的 source span。 */
    public let changedRange: SourceSpan
    /** 受影响的节点集合。 */
    public let changedNodes: ChangedNodeSet
    /** 是否使用了 block-local 增量路径。 */
    public let wasIncremental: Bool
    /** 诊断受影响的 source span。 */
    public let diagnosticsChangedRange: SourceSpan
    /** source map 受影响的 source span。 */
    public let sourceMapChangedRange: SourceSpan
    /**
     * 创建 reparse 结果。
     * @param snapshot 编辑后的 snapshot。
     * @param changedRange 本次编辑影响的 source span。
     * @param changedNodes 受影响的节点集合。
     * @param wasIncremental 是否使用了增量路径。
     */
    public init(snapshot: DocumentSnapshot, changedRange: SourceSpan, changedNodes: ChangedNodeSet, wasIncremental: Bool) {
        this.snapshot = snapshot
        this.changedRange = changedRange
        this.changedNodes = changedNodes
        this.wasIncremental = wasIncremental
        this.diagnosticsChangedRange = changedRange
        this.sourceMapChangedRange = changedRange
    }
}

/**
 * 将 engine、ParseResult、lossless CST 和双向映射绑定在一起的编辑 snapshot。
 *
 * `applyEdits` 使用原始 UTF-8 byte range；满足纯文本、等 byte 长度、顶层 paragraph
 * 或 heading 等条件时可使用 block-local incremental path，否则回退完整解析。
 */
public class DocumentSnapshot {
    /** 创建 snapshot 的 engine。 */
    public let engine: MarkdownEngine
    /** 单调递增的 snapshot 版本。 */
    public let version: Int64
    /** 绑定的 parse 结果。 */
    public let result: ParseResult
    /** lossless CST。 */
    public let syntaxTree: SyntaxTree
    /** CST 与 AST 的双向映射。 */
    public let syntaxMap: SyntaxToAstMap
    /** 当前文本的 SHA-256 digest。 */
    public let sourceDigest: String

    internal init(engine: MarkdownEngine, version: Int64, result: ParseResult) {
        this.engine = engine
        this.version = version
        this.result = result
        syntaxTree = SyntaxTree.parse(result.source, document: Some(result.document))
        syntaxMap = SyntaxToAstMap(syntaxTree, result.document)
        sourceDigest = Sha256.digestBytes(result.source.text().toArray())
    }

    /**
     * 应用不重叠的 byte-range edits，并返回新的 snapshot。
     * @param edits 使用原始 UTF-8 byte range 的替换列表。
     * @return 包含 changed range、NodeIds 和增量标记的 `ReparseResult`。
     * @throws IllegalArgumentException edit 越界或重叠时。
     */
    public func applyEdits(edits: Array<SourceEdit>): ReparseResult {
        if (edits.isEmpty()) {
            return ReparseResult(this, SourceSpan(0, 0), ChangedNodeSet([]), false)
        }
        if (edits.size == 1) {
            if (let Some(incremental) <- tryIncrementalEdit(edits[0])) {
                return incremental
            }
        }
        let ordered = edits.clone()
        sortEdits(ordered)
        var previousEnd: Int64 = 0
        for (edit in ordered) {
            if (edit.range.endByte > result.source.byteLength() || edit.range.startByte < previousEnd) {
                throw IllegalArgumentException("source edits are outside source or overlap")
            }
            previousEnd = edit.range.endByte
        }
        let out = StringBuilder()
        var cursor: Int64 = 0
        for (edit in ordered) {
            out.append(result.source.slice(SourceSpan(cursor, edit.range.startByte)))
            out.append(edit.replacement)
            cursor = edit.range.endByte
        }
        out.append(result.source.slice(SourceSpan(cursor, result.source.byteLength())))
        let nextResult = engine.parse(out.toString())
        let nextSnapshot = DocumentSnapshot(engine, version + 1, nextResult)
        let changedIds = ArrayList<NodeId>()
        for (event in nextResult.document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                changedIds.add(node.nodeId)
            }
        }
        let first = ordered[0].range.startByte
        let last = ordered[ordered.size - 1].range.endByte
        var delta: Int64 = 0
        for (edit in ordered) {
            delta += edit.replacement.size - edit.range.length()
        }
        ReparseResult(nextSnapshot, SourceSpan(first, max(first, last + delta)), ChangedNodeSet(changedIds.toArray()),
            false)
    }

    private func tryIncrementalEdit(edit: SourceEdit): ?ReparseResult {
        if (edit.range.endByte > result.source.byteLength() || edit.range.length() != edit.replacement.size ||
            !result.source.hasIdentityMapping() || !incrementalPlainText(edit.replacement)) {
            return None
        }
        let hasReferences = !result.document.references.isEmpty()
        if (hasReferences) {
            return None
        }
        let dialect = engine.dialect
        if (!dialect.blockRules.isEmpty() || !dialect.inlineRules.isEmpty() || !dialect.parserSpis.isEmpty() ||
            !dialect.documentProcessors.isEmpty()) {
            return None
        }
        var target: ?NodeRef = None
        for (event in result.document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                if (let NodeKind.Text <- node.kind) {
                    if (let Some(span) <- node.span) {
                        if (span.containsSpan(edit.range)) {
                            let text = node.asText().getOrThrow()
                            if (text.raw == text.value && incrementalPlainText(text.raw)) {
                                target = Some(node)
                            }
                        }
                    }
                }
            }
        }
        let textNode = match (target) {
            case Some(value) => value
            case None => return None
        }
        let ancestors = AstQuery.ancestors(result.document, textNode.nodeId)
        if (ancestors.size != 2) {
            return None
        }
        match (ancestors[1].kind) {
            case NodeKind.Paragraph => ()
            case NodeKind.Heading => ()
            case _ => return None
        }
        let span = textNode.span.getOrThrow()
        let text = textNode.asText().getOrThrow()
        let localStart = edit.range.startByte - span.startByte
        let localEnd = edit.range.endByte - span.startByte
        let replacement = text.raw[0..localStart] + edit.replacement + text.raw[localEnd..]
        let nextDocument = TreeRewriter.rewrite(result.document, {
            node => if (node.nodeId == textNode.nodeId) {
                RewriteAction.ReplaceText(replacement, replacement)
            } else {
                RewriteAction.Keep
            }
        })
        let sourceText = result.source.text()
        let nextText = sourceText[0..edit.range.startByte] + edit.replacement + sourceText[edit.range.endByte..]
        let nextSource = SourceBuffer(nextText)
        let nextResult = ParseResult(nextDocument.withSourceBuffer(nextSource), nextSource, result
            .diagnostics
            .toArray())
        let nextSnapshot = DocumentSnapshot(engine, version + 1, nextResult)
        let changed = ArrayList<NodeId>()
        changed.add(textNode.nodeId)
        for (ancestor in ancestors) {
            changed.add(ancestor.nodeId)
        }
        Some(ReparseResult(nextSnapshot, edit.range, ChangedNodeSet(changed.toArray()), true))
    }

    /**
     * 将 UTF-16 编辑位置转换为 byte range 后应用编辑。
     * @param start 编辑起点。
     * @param end 编辑终点。
     * @param replacement 替换文本。
     * @return 新的 `ReparseResult`。
     */
    public func applyUtf16Edit(start: Utf16Position, end: Utf16Position, replacement: String): ReparseResult {
        applyEdits([SourceEdit(SourceSpan(result.source.byteOffset(start), result.source.byteOffset(end)), replacement)])
    }
}

extend MarkdownEngine {
    /**
     * 解析 source 并创建同时包含 AST、CST 和映射的初始 snapshot。
     * @param source 要解析的 Markdown 文本。
     * @return version 为 1 的 `DocumentSnapshot`。
     */
    public func parseSnapshot(source: String): DocumentSnapshot {
        DocumentSnapshot(this, 1, parse(source))
    }
}

/** 在指定范围内格式化，同时尽量保留未触及源码的 byte-for-byte 内容。 */
public class PreservingFormatter {
    /** 应用 formatter 产生的 edits。
     * @param snapshot 目标 snapshot。
     * @param edits 要应用的替换列表。
     * @return 新的 `ReparseResult`。
     * @throws IllegalArgumentException edit 越界或重叠时。
     */
    public static func applyEdits(snapshot: DocumentSnapshot, edits: Array<SourceEdit>): ReparseResult {
        snapshot.applyEdits(edits)
    }

    /**
     * 格式化 source range；不支持的 custom syntax 按 fallback 处理。
     * @param snapshot 要编辑的 snapshot。
     * @param range 使用原始 UTF-8 byte range 的目标范围。
     * @param fallback 无 Markdown lowering 时的策略。
     * @return 可应用到 snapshot 的 source edits。
     * @throws IllegalArgumentException range 越界时。
     * @throws MarkdownException fallback 为 `Error` 且范围内有不支持的 custom syntax 时。
     */
    public static func formatRange(snapshot: DocumentSnapshot, range: SourceSpan,
        fallback!: RangeFormatFallback = RangeFormatFallback.PreserveSource): Array<SourceEdit> {
        if (range.endByte > snapshot.result.source.byteLength()) {
            throw IllegalArgumentException("format range is outside source")
        }
        let original = snapshot.result.source.slice(range)
        if (rangeHasUnsupportedCustom(snapshot, range)) {
            match (fallback) {
                case RangeFormatFallback.PreserveSource => return []
                case RangeFormatFallback.Error => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                    "range contains extension syntax without Markdown lowering", phase: "format", span: Some(range))
            }
        }
        let formatted = preservingFormatText(original)
        if (formatted == original) {
            []
        } else {
            [SourceEdit(range, formatted)]
        }
    }

    /** 按 NodeId 定位 span 并格式化该节点。
     * @param snapshot 要编辑的 snapshot。
     * @param nodeId 目标节点 id。
     * @param fallback 无 Markdown lowering 时的策略。
     * @return 可应用到 snapshot 的 source edits。
     * @throws IllegalArgumentException 节点不存在或无 source range 时。
     */
    public static func formatNode(snapshot: DocumentSnapshot, nodeId: NodeId,
        fallback!: RangeFormatFallback = RangeFormatFallback.PreserveSource): Array<SourceEdit> {
        match (AstQuery.byNodeId(snapshot.result.document, nodeId)) {
            case Some(node) => match (node.span) {
                case Some(span) => formatRange(snapshot, span, fallback: fallback)
                case None => throw IllegalArgumentException("node has no source range")
            }
            case None => throw IllegalArgumentException("node id is not part of snapshot")
        }
    }

    /** 格式化 reparse result 的 changed range。
     * @param reparse 上一次 reparse 的结果。
     * @param fallback 无 Markdown lowering 时的策略。
     * @return 可应用到 snapshot 的 source edits。
     * @throws MarkdownException fallback 为 `Error` 且 changed range 内有不支持的 custom syntax 时。
     */
    public static func formatChangedRanges(reparse: ReparseResult,
        fallback!: RangeFormatFallback = RangeFormatFallback.PreserveSource): Array<SourceEdit> {
        formatRange(reparse.snapshot, reparse.changedRange, fallback: fallback)
    }
}

private func rangeHasUnsupportedCustom(snapshot: DocumentSnapshot, range: SourceSpan): Bool {
    for (node in AstQuery.customNodes(snapshot.result.document)) {
        if (let Some(span) <- node.span) {
            if (spansOverlap(span, range)) {
                var extensionId = ""
                var localKindId = ""
                match (node.kind) {
                    case NodeKind.CustomBlock =>
                        let value = node.asCustomBlock().getOrThrow()
                        extensionId = value.extensionId
                        localKindId = value.localKindId
                    case NodeKind.CustomInline =>
                        let value = node.asCustomInline().getOrThrow()
                        extensionId = value.extensionId
                        localKindId = value.localKindId
                    case _ => ()
                }
                var found = false
                for (index in 0..snapshot.engine.dialect.rendererRules.size) {
                    let rule = snapshot.engine.dialect.rendererRules[index]
                    if (rule.extensionId == extensionId && rule.localKindId == localKindId &&
                        !rule.markdownOpener.isEmpty()) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    return true
                }
            }
        }
    }
    false
}

private func spansOverlap(left: SourceSpan, right: SourceSpan): Bool {
    left.startByte < right.endByte && right.startByte < left.endByte
}

private func incrementalPlainText(value: String): Bool {
    for (byte in value.toArray()) {
        if (byte < 0x80 &&
            !((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b' ' || byte == b'\t')) {
            return false
        }
    }
    true
}

private func preservingFormatText(value: String): String {
    let out = StringBuilder()
    var lineStart: Int64 = 0
    var index: Int64 = 0
    while (index <= value.size) {
        if (index == value.size || value[index] == 10 || value[index] == 13) {
            out.append(preservingFormatLine(value[lineStart..index]))
            if (index < value.size) {
                if (value[index] == 13 && index + 1 < value.size && value[index + 1] == 10) {
                    out.append("\r\n");
                    index += 2
                } else {
                    out.append(value[index..index + 1]);
                    index++
                }
            } else {
                index++
            }
            lineStart = index
        } else {
            index = editorNextRune(value, index)
        }
    }
    out.toString()
}

private func preservingFormatLine(line: String): String {
    var leading: Int64 = 0
    while (leading < line.size && leading < 4 && line[leading] == b' ') {
        leading++
    }
    if (leading > 3 || leading >= line.size || line[leading] != b'#') {
        return line
    }
    var markerEnd = leading
    while (markerEnd < line.size && markerEnd - leading < 6 && line[markerEnd] == b'#') {
        markerEnd++
    }
    if (markerEnd >= line.size || (line[markerEnd] != b' ' && line[markerEnd] != b'\t')) {
        return line
    }
    var content = markerEnd
    while (content < line.size && (line[content] == b' ' || line[content] == b'\t')) {
        content++
    }
    line[..markerEnd] + " " + line[content..]
}

/** preserving formatter 遇到没有 Markdown lowering 的 custom node 时的策略。 */
public enum RangeFormatFallback {
    /** 保留 custom node 的原始源码。 */
    | PreserveSource
    /** 抛出 `UnsupportedNode` 异常。 */
    | Error
}

private func classifySyntaxByte(byte: Byte, lineStart: Bool): SyntaxKind {
    if (byte == b'#') {
        SyntaxKind.HeadingMarker
    } else if (lineStart && (byte == b'-' || byte == b'+' || byte == b'*' || (byte >= b'0' && byte <= b'9'))) {
        SyntaxKind.ListMarker
    } else if (byte == b'>') {
        SyntaxKind.BlockQuoteMarker
    } else if (byte == b'*' || byte == b'_') {
        SyntaxKind.Delimiter
    } else if (byte == b'[' || byte == b']') {
        SyntaxKind.LinkLabel
    } else if (byte == b'(' || byte == b')') {
        SyntaxKind.LinkDestination
    } else {
        SyntaxKind.Text
    }
}

private func sortEdits(edits: Array<SourceEdit>): Unit {
    var index: Int64 = 1
    while (index < edits.size) {
        var current = index
        while (current > 0 && edits[current].range.startByte < edits[current - 1].range.startByte) {
            let swap = edits[current - 1];
            edits[current - 1] = edits[current]
            edits[current] = swap
            current--
        }
        index++
    }
}

private func editorNextRune(value: String, offset: Int64): Int64 {
    if (offset >= value.size) {
        return value.size
    }
    let first = value[offset]
    let width: Int64 = if ((first & 0b1000_0000) == 0) {
        1
    } else if ((first & 0b1110_0000) == 0b1100_0000) {
        2
    } else if ((first & 0b1111_0000) == 0b1110_0000) {
        3
    } else if ((first & 0b1111_1000) == 0b1111_0000) {
        4
    } else {
        1
    }
    let end = offset + width
    if (end < value.size) {
        end
    } else {
        value.size
    }
}
