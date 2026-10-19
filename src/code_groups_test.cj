package markdown

import std.unittest.*
import std.unittest.testmacro.*

private func codeGroupTestEngine(): MarkdownEngine {
    MarkdownEngine
        .builder()
        .dialect(OfficialExtensions.codeGroups(MarkdownDialect.define("groups-test", "1")).build())
        .build()
}

private class CodeGroupOutputSink <: AsyncTextSink {
    let text = StringBuilder()
    private var calls: Int64 = 0
    public func write(value: String): AsyncSinkWriteResult {
        calls++
        if (calls % 3 == 1) {
            return AsyncSinkWriteResult.Pause(0)
        }
        text.append(value)
        AsyncSinkWriteResult.Pause(value.size)
    }
}

@Test
class CodeGroupTests {
    @TestCase
    func groupsOrdinaryCodeBlocksWithTitlesHighlightsAndExactCopyText(): Unit {
        let engine = codeGroupTestEngine()
        let source = ":::code-group\r\n```js title=\"main.js\" {2}\r\nalpha < beta\r\n中😀\r\n```\r\n\r\n```cangjie title=\"empty.cj\"\r\n```\r\n:::\r\noutside\r\n"
        let result = engine.parse(source)
        let group = result.document.root().children()[0]
        @Expect(group.children().size, 2)
        let first = codeGroupPayload(group.children()[0]).getOrThrow()
        @Expect(first.title, "main.js")
        @Expect(first.highlightedLines.size, 1)
        @Expect(first.highlightedLines[0].firstLine, 2)
        @Expect(first.copyText, "alpha < beta\r\n中😀\r\n")
        @Expect(group.children()[0].children()[0].asCodeBlock().getOrThrow().literal, "alpha < beta\n中😀\n")
        @Expect(codeGroupPayload(group.children()[1]).getOrThrow().copyText, "")
        let expected = "<div class=\"code-group\">\n<figure class=\"code-group-item\">\n<figcaption>main.js</figcaption>\n<pre><code class=\"language-js\">alpha &lt; beta\n<mark class=\"code-line\">中😀</mark>\n</code></pre>\n</figure>\n<figure class=\"code-group-item\">\n<figcaption>empty.cj</figcaption>\n<pre><code class=\"language-cangjie\"></code></pre>\n</figure>\n</div>\n<p>outside</p>\n"
        @Expect(engine.htmlRenderer().render(result.document), expected)
        @Expect(PlainTextRenderer().render(result.document), "main.js\nalpha < beta\n中😀\n\n\nempty.cj\n\n\noutside")
        @Expect(engine.parseSnapshot(source).syntaxTree.losslessText(), source)
        let mapped = engine.htmlRenderer().renderWithSourceMap(result.document)
        @Expect(mapped.content, expected)
        var found = false
        let code = group.children()[0].children()[0]
        for (entry in mapped.sourceMap.toArray()) {
            if (entry.nodeId == Some(code.nodeId)) {
                found = true
                @Expect(entry.sourceSpan, code.span)
            }
        }
        @Expect(found, true)
        for (widths in [[1], [3, 1, 17, 2], [source.size]]) {
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), result)
        }
    }

    @TestCase
    func fencesOwnTheirContentsAndCanonicalMarkdownKeepsGroupMetadata(): Unit {
        let engine = codeGroupTestEngine()
        for (source in [":::code-group\n~~~~markdown title=\"`notes`\" {1-3}\n```cj\n:::\n```\n~~~~\n:::\n",
            "> :::code-group\r\n> ```text title=\"中😀\" {1}\r\n> \tcode\r\n> ```\r\n> :::\r\n",
            "- :::code-group\n  ```c++\n  int x;\n  ```\n  :::\n",
            ":::code-group\n```\n```\n~~~objective-c title=\"<&>\"\nx\n~~~\n:::\n"]) {
            let result = engine.parse(source)
            @Expect(AstQuery.customNodes(result.document).size >= 2, true)
            let canonical = CanonicalMarkdownRenderer().render(result.document)
            @Expect(engine.htmlRenderer().render(engine.parse(canonical).document), engine.htmlRenderer().render(result.document))
            @Expect(CanonicalMarkdownRenderer().render(engine.parse(canonical).document), canonical)
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), [1]), result)
        }
    }

    @TestCase
    func invalidHeadersRemainVisibleAndReferenceCollectionUsesTheFallback(): Unit {
        let engine = codeGroupTestEngine()
        for (suffix in ["{0}", "{2}", "{1-0}", "{1,1}", "{999999999999999999999}", "{1} ignored", "title=\"bad\\n\"",
            "title=\"unclosed"]) {
            let source = ":::code-group\n```text ${suffix}\nbody\n```\n:::\n"
            let result = engine.parse(source)
            @Expect(AstQuery.customNodes(result.document).size, 0)
            @Expect(result.diagnostics[0].code, "MD5001_INVALID_CODE_GROUP")
            @Expect(PlainTextRenderer().render(result.document).contains("body"), true)
            @Expect(engine.parseSnapshot(source).syntaxTree.losslessText(), source)
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), [1, 2]), result)
        }
        let adjacent = "[x][id]\n\n:::code-group\n[id]: /valid\n:::\n"
        @Expect(Markdown.parse(adjacent).document.references.size, 0)
        @Expect(engine.parse(adjacent).document.references.size, 0)
        let invalidBody = "[x][id]\n\n:::code-group\n\n[id]: /valid\n\n:::\n"
        let fallback = engine.parse(invalidBody)
        @Expect(Markdown.parse(invalidBody).document.references.size, 1)
        @Expect(fallback.document.references.size, 1)
        @Expect(engine.htmlRenderer().render(fallback.document).contains("href=\"/valid\""), true)
        for (source in [":::code-group\n```text\nnot closed\n:::\n", ":::code-group\n```\nx\n```\n"]) {
            let result = engine.parse(source)
            @Expect(AstQuery.customNodes(result.document).size, 0)
            @Expect(PlainTextRenderer().render(result.document).contains(":::code-group"), true)
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), [1]), result)
        }
    }

    @TestCase
    func optionalGrammarAndOutputKeepLimitsCancellationAndBackpressure(): Unit {
        let engine = codeGroupTestEngine()
        let source = ":::code-group\n```text title=\"<unsafe>\" {1}\n中😀 & <x>\n```\n:::\n"
        @Expect(AstQuery.customNodes(Markdown.parse(source).document).size, 0)
        let document = engine.parse(source).document
        let syncBudget = OperationBudget.safe()
        let expected = engine.htmlRenderer().render(document, budget: syncBudget)
        let asyncBudget = OperationBudget.safe()
        let output = engine.htmlRenderer().newOutputSession(document, chunkBytes: 4, budget: asyncBudget)
        let sink = CodeGroupOutputSink()
        var complete = false
        while (!complete) {
            match (output.resume(sink)) {
                case AsyncRenderState.Complete => complete = true
                case AsyncRenderState.Paused => ()
                case AsyncRenderState.Failed(error) => throw error
            }
        }
        @Expect(sink.text.toString(), expected)
        @Expect(asyncBudget.usedRenderedNodes(), syncBudget.usedRenderedNodes())
        @Expect(expected.contains("<figcaption>&lt;unsafe&gt;</figcaption>"), true)
        @ExpectThrows[MarkdownException](engine.parseEvents(source))
        @ExpectThrows[MarkdownException](engine.newRawBlockEventSession())
        @ExpectThrows[MarkdownException](engine.renderHtml(source, mode: HtmlExecutionMode.RequireFused))
        let cancelled = CancellationSource()
        cancelled.cancel()
        @ExpectThrows[MarkdownException](engine.parse(source, cancellation: cancelled.token))
        @ExpectThrows[MarkdownException](engine.parse(source, budget: OperationBudget(10, 100, 100, 100, 100, 100)))
        @ExpectThrows[MarkdownException](HtmlRenderer(maximumOutputBytes: Some(8)).render(document))
        let prefix = ":::code-group\n```text\n"
        let invalidBytes = (prefix + "x\n```\n:::\n").toArray()
        invalidBytes[prefix.size] = 0xFF
        let replaced = engine.parse(invalidBytes, utf8Policy: Utf8Policy.ReplaceInvalid)
        @Expect(codeGroupPayload(replaced.document.root().children()[0].children()[0]).getOrThrow().copyText, "�\n")
        expectAppendEquivalent(engine, appendByWidths(engine, invalidBytes, [1], policy: Utf8Policy.ReplaceInvalid),
            replaced)
        for (kind in 0..3) {
            let rule = BlockSyntax.define("code-groups", "code-group").codeGroup()
            if (kind == 0) {
                rule.nesting(true)
            }
            if (kind == 1) {
                rule.content(BlockContentMode.Literal)
            }
            if (kind == 2) {
                rule.maximumBlockBytes(8)
            }
            let dialect = MarkdownDialect
                .define("bounded-group", "1")
                .enable(ExtensionManifest("code-groups", "1.0.0", "1"))
                .block(rule)
                .build()
            if (kind < 2) {
                @ExpectThrows[MarkdownException](DialectCompiler.compile(dialect))
            } else {
                @ExpectThrows[LimitExceededException](MarkdownEngine.builder().dialect(dialect).build().parse(source))
            }
        }
    }

    @TestCase
    func officialProfilesAndDisablementMatchTheirDeclarations(): Unit {
        let input = ":::code-group\n```text\nx\n```\n:::\n"
        for (profile in [MarkdownProfile.commonMark0312(), MarkdownProfile.gfmModernV1()]) {
            let builder = OfficialExtensions.codeGroups(MarkdownDialect.define("group-profile", "1").base(profile))
            let engine = MarkdownEngine.builder().dialect(builder.build()).build()
            @Expect(engine.capabilities().extension("code-groups").getOrThrow().semanticVersion, "1.0.0")
            @Expect(AstQuery.customNodes(engine.parse(input).document).size, 2)
            let report = MarkdownExtensionTestKit.verify(engine, input)
            @Expect(report.failedChecks.size, 0)
            builder.parserOptions(DialectParserOptions(extensionsEnabled: false))
            let off = MarkdownEngine.builder().dialect(builder.build()).build()
            let base = MarkdownEngine.builder().profile(profile).build()
            @Expect(off.htmlRenderer().render(off.parse(input).document), base.htmlRenderer().render(base.parse(input).document))
            @Expect(AstQuery.customNodes(engine.parse(input).document).size, 2)
        }
        let unsupported = OfficialExtensions
            .codeGroups(MarkdownDialect.define("old-profile", "1").base(MarkdownProfile.gfm029()))
            .build()
        @ExpectThrows[MarkdownException](DialectCompiler.compile(unsupported))
        let override = OfficialExtensions
            .codeGroups(MarkdownDialect.define("group-override", "1"))
            .renderer(RendererRule("code-groups", "code-group-item", "div"))
            .build()
        @ExpectThrows[MarkdownException](DialectCompiler.compile(override))
        let duplicate = OfficialExtensions
            .codeGroups(OfficialExtensions.codeGroups(MarkdownDialect.define("duplicate-group", "1")))
            .build()
        @ExpectThrows[MarkdownException](DialectCompiler.compile(duplicate))
    }

    @TestCase
    func richLiteralContainersNeverExportReferenceDefinitions(): Unit {
        for (math in [false, true]) {
            let builder = MarkdownDialect.define("literal-references", "2")
            if (math) {
                OfficialExtensions.math(builder)
            } else {
                OfficialExtensions.codeGroups(builder)
            }
            let engine = MarkdownEngine.builder().dialect(builder.build()).build()
            let body = if (math) {
                "$$\n\n[id]: /wrong\n$$"
            } else {
                ":::code-group\n```text\n\n[id]: /wrong\n```\n:::"
            }
            let input = "[x][id]\n\n" + body + "\n\n[id]: /right\n"
            let result = engine.parse(input)
            @Expect(result.document.references.size, 1)
            @Expect(result.document.references[0].destination, "/right")
            @Expect(engine.htmlRenderer().render(result.document).contains("href=\"/right\""), true)
            expectAppendEquivalent(engine, appendByWidths(engine, input.toArray(), [1]), result)
        }
        let engine = codeGroupTestEngine()
        let bound = engine.parse(":::code-group\n```text\nx\n```\n:::\n").document
        let unbound = AstArenaBuilder(bound).freeze(bound.root().index)
        @ExpectThrows[MarkdownException](engine.htmlRenderer().render(unbound))
        @ExpectThrows[MarkdownException](PlainTextRenderer().render(unbound))
        @ExpectThrows[MarkdownException](CanonicalMarkdownRenderer().render(unbound))
        let transformed = TreeRewriter.rewrite(bound, {
            node => if (node.asCodeBlock().isSome()) {
                RewriteAction.DetachLiteral
            } else {
                RewriteAction.Keep
            }
        })
        @Expect(engine.htmlRenderer().render(transformed), engine.htmlRenderer().render(bound))
    }

    @TestCase
    func codeGroupsComposeInsideBoundFootnotesAndDefinitionBodies(): Unit {
        let builder = OfficialExtensions.headingIds(
            OfficialExtensions.math(
                OfficialExtensions.definitionLists(
                    OfficialExtensions.footnotes(
                        OfficialExtensions.codeGroups(MarkdownDialect.define("bound-groups", "2"))))))
        let engine = MarkdownEngine.builder().dialect(builder.build()).build()
        let source = "# Code {#code}\n\nref[^n]\n\n[^n]: $x$.\n\n    :::code-group\n    ```cj title=\"footnote\"\n    [fake]: /hidden\n    ```\n    :::\n\nTerm\n: :::code-group\n  ~~~text title=\"definition\"\n  [^fake]\n  ~~~\n  :::\n"
        let result = engine.parse(source)
        @Expect(result.document.references.size, 0)
        @Expect(result.document.bindings.footnotes.size, 1)
        @Expect(result.diagnostics.size, 0)
        let html = engine.htmlRenderer().render(result.document)
        @Expect(html.contains("<figcaption>footnote</figcaption>"), true)
        @Expect(html.contains("<figcaption>definition</figcaption>"), true)
        let canonical = CanonicalMarkdownRenderer().render(result.document)
        @Expect(engine.htmlRenderer().render(engine.parse(canonical).document), html)
        for (widths in [[1], [7, 2, 19], [source.size]]) {
            expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), result)
        }
    }

    @TestCase
    func interactiveDataPreservesCopyBytesWithoutLoadingScriptsOrChangingParserIdentity(): Unit {
        let engine = codeGroupTestEngine()
        let source = ":::code-group\r\n```text title=\"示例😀\" {1}\r\n中😀\r\n```\r\n:::\r\n"
        let document = engine.parse(source).document
        let options = CodeGroupHtmlOptions(interactive: true, groupLabel: "代码示例", copyLabel: "复制代码",
            copiedLabel: "已复制", copyFailedLabel: "复制失败", copyUnavailableLabel: "不可复制")
        let renderer = engine.htmlRenderer(codeGroups: options)
        let expected = renderer.render(document)
        @Expect(expected.contains("data-code-copy-hex=\"e4b8adf09f98800d0a\""), true)
        @Expect(expected.contains("aria-label=\"代码示例\""), true)
        @Expect(expected.contains("<script"), false)
        @Expect(expected.contains("hidden"), false)
        @Expect(expected.contains("role=\"tab\""), false)
        let output = renderer.newOutputSession(document, chunkBytes: 4)
        let sink = CodeGroupOutputSink()
        var complete = false
        while (!complete) {
            match (output.resume(sink)) {
                case AsyncRenderState.Complete => complete = true
                case AsyncRenderState.Paused => ()
                case AsyncRenderState.Failed(error) => throw error
            }
        }
        @Expect(sink.text.toString(), expected)
        let limited = engine
            .htmlRenderer(codeGroups: CodeGroupHtmlOptions(interactive: true, maximumCopyBytes: 1))
            .render(document)
        @Expect(limited.contains("data-copy-unavailable=\"size\""), true)
        @Expect(limited.contains("data-code-copy-hex="), false)
        @Expect(limited.contains("中😀"), true)
        @Expect(renderer.fingerprint() == engine.htmlRenderer().fingerprint(), false)
        @Expect(engine.htmlRenderer(codeGroups: CodeGroupHtmlOptions(copyLabel: "unused")).fingerprint(),
            engine.htmlRenderer().fingerprint())
        @ExpectThrows[IllegalArgumentException](CodeGroupHtmlOptions(copyLabel: ""))
        @ExpectThrows[IllegalArgumentException](CodeGroupHtmlOptions(maximumCopyBytes: 4194305))
        @ExpectThrows[MarkdownException](HtmlRenderer(codeGroups: options, maximumOutputBytes: Some(100)).render(document))
    }

    @TestCase
    func canonicalConsumesTypedMetadataAndDeletionKeepsStableUntitledLabels(): Unit {
        let engine = codeGroupTestEngine()
        let input = ":::code-group\n```js title=\"old\"\nx\n```\n:::\n"
        let codeStart = ":::code-group\n".size
        let closeStart = codeStart + "```js title=\"old\"\n".size + "x\n".size
        let codeSpan = SourceSpan(codeStart, closeStart + 3)
        for (title in ["changed \" quote", "path \\ end", "new `title`"]) {
            let source = SourceBuffer(input)
            let nodes = ParserNodeFactory(100, source: Some(source))
            let code = nodes.codeBlock(CodeBlockKind.Fenced, LiteralStorage.Copy("x\n"), codeSpan,
                fenceCharacter: Some(b'`'), fenceLength: 3, openingFenceSpan: Some(SourceSpan(codeStart, codeStart + 3)),
                closingFenceSpan: Some(SourceSpan(closeStart, closeStart + 3)), infoRaw: "js title=\"old\"",
                language: "js")
            let item = nodes.customBlock("code-groups", "1.0.0", "code-group-item",
                CodeGroupPayload(CodeGroupRole.Item, title: title, highlightedLines: [CodeLineRange(1, 1)],
                    copyText: "x\n"), [code], Some(codeSpan),
                NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(codeSpan),
                    extensionId: Some("code-groups")))
            let group = nodes.customBlock("code-groups", "1.0.0", "code-group", CodeGroupPayload(CodeGroupRole.Group),
                [item], Some(SourceSpan(0, input.size)),
                NodeOrigin(NodeOriginKind.ExtensionGenerated, sourceSpan: Some(SourceSpan(0, input.size)),
                    extensionId: Some("code-groups")))
            let raw = nodes.finishDocument([group], SourceSpan(0, input.size), engine.profile,
                engine.dialect.fingerprint, [])
            let document = DocumentBinder.bind(raw, BindingOptions(), engine.limits, OperationBudget.safe(),
                CancellationToken.none())
            @Expect(document.root().children()[0].children()[0].children()[0].asCodeBlock().getOrThrow().infoRaw, "js title=\"old\"")
            let canonical = CanonicalMarkdownRenderer().render(document)
            let restored = engine.parse(canonical)
            @Expect(codeGroupPayload(restored.document.root().children()[0].children()[0]).getOrThrow().title, title)
            @Expect(engine.htmlRenderer().render(restored.document), engine.htmlRenderer().render(document))
            @Expect(CanonicalMarkdownRenderer().render(restored.document), canonical)
        }
        let original = engine.parse(":::code-group\n```\na\n```\n```\nb\n```\n:::\n").document
        let first = original.root().children()[0].children()[0].nodeId
        let removed = TreeRewriter.rewrite(original, {
            node => if (node.nodeId == first) {
                RewriteAction.Remove
            } else {
                RewriteAction.Keep
            }
        })
        @Expect(codeGroupPayload(removed.root().children()[0].children()[0]).getOrThrow().title, "text")
        let canonical = CanonicalMarkdownRenderer().render(removed)
        @Expect(engine.htmlRenderer().render(engine.parse(canonical).document), engine.htmlRenderer().render(removed))
    }

    @TestCase
    func manyNestedCloserLinesHaveLinearAppendWork(): Unit {
        let engine = codeGroupTestEngine()
        var previous: Int64 = 0
        for (count in [32, 64, 128]) {
            let input = StringBuilder()
            input.append(":::code-group\n```text\n")
            for (_ in 0..count) {
                input.append(":::\n")
            }
            input.append("```\n:::\n\n# stop\n")
            let source = input.toString()
            let budget = OperationBudget.safe()
            let session = engine.newAppendSession(budget: budget)
            let replica = AppendReplica()
            for (byte in source.toArray()) {
                replica.apply(session.feed([byte]))
            }
            replica.apply(session.finish())
            expectAppendEquivalent(engine, replica.result.getOrThrow(), engine.parse(source))
            if (previous > 0) {
                @Expect(budget.usedScanSteps() < previous * 3, true)
            }
            previous = budget.usedScanSteps()
        }
    }
}
