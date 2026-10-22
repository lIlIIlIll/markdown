package markdown.core

import std.collection.*

/** 绑定阶段的确定性 ID scope 和未定义引用策略。 */
public class BindingOptions {
    /** 宿主为拼装片段指定的唯一 ID 前缀；空值保持文档内 ID。 */
    public let idScope: String
    /** 未定义脚注是否导致致命失败；默认保留可见原文。 */
    public let strictUndefinedFootnotes: Bool

    /** 创建不可变绑定配置。
     * @param idScope 拼装多个文档时使用的唯一片段前缀。
     * @param strictUndefinedFootnotes 是否将未定义脚注视为致命错误。
     */
    public init(idScope!: String = "", strictUndefinedFootnotes!: Bool = false) {
        if (idScope.size > 128) {
            throw IllegalArgumentException("ID scope exceeds 128 UTF-8 bytes")
        }
        for (byte in idScope.toArray()) {
            if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
                byte == b'_' || byte == b'-')) {
                throw IllegalArgumentException("ID scope must contain only ASCII letters, digits, _ and -")
            }
        }
        this.idScope = idScope
        this.strictUndefinedFootnotes = strictUndefinedFootnotes
    }
}

/** 脚注引用的原始及规范化 label；不包含派生 HTML。 */
public class FootnoteReferencePayload <: CustomPayload {
    /** 作者输入的 label。 */
    public let labelRaw: String
    /** 用于查找定义的规范化 label。 */
    public let labelNormalized: String
    /** label 本身的 UTF-8 来源范围，不包含方括号和 ^。 */
    public let labelSpan: SourceSpan

    /** 创建版本化脚注引用 payload。
     * @param labelRaw 作者输入的 label。
     * @param labelSpan label 的来源范围。
     */
    public init(labelRaw: String, labelSpan: SourceSpan) {
        this.labelRaw = labelRaw
        this.labelNormalized = normalizeFootnoteLabel(labelRaw)
        this.labelSpan = labelSpan
    }

    /** 返回 payload schema 身份。
     * @return 当前脚注引用 schema。
     */
    public func payloadTypeId(): String {
        "markdown.footnote-reference/1"
    }
}

/** 脚注定义的 label；定义正文由节点 children 表达。 */
public class FootnoteDefinitionPayload <: CustomPayload {
    /** 作者输入的 label。 */
    public let labelRaw: String
    /** 用于查找定义的规范化 label。 */
    public let labelNormalized: String
    /** label 本身的来源范围。 */
    public let labelSpan: SourceSpan

    /** 创建版本化脚注定义 payload。
     * @param labelRaw 作者输入的 label。
     * @param labelSpan label 的来源范围。
     */
    public init(labelRaw: String, labelSpan: SourceSpan) {
        this.labelRaw = labelRaw
        this.labelNormalized = normalizeFootnoteLabel(labelRaw)
        this.labelSpan = labelSpan
    }

    /** 返回 payload schema 身份。
     * @return 当前脚注定义 schema。
     */
    public func payloadTypeId(): String {
        "markdown.footnote-definition/1"
    }
}

/** 一次脚注引用的已绑定目标、编号和往返锚点。 */
public class FootnoteReferenceBinding {
    /** 本次引用的节点身份。 */
    public let reference: NodeId
    /** 首个有效定义的节点身份。 */
    public let definition: NodeId
    /** 按首次可达引用分配的展示编号。 */
    public let number: Int64
    /** 本次引用独有的锚点 ID。 */
    public let referenceId: String
    /** 定义的锚点 ID。 */
    public let definitionId: String

    protected init(reference: NodeId, definition: NodeId, number: Int64, referenceId: String, definitionId: String) {
        this.reference = reference
        this.definition = definition
        this.number = number
        this.referenceId = referenceId
        this.definitionId = definitionId
    }
}

/** 已引用脚注的定义、展示顺序和全部回链；未引用定义仍保留于 AST。 */
public class FootnoteDefinitionBinding {
    protected let definitionIndex: Int64
    /** 定义节点。 */
    public let definition: NodeId
    /** 展示编号。 */
    public let number: Int64
    /** 定义的锚点 ID。 */
    public let definitionId: String
    /** 按遇到顺序排列的全部可达引用。 */
    public let references: ImmutableArray<FootnoteReferenceBinding>

    protected init(definition: NodeId, definitionIndex: Int64, number: Int64, definitionId: String,
        references: Array<FootnoteReferenceBinding>) {
        this.definition = definition
        this.definitionIndex = definitionIndex
        this.number = number
        this.definitionId = definitionId
        this.references = ImmutableArray<FootnoteReferenceBinding>(references)
    }
}

/** 不可变文档语义绑定索引；renderer、查询和分析共享其中的决策。 */
public class DocumentBindings {
    private static let EMPTY = DocumentBindings(BindingOptions(), ParseLimits.safe(), "", [],
        HashMap<NodeId, FootnoteReferenceBinding>(), [], footnotesEnabled: false)
    protected let footnotesEnabled: Bool
    protected let headingsEnabled: Bool
    protected let semanticPayloadsValidated: Bool
    protected let limits: ParseLimits
    protected let engineFingerprint: String
    protected let options: BindingOptions
    /** 按编号排列的可达脚注；不包含未引用定义。 */
    public let footnotes: ImmutableArray<FootnoteDefinitionBinding>
    /** 按文档顺序排列的可渲染标题。 */
    public let headings: ImmutableArray<HeadingBinding>
    /** 已绑定文档中按遍历顺序排列的可渲染链接。 */
    public let links: ImmutableArray<LinkBinding>
    /** 绑定阶段的可恢复诊断。 */
    public let diagnostics: ImmutableArray<Diagnostic>
    private let footnoteReferences: HashMap<NodeId, FootnoteReferenceBinding>
    private let headingNodes = HashMap<NodeId, HeadingBinding>()
    private let headingIds = HashMap<String, HeadingBinding>()
    private let fragments = HashMap<String, NodeId>()
    private let linkNodes = HashMap<NodeId, LinkBinding>()

    internal func relocatedDefinitions(indexes: HashMap<Int64, Int64>): DocumentBindings {
        let notes = ArrayList<FootnoteDefinitionBinding>()
        for (note in footnotes.toArray()) {
            notes.add(
                FootnoteDefinitionBinding(note.definition, indexes[note.definitionIndex], note.number, note.definitionId,
                    note.references.toArray()))
        }
        DocumentBindings(options, limits, engineFingerprint, notes.toArray(), footnoteReferences, diagnostics.toArray(),
            footnotesEnabled: footnotesEnabled, headingsEnabled: headingsEnabled, headings: headings.toArray(),
            links: links.toArray(), semanticPayloadsValidated: semanticPayloadsValidated)
    }

    protected init(options: BindingOptions, limits: ParseLimits, engineFingerprint: String,
        footnotes: Array<FootnoteDefinitionBinding>, references: HashMap<NodeId, FootnoteReferenceBinding>,
        diagnostics: Array<Diagnostic>, footnotesEnabled!: Bool = true, headingsEnabled!: Bool = false,
        headings!: Array<HeadingBinding> = [], links!: Array<LinkBinding> = [], semanticPayloadsValidated!: Bool = false) {
        this.options = options
        this.limits = limits
        this.engineFingerprint = engineFingerprint
        this.footnotesEnabled = footnotesEnabled
        this.headingsEnabled = headingsEnabled
        this.semanticPayloadsValidated = semanticPayloadsValidated
        this.footnotes = ImmutableArray<FootnoteDefinitionBinding>(footnotes)
        this.headings = ImmutableArray<HeadingBinding>(headings)
        this.links = ImmutableArray<LinkBinding>(links)
        for (link in links) {
            linkNodes.add(link.link, link)
        }
        for (heading in headings) {
            headingNodes.add(heading.heading, heading)
            headingIds.add(heading.id, heading)
            fragments.add(heading.id, heading.heading)
        }
        for (note in footnotes) {
            fragments.add(note.definitionId, note.definition)
            for (reference in note.references.toArray()) {
                fragments.add(reference.referenceId, reference.reference)
            }
        }
        this.footnoteReferences = references
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
    }

    protected static func empty(): DocumentBindings {
        EMPTY
    }

    /** 读取一次引用的绑定；未定义或不属于此索引时返回 None。
     * @param nodeId 引用的节点身份。
     * @return 本次引用的绑定。
     */
    public func footnoteReference(nodeId: NodeId): ?FootnoteReferenceBinding {
        footnoteReferences.get(nodeId)
    }

    /** 查找标题的权威绑定。
     * @param nodeId 标题节点身份。
     * @return 属于此文档的标题绑定。
     */
    public func headingForNode(nodeId: NodeId): ?HeadingBinding {
        headingNodes.get(nodeId)
    }

    /** 用最终 fragment ID 查找标题。
     * @param id 最终的标题锚点 ID。
     * @return 对应标题绑定。
     */
    public func headingForId(id: String): ?HeadingBinding {
        headingIds.get(id)
    }

    /** 查找实际输出的 fragment 目标，包括标题、脚注和回链。
     * @param id 已解码的最终 ID，不含 `#`。
     * @return 对应语义节点的身份。
     */
    public func fragmentTarget(id: String): ?NodeId {
        fragments.get(id)
    }

    /** 查询当前文档中的链接绑定。
     * @param nodeId 链接节点身份。
     * @return 链接的输出目标及已解析的本地目标。
     */
    public func linkForNode(nodeId: NodeId): ?LinkBinding {
        linkNodes.get(nodeId)
    }

    /** 创建层级范围内的结构化目录。
     * @param minimumLevel 最浅标题层级。
     * @param maximumLevel 最深标题层级。
     * @return 按文档顺序排列的目录根条目。
     * @throws IllegalArgumentException 层级范围不在 1..6 内时。
     */
    public func tableOfContents(minimumLevel!: Int64 = 1, maximumLevel!: Int64 = 6): Array<TocEntry> {
        buildToc(headings, minimumLevel, maximumLevel)
    }
}

private func footnoteDefinitionPayload(node: NodeRef): ?FootnoteDefinitionPayload {
    if (let NodeKind.CustomBlock <- node.kind) {
        if (let value: FootnoteDefinitionPayload <- node.asCustomBlock().getOrThrow().payload) {
            return Some(value)
        }
    }
    None
}

private func footnoteReferencePayload(node: NodeRef): ?FootnoteReferencePayload {
    if (let NodeKind.CustomInline <- node.kind) {
        if (let value: FootnoteReferencePayload <- node.asCustomInline().getOrThrow().payload) {
            return Some(value)
        }
    }
    None
}

private class BindingWork {
    private let limits: ParseLimits
    private let budget: OperationBudget
    private let cancellation: CancellationToken
    private var units: Int64
    protected prop maximumLiteralBytes: Int64 {
        get() {
            limits.maximumLiteralBytes
        }
    }

    protected init(document: Document, limits: ParseLimits, budget: OperationBudget, cancellation: CancellationToken) {
        this.limits = limits
        this.budget = budget
        this.cancellation = cancellation
        units = document.references.size
    }

    protected func step(): Unit {
        cancellation.throwIfCancelled(phase: "bind")
        budget.consumeScan()
    }

    protected func bytes(count: Int64): Unit {
        cancellation.throwIfCancelled(phase: "bind")
        budget.consumeScan(steps: count)
    }

    func referenceUnit(span: ?SourceSpan): Unit {
        step()
        if (units >= limits.maximumReferences) {
            throw LimitExceededException("reference_bindings", limits.maximumReferences, units + 1, "bind", span: span)
        }
        units++
    }
}

private class AnchorAllocator {
    private let scope: String
    private let used = HashSet<String>()
    private let suffixes = HashMap<String, Int64>()
    private let work: BindingWork

    protected init(options: BindingOptions, work: BindingWork) {
        scope = if (options.idScope.isEmpty()) {
            ""
        } else {
            options.idScope + "-"
        }
        this.work = work
    }

    func claim(preferred: String): String {
        let base = scope + preferred
        var candidate = base
        var suffix: Int64 = match (suffixes.get(base)) {
            case Some(value) => value;
            case None => 2
        }
        while (!used.add(candidate)) {
            work.step()
            candidate = "${base}-${suffix}"
            suffix++
        }
        suffixes.add(base, suffix)
        candidate
    }
}

private class PendingFootnoteBinding {
    protected let definition: NodeId
    protected let definitionIndex: Int64
    protected let number: Int64
    protected let definitionId: String
    protected let references = ArrayList<FootnoteReferenceBinding>()

    protected init(definition: NodeId, definitionIndex: Int64, number: Int64, definitionId: String) {
        this.definition = definition
        this.definitionIndex = definitionIndex
        this.number = number
        this.definitionId = definitionId
    }
}

// The ordinary batch path does not call this walk unless document-wide
// extension semantics are enabled. No CST, history, or source copy is created.
protected class DocumentBinder {
    protected static func bind(document: Document, options: BindingOptions, limits: ParseLimits,
        budget: OperationBudget, cancellation: CancellationToken, headingsEnabled!: Bool = false): Document {
        let work = BindingWork(document, limits, budget, cancellation)
        let firstDefinitions = HashMap<String, NodeRef>()
        let definitionReferences = HashMap<NodeId, ArrayList<NodeRef>>()
        let contexts = ArrayList<NodeId>()
        let bodyReferences = ArrayList<NodeRef>()
        let allReferences = ArrayList<NodeRef>()
        let diagnostics = ArrayList<Diagnostic>()
        let headingNodes = ArrayList<NodeRef>()
        let headingOwners = HashMap<NodeId, NodeId>()
        let linkNodes = ArrayList<NodeRef>()
        let linkOwners = HashMap<NodeId, NodeId>()
        let parents = ArrayList<NodeRef>()
        for (event in document.walk()) {
            work.step()
            match (event) {
                case NodeRefWalkEvent.Enter(node) =>
                    validateSemanticPayload(document, node, parents, work)
                    validateDefinitionListNode(document, node, parents, budget, cancellation)
                    validateMathNode(document, node, limits, budget, cancellation)
                    validateCodeGroupNode(node, parents, limits, budget, cancellation)
                    if (let NodeKind.Link <- node.kind) {
                        linkNodes.add(node)
                        if (!contexts.isEmpty()) {
                            linkOwners.add(node.nodeId, contexts[contexts.size - 1])
                        }
                    }
                    if (headingsEnabled && let NodeKind.Heading <- node.kind) {
                        headingNodes.add(node)
                        if (!contexts.isEmpty()) {
                            headingOwners.add(node.nodeId, contexts[contexts.size - 1])
                        }
                    }
                    if (let Some(payload) <- footnoteDefinitionPayload(node)) {
                        work.referenceUnit(node.span)
                        if (let Some(first) <- firstDefinitions.get(payload.labelNormalized)) {
                            diagnostics.add(
                                Diagnostic("MD4002_DUPLICATE_FOOTNOTE", DiagnosticSeverity.Warning,
                                    "duplicate footnote definition; the first definition is used", payload.labelSpan,
                                    relatedSpans: [first.span.getOrThrow()], extensionId: Some("footnotes")))
                        } else {
                            firstDefinitions.add(payload.labelNormalized, node)
                        }
                        definitionReferences.add(node.nodeId, ArrayList<NodeRef>())
                        contexts.add(node.nodeId)
                    } else if (footnoteReferencePayload(node).isSome()) {
                        work.referenceUnit(node.span)
                        allReferences.add(node)
                        if (contexts.isEmpty()) {
                            bodyReferences.add(node)
                        } else {
                            definitionReferences[contexts[contexts.size - 1]].add(node)
                        }
                    }
                    parents.add(node)
                case NodeRefWalkEvent.Exit(node) =>
                    if (footnoteDefinitionPayload(node).isSome()) {
                        contexts.remove(at: contexts.size - 1)
                    }
                    parents.remove(at: parents.size - 1)
            }
        }
        for (node in allReferences) {
            work.step()
            let payload = footnoteReferencePayload(node).getOrThrow()
            if (firstDefinitions.get(payload.labelNormalized).isNone()) {
                if (options.strictUndefinedFootnotes) {
                    throw MarkdownException(MarkdownErrorCode.InvalidReference, "undefined footnote reference",
                        phase: "bind", span: Some(payload.labelSpan))
                }
                diagnostics.add(
                    Diagnostic(if (payload.labelNormalized.isEmpty()) {
                        "MD4003_INVALID_FOOTNOTE"
                    } else {
                        "MD4001_UNDEFINED_FOOTNOTE"
                    }, DiagnosticSeverity.Warning,
                        "invalid or undefined footnote reference; the original syntax is preserved", payload.labelSpan,
                        extensionId: Some("footnotes")))
            }
        }
        let anchors = AnchorAllocator(options, work)
        let reachable = reachableDefinitions(bodyReferences, firstDefinitions, definitionReferences, work)
        let headings = bindHeadings(headingNodes, headingOwners, reachable, anchors, options, diagnostics, work)
        let active = HashMap<NodeId, PendingFootnoteBinding>()
        let ordered = ArrayList<PendingFootnoteBinding>()
        let references = HashMap<NodeId, FootnoteReferenceBinding>()
        bindReferences(bodyReferences, firstDefinitions, active, ordered, references, anchors, work)
        var cursor: Int64 = 0
        while (cursor < ordered.size) {
            work.step()
            let pending = ordered[cursor]
            bindReferences(definitionReferences[pending.definition], firstDefinitions, active, ordered, references,
                anchors, work)
            cursor++
        }
        let notes = ArrayList<FootnoteDefinitionBinding>()
        for (pending in ordered) {
            work.step()
            notes.add(
                FootnoteDefinitionBinding(pending.definition, pending.definitionIndex, pending.number,
                    pending.definitionId, pending.references.toArray()))
        }
        let links = bindLinks(linkNodes, linkOwners, reachable, headings, notes, options, work)
        document.withBindings(
            DocumentBindings(options, limits, parserConfigurationFingerprint(document.dialectFingerprint, limits,
                options), notes.toArray(), references, diagnostics.toArray(), headingsEnabled: headingsEnabled,
                headings: headings, links: links, semanticPayloadsValidated: true))
    }

    private static func bindLinks(nodes: ArrayList<NodeRef>, owners: HashMap<NodeId, NodeId>,
        reachable: HashSet<NodeId>, headings: Array<HeadingBinding>, notes: ArrayList<FootnoteDefinitionBinding>,
        options: BindingOptions, work: BindingWork): Array<LinkBinding> {
        let targets = HashMap<String, NodeId>()
        for (heading in headings) {
            targets.add(heading.id, heading.heading)
        }
        for (note in notes) {
            targets.add(note.definitionId, note.definition)
            for (reference in note.references.toArray()) {
                targets.add(reference.referenceId, reference.reference)
            }
        }
        let links = ArrayList<LinkBinding>()
        for (node in nodes) {
            work.step()
            if (let Some(owner) <- owners.get(node.nodeId)) {
                if (!reachable.contains(owner)) {
                    continue
                }
            }
            let destination = node.asLink().getOrThrow().destination
            var rendered = destination
            var target: ?NodeId = None
            if (destination.startsWith("#") && destination.size > 1) {
                if (let Some(fragment) <- decodeFragment(destination[1..], {count => work.bytes(count)})) {
                    var id = if (options.idScope.isEmpty()) {
                        fragment
                    } else {
                        options.idScope + "-" + fragment
                    }
                    target = targets.get(id)
                    if (target.isNone() && !options.idScope.isEmpty()) {
                        id = fragment
                        target = targets.get(id)
                    }
                    if (target.isSome()) {
                        rendered = "#${id}"
                    }
                }
            }
            links.add(LinkBinding(node.nodeId, destination, rendered, target))
        }
        links.toArray()
    }

    private static func reachableDefinitions(body: ArrayList<NodeRef>, definitions: HashMap<String, NodeRef>,
        children: HashMap<NodeId, ArrayList<NodeRef>>, work: BindingWork): HashSet<NodeId> {
        let reachable = HashSet<NodeId>()
        let pending = ArrayList<ArrayList<NodeRef>>()
        pending.add(body)
        var index: Int64 = 0
        while (index < pending.size) {
            for (reference in pending[index]) {
                work.step()
                if (let Some(definition) <- definitions.get(
                    footnoteReferencePayload(reference).getOrThrow().labelNormalized)) {
                    if (reachable.add(definition.nodeId)) {
                        pending.add(children[definition.nodeId])
                    }
                }
            }
            index++
        }
        reachable
    }

    private static func bindHeadings(nodes: ArrayList<NodeRef>, owners: HashMap<NodeId, NodeId>,
        reachable: HashSet<NodeId>, anchors: AnchorAllocator, options: BindingOptions,
        diagnostics: ArrayList<Diagnostic>, work: BindingWork): Array<HeadingBinding> {
        let visible = ArrayList<NodeRef>()
        let firstIds = HashMap<String, NodeRef>()
        let assigned = HashMap<NodeId, String>()
        for (node in nodes) {
            work.step()
            if (let Some(owner) <- owners.get(node.nodeId)) {
                if (!reachable.contains(owner)) {
                    continue
                }
            }
            visible.add(node)
            if (let Some(metadata) <- headingMetadata(node)) {
                if (firstIds.get(metadata.rawId).isNone()) {
                    firstIds.add(metadata.rawId, node)
                    work.referenceUnit(node.span)
                    assigned.add(node.nodeId, anchors.claim(metadata.rawId))
                }
            }
        }
        // Reserve every distinct explicit spelling before assigning suffixes
        // or automatic slugs, including explicit IDs appearing later in source.
        for (node in visible) {
            if (assigned.get(node.nodeId).isSome()) {
                continue
            }
            if (let Some(metadata) <- headingMetadata(node)) {
                work.referenceUnit(node.span)
                assigned.add(node.nodeId, anchors.claim(metadata.rawId))
                diagnostics.add(
                    Diagnostic("MD4010_DUPLICATE_HEADING_ID", DiagnosticSeverity.Warning,
                        "duplicate explicit heading ID; a unique suffix is used", metadata.idSpan,
                        relatedSpans: [headingMetadata(firstIds[metadata.rawId]).getOrThrow().idSpan],
                        extensionId: Some("heading-ids")))
            }
        }
        let result = ArrayList<HeadingBinding>()
        for (node in visible) {
            work.step()
            let text = headingDisplayText(node, {count => work.bytes(count)}, work.maximumLiteralBytes)
            let id = match (assigned.get(node.nodeId)) {
                case Some(value) => value
                case None =>
                    work.referenceUnit(node.span);
                    anchors.claim(headingSlug(text, {count => work.bytes(count)}))
            }
            result.add(HeadingBinding(node, text, id, headingMetadata(node), options.idScope))
        }
        result.toArray()
    }

    private static func validateSemanticPayload(document: Document, node: NodeRef, parents: ArrayList<NodeRef>,
        work: BindingWork): Unit {
        if (let Some(payload) <- footnoteDefinitionPayload(node)) {
            validatePayloadSource(document, node, payload.labelRaw, payload.labelSpan, work)
            if (payload.labelNormalized.isEmpty()) {
                invalidPayload(node, "empty footnote definition label")
            }
        } else if (let Some(payload) <- footnoteReferencePayload(node)) {
            validatePayloadSource(document, node, payload.labelRaw, payload.labelSpan, work)
            if (node.children().size != 0) {
                invalidPayload(node, "footnote references cannot have children")
            }
        } else if (let NodeKind.CustomInline <- node.kind) {
            let payload = node.asCustomInline().getOrThrow().payload
            if (payload is FootnoteDefinitionPayload) {
                invalidPayload(node, "footnote definitions must be blocks")
            }
            if (let metadata: HeadingIdPayload <- payload) {
                validatePayloadSource(document, node, metadata.rawId, metadata.idSpan, work)
                if (parents.isEmpty()) {
                    invalidPayload(node, "heading metadata requires a heading parent")
                }
                let parent = parents[parents.size - 1]
                if (parent.asHeading().isNone()) {
                    invalidPayload(node, "heading metadata requires a heading parent")
                }
                let children = parent.children()
                if (children[children.size - 1].nodeId != node.nodeId || node.children().size != 0) {
                    invalidPayload(node, "heading metadata must be a childless heading suffix")
                }
            }
        } else if (let NodeKind.CustomBlock <- node.kind) {
            let payload = node.asCustomBlock().getOrThrow().payload
            if (payload is FootnoteReferencePayload || payload is HeadingIdPayload) {
                invalidPayload(node, "inline semantic metadata cannot be a block")
            }
        }
    }

    private static func validatePayloadSource(document: Document, node: NodeRef, raw: String, span: SourceSpan,
        work: BindingWork): Unit {
        work.bytes(raw.size)
        if (let Some(nodeSpan) <- node.span) {
            if (nodeSpan.containsSpan(span)) {
                if (let Some(source) <- document.parserSourceBuffer()) {
                    if (span.endByte <= source.byteLength() && source.slice(span) == raw) {
                        return
                    }
                }
            }
        }
        invalidPayload(node, "semantic payload source is outside its node or does not match the original source")
    }

    private static func invalidPayload(node: NodeRef, message: String): Unit {
        throw MarkdownException(MarkdownErrorCode.ExtensionFailure, message, phase: "bind", span: node.span)
    }

    private static func bindReferences(nodes: ArrayList<NodeRef>, definitions: HashMap<String, NodeRef>,
        active: HashMap<NodeId, PendingFootnoteBinding>, ordered: ArrayList<PendingFootnoteBinding>,
        bindings: HashMap<NodeId, FootnoteReferenceBinding>, anchors: AnchorAllocator, work: BindingWork): Unit {
        for (node in nodes) {
            work.step()
            let payload = footnoteReferencePayload(node).getOrThrow()
            if (let Some(definition) <- definitions.get(payload.labelNormalized)) {
                let pending = match (active.get(definition.nodeId)) {
                    case Some(value) => value
                    case None =>
                        work.referenceUnit(definition.span)
                        let number = ordered.size + 1
                        let value = PendingFootnoteBinding(definition.nodeId, definition.index, number,
                            anchors.claim("fn-${number}"))
                        active.add(definition.nodeId, value)
                        ordered.add(value)
                        value
                }
                work.referenceUnit(node.span)
                work.referenceUnit(node.span)
                let binding = FootnoteReferenceBinding(node.nodeId, definition.nodeId, pending.number,
                    anchors.claim("fnref-${pending.number}-${pending.references.size + 1}"), pending.definitionId)
                pending.references.add(binding)
                bindings.add(node.nodeId, binding)
            }
        }
    }
}
