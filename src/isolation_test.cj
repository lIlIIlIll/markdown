package markdown

import std.unittest.*
import std.unittest.testmacro.*

class EchoIsolationTransport <: PluginIsolationTransport {
    var calls: Int64 = 0
    public func invoke(request: IsolatedPluginRequest, policy: PluginIsolationPolicy, _: CancellationToken): IsolatedPluginResponse {
        calls++
        @Expect(policy.allowFileRead, false)
        @Expect(policy.allowFileWrite, false)
        @Expect(policy.allowNetwork, false)
        @Expect(policy.allowChildProcesses, false)
        IsolatedPluginResponse(request.extensionId, request.implementationVersion, "isolated:${request.payload}")
    }
}

class FailingIsolationTransport <: PluginIsolationTransport {
    public func invoke(_: IsolatedPluginRequest, _: PluginIsolationPolicy, _: CancellationToken): IsolatedPluginResponse {
        throw IllegalStateException("worker terminated")
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
}
