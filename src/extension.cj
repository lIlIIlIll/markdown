package markdown

import std.collection.*
import std.unicode.*

public enum MissingRendererPolicy {
    | Error
    | RenderChildren
    | RenderLiteral
    | Drop
    | CustomFallback
}

public class ExtensionCapabilities {
    public let parse: Bool
    public let specHtml: Bool
    public let safeHtml: Bool
    public let plainText: Bool
    public let markdown: Bool
    public let cst: Bool
    public let format: Bool
    public let serialize: Bool
    public let incremental: Bool
    public let lint: Bool
    public let postprocess: Bool
    public let transform: Bool

    public init(
        parse!: Bool = true,
        specHtml!: Bool = false,
        safeHtml!: Bool = false,
        plainText!: Bool = false,
        markdown!: Bool = false,
        cst!: Bool = false,
        format!: Bool = false,
        serialize!: Bool = false,
        incremental!: Bool = false,
        lint!: Bool = false,
        postprocess!: Bool = false,
        transform!: Bool = false
    ) {
        this.parse = parse
        this.specHtml = specHtml
        this.safeHtml = safeHtml
        this.plainText = plainText
        this.markdown = markdown
        this.cst = cst
        this.format = format
        this.serialize = serialize
        this.incremental = incremental
        this.lint = lint
        this.postprocess = postprocess
        this.transform = transform
    }
}

public class ExtensionDependency {
    public let extensionId: String
    public let minimumSemanticVersion: String
    public init(extensionId: String, minimumSemanticVersion: String) {
        this.extensionId = extensionId
        this.minimumSemanticVersion = minimumSemanticVersion
    }
}

public class ExtensionManifest {
    public let extensionId: String
    public let semanticVersion: String
    public let implementationVersion: String
    public let requiredSpiVersion: String
    public let supportedProfiles: ImmutableArray<String>
    public let dependencies: ImmutableArray<String>
    public let dependencyConstraints: ImmutableArray<ExtensionDependency>
    public let conflicts: ImmutableArray<String>
    public let capabilities: ExtensionCapabilities
    public let ruleBudget: Int64
    public let trustLevel: String
    public let missingRendererPolicy: MissingRendererPolicy
    public let shareable: Bool

    public init(
        extensionId: String,
        semanticVersion: String,
        implementationVersion: String,
        requiredSpiVersion!: String = "1",
        supportedProfiles!: Array<String> = ["commonmark-0.31.2", "gfm-modern-v1"],
        dependencies!: Array<String> = [],
        dependencyConstraints!: Array<ExtensionDependency> = [],
        conflicts!: Array<String> = [],
        capabilities!: ExtensionCapabilities = ExtensionCapabilities(),
        ruleBudget!: Int64 = 100000,
        trustLevel!: String = "host-code",
        missingRendererPolicy!: MissingRendererPolicy = MissingRendererPolicy.Error,
        shareable!: Bool = true
    ) {
        this.extensionId = extensionId
        this.semanticVersion = semanticVersion
        this.implementationVersion = implementationVersion
        this.requiredSpiVersion = requiredSpiVersion
        this.supportedProfiles = ImmutableArray<String>(supportedProfiles)
        this.dependencies = ImmutableArray<String>(dependencies)
        this.dependencyConstraints = ImmutableArray<ExtensionDependency>(dependencyConstraints)
        this.conflicts = ImmutableArray<String>(conflicts)
        this.capabilities = capabilities
        this.ruleBudget = ruleBudget
        this.trustLevel = trustLevel
        this.missingRendererPolicy = missingRendererPolicy
        this.shareable = shareable
    }
}

public class InlineParserSpiContext {
    public let input: String
    public let startOffset: Int64
    public let maximumLookahead: Int64
    private let baseByteOffset: Int64
    private let source: SourceBuffer
    private let ids: NodeIdAllocator
    public let budget: OperationBudget
    public let cancellation: CancellationToken

    internal init(input: String, startOffset: Int64, maximumLookahead: Int64, baseByteOffset: Int64,
        source: SourceBuffer, ids: NodeIdAllocator, budget: OperationBudget, cancellation: CancellationToken) {
        this.input = input
        this.startOffset = startOffset
        this.maximumLookahead = maximumLookahead
        this.baseByteOffset = baseByteOffset
        this.source = source
        this.ids = ids
        this.budget = budget
        this.cancellation = cancellation
    }

    public func nextNodeId(): NodeId {
        ids.next()
    }
    public func sourceSpan(localStart: Int64, localEnd: Int64): SourceSpan {
        if (localStart < 0 || localEnd < localStart || localEnd > input.size) {
            throw IllegalArgumentException("SPI span is outside inline input")
        }
        SourceSpan(source.originalOffset(baseByteOffset + localStart), source.originalOffset(baseByteOffset + localEnd))
    }
}

public enum InlineParserSpiResult {
    | NoMatch
    | Matched(CustomInline, Int64)
}

public interface InlineParserSpi {
    prop extensionId: String
    prop ruleId: String
    prop maximumLookahead: Int64
    prop priority: Int64
    prop deterministic: Bool
    func tryParse(context: InlineParserSpiContext): InlineParserSpiResult
}

public enum ExtensionProcessingPhase {
    | DocumentPostprocess
    | AstTransform
}

public interface ExtensionDocumentProcessor {
    prop extensionId: String
    prop processorId: String
    prop version: String
    prop phase: ExtensionProcessingPhase
    prop priority: Int64
    prop deterministic: Bool
    func process(document: Document, budget: OperationBudget, cancellation: CancellationToken): Document
}

public interface ExtensionLintProvider {
    prop extensionId: String
    prop ruleId: String
    prop version: String
    func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic>
}

public enum InlineSyntaxKind {
    | PairedDelimiter
    | SingleToken
    | MetadataSuffix
}

public enum InlineEscapePolicy {
    | CommonMarkBackslash
    | LiteralBackslash
}

public enum InlineFlankingRule {
    | Any
    | CommonMark
    | WordBoundary
}

public enum SyntaxPhase {
    | Inline
    | Block
    | Metadata
}

public enum SyntaxBacktrackingPolicy {
    | None
}

public class SyntaxResourceCost {
    public let baseCost: Int64
    public let perByteCost: Int64
    public init(baseCost!: Int64 = 1, perByteCost!: Int64 = 1) {
        if (baseCost < 0 || perByteCost < 0) {
            throw IllegalArgumentException("syntax resource costs must be non-negative")
        }
        this.baseCost = baseCost
        this.perByteCost = perByteCost
    }
}

public class InlineSyntaxMatch {
    public let extensionId: String
    public let ruleId: String
    public let literal: String
    public let span: SourceSpan
    public let children: ImmutableArray<MarkdownNode>
    public init(extensionId: String, ruleId: String, literal: String, span: SourceSpan, children: Array<MarkdownNode>) {
        this.extensionId = extensionId
        this.ruleId = ruleId
        this.literal = literal
        this.span = span
        this.children = ImmutableArray<MarkdownNode>(children)
    }
}

public interface InlinePayloadEmitter {
    func emit(value: InlineSyntaxMatch): CustomPayload
}

public class InlineSyntaxRule {
    public let extensionId: String
    public let ruleId: String
    public let opener: String
    public let closer: String
    public let parseChildren: Bool
    public let emitContent: Bool
    public let allowNesting: Bool
    public let maximumDelimiterLength: Int64
    public let maximumLookahead: Int64
    public let priority: Int64
    public let conflictGroup: String
    public let syntaxKind: InlineSyntaxKind
    public let escapePolicy: InlineEscapePolicy
    public let flankingRule: InlineFlankingRule
    public let phase: SyntaxPhase
    public let tieBreak: String
    public let backtrackingPolicy: SyntaxBacktrackingPolicy
    public let resourceCost: SyntaxResourceCost
    public let emitter: ?InlinePayloadEmitter
    internal let registrationOrder: Int64

    internal init(builder: InlineSyntaxBuilder, registrationOrder: Int64) {
        extensionId = builder.extensionId
        ruleId = builder.ruleId
        opener = builder.openerValue
        closer = builder.closerValue
        parseChildren = builder.parseChildrenValue
        emitContent = builder.emitContentValue
        allowNesting = builder.allowNestingValue
        maximumDelimiterLength = builder.maximumDelimiterLengthValue
        maximumLookahead = builder.maximumLookaheadValue
        priority = builder.priorityValue
        conflictGroup = builder.conflictGroupValue
        syntaxKind = builder.syntaxKindValue
        escapePolicy = builder.escapePolicyValue
        flankingRule = builder.flankingRuleValue
        phase = match (syntaxKind) {
            case InlineSyntaxKind.MetadataSuffix => SyntaxPhase.Metadata
            case _ => SyntaxPhase.Inline
        }
        tieBreak = "registration-order>extension-id>rule-id"
        backtrackingPolicy = SyntaxBacktrackingPolicy.None
        resourceCost = builder.resourceCostValue
        emitter = builder.emitterValue
        this.registrationOrder = registrationOrder
    }
}

public class InlineSyntaxBuilder {
    public let extensionId: String
    public let ruleId: String
    internal var openerValue = ""
    internal var closerValue = ""
    internal var parseChildrenValue = true
    internal var emitContentValue = true
    internal var allowNestingValue = true
    internal var maximumDelimiterLengthValue: Int64 = 16
    internal var maximumLookaheadValue: Int64 = 4096
    internal var priorityValue: Int64 = 100
    internal var conflictGroupValue = ""
    internal var syntaxKindValue = InlineSyntaxKind.PairedDelimiter
    internal var escapePolicyValue = InlineEscapePolicy.CommonMarkBackslash
    internal var flankingRuleValue = InlineFlankingRule.Any
    internal var resourceCostValue = SyntaxResourceCost()
    internal var emitterValue: ?InlinePayloadEmitter = None

    internal init(extensionId: String, ruleId: String) {
        this.extensionId = extensionId
        this.ruleId = ruleId
    }

    public func delimiter(opener: String, closer!: String = ""): InlineSyntaxBuilder {
        syntaxKindValue = InlineSyntaxKind.PairedDelimiter
        openerValue = opener
        closerValue = if (closer.isEmpty()) {
            opener
        } else {
            closer
        }
        this
    }
    public func token(value: String): InlineSyntaxBuilder {
        syntaxKindValue = InlineSyntaxKind.SingleToken
        openerValue = value
        closerValue = ""
        parseChildrenValue = false
        emitContentValue = false
        allowNestingValue = false
        this
    }
    public func metadataSuffix(opener: String, closer: String): InlineSyntaxBuilder {
        syntaxKindValue = InlineSyntaxKind.MetadataSuffix
        openerValue = opener
        closerValue = closer
        parseChildrenValue = false
        emitContentValue = false
        allowNestingValue = false
        this
    }
    public func escaping(policy: InlineEscapePolicy): InlineSyntaxBuilder {
        escapePolicyValue = policy
        this
    }
    public func flanking(rule: InlineFlankingRule): InlineSyntaxBuilder {
        flankingRuleValue = rule
        this
    }
    public func content(parseChildren: Bool): InlineSyntaxBuilder {
        parseChildrenValue = parseChildren
        this
    }
    public func emitContent(enabled: Bool): InlineSyntaxBuilder {
        emitContentValue = enabled
        this
    }
    public func nesting(allow: Bool): InlineSyntaxBuilder {
        allowNestingValue = allow
        this
    }
    public func maximumDelimiterLength(value: Int64): InlineSyntaxBuilder {
        maximumDelimiterLengthValue = value
        this
    }
    public func maximumLookahead(value: Int64): InlineSyntaxBuilder {
        maximumLookaheadValue = value
        this
    }
    public func priority(value: Int64): InlineSyntaxBuilder {
        priorityValue = value
        this
    }
    public func conflictGroup(value: String): InlineSyntaxBuilder {
        conflictGroupValue = value
        this
    }
    public func resourceCost(cost: SyntaxResourceCost): InlineSyntaxBuilder {
        resourceCostValue = cost
        this
    }
    public func emit(emitter: InlinePayloadEmitter): InlineSyntaxBuilder {
        emitterValue = Some(emitter)
        this
    }
}

public class InlineSyntax {
    public static func define(extensionId: String, ruleId: String): InlineSyntaxBuilder {
        InlineSyntaxBuilder(extensionId, ruleId)
    }
}

// cjlint-ignore -start !G.ENU.01 Public BlockContentMode.Markdown is the frozen DSL spelling.
public enum BlockContentMode {
    | Markdown
    | Literal
}

public enum BlockSyntaxKind {
    | PairedContainer
    | SingleLine
}

// cjlint-ignore -end Public BlockContentMode.Markdown is the frozen DSL spelling.
public enum SyntaxParameterType {
    | StringValue
    | IntegerValue
    | BooleanValue
    | IdentifierValue
}

public enum SyntaxParameterValue {
    | StringValue(String)
    | IntegerValue(Int64)
    | BooleanValue(Bool)
    | IdentifierValue(String)
}

public class SyntaxParameterSpec {
    public let name: String
    public let parameterType: SyntaxParameterType
    public let required: Bool
    public init(name: String, parameterType: SyntaxParameterType, required!: Bool = false) {
        if (name.isEmpty()) {
            throw IllegalArgumentException("parameter name must not be empty")
        }
        this.name = name
        this.parameterType = parameterType
        this.required = required
    }
}

public class BlockSyntaxMatch {
    public let extensionId: String
    public let ruleId: String
    public let name: String
    public let parametersRaw: String
    public let literal: String
    public let span: SourceSpan
    public let children: ImmutableArray<MarkdownNode>
    private let typedValues: HashMap<String, SyntaxParameterValue>

    public init(extensionId: String, ruleId: String, name: String, parametersRaw: String, literal: String,
        span: SourceSpan, children: Array<MarkdownNode>, typedValues: HashMap<String, SyntaxParameterValue>) {
        this.extensionId = extensionId
        this.ruleId = ruleId
        this.name = name
        this.parametersRaw = parametersRaw
        this.literal = literal
        this.span = span
        this.children = ImmutableArray<MarkdownNode>(children)
        this.typedValues = typedValues
    }

    public func parameter(name: String): ?SyntaxParameterValue {
        typedValues.get(name)
    }
}

public interface BlockPayloadEmitter {
    func emit(value: BlockSyntaxMatch): CustomPayload
}

public class BlockSyntaxRule {
    public let extensionId: String
    public let ruleId: String
    public let openerPrefix: String
    public let closer: String
    public let contentMode: BlockContentMode
    public let allowNesting: Bool
    public let maximumBlockBytes: Int64
    public let maximumCaptureLength: Int64
    public let priority: Int64
    public let conflictGroup: String
    public let parameters: ImmutableArray<SyntaxParameterSpec>
    public let phase: SyntaxPhase
    public let tieBreak: String
    public let backtrackingPolicy: SyntaxBacktrackingPolicy
    public let resourceCost: SyntaxResourceCost
    public let emitter: ?BlockPayloadEmitter
    public let syntaxKind: BlockSyntaxKind
    public let kindFromFirstWord: Bool
    public let documentStartOnly: Bool
    internal let registrationOrder: Int64

    internal init(builder: BlockSyntaxBuilder, registrationOrder: Int64) {
        extensionId = builder.extensionId
        ruleId = builder.ruleId
        openerPrefix = builder.openerPrefixValue
        closer = builder.closerValue
        contentMode = builder.contentModeValue
        allowNesting = builder.allowNestingValue
        maximumBlockBytes = builder.maximumBlockBytesValue
        maximumCaptureLength = builder.maximumCaptureLengthValue
        priority = builder.priorityValue
        conflictGroup = builder.conflictGroupValue
        parameters = ImmutableArray<SyntaxParameterSpec>(builder.parameterValues.toArray())
        phase = SyntaxPhase.Block
        tieBreak = "registration-order>extension-id>rule-id"
        backtrackingPolicy = SyntaxBacktrackingPolicy.None
        resourceCost = builder.resourceCostValue
        emitter = builder.emitterValue
        syntaxKind = builder.syntaxKindValue
        kindFromFirstWord = builder.kindFromFirstWordValue
        documentStartOnly = builder.documentStartOnlyValue
        this.registrationOrder = registrationOrder
    }
}

public class BlockSyntaxBuilder {
    public let extensionId: String
    public let ruleId: String
    internal var openerPrefixValue = ""
    internal var closerValue = ""
    internal var contentModeValue = BlockContentMode.Markdown
    internal var allowNestingValue = true
    internal var maximumBlockBytesValue: Int64 = 1048576
    internal var maximumCaptureLengthValue: Int64 = 4096
    internal var priorityValue: Int64 = 100
    internal var conflictGroupValue = ""
    internal let parameterValues = ArrayList<SyntaxParameterSpec>()
    internal var resourceCostValue = SyntaxResourceCost()
    internal var emitterValue: ?BlockPayloadEmitter = None
    internal var syntaxKindValue = BlockSyntaxKind.PairedContainer
    internal var kindFromFirstWordValue = true
    internal var documentStartOnlyValue = false

    internal init(extensionId: String, ruleId: String) {
        this.extensionId = extensionId
        this.ruleId = ruleId
    }

    public func opener(prefix: String): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.PairedContainer
        openerPrefixValue = prefix
        this
    }
    public func linePrefix(prefix: String): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.SingleLine
        openerPrefixValue = prefix
        closerValue = ""
        allowNestingValue = false
        this
    }
    public func closer(exact: String): BlockSyntaxBuilder {
        closerValue = exact
        this
    }
    public func content(mode: BlockContentMode): BlockSyntaxBuilder {
        contentModeValue = mode
        this
    }
    public func nesting(allow: Bool): BlockSyntaxBuilder {
        allowNestingValue = allow
        this
    }
    public func maximumBlockBytes(value: Int64): BlockSyntaxBuilder {
        maximumBlockBytesValue = value
        this
    }
    public func maximumCaptureLength(value: Int64): BlockSyntaxBuilder {
        maximumCaptureLengthValue = value
        this
    }
    public func priority(value: Int64): BlockSyntaxBuilder {
        priorityValue = value
        this
    }
    public func conflictGroup(value: String): BlockSyntaxBuilder {
        conflictGroupValue = value
        this
    }
    public func parameter(name: String, parameterType: SyntaxParameterType, required!: Bool = false): BlockSyntaxBuilder {
        parameterValues.add(SyntaxParameterSpec(name, parameterType, required: required));
        this
    }
    public func resourceCost(cost: SyntaxResourceCost): BlockSyntaxBuilder {
        resourceCostValue = cost
        this
    }
    public func emit(emitter: BlockPayloadEmitter): BlockSyntaxBuilder {
        emitterValue = Some(emitter)
        this
    }
    public func kindFromFirstWord(enabled: Bool): BlockSyntaxBuilder {
        kindFromFirstWordValue = enabled
        this
    }
    public func documentStartOnly(enabled!: Bool = true): BlockSyntaxBuilder {
        documentStartOnlyValue = enabled
        this
    }
}

public class BlockSyntax {
    public static func define(extensionId: String, ruleId: String): BlockSyntaxBuilder {
        BlockSyntaxBuilder(extensionId, ruleId)
    }
}

// cjlint-ignore -start !G.ENU.01 Public RendererAttributeKind.Text is the frozen DSL spelling.
public enum RendererAttributeKind {
    | Text
    | LinkUri
    | ImageUri
}
// cjlint-ignore -end Public RendererAttributeKind.Text is the frozen DSL spelling.

public enum RendererAttributeSource {
    | FixedValue(String)
    | PayloadParameter(String)
    | PayloadLiteral
}

public class RendererAttributeSpec {
    public let name: String
    public let kind: RendererAttributeKind
    public let source: RendererAttributeSource
    public init(name: String, kind: RendererAttributeKind, source: RendererAttributeSource) {
        this.name = name
        this.kind = kind
        this.source = source
    }
}

public enum MarkdownBlockLowering {
    | Container
    | Line
}

public class RendererRule {
    public let extensionId: String
    public let localKindId: String
    public let htmlTag: String
    public let classToken: String
    public let markdownOpener: String
    public let markdownCloser: String
    public let textPrefix: String
    public let textSuffix: String
    public let attributes: ImmutableArray<RendererAttributeSpec>
    public let renderPayloadLiteral: Bool
    public let markdownBlockLowering: MarkdownBlockLowering

    public init(
        extensionId: String,
        localKindId: String,
        htmlTag: String,
        classToken!: String = "",
        markdownOpener!: String = "",
        markdownCloser!: String = "",
        textPrefix!: String = "",
        textSuffix!: String = "",
        attributes!: Array<RendererAttributeSpec> = [],
        renderPayloadLiteral!: Bool = false,
        markdownBlockLowering!: MarkdownBlockLowering = MarkdownBlockLowering.Container
    ) {
        this.extensionId = extensionId
        this.localKindId = localKindId
        this.htmlTag = htmlTag
        this.classToken = classToken
        this.markdownOpener = markdownOpener
        this.markdownCloser = markdownCloser
        this.textPrefix = textPrefix
        this.textSuffix = textSuffix
        this.attributes = ImmutableArray<RendererAttributeSpec>(attributes)
        this.renderPayloadLiteral = renderPayloadLiteral
        this.markdownBlockLowering = markdownBlockLowering
    }
}

public class DialectParserOptions {
    public let emitUnclosedExtensionDiagnostics: Bool
    public let extensionsEnabled: Bool

    public init(emitUnclosedExtensionDiagnostics!: Bool = true, extensionsEnabled!: Bool = true) {
        this.emitUnclosedExtensionDiagnostics = emitUnclosedExtensionDiagnostics
        this.extensionsEnabled = extensionsEnabled
    }
}

public class MarkdownDialect {
    public let id: String
    public let version: String
    public let baseProfile: MarkdownProfile
    public let parserOptions: DialectParserOptions
    public let limits: ParseLimits
    internal let manifests: Array<ExtensionManifest>
    internal let inlineBuilders: Array<InlineSyntaxBuilder>
    internal let blockBuilders: Array<BlockSyntaxBuilder>
    internal let rendererRules: Array<RendererRule>
    internal let parserSpis: Array<InlineParserSpi>
    internal let documentProcessors: Array<ExtensionDocumentProcessor>
    internal let lintProviders: Array<ExtensionLintProvider>

    internal init(builder: MarkdownDialectBuilder) {
        id = builder.id
        version = builder.version
        baseProfile = builder.baseProfileValue
        parserOptions = builder.parserOptionsValue
        limits = builder.limitsValue
        manifests = builder.manifests.toArray()
        inlineBuilders = builder.inlineBuilders.toArray()
        blockBuilders = builder.blockBuilders.toArray()
        rendererRules = builder.rendererRules.toArray()
        parserSpis = builder.parserSpis.toArray()
        documentProcessors = builder.documentProcessors.toArray()
        lintProviders = builder.lintProviders.toArray()
    }

    public static func define(id: String, version: String): MarkdownDialectBuilder {
        MarkdownDialectBuilder(id, version)
    }
}

public class MarkdownDialectBuilder {
    public let id: String
    public let version: String
    internal var baseProfileValue = MarkdownProfile.commonMark0312()
    internal var parserOptionsValue = DialectParserOptions()
    internal var limitsValue = ParseLimits.safe()
    internal let manifests = ArrayList<ExtensionManifest>()
    internal let inlineBuilders = ArrayList<InlineSyntaxBuilder>()
    internal let blockBuilders = ArrayList<BlockSyntaxBuilder>()
    internal let rendererRules = ArrayList<RendererRule>()
    internal let parserSpis = ArrayList<InlineParserSpi>()
    internal let documentProcessors = ArrayList<ExtensionDocumentProcessor>()
    internal let lintProviders = ArrayList<ExtensionLintProvider>()

    internal init(id: String, version: String) {
        this.id = id
        this.version = version
    }

    public func base(profile: MarkdownProfile): MarkdownDialectBuilder {
        baseProfileValue = profile
        this
    }
    public func parserOptions(options: DialectParserOptions): MarkdownDialectBuilder {
        parserOptionsValue = options
        this
    }
    public func limits(limits: ParseLimits): MarkdownDialectBuilder {
        limitsValue = limits
        this
    }
    public func enable(manifest: ExtensionManifest): MarkdownDialectBuilder {
        manifests.add(manifest);
        this
    }
    public func inline(rule: InlineSyntaxBuilder): MarkdownDialectBuilder {
        inlineBuilders.add(rule);
        this
    }
    public func block(rule: BlockSyntaxBuilder): MarkdownDialectBuilder {
        blockBuilders.add(rule);
        this
    }
    public func renderer(rule: RendererRule): MarkdownDialectBuilder {
        rendererRules.add(rule);
        this
    }
    public func parserSpi(spi: InlineParserSpi): MarkdownDialectBuilder {
        parserSpis.add(spi);
        this
    }
    public func documentProcessor(processor: ExtensionDocumentProcessor): MarkdownDialectBuilder {
        documentProcessors.add(processor)
        this
    }
    public func lint(provider: ExtensionLintProvider): MarkdownDialectBuilder {
        lintProviders.add(provider)
        this
    }
    public func disable(extensionId: String): MarkdownDialectBuilder {
        manifests.removeIf({manifest => manifest.extensionId == extensionId})
        inlineBuilders.removeIf({rule => rule.extensionId == extensionId})
        blockBuilders.removeIf({rule => rule.extensionId == extensionId})
        rendererRules.removeIf({rule => rule.extensionId == extensionId})
        parserSpis.removeIf({spi => spi.extensionId == extensionId})
        documentProcessors.removeIf({processor => processor.extensionId == extensionId})
        lintProviders.removeIf({provider => provider.extensionId == extensionId})
        this
    }
    public func build(): MarkdownDialect {
        MarkdownDialect(this)
    }
}

public class CompiledMarkdownDialect {
    public let id: String
    public let version: String
    public let baseProfile: MarkdownProfile
    public let parserOptions: DialectParserOptions
    public let declaredLimits: ParseLimits
    public let fingerprint: String
    public let manifests: ImmutableArray<ExtensionManifest>
    public let inlineRules: ImmutableArray<InlineSyntaxRule>
    public let blockRules: ImmutableArray<BlockSyntaxRule>
    public let rendererRules: ImmutableArray<RendererRule>
    public let parserSpis: ImmutableArray<InlineParserSpi>
    public let documentProcessors: ImmutableArray<ExtensionDocumentProcessor>
    public let lintProviders: ImmutableArray<ExtensionLintProvider>

    internal init(
        dialect: MarkdownDialect,
        inlineRules: Array<InlineSyntaxRule>,
        blockRules: Array<BlockSyntaxRule>,
        parserSpis: Array<InlineParserSpi>,
        documentProcessors: Array<ExtensionDocumentProcessor>,
        lintProviders: Array<ExtensionLintProvider>,
        fingerprint: String
    ) {
        id = dialect.id
        version = dialect.version
        baseProfile = dialect.baseProfile
        parserOptions = dialect.parserOptions
        declaredLimits = dialect.limits
        this.fingerprint = fingerprint
        manifests = ImmutableArray<ExtensionManifest>(dialect.manifests)
        this.inlineRules = ImmutableArray<InlineSyntaxRule>(inlineRules)
        this.blockRules = ImmutableArray<BlockSyntaxRule>(blockRules)
        rendererRules = ImmutableArray<RendererRule>(dialect.rendererRules)
        this.parserSpis = ImmutableArray<InlineParserSpi>(parserSpis)
        this.documentProcessors = ImmutableArray<ExtensionDocumentProcessor>(documentProcessors)
        this.lintProviders = ImmutableArray<ExtensionLintProvider>(lintProviders)
    }

    public static func builtin(profile: MarkdownProfile): CompiledMarkdownDialect {
        DialectCompiler.compile(MarkdownDialect.define(profile.id, profile.standardVersion).base(profile).build())
    }
}

public class DialectCompiler {
    public static func compile(dialect: MarkdownDialect): CompiledMarkdownDialect {
        validateIdentifier("dialect id", dialect.id)
        validateIdentifier("dialect version", dialect.version)
        let manifestIds = HashSet<String>()
        for (manifest in dialect.manifests) {
            validateManifest(manifest)
            if (!supportsProfile(manifest, dialect.baseProfile.id)) {
                fail("extension ${manifest.extensionId} does not support profile ${dialect.baseProfile.id}")
            }
            if (!manifestIds.add(manifest.extensionId)) {
                fail("duplicate extension id: ${manifest.extensionId}")
            }
        }
        for (manifest in dialect.manifests) {
            for (dependency in manifest.dependencies.toArray()) {
                if (!manifestIds.contains(dependency)) {
                    fail("missing extension dependency: ${dependency}")
                }
            }
            for (constraint in manifest.dependencyConstraints.toArray()) {
                if (parseSemanticVersion(constraint.minimumSemanticVersion).isNone()) {
                    fail("invalid minimum semantic version for dependency: ${constraint.extensionId}")
                }
                let found = findManifest(dialect.manifests, constraint.extensionId)
                match (found) {
                    case Some(dependency) =>
                        if (!semanticVersionAtLeast(dependency.semanticVersion, constraint.minimumSemanticVersion)) {
                            fail("extension dependency version is not satisfied: ${constraint.extensionId}")
                        }
                    case None => fail("missing extension dependency: ${constraint.extensionId}")
                }
            }
            for (conflict in manifest.conflicts.toArray()) {
                if (manifestIds.contains(conflict)) {
                    fail("extension conflict: ${manifest.extensionId} vs ${conflict}")
                }
            }
        }
        validateDependencyGraph(dialect.manifests)
        let ruleIdentities = HashSet<String>()
        let inline = ArrayList<InlineSyntaxRule>()
        for (index in 0..dialect.inlineBuilders.size) {
            let builder = dialect.inlineBuilders[index]
            if (!manifestIds.contains(builder.extensionId)) {
                fail("inline rule extension is not enabled")
            }
            validateInline(builder)
            if (!ruleIdentities.add("${builder.extensionId}/${builder.ruleId}")) {
                fail("duplicate rule id: ${builder.extensionId}/${builder.ruleId}")
            }
            inline.add(InlineSyntaxRule(builder, index))
        }
        let block = ArrayList<BlockSyntaxRule>()
        for (index in 0..dialect.blockBuilders.size) {
            let builder = dialect.blockBuilders[index]
            if (!manifestIds.contains(builder.extensionId)) {
                fail("block rule extension is not enabled")
            }
            validateBlock(builder)
            if (!ruleIdentities.add("${builder.extensionId}/${builder.ruleId}")) {
                fail("duplicate rule id: ${builder.extensionId}/${builder.ruleId}")
            }
            block.add(BlockSyntaxRule(builder, index))
        }
        rejectRuleConflicts(inline.toArray(), block.toArray())
        validateParserSpis(dialect, manifestIds)
        for (spi in dialect.parserSpis) {
            if (!ruleIdentities.add("${spi.extensionId}/${spi.ruleId}")) {
                fail("duplicate rule id: ${spi.extensionId}/${spi.ruleId}")
            }
        }
        let spis = ArrayList<InlineParserSpi>()
        spis.add(all: dialect.parserSpis)
        sortParserSpis(spis)
        let processors = ArrayList<ExtensionDocumentProcessor>()
        processors.add(all: dialect.documentProcessors)
        validateDocumentProcessors(processors, manifestIds)
        sortDocumentProcessors(processors)
        let lintProviders = ArrayList<ExtensionLintProvider>()
        lintProviders.add(all: dialect.lintProviders)
        validateLintProviders(lintProviders, manifestIds)
        sortInline(inline)
        sortBlock(block)
        validateCapabilities(dialect)
        validateRenderers(dialect, manifestIds)
        let canonical = canonicalDescriptor(dialect, inline.toArray(), block.toArray())
        CompiledMarkdownDialect(dialect, inline.toArray(), block.toArray(), spis.toArray(), processors.toArray(),
            lintProviders.toArray(), stableDescriptorDigest(canonical))
    }

    private static func validateParserSpis(dialect: MarkdownDialect, manifestIds: HashSet<String>): Unit {
        let identities = HashSet<String>()
        for (spi in dialect.parserSpis) {
            if (!manifestIds.contains(spi.extensionId)) {
                fail("parser SPI extension is not enabled")
            }
            validateIdentifier("parser SPI rule id", spi.ruleId)
            if (spi.maximumLookahead <= 0) {
                fail("parser SPI lookahead must be bounded")
            }
            if (!spi.deterministic) {
                fail("non-deterministic parser SPI is not supported")
            }
            let identity = "${spi.extensionId}/${spi.ruleId}"
            if (!identities.add(identity)) {
                fail("duplicate parser SPI rule id")
            }
        }
    }

    private static func validateDocumentProcessors(values: ArrayList<ExtensionDocumentProcessor>,
        manifestIds: HashSet<String>): Unit {
        let identities = HashSet<String>()
        for (processor in values) {
            if (!manifestIds.contains(processor.extensionId)) {
                fail("document processor extension is not enabled")
            }
            validateIdentifier("document processor id", processor.processorId)
            validateIdentifier("document processor version", processor.version)
            if (!processor.deterministic) {
                fail("non-deterministic document processor is not supported")
            }
            if (!identities.add("${processor.extensionId}/${processor.processorId}")) {
                fail("duplicate document processor id")
            }
        }
    }

    private static func validateLintProviders(values: ArrayList<ExtensionLintProvider>, manifestIds: HashSet<String>): Unit {
        let identities = HashSet<String>()
        for (provider in values) {
            if (!manifestIds.contains(provider.extensionId)) {
                fail("lint provider extension is not enabled")
            }
            validateIdentifier("extension lint rule id", provider.ruleId)
            validateIdentifier("extension lint version", provider.version)
            if (!identities.add("${provider.extensionId}/${provider.ruleId}")) {
                fail("duplicate extension lint rule id")
            }
        }
    }

    private static func validateDependencyGraph(manifests: Array<ExtensionManifest>): Unit {
        let remaining = ArrayList<ExtensionManifest>()
        remaining.add(all: manifests)
        let resolved = HashSet<String>()
        while (!remaining.isEmpty()) {
            var selected: Int64 = -1
            for (index in 0..remaining.size) {
                let manifest = remaining[index]
                var ready = true
                for (dependency in manifest.dependencies.toArray()) {
                    if (!resolved.contains(dependency)) {
                        ready = false
                        break
                    }
                }
                if (ready) {
                    for (constraint in manifest.dependencyConstraints.toArray()) {
                        if (!resolved.contains(constraint.extensionId)) {
                            ready = false
                            break
                        }
                    }
                }
                if (ready && (selected < 0 || manifest.extensionId < remaining[selected].extensionId)) {
                    selected = index
                }
            }
            if (selected < 0) {
                fail("extension dependency cycle")
            }
            resolved.add(remaining[selected].extensionId)
            remaining.remove(at: selected)
        }
    }

    private static func validateCapabilities(dialect: MarkdownDialect): Unit {
        for (manifest in dialect.manifests) {
            var hasParser = false
            var hasPostprocessor = false
            var hasTransform = false
            var hasLint = false
            for (rule in dialect.inlineBuilders) {
                if (rule.extensionId == manifest.extensionId) {
                    hasParser = true
                }
            }
            for (rule in dialect.blockBuilders) {
                if (rule.extensionId == manifest.extensionId) {
                    hasParser = true
                }
            }
            for (spi in dialect.parserSpis) {
                if (spi.extensionId == manifest.extensionId) {
                    hasParser = true
                }
            }
            if (hasParser && !manifest.capabilities.parse) {
                fail("extension parser rules require parse capability")
            }
            for (processor in dialect.documentProcessors) {
                if (processor.extensionId == manifest.extensionId) {
                    match (processor.phase) {
                        case ExtensionProcessingPhase.DocumentPostprocess =>
                            hasPostprocessor = true
                            if (!manifest.capabilities.postprocess) {
                                fail("document postprocessor requires postprocess capability")
                            }
                        case ExtensionProcessingPhase.AstTransform =>
                            hasTransform = true
                            if (!manifest.capabilities.transform) {
                                fail("AST transform requires transform capability")
                            }
                    }
                }
            }
            for (provider in dialect.lintProviders) {
                if (provider.extensionId == manifest.extensionId) {
                    hasLint = true
                    if (!manifest.capabilities.lint) {
                        fail("extension lint provider requires lint capability")
                    }
                }
            }
            if (manifest.capabilities.postprocess && !hasPostprocessor) {
                fail("postprocess capability has no document postprocessor")
            }
            if (manifest.capabilities.transform && !hasTransform) {
                fail("transform capability has no AST transform")
            }
            if (manifest.capabilities.lint && !hasLint) {
                fail("lint capability has no extension lint provider")
            }
            if (manifest.capabilities.serialize || manifest.capabilities.incremental) {
                fail("serialize/incremental extension capabilities are not supported by parser plan v1")
            }
            let renderer = findRenderer(dialect.rendererRules, manifest.extensionId)
            let needsRenderer = manifest.capabilities.specHtml || manifest.capabilities.safeHtml || manifest
                .capabilities
                .plainText || manifest.capabilities.markdown || manifest.capabilities.format
            if (needsRenderer && renderer.isNone() && match (manifest.missingRendererPolicy) {
                case MissingRendererPolicy.Error => true;
                case _ => false
            }) {
                fail("declared renderer capability has no renderer rule")
            }
            if (manifest.capabilities.markdown || manifest.capabilities.format) {
                match (renderer) {
                    case Some(rule) =>
                        let complete = match (rule.markdownBlockLowering) {
                            case MarkdownBlockLowering.Container => !rule.markdownOpener.isEmpty() &&
                                !rule.markdownCloser.isEmpty()
                            case MarkdownBlockLowering.Line => !rule.markdownOpener.isEmpty()
                        }
                        if (!complete) {
                            fail("Markdown/format capability requires Markdown lowering")
                        }
                    case None => match (manifest.missingRendererPolicy) {
                        case MissingRendererPolicy.Error => fail("Markdown/format capability requires renderer")
                        case _ => ()
                    }
                }
            }
        }
    }

    private static func validateManifest(manifest: ExtensionManifest): Unit {
        validateIdentifier("extension id", manifest.extensionId)
        validateIdentifier("semantic version", manifest.semanticVersion)
        if (parseSemanticVersion(manifest.semanticVersion).isNone()) {
            fail("extension semantic version must be a valid SemVer version")
        }
        validateIdentifier("implementation version", manifest.implementationVersion)
        if (manifest.requiredSpiVersion != "1") {
            fail("unsupported extension SPI version")
        }
        if (manifest.ruleBudget <= 0) {
            fail("extension rule budget must be positive")
        }
    }

    private static func validateInline(rule: InlineSyntaxBuilder): Unit {
        validateIdentifier("rule id", rule.ruleId)
        if (rule.openerValue.isEmpty()) {
            fail("inline opener/token must not be empty")
        }
        match (rule.syntaxKindValue) {
            case InlineSyntaxKind.SingleToken =>
                if (!rule.closerValue.isEmpty()) {
                    fail("single-token syntax must not have a closer")
                }
            case _ =>
                if (rule.closerValue.isEmpty()) {
                    fail("paired inline syntax closer must not be empty")
                }
        }
        if (rule.openerValue.size > rule.maximumDelimiterLengthValue || rule.closerValue.size > rule
            .maximumDelimiterLengthValue) {
            fail("inline delimiter exceeds maximum")
        }
        if (rule.maximumLookaheadValue <= 0 || rule.maximumDelimiterLengthValue <= 0) {
            fail("unbounded inline rule")
        }
    }

    private static func validateBlock(rule: BlockSyntaxBuilder): Unit {
        validateIdentifier("rule id", rule.ruleId)
        if (rule.openerPrefixValue.isEmpty()) {
            fail("block opener must not be empty")
        }
        match (rule.syntaxKindValue) {
            case BlockSyntaxKind.PairedContainer =>
                if (rule.closerValue.isEmpty()) {
                    fail("paired block closer must not be empty")
                }
            case BlockSyntaxKind.SingleLine =>
                if (!rule.closerValue.isEmpty()) {
                    fail("single-line block must not have a closer")
                }
        }
        if (rule.maximumBlockBytesValue <= 0 || rule.maximumCaptureLengthValue <= 0) {
            fail("unbounded block rule")
        }
        let names = HashSet<String>()
        for (parameter in rule.parameterValues) {
            validateIdentifier("parameter name", parameter.name)
            if (!names.add(parameter.name)) {
                fail("duplicate block parameter")
            }
        }
    }

    private static func rejectRuleConflicts(inline: Array<InlineSyntaxRule>, block: Array<BlockSyntaxRule>): Unit {
        for (left in 0..inline.size) {
            for (right in left + 1..inline.size) {
                if (inline[left].opener == inline[right].opener) {
                    fail("inline delimiter conflict")
                }
            }
        }
        for (left in 0..block.size) {
            for (right in left + 1..block.size) {
                if (block[left].openerPrefix == block[right].openerPrefix) {
                    fail("block opener conflict")
                }
            }
        }
    }

    private static func validateRenderers(dialect: MarkdownDialect, manifestIds: HashSet<String>): Unit {
        for (renderer in dialect.rendererRules) {
            if (!manifestIds.contains(renderer.extensionId)) {
                fail("renderer extension is not enabled")
            }
            if (!validHtmlName(renderer.htmlTag)) {
                fail("invalid structured renderer tag")
            }
            if (!renderer.classToken.isEmpty() && !validClassToken(renderer.classToken)) {
                fail("invalid structured renderer class token")
            }
            match (renderer.markdownBlockLowering) {
                case MarkdownBlockLowering.Container =>
                    if (renderer.markdownOpener.isEmpty() != renderer.markdownCloser.isEmpty()) {
                        fail("container Markdown lowering requires both opener and closer")
                    }
                case MarkdownBlockLowering.Line =>
                    if (renderer.markdownOpener.isEmpty() || !renderer.markdownCloser.isEmpty()) {
                        fail("line Markdown lowering requires an opener and no closer")
                    }
            }
            let attributeNames = HashSet<String>()
            for (attribute in renderer.attributes.toArray()) {
                if (!validHtmlAttributeName(attribute.name) || !attributeNames.add(attribute.name)) {
                    fail("invalid or duplicate structured renderer attribute")
                }
                let lower = attribute.name.toLower()
                if (lower.startsWith("on") || lower == "style") {
                    fail("event and style attributes are not allowed in structured renderer rules")
                }
                match (attribute.kind) {
                    case RendererAttributeKind.Text =>
                        if (lower == "href" || lower == "src") {
                            fail("URI attributes require an explicit URI attribute kind")
                        }
                    case RendererAttributeKind.LinkUri =>
                        if (lower != "href") {
                            fail("LinkUri attributes must use href")
                        }
                    case RendererAttributeKind.ImageUri =>
                        if (lower != "src") {
                            fail("ImageUri attributes must use src")
                        }
                }
            }
        }
        for (manifest in dialect.manifests) {
            match (manifest.missingRendererPolicy) {
                case MissingRendererPolicy.Error =>
                    if ((manifest.capabilities.safeHtml || manifest.capabilities.specHtml) &&
                        !hasRenderer(dialect.rendererRules, manifest.extensionId)) {
                        fail("missing renderer coverage")
                    }
                case _ => ()
            }
        }
    }

    private static func sortInline(values: ArrayList<InlineSyntaxRule>): Unit {
        var index: Int64 = 1
        while (index < values.size) {
            var current = index
            while (current > 0 && ruleBefore(values[current], values[current - 1])) {
                let swap = values[current - 1];
                values[current - 1] = values[current]
                values[current] = swap
                current--
            }
            index++
        }
    }

    private static func sortBlock(values: ArrayList<BlockSyntaxRule>): Unit {
        var index: Int64 = 1
        while (index < values.size) {
            var current = index
            while (current > 0 && blockBefore(values[current], values[current - 1])) {
                let swap = values[current - 1];
                values[current - 1] = values[current]
                values[current] = swap
                current--
            }
            index++
        }
    }

    private static func sortParserSpis(values: ArrayList<InlineParserSpi>): Unit {
        var index: Int64 = 1
        while (index < values.size) {
            var current = index
            while (current > 0 && (values[current].priority > values[current - 1].priority || (values[current].priority ==
                    values[current - 1].priority && (values[current].extensionId < values[current - 1].extensionId || (values[current]
                    .extensionId == values[current - 1].extensionId && values[current].ruleId < values[current - 1]
                    .ruleId))))) {
                let swap = values[current - 1];
                values[current - 1] = values[current]
                values[current] = swap
                current--
            }
            index++
        }
    }

    private static func sortDocumentProcessors(values: ArrayList<ExtensionDocumentProcessor>): Unit {
        var index: Int64 = 1
        while (index < values.size) {
            var current = index
            while (current > 0 && documentProcessorBefore(values[current], values[current - 1])) {
                let swap = values[current - 1]
                values[current - 1] = values[current]
                values[current] = swap
                current--
            }
            index++
        }
    }

    private static func documentProcessorBefore(left: ExtensionDocumentProcessor, right: ExtensionDocumentProcessor): Bool {
        let leftPhase = match (left.phase) {
            case ExtensionProcessingPhase.DocumentPostprocess => 0
            case ExtensionProcessingPhase.AstTransform => 1
        }
        let rightPhase = match (right.phase) {
            case ExtensionProcessingPhase.DocumentPostprocess => 0
            case ExtensionProcessingPhase.AstTransform => 1
        }
        if (leftPhase != rightPhase) {
            return leftPhase < rightPhase
        }
        if (left.priority != right.priority) {
            return left.priority > right.priority
        }
        if (left.extensionId != right.extensionId) {
            return left.extensionId < right.extensionId
        }
        left.processorId < right.processorId
    }

    private static func ruleBefore(left: InlineSyntaxRule, right: InlineSyntaxRule): Bool {
        let leftPhase = syntaxPhaseRank(left.phase)
        let rightPhase = syntaxPhaseRank(right.phase)
        if (leftPhase != rightPhase) {
            return leftPhase < rightPhase
        }
        if (left.priority != right.priority) {
            return left.priority > right.priority
        }
        if (left.registrationOrder != right.registrationOrder) {
            return left.registrationOrder < right.registrationOrder
        }
        if (left.extensionId != right.extensionId) {
            return left.extensionId < right.extensionId
        }
        left.ruleId < right.ruleId
    }
    private static func blockBefore(left: BlockSyntaxRule, right: BlockSyntaxRule): Bool {
        left.priority > right.priority || (left.priority == right.priority && left.registrationOrder < right
            .registrationOrder)
    }

    private static func fail(message: String): Nothing {
        throw MarkdownException(MarkdownErrorCode.ExtensionConflict, message, phase: "dialect_compile")
    }
}

public class SyntaxPayload <: CustomPayload {
    public let name: String
    public let parameters: String
    public let literal: String
    private let typedValues: HashMap<String, SyntaxParameterValue>

    public init(name: String, parameters: String, literal: String,
        typedValues!: HashMap<String, SyntaxParameterValue> = HashMap<String, SyntaxParameterValue>()) {
        this.name = name
        this.parameters = parameters
        this.literal = literal
        this.typedValues = typedValues
    }
    public func payloadTypeId(): String {
        "markdown.syntax-payload.v1"
    }
    public func parameter(name: String): ?SyntaxParameterValue {
        typedValues.get(name)
    }
}

private func validateIdentifier(label: String, value: String): Unit {
    if (value.isEmpty()) {
        throw MarkdownException(MarkdownErrorCode.ExtensionConflict, "${label} must not be empty",
            phase: "dialect_compile")
    }
}

private func syntaxPhaseRank(phase: SyntaxPhase): Int64 {
    match (phase) {
        case SyntaxPhase.Inline => 0
        case SyntaxPhase.Metadata => 1
        case SyntaxPhase.Block => 2
    }
}

private func hasRenderer(rules: Array<RendererRule>, extensionId: String): Bool {
    for (rule in rules) {
        if (rule.extensionId == extensionId) {
            return true
        }
    }
    false
}

private func findRenderer(rules: Array<RendererRule>, extensionId: String): ?RendererRule {
    for (rule in rules) {
        if (rule.extensionId == extensionId) {
            return Some(rule)
        }
    }
    None
}

private func findManifest(manifests: Array<ExtensionManifest>, extensionId: String): ?ExtensionManifest {
    for (manifest in manifests) {
        if (manifest.extensionId == extensionId) {
            return Some(manifest)
        }
    }
    None
}

private func supportsProfile(manifest: ExtensionManifest, profileId: String): Bool {
    for (supported in manifest.supportedProfiles.toArray()) {
        if (supported == profileId) {
            return true
        }
    }
    false
}

private func semanticVersionAtLeast(actual: String, minimum: String): Bool {
    match ((parseSemanticVersion(actual), parseSemanticVersion(minimum))) {
        case (Some(left), Some(right)) => compareSemanticVersions(left, right) >= 0
        case _ => false
    }
}

private enum SemanticPrereleaseIdentifier {
    | Numeric(Int64)
    | Text(String)
}

private class ParsedSemanticVersion {
    let major: Int64
    let minor: Int64
    let patch: Int64
    let prerelease: Array<SemanticPrereleaseIdentifier>
    init(major: Int64, minor: Int64, patch: Int64, prerelease: Array<SemanticPrereleaseIdentifier>) {
        this.major = major
        this.minor = minor
        this.patch = patch
        this.prerelease = prerelease
    }
}

private func parseSemanticVersion(value: String): ?ParsedSemanticVersion {
    let majorResult = semanticCoreNumber(value, 0)
    let major = match (majorResult) {
        case Some(result) => result
        case None => return None
    }
    if (major[1] >= value.size || value[major[1]] != b'.') {
        return None
    }
    let minorResult = semanticCoreNumber(value, major[1] + 1)
    let minor = match (minorResult) {
        case Some(result) => result
        case None => return None
    }
    if (minor[1] >= value.size || value[minor[1]] != b'.') {
        return None
    }
    let patchResult = semanticCoreNumber(value, minor[1] + 1)
    let patch = match (patchResult) {
        case Some(result) => result
        case None => return None
    }
    var index = patch[1]
    let prerelease = ArrayList<SemanticPrereleaseIdentifier>()
    if (index < value.size && value[index] == b'-') {
        index++
        let parsed = semanticPrerelease(value, index)
        match (parsed) {
            case Some(result) =>
                for (identifier in result[0]) {
                    prerelease.add(identifier)
                }
                index = result[1]
            case None => return None
        }
    }
    if (index < value.size && value[index] == b'+') {
        index++
        match (semanticBuildMetadataEnd(value, index)) {
            case Some(end) => index = end
            case None => return None
        }
    }
    if (index != value.size) {
        return None
    }
    Some(ParsedSemanticVersion(major[0], minor[0], patch[0], prerelease.toArray()))
}

private func semanticCoreNumber(value: String, start: Int64): ?(Int64, Int64) {
    if (start >= value.size || value[start] < b'0' || value[start] > b'9') {
        return None
    }
    var index = start
    var number: Int64 = 0
    while (index < value.size && value[index] >= b'0' && value[index] <= b'9') {
        let digit = Int64(value[index] - b'0')
        if (number > (Int64.Max - digit) / 10) {
            return None
        }
        number = number * 10 + digit
        index++
    }
    if (index - start > 1 && value[start] == b'0') {
        return None
    }
    Some((number, index))
}

private func semanticPrerelease(value: String, start: Int64): ?(Array<SemanticPrereleaseIdentifier>, Int64) {
    let identifiers = ArrayList<SemanticPrereleaseIdentifier>()
    var identifierStart = start
    var index = start
    while (true) {
        if (index == value.size || value[index] == b'+' || value[index] == b'.') {
            if (identifierStart == index) {
                return None
            }
            let raw = value[identifierStart..index]
            var numeric = true
            for (byte in raw.toArray()) {
                if (!semanticIdentifierByte(byte)) {
                    return None
                }
                if (byte < b'0' || byte > b'9') {
                    numeric = false
                }
            }
            if (numeric) {
                if (raw.size > 1 && raw[0] == b'0') {
                    return None
                }
                match (semanticCoreNumber(raw, 0)) {
                    case Some(result) => identifiers.add(SemanticPrereleaseIdentifier.Numeric(result[0]))
                    case None => return None
                }
            } else {
                identifiers.add(SemanticPrereleaseIdentifier.Text(raw))
            }
            if (index == value.size || value[index] == b'+') {
                return Some((identifiers.toArray(), index))
            }
            identifierStart = index + 1
        }
        index++
    }
    None
}

private func semanticBuildMetadataEnd(value: String, start: Int64): ?Int64 {
    var identifierStart = start
    var index = start
    while (index <= value.size) {
        if (index == value.size || value[index] == b'.') {
            if (identifierStart == index) {
                return None
            }
            for (byte in value[identifierStart..index].toArray()) {
                if (!semanticIdentifierByte(byte)) {
                    return None
                }
            }
            if (index == value.size) {
                return Some(index)
            }
            identifierStart = index + 1
        }
        index++
    }
    None
}

private func semanticIdentifierByte(value: Byte): Bool {
    (value >= b'0' && value <= b'9') || (value >= b'A' && value <= b'Z') || (value >= b'a' && value <= b'z') || value ==
        b'-'
}

private func compareSemanticVersions(left: ParsedSemanticVersion, right: ParsedSemanticVersion): Int64 {
    for ((leftValue, rightValue) in [(left.major, right.major), (left.minor, right.minor), (left.patch, right.patch)]) {
        if (leftValue < rightValue) {
            return -1
        }
        if (leftValue > rightValue) {
            return 1
        }
    }
    if (left.prerelease.isEmpty() && right.prerelease.isEmpty()) {
        return 0
    }
    if (left.prerelease.isEmpty()) {
        return 1
    }
    if (right.prerelease.isEmpty()) {
        return -1
    }
    let shared = min(left.prerelease.size, right.prerelease.size)
    for (index in 0..shared) {
        let compared = compareSemanticIdentifier(left.prerelease[index], right.prerelease[index])
        if (compared != 0) {
            return compared
        }
    }
    if (left.prerelease.size < right.prerelease.size) {
        -1
    } else if (left.prerelease.size > right.prerelease.size) {
        1
    } else {
        0
    }
}

private func compareSemanticIdentifier(left: SemanticPrereleaseIdentifier, right: SemanticPrereleaseIdentifier): Int64 {
    match ((left, right)) {
        case (SemanticPrereleaseIdentifier.Numeric(leftValue), SemanticPrereleaseIdentifier.Numeric(rightValue)) =>
            if (leftValue < rightValue) {
                -1
            } else if (leftValue > rightValue) {
                1
            } else {
                0
            }
        case (SemanticPrereleaseIdentifier.Numeric(_), SemanticPrereleaseIdentifier.Text(_)) => -1
        case (SemanticPrereleaseIdentifier.Text(_), SemanticPrereleaseIdentifier.Numeric(_)) => 1
        case (SemanticPrereleaseIdentifier.Text(leftValue), SemanticPrereleaseIdentifier.Text(rightValue)) =>
            if (leftValue < rightValue) {
                -1
            } else if (leftValue > rightValue) {
                1
            } else {
                0
            }
    }
}

private func validHtmlName(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'0' && byte <= b'9') || byte == b'-')) {
            return false
        }
    }
    true
}

private func validClassToken(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'-' || byte == b'_')) {
            return false
        }
    }
    true
}

private func validHtmlAttributeName(value: String): Bool {
    if (value.isEmpty()) {
        return false
    }
    for (byte in value.toArray()) {
        if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b'-' || byte == b'_')) {
            return false
        }
    }
    true
}

private func canonicalDescriptor(
    dialect: MarkdownDialect,
    inline: Array<InlineSyntaxRule>,
    block: Array<BlockSyntaxRule>
): String {
    let out = CanonicalDescriptor()
    out.append("dialect=");
    out.append(dialect.id);
    out.append("@");
    out.append(dialect.version)
    out.append("|base=");
    out.append(dialect.baseProfile.id)
    out.append("|options=extensions:");
    out.append(dialect.parserOptions.extensionsEnabled)
    out.append(",unclosed-diagnostics:");
    out.append(dialect.parserOptions.emitUnclosedExtensionDiagnostics)
    let limits = dialect.limits
    out.append("|limits=");
    out.append(limits.maximumInputBytes);
    out.append(":");
    out.append(limits.maximumLineBytes);
    out.append(":")
    out.append(limits.maximumNestingDepth);
    out.append(":");
    out.append(limits.maximumAstNodes);
    out.append(":")
    out.append(limits.maximumReferences);
    out.append(":");
    out.append(limits.maximumTableColumns);
    out.append(":")
    out.append(limits.maximumUrlBytes);
    out.append(":");
    out.append(limits.maximumLiteralBytes);
    out.append(":")
    out.append(limits.maximumOutputBytes);
    out.append(":");
    out.append(limits.maximumExtensionCaptureBytes);
    out.append(":")
    out.append(limits.maximumExtensionLookaheadBytes)
    let manifests = dialect.manifests.clone()
    sortCanonicalManifests(manifests)
    for (manifest in manifests) {
        out.append("|ext=");
        out.append(manifest.extensionId);
        out.append("@");
        out.append(manifest.semanticVersion)
        out.append("#");
        out.append(manifest.implementationVersion)
        out.append(":spi=");
        out.append(manifest.requiredSpiVersion)
        out.append(":budget=");
        out.append(manifest.ruleBudget)
        out.append(":trust=");
        out.append(manifest.trustLevel)
        out.append(":shareable=");
        out.append(manifest.shareable)
        out.append(":cap=");
        out.append(manifest.capabilities.parse);
        out.append(":")
        out.append(manifest.capabilities.specHtml);
        out.append(":");
        out.append(manifest.capabilities.safeHtml)
        out.append(":");
        out.append(manifest.capabilities.plainText);
        out.append(":")
        out.append(manifest.capabilities.markdown);
        out.append(":");
        out.append(manifest.capabilities.cst)
        out.append(":");
        out.append(manifest.capabilities.format);
        out.append(":")
        out.append(manifest.capabilities.serialize);
        out.append(":");
        out.append(manifest.capabilities.incremental)
        out.append(":");
        out.append(manifest.capabilities.lint)
        out.append(":");
        out.append(manifest.capabilities.postprocess)
        out.append(":");
        out.append(manifest.capabilities.transform)
        let dependencies = manifest.dependencies.toArray()
        sortCanonicalStrings(dependencies)
        for (dependency in dependencies) {
            out.append(":dep=");
            out.append(dependency)
        }
        let constraints = manifest.dependencyConstraints.toArray()
        sortCanonicalDependencies(constraints)
        for (constraint in constraints) {
            out.append(":dep-version=");
            out.append(constraint.extensionId);
            out.append(">=")
            out.append(constraint.minimumSemanticVersion)
        }
        let conflicts = manifest.conflicts.toArray()
        sortCanonicalStrings(conflicts)
        for (conflict in conflicts) {
            out.append(":conflict=")
            out.append(conflict)
        }
    }
    for (rule in inline) {
        out.append("|inline=");
        out.append(rule.extensionId);
        out.append("/");
        out.append(rule.ruleId)
        out.append(":");
        out.append(rule.opener);
        out.append(":");
        out.append(rule.closer);
        out.append(":")
        out.append(rule.priority)
        out.append(":kind=")
        match (rule.syntaxKind) {
            case InlineSyntaxKind.PairedDelimiter => out.append("paired")
            case InlineSyntaxKind.SingleToken => out.append("token")
            case InlineSyntaxKind.MetadataSuffix => out.append("metadata")
        }
        out.append(":children=");
        out.append(rule.parseChildren)
        out.append(":emit-content=");
        out.append(rule.emitContent)
        out.append(":nesting=");
        out.append(rule.allowNesting)
        out.append(":delimiter=");
        out.append(rule.maximumDelimiterLength)
        out.append(":lookahead=");
        out.append(rule.maximumLookahead)
        out.append(":conflict=");
        out.append(rule.conflictGroup)
        out.append(":escape=")
        match (rule.escapePolicy) {
            case InlineEscapePolicy.CommonMarkBackslash => out.append("commonmark")
            case InlineEscapePolicy.LiteralBackslash => out.append("literal")
        }
        out.append(":flanking=")
        match (rule.flankingRule) {
            case InlineFlankingRule.Any => out.append("any")
            case InlineFlankingRule.CommonMark => out.append("commonmark")
            case InlineFlankingRule.WordBoundary => out.append("word")
        }
        out.append(":cost=");
        out.append(rule.resourceCost.baseCost);
        out.append(":")
        out.append(rule.resourceCost.perByteCost)
    }
    for (rule in block) {
        out.append("|block=");
        out.append(rule.extensionId);
        out.append("/");
        out.append(rule.ruleId)
        out.append(":");
        out.append(rule.openerPrefix);
        out.append(":");
        out.append(rule.closer);
        out.append(":")
        out.append(rule.priority)
        out.append(":kind=")
        match (rule.syntaxKind) {
            case BlockSyntaxKind.PairedContainer => out.append("paired")
            case BlockSyntaxKind.SingleLine => out.append("line")
        }
        out.append(":dynamic-kind=");
        out.append(rule.kindFromFirstWord)
        out.append(":document-start=");
        out.append(rule.documentStartOnly)
        out.append(":content=")
        match (rule.contentMode) {
            case BlockContentMode.Markdown => out.append("markdown")
            case BlockContentMode.Literal => out.append("literal")
        }
        out.append(":nesting=");
        out.append(rule.allowNesting)
        out.append(":block-bytes=");
        out.append(rule.maximumBlockBytes)
        out.append(":capture=");
        out.append(rule.maximumCaptureLength)
        out.append(":conflict=");
        out.append(rule.conflictGroup)
        out.append(":cost=");
        out.append(rule.resourceCost.baseCost);
        out.append(":")
        out.append(rule.resourceCost.perByteCost)
        for (parameter in rule.parameters.toArray()) {
            out.append(":param=");
            out.append(parameter.name);
            out.append(":")
            match (parameter.parameterType) {
                case SyntaxParameterType.StringValue => out.append("string")
                case SyntaxParameterType.IntegerValue => out.append("integer")
                case SyntaxParameterType.BooleanValue => out.append("boolean")
                case SyntaxParameterType.IdentifierValue => out.append("identifier")
            }
            out.append(if (parameter.required) {
                ":required"
            } else {
                ":optional"
            })
        }
    }
    for (spi in dialect.parserSpis) {
        out.append("|parser-spi=");
        out.append(spi.extensionId);
        out.append("/");
        out.append(spi.ruleId)
        out.append(":");
        out.append(spi.maximumLookahead);
        out.append(":");
        out.append(spi.priority)
    }
    for (processor in dialect.documentProcessors) {
        out.append("|processor=");
        out.append(processor.extensionId);
        out.append("/")
        out.append(processor.processorId);
        out.append("@");
        out.append(processor.version);
        out.append(":")
        match (processor.phase) {
            case ExtensionProcessingPhase.DocumentPostprocess => out.append("postprocess")
            case ExtensionProcessingPhase.AstTransform => out.append("transform")
        }
        out.append(":");
        out.append(processor.priority)
    }
    for (provider in dialect.lintProviders) {
        out.append("|lint=");
        out.append(provider.extensionId);
        out.append("/")
        out.append(provider.ruleId);
        out.append("@");
        out.append(provider.version)
    }
    out.append("|spi=1|plan=1")
    out.toString()
}

private func sortCanonicalManifests(values: Array<ExtensionManifest>): Unit {
    for (index in 1..values.size) {
        let value = values[index]
        var cursor = index
        while (cursor > 0 && canonicalManifestKey(value) < canonicalManifestKey(values[cursor - 1])) {
            values[cursor] = values[cursor - 1]
            cursor--
        }
        values[cursor] = value
    }
}

private func canonicalManifestKey(value: ExtensionManifest): String {
    let out = CanonicalDescriptor()
    out.append(value.extensionId)
    out.append(value.semanticVersion)
    out.append(value.implementationVersion)
    out.toString()
}

private func sortCanonicalStrings(values: Array<String>): Unit {
    for (index in 1..values.size) {
        let value = values[index]
        var cursor = index
        while (cursor > 0 && value < values[cursor - 1]) {
            values[cursor] = values[cursor - 1]
            cursor--
        }
        values[cursor] = value
    }
}

private func sortCanonicalDependencies(values: Array<ExtensionDependency>): Unit {
    for (index in 1..values.size) {
        let value = values[index]
        var cursor = index
        while (cursor > 0 && canonicalDependencyKey(value) < canonicalDependencyKey(values[cursor - 1])) {
            values[cursor] = values[cursor - 1]
            cursor--
        }
        values[cursor] = value
    }
}

private func canonicalDependencyKey(value: ExtensionDependency): String {
    let out = CanonicalDescriptor()
    out.append(value.extensionId)
    out.append(value.minimumSemanticVersion)
    out.toString()
}

private func stableDescriptorDigest(value: String): String {
    Sha256.digest(value)
}
