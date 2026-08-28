package markdown

import std.collection.*
import std.unicode.*

public enum LintCategory {
    | Syntax
    | Security
    | Style
    | Accessibility
    | DocumentStructure
    | Extension
}

public enum FixApplicability {
    | Always
    | MaybeIncorrect
    | ManualReview
}

public class Fix {
    public let title: String
    public let edits: ImmutableArray<SourceEdit>
    public let applicability: FixApplicability
    public let sourceDigest: String
    public let snapshotVersion: Int64
    public init(title: String, edits: Array<SourceEdit>, applicability: FixApplicability, sourceDigest: String,
        snapshotVersion: Int64) {
        this.title = title
        this.edits = ImmutableArray<SourceEdit>(edits)
        this.applicability = applicability
        this.sourceDigest = sourceDigest
        this.snapshotVersion = snapshotVersion
    }
}

public class LintDiagnostic {
    public let code: String
    public let category: LintCategory
    public let severity: DiagnosticSeverity
    public let message: String
    public let span: SourceSpan
    public let fixes: ImmutableArray<Fix>
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

public class MarkdownLinter {
    public static func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic> {
        let out = ArrayList<LintDiagnostic>()
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

    public static func applyFix(snapshot: DocumentSnapshot, fix: Fix): ReparseResult {
        if (fix.sourceDigest != snapshot.sourceDigest || fix.snapshotVersion != snapshot.version) {
            throw IllegalStateException("fix is stale for this snapshot")
        }
        snapshot.applyEdits(fix.edits.toArray())
    }
}

extend MarkdownEngine {
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

public class ExplainResult {
    public let candidateRules: ImmutableArray<String>
    public let selectedRule: String
    public let rejectedRules: ImmutableArray<String>
    public let priority: Int64
    public let tieBreak: String
    public let lookahead: Int64
    public let containerState: String
    public let extensionId: String
    public let profileClause: String
    public let fingerprint: String
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

public class CompiledDialectExplanation {
    public let profileId: String
    public let blockRuleOrder: ImmutableArray<String>
    public let inlineRuleOrder: ImmutableArray<String>
    public let parserSpiOrder: ImmutableArray<String>
    public let rendererCoverage: ImmutableArray<String>
    public let maximumInputBytes: Int64
    public let maximumNestingDepth: Int64
    public let fingerprint: String
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
    public func explainDialect(): CompiledDialectExplanation {
        CompiledDialectExplanation(this)
    }

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
        FixApplicability.Always, snapshot.sourceDigest, snapshot.version)
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
