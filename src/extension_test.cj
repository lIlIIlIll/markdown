package markdown

import std.unittest.*
import std.unittest.testmacro.*

class HashTagSpi <: InlineParserSpi {
    public prop extensionId: String {
        get() {
            "spi"
        }
    }
    public prop ruleId: String {
        get() {
            "hashtag"
        }
    }
    public prop maximumLookahead: Int64 {
        get() {
            64
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    public func tryParse(context: InlineParserSpiContext): InlineParserSpiResult {
        let start = context.startOffset
        if (start >= context.input.size || context.input[start] != b'#') {
            return InlineParserSpiResult.NoMatch
        }
        var end = start + 1
        while (end < context.input.size && end - start <= maximumLookahead && context.input[end] != b' ' &&
                context.input[end] != 10) {
            end++
        }
        if (end == start + 1) {
            return InlineParserSpiResult.NoMatch
        }
        let span = context.sourceSpan(start, end)
        let bodySpan = context.sourceSpan(start + 1, end)
        let body = context.input[start + 1..end]
        let origin = NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(span),
            extensionId: Some(extensionId))
        InlineParserSpiResult.Matched(
            CustomInline(context.nextNodeId(), extensionId, "1", ruleId, SyntaxPayload(ruleId, "", body),
                [Text(context.nextNodeId(), body, body, bodySpan)], Some(span), origin), end)
    }
}

private func countCustomKind(nodes: Array<MarkdownNode>, localKindId: String): Int64 {
    var count: Int64 = 0
    for (node in nodes) {
        match (node) {
            case value: CustomInline =>
                if (value.localKindId == localKindId) {
                    count++
                }
            case value: CustomBlock =>
                if (value.localKindId == localKindId) {
                    count++
                }
            case _ => ()
        }
    }
    count
}

class FailingInlineSpi <: InlineParserSpi {
    public prop extensionId: String {
        get() {
            "fail"
        }
    }
    public prop ruleId: String {
        get() {
            "failure"
        }
    }
    public prop maximumLookahead: Int64 {
        get() {
            8
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    public func tryParse(context: InlineParserSpiContext): InlineParserSpiResult {
        if (context.input[context.startOffset] == b'!') {
            throw IllegalStateException("callback failed")
        }
        InlineParserSpiResult.NoMatch
    }
}

class NamedPayload <: CustomPayload {
    public let value: String
    public init(value: String) {
        this.value = value
    }
    public func payloadTypeId(): String {
        "test.named-payload.v1"
    }
}

class NamedInlineEmitter <: InlinePayloadEmitter {
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        NamedPayload("inline:${value.literal}")
    }
}

class NamedBlockEmitter <: BlockPayloadEmitter {
    public func emit(value: BlockSyntaxMatch): CustomPayload {
        NamedPayload("block:${value.name}:${value.literal}")
    }
}

class PrefixProcessor <: ExtensionDocumentProcessor {
    private let prefix: String
    private let phaseValue: ExtensionProcessingPhase
    private let idValue: String
    public init(prefix: String, phase: ExtensionProcessingPhase, id: String) {
        this.prefix = prefix
        this.phaseValue = phase
        this.idValue = id
    }
    public prop extensionId: String {
        get() {
            "pipeline"
        }
    }
    public prop processorId: String {
        get() {
            idValue
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public prop phase: ExtensionProcessingPhase {
        get() {
            phaseValue
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    public func process(document: Document, budget: OperationBudget, cancellation: CancellationToken): Document {
        TreeRewriter.rewrite(document, {
            node => match (node) {
                case value: Text => RewriteAction.MapText(prefix + value.value)
                case _ => RewriteAction.Keep
            }
        }, budget: budget, cancellation: cancellation)
    }
}

class PipelineLintProvider <: ExtensionLintProvider {
    public prop extensionId: String {
        get() {
            "pipeline"
        }
    }
    public prop ruleId: String {
        get() {
            "marker"
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public func lint(_: DocumentSnapshot): Array<LintDiagnostic> {
        [LintDiagnostic("PIPELINE_MARKER", LintCategory.Extension, DiagnosticSeverity.Info, "pipeline lint executed",
            SourceSpan(0, 1))]
    }
}

@Test
class ExtensionDslTest {
    @TestCase
    func compilesAndRunsInlineBlockAndRendererDslEndToEnd(): Unit {
        let manifest = ExtensionManifest(
            "docs",
            "1.0.0",
            "build-1",
            capabilities: ExtensionCapabilities(specHtml: true, safeHtml: true, plainText: true, markdown: true)
        )
        let dialect = MarkdownDialect
            .define("docs-v1", "1.0.0")
            .base(MarkdownProfile.commonMark0312())
            .enable(manifest)
            .inline(InlineSyntax.define("docs", "highlight").delimiter("==").maximumLookahead(128).priority(200))
            .block(
                BlockSyntax
                    .define("docs", "container")
                    .opener(":::")
                    .closer(":::")
                    .content(BlockContentMode.Markdown)
                    .maximumBlockBytes(4096)
                    .priority(100)
                    .parameter("title", SyntaxParameterType.StringValue, required: true))
            .renderer(
                RendererRule("docs", "highlight", "mark", classToken: "highlight", markdownOpener: "==",
                    markdownCloser: "==", textPrefix: "[", textSuffix: "]"))
            .renderer(
                RendererRule(
                    "docs",
                    "note",
                    "aside",
                    classToken: "admonition-note",
                    markdownOpener: ":::note",
                    markdownCloser: ":::",
                    attributes: [
                        RendererAttributeSpec("data-title", RendererAttributeKind.Text,
                            RendererAttributeSource.PayloadParameter("title")),
                        RendererAttributeSpec("href", RendererAttributeKind.LinkUri,
                            RendererAttributeSource.FixedValue("javascript:blocked"))
                    ]
                )
            )
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let result = engine.parse(":::note title=Careful\nA **bold** body.\n:::\n\nUse ==this==.")
        @Expect(result.document.children().size, 2)
        match (result.document.children()[0]) {
            case custom: CustomBlock =>
                @Expect(custom.localKindId, "note")
                match (custom.payload) {
                    case payload: SyntaxPayload =>
                        @Expect(payload.parameters, "title=Careful")
                        @Expect(payload.literal, "A **bold** body.")
                        match (payload.parameter("title")) {
                            case Some(SyntaxParameterValue.StringValue(value)) => @Expect(value, "Careful")
                            case _ => @Expect(false)
                        }
                    case _ => @Expect(false)
                }
                @Expect(custom.children().size, 1)
            case _ => @Expect(false)
        }
        let html = HtmlRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(result.document)
        @Expect(html.contains("<aside class=\"admonition-note\" data-title=\"Careful\"><p>A <strong>bold</strong> body.</p>"),
            true)
        @Expect(html.contains("javascript:"), false)
        @Expect(html.contains("<mark class=\"highlight\">this</mark>"), true)
        @Expect(PlainTextRenderer(extensionRules: engine.dialect.rendererRules.toArray())
            .render(result.document).contains("Use [this]."), true)
        let formatted = CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray()).render(
            result.document)
        @Expect(formatted.contains(":::note title=Careful\n"), true)
        @Expect(formatted.contains("==this=="), true)
    }

    @TestCase
    func unknownAndUnclosedSyntaxHaveDeterministicFallbackAndDiagnostic(): Unit {
        let manifest = ExtensionManifest("docs", "1.0.0", "1")
        let dialect = MarkdownDialect
            .define("docs", "1")
            .enable(manifest)
            .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let unknown = engine.parse("%%%unknown")
        match (unknown.document.children()[0]) {
            case paragraph: Paragraph => match (paragraph.children()[0]) {
                case text: Text => @Expect(text.value, "%%%unknown")
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let unclosed = engine.parse(":::note\nbody")
        @Expect(unclosed.diagnostics.size, 1)
        @Expect(unclosed.diagnostics[0].code, "MD3002_UNCLOSED_EXTENSION")
        @Expect(unclosed.diagnostics[0].extensionId, Some("docs"))
    }

    @TestCase
    func typedBlockParametersHonorQuotesEscapesTypesAndInvalidDiagnostics(): Unit {
        let dialect = MarkdownDialect
            .define("typed", "1")
            .enable(ExtensionManifest("typed", "1.0.0", "1"))
            .block(
                BlockSyntax
                    .define("typed", "box")
                    .opener(":::")
                    .closer(":::")
                    .parameter("title", SyntaxParameterType.StringValue, required: true)
                    .parameter("count", SyntaxParameterType.IntegerValue)
                    .parameter("enabled", SyntaxParameterType.BooleanValue)
                    .parameter("kind", SyntaxParameterType.IdentifierValue))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let valid = engine.parse(":::box title=\"hello world\" count=3 enabled=true kind=note\nbody\n:::")
        match (valid.document.children()[0]) {
            case custom: CustomBlock => match (custom.payload) {
                case payload: SyntaxPayload =>
                    match (payload.parameter("title")) {
                        case Some(SyntaxParameterValue.StringValue(value)) => @Expect(value, "hello world")
                        case _ => @Expect(false)
                    }
                    match (payload.parameter("count")) {
                        case Some(SyntaxParameterValue.IntegerValue(value)) => @Expect(value, 3)
                        case _ => @Expect(false)
                    }
                    match (payload.parameter("enabled")) {
                        case Some(SyntaxParameterValue.BooleanValue(value)) => @Expect(value, true)
                        case _ => @Expect(false)
                    }
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }
        let invalid = engine.parse(":::box title=x count=nope\nbody\n:::")
        @Expect(invalid.diagnostics.size > 0, true)
        @Expect(invalid.diagnostics[0].code, "MD3003_INVALID_EXTENSION_PARAMETER")
        @Expect(AstQuery.customNodes(invalid.document).size, 0)
    }

    @TestCase
    func compilerRejectsConflictsDependenciesUnboundedRulesAndMissingRenderer(): Unit {
        let base = ExtensionManifest("a", "1.0.0", "1")
        let missingDependency = ExtensionManifest("b", "1.0.0", "1", dependencies: ["missing"])
        expectCompileFailure(MarkdownDialect.define("x", "1").enable(base).enable(missingDependency).build())

        let duplicateRules = MarkdownDialect
            .define("x", "1")
            .enable(base)
            .inline(InlineSyntax.define("a", "one").delimiter("=="))
            .inline(InlineSyntax.define("a", "two").delimiter("=="))
            .build()
        expectCompileFailure(duplicateRules)

        let unbounded = MarkdownDialect
            .define("x", "1")
            .enable(base)
            .inline(InlineSyntax.define("a", "one").delimiter("==").maximumLookahead(0))
            .build()
        expectCompileFailure(unbounded)

        let needsRenderer = ExtensionManifest("rendered", "1.0.0", "1",
            capabilities: ExtensionCapabilities(safeHtml: true))
        expectCompileFailure(MarkdownDialect.define("x", "1").enable(needsRenderer).build())
    }

    @TestCase
    func dialectOptionsLimitsAndFingerprintAreRuntimeEffective(): Unit {
        let manifest = ExtensionManifest("docs", "1.0.0", "1")
        let small = ParseLimits(64, 64, 16, 128, 16, 16, 32, 64, 256, 32, 32)
        let disabledDialect = MarkdownDialect
            .define("docs", "1")
            .enable(manifest)
            .inline(InlineSyntax.define("docs", "mark").delimiter("=="))
            .parserOptions(DialectParserOptions(extensionsEnabled: false))
            .limits(small)
            .build()
        let disabled = MarkdownEngine.builder().dialect(disabledDialect).build()
        @Expect(disabled.limits.maximumInputBytes, 64)
        @Expect(AstQuery.customNodes(disabled.parse("==x==").document).size, 0)

        let quietDialect = MarkdownDialect
            .define("docs", "1")
            .enable(manifest)
            .inline(InlineSyntax.define("docs", "mark").delimiter("=="))
            .parserOptions(DialectParserOptions(emitUnclosedExtensionDiagnostics: false))
            .build()
        let quiet = MarkdownEngine.builder().dialect(quietDialect).build()
        @Expect(quiet.parse("==open").diagnostics.size, 0)
        @Expect(disabled.dialect.fingerprint == quiet.dialect.fingerprint, false)

        let explicit = MarkdownEngine.builder().dialect(disabledDialect).limits(ParseLimits.trusted()).build()
        @Expect(explicit.limits.maximumInputBytes, ParseLimits.trusted().maximumInputBytes)
    }

    @TestCase
    func compilerRejectsProfileCyclesVersionsRuleIdentityAndCapabilities(): Unit {
        expectCompileFailure(
            MarkdownDialect
                .define("profile", "1")
                .enable(ExtensionManifest("only-gfm", "1.0.0", "1", supportedProfiles: ["gfm-modern-v1"]))
                .build())

        let cycleA = ExtensionManifest("a", "1.0.0", "1", dependencies: ["b"])
        let cycleB = ExtensionManifest("b", "1.0.0", "1", dependencies: ["a"])
        expectCompileFailure(MarkdownDialect.define("cycle", "1").enable(cycleA).enable(cycleB).build())

        let dependency = ExtensionManifest("dependency", "1.5.0", "1")
        let consumer = ExtensionManifest("consumer", "1.0.0", "1",
            dependencyConstraints: [ExtensionDependency("dependency", "2.0.0")])
        expectCompileFailure(MarkdownDialect.define("version", "1").enable(dependency).enable(consumer).build())

        let duplicate = ExtensionManifest("duplicate", "1.0.0", "1")
        expectCompileFailure(
            MarkdownDialect
                .define("rules", "1")
                .enable(duplicate)
                .inline(InlineSyntax.define("duplicate", "same").delimiter("=="))
                .block(BlockSyntax.define("duplicate", "same").opener(":::").closer(":::"))
                .build())

        let noParse = ExtensionManifest("no-parse", "1.0.0", "1", capabilities: ExtensionCapabilities(parse: false))
        expectCompileFailure(
            MarkdownDialect
                .define("capability", "1")
                .enable(noParse)
                .inline(InlineSyntax.define("no-parse", "mark").delimiter("=="))
                .build())

        let noMarkdownLowering = ExtensionManifest("format", "1.0.0", "1",
            capabilities: ExtensionCapabilities(markdown: true))
        expectCompileFailure(
            MarkdownDialect
                .define("format", "1")
                .enable(noMarkdownLowering)
                .renderer(RendererRule("format", "node", "span"))
                .build())

        expectCompileFailure(
            MarkdownDialect
                .define("lint-capability", "1")
                .enable(ExtensionManifest("lint-only", "1.0.0", "1", capabilities: ExtensionCapabilities(lint: true)))
                .build())
        expectCompileFailure(
            MarkdownDialect
                .define("incremental-capability", "1")
                .enable(
                    ExtensionManifest("incremental", "1.0.0", "1",
                        capabilities: ExtensionCapabilities(incremental: true)))
                .build())
    }

    @TestCase
    func semanticVersionConstraintsFollowSemVerPrecedenceAndRejectInvalidVersions(): Unit {
        let release = ExtensionManifest("dependency", "1.0.0", "release")
        let acceptsPrereleaseMinimum = ExtensionManifest("consumer", "1.0.0", "1",
            dependencyConstraints: [ExtensionDependency("dependency", "1.0.0-alpha.9")])
        let compiled = MarkdownDialect.define("semver", "1").enable(release).enable(acceptsPrereleaseMinimum).build()
        @Expect(compiled.manifests.size, 2)

        let prerelease = ExtensionManifest("dependency", "1.0.0-alpha.10+build.7", "pre")
        let acceptsNumericOrdering = ExtensionManifest("consumer", "1.0.0", "1",
            dependencyConstraints: [ExtensionDependency("dependency", "1.0.0-alpha.2+ignored")])
        @Expect(
            MarkdownDialect
                .define("semver-pre", "1")
                .enable(prerelease)
                .enable(acceptsNumericOrdering)
                .build()
                .manifests
                .size,
            2)

        let needsRelease = ExtensionManifest("consumer", "1.0.0", "1",
            dependencyConstraints: [ExtensionDependency("dependency", "1.0.0")])
        expectCompileFailure(
            MarkdownDialect.define("semver-release", "1").enable(prerelease).enable(needsRelease).build())

        for (invalid in ["1", "1.0", "01.0.0", "1.01.0", "1.0.01", "1.0.0-", "1.0.0-alpha..1", "1.0.0-alpha.01",
            "1.0.0+", "1.0.0+build..1", "9223372036854775808.0.0"]) {
            expectCompileFailure(
                MarkdownDialect.define("invalid-semver", "1").enable(ExtensionManifest("invalid", invalid, "1")).build())
        }

        let invalidMinimum = ExtensionManifest("consumer", "1.0.0", "1",
            dependencyConstraints: [ExtensionDependency("dependency", "1.0")])
        expectCompileFailure(
            MarkdownDialect.define("invalid-minimum", "1").enable(release).enable(invalidMinimum).build())
    }

    @TestCase
    func syntaxDslKindsEscapingFlankingNestingEmittersAndCostsAreEffective(): Unit {
        let manifest = ExtensionManifest("syntax", "1.0.0", "1")
        let dialect = MarkdownDialect
            .define("syntax", "1")
            .enable(manifest)
            .inline(InlineSyntax.define("syntax", "escaped").delimiter("=="))
            .inline(
                InlineSyntax
                    .define("syntax", "literal")
                    .delimiter("%%")
                    .escaping(InlineEscapePolicy.LiteralBackslash)
                    .emit(NamedInlineEmitter()))
            .inline(InlineSyntax.define("syntax", "token").token("@here").flanking(InlineFlankingRule.WordBoundary))
            .inline(
                InlineSyntax
                    .define("syntax", "metadata")
                    .metadataSuffix("{#", "}")
                    .flanking(InlineFlankingRule.WordBoundary))
            .inline(
                InlineSyntax
                    .define("syntax", "nested")
                    .delimiter("{{", closer: "}}")
                    .nesting(true)
                    .flanking(InlineFlankingRule.CommonMark))
            .block(
                BlockSyntax
                    .define("syntax", "container")
                    .opener(":::")
                    .closer(":::")
                    .nesting(true)
                    .emit(NamedBlockEmitter()))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let inline = engine.parse("\\==escaped== \\%%literal%% @here word@here x{#id} {{outer {{inner}} end}}")
        let custom = AstQuery.customNodes(inline.document)
        @Expect(countCustomKind(custom, "escaped"), 0)
        @Expect(countCustomKind(custom, "literal"), 1)
        @Expect(countCustomKind(custom, "token"), 1)
        @Expect(countCustomKind(custom, "metadata"), 1)
        @Expect(countCustomKind(custom, "nested"), 2)
        var sawMetadataPhase = false
        for (index in 0..engine.dialect.inlineRules.size) {
            let rule = engine.dialect.inlineRules[index]
            if (rule.ruleId == "metadata") {
                match (rule.phase) {
                    case SyntaxPhase.Metadata => sawMetadataPhase = true
                    case _ => ()
                }
                match (rule.backtrackingPolicy) {
                    case SyntaxBacktrackingPolicy.None => @Expect(true)
                }
                @Expect(rule.tieBreak, "registration-order>extension-id>rule-id")
            }
        }
        @Expect(sawMetadataPhase, true)
        for (node in custom) {
            if (let value: CustomInline <- node) {
                if (value.localKindId == "literal") {
                    match (value.payload) {
                        case named: NamedPayload => @Expect(named.value, "inline:literal")
                        case _ => @Expect(false)
                    }
                }
            }
        }

        let blocks = engine.parse(":::outer\n:::inner\nbody\n:::\n:::")
        @Expect(countCustomKind(AstQuery.customNodes(blocks.document), "outer"), 1)
        @Expect(countCustomKind(AstQuery.customNodes(blocks.document), "inner"), 1)
        match (blocks.document.children()[0]) {
            case outer: CustomBlock => match (outer.payload) {
                case named: NamedPayload => @Expect(named.value.contains("block:outer:"), true)
                case _ => @Expect(false)
            }
            case _ => @Expect(false)
        }

        let nonNested = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("non-nested", "1")
                    .enable(ExtensionManifest("non-nested", "1.0.0", "1"))
                    .block(BlockSyntax.define("non-nested", "container").opener(":::").closer(":::").nesting(false))
                    .build())
            .build()
        let nonNestedResult = nonNested.parse(":::outer\n:::inner\nbody\n:::\n:::")
        @Expect(AstQuery.customNodes(nonNestedResult.document).size, 1)

        let ordered = DialectCompiler.compile(
            MarkdownDialect
                .define("ordered", "1")
                .enable(ExtensionManifest("ordered", "1.0.0", "1"))
                .inline(InlineSyntax.define("ordered", "metadata").metadataSuffix("{#", "}"))
                .inline(InlineSyntax.define("ordered", "paired").delimiter("=="))
                .build())
        @Expect(ordered.inlineRules[0].ruleId, "paired")
        @Expect(ordered.inlineRules[1].ruleId, "metadata")

        let costly = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("cost", "1")
                    .enable(ExtensionManifest("cost", "1.0.0", "1"))
                    .inline(
                        InlineSyntax
                            .define("cost", "mark")
                            .delimiter("==")
                            .resourceCost(SyntaxResourceCost(baseCost: 1000, perByteCost: 10)))
                    .build())
            .build()
        try {
            costly.parse("==x==", budget: OperationBudget(100, 100, 10, 10, 100, 100))
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.BudgetExceeded => @Expect(true)
                case _ => @Expect(false)
            }
        }
    }

    @TestCase
    func extensionPostprocessTransformLintAndFormatterCategoriesRunInFixedOrder(): Unit {
        let manifest = ExtensionManifest("pipeline", "1.0.0", "build-1",
            capabilities: ExtensionCapabilities(postprocess: true, transform: true, lint: true))
        let dialect = MarkdownDialect
            .define("pipeline", "1")
            .enable(manifest)
            .documentProcessor(PrefixProcessor("T:", ExtensionProcessingPhase.AstTransform, "transform"))
            .documentProcessor(PrefixProcessor("P:", ExtensionProcessingPhase.DocumentPostprocess, "post"))
            .lint(PipelineLintProvider())
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let parsed = engine.parse("x")
        @Expect(PlainTextRenderer().render(parsed.document), "T:P:x")
        match (AstQuery.descendants(parsed.document)[1].origin.kind) {
            case NodeOriginKind.Transformed => @Expect(true)
            case _ => @Expect(false)
        }
        @Expect(engine.dialect.documentProcessors[0].processorId, "post")
        @Expect(engine.dialect.documentProcessors[1].processorId, "transform")
        let lint = engine.lint(engine.parseSnapshot("x"))
        var found = false
        for (diagnostic in lint) {
            if (diagnostic.code == "PIPELINE_MARKER") {
                found = true
            }
        }
        @Expect(found, true)

        let missingCapabilities = ExtensionManifest("pipeline", "1.0.0", "1")
        expectCompileFailure(
            MarkdownDialect
                .define("missing-pipeline-capability", "1")
                .enable(missingCapabilities)
                .documentProcessor(PrefixProcessor("P:", ExtensionProcessingPhase.DocumentPostprocess, "post"))
                .build())
    }

    @TestCase
    func builderDisableRemovesRegistrationBeforeCompilation(): Unit {
        let dialect = MarkdownDialect
            .define("x", "1")
            .enable(ExtensionManifest("temp", "1.0.0", "1"))
            .inline(InlineSyntax.define("temp", "mark").delimiter("=="))
            .disable("temp")
            .build()
        let compiled = DialectCompiler.compile(dialect)
        @Expect(compiled.manifests.size, 0)
        @Expect(compiled.inlineRules.size, 0)
    }

    @TestCase
    func boundedParserSpiRunsAndFailuresAreStructuredWithoutStateLeak(): Unit {
        let dialect = MarkdownDialect
            .define("spi", "1")
            .enable(ExtensionManifest("spi", "1.0.0", "build-1"))
            .parserSpi(HashTagSpi())
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let parsed = engine.parse("Use #topic now")
        @Expect(AstQuery.customNodes(parsed.document).size, 1)
        match (AstQuery.customNodes(parsed.document)[0]) {
            case custom: CustomInline =>
                @Expect(custom.localKindId, "hashtag")
                @Expect(custom.span, Some(SourceSpan(4, 10)))
            case _ => @Expect(false)
        }

        let nodeLimited = ParseLimits(1024, 1024, 16, 3, 16, 16, 1024, 1024, 4096, 1024, 1024)
        try {
            MarkdownEngine.builder().dialect(dialect).limits(nodeLimited).build().parse("#topic")
            @Expect(false)
        } catch (error: LimitExceededException) {
            @Expect(error.limitKind, "ast_nodes")
            @Expect(error.phase, "ast_allocation")
        }

        let failing = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("fail", "1")
                    .enable(ExtensionManifest("fail", "1.2.0", "broken-build"))
                    .parserSpi(FailingInlineSpi())
                    .build())
            .build()
        try {
            failing.parse("!");
            @Expect(false)
        } catch (error: ExtensionFailureException) {
            @Expect(error.extensionId, "fail")
            @Expect(error.semanticVersion, "1.2.0")
            @Expect(error.implementationVersion, "broken-build")
            @Expect(error.ruleId, Some("failure"))
            @Expect(error.cause.message, "callback failed")
        }
        // A failed parse owns its state; a later parse on the same immutable
        // engine starts from a clean session.
        @Expect(HtmlRenderer().render(failing.parse("ok").document), "<p>ok</p>\n")
    }

    private func expectCompileFailure(dialect: MarkdownDialect): Unit {
        try {
            DialectCompiler.compile(dialect)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.ExtensionConflict => @Expect(error.phase, "dialect_compile")
                case _ => @Expect(false)
            }
        }
    }
}
