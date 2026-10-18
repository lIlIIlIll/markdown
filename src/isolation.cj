package markdown

import std.collection.*

/**
 * isolated plugin IPC 的权限、输入输出上限和协议版本。
 *
 * 权限默认全部关闭；所有 byte/count limits 必须为正数。该类型只描述协议约束，
 * 不会自行创建 OS process 或 sandbox。
 */
public class PluginIsolationPolicy {
    /** 是否允许读取文件。 */
    public let allowFileRead: Bool
    /** 是否允许写入文件。 */
    public let allowFileWrite: Bool
    /** 是否允许访问网络。 */
    public let allowNetwork: Bool
    /** 是否允许创建子进程。 */
    public let allowChildProcesses: Bool
    /** 请求 payload 的最大字节数。 */
    public let maximumInputBytes: Int64
    /** 响应 output 的最大字节数。 */
    public let maximumOutputBytes: Int64
    /** 响应中 diagnostic 的最大数量。 */
    public let maximumDiagnosticCount: Int64
    /** 单条 diagnostic message 的最大字节数。 */
    public let maximumDiagnosticMessageBytes: Int64
    /** 全部 diagnostic 合计的最大字节数。 */
    public let maximumDiagnosticAggregateBytes: Int64
    /** 响应合计的最大字节数。 */
    public let maximumResponseBytes: Int64
    /** IPC 协议版本。 */
    public let protocolVersion: String
    /**
     * 创建隔离策略；byte/count limits 非正时抛出 `IllegalArgumentException`。
     * @param allowFileRead 是否允许读取文件。
     * @param allowFileWrite 是否允许写入文件。
     * @param allowNetwork 是否允许访问网络。
     * @param allowChildProcesses 是否允许创建子进程。
     * @param maximumInputBytes 请求 payload 的最大字节数。
     * @param maximumOutputBytes 响应 output 的最大字节数。
     * @param maximumDiagnosticCount 响应中 diagnostic 的最大数量。
     * @param maximumDiagnosticMessageBytes 单条 diagnostic message 的最大字节数。
     * @param maximumDiagnosticAggregateBytes 全部 diagnostic 合计的最大字节数。
     * @param maximumResponseBytes 响应合计的最大字节数。
     * @param protocolVersion IPC 协议版本。
     */
    public init(allowFileRead!: Bool = false, allowFileWrite!: Bool = false, allowNetwork!: Bool = false,
        allowChildProcesses!: Bool = false, maximumInputBytes!: Int64 = 1024 * 1024,
        maximumOutputBytes!: Int64 = 4 * 1024 * 1024, maximumDiagnosticCount!: Int64 = 1024,
        maximumDiagnosticMessageBytes!: Int64 = 64 * 1024, maximumDiagnosticAggregateBytes!: Int64 = 1024 * 1024,
        maximumResponseBytes!: Int64 = 5 * 1024 * 1024, protocolVersion!: String = "markdown-isolation-ipc-1") {
        if (maximumInputBytes <= 0 || maximumOutputBytes <= 0 || maximumDiagnosticCount <= 0 ||
            maximumDiagnosticMessageBytes <= 0 || maximumDiagnosticAggregateBytes <= 0 || maximumResponseBytes <= 0) {
            throw IllegalArgumentException("isolation byte limits must be positive")
        }
        this.allowFileRead = allowFileRead
        this.allowFileWrite = allowFileWrite
        this.allowNetwork = allowNetwork
        this.allowChildProcesses = allowChildProcesses
        this.maximumInputBytes = maximumInputBytes
        this.maximumOutputBytes = maximumOutputBytes
        this.maximumDiagnosticCount = maximumDiagnosticCount
        this.maximumDiagnosticMessageBytes = maximumDiagnosticMessageBytes
        this.maximumDiagnosticAggregateBytes = maximumDiagnosticAggregateBytes
        this.maximumResponseBytes = maximumResponseBytes
        this.protocolVersion = protocolVersion
    }
}

/** isolated plugin 请求的协议、扩展身份、操作和 payload。 */
public class IsolatedPluginRequest {
    /** 请求使用的协议版本。 */
    public let protocolVersion: String
    /** 目标扩展 id。 */
    public let extensionId: String
    /** 目标扩展的实现版本。 */
    public let implementationVersion: String
    /** 请求的操作名称。 */
    public let operation: String
    /** 请求 payload 文本。 */
    public let payload: String
    /**
     * 创建隔离插件请求。
     * @param extensionId 目标扩展 id。
     * @param implementationVersion 目标扩展的实现版本。
     * @param operation 请求的操作名称。
     * @param payload 请求 payload 文本。
     * @param protocolVersion 请求使用的协议版本。
     */
    public init(extensionId: String, implementationVersion: String, operation: String, payload: String,
        protocolVersion!: String = "markdown-isolation-ipc-1") {
        this.protocolVersion = protocolVersion
        this.extensionId = extensionId
        this.implementationVersion = implementationVersion
        this.operation = operation
        this.payload = payload
    }
}

/** isolated plugin 响应的协议身份、output 和 diagnostics。 */
public class IsolatedPluginResponse {
    /** 响应使用的协议版本。 */
    public let protocolVersion: String
    /** 响应对应的扩展 id。 */
    public let extensionId: String
    /** 响应对应的实现版本。 */
    public let implementationVersion: String
    /** 插件产生的 output 文本。 */
    public let output: String
    /** 插件产生的 diagnostic 列表。 */
    public let diagnostics: ImmutableArray<Diagnostic>
    /**
     * 创建隔离插件响应。
     * @param extensionId 响应对应的扩展 id。
     * @param implementationVersion 响应对应的实现版本。
     * @param output 插件产生的 output 文本。
     * @param diagnostics 插件产生的 diagnostic 列表。
     * @param protocolVersion 响应使用的协议版本。
     */
    public init(extensionId: String, implementationVersion: String, output: String,
        diagnostics!: Array<Diagnostic> = [], protocolVersion!: String = "markdown-isolation-ipc-1") {
        this.protocolVersion = protocolVersion
        this.extensionId = extensionId
        this.implementationVersion = implementationVersion
        this.output = output
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
    }
}

/**
 * isolated plugin transport 的有界响应 decoder。
 *
 * transport 必须增量提交身份、output 和 diagnostics；sink 会在保留 chunk 或
 * diagnostic 前检查对应 limits。
 */
public class IsolatedPluginResponseSink {
    private let policy: PluginIsolationPolicy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let output = StringBuilder()
    private let diagnostics = ArrayList<Diagnostic>()
    private let responseProtocolVersion = StringBuilder()
    private let responseExtensionId = StringBuilder()
    private let responseImplementationVersion = StringBuilder()
    private var outputBytes: Int64 = 0
    private var diagnosticBytes: Int64 = 0
    private var responseBytes: Int64 = 0
    private var finished: Bool = false
    private var diagnosticOpen: Bool = false
    private var diagnosticCode: String = ""
    private var diagnosticSeverity: DiagnosticSeverity = DiagnosticSeverity.Info
    private var diagnosticSpan: SourceSpan = SourceSpan(0, 0)
    private var diagnosticExtensionId: ?String = None
    private var diagnosticRuleId: ?String = None
    private var diagnosticMessage = StringBuilder()
    private var diagnosticMessageBytes: Int64 = 0
    private var diagnosticRelatedSpans = ArrayList<SourceSpan>()
    private var diagnosticFixes = ArrayList<DiagnosticFix>()

    internal init(policy: PluginIsolationPolicy, cancellation: CancellationToken, budget: OperationBudget) {
        this.policy = policy
        this.cancellation = cancellation
        this.budget = budget
    }

    /** 增量提交响应 protocol version。
     * @param chunk 要追加的文本块。
     * @throws IllegalStateException 响应已完成时。
     * @throws LimitExceededException 超出响应 byte 上限时。
     * @throws MarkdownException 取消时。
     */
    public func writeProtocolVersion(chunk: String): Unit {
        consumeIdentityBytes(chunk.size)
        responseProtocolVersion.append(chunk)
    }

    /** 增量提交响应 extension ID。
     * @param chunk 要追加的文本块。
     * @throws IllegalStateException 响应已完成时。
     * @throws LimitExceededException 超出响应 byte 上限时。
     * @throws MarkdownException 取消时。
     */
    public func writeExtensionId(chunk: String): Unit {
        consumeIdentityBytes(chunk.size)
        responseExtensionId.append(chunk)
    }

    /** 增量提交响应 implementation version。
     * @param chunk 要追加的文本块。
     * @throws IllegalStateException 响应已完成时。
     * @throws LimitExceededException 超出响应 byte 上限时。
     * @throws MarkdownException 取消时。
     */
    public func writeImplementationVersion(chunk: String): Unit {
        consumeIdentityBytes(chunk.size)
        responseImplementationVersion.append(chunk)
    }

    /** 增量提交 output chunk，并同时检查 output/response limits。
     * @param chunk 要追加的文本块。
     * @throws IllegalStateException 响应已完成时。
     * @throws LimitExceededException 超出响应 byte 上限时。
     * @throws MarkdownException 取消时。
     */
    public func writeOutput(chunk: String): Unit {
        ensureOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        checkAdditional("isolated_plugin_output", policy.maximumOutputBytes, outputBytes, chunk.size)
        checkAdditional("isolated_plugin_response", policy.maximumResponseBytes, responseBytes, chunk.size)
        budget.consumeOutput(bytes: chunk.size)
        output.append(chunk)
        outputBytes += chunk.size
        responseBytes += chunk.size
    }

    /** 开始一条有界 diagnostic。
     * @param code diagnostic 代码，不能为空。
     * @param severity 严重级别。
     * @param span 关联的 source span。
     * @param extensionId 产生 diagnostic 的扩展 id。
     * @param ruleId 产生 diagnostic 的规则 id。
     * @throws IllegalStateException 响应已完成或 diagnostic 已打开时。
     * @throws LimitExceededException diagnostic 数量或聚合字节超限时。
     * @throws IllegalArgumentException code 为空时。
     * @throws MarkdownException 取消时。
     */
    public func beginDiagnostic(code: String, severity: DiagnosticSeverity, span: SourceSpan,
        extensionId!: ?String = None, ruleId!: ?String = None): Unit {
        ensureOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        if (diagnosticOpen) {
            throw IllegalStateException("isolated plugin diagnostic is already open")
        }
        if (diagnostics.size >= policy.maximumDiagnosticCount) {
            throw LimitExceededException("isolated_plugin_diagnostic_count", policy.maximumDiagnosticCount,
                diagnostics.size + 1, "plugin_isolation", extensionId: extensionId)
        }
        if (code.isEmpty()) {
            throw IllegalArgumentException("isolated plugin diagnostic code must not be empty")
        }
        var encodedBytes = code.size + 24
        match (extensionId) {
            case Some(value) => encodedBytes += value.size
            case None => ()
        }
        match (ruleId) {
            case Some(value) => encodedBytes += value.size
            case None => ()
        }
        consumeDiagnosticBytes(encodedBytes)
        diagnosticOpen = true
        diagnosticCode = code
        diagnosticSeverity = severity
        diagnosticSpan = span
        diagnosticExtensionId = extensionId
        diagnosticRuleId = ruleId
        diagnosticMessage = StringBuilder()
        diagnosticMessageBytes = 0
        diagnosticRelatedSpans = ArrayList<SourceSpan>()
        diagnosticFixes = ArrayList<DiagnosticFix>()
    }

    /** 增量追加 diagnostic message。
     * @param chunk 要追加的文本块。
     */
    public func writeDiagnosticMessage(chunk: String): Unit {
        ensureDiagnosticOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        checkAdditional("isolated_plugin_diagnostic_message", policy.maximumDiagnosticMessageBytes,
            diagnosticMessageBytes, chunk.size)
        consumeDiagnosticBytes(chunk.size)
        diagnosticMessage.append(chunk)
        diagnosticMessageBytes += chunk.size
    }

    /** 为当前 diagnostic 添加 related span。
     * @param span 要添加的 source span。
     * @throws IllegalStateException 无打开的 diagnostic 时。
     * @throws LimitExceededException 超出聚合字节上限时。
     * @throws MarkdownException 取消时。
     */
    public func addDiagnosticRelatedSpan(span: SourceSpan): Unit {
        ensureDiagnosticOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        consumeDiagnosticBytes(16)
        diagnosticRelatedSpans.add(span)
    }

    /** 为当前 diagnostic 添加源码 fix。
     * @param title fix 的展示标题。
     * @param span fix 作用的 source span。
     * @param replacement 替换后的文本。
     * @throws IllegalStateException 无打开的 diagnostic 时。
     * @throws LimitExceededException 超出聚合字节上限时。
     * @throws MarkdownException 取消时。
     */
    public func addDiagnosticFix(title: String, span: SourceSpan, replacement: String): Unit {
        ensureDiagnosticOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        consumeDiagnosticBytes(title.size + replacement.size + 16)
        diagnosticFixes.add(DiagnosticFix(title, span, replacement))
    }

    /**
     * 完成当前 diagnostic 并追加到响应。
     * @throws IllegalStateException 无打开的 diagnostic 时。
     */
    public func finishDiagnostic(): Unit {
        ensureDiagnosticOpen()
        diagnostics.add(
            Diagnostic(diagnosticCode, diagnosticSeverity, diagnosticMessage.toString(), diagnosticSpan,
                relatedSpans: diagnosticRelatedSpans.toArray(), extensionId: diagnosticExtensionId,
                ruleId: diagnosticRuleId, fixes: diagnosticFixes.toArray()))
        diagnosticOpen = false
    }

    private func consumeDiagnosticBytes(encodedBytes: Int64): Unit {
        checkAdditional("isolated_plugin_diagnostics", policy.maximumDiagnosticAggregateBytes, diagnosticBytes,
            encodedBytes)
        checkAdditional("isolated_plugin_response", policy.maximumResponseBytes, responseBytes, encodedBytes)
        budget.consumeOutput(bytes: encodedBytes)
        diagnosticBytes += encodedBytes
        responseBytes += encodedBytes
    }

    private func consumeIdentityBytes(encodedBytes: Int64): Unit {
        ensureOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        checkAdditional("isolated_plugin_response", policy.maximumResponseBytes, responseBytes, encodedBytes)
        budget.consumeOutput(bytes: encodedBytes)
        responseBytes += encodedBytes
    }

    internal func finish(request: IsolatedPluginRequest): IsolatedPluginResponse {
        ensureOpen()
        if (diagnosticOpen) {
            throw IllegalStateException("isolated plugin diagnostic is unfinished")
        }
        if (responseProtocolVersion.toString() != request.protocolVersion || responseExtensionId.toString() != request
            .extensionId || responseImplementationVersion.toString() != request.implementationVersion) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure, "isolated plugin response identity mismatch",
                phase: "plugin_isolation")
        }
        finished = true
        IsolatedPluginResponse(request.extensionId, request.implementationVersion, output.toString(),
            diagnostics: diagnostics.toArray(), protocolVersion: request.protocolVersion)
    }

    private func ensureOpen(): Unit {
        if (finished) {
            throw IllegalStateException("isolated plugin response is already finished")
        }
    }

    private func ensureDiagnosticOpen(): Unit {
        ensureOpen()
        if (!diagnosticOpen) {
            throw IllegalStateException("isolated plugin diagnostic is not open")
        }
    }

    private func checkAdditional(kind: String, maximum: Int64, current: Int64, additional: Int64): Unit {
        if (additional < 0 || current > maximum - additional) {
            throw LimitExceededException(kind, maximum, current + additional, "plugin_isolation")
        }
    }
}

/** 宿主实现的进程或 sandbox transport；库只规定 fail-closed IPC 契约。 */
public interface PluginIsolationTransport {
    // Implementations must create the OS process/sandbox and enforce the passed policy.
    // Decode every untrusted string incrementally through responseSink; do not build an unbounded response first.
    /** 在给定 policy 约束下调用插件并增量解码响应。
     * @param request 要执行的插件请求。
     * @param policy 调用使用的隔离策略。
     * @param cancellation 协作式取消信号。
     * @param responseSink 增量响应 sink。
     */
    func invoke(request: IsolatedPluginRequest, policy: PluginIsolationPolicy, cancellation: CancellationToken,
        responseSink: IsolatedPluginResponseSink): Unit
}

/** isolated plugin 端口的协议能力声明；内建 OS sandbox 默认不存在。 */
public class PluginIsolationCapabilities {
    /** 支持的协议版本。 */
    public let protocolVersion: String = "markdown-isolation-ipc-1"
    /** 是否强制进程边界隔离。 */
    public let processBoundaryRequired: Bool = true
    /** 是否提供内建 OS sandbox。 */
    public let builtInOsSandbox: Bool = false
    /** 是否以 fail-closed 方式处理协议错误。 */
    public let failClosed: Bool = true
    /** 创建默认能力声明。 */
    public init() {}
}

/** 使用 transport 和 policy 调用 isolated plugin 的 runner。 */
public class IsolatedPluginRunner {
    /** 调用插件时使用的隔离策略。 */
    public let policy: PluginIsolationPolicy
    private let transport: PluginIsolationTransport
    /**
     * 创建 runner。
     * @param transport 宿主提供的进程或 sandbox transport。
     * @param policy 调用插件时使用的隔离策略。
     */
    public init(transport: PluginIsolationTransport, policy!: PluginIsolationPolicy = PluginIsolationPolicy()) {
        this.transport = transport
        this.policy = policy
    }

    /** 校验 request 身份和 limits，增量收集响应并在身份不匹配时 fail closed。
     * @param request 要执行的插件请求。
     * @param cancellation 协作式取消信号。
     * @param budget 单次调用的操作预算。
     * @return 校验后的插件响应。
     * @throws MarkdownException 协议不匹配时。
     * @throws IllegalArgumentException 请求身份不完整时。
     * @throws LimitExceededException payload 超过上限时。
     * @throws ExtensionFailureException transport 调用失败时。
     */
    public func invoke(request: IsolatedPluginRequest, cancellation!: CancellationToken = CancellationToken.none(),
        budget!: OperationBudget = OperationBudget.safe()): IsolatedPluginResponse {
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        if (request.protocolVersion != policy.protocolVersion) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure, "isolation protocol mismatch",
                phase: "plugin_isolation")
        }
        if (request.extensionId.isEmpty() || request.implementationVersion.isEmpty() || request.operation.isEmpty()) {
            throw IllegalArgumentException("isolated plugin request identity is incomplete")
        }
        if (request.payload.size > policy.maximumInputBytes) {
            throw LimitExceededException("isolated_plugin_input", policy.maximumInputBytes, request.payload.size,
                "plugin_isolation", extensionId: Some(request.extensionId))
        }
        budget.consumeExtensionCallback()
        let responseSink = IsolatedPluginResponseSink(policy, cancellation, budget)
        try {
            transport.invoke(request, policy, cancellation, responseSink)
        } catch (error: Exception) {
            throw ExtensionFailureException(request.extensionId, "isolated", request.implementationVersion,
                "plugin_isolation", error)
        }
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        responseSink.finish(request)
    }

    /**
     * 返回 isolation protocol 能力声明。
     * @return isolation protocol 能力声明。
     */
    public func capabilities(): PluginIsolationCapabilities {
        PluginIsolationCapabilities()
    }
}
