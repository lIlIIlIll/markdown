package markdown

import std.time.*

/** 可选的统计计时开关；默认不读取时钟。 */
public class StatisticsOptions {
    /** 是否采集计时信息。 */
    public let timing: Bool
    /**
     * 创建统计选项。
     * @param timing 是否读取时钟采集耗时。
     */
    public init(timing!: Bool = false) {
        this.timing = timing
    }
}

/** parse 输入、AST、reference、callback、scan 和可选 duration 统计。 */
public class ParseStatistics {
    /** 输入的字节数。 */
    public let inputBytes: Int64
    /** 输入行数。 */
    public let lineCount: Int64
    /** AST 节点总数。 */
    public let nodeCount: Int64
    /** AST 最大深度。 */
    public let maxDepth: Int64
    /** 引用定义（reference definition）数量。 */
    public let referenceCount: Int64
    /** 扩展回调调用次数。 */
    public let extensionCallbackCount: Int64
    /** 扫描步数。 */
    public let scanSteps: Int64
    /** 解析耗时（纳秒）；未开启 timing 时为 `None`。 */
    public let parseDurationNanos: ?Int64
    /** 诊断数量。 */
    public let diagnosticCount: Int64
    /** 实际使用的 profile id。 */
    public let profileId: String
    /** 实际使用的 dialect fingerprint。 */
    public let dialectFingerprint: String
    /**
     * 从 parse 结果和 budget 汇总统计。
     * @param result 被统计的 parse 结果。
     * @param budget 本次解析使用的操作预算。
     * @param duration 解析耗时（纳秒）；未计时为 `None`。
     */
    public init(result: ParseResult, budget: OperationBudget, duration: ?Int64) {
        inputBytes = result.source.byteLength()
        lineCount = result.source.lineCount()
        var nodes: Int64 = 0;
        var depth: Int64 = 0;
        var maximumDepth: Int64 = 0
        for (event in result.ast.walk()) {
            match (event) {
                case NodeRefWalkEvent.Enter(_) =>
                    nodes++;
                    depth++
                    if (depth > maximumDepth) {
                        maximumDepth = depth
                    }
                case NodeRefWalkEvent.Exit(_) => depth--
            }
        }
        nodeCount = nodes
        maxDepth = maximumDepth
        let root = result.ast.root().asDocument().getOrThrow()
        referenceCount = root.references.size
        extensionCallbackCount = budget.usedExtensionCallbacks()
        scanSteps = budget.usedScanSteps()
        parseDurationNanos = duration
        diagnosticCount = result.diagnostics.size
        profileId = root.profile.id
        dialectFingerprint = root.dialectFingerprint
    }
}

/** 带 `ParseStatistics` 的 parse result。 */
public class ObservedParseResult {
    /** 原始 parse 结果。 */
    public let result: ParseResult
    /** 关联的解析统计。 */
    public let statistics: ParseStatistics
    /**
     * 创建带统计的 parse 结果。
     * @param result 原始 parse 结果。
     * @param statistics 关联的解析统计。
     */
    public init(result: ParseResult, statistics: ParseStatistics) {
        this.result = result
        this.statistics = statistics
    }
}

/** renderer 节点、输出 byte、可选 duration 和 fingerprint 统计。 */
public class RenderStatistics {
    /** 渲染的节点数。 */
    public let renderedNodes: Int64
    /** 输出的字节数。 */
    public let outputBytes: Int64
    /** 渲染耗时（纳秒）；未开启 timing 时为 `None`。 */
    public let renderDurationNanos: ?Int64
    /** renderer 的 fingerprint。 */
    public let rendererFingerprint: String
    /**
     * 创建渲染统计。
     * @param renderedNodes 渲染的节点数。
     * @param outputBytes 输出的字节数。
     * @param duration 渲染耗时（纳秒）；未计时为 `None`。
     * @param rendererFingerprint renderer 的 fingerprint。
     */
    public init(renderedNodes: Int64, outputBytes: Int64, duration: ?Int64, rendererFingerprint: String) {
        this.renderedNodes = renderedNodes
        this.outputBytes = outputBytes
        this.renderDurationNanos = duration
        this.rendererFingerprint = rendererFingerprint
    }
}

/** 带 `RenderStatistics` 的 HTML 输出。 */
public class ObservedRenderedOutput {
    /** 渲染得到的 HTML 文本。 */
    public let content: String
    /** 关联的渲染统计。 */
    public let statistics: RenderStatistics
    /**
     * 创建带统计的渲染输出。
     * @param content 渲染得到的 HTML 文本。
     * @param statistics 关联的渲染统计。
     */
    public init(content: String, statistics: RenderStatistics) {
        this.content = content
        this.statistics = statistics
    }
}

extend MarkdownEngine {
    /** 解析并返回带统计信息的结果；`timing` 默认关闭。
     * @param value 待解析的 Markdown 文本。
     * @param options 统计选项。
     * @return 带统计的解析结果。
     * @throws MarkdownException 底层 parse 失败时。
     */
    public func parseObserved(value: String, options!: StatisticsOptions = StatisticsOptions()): ObservedParseResult {
        let budget = OperationBudget.safe()
        let start: ?MonoTime = if (options.timing) {
            Some(MonoTime.now())
        } else {
            None
        }
        let result = parse(value, budget: budget)
        let duration: ?Int64 = match (start) {
            case Some(value) => Some((MonoTime.now() - value).toNanoseconds())
            case None => None
        }
        ObservedParseResult(result, ParseStatistics(result, budget, duration))
    }
}

extend HtmlRenderer {
    /** 渲染并返回带统计信息的输出；`timing` 默认关闭。
     * @param document 待渲染的 Document。
     * @param options 统计选项。
     * @return 带统计的渲染输出。
     * @throws MarkdownException 底层 render 失败时。
     */
    public func renderObserved(document: Document, options!: StatisticsOptions = StatisticsOptions()): ObservedRenderedOutput {
        let budget = OperationBudget.safe()
        let start: ?MonoTime = if (options.timing) {
            Some(MonoTime.now())
        } else {
            None
        }
        let content = render(document, budget: budget)
        let duration: ?Int64 = match (start) {
            case Some(value) => Some((MonoTime.now() - value).toNanoseconds())
            case None => None
        }
        ObservedRenderedOutput(content,
            RenderStatistics(budget.usedRenderedNodes(), budget.usedOutputBytes(), duration, fingerprint()))
    }
}
