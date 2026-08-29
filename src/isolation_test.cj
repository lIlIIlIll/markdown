package markdown

import std.unittest.*
import std.unittest.testmacro.*

class EchoIsolationTransport <: PluginIsolationTransport {
    var calls: Int64 = 0
    public func invoke(request: IsolatedPluginRequest, policy: PluginIsolationPolicy, _: CancellationToken,
        responseSink: IsolatedPluginResponseSink): IsolatedPluginResponseIdentity {
        calls++
        @Expect(policy.allowFileRead, false)
        @Expect(policy.allowFileWrite, false)
        @Expect(policy.allowNetwork, false)
        @Expect(policy.allowChildProcesses, false)
        responseSink.writeOutput("isolated:")
        responseSink.writeOutput(request.payload)
        IsolatedPluginResponseIdentity(request.protocolVersion, request.extensionId, request.implementationVersion)
    }
}

class FailingIsolationTransport <: PluginIsolationTransport {
    public func invoke(_: IsolatedPluginRequest, _: PluginIsolationPolicy, _: CancellationToken,
        _: IsolatedPluginResponseSink): IsolatedPluginResponseIdentity {
        throw IllegalStateException("worker terminated")
    }
}

class DiagnosticIsolationTransport <: PluginIsolationTransport {
    private let messages: Array<String>
    public init(messages: Array<String>) {
        this.messages = messages
    }
    public func invoke(request: IsolatedPluginRequest, _: PluginIsolationPolicy, _: CancellationToken,
        responseSink: IsolatedPluginResponseSink): IsolatedPluginResponseIdentity {
        for (message in messages) {
            responseSink.beginDiagnostic("PLUGIN", DiagnosticSeverity.Warning, SourceSpan(0, 0),
                extensionId: Some(request.extensionId))
            responseSink.writeDiagnosticMessage(message)
            responseSink.finishDiagnostic()
        }
        IsolatedPluginResponseIdentity(request.protocolVersion, request.extensionId, request.implementationVersion)
    }
}

@Test
class PluginIsolationTest {
    @TestCase
    func isolationPolicyIpcIdentityLimitsCancellationAndFailClosedAreEnforced(): Unit {
        let transport = EchoIsolationTransport()
        let runner = IsolatedPluginRunner(transport,
            policy: PluginIsolationPolicy(maximumInputBytes: 32, maximumOutputBytes: 64))
        let request = IsolatedPluginRequest("plugin", "build-1", "render", "value")
        @Expect(runner.invoke(request).output, "isolated:value")
        @Expect(transport.calls, 1)
        @Expect(runner.capabilities().processBoundaryRequired, true)
        @Expect(runner.capabilities().builtInOsSandbox, false)

        let cancelled = CancellationSource();
        cancelled.cancel()
        try {
            runner.invoke(request, cancellation: cancelled.token);
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled => @Expect(true)
                case _ => @Expect(false)
            }
        }
        @Expect(transport.calls, 1)

        try {
            runner.invoke(IsolatedPluginRequest("plugin", "build-1", "render", "012345678901234567890123456789012"))
            @Expect(false)
        } catch (_: LimitExceededException) {
            @Expect(true)
        }

        try {
            IsolatedPluginRunner(FailingIsolationTransport()).invoke(request);
            @Expect(false)
        } catch (error: ExtensionFailureException) {
            @Expect(error.extensionId, "plugin")
            @Expect(error.cause.message, "worker terminated")
        }
    }

    @TestCase
    func isolationDiagnosticsAreBoundedDuringTransportDecode(): Unit {
        let request = IsolatedPluginRequest("plugin", "build-1", "lint", "value")
        try {
            IsolatedPluginRunner(DiagnosticIsolationTransport(["a", "b"]),
                policy: PluginIsolationPolicy(maximumDiagnosticCount: 1)).invoke(request)
            @Expect(false)
        } catch (error: ExtensionFailureException) {
            @Expect(error.cause is LimitExceededException, true)
        }

        try {
            IsolatedPluginRunner(DiagnosticIsolationTransport(["12345"]),
                policy: PluginIsolationPolicy(maximumDiagnosticMessageBytes: 4)).invoke(request)
            @Expect(false)
        } catch (error: ExtensionFailureException) {
            @Expect(error.cause is LimitExceededException, true)
        }

        try {
            IsolatedPluginRunner(DiagnosticIsolationTransport(["1234", "5678"]),
                policy: PluginIsolationPolicy(maximumDiagnosticAggregateBytes: 35)).invoke(request)
            @Expect(false)
        } catch (error: ExtensionFailureException) {
            @Expect(error.cause is LimitExceededException, true)
        }

        try {
            IsolatedPluginRunner(DiagnosticIsolationTransport(["1234"]),
                policy: PluginIsolationPolicy(maximumResponseBytes: 32)).invoke(request)
            @Expect(false)
        } catch (error: ExtensionFailureException) {
            @Expect(error.cause is LimitExceededException, true)
        }
    }
}
