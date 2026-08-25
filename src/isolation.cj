package markdown

public class PluginIsolationPolicy {
    public let allowFileRead: Bool
    public let allowFileWrite: Bool
    public let allowNetwork: Bool
    public let allowChildProcesses: Bool
    public let maximumInputBytes: Int64
    public let maximumOutputBytes: Int64
    public let protocolVersion: String
    public init(allowFileRead!: Bool = false, allowFileWrite!: Bool = false, allowNetwork!: Bool = false,
        allowChildProcesses!: Bool = false, maximumInputBytes!: Int64 = 1024 * 1024,
        maximumOutputBytes!: Int64 = 4 * 1024 * 1024, protocolVersion!: String = "markdown-isolation-ipc-1") {
        if (maximumInputBytes <= 0 || maximumOutputBytes <= 0) {
            throw IllegalArgumentException("isolation byte limits must be positive")
        }
        this.allowFileRead = allowFileRead
        this.allowFileWrite = allowFileWrite
        this.allowNetwork = allowNetwork
        this.allowChildProcesses = allowChildProcesses
        this.maximumInputBytes = maximumInputBytes
        this.maximumOutputBytes = maximumOutputBytes
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

public interface PluginIsolationTransport {
    // Implementations must create the OS process/sandbox and enforce the passed policy.
    func invoke(request: IsolatedPluginRequest, policy: PluginIsolationPolicy, cancellation: CancellationToken): IsolatedPluginResponse
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
        let response = try {
            transport.invoke(request, policy, cancellation)
        } catch (error: Exception) {
            throw ExtensionFailureException(request.extensionId, "isolated", request.implementationVersion,
                "plugin_isolation", error)
        }
        cancellation.throwIfCancelled(phase: "plugin_isolation")
        if (response.protocolVersion != policy.protocolVersion || response.extensionId != request.extensionId ||
            response.implementationVersion != request.implementationVersion) {
            throw MarkdownException(MarkdownErrorCode.ExtensionFailure, "isolated plugin response identity mismatch",
                phase: "plugin_isolation")
        }
        if (response.output.size > policy.maximumOutputBytes) {
            throw LimitExceededException("isolated_plugin_output", policy.maximumOutputBytes, response.output.size,
                "plugin_isolation", extensionId: Some(request.extensionId))
        }
        budget.consumeOutput(bytes: response.output.size)
        response
    }

    public func capabilities(): PluginIsolationCapabilities {
        PluginIsolationCapabilities()
    }
}
