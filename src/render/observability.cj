package markdown.render

import markdown.core.{Document, OperationBudget, StatisticsOptions}
import std.time.*

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
