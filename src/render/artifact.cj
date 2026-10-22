package markdown.render

import markdown.core.{Document, ImmutableArray, MarkdownErrorCode, MarkdownException, NodeId, SourceSpan}
import std.collection.*

/** 一段 renderer 输出与 source span、NodeId 的映射记录。 */
public class RenderedSourceMapEntry {
    /** 输出中的 byte range。 */
    public let outputRange: SourceSpan
    /** 对应的粗粒度 source span；纯结构标记为 None，派生展示可保留来源。 */
    public let sourceSpan: ?SourceSpan
    /** 产生该输出的 AST 节点 id；纯结构标记为 None，派生展示可保留节点。 */
    public let nodeId: ?NodeId
    /** 是否为生成内容；true 且带来源表示派生展示，不表示字符级映射。 */
    public let generated: Bool
    /**
     * 创建 source map 记录。
     * @param outputRange 输出中的 byte range。
     * @param sourceSpan 粗粒度来源；纯结构标记为 None，派生展示可保留来源。
     * @param nodeId 原始节点；纯结构标记为 None，派生展示可保留节点。
     * @param generated 是否为 renderer 生成的非 source 内容。
     */
    public init(outputRange: SourceSpan, sourceSpan: ?SourceSpan, nodeId: ?NodeId, generated: Bool) {
        this.outputRange = outputRange
        this.sourceSpan = sourceSpan
        this.nodeId = nodeId
        this.generated = generated
    }
}

/** 带 source map 的 HTML 输出；查询按 output byte range 工作。 */
public class RenderedOutput {
    /** 渲染得到的 HTML 文本。 */
    public let content: String
    /** 按 output byte 排序的 source map 记录。 */
    public let sourceMap: ImmutableArray<RenderedSourceMapEntry>
    /**
     * 创建带 source map 的输出。
     * @param content 渲染得到的 HTML 文本。
     * @param sourceMap source map 记录列表。
     */
    public init(content: String, sourceMap: Array<RenderedSourceMapEntry>) {
        this.content = content
        this.sourceMap = ImmutableArray<RenderedSourceMapEntry>(sourceMap)
    }

    /** 查询 output byte 对应的 source span；无 source 对应的 generated 片段返回 None。
     * @param outputByte 输出中的字节偏移。
     * @return 粗粒度来源；没有来源的结构标记为 None。
     * @throws IllegalArgumentException outputByte 越界时。
     */
    public func sourceSpanAt(outputByte: Int64): ?SourceSpan {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        findEntry(outputByte).sourceSpan
    }

    /** 查询 output byte 对应的 NodeId；无来源的结构标记返回 None。
     * @param outputByte 输出中的字节偏移。
     * @return 对应的 NodeId；没有来源的结构标记为 None。
     * @throws IllegalArgumentException outputByte 越界时。
     */
    public func nodeIdAt(outputByte: Int64): ?NodeId {
        if (outputByte < 0 || outputByte >= content.size) {
            throw IllegalArgumentException("output byte is outside rendered content")
        }
        findEntry(outputByte).nodeId
    }

    /** 返回一个 NodeId 产生的所有 output ranges。
     * @param nodeId 目标节点 id。
     * @return 该节点产生的全部 output range。
     */
    public func outputRanges(nodeId: NodeId): Array<SourceSpan> {
        let ranges = ArrayList<SourceSpan>()
        for (entry in sourceMap.toArray()) {
            if (entry.nodeId == Some(nodeId)) {
                ranges.add(entry.outputRange)
            }
        }
        ranges.toArray()
    }

    private func findEntry(outputByte: Int64): RenderedSourceMapEntry {
        var low: Int64 = 0
        var high = sourceMap.size
        while (low < high) {
            let middle = low + (high - low) / 2
            let entry = sourceMap[middle]
            if (outputByte < entry.outputRange.startByte) {
                high = middle
            } else if (outputByte >= entry.outputRange.endByte) {
                low = middle + 1
            } else {
                return entry
            }
        }
        throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
            "rendered source map does not cover output byte", phase: "source_map")
    }
}

extend HtmlRenderer {
    /**
     * 渲染 HTML 并同步记录 output-to-source map，不通过输出字符串反推映射。
     * @param document 要渲染的 Document。
     * @return 包含 HTML 和 source map 的 `RenderedOutput`。
     * @throws MarkdownException 取消或超出限制时。
     * @throws SinkFailureException sink 写入失败时。
     */
    public func renderWithSourceMap(document: Document): RenderedOutput {
        let sink = StringTextSink(true)
        renderTo(document, sink)
        RenderedOutput(sink.content(), sink.sourceMap())
    }
}
