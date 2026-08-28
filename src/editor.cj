package markdown

import std.collection.*

// cjlint-ignore -start !G.ENU.01 Stable syntax kinds intentionally mirror semantic type names.
public enum SyntaxKind {
    | Document
    | Text
    | Whitespace
    | Newline
    | HeadingMarker
    | ListMarker
    | BlockQuoteMarker
    | Fence
    | InfoString
    | Delimiter
    | LinkLabel
    | LinkDestination
    | Html
    | Entity
    | ExtensionToken
    | Invalid
    | BlockNode
    | InlineNode
    | Trivia
}

public class SyntaxToken {
    public let kind: SyntaxKind
    public let raw: String
    public let span: SourceSpan
    public init(kind: SyntaxKind, raw: String, span: SourceSpan) {
        this.kind = kind
        this.raw = raw
        this.span = span
    }
}

public class Trivia {
    public let raw: String
    public let span: SourceSpan
    public init(raw: String, span: SourceSpan) {
        this.raw = raw
        this.span = span
    }
}
// cjlint-ignore -end Stable syntax kinds intentionally mirror semantic type names.

public class SyntaxNode {
    public let kind: SyntaxKind
    public let span: SourceSpan
    public let tokens: ImmutableArray<SyntaxToken>
    public let children: ImmutableArray<SyntaxNode>
    public let leadingTrivia: ImmutableArray<Trivia>
    public let trailingTrivia: ImmutableArray<Trivia>
    public let semanticNodeId: ?NodeId
    internal let firstTokenIndex: Int64
    internal let tokenCount: Int64
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

public class SyntaxTree {
    public let source: SourceBuffer
    public let root: SyntaxNode
    private let tokenArena: Array<SyntaxToken>

    private init(source: SourceBuffer, root: SyntaxNode, tokenArena: Array<SyntaxToken>) {
        this.source = source
        this.root = root
        this.tokenArena = tokenArena
    }

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
        let flatRoot = SyntaxNode(SyntaxKind.Document, SourceSpan(0, source.byteLength()), tokenValues, 0,
            tokenValues.size)
        match (document) {
            case Some(value) => SyntaxTree(source, syntaxRootForDocument(value, tokenValues), tokenValues)
            case None => SyntaxTree(source, flatRoot, tokenValues)
        }
    }

    public func losslessText(): String {
        let out = StringBuilder()
        for (token in tokenArena) {
            out.append(token.raw)
        }
        out.toString()
    }

    public func originatingTokens(node: NodeRef): Array<SyntaxToken> {
        match (node.span) {
            case Some(span) =>
                let range = syntaxTokenRangeInSpan(tokenArena, span)
                ImmutableArray<SyntaxToken>(tokenArena, range.first, range.count).toArray()
            case None => []
        }
    }

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
            if (tokenArena[index].span == token.span) {
                return Some(index)
            }
            index++
        }
        None
    }

    internal func tokenArenaSize(): Int64 {
        tokenArena.size
    }
}

public class SyntaxToAstMap {
    public let syntaxTree: SyntaxTree
    public let document: Document
    private let syntaxNodesById: HashMap<Int64, SyntaxNode>
    private let semanticNodesById: HashMap<Int64, NodeRef>
    private let semanticNodeIdsByToken: Array<Int64>
    public init(syntaxTree: SyntaxTree, document: Document) {
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
    public func originatingTokens(node: NodeRef): Array<SyntaxToken> {
        syntaxTree.originatingTokens(node)
    }
    public func originatingSyntaxNode(node: NodeRef): ?SyntaxNode {
        syntaxNodesById.get(node.nodeId.value)
    }
    public func semanticNode(node: SyntaxNode): ?NodeRef {
        match (node.semanticNodeId) {
            case Some(id) => semanticNodesById.get(id.value)
            case None => None
        }
    }
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
                case NodeKind.Document => SyntaxKind.Document
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
        case None => SyntaxNode(SyntaxKind.Document, SourceSpan(0, 0), tokens, 0, 0)
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

public class SourceEdit {
    public let range: SourceSpan
    public let replacement: String
    public init(range: SourceSpan, replacement: String) {
        this.range = range
        this.replacement = replacement
    }
}

public class ChangedNodeSet {
    public let nodeIds: ImmutableArray<NodeId>
    public init(nodeIds: Array<NodeId>) {
        this.nodeIds = ImmutableArray<NodeId>(nodeIds)
    }
}

public struct StableNodeId <: Equatable<StableNodeId> {
    public let value: String
    public init(value: String) {
        this.value = value
    }
    public operator func ==(other: StableNodeId): Bool {
        value == other.value
    }
}

public class ReparseResult {
    public let snapshot: DocumentSnapshot
    public let changedRange: SourceSpan
    public let changedNodes: ChangedNodeSet
    public let wasIncremental: Bool
    public let diagnosticsChangedRange: SourceSpan
    public let sourceMapChangedRange: SourceSpan
    public init(snapshot: DocumentSnapshot, changedRange: SourceSpan, changedNodes: ChangedNodeSet, wasIncremental: Bool) {
        this.snapshot = snapshot
        this.changedRange = changedRange
        this.changedNodes = changedNodes
        this.wasIncremental = wasIncremental
        this.diagnosticsChangedRange = changedRange
        this.sourceMapChangedRange = changedRange
    }
}

public class DocumentSnapshot {
    public let engine: MarkdownEngine
    public let version: Int64
    public let result: ParseResult
    public let syntaxTree: SyntaxTree
    public let syntaxMap: SyntaxToAstMap
    public let sourceDigest: String
    private let stableIds: HashMap<Int64, StableNodeId>

    internal init(engine: MarkdownEngine, version: Int64, result: ParseResult) {
        this.engine = engine
        this.version = version
        this.result = result
        syntaxTree = SyntaxTree.parse(result.source, document: Some(result.document))
        syntaxMap = SyntaxToAstMap(syntaxTree, result.document)
        sourceDigest = Sha256.digestBytes(result.source.text().toArray())
        stableIds = buildStableNodeIds(result)
    }

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

    public func stableNodeId(nodeId: NodeId): ?StableNodeId {
        stableIds.get(nodeId.value)
    }

    private func tryIncrementalEdit(edit: SourceEdit): ?ReparseResult {
        if (edit.range.endByte > result.source.byteLength() || edit.range.length() != edit.replacement.size ||
            !result.source.hasIdentityMapping() || !incrementalPlainText(edit.replacement) ||
            !result.document.references.isEmpty() || !engine.dialect.blockRules.isEmpty() ||
            !engine.dialect.inlineRules.isEmpty() || !engine.dialect.parserSpis.isEmpty() ||
            !engine.dialect.documentProcessors.isEmpty()) {
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
        let nextResult = ParseResult(nextDocument, SourceBuffer(nextText), result.diagnostics.toArray())
        let nextSnapshot = DocumentSnapshot(engine, version + 1, nextResult)
        let changed = ArrayList<NodeId>()
        changed.add(textNode.nodeId)
        for (ancestor in ancestors) {
            changed.add(ancestor.nodeId)
        }
        Some(ReparseResult(nextSnapshot, edit.range, ChangedNodeSet(changed.toArray()), true))
    }

    public func applyUtf16Edit(start: Utf16Position, end: Utf16Position, replacement: String): ReparseResult {
        applyEdits([SourceEdit(SourceSpan(result.source.byteOffset(start), result.source.byteOffset(end)), replacement)])
    }
}

extend MarkdownEngine {
    public func parseSnapshot(source: String): DocumentSnapshot {
        DocumentSnapshot(this, 1, parse(source))
    }
}

public class PreservingFormatter {
    public static func applyEdits(snapshot: DocumentSnapshot, edits: Array<SourceEdit>): ReparseResult {
        snapshot.applyEdits(edits)
    }

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

private func buildStableNodeIds(result: ParseResult): HashMap<Int64, StableNodeId> {
    let values = HashMap<Int64, StableNodeId>()
    var ordinal: Int64 = 0
    for (event in result.document.walk()) {
        if (let NodeRefWalkEvent.Enter(node) <- event) {
            let source = match (node.span) {
                case Some(span) => result.source.slice(span)
                case None => ""
            }
            values.add(node.nodeId.value, StableNodeId(Sha256.digest("${stableNodeKind(node)}|${ordinal}|${source}")))
            ordinal++
        }
    }
    values
}

private func stableNodeKind(node: NodeRef): String {
    match (node.kind) {
        case NodeKind.Document => "document"
        case NodeKind.BlockQuote => "block-quote"
        case NodeKind.List => "list"
        case NodeKind.ListItem => "list-item"
        case NodeKind.Paragraph => "paragraph"
        case NodeKind.Heading => "heading"
        case NodeKind.ThematicBreak => "thematic-break"
        case NodeKind.CodeBlock => "code-block"
        case NodeKind.HtmlBlock => "html-block"
        case NodeKind.Table => "table"
        case NodeKind.TableRow => "table-row"
        case NodeKind.TableCell => "table-cell"
        case NodeKind.CustomBlock => "custom-block"
        case NodeKind.Text => "text"
        case NodeKind.SoftBreak => "soft-break"
        case NodeKind.HardBreak => "hard-break"
        case NodeKind.CodeSpan => "code-span"
        case NodeKind.Emphasis => "emphasis"
        case NodeKind.Strong => "strong"
        case NodeKind.Strikethrough => "strikethrough"
        case NodeKind.Link => "link"
        case NodeKind.Image => "image"
        case NodeKind.HtmlInline => "html-inline"
        case NodeKind.CustomInline => "custom-inline"
    }
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

public enum RangeFormatFallback {
    | PreserveSource
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
