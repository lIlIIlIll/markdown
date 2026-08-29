package markdown

import std.collection.*

public class PluginIsolationPolicy {
    public let allowFileRead: Bool
    public let allowFileWrite: Bool
    public let allowNetwork: Bool
    public let allowChildProcesses: Bool
    public let maximumInputBytes: Int64
    public let maximumOutputBytes: Int64
    public let maximumDiagnosticCount: Int64
    public let maximumDiagnosticMessageBytes: Int64
    public let maximumDiagnosticAggregateBytes: Int64
    public let maximumResponseBytes: Int64
    public let protocolVersion: String
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

public class IsolatedPluginRequest {
    public let protocolVersion: String
    public let extensionId: String
    public let implementationVersion: String
    public let operation: String
    public let payload: String
    public init(extensionId: String, implementationVersion: String, operation: String, payload: String,
        protocolVersion!: String = "markdown-isolation-ipc-1") {
        this.protocolVersion = protocolVersion
        this.extensionId = extensionId
        this.implementationVersion = implementationVersion
        this.operation = operation
        this.payload = payload
    }
}

public class IsolatedPluginResponse {
    public let protocolVersion: String
    public let extensionId: String
    public let implementationVersion: String
    public let output: String
    public let diagnostics: ImmutableArray<Diagnostic>
    public init(extensionId: String, implementationVersion: String, output: String,
        diagnostics!: Array<Diagnostic> = [], protocolVersion!: String = "markdown-isolation-ipc-1") {
        this.protocolVersion = protocolVersion
        this.extensionId = extensionId
        this.implementationVersion = implementationVersion
        this.output = output
        this.diagnostics = ImmutableArray<Diagnostic>(diagnostics)
    }
}

public class IsolatedPluginResponseIdentity {
    public let protocolVersion: String
    public let extensionId: String
    public let implementationVersion: String
    public init(protocolVersion: String, extensionId: String, implementationVersion: String) {
        this.protocolVersion = protocolVersion
        this.extensionId = extensionId
        this.implementationVersion = implementationVersion
    }
}

/**
 * Bounded response decoder for an isolated plugin transport.
 *
 * A transport must stream decoded output and diagnostics through this sink.
 * The sink rejects a limit before it retains the chunk or diagnostic.
 */
public class IsolatedPluginResponseSink {
    private let policy: PluginIsolationPolicy
    private let cancellation: CancellationToken
    private let budget: OperationBudget
    private let output = StringBuilder()
    private let diagnostics = ArrayList<Diagnostic>()
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
        consumeDiagnosticBytes(encodedBytes, extensionId)
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

    public func writeDiagnosticMessage(chunk: String): Unit {
        ensureDiagnosticOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        checkAdditional("isolated_plugin_diagnostic_message", policy.maximumDiagnosticMessageBytes,
            diagnosticMessageBytes, chunk.size)
        consumeDiagnosticBytes(chunk.size, diagnosticExtensionId)
        diagnosticMessage.append(chunk)
        diagnosticMessageBytes += chunk.size
    }

    public func addDiagnosticRelatedSpan(span: SourceSpan): Unit {
        ensureDiagnosticOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        consumeDiagnosticBytes(16, diagnosticExtensionId)
        diagnosticRelatedSpans.add(span)
    }

    public func addDiagnosticFix(title: String, span: SourceSpan, replacement: String): Unit {
        ensureDiagnosticOpen()
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        consumeDiagnosticBytes(title.size + replacement.size + 16, diagnosticExtensionId)
        diagnosticFixes.add(DiagnosticFix(title, span, replacement))
    }

    public func finishDiagnostic(): Unit {
        ensureDiagnosticOpen()
        diagnostics.add(
            Diagnostic(diagnosticCode, diagnosticSeverity, diagnosticMessage.toString(), diagnosticSpan,
                relatedSpans: diagnosticRelatedSpans.toArray(), extensionId: diagnosticExtensionId,
                ruleId: diagnosticRuleId, fixes: diagnosticFixes.toArray()))
        diagnosticOpen = false
    }

    private func consumeDiagnosticBytes(encodedBytes: Int64, extensionId: ?String): Unit {
        checkAdditional("isolated_plugin_diagnostics", policy.maximumDiagnosticAggregateBytes, diagnosticBytes,
            encodedBytes)
        checkAdditional("isolated_plugin_response", policy.maximumResponseBytes, responseBytes, encodedBytes)
        budget.consumeOutput(bytes: encodedBytes)
        diagnosticBytes += encodedBytes
        responseBytes += encodedBytes
    }

    internal func finish(identity: IsolatedPluginResponseIdentity): IsolatedPluginResponse {
        ensureOpen()
        if (diagnosticOpen) {
            throw IllegalStateException("isolated plugin diagnostic is unfinished")
        }
        let identityBytes = identity.protocolVersion.size + identity.extensionId.size + identity
            .implementationVersion
            .size
        checkAdditional("isolated_plugin_response", policy.maximumResponseBytes, responseBytes, identityBytes)
        budget.consumeOutput(bytes: identityBytes)
        responseBytes += identityBytes
        finished = true
        IsolatedPluginResponse(identity.extensionId, identity.implementationVersion, output.toString(),
            diagnostics: diagnostics.toArray(), protocolVersion: identity.protocolVersion)
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

public interface PluginIsolationTransport {
    // Implementations must create the OS process/sandbox and enforce the passed policy.
    // Decode untrusted output incrementally through responseSink; do not build an unbounded response first.
    func invoke(request: IsolatedPluginRequest, policy: PluginIsolationPolicy, cancellation: CancellationToken,
        responseSink: IsolatedPluginResponseSink): IsolatedPluginResponseIdentity
}

public class PluginIsolationCapabilities {
    public let protocolVersion: String = "markdown-isolation-ipc-1"
    public let processBoundaryRequired: Bool = true
    public let builtInOsSandbox: Bool = false
    public let failClosed: Bool = true
    public init() {}
}

public class IsolatedPluginRunner {
    public let policy: PluginIsolationPolicy
    private let transport: PluginIsolationTransport
    public init(transport: PluginIsolationTransport, policy!: PluginIsolationPolicy = PluginIsolationPolicy()) {
        this.transport = transport
        this.policy = policy
    }

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
        let identity = try {
            transport.invoke(request, policy, cancellation, responseSink)
        } catch (error: Exception) {
            throw ExtensionFailureException(request.extensionId, "isolated", request.implementationVersion,
                "plugin_isolation", error)
        }
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        let response = responseSink.finish(identity)
        if (response.protocolVersion != policy.protocolVersion || response.extensionId != request.extensionId ||
            response.implementationVersion != request.implementationVersion) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure, "isolated plugin response identity mismatch",
                phase: "plugin_isolation")
        }
        response
    }

    public func capabilities(): PluginIsolationCapabilities {
        PluginIsolationCapabilities()
    }
}
