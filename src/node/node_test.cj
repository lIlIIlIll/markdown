package markdown.node

import markdown.core.{CancellationSource, MarkdownException, OperationBudget}
import markdown.render.{RichContentFailure, RichContentKind, RichContentLimits, RichContentOutcome, RichContentRequest}
import std.unittest.*
import std.unittest.testmacro.*

@Test
class OptionalNodeBackendTests {
    @TestCase
    func missingRuntimeIsReadableWithoutLaunchingAnyProgram(): Unit {
        let backend = NodeRichContentBackend("/__markdown_missing_runtime__", "/__markdown_missing_work__")
        @Expect(backend.runtimeIdentity, "missing")
        let results = backend.prepare([RichContentRequest(RichContentKind.Math, "x")], RichContentLimits(),
            OperationBudget.safe(), CancellationSource().token)
        @Expect(results.size, 1)
        if (let RichContentOutcome.Unavailable(RichContentFailure.Missing) <- results[0]) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        let cancelled = CancellationSource();
        cancelled.cancel()
        @ExpectThrows[MarkdownException](backend.prepare([], RichContentLimits(), OperationBudget.safe(), cancelled.token))
    }

    @TestCase
    func identitiesIncludeOnlyActualKindConfiguration(): Unit {
        let light = NodeRichContentBackend("/__markdown_missing_runtime__", "/__markdown_missing_work__")
        let dark = NodeRichContentBackend("/__markdown_missing_runtime__", "/__markdown_missing_work__",
            shikiTheme: "github-dark", diagramTheme: "dark", allowUnsandboxedChromium: true)
        @Expect(light.identity(RichContentKind.Math), dark.identity(RichContentKind.Math))
        @Expect(light.identity(RichContentKind.Highlight) != dark.identity(RichContentKind.Highlight), true)
        @Expect(light.identity(RichContentKind.Diagram) != dark.identity(RichContentKind.Diagram), true)
    }

    @TestCase
    func configurationDoesNotAcceptRelativePathsOrDynamicThemeNames(): Unit {
        @ExpectThrows[IllegalArgumentException](NodeRichContentBackend("relative", "/work"))
        @ExpectThrows[IllegalArgumentException](NodeRichContentBackend("/runtime", "relative"))
        @ExpectThrows[IllegalArgumentException](NodeRichContentBackend("/runtime", "/work", shikiTheme: "custom.json"))
        @ExpectThrows[IllegalArgumentException](NodeRichContentBackend("/runtime", "/work", diagramTheme: "custom"))
    }
}
