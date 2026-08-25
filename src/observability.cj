package markdown

import std.time.*

public class StatisticsOptions {
    public let timing: Bool
    public init(timing!: Bool = false) {
        this.timing = timing
    }
}

public class ParseStatistics {
    public let inputBytes: Int64
    public let lineCount: Int64
    public let nodeCount: Int64
    public let maxDepth: Int64
    public let referenceCount: Int64
    public let extensionCallbackCount: Int64
    public let scanSteps: Int64
    public let parseDurationNanos: ?Int64
    public let diagnosticCount: Int64
    public let profileId: String
    public let dialectFingerprint: String
    public init(result: ParseResult, budget: OperationBudget, duration: ?Int64) {
        inputBytes = result.source.byteLength()
        lineCount = result.source.lineCount()
        var nodes: Int64 = 0;
        var depth: Int64 = 0;
        var maximumDepth: Int64 = 0
        for (event in result.document.walk()) {
            match (event) {
                case WalkEvent.Enter(_) =>
                    nodes++;
                    depth++
                    if (depth > maximumDepth) {
                        maximumDepth = depth
                    }
                case WalkEvent.Exit(_) => depth--
            }
        }
        nodeCount = nodes
        maxDepth = maximumDepth
        referenceCount = result.document.references.size
        extensionCallbackCount = budget.usedExtensionCallbacks()
        scanSteps = budget.usedScanSteps()
        parseDurationNanos = duration
        diagnosticCount = result.diagnostics.size
        profileId = result.document.profile.id
        dialectFingerprint = result.document.dialectFingerprint
    }
}

public class ObservedParseResult {
    public let result: ParseResult
    public let statistics: ParseStatistics
    public init(result: ParseResult, statistics: ParseStatistics) {
        this.result = result
        this.statistics = statistics
    }
}

public class RenderStatistics {
    public let renderedNodes: Int64
    public let outputBytes: Int64
    public let renderDurationNanos: ?Int64
    public let rendererFingerprint: String
    public init(renderedNodes: Int64, outputBytes: Int64, duration: ?Int64, rendererFingerprint: String) {
        this.renderedNodes = renderedNodes
        this.outputBytes = outputBytes
        this.renderDurationNanos = duration
        this.rendererFingerprint = rendererFingerprint
    }
}

public class ObservedRenderedOutput {
    public let content: String
    public let statistics: RenderStatistics
    public init(content: String, statistics: RenderStatistics) {
        this.content = content
        this.statistics = statistics
    }
}

extend MarkdownEngine {
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
