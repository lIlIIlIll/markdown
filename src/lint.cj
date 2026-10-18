package markdown

import std.collection.*
import std.unicode.*

/** lint diagnostic 的语义类别。 */
public enum LintCategory {
    /** 语法类 lint。 */
    | Syntax
    /** 安全类 lint。 */
    | Security
    /** 风格类 lint。 */
    | Style
    /** 可访问性 lint。 */
    | Accessibility
    /** 文档结构 lint。 */
    | DocumentStructure
    /** 扩展提供的 lint。 */
    | Extension
}

/** lint fix 的自动应用可信度。 */
public enum FixApplicability {
    /** 总是可以自动应用。 */
    | Always
    /** 自动应用可能不正确。 */
    | MaybeIncorrect
    /** 需要人工确认。 */
    | ManualReview
}

/** 绑定不可变 Document revision、源码 digest 和 edits 的 lint fix。 */
public class Fix {
    /** fix 的展示标题。 */
    public let title: String
    /** 要应用到源码的 edit 列表。 */
    public let edits: ImmutableArray<SourceEdit>
    /** 自动应用可信度。 */
    public let applicability: FixApplicability
    /** fix 生成时的 snapshot digest。 */
    public let sourceDigest: String
    /** fix 生成时的 Document revision。 */
    public let documentRevision: Int64
    /**
     * 创建 lint fix。
     * @param title fix 的展示标题。
     * @param edits 要应用到源码的 edit 列表。
     * @param applicability 自动应用可信度。
     * @param sourceDigest fix 生成时的 snapshot digest。
     * @param documentRevision fix 生成时的 Document revision。
     */
    public init(title: String, edits: Array<SourceEdit>, applicability: FixApplicability, sourceDigest: String,
        documentRevision: Int64) {
        this.title = title
        this.edits = ImmutableArray<SourceEdit>(edits)
        this.applicability = applicability
        this.sourceDigest = sourceDigest
        this.documentRevision = documentRevision
    }
}

/**
 * 编辑器可消费的 lint diagnostic。
 *
 * 除 code、severity、message 和 span 外，还可携带带 freshness 校验的 fixes。
 */
public class LintDiagnostic {
    /** lint 诊断代码。 */
    public let code: String
    /** 诊断类别。 */
    public let category: LintCategory
    /** 严重级别。 */
    public let severity: DiagnosticSeverity
    /** 人读消息。 */
    public let message: String
    /** 关联的 source span。 */
    public let span: SourceSpan
    /** 可选的自动修复列表。 */
    public let fixes: ImmutableArray<Fix>
    /**
     * 创建 lint 诊断。
     * @param code lint 诊断代码。
     * @param category 诊断类别。
     * @param severity 严重级别。
     * @param message 人读消息。
     * @param span 关联的 source span。
     * @param fixes 可选的自动修复列表。
     */
    public init(code: String, category: LintCategory, severity: DiagnosticSeverity, message: String, span: SourceSpan,
        fixes!: Array<Fix> = []) {
        this.code = code
        this.category = category
        this.severity = severity
        this.message = message
        this.span = span
        this.fixes = ImmutableArray<Fix>(fixes)
    }
}

/** 提供内建结构、安全、可访问性和 reference lint 规则。 */
public class MarkdownLinter {
    /** 对 snapshot 运行内建 lint；不会修改 snapshot。
     * @param snapshot 目标文档 snapshot。
     * @return 全部内建 lint 诊断。
     */
    public static func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic> {
        let out = ArrayList<LintDiagnostic>()
        for (diagnostic in snapshot.result.diagnostics.toArray()) {
            let fixes = ArrayList<Fix>()
            for (fix in diagnostic.fixes.toArray()) {
                fixes.add(
                    Fix(fix.title, [SourceEdit(fix.span, fix.replacement)], FixApplicability.MaybeIncorrect,
                        snapshot.sourceDigest, snapshot.result.document.revision))
            }
            out.add(
                LintDiagnostic(diagnostic.code, if (diagnostic.extensionId.isSome()) {
                    LintCategory.Extension
                } else {
                    LintCategory.Syntax
                }, diagnostic.severity, diagnostic.message, diagnostic.span, fixes: fixes.toArray()))
        }
        var previousHeading: Int64 = 0
        let usedReferenceDestinations = HashSet<String>()
        for (event in snapshot.result.document.walk()) {
            if (let NodeRefWalkEvent.Enter(node) <- event) {
                match (node.kind) {
                    case NodeKind.Heading =>
                        let heading = node.asHeading().getOrThrow()
                        if (previousHeading > 0 && heading.level > previousHeading + 1) {
                            out.add(
                                LintDiagnostic("MDL1001_HEADING_LEVEL_JUMP", LintCategory.DocumentStructure,
                                    DiagnosticSeverity.Warning, "heading level jumps by more than one",
                                    requiredLintSpan(node)))
                        }
                        previousHeading = heading.level
                    case NodeKind.Link =>
                        let link = node.asLink().getOrThrow()
                        if (let Some(binding) <- snapshot.result.document.bindings.linkForNode(node.nodeId)) {
                            if (binding.isLocalFragment && binding.destination.size > 1 && binding.target.isNone()) {
                                out.add(
                                    LintDiagnostic("MDL1005_MISSING_FRAGMENT", LintCategory.DocumentStructure,
                                        DiagnosticSeverity.Warning, "local fragment has no rendered target",
                                        requiredLintSpan(node)))
                            }
                        }
                        match (link.syntaxKind) {
                            case LinkSyntaxKind.FullReference => usedReferenceDestinations.add(link.destination)
                            case LinkSyntaxKind.CollapsedReference => usedReferenceDestinations.add(link.destination)
                            case LinkSyntaxKind.ShortcutReference => usedReferenceDestinations.add(link.destination)
                            case _ => ()
                        }
                        if (link.destination.isEmpty()) {
                            out.add(
                                LintDiagnostic("MDL2001_EMPTY_LINK", LintCategory.Accessibility,
                                    DiagnosticSeverity.Warning, "link destination is empty", requiredLintSpan(node)))
                        } else if (dangerousLintUri(link.destination)) {
                            out.add(
                                LintDiagnostic("MDL3001_UNSAFE_URI", LintCategory.Security, DiagnosticSeverity.Error,
                                    "link URI uses a dangerous scheme", requiredLintSpan(node)))
                        }
                    case NodeKind.Image =>
                        let image = node.asImage().getOrThrow()
                        match (image.syntaxKind) {
                            case LinkSyntaxKind.FullReference => usedReferenceDestinations.add(image.destination)
                            case LinkSyntaxKind.CollapsedReference => usedReferenceDestinations.add(image.destination)
                            case LinkSyntaxKind.ShortcutReference => usedReferenceDestinations.add(image.destination)
                            case _ => ()
                        }
                        if (plainLintText(node).isEmpty()) {
                            out.add(
                                LintDiagnostic("MDL2002_IMAGE_ALT_MISSING", LintCategory.Accessibility,
                                    DiagnosticSeverity.Warning, "image alt text is empty", requiredLintSpan(node)))
                        }
                        if (image.destination.isEmpty()) {
                            out.add(
                                LintDiagnostic("MDL2003_IMAGE_DESTINATION_EMPTY", LintCategory.Accessibility,
                                    DiagnosticSeverity.Warning, "image destination is empty", requiredLintSpan(node)))
                        }
                    case NodeKind.HtmlBlock => out.add(rawHtmlLint(snapshot, node))
                    case NodeKind.HtmlInline => out.add(rawHtmlLint(snapshot, node))
                    case NodeKind.Table =>
                        let table = node.asTable().getOrThrow()
                        for (row in node.children().toArray()) {
                            if (row.children().size != table.alignments.size) {
                                out.add(
                                    LintDiagnostic("MDL1004_TABLE_COLUMN_MISMATCH", LintCategory.Syntax,
                                        DiagnosticSeverity.Warning, "table row column count does not match header",
                                        requiredLintSpan(row)))
                            }
                        }
                    case NodeKind.Text =>
                        let text = node.asText().getOrThrow()
                        if (containsInvisible(text.value)) {
                            out.add(
                                LintDiagnostic("MDL3002_INVISIBLE_UNICODE", LintCategory.Security,
                                    DiagnosticSeverity.Warning, "text contains bidi or zero-width controls",
                                    requiredLintSpan(node)))
                        }
                    case _ => ()
                }
            }
        }
        let effective = HashSet<String>()
        for (reference in snapshot.result.document.root().asDocument().getOrThrow().references.toArray()) {
            if (!effective.add(reference.labelNormalized)) {
                out.add(
                    LintDiagnostic("MDL1002_DUPLICATE_REFERENCE", LintCategory.Syntax, DiagnosticSeverity.Warning,
                        "duplicate reference definition", reference.sourceSpan))
            }
            if (reference.isEffective && !usedReferenceDestinations.contains(reference.destination)) {
                out.add(
                    LintDiagnostic("MDL1003_UNUSED_REFERENCE", LintCategory.Syntax, DiagnosticSeverity.Info,
                        "reference definition is not used", reference.sourceSpan))
            }
        }
        appendMarkerAndAmbiguityLint(snapshot, out)
        out.toArray()
    }

    /** 应用与当前 snapshot digest 和 version 匹配的 fix。
     * @param snapshot fix 的目标 snapshot。
     * @param fix 要应用的 fix；过期时抛出异常。
     * @return 重新解析得到的 `ReparseResult`。
     * @throws IllegalStateException fix 已过期时。
     * @throws IllegalArgumentException edit 越界或重叠时。
     */
    public static func applyFix(snapshot: DocumentSnapshot, fix: Fix): ReparseResult {
        if (fix.sourceDigest != snapshot.sourceDigest || fix.documentRevision != snapshot.result.document.revision) {
            throw IllegalStateException("fix is stale for this snapshot")
        }
        snapshot.applyEdits(fix.edits.toArray())
    }
}

extend MarkdownEngine {
    /** 运行内建 lint 和 dialect 注册的扩展 lint providers。
     * @param snapshot 目标文档 snapshot。
     * @return 内建与扩展 lint 诊断。
     * @throws ExtensionFailureException 扩展 lint provider 失败时。
     */
    public func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic> {
        if (snapshot.engine.dialect.fingerprint != dialect.fingerprint) {
            throw IllegalArgumentException("snapshot was created by a different dialect")
        }
        let diagnostics = ArrayList<LintDiagnostic>()
        diagnostics.add(all: MarkdownLinter.lint(snapshot))
        for (index in 0..dialect.lintProviders.size) {
            let provider = dialect.lintProviders[index]
            try {
                diagnostics.add(all: provider.lint(snapshot))
            } catch (error: Exception) {
                let manifest = lintManifest(dialect.manifests, provider.extensionId)
                throw ExtensionFailureException(provider.extensionId, manifest.semanticVersion,
                    manifest.implementationVersion, "extension_lint", error, ruleId: Some(provider.ruleId))
            }
        }
        diagnostics.toArray()
    }
}

/** 指定 source byte offset 的 rule 候选、选择和 tie-break 解释。 */
public class ExplainResult {
    /** 候选 rule 标识列表。 */
    public let candidateRules: ImmutableArray<String>
    /** 被选中的 rule 标识。 */
    public let selectedRule: String
    /** 未选中的 rule 标识列表。 */
    public let rejectedRules: ImmutableArray<String>
    /** 选中 rule 的优先级。 */
    public let priority: Int64
    /** 平局裁决规则说明。 */
    public let tieBreak: String
    /** 向前查看的字节数。 */
    public let lookahead: Int64
    /** 决策时的容器状态描述。 */
    public let containerState: String
    /** 选中 rule 所属的扩展 id。 */
    public let extensionId: String
    /** 决策使用的 profile 子句。 */
    public let profileClause: String
    /** dialect fingerprint。 */
    public let fingerprint: String
    /**
     * 创建解释结果。
     * @param candidates 候选 rule 标识列表。
     * @param selected 被选中的 rule 标识。
     * @param rejected 未选中的 rule 标识列表。
     * @param priority 选中 rule 的优先级。
     * @param tieBreak 平局裁决规则说明。
     * @param lookahead 向前查看的字节数。
     * @param containerState 决策时的容器状态描述。
     * @param extensionId 选中 rule 所属的扩展 id。
     * @param profileClause 决策使用的 profile 子句。
     * @param fingerprint dialect fingerprint。
     */
    public init(candidates: Array<String>, selected: String, rejected: Array<String>, priority: Int64, tieBreak: String,
        lookahead: Int64, containerState: String, extensionId: String, profileClause: String, fingerprint: String) {
        candidateRules = ImmutableArray<String>(candidates)
        selectedRule = selected
        rejectedRules = ImmutableArray<String>(rejected)
        this.priority = priority
        this.tieBreak = tieBreak
        this.lookahead = lookahead
        this.containerState = containerState
        this.extensionId = extensionId
        this.profileClause = profileClause
        this.fingerprint = fingerprint
    }
}

/** 已编译 dialect 的 profile、rule 顺序、renderer coverage 和 limits 摘要。 */
public class CompiledDialectExplanation {
    /** 实际使用的 profile id。 */
    public let profileId: String
    /** block rule 的生效顺序。 */
    public let blockRuleOrder: ImmutableArray<String>
    /** inline rule 的生效顺序。 */
    public let inlineRuleOrder: ImmutableArray<String>
    /** parser SPI 的生效顺序。 */
    public let parserSpiOrder: ImmutableArray<String>
    /** renderer 覆盖的输出目标列表。 */
    public let rendererCoverage: ImmutableArray<String>
    /** 输入字节数上限。 */
    public let maximumInputBytes: Int64
    /** 嵌套深度上限。 */
    public let maximumNestingDepth: Int64
    /** dialect fingerprint。 */
    public let fingerprint: String
    /**
     * 从 engine 汇总 dialect 解释。
     * @param engine 目标 engine。
     */
    public init(engine: MarkdownEngine) {
        profileId = engine.profile.id
        let blocks = ArrayList<String>()
        for (index in 0..engine.dialect.blockRules.size) {
            let rule = engine.dialect.blockRules[index]
            blocks.add("${rule.extensionId}/${rule.ruleId}")
        }
        blockRuleOrder = ImmutableArray<String>(blocks.toArray())
        let inlines = ArrayList<String>()
        for (index in 0..engine.dialect.inlineRules.size) {
            let rule = engine.dialect.inlineRules[index]
            inlines.add("${rule.extensionId}/${rule.ruleId}")
        }
        inlineRuleOrder = ImmutableArray<String>(inlines.toArray())
        let spis = ArrayList<String>()
        for (index in 0..engine.dialect.parserSpis.size) {
            let spi = engine.dialect.parserSpis[index]
            spis.add("${spi.extensionId}/${spi.ruleId}")
        }
        parserSpiOrder = ImmutableArray<String>(spis.toArray())
        let renderers = ArrayList<String>()
        for (index in 0..engine.dialect.rendererRules.size) {
            let rule = engine.dialect.rendererRules[index]
            renderers.add("${rule.extensionId}/${rule.localKindId}")
        }
        rendererCoverage = ImmutableArray<String>(renderers.toArray())
        maximumInputBytes = engine.limits.maximumInputBytes
        maximumNestingDepth = engine.limits.maximumNestingDepth
        fingerprint = engine.dialect.fingerprint
    }
}

extend MarkdownEngine {
    /**
     * 返回当前 engine 的已编译 dialect 解释。
     * @return 已编译 dialect 的解释摘要。
     */
    public func explainDialect(): CompiledDialectExplanation {
        CompiledDialectExplanation(this)
    }

    /** 解释 source 指定 byte offset 的 rule 选择；offset 必须位于 source 内。
     * @param source 待解释的 Markdown 文本。
     * @param byteOffset 目标字节偏移。
     * @return 该偏移的 rule 选择解释。
     * @throws IllegalArgumentException offset 越界时。
     */
    public func explain(source: String, byteOffset: Int64): ExplainResult {
        if (byteOffset < 0 || byteOffset > source.size) {
            throw IllegalArgumentException("explain offset outside source")
        }
        let candidates = ArrayList<String>()
        for (rule in dialect.blockRules.toArray()) {
            candidates.add("block:${rule.extensionId}/${rule.ruleId}")
        }
        for (rule in dialect.inlineRules.toArray()) {
            candidates.add("inline:${rule.extensionId}/${rule.ruleId}")
        }
        candidates.add("commonmark:block")
        candidates.add("commonmark:inline")
        var selected = "commonmark:inline"
        var priority: Int64 = 0
        var extensionId = ""
        for (rule in dialect.inlineRules.toArray()) {
            if (byteOffset + rule.opener.size <= source.size && source[byteOffset..byteOffset + rule.opener.size] == rule
                .opener) {
                selected = "inline:${rule.extensionId}/${rule.ruleId}"
                priority = rule.priority
                extensionId = rule.extensionId
                break
            }
        }
        let rejected = ArrayList<String>()
        for (candidate in candidates) {
            if (candidate != selected) {
                rejected.add(candidate)
            }
        }
        ExplainResult(candidates.toArray(), selected, rejected.toArray(), priority,
            "phase>priority>registration-order>extension-id>rule-id", 0, "document", extensionId, profile.id,
            dialect.fingerprint)
    }
}

private func rawHtmlLint(snapshot: DocumentSnapshot, node: NodeRef): LintDiagnostic {
    let span = requiredLintSpan(node)
    let fix = Fix("Escape raw HTML", [SourceEdit(span, escapeLintHtml(snapshot.result.source.slice(span)))],
        FixApplicability.Always, snapshot.sourceDigest, snapshot.result.document.revision)
    LintDiagnostic("MDL3003_RAW_HTML", LintCategory.Security, DiagnosticSeverity.Warning, "raw HTML is present", span,
        fixes: [fix])
}

private func lintManifest(manifests: ImmutableArray<ExtensionManifest>, extensionId: String): ExtensionManifest {
    for (index in 0..manifests.size) {
        if (manifests[index].extensionId == extensionId) {
            return manifests[index]
        }
    }
    throw IllegalStateException("compiled dialect is missing extension manifest")
}

private func requiredLintSpan(node: NodeRef): SourceSpan {
    match (node.span) {
        case Some(span) => span;
        case None => SourceSpan(0, 0)
    }
}

private func dangerousLintUri(value: String): Bool {
    let lower = value.toLower().replace(" ", "").replace("\t", "")
    lower.startsWith("javascript:") || lower.startsWith("vbscript:") || lower.startsWith("file:")
}

private func containsInvisible(value: String): Bool {
    value.contains("\u{200B}") || value.contains("\u{200E}") || value.contains("\u{200F}") || value.contains("\u{202A}") ||
        value.contains("\u{202B}") || value.contains("\u{202D}") || value.contains("\u{202E}") || value.contains(
        "\u{2066}") || value.contains("\u{2067}") || value.contains("\u{2068}") || value.contains("\u{2069}") ||
        value.contains("\u{2028}") || value.contains("\u{2029}") || value.contains("\u{00AD}") || value.contains(
        "\u{FEFF}")
}

private func appendMarkerAndAmbiguityLint(snapshot: DocumentSnapshot, out: ArrayList<LintDiagnostic>): Unit {
    var firstBullet = ""
    for (token in snapshot.syntaxTree.root.tokens.toArray()) {
        match (token.kind) {
            case SyntaxKind.ListMarker =>
                if (token.raw == "-" || token.raw == "+" || token.raw == "*") {
                    if (firstBullet.isEmpty()) {
                        firstBullet = token.raw
                    } else if (token.raw != firstBullet) {
                        out.add(
                            LintDiagnostic("MDL4001_MIXED_LIST_MARKERS", LintCategory.Style, DiagnosticSeverity.Info,
                                "bullet list markers are mixed", token.span))
                        firstBullet = token.raw
                    }
                }
            case _ => ()
        }
    }
    for (event in snapshot.result.document.walk()) {
        if (let NodeRefWalkEvent.Enter(node) <- event) {
            if (let NodeKind.Text <- node.kind) {
                let text = node.asText().getOrThrow()
                if (text.raw.contains("**") || text.raw.contains("__") || text.raw.contains("~~") || text
                    .raw
                    .contains("[")) {
                    out.add(
                        LintDiagnostic("MDL1005_AMBIGUOUS_OR_UNCLOSED_SYNTAX", LintCategory.Syntax,
                            DiagnosticSeverity.Info, "text contains ambiguous or unclosed Markdown syntax",
                            requiredLintSpan(node)))
                }
            }
        }
    }
}

private func plainLintText(node: NodeRef): String {
    let out = StringBuilder()
    for (event in node.walk()) {
        if (let NodeRefWalkEvent.Enter(value) <- event) {
            if (let NodeKind.Text <- value.kind) {
                out.append(value.asText().getOrThrow().value)
            }
        }
    }
    out.toString()
}

private func escapeLintHtml(value: String): String {
    value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}
