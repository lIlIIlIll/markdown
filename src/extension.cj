package markdown

import std.collection.*
import std.unicode.*

/** custom node 缺少 renderer rule 时的处理策略。 */
public enum MissingRendererPolicy {
    /** 抛出异常。 */
    | Error
    /** 渲染 child 节点。 */
    | RenderChildren
    /** 渲染 raw literal。 */
    | RenderLiteral
    /** 丢弃节点。 */
    | Drop
    /** 交给宿主 fallback 处理。 */
    | CustomFallback
}

/**
 * 扩展声明的解析、输出、编辑和 transform 能力集合。
 *
 * 默认只声明 `parse`；声明其他能力后，dialect compiler 会要求对应实现或明确
 * 的 fallback 策略。
 */
public class ExtensionCapabilities {
    /** 是否参与解析。 */
    public let parse: Bool
    /** 是否声明 spec HTML 输出。 */
    public let specHtml: Bool
    /** 是否声明安全 HTML 输出。 */
    public let safeHtml: Bool
    /** 是否声明纯文本输出。 */
    public let plainText: Bool
    /** 是否声明 canonical Markdown 输出。 */
    public let markdown: Bool
    /** 是否声明 lossless CST。 */
    public let cst: Bool
    /** 是否声明 canonical Markdown 格式化。 */
    public let format: Bool
    /** 是否声明 artifact 序列化。 */
    public let serialize: Bool
    /** 是否声明增量编辑。 */
    public let incremental: Bool
    /** 是否声明 snapshot lint。 */
    public let lint: Bool
    /** 是否声明 document 分析。 */
    public let analysis: Bool
    /** 是否声明 AST transform。 */
    public let transform: Bool

    /**
     * 创建能力声明。
     * @param parse 是否参与解析。
     * @param specHtml 是否声明 spec HTML 输出。
     * @param safeHtml 是否声明安全 HTML 输出。
     * @param plainText 是否声明纯文本输出。
     * @param markdown 是否声明 canonical Markdown 输出。
     * @param cst 是否声明 lossless CST。
     * @param format 是否声明 canonical Markdown 格式化。
     * @param serialize 是否声明 artifact 序列化。
     * @param incremental 是否声明增量编辑。
     * @param lint 是否声明 snapshot lint。
     * @param analysis 是否声明 document 分析。
     * @param transform 是否声明 AST transform。
     */
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
        analysis!: Bool = false,
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
        this.analysis = analysis
        this.transform = transform
    }
}

/** 扩展依赖及其最低 semantic version。 */
public class ExtensionDependency {
    /** 依赖的扩展 id。 */
    public let extensionId: String
    /** 可接受的最低 semantic version。 */
    public let minimumSemanticVersion: String
    /** 创建依赖声明。
     * @param extensionId 依赖的扩展 id。
     * @param minimumSemanticVersion 可接受的最低 semantic version。
     */
    public init(extensionId: String, minimumSemanticVersion: String) {
        this.extensionId = extensionId
        this.minimumSemanticVersion = minimumSemanticVersion
    }
}

/**
 * 扩展的稳定身份、依赖、能力和 renderer fallback 配置。
 *
 * `requiredSpiVersion` 默认是 `"3"`，`ruleBudget` 默认是 `100000`，
 * `trustLevel` 默认是 `"host-code"`，缺失 renderer 默认失败，扩展默认可共享。
 *
 * ```cj
 * let manifest = ExtensionManifest(
 *     "docs", "1.0.0", "build-1",
 *     capabilities: ExtensionCapabilities(safeHtml: true, markdown: true)
 * )
 * ```
 */
public class ExtensionManifest {
    /** 扩展的稳定唯一 id。 */
    public let extensionId: String
    /** 扩展的语义版本。 */
    public let semanticVersion: String
    /** 扩展的实现版本。 */
    public let implementationVersion: String
    /** 要求的 parser SPI 版本。 */
    public let requiredSpiVersion: String
    /** 支持的 profile id 列表。 */
    public let supportedProfiles: ImmutableArray<String>
    /** 依赖的扩展 id 列表。 */
    public let dependencies: ImmutableArray<String>
    /** 带版本约束的依赖列表。 */
    public let dependencyConstraints: ImmutableArray<ExtensionDependency>
    /** 冲突的扩展 id 列表。 */
    public let conflicts: ImmutableArray<String>
    /** 声明的能力集合。 */
    public let capabilities: ExtensionCapabilities
    /** 扩展可声明的 rule 数量上限。 */
    public let ruleBudget: Int64
    /** 信任级别标识。 */
    public let trustLevel: String
    /** 缺少 renderer rule 时的处理策略。 */
    public let missingRendererPolicy: MissingRendererPolicy
    /** 是否允许在进程间共享。 */
    public let shareable: Bool

    /**
     * 创建 manifest。
     * @param extensionId 扩展的稳定唯一 id。
     * @param semanticVersion 扩展的语义版本。
     * @param implementationVersion 扩展的实现版本。
     * @param requiredSpiVersion 要求的 parser SPI 版本。
     * @param supportedProfiles 支持的 profile id 列表。
     * @param dependencies 依赖的扩展 id 列表。
     * @param dependencyConstraints 带版本约束的依赖列表。
     * @param conflicts 冲突的扩展 id 列表。
     * @param capabilities 声明的能力集合。
     * @param ruleBudget 扩展可声明的 rule 数量上限。
     * @param trustLevel 信任级别标识。
     * @param missingRendererPolicy 缺少 renderer rule 时的处理策略。
     * @param shareable 是否允许在进程间共享。
     */
    public init(
        extensionId: String,
        semanticVersion: String,
        implementationVersion: String,
        requiredSpiVersion!: String = "3",
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

/** Inline parser SPI callback 的受限输入、预算和取消上下文。 */
public class InlineParserSpiContext {
    /** SPI callback 可见的受限输入文本。 */
    public let input: String
    /** 本段输入在 callback 输入中的起始偏移。 */
    public let startOffset: Int64
    /** 允许的向前查看上限。 */
    public let maximumLookahead: Int64
    private let baseByteOffset: Int64
    private let source: SourceBuffer
    /** 本次解析的操作预算。 */
    public let budget: OperationBudget
    /** 协作式取消信号。 */
    public let cancellation: CancellationToken

    internal init(input: String, startOffset: Int64, maximumLookahead: Int64, baseByteOffset: Int64,
        source: SourceBuffer, budget: OperationBudget, cancellation: CancellationToken) {
        this.input = input
        this.startOffset = startOffset
        this.maximumLookahead = maximumLookahead
        this.baseByteOffset = baseByteOffset
        this.source = source
        this.budget = budget
        this.cancellation = cancellation
    }

    /** 将 callback 输入中的 local byte range 转为原始 source span。
     * @param localStart local 起始偏移（含）。
     * @param localEnd local 结束偏移（不含）。
     * @return 对应的原始 source span。
     * @throws IllegalArgumentException local range 越界时。
     */
    public func sourceSpan(localStart: Int64, localEnd: Int64): SourceSpan {
        if (localStart < 0 || localEnd < localStart || localEnd > input.size) {
            throw IllegalArgumentException("SPI span is outside inline input")
        }
        SourceSpan(source.originalOffset(baseByteOffset + localStart), source.originalOffset(baseByteOffset + localEnd))
    }
}

/** SPI 生成的 inline child 文本及其 raw/semantic 表示。 */
public class InlineParserSpiText {
    /** 匹配到的原始文本。 */
    public let raw: String
    /** 语义文本。 */
    public let value: String
    /** 文本覆盖的 source span。 */
    public let span: SourceSpan
    /** 创建 SPI 文本。
     * @param raw 匹配到的原始文本。
     * @param value 语义文本。
     * @param span 文本覆盖的 source span。
     */
    public init(raw: String, value: String, span: SourceSpan) {
        this.raw = raw
        this.value = value
        this.span = span
    }
}

/** SPI 成功匹配后返回的 custom inline node 描述。 */
public class InlineParserSpiNode {
    /** 定义该节点的扩展 id。 */
    public let extensionId: String
    /** 扩展的语义版本。 */
    public let extensionSemanticVersion: String
    /** 扩展内的 local kind id。 */
    public let localKindId: String
    /** 扩展提供的 typed payload。 */
    public let payload: CustomPayload
    /** 匹配覆盖的 source span。 */
    public let span: SourceSpan
    /** 匹配产生的 inline child 文本列表。 */
    public let children: ImmutableArray<InlineParserSpiText>
    /** 创建 SPI custom inline 节点。
     * @param extensionId 定义该节点的扩展 id。
     * @param extensionSemanticVersion 扩展的语义版本。
     * @param localKindId 扩展内的 local kind id。
     * @param payload 扩展提供的 typed payload。
     * @param span 匹配覆盖的 source span。
     * @param children 匹配产生的 inline child 文本列表。
     */
    public init(extensionId: String, extensionSemanticVersion: String, localKindId: String, payload: CustomPayload,
        span: SourceSpan, children!: Array<InlineParserSpiText> = []) {
        this.extensionId = extensionId
        this.extensionSemanticVersion = extensionSemanticVersion
        this.localKindId = localKindId
        this.payload = payload
        this.span = span
        this.children = ImmutableArray<InlineParserSpiText>(children)
    }
}

/** SPI callback 的匹配结果和 consumed byte 数。 */
public enum InlineParserSpiResult {
    /** 本次位置无匹配。 */
    | NoMatch
    /** 匹配成功，携带节点描述和 consumed byte 数。 */
    | Matched(InlineParserSpiNode, Int64)
}

/**
 * 用于表达有限、无法由 DSL 描述的 inline syntax 的 SPI v1。
 *
 * `triggerBytes` 必须非空且无重复；runtime 会校验 consumed range、NodeId 和 span。
 */
public interface InlineParserSpi {
    /** SPI 所属的扩展 id。 */
    prop extensionId: String
    /** SPI 的 rule id。 */
    prop ruleId: String
    /** 触发匹配的字节集合；非空且无重复。 */
    prop triggerBytes: Array<Byte>
    /** 允许的向前查看上限。 */
    prop maximumLookahead: Int64
    /** SPI 的优先级。 */
    prop priority: Int64
    /** 相同输入是否产生相同输出。 */
    prop deterministic: Bool
    /** 在指定上下文中尝试匹配 inline 语法。
     * @param context 受限的解析上下文。
     * @return 匹配结果；无匹配时为 `NoMatch`。
     */
    func tryParse(context: InlineParserSpiContext): InlineParserSpiResult
}

internal class ParserHotPlan {
    internal let hasInlineDsl: Bool
    internal let hasBlockDsl: Bool
    internal let hasInlineSpi: Bool
    internal let hasDocumentStages: Bool
    internal let hasFootnotes: Bool
    internal let hasMath: Bool
    internal let definitionListRule: ?BlockSyntaxRule
    internal let headingIdRule: ?InlineSyntaxRule
    private let inlineDslByFirstByte: Array<ImmutableArray<InlineSyntaxRule>>
    private let blockDslByFirstByte: Array<ImmutableArray<BlockSyntaxRule>>
    private let inlineSpiByFirstByte: Array<ImmutableArray<InlineParserSpi>>

    internal init(inlineRules: Array<InlineSyntaxRule>, blockRules: Array<BlockSyntaxRule>,
        parserSpis: Array<InlineParserSpi>, astTransforms: Array<ExtensionAstTransform>,
        analyses: Array<ExtensionDocumentAnalysis>) {
        hasInlineDsl = !inlineRules.isEmpty()
        hasBlockDsl = !blockRules.isEmpty()
        hasInlineSpi = !parserSpis.isEmpty()
        hasDocumentStages = !astTransforms.isEmpty() || !analyses.isEmpty()
        let inlineBuckets = Array<ArrayList<InlineSyntaxRule>>(256) {_ => ArrayList<InlineSyntaxRule>()}
        let blockBuckets = Array<ArrayList<BlockSyntaxRule>>(256) {_ => ArrayList<BlockSyntaxRule>()}
        let spiBuckets = Array<ArrayList<InlineParserSpi>>(256) {_ => ArrayList<InlineParserSpi>()}
        var footnotes = false
        var math = false
        var headingRule: ?InlineSyntaxRule = None
        var definitionRule: ?BlockSyntaxRule = None
        for (rule in inlineRules) {
            inlineBuckets[Int64(rule.opener[0])].add(rule)
            if (let InlineSyntaxKind.HeadingIdSuffix <- rule.syntaxKind) {
                headingRule = Some(rule)
            }
            if (let Some(emitter) <- rule.emitter) {
                if (emitter is FootnoteReferenceEmitter) {
                    footnotes = true
                }
                if (emitter is MathInlineEmitter) {
                    math = true
                }
            }
        }
        for (rule in blockRules) {
            blockBuckets[Int64(rule.openerPrefix[0])].add(rule)
            if (let BlockSyntaxKind.DisplayMath <- rule.syntaxKind) {
                math = true
            }
            if (let BlockSyntaxKind.FootnoteDefinition <- rule.syntaxKind) {
                footnotes = true
            }
            if (definitionRule.isNone() && let BlockSyntaxKind.DefinitionList <- rule.syntaxKind) {
                definitionRule = Some(rule)
            }
        }
        hasFootnotes = footnotes
        hasMath = math
        definitionListRule = definitionRule
        headingIdRule = headingRule
        for (spi in parserSpis) {
            for (trigger in spi.triggerBytes) {
                spiBuckets[Int64(trigger)].add(spi)
            }
        }
        inlineDslByFirstByte = Array<ImmutableArray<InlineSyntaxRule>>(256) {
            index => ImmutableArray<InlineSyntaxRule>(inlineBuckets[index].toArray())
        }
        blockDslByFirstByte = Array<ImmutableArray<BlockSyntaxRule>>(256) {
            index => ImmutableArray<BlockSyntaxRule>(blockBuckets[index].toArray())
        }
        inlineSpiByFirstByte = Array<ImmutableArray<InlineParserSpi>>(256) {
            index => ImmutableArray<InlineParserSpi>(spiBuckets[index].toArray())
        }
    }

    internal func inlineRules(firstByte: Byte): ImmutableArray<InlineSyntaxRule> {
        inlineDslByFirstByte[Int64(firstByte)]
    }

    internal func blockRules(firstByte: Byte): ImmutableArray<BlockSyntaxRule> {
        blockDslByFirstByte[Int64(firstByte)]
    }

    internal func parserSpis(firstByte: Byte): ImmutableArray<InlineParserSpi> {
        inlineSpiByFirstByte[Int64(firstByte)]
    }
}

internal class RendererHotPlan {
    internal let hasCustomRules: Bool

    internal init(rendererRules: Array<RendererRule>) {
        hasCustomRules = !rendererRules.isEmpty()
    }
}

/** 为 `DocumentSnapshot` 提供扩展诊断的接口。 */
public interface ExtensionLintProvider {
    /** provider 所属的扩展 id。 */
    prop extensionId: String
    /** provider 的 rule id。 */
    prop ruleId: String
    /** provider 的版本。 */
    prop version: String
    /** 为 snapshot 产生扩展 lint 诊断。
     * @param snapshot 目标文档 snapshot。
     * @return 扩展产生的 lint 诊断数组。
     */
    func lint(snapshot: DocumentSnapshot): Array<LintDiagnostic>
}

/** inline rule 的语法形态。 */
public enum InlineSyntaxKind {
    /** 成对 delimiter 语法。 */
    | PairedDelimiter
    /** 单 token 语法。 */
    | SingleToken
    /** metadata suffix 语法。 */
    | MetadataSuffix
    /** 只允许出现在标题尾部的显式 ID。 */
    | HeadingIdSuffix
}

/** inline delimiter 中反斜杠的处理策略。 */
public enum InlineEscapePolicy {
    /** CommonMark 反斜杠转义语义。 */
    | CommonMarkBackslash
    /** 反斜杠按字面处理。 */
    | LiteralBackslash
}

/** inline delimiter 的 flanking 匹配规则。 */
public enum InlineFlankingRule {
    /** 任意位置均可匹配。 */
    | Any
    /** CommonMark flanking 规则。 */
    | CommonMark
    /** 要求词边界的 flanking 规则。 */
    | WordBoundary
}

/** syntax rule 参与解析的阶段。 */
public enum SyntaxPhase {
    /** inline 解析阶段。 */
    | Inline
    /** block 解析阶段。 */
    | Block
    /** metadata 解析阶段。 */
    | Metadata
}

/** syntax rule 的回溯策略；当前只支持 `None`。 */
public enum SyntaxBacktrackingPolicy {
    /** 不回溯。 */
    | None
}

/** static syntax resource cost，用于扩展预算估算。 */
public class SyntaxResourceCost {
    /** 每次匹配的固定成本。 */
    public let baseCost: Int64
    /** 每字节的附加成本。 */
    public let perByteCost: Int64
    /** 创建 resource cost；参数为负时抛出 `IllegalArgumentException`。
     * @param baseCost 每次匹配的固定成本。
     * @param perByteCost 每字节的附加成本。
     */
    public init(baseCost!: Int64 = 1, perByteCost!: Int64 = 1) {
        if (baseCost < 0 || perByteCost < 0) {
            throw IllegalArgumentException("syntax resource costs must be non-negative")
        }
        this.baseCost = baseCost
        this.perByteCost = perByteCost
    }
}

/** inline DSL rule 匹配后的 raw literal、span 和 child summary。 */
public class InlineSyntaxMatch {
    /** 匹配所属的扩展 id。 */
    public let extensionId: String
    /** 匹配的 rule id。 */
    public let ruleId: String
    /** 容器归一化后的匹配体。 */
    public let literal: String
    /** 未经容器内转义归一化的原始匹配体，遵循输入 UTF-8 策略。 */
    public let rawLiteral: String
    /** 匹配体本身的精确来源范围，不包含 delimiter。 */
    public let literalSpan: SourceSpan
    /** 匹配覆盖的 source span。 */
    public let span: SourceSpan
    /** 匹配子节点的语义摘要。 */
    public let children: ImmutableArray<SyntaxChildSummary>
    /** 创建 inline 匹配记录。
     * @param extensionId 匹配所属的扩展 id。
     * @param ruleId 匹配的 rule id。
     * @param literal 容器归一化后的匹配体。
     * @param rawLiteral 原始匹配体，遵循输入 UTF-8 策略。
     * @param literalSpan 匹配体的来源范围。
     * @param span 匹配覆盖的 source span。
     * @param children 匹配子节点的语义摘要。
     */
    public init(extensionId: String, ruleId: String, literal: String, rawLiteral: String, literalSpan: SourceSpan,
        span: SourceSpan, children: Array<SyntaxChildSummary>) {
        this.extensionId = extensionId
        this.ruleId = ruleId
        this.literal = literal
        this.rawLiteral = rawLiteral
        this.literalSpan = literalSpan
        this.span = span
        this.children = ImmutableArray<SyntaxChildSummary>(children)
    }
}

/** DSL 匹配子节点的轻量语义摘要。 */
public class SyntaxChildSummary {
    /** 子节点的 AST 类别。 */
    public let kind: NodeKind
    /** 子节点的 source span。 */
    public let span: ?SourceSpan
    /** 子节点的语义文本。 */
    public let semanticText: String
    /** 创建子节点摘要。
     * @param kind 子节点的 AST 类别。
     * @param span 子节点的 source span。
     * @param semanticText 子节点的语义文本。
     */
    public init(kind: NodeKind, span: ?SourceSpan, semanticText: String) {
        this.kind = kind
        this.span = span
        this.semanticText = semanticText
    }
}

/** 将 inline 匹配转换为 typed custom payload 的 callback。 */
public interface InlinePayloadEmitter {
    /** 将 inline 匹配转换为 typed payload。
     * @param value inline 匹配记录。
     * @return 转换得到的 typed payload。
     */
    func emit(value: InlineSyntaxMatch): CustomPayload
}

/** 编译后的 inline syntax rule；由 `InlineSyntaxBuilder` 生成。 */
public class InlineSyntaxRule {
    /** rule 所属的扩展 id。 */
    public let extensionId: String
    /** rule 的稳定 id。 */
    public let ruleId: String
    /** opener delimiter 文本。 */
    public let opener: String
    /** closer delimiter 文本。 */
    public let closer: String
    /** 是否解析匹配内容中的 Markdown children。 */
    public let parseChildren: Bool
    /** 是否保留匹配内容的可见文本。 */
    public let emitContent: Bool
    /** 是否允许同 rule 嵌套。 */
    public let allowNesting: Bool
    /** 匹配内容是否允许跨行。 */
    public let allowLineBreaks: Bool
    /** delimiter 长度上限。 */
    public let maximumDelimiterLength: Int64
    /** rule lookahead byte 上限。 */
    public let maximumLookahead: Int64
    /** rule 的解析优先级。 */
    public let priority: Int64
    /** 与其他 rule 冲突时使用的分组。 */
    public let conflictGroup: String
    /** 语法形态。 */
    public let syntaxKind: InlineSyntaxKind
    /** 反斜杠 escaping policy。 */
    public let escapePolicy: InlineEscapePolicy
    /** delimiter flanking 规则。 */
    public let flankingRule: InlineFlankingRule
    /** rule 参与的解析阶段。 */
    public let phase: SyntaxPhase
    /** 平局裁决规则说明。 */
    public let tieBreak: String
    /** 回溯策略。 */
    public let backtrackingPolicy: SyntaxBacktrackingPolicy
    /** 静态 resource cost。 */
    public let resourceCost: SyntaxResourceCost
    /** typed payload emitter。 */
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
        allowLineBreaks = builder.allowLineBreaksValue
        maximumDelimiterLength = builder.maximumDelimiterLengthValue
        maximumLookahead = builder.maximumLookaheadValue
        priority = builder.priorityValue
        conflictGroup = builder.conflictGroupValue
        syntaxKind = builder.syntaxKindValue
        escapePolicy = builder.escapePolicyValue
        flankingRule = builder.flankingRuleValue
        phase = match (syntaxKind) {
            case InlineSyntaxKind.MetadataSuffix => SyntaxPhase.Metadata
            case InlineSyntaxKind.HeadingIdSuffix => SyntaxPhase.Metadata
            case _ => SyntaxPhase.Inline
        }
        tieBreak = "registration-order>extension-id>rule-id"
        backtrackingPolicy = SyntaxBacktrackingPolicy.None
        resourceCost = builder.resourceCostValue
        emitter = builder.emitterValue
        this.registrationOrder = registrationOrder
    }
}

/**
 * 构造 inline syntax rule 的 fluent builder。
 *
 * 默认 delimiter 上限为 16、lookahead 为 4096、priority 为 100，并允许解析 children
 * 和同规则嵌套。
 *
 * ```cj
 * let mark = InlineSyntax.define("docs", "mark")
 *     .delimiter("==")
 *     .content(true)
 *     .nesting(false)
 * ```
 */
public class InlineSyntaxBuilder {
    /** builder 所属的扩展 id。 */
    public let extensionId: String
    /** builder 的 rule id。 */
    public let ruleId: String
    internal var openerValue = ""
    internal var closerValue = ""
    internal var parseChildrenValue = true
    internal var emitContentValue = true
    internal var allowNestingValue = true
    internal var allowLineBreaksValue = true
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

    /** 定义成对 delimiter；省略 closer 时使用 opener。
     * @param opener opener delimiter 文本。
     * @param closer closer delimiter 文本；省略时使用 opener。
     * @return 同一 builder，支持链式调用。
     */
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
    /** 定义单 token rule，并关闭 children、content 和嵌套。
     * @param value token 文本。
     * @return 同一 builder，支持链式调用。
     */
    public func token(value: String): InlineSyntaxBuilder {
        syntaxKindValue = InlineSyntaxKind.SingleToken
        openerValue = value
        closerValue = ""
        parseChildrenValue = false
        emitContentValue = false
        allowNestingValue = false
        this
    }
    /** 定义不解析 children 的 metadata suffix rule。
     * @param opener suffix opener 文本。
     * @param closer suffix closer 文本。
     * @return 同一 builder，支持链式调用。
     */
    public func metadataSuffix(opener: String, closer: String): InlineSyntaxBuilder {
        syntaxKindValue = InlineSyntaxKind.MetadataSuffix
        openerValue = opener
        closerValue = closer
        parseChildrenValue = false
        emitContentValue = false
        allowNestingValue = false
        this
    }
    /** 定义只在标题尾部匹配的 `{#id}` 元数据。
     * @return 同一 builder，支持链式调用。
     */
    public func headingIdSuffix(): InlineSyntaxBuilder {
        syntaxKindValue = InlineSyntaxKind.HeadingIdSuffix
        openerValue = "{#"
        closerValue = "}"
        parseChildrenValue = false
        emitContentValue = false
        allowNestingValue = false
        allowLineBreaksValue = false
        this
    }
    /** 设置反斜杠 escaping policy。
     * @param policy 要使用的 escaping policy。
     * @return 同一 builder，支持链式调用。
     */
    public func escaping(policy: InlineEscapePolicy): InlineSyntaxBuilder {
        escapePolicyValue = policy
        this
    }
    /** 设置 delimiter flanking rule。
     * @param rule 要使用的 flanking 规则。
     * @return 同一 builder，支持链式调用。
     */
    public func flanking(rule: InlineFlankingRule): InlineSyntaxBuilder {
        flankingRuleValue = rule
        this
    }
    /** 设置是否解析匹配内容中的 Markdown children。
     * @param parseChildren 是否解析 children。
     * @return 同一 builder，支持链式调用。
     */
    public func content(parseChildren: Bool): InlineSyntaxBuilder {
        parseChildrenValue = parseChildren
        this
    }
    /** 设置是否保留匹配内容的可见文本。
     * @param enabled 是否保留可见文本。
     * @return 同一 builder，支持链式调用。
     */
    public func emitContent(enabled: Bool): InlineSyntaxBuilder {
        emitContentValue = enabled
        this
    }
    /** 设置是否允许同 rule 嵌套。
     * @param allow 是否允许嵌套。
     * @return 同一 builder，支持链式调用。
     */
    public func nesting(allow: Bool): InlineSyntaxBuilder {
        allowNestingValue = allow
        this
    }
    /** 设置匹配内容是否允许跨行。
     * @param allow 是否允许换行。
     * @return 同一 builder，支持链式调用。
     */
    public func lineBreaks(allow: Bool): InlineSyntaxBuilder {
        allowLineBreaksValue = allow
        this
    }
    /** 设置 delimiter 长度上限。
     * @param value 长度上限。
     * @return 同一 builder，支持链式调用。
     */
    public func maximumDelimiterLength(value: Int64): InlineSyntaxBuilder {
        maximumDelimiterLengthValue = value
        this
    }
    /** 设置 rule lookahead byte 上限。
     * @param value lookahead 上限（字节）。
     * @return 同一 builder，支持链式调用。
     */
    public func maximumLookahead(value: Int64): InlineSyntaxBuilder {
        maximumLookaheadValue = value
        this
    }
    /** 设置 rule priority；相同 priority 按 registration order 决定顺序。
     * @param value 优先级数值。
     * @return 同一 builder，支持链式调用。
     */
    public func priority(value: Int64): InlineSyntaxBuilder {
        priorityValue = value
        this
    }
    /** 设置与其他 rule 冲突时使用的分组。
     * @param value 分组名称。
     * @return 同一 builder，支持链式调用。
     */
    public func conflictGroup(value: String): InlineSyntaxBuilder {
        conflictGroupValue = value
        this
    }
    /** 设置静态 resource cost。
     * @param cost 要使用的 resource cost。
     * @return 同一 builder，支持链式调用。
     */
    public func resourceCost(cost: SyntaxResourceCost): InlineSyntaxBuilder {
        resourceCostValue = cost
        this
    }
    /** 注册 typed payload emitter。
     * @param emitter 要注册的 emitter。
     * @return 同一 builder，支持链式调用。
     */
    public func emit(emitter: InlinePayloadEmitter): InlineSyntaxBuilder {
        emitterValue = Some(emitter)
        this
    }
}

/** inline DSL 的入口工厂。 */
public class InlineSyntax {
    /** 创建指定扩展和 rule ID 的 inline builder。
     * @param extensionId 扩展 id。
     * @param ruleId rule id。
     * @return 新的 inline builder。
     */
    public static func define(extensionId: String, ruleId: String): InlineSyntaxBuilder {
        InlineSyntaxBuilder(extensionId, ruleId)
    }
}

// cjlint-ignore -start !G.ENU.01 Public BlockContentMode.Markdown is the frozen DSL spelling.
/** block body 按 Markdown 解析还是作为 literal 保留。 */
public enum BlockContentMode {
    /** body 按 Markdown 解析。 */
    | Markdown
    /** body 作为 literal 保留。 */
    | Literal
}

/** block rule 的边界语法。 */
public enum BlockSyntaxKind {
    /** paired-container：由 opener 与 closer 定义范围。 */
    | PairedContainer
    /** 单行 rule。 */
    | SingleLine
    /** 脚注定义：标签行和缩进四列的后续 Markdown blocks。 */
    | FootnoteDefinition
    /** 术语行和冒号定义，包含普通 Markdown 正文。 */
    | DefinitionList
    /** 独占一行的 `$$` 边界和不解析 Markdown 的公式正文。 */
    | DisplayMath
}

// cjlint-ignore -end Public BlockContentMode.Markdown is the frozen DSL spelling.
/** block 参数支持的类型。 */
public enum SyntaxParameterType {
    /** 字符串参数。 */
    | StringValue
    /** 整数参数。 */
    | IntegerValue
    /** 布尔参数。 */
    | BooleanValue
    /** 标识符参数。 */
    | IdentifierValue
}

/** block 参数解析后的 typed value。 */
public enum SyntaxParameterValue {
    /** 字符串值。 */
    | StringValue(String)
    /** 整数值。 */
    | IntegerValue(Int64)
    /** 布尔值。 */
    | BooleanValue(Bool)
    /** 标识符值。 */
    | IdentifierValue(String)
}

/** block syntax 参数名、类型和 required 标记。 */
public class SyntaxParameterSpec {
    /** 参数名称。 */
    public let name: String
    /** 参数类型。 */
    public let parameterType: SyntaxParameterType
    /** 是否必填。 */
    public let required: Bool
    /**
     * 创建参数规格；名称为空时抛出 `IllegalArgumentException`。
     * @param name 参数名称。
     * @param parameterType 参数类型。
     * @param required 是否必填。
     */
    public init(name: String, parameterType: SyntaxParameterType, required!: Bool = false) {
        if (name.isEmpty()) {
            throw IllegalArgumentException("parameter name must not be empty")
        }
        this.name = name
        this.parameterType = parameterType
        this.required = required
    }
}

/** block DSL 匹配后的 raw 参数、literal、children 和 typed values。 */
public class BlockSyntaxMatch {
    /** 匹配所属的扩展 id。 */
    public let extensionId: String
    /** 匹配的 rule id。 */
    public let ruleId: String
    /** 从 opener 派生的 block 名称。 */
    public let name: String
    /** 原始参数文本。 */
    public let parametersRaw: String
    /** 匹配到的 body 文本。 */
    public let literal: String
    /** 匹配覆盖的 source span。 */
    public let span: SourceSpan
    /** 匹配子节点的语义摘要。 */
    public let children: ImmutableArray<SyntaxChildSummary>
    private let typedValues: HashMap<String, SyntaxParameterValue>

    /**
     * 创建 block 匹配记录。
     * @param extensionId 匹配所属的扩展 id。
     * @param ruleId 匹配的 rule id。
     * @param name 从 opener 派生的 block 名称。
     * @param parametersRaw 原始参数文本。
     * @param literal 匹配到的 body 文本。
     * @param span 匹配覆盖的 source span。
     * @param children 匹配子节点的语义摘要。
     * @param typedValues 已解析的 typed 参数表。
     */
    public init(extensionId: String, ruleId: String, name: String, parametersRaw: String, literal: String,
        span: SourceSpan, children: Array<SyntaxChildSummary>, typedValues: HashMap<String, SyntaxParameterValue>) {
        this.extensionId = extensionId
        this.ruleId = ruleId
        this.name = name
        this.parametersRaw = parametersRaw
        this.literal = literal
        this.span = span
        this.children = ImmutableArray<SyntaxChildSummary>(children)
        this.typedValues = typedValues
    }

    /** 按名称读取已解析的 typed parameter；未提供时返回 None。
     * @param name 参数名称。
     * @return 对应的 typed 参数值；未提供时为 `None`。
     */
    public func parameter(name: String): ?SyntaxParameterValue {
        typedValues.get(name)
    }
}

/** 将 block 匹配转换为 typed custom payload 的 callback。 */
public interface BlockPayloadEmitter {
    /** 将 block 匹配转换为 typed payload。
     * @param value block 匹配记录。
     * @return 转换得到的 typed payload。
     */
    func emit(value: BlockSyntaxMatch): CustomPayload
}

/** 编译后的 block syntax rule；由 `BlockSyntaxBuilder` 生成。 */
public class BlockSyntaxRule {
    /** rule 所属的扩展 id。 */
    public let extensionId: String
    /** rule 的稳定 id。 */
    public let ruleId: String
    /** opener prefix 文本。 */
    public let openerPrefix: String
    /** paired block 的精确 closer。 */
    public let closer: String
    /** body 的 Markdown 或 literal 模式。 */
    public let contentMode: BlockContentMode
    /** 是否允许同 rule 嵌套。 */
    public let allowNesting: Bool
    /** 原始 block body 的 byte 上限。 */
    public let maximumBlockBytes: Int64
    /** 单次 capture 的 byte 上限。 */
    public let maximumCaptureLength: Int64
    /** rule 的解析优先级。 */
    public let priority: Int64
    /** 与其他 rule 冲突时使用的分组。 */
    public let conflictGroup: String
    /** 支持的 typed 参数规格列表。 */
    public let parameters: ImmutableArray<SyntaxParameterSpec>
    /** rule 参与的解析阶段。 */
    public let phase: SyntaxPhase
    /** 平局裁决规则说明。 */
    public let tieBreak: String
    /** 回溯策略。 */
    public let backtrackingPolicy: SyntaxBacktrackingPolicy
    /** 静态 resource cost。 */
    public let resourceCost: SyntaxResourceCost
    /** typed payload emitter。 */
    public let emitter: ?BlockPayloadEmitter
    /** block 语法形态。 */
    public let syntaxKind: BlockSyntaxKind
    /** local kind 是否从 opener 后第一个词派生。 */
    public let kindFromFirstWord: Bool
    /** 是否只在文档开头匹配。 */
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

/**
 * 构造 block syntax rule 的 fluent builder。
 *
 * 默认 body 按 Markdown 解析、允许嵌套，`maximumBlockBytes` 为 1 MiB，
 * `maximumCaptureLength` 为 4096，priority 为 100。
 *
 * ```cj
 * let note = BlockSyntax.define("docs", "note")
 *     .opener(":::")
 *     .closer(":::")
 *     .content(BlockContentMode.Markdown)
 * ```
 */
public class BlockSyntaxBuilder {
    /** builder 所属的扩展 id。 */
    public let extensionId: String
    /** builder 的 rule id。 */
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

    /** 定义 paired block 的 opener prefix。
     * @param prefix opener prefix 文本。
     * @return 同一 builder，支持链式调用。
     */
    public func opener(prefix: String): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.PairedContainer
        openerPrefixValue = prefix
        this
    }
    /** 定义单行 block rule，并关闭嵌套。
     * @param prefix 行前缀文本。
     * @return 同一 builder，支持链式调用。
     */
    public func linePrefix(prefix: String): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.SingleLine
        openerPrefixValue = prefix
        closerValue = ""
        allowNestingValue = false
        this
    }
    /** 定义 `[^label]:` 脚注和缩进四列的后续正文。
     * @return 同一 builder，支持链式调用。
     */
    public func footnoteDefinition(): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.FootnoteDefinition
        openerPrefixValue = "[^"
        closerValue = ""
        contentModeValue = BlockContentMode.Markdown
        kindFromFirstWordValue = false
        allowNestingValue = true
        this
    }
    /** 定义带 entry/term/definition 归属的结构化定义列表。
     * @return 同一 builder，支持链式调用。
     */
    public func definitionList(): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.DefinitionList
        openerPrefixValue = ":"
        closerValue = ""
        contentModeValue = BlockContentMode.Markdown
        kindFromFirstWordValue = false
        allowNestingValue = true
        this
    }
    /** 定义独占一行的 `$$` display math；正文只保存 TeX 和来源。 */
    public func displayMath(): BlockSyntaxBuilder {
        syntaxKindValue = BlockSyntaxKind.DisplayMath
        openerPrefixValue = "$$"
        closerValue = "$$"
        contentModeValue = BlockContentMode.Literal
        kindFromFirstWordValue = false
        allowNestingValue = false
        this
    }
    /** 设置 paired block 的精确 closer。
     * @param exact closer 文本。
     * @return 同一 builder，支持链式调用。
     */
    public func closer(exact: String): BlockSyntaxBuilder {
        closerValue = exact
        this
    }
    /** 选择 body 的 Markdown 或 literal 模式。
     * @param mode 要使用的内容模式。
     * @return 同一 builder，支持链式调用。
     */
    public func content(mode: BlockContentMode): BlockSyntaxBuilder {
        contentModeValue = mode
        this
    }
    /** 设置是否允许同规则嵌套。
     * @param allow 是否允许嵌套。
     * @return 同一 builder，支持链式调用。
     */
    public func nesting(allow: Bool): BlockSyntaxBuilder {
        allowNestingValue = allow
        this
    }
    /** 设置原始 block body 的 byte 上限。
     * @param value byte 上限。
     * @return 同一 builder，支持链式调用。
     */
    public func maximumBlockBytes(value: Int64): BlockSyntaxBuilder {
        maximumBlockBytesValue = value
        this
    }
    /** 设置单次 capture 的 byte 上限。
     * @param value byte 上限。
     * @return 同一 builder，支持链式调用。
     */
    public func maximumCaptureLength(value: Int64): BlockSyntaxBuilder {
        maximumCaptureLengthValue = value
        this
    }
    /** 设置 rule priority。
     * @param value 优先级数值。
     * @return 同一 builder，支持链式调用。
     */
    public func priority(value: Int64): BlockSyntaxBuilder {
        priorityValue = value
        this
    }
    /** 设置冲突分组。
     * @param value 分组名称。
     * @return 同一 builder，支持链式调用。
     */
    public func conflictGroup(value: String): BlockSyntaxBuilder {
        conflictGroupValue = value
        this
    }
    /** 添加 typed 参数；unknown、duplicate、missing 或类型不匹配会在编译/解析时失败。
     * @param name 参数名称。
     * @param parameterType 参数类型。
     * @param required 是否必填。
     * @return 同一 builder，支持链式调用。
     */
    public func parameter(name: String, parameterType: SyntaxParameterType, required!: Bool = false): BlockSyntaxBuilder {
        parameterValues.add(SyntaxParameterSpec(name, parameterType, required: required));
        this
    }
    /** 设置静态 resource cost。
     * @param cost 要使用的 resource cost。
     * @return 同一 builder，支持链式调用。
     */
    public func resourceCost(cost: SyntaxResourceCost): BlockSyntaxBuilder {
        resourceCostValue = cost
        this
    }
    /** 注册 typed payload emitter。
     * @param emitter 要注册的 emitter。
     * @return 同一 builder，支持链式调用。
     */
    public func emit(emitter: BlockPayloadEmitter): BlockSyntaxBuilder {
        emitterValue = Some(emitter)
        this
    }
    /** 设置 local kind 是否从 opener 后第一个词派生。
     * @param enabled 是否从第一个词派生。
     * @return 同一 builder，支持链式调用。
     */
    public func kindFromFirstWord(enabled: Bool): BlockSyntaxBuilder {
        kindFromFirstWordValue = enabled
        this
    }
    /** 限制 rule 只在文档开头匹配。
     * @param enabled 是否只在文档开头匹配。
     * @return 同一 builder，支持链式调用。
     */
    public func documentStartOnly(enabled!: Bool = true): BlockSyntaxBuilder {
        documentStartOnlyValue = enabled
        this
    }
}

/** block DSL 的入口工厂。 */
public class BlockSyntax {
    /** 创建指定扩展和 rule ID 的 block builder。
     * @param extensionId 扩展 id。
     * @param ruleId rule id。
     * @return 新的 block builder。
     */
    public static func define(extensionId: String, ruleId: String): BlockSyntaxBuilder {
        BlockSyntaxBuilder(extensionId, ruleId)
    }
}

// cjlint-ignore -start !G.ENU.01 Public RendererAttributeKind.Text is the frozen DSL spelling.
/** renderer attribute 值的类别。 */
public enum RendererAttributeKind {
    /** 纯文本属性。 */
    | Text
    /** link URI 属性。 */
    | LinkUri
    /** image URI 属性。 */
    | ImageUri
}
// cjlint-ignore -end Public RendererAttributeKind.Text is the frozen DSL spelling.

/** renderer attribute 值的来源。 */
public enum RendererAttributeSource {
    /** 固定文本值，携带值内容。 */
    | FixedValue(String)
    /** 从 payload 参数读取，携带参数名。 */
    | PayloadParameter(String)
    /** 使用 payload literal 文本。 */
    | PayloadLiteral
}

/** renderer attribute 的名称、URI kind 和 payload 来源。 */
public class RendererAttributeSpec {
    /** 属性名称。 */
    public let name: String
    /** 属性值类别。 */
    public let kind: RendererAttributeKind
    /** 属性值来源。 */
    public let source: RendererAttributeSource
    /**
     * 创建 attribute 规格。
     * @param name 属性名称。
     * @param kind 属性值类别。
     * @param source 属性值来源。
     */
    public init(name: String, kind: RendererAttributeKind, source: RendererAttributeSource) {
        this.name = name
        this.kind = kind
        this.source = source
    }
}

/** custom block 降低为 Markdown 时的容器或单行形式。 */
public enum MarkdownBlockLowering {
    /** 以容器元素包裹 child 内容。 */
    | Container
    /** 以单行形式降低。 */
    | Line
}

/**
 * custom node 到 HTML、纯文本和 Markdown 的声明式 lowering 规则。
 *
 * `classToken`、opener/closer、text prefix/suffix 默认为空；attribute 默认不定义，
 * `renderPayloadLiteral` 默认关闭，block lowering 默认是 `Container`。
 *
 * ```cj
 * let rule = RendererRule("docs", "note", "aside", classToken: "note")
 * ```
 */
public class RendererRule {
    /** rule 所属的扩展 id。 */
    public let extensionId: String
    /** 扩展内的 local kind id。 */
    public let localKindId: String
    /** 输出使用的 HTML tag。 */
    public let htmlTag: String
    /** 附加到 HTML tag 的 class。 */
    public let classToken: String
    /** Markdown lowering 的 opener 文本。 */
    public let markdownOpener: String
    /** Markdown lowering 的 closer 文本。 */
    public let markdownCloser: String
    /** 纯文本输出的前缀。 */
    public let textPrefix: String
    /** 纯文本输出的后缀。 */
    public let textSuffix: String
    /** 声明式 attribute 规格列表。 */
    public let attributes: ImmutableArray<RendererAttributeSpec>
    /** 是否将 payload literal 原样写入 HTML。 */
    public let renderPayloadLiteral: Bool
    /** custom block 的 Markdown lowering 形式。 */
    public let markdownBlockLowering: MarkdownBlockLowering

    /**
     * 创建 renderer rule。
     * @param extensionId rule 所属的扩展 id。
     * @param localKindId 扩展内的 local kind id。
     * @param htmlTag 输出使用的 HTML tag。
     * @param classToken 附加到 HTML tag 的 class。
     * @param markdownOpener Markdown lowering 的 opener 文本。
     * @param markdownCloser Markdown lowering 的 closer 文本。
     * @param textPrefix 纯文本输出的前缀。
     * @param textSuffix 纯文本输出的后缀。
     * @param attributes 声明式 attribute 规格列表。
     * @param renderPayloadLiteral 是否将 payload literal 原样写入 HTML。
     * @param markdownBlockLowering custom block 的 Markdown lowering 形式。
     */
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

/** dialect parser 的扩展开关和未闭合 block 诊断选项。 */
public class DialectParserOptions {
    /** 未闭合扩展 block 是否产生诊断。 */
    public let emitUnclosedExtensionDiagnostics: Bool
    /** 是否启用扩展解析。 */
    public let extensionsEnabled: Bool

    /**
     * 创建 parser options。
     * @param emitUnclosedExtensionDiagnostics 未闭合扩展 block 是否产生诊断。
     * @param extensionsEnabled 是否启用扩展解析。
     */
    public init(emitUnclosedExtensionDiagnostics!: Bool = true, extensionsEnabled!: Bool = true) {
        this.emitUnclosedExtensionDiagnostics = emitUnclosedExtensionDiagnostics
        this.extensionsEnabled = extensionsEnabled
    }
}

/**
 * 版本化 dialect 的声明集合。
 *
 * 通过 `define(id, version)` 创建 builder，再由 `DialectCompiler.compile` 校验并
 * 生成 `CompiledMarkdownDialect`。
 */
public class MarkdownDialect {
    /** dialect 的稳定唯一 id。 */
    public let id: String
    /** dialect 的语义版本。 */
    public let version: String
    /** 作为基础的 profile。 */
    public let baseProfile: MarkdownProfile
    /** 扩展 parser options。 */
    public let parserOptions: DialectParserOptions
    /** dialect 默认 limits。 */
    public let limits: ParseLimits
    internal let manifests: Array<ExtensionManifest>
    internal let inlineBuilders: Array<InlineSyntaxBuilder>
    internal let blockBuilders: Array<BlockSyntaxBuilder>
    internal let rendererRules: Array<RendererRule>
    internal let parserSpis: Array<InlineParserSpi>
    internal let astTransforms: Array<ExtensionAstTransform>
    internal let documentAnalyses: Array<ExtensionDocumentAnalysis>
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
        astTransforms = builder.astTransforms.toArray()
        documentAnalyses = builder.documentAnalyses.toArray()
        lintProviders = builder.lintProviders.toArray()
    }

    /** 创建指定身份的 dialect builder。
     * @param id dialect 的稳定唯一 id。
     * @param version dialect 的语义版本。
     * @return 新的 dialect builder。
     */
    public static func define(id: String, version: String): MarkdownDialectBuilder {
        MarkdownDialectBuilder(id, version)
    }
}

/**
 * 组装 profile、limits、extension、syntax、renderer、SPI、processor 和 lint provider。
 *
 * 所有 fluent 方法返回同一个 builder；`build` 只组装声明，语义校验在 compiler 阶段完成。
 *
 * ```cj
 * let dialect = MarkdownDialect.define("docs-v1", "1")
 *     .enable(manifest)
 *     .block(note)
 *     .renderer(rule)
 *     .build()
 * let engine = MarkdownEngine.builder().dialect(dialect).build()
 * ```
 */
public class MarkdownDialectBuilder {
    /** builder 的稳定唯一 id。 */
    public let id: String
    /** builder 的语义版本。 */
    public let version: String
    internal var baseProfileValue = MarkdownProfile.commonMark0312()
    internal var parserOptionsValue = DialectParserOptions()
    internal var limitsValue = ParseLimits.safe()
    internal let manifests = ArrayList<ExtensionManifest>()
    internal let inlineBuilders = ArrayList<InlineSyntaxBuilder>()
    internal let blockBuilders = ArrayList<BlockSyntaxBuilder>()
    internal let rendererRules = ArrayList<RendererRule>()
    internal let parserSpis = ArrayList<InlineParserSpi>()
    internal let astTransforms = ArrayList<ExtensionAstTransform>()
    internal let documentAnalyses = ArrayList<ExtensionDocumentAnalysis>()
    internal let lintProviders = ArrayList<ExtensionLintProvider>()

    internal init(id: String, version: String) {
        this.id = id
        this.version = version
    }

    /** 设置 dialect 的 base profile。
     * @param profile 要使用的 profile。
     * @return 同一 builder，支持链式调用。
     */
    public func base(profile: MarkdownProfile): MarkdownDialectBuilder {
        baseProfileValue = profile
        this
    }
    /** 设置扩展 parser options。
     * @param options 要使用的 parser options。
     * @return 同一 builder，支持链式调用。
     */
    public func parserOptions(options: DialectParserOptions): MarkdownDialectBuilder {
        parserOptionsValue = options
        this
    }
    /** 设置 dialect 默认 limits。
     * @param limits 要使用的结构限制。
     * @return 同一 builder，支持链式调用。
     */
    public func limits(limits: ParseLimits): MarkdownDialectBuilder {
        limitsValue = limits
        this
    }
    /** 注册 extension manifest。
     * @param manifest 要注册的 manifest。
     * @return 同一 builder，支持链式调用。
     */
    public func enable(manifest: ExtensionManifest): MarkdownDialectBuilder {
        manifests.add(manifest);
        this
    }
    /** 注册 inline syntax builder。
     * @param rule 要注册的 inline builder。
     * @return 同一 builder，支持链式调用。
     */
    public func inline(rule: InlineSyntaxBuilder): MarkdownDialectBuilder {
        inlineBuilders.add(rule);
        this
    }
    /** 注册 block syntax builder。
     * @param rule 要注册的 block builder。
     * @return 同一 builder，支持链式调用。
     */
    public func block(rule: BlockSyntaxBuilder): MarkdownDialectBuilder {
        blockBuilders.add(rule);
        this
    }
    /** 注册 custom node renderer rule。
     * @param rule 要注册的 renderer rule。
     * @return 同一 builder，支持链式调用。
     */
    public func renderer(rule: RendererRule): MarkdownDialectBuilder {
        rendererRules.add(rule);
        this
    }
    /** 注册 inline parser SPI。
     * @param spi 要注册的 SPI 实现。
     * @return 同一 builder，支持链式调用。
     */
    public func parserSpi(spi: InlineParserSpi): MarkdownDialectBuilder {
        parserSpis.add(spi);
        this
    }
    /** 注册绑定前的完整 AST transform。
     * @param processor 要注册的转换。
     * @return 同一 builder，支持链式调用。
     */
    public func astTransform(processor: ExtensionAstTransform): MarkdownDialectBuilder {
        astTransforms.add(processor)
        this
    }
    /** 注册完整绑定后的只读 document analysis。
     * @param analysis 分析实现；只产生诊断，不修改 AST。
     * @return 同一 builder，支持链式调用。
     */
    public func documentAnalysis(analysis: ExtensionDocumentAnalysis): MarkdownDialectBuilder {
        documentAnalyses.add(analysis)
        this
    }
    /** 注册 snapshot lint provider。
     * @param provider 要注册的 lint provider。
     * @return 同一 builder，支持链式调用。
     */
    public func lint(provider: ExtensionLintProvider): MarkdownDialectBuilder {
        lintProviders.add(provider)
        this
    }
    /** 在编译前移除指定 extension 的全部声明。
     * @param extensionId 要移除的扩展 id。
     * @return 同一 builder，支持链式调用。
     */
    public func disable(extensionId: String): MarkdownDialectBuilder {
        manifests.removeIf({manifest => manifest.extensionId == extensionId})
        inlineBuilders.removeIf({rule => rule.extensionId == extensionId})
        blockBuilders.removeIf({rule => rule.extensionId == extensionId})
        rendererRules.removeIf({rule => rule.extensionId == extensionId})
        parserSpis.removeIf({spi => spi.extensionId == extensionId})
        astTransforms.removeIf({processor => processor.extensionId == extensionId})
        documentAnalyses.removeIf({analysis => analysis.extensionId == extensionId})
        lintProviders.removeIf({provider => provider.extensionId == extensionId})
        this
    }
    /**
     * 生成不可变 dialect 声明。
     * @return 不可变的 dialect 声明。
     */
    public func build(): MarkdownDialect {
        MarkdownDialect(this)
    }
}

/** 通过 compiler 验证后的不可变 dialect 及其已排序规则。 */
public class CompiledMarkdownDialect {
    /** 编译后的 dialect id。 */
    public let id: String
    /** 编译后的 dialect 版本。 */
    public let version: String
    /** 作为基础的 profile。 */
    public let baseProfile: MarkdownProfile
    /** 扩展 parser options。 */
    public let parserOptions: DialectParserOptions
    /** dialect 声明的默认 limits。 */
    public let declaredLimits: ParseLimits
    /** 稳定的 dialect fingerprint。 */
    public let fingerprint: String
    /** 启用的 manifest 列表。 */
    public let manifests: ImmutableArray<ExtensionManifest>
    /** 已排序的 inline rule 列表。 */
    public let inlineRules: ImmutableArray<InlineSyntaxRule>
    /** 已排序的 block rule 列表。 */
    public let blockRules: ImmutableArray<BlockSyntaxRule>
    /** 已排序的 renderer rule 列表。 */
    public let rendererRules: ImmutableArray<RendererRule>
    /** 已排序的 parser SPI 列表。 */
    public let parserSpis: ImmutableArray<InlineParserSpi>
    /** 绑定前 AST transform 的有序执行计划。 */
    public let astTransforms: ImmutableArray<ExtensionAstTransform>
    /** 绑定后只读分析的有序执行计划。 */
    public let documentAnalyses: ImmutableArray<ExtensionDocumentAnalysis>
    /** 已排序的 lint provider 列表。 */
    public let lintProviders: ImmutableArray<ExtensionLintProvider>
    internal let parserHotPlan: ParserHotPlan
    internal let rendererHotPlan: RendererHotPlan

    internal func requiresFullAst(): Bool {
        parserHotPlan.hasDocumentStages || (parserOptions.extensionsEnabled && (parserHotPlan.hasFootnotes ||
            parserHotPlan.headingIdRule.isSome() || parserHotPlan.definitionListRule.isSome() || parserHotPlan.hasMath))
    }

    internal init(
        dialect: MarkdownDialect,
        inlineRules: Array<InlineSyntaxRule>,
        blockRules: Array<BlockSyntaxRule>,
        parserSpis: Array<InlineParserSpi>,
        astTransforms: Array<ExtensionAstTransform>,
        documentAnalyses: Array<ExtensionDocumentAnalysis>,
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
        this.astTransforms = ImmutableArray<ExtensionAstTransform>(astTransforms)
        this.documentAnalyses = ImmutableArray<ExtensionDocumentAnalysis>(documentAnalyses)
        this.lintProviders = ImmutableArray<ExtensionLintProvider>(lintProviders)
        parserHotPlan = ParserHotPlan(inlineRules, blockRules, parserSpis, astTransforms, documentAnalyses)
        rendererHotPlan = RendererHotPlan(dialect.rendererRules)
    }

    /** 为内建 profile 创建无扩展的已编译 dialect。
     * @param profile 目标 profile。
     * @return 无扩展的已编译 dialect。
     */
    public static func builtin(profile: MarkdownProfile): CompiledMarkdownDialect {
        DialectCompiler.compile(MarkdownDialect.define(profile.id, profile.standardVersion).base(profile).build())
    }
}

/** 验证 dialect 身份、依赖、规则、能力声明并生成 fingerprint。 */
public class DialectCompiler {
    /**
     * 编译 dialect；失败时抛出 `MarkdownException` 或 `ExtensionFailureException`。
     * @param dialect 待校验和编译的 dialect。
     * @return 带有稳定 fingerprint 和排序规则的 compiled dialect。
     * @throws MarkdownException 身份、依赖、规则或能力校验失败时。
     */
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
        let processors = ArrayList<ExtensionAstTransform>()
        processors.add(all: dialect.astTransforms)
        validateAstTransforms(processors, manifestIds)
        sortAstTransforms(processors)
        let analyses = ArrayList<ExtensionDocumentAnalysis>()
        analyses.add(all: dialect.documentAnalyses)
        validateDocumentAnalyses(analyses, manifestIds)
        sortDocumentAnalyses(analyses)
        let lintProviders = ArrayList<ExtensionLintProvider>()
        lintProviders.add(all: dialect.lintProviders)
        validateLintProviders(lintProviders, manifestIds)
        sortInline(inline)
        sortBlock(block)
        validateCapabilities(dialect)
        validateRenderers(dialect, manifestIds)
        let canonical = canonicalDescriptor(dialect, inline.toArray(), block.toArray())
        CompiledMarkdownDialect(dialect, inline.toArray(), block.toArray(), spis.toArray(), processors.toArray(),
            analyses.toArray(), lintProviders.toArray(), stableDescriptorDigest(canonical))
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
            if (spi.triggerBytes.isEmpty()) {
                fail("parser SPI trigger bytes must not be empty")
            }
            let triggers = HashSet<Byte>()
            for (trigger in spi.triggerBytes) {
                if (!triggers.add(trigger)) {
                    fail("parser SPI trigger bytes must not contain duplicates")
                }
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

    private static func validateAstTransforms(values: ArrayList<ExtensionAstTransform>, manifestIds: HashSet<String>): Unit {
        let identities = HashSet<String>()
        for (processor in values) {
            if (!manifestIds.contains(processor.extensionId)) {
                fail("document processor extension is not enabled")
            }
            validateIdentifier("document processor id", processor.transformId)
            validateIdentifier("document processor version", processor.version)
            if (!processor.deterministic) {
                fail("non-deterministic document processor is not supported")
            }
            if (!identities.add("${processor.extensionId}/${processor.transformId}")) {
                fail("duplicate document processor id")
            }
        }
    }

    private static func validateDocumentAnalyses(values: ArrayList<ExtensionDocumentAnalysis>,
        manifestIds: HashSet<String>): Unit {
        let identities = HashSet<String>()
        for (analysis in values) {
            if (!manifestIds.contains(analysis.extensionId)) {
                fail("document analysis extension is not enabled")
            }
            validateIdentifier("document analysis id", analysis.analysisId)
            validateIdentifier("document analysis version", analysis.version)
            if (!analysis.deterministic) {
                fail("non-deterministic document analysis is not supported")
            }
            if (!identities.add("${analysis.extensionId}/${analysis.analysisId}")) {
                fail("duplicate document analysis id")
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
            let boundRenderer = hasBoundSemanticRenderer(dialect, manifest.extensionId)
            var hasParser = false
            var hasAnalysis = false
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
            for (transform in dialect.astTransforms) {
                if (transform.extensionId == manifest.extensionId) {
                    hasTransform = true
                    if (!manifest.capabilities.transform) {
                        fail("AST transform requires transform capability")
                    }
                }
            }
            for (analysis in dialect.documentAnalyses) {
                if (analysis.extensionId == manifest.extensionId) {
                    hasAnalysis = true
                    if (!manifest.capabilities.analysis) {
                        fail("document analysis requires analysis capability")
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
            if (manifest.capabilities.analysis && !hasAnalysis) {
                fail("analysis capability has no document analysis")
            }
            if (manifest.capabilities.transform && !hasTransform) {
                fail("transform capability has no AST transform")
            }
            if (manifest.capabilities.lint && !hasLint && !boundRenderer) {
                fail("lint capability has no extension lint provider")
            }
            if ((manifest.capabilities.serialize && !boundRenderer) || manifest.capabilities.incremental) {
                fail("the parser plan does not support the declared extension cache/edit capability")
            }
            let renderer = findRenderer(dialect.rendererRules, manifest.extensionId)
            let needsRenderer = manifest.capabilities.specHtml || manifest.capabilities.safeHtml || manifest
                .capabilities
                .plainText || manifest.capabilities.markdown || manifest.capabilities.format
            if (needsRenderer && !boundRenderer && renderer.isNone() && match (manifest.missingRendererPolicy) {
                case MissingRendererPolicy.Error => true;
                case _ => false
            }) {
                fail("declared renderer capability has no renderer rule")
            }
            if (!boundRenderer && (manifest.capabilities.markdown || manifest.capabilities.format)) {
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

    private static func hasBoundFootnoteRenderer(dialect: MarkdownDialect, extensionId: String): Bool {
        if (extensionId != "footnotes") {
            return false
        }
        var reference = false
        var definition = false
        for (rule in dialect.inlineBuilders) {
            if (rule.extensionId == extensionId && rule.ruleId == "footnote-reference") {
                if (let Some(emitter) <- rule.emitterValue) {
                    if (emitter is FootnoteReferenceEmitter) {
                        reference = true
                    }
                }
            }
        }
        for (rule in dialect.blockBuilders) {
            if (rule.extensionId == extensionId && rule.ruleId == "footnote-definition" && let BlockSyntaxKind
                .FootnoteDefinition <- rule.syntaxKindValue) {
                definition = true
            }
        }
        reference && definition
    }

    private static func hasBoundSemanticRenderer(dialect: MarkdownDialect, extensionId: String): Bool {
        if (hasBoundFootnoteRenderer(dialect, extensionId)) {
            return true
        }
        for (rule in dialect.blockBuilders) {
            if (rule.extensionId == extensionId && let BlockSyntaxKind.DisplayMath <- rule.syntaxKindValue) {
                return true
            }
            if (rule.extensionId == extensionId && let BlockSyntaxKind.DefinitionList <- rule.syntaxKindValue) {
                return true
            }
        }
        for (rule in dialect.inlineBuilders) {
            if (rule.extensionId == extensionId && let Some(emitter) <- rule.emitterValue) {
                if (emitter is MathInlineEmitter) {
                    return true
                }
            }
        }
        if (extensionId == "heading-ids") {
            for (rule in dialect.inlineBuilders) {
                if (rule.extensionId == extensionId && let InlineSyntaxKind.HeadingIdSuffix <- rule.syntaxKindValue) {
                    return true
                }
            }
        }
        false
    }

    private static func validateManifest(manifest: ExtensionManifest): Unit {
        validateIdentifier("extension id", manifest.extensionId)
        validateIdentifier("semantic version", manifest.semanticVersion)
        if (parseSemanticVersion(manifest.semanticVersion).isNone()) {
            fail("extension semantic version must be a valid SemVer version")
        }
        validateIdentifier("implementation version", manifest.implementationVersion)
        if (manifest.requiredSpiVersion != "3") {
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
        if (let Some(emitter) <- rule.emitterValue) {
            if (emitter is MathInlineEmitter) {
                if (rule.openerValue != "$" || rule.closerValue != "$" || rule.parseChildrenValue || rule
                    .emitContentValue || rule.allowLineBreaksValue || rule.allowNestingValue) {
                    fail("inline math requires the fixed literal grammar and payload")
                }
                if (let InlineEscapePolicy.LiteralBackslash <- rule.escapePolicyValue) {
                    fail("inline math requires backslash-protected delimiters")
                }
                match (rule.flankingRuleValue) {
                    case InlineFlankingRule.CommonMark => ()
                    case _ => fail("inline math requires CommonMark flanking")
                }
            }
        }
        match (rule.syntaxKindValue) {
            case InlineSyntaxKind.HeadingIdSuffix =>
                if (rule.openerValue != "{#" || rule.closerValue != "}" || rule.emitterValue.isSome() || rule
                    .parseChildrenValue || rule.emitContentValue || rule.allowLineBreaksValue || rule.allowNestingValue) {
                    fail("heading IDs require the structured heading suffix grammar and payload")
                }
                if (let InlineEscapePolicy.LiteralBackslash <- rule.escapePolicyValue) {
                    fail("heading IDs require the fixed heading suffix escape policy")
                }
                match (rule.flankingRuleValue) {
                    case InlineFlankingRule.Any => ()
                    case _ => fail("heading IDs require the fixed heading suffix boundary")
                }
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
            case BlockSyntaxKind.DisplayMath =>
                if (rule.openerPrefixValue != "$$" || rule.closerValue != "$$" || rule.kindFromFirstWordValue ||
                    rule.emitterValue.isSome() || !rule.parameterValues.isEmpty() || rule.allowNestingValue || rule
                    .documentStartOnlyValue) {
                    fail("display math requires the fixed structured grammar and payload")
                }
                if (let BlockContentMode.Markdown <- rule.contentModeValue) {
                    fail("display math content must be literal")
                }
            case BlockSyntaxKind.DefinitionList =>
                if (rule.openerPrefixValue != ":" || !rule.closerValue.isEmpty() || rule.kindFromFirstWordValue ||
                    rule.emitterValue.isSome() || !rule.parameterValues.isEmpty() || !rule.allowNestingValue || rule
                    .documentStartOnlyValue) {
                    fail("definition lists require the structured grammar and payload")
                }
                if (let BlockContentMode.Literal <- rule.contentModeValue) {
                    fail("definition list content must be Markdown")
                }
            case BlockSyntaxKind.FootnoteDefinition =>
                if (rule.openerPrefixValue != "[^" || !rule.closerValue.isEmpty() || rule.kindFromFirstWordValue ||
                    rule.emitterValue.isSome() || !rule.parameterValues.isEmpty() || !rule.allowNestingValue) {
                    fail("footnote definitions require the structured footnote grammar and payload")
                }
                if (let BlockContentMode.Literal <- rule.contentModeValue) {
                    fail("footnote definition content must be Markdown")
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
            if (hasSemanticRendererOverride(dialect, renderer)) {
                fail("structured semantic nodes do not support generic renderer overrides")
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
                        !hasBoundSemanticRenderer(dialect, manifest.extensionId) &&
                        !hasRenderer(dialect.rendererRules, manifest.extensionId)) {
                        fail("missing renderer coverage")
                    }
                case _ => ()
            }
        }
    }

    private static func hasSemanticRendererOverride(dialect: MarkdownDialect, renderer: RendererRule): Bool {
        for (rule in dialect.inlineBuilders) {
            if (rule.extensionId == renderer.extensionId && rule.ruleId == renderer.localKindId) {
                if (let InlineSyntaxKind.HeadingIdSuffix <- rule.syntaxKindValue) {
                    return true
                }
                if (let Some(emitter) <- rule.emitterValue) {
                    if (emitter is FootnoteReferenceEmitter || emitter is MathInlineEmitter) {
                        return true
                    }
                }
            }
        }
        for (rule in dialect.blockBuilders) {
            if (rule.extensionId != renderer.extensionId) {
                continue
            }
            match (rule.syntaxKindValue) {
                case BlockSyntaxKind.DisplayMath =>
                    if (renderer.localKindId == rule.ruleId) {
                        return true
                    }
                case BlockSyntaxKind.FootnoteDefinition =>
                    if (renderer.localKindId == "footnote-definition") {
                        return true
                    }
                case BlockSyntaxKind.DefinitionList => for (role in [DefinitionListRole.List, DefinitionListRole.Entry,
                    DefinitionListRole.Term, DefinitionListRole.Definition]) {
                    if (definitionListKind(role) == renderer.localKindId) {
                        return true
                    }
                }
                case _ => ()
            }
        }
        false
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

    private static func sortAstTransforms(values: ArrayList<ExtensionAstTransform>): Unit {
        var index: Int64 = 1
        while (index < values.size) {
            var current = index
            while (current > 0 && astTransformBefore(values[current], values[current - 1])) {
                let swap = values[current - 1]
                values[current - 1] = values[current]
                values[current] = swap
                current--
            }
            index++
        }
    }

    private static func astTransformBefore(left: ExtensionAstTransform, right: ExtensionAstTransform): Bool {
        if (left.priority != right.priority) {
            return left.priority > right.priority
        }
        if (left.extensionId != right.extensionId) {
            return left.extensionId < right.extensionId
        }
        left.transformId < right.transformId
    }

    private static func sortDocumentAnalyses(values: ArrayList<ExtensionDocumentAnalysis>): Unit {
        var index: Int64 = 1
        while (index < values.size) {
            var current = index
            while (current > 0 && documentAnalysisBefore(values[current], values[current - 1])) {
                let swap = values[current - 1]
                values[current - 1] = values[current]
                values[current] = swap
                current--
            }
            index++
        }
    }

    private static func documentAnalysisBefore(left: ExtensionDocumentAnalysis, right: ExtensionDocumentAnalysis): Bool {
        if (left.priority != right.priority) {
            return left.priority > right.priority
        }
        if (left.extensionId != right.extensionId) {
            return left.extensionId < right.extensionId
        }
        left.analysisId < right.analysisId
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

/** 内建 DSL custom node 使用的 payload，保留 raw 参数、literal 和 typed values。 */
public class SyntaxPayload <: CustomPayload {
    /** block 名称。 */
    public let name: String
    /** 原始参数文本。 */
    public let parameters: String
    /** 原始 body 文本。 */
    public let literal: String
    private let typedValues: HashMap<String, SyntaxParameterValue>

    /**
     * 创建 payload。
     * @param name block 名称。
     * @param parameters 原始参数文本。
     * @param literal 原始 body 文本。
     * @param typedValues 已解析的 typed 参数表。
     */
    public init(name: String, parameters: String, literal: String,
        typedValues!: HashMap<String, SyntaxParameterValue> = HashMap<String, SyntaxParameterValue>()) {
        this.name = name
        this.parameters = parameters
        this.literal = literal
        this.typedValues = typedValues
    }
    /**
     * 返回稳定 payload type identity。
     * @return 稳定的 payload type 标识。
     */
    public func payloadTypeId(): String {
        "markdown.syntax-payload.v1"
    }
    /** 按名称读取 typed parameter；不存在时返回 None。
     * @param name 参数名称。
     * @return 对应的 typed 参数值；不存在时为 `None`。
     */
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
    out.append("parser-plan-4|dialect=");
    out.append(dialect.id);
    out.append("@");
    out.append(dialect.version)
    out.append("|base-kind=");
    out.append(profileKindIdentityTag(dialect.baseProfile.kind))
    out.append("|base-id=");
    out.append(dialect.baseProfile.id)
    out.append("|base-version=");
    out.append(dialect.baseProfile.standardVersion)
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
        out.append(manifest.capabilities.analysis)
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
            case InlineSyntaxKind.HeadingIdSuffix => out.append("heading-id")
        }
        out.append(":children=");
        out.append(rule.parseChildren)
        out.append(":emit-content=");
        out.append(rule.emitContent)
        out.append(":nesting=");
        out.append(rule.allowNesting)
        out.append(":line-breaks=");
        out.append(rule.allowLineBreaks)
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
            case BlockSyntaxKind.FootnoteDefinition => out.append("footnote")
            case BlockSyntaxKind.DefinitionList => out.append("definition-list/2")
            case BlockSyntaxKind.DisplayMath => out.append("display-math/2")
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
    for (processor in dialect.astTransforms) {
        out.append("|ast-transform=");
        out.append(processor.extensionId);
        out.append("/")
        out.append(processor.transformId);
        out.append("@");
        out.append(processor.version);
        out.append(":")
        out.append("transform")
        out.append(":");
        out.append(processor.priority)
    }
    for (analysis in dialect.documentAnalyses) {
        out.append("|document-analysis=")
        out.append(analysis.extensionId)
        out.append("/")
        out.append(analysis.analysisId)
        out.append("@")
        out.append(analysis.version)
        out.append(":")
        out.append(analysis.priority)
    }
    for (provider in dialect.lintProviders) {
        out.append("|lint=");
        out.append(provider.extensionId);
        out.append("/")
        out.append(provider.ruleId);
        out.append("@");
        out.append(provider.version)
    }
    out.append("|spi=3|plan=4")
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
