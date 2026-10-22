package markdown.engine

import markdown.core.ImmutableArray
import std.collection.*

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
