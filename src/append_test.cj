package markdown

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func appendTestEngine(): MarkdownEngine {
    MarkdownEngine
        .builder()
        .dialect(
            OfficialExtensions
                .headingIds(
                    OfficialExtensions.footnotes(
                        MarkdownDialect.define("append-test", "2").base(MarkdownProfile.gfmModernV1())))
                .build())
        .bindingOptions(BindingOptions(idScope: "part"))
        .build()
}

internal func expectAppendEquivalent(engine: MarkdownEngine, actual: ParseResult, expected: ParseResult): Unit {
    @Expect(actual.source.text(), expected.source.text())
    @Expect(actual.document.nodeCount, expected.document.nodeCount)
    @Expect(actual.document.references.size, expected.document.references.size)
    for (index in 0..actual.document.references.size) {
        let leftDefinition = actual.document.references[index]
        let rightDefinition = expected.document.references[index]
        @Expect(leftDefinition.labelRaw, rightDefinition.labelRaw)
        @Expect(leftDefinition.labelNormalized, rightDefinition.labelNormalized)
        @Expect(leftDefinition.destinationRaw, rightDefinition.destinationRaw)
        @Expect(leftDefinition.destination, rightDefinition.destination)
        @Expect(leftDefinition.titleRaw, rightDefinition.titleRaw)
        @Expect(leftDefinition.title, rightDefinition.title)
        @Expect(leftDefinition.sourceSpan, rightDefinition.sourceSpan)
        @Expect(leftDefinition.isEffective, rightDefinition.isEffective)
        @Expect(leftDefinition.shadowedBy, rightDefinition.shadowedBy)
    }
    let left = engine.htmlRenderer().renderWithSourceMap(actual.document)
    let right = engine.htmlRenderer().renderWithSourceMap(expected.document)
    @Expect(left.content, right.content)
    @Expect(left.sourceMap.size, right.sourceMap.size)
    for (index in 0..left.sourceMap.size) {
        @Expect(left.sourceMap[index].sourceSpan, right.sourceMap[index].sourceSpan)
        @Expect(left.sourceMap[index].outputRange, right.sourceMap[index].outputRange)
        @Expect(left.sourceMap[index].generated, right.sourceMap[index].generated)
    }
    @Expect(PlainTextRenderer().render(actual.document), PlainTextRenderer().render(expected.document))
    let markdown = CanonicalMarkdownRenderer(extensionRules: engine.dialect.rendererRules.toArray())
    @Expect(markdown.render(actual.document), markdown.render(expected.document))
    @Expect(actual.diagnostics.size, expected.diagnostics.size)
    for (index in 0..actual.diagnostics.size) {
        @Expect(actual.diagnostics[index].code, expected.diagnostics[index].code)
        @Expect(actual.diagnostics[index].span, expected.diagnostics[index].span)
        @Expect(actual.diagnostics[index].relatedSpans, expected.diagnostics[index].relatedSpans)
    }
    if (actual.source.hasIdentityMapping()) {
        let snapshot = DocumentSnapshot(engine, 1, actual)
        let leftBytes = BinaryArtifactCodec.encode(snapshot).bytes()
        let rightBytes = BinaryArtifactCodec.encode(DocumentSnapshot(engine, 1, expected)).bytes()
        @Expect(leftBytes.size, rightBytes.size)
        for (index in 0..leftBytes.size) {
            @Expect(leftBytes[index], rightBytes[index])
        }
        let restored = BinaryArtifactCodec.read(engine, leftBytes)
        @Expect(engine.htmlRenderer().render(restored.result.document), left.content)
        @Expect(snapshot.syntaxTree.losslessText(), actual.source.text())
    }
}

internal func appendByWidths(engine: MarkdownEngine, bytes: Array<Byte>, widths: Array<Int64>,
    policy!: Utf8Policy = Utf8Policy.Strict): ParseResult {
    let session = engine.newAppendSession(utf8Policy: policy)
    let replica = AppendReplica()
    var offset: Int64 = 0
    var index: Int64 = 0
    while (offset < bytes.size) {
        let end = min(bytes.size, offset + widths[index % widths.size])
        replica.apply(session.feed(bytes[offset..end]))
        offset = end
        index++
    }
    let final = session.finish()
    match (final.state) {
        case AppendState.Complete => ()
        case AppendState.Failed(error) => throw error
        case _ => @Expect(false)
    }
    replica.apply(final)
    let result = replica.result.getOrThrow()
    @Expect(replica.blocks().size, result.document.root().children().size)
    for (index in 0..replica.blocks().size) {
        @Expect(replica.blocks()[index].node.nodeId, result.document.root().children()[index].nodeId)
        @Expect(replica.blocks()[index].finalSemantics, true)
    }
    result
}

@Test
class AppendSessionTests {
    @TestCase
    func feedDeliversClosedDraftsAndFinishBindsForwardDependencies(): Unit {
        let engine = appendTestEngine()
        let session = engine.newAppendSession()
        let replica = AppendReplica()
        let first = session.feed("# First\n\n[late][id] and [^n].\n\n")
        @Expect(first.changes.size >= 1, true)
        @Expect(first.progress.inputBytes, "# First\n\n[late][id] and [^n].\n\n".size)
        replica.apply(first)
        @Expect(replica.result.isNone(), true)
        @Expect(replica.blocks()[0].finalSemantics, false)
        let firstId = replica.blocks()[0].node.nodeId
        let tail = "[^n]: 中文 **note**.\n\n    > continued\n\n[id]: /target\n\n## Last {#last}\n"
        replica.apply(session.feed(tail))
        let final = session.finish()
        replica.apply(final)
        let result = replica.result.getOrThrow()
        @Expect(result.document.root().children()[0].nodeId, firstId)
        @Expect(result.document.bindings.footnotes.size, 1)
        expectAppendEquivalent(engine, result, engine.parse("# First\n\n[late][id] and [^n].\n\n" + tail))
        @ExpectThrows[IllegalStateException](session.finish())
        @ExpectThrows[IllegalStateException](session.feed("later"))
    }

    @TestCase
    func arbitraryChunksKeepUtf8CrLfContainersTablesAndScopesExact(): Unit {
        let engine = appendTestEngine()
        let inputs = ["\u{FEFF}# 中文😀 {#显式}\r\n\r\n> **a**\r\n> b\r\n> ---\r\n\r\n",
            "| **H** | x |\r\n| --- | --- |\r\n| [^a\\|b] | [late][id] |\r\n\r\n[^a\\|b]: note\r\n\r\n[id]: /中文\r\n",
            "- one\n\n  two [id]\n\n- three\n\n```cj\n😀\n```\n\n[id]: /ok\n", "[id]\n\n[id]: /first\n\n[id]: /second\n",
            "`````\n\n```\naaa\n", ""]
        for (text in inputs) {
            let expected = engine.parse(text)
            for (widths in [[1], [7], [1, 13, 2, 5, 3, 19], [max(1, text.size)]]) {
                expectAppendEquivalent(engine, appendByWidths(engine, text.toArray(), widths), expected)
            }
        }
    }

    @TestCase
    func replicaRejectsMissingRepeatedAndCrossSessionBatchesWithoutMutation(): Unit {
        let engine = MarkdownEngine.builder().build()
        let session = engine.newAppendSession()
        let first = session.feed("first\n\n")
        let second = session.feed("second\n\n")
        let replica = AppendReplica()
        @ExpectThrows[IllegalArgumentException](replica.apply(second))
        @Expect(replica.version, 0)
        replica.apply(first)
        let saved = replica.blocks()
        @ExpectThrows[IllegalArgumentException](replica.apply(first))
        @Expect(replica.version, 1)
        @Expect(replica.blocks().size, saved.size)
        @ExpectThrows[IllegalArgumentException](replica.apply(engine.newAppendSession().feed("foreign")))
        @Expect(replica.version, 1)
        replica.apply(second)
        let final = session.finish()
        replica.apply(final)
        @ExpectThrows[IllegalArgumentException](replica.apply(final))
        @Expect(replica.result.isSome(), true)
    }

    @TestCase
    func utf8ErrorsCancellationAndBudgetFailuresAreTerminalWithoutSuccess(): Unit {
        let engine = MarkdownEngine.builder().build()
        let bytes = [UInt8(0xF0), UInt8(0x9F), UInt8(0x98)]
        let strict = engine.newAppendSession()
        let replica = AppendReplica()
        replica.apply(strict.feed(bytes))
        let bad = strict.finish()
        match (bad.state) {
            case AppendState.Failed(error) =>
                if (let MarkdownErrorCode.InvalidEncoding <- error.code) {
                    @Expect(true)
                } else {
                    @Expect(false)
                }
            case _ => @Expect(false)
        }
        replica.apply(bad)
        @Expect(replica.result.isNone(), true)
        @ExpectThrows[IllegalStateException](strict.feed("x"))
        let invalid = [b'a', UInt8(0xFF), b'\n', b'\n', b'b', UInt8(0xE2)]
        for (widths in [[1], [2, 3], [invalid.size]]) {
            expectAppendEquivalent(engine, appendByWidths(engine, invalid, widths, policy: Utf8Policy.ReplaceInvalid),
                engine.parse(invalid, utf8Policy: Utf8Policy.ReplaceInvalid))
        }
        let cancellation = CancellationSource()
        let cancelled = engine.newAppendSession(cancellation: cancellation.token)
        let _ = cancelled.feed("prefix")
        cancellation.cancel()
        if (let AppendState.Failed(error) <- cancelled.finish().state) {
            if (let MarkdownErrorCode.Cancelled <- error.code) {
                @Expect(true)
            } else {
                @Expect(false)
            }
        } else {
            @Expect(false)
        }
        @ExpectThrows[IllegalStateException](cancelled.finish())
        let bounded = engine.newAppendSession(budget: OperationBudget(0, 0, 0, 0, 0, 0))
        if (let AppendState.Failed(_) <- bounded.feed("x").state) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        @ExpectThrows[IllegalStateException](bounded.finish())
    }

    @TestCase
    func limitsAreCumulativeAndPendingIsIndependentOfCallerChunkSize(): Unit {
        let engine = MarkdownEngine.builder().build()
        for (width in [1, 5, 20]) {
            let session = engine.newAppendSession(limits: AppendLimits(maximumPendingBytes: 4))
            let bytes = "abcde".toArray()
            var offset: Int64 = 0
            var stopped = false
            while (offset < bytes.size && !stopped) {
                let end = min(bytes.size, offset + width)
                if (let AppendState.Failed(error) <- session.feed(bytes[offset..end]).state) {
                    let limit = error as LimitExceededException
                    @Expect(limit.getOrThrow().limitKind, "pending_bytes")
                    @Expect(limit.getOrThrow().observedValue, 5)
                    stopped = true
                }
                offset = end
            }
            @Expect(stopped, true)
        }
        let retained = engine.newAppendSession(limits: AppendLimits(maximumRetainedInputBytes: 8))
        let _ = retained.feed("a\n\n")
        let _ = retained.feed("b\n\n")
        if (let AppendState.Failed(error) <- retained.feed("c\n\n").state) {
            @Expect((error as LimitExceededException).getOrThrow().limitKind, "retained_input_bytes")
        } else {
            @Expect(false)
        }
        let batches = engine.newAppendSession(limits: AppendLimits(maximumUpdateBatches: 2))
        let _ = batches.feed("")
        let last = batches.feed("")
        @Expect(last.sequence, 2)
        if (let AppendState.Failed(_) <- last.state) {
            @Expect(true)
        } else {
            @Expect(false)
        }
        let nodes = engine.newAppendSession(limits: AppendLimits(maximumNodeConstructionSteps: 1))
        let _ = nodes.feed("text\n\n")
        @ExpectThrows[IllegalStateException](nodes.finish())
        let patches = engine.newAppendSession(limits: AppendLimits(maximumPatchSteps: 1))
        let _ = patches.feed("one\n\n")
        if (let AppendState.Failed(_) <- patches.finish().state) {
            @Expect(true)
        } else {
            @Expect(false)
        }
    }
}

internal func verifyAppendStandardCases(cases: Array<(MarkdownProfile, String)>): Unit {
    for ((profile, text) in cases) {
        let engine = MarkdownEngine.builder().profile(profile).build()
        let expected = engine.parse(text)
        let lineWidths = ArrayList<Int64>()
        var start: Int64 = 0
        let bytes = text.toArray()
        for (index in 0..bytes.size) {
            if (bytes[index] == b'\n') {
                lineWidths.add(index + 1 - start);
                start = index + 1
            }
        }
        if (start < bytes.size) {
            lineWidths.add(bytes.size - start)
        }
        if (lineWidths.isEmpty()) {
            lineWidths.add(1)
        }
        let randomWidths = ArrayList<Int64>()
        var randomState = text.size + 20261018
        for (_ in 0..32) {
            randomState = (randomState * 1103515245 + 12345) % 2147483647
            randomWidths.add(1 + randomState % 31)
        }
        for (widths in [[1], [7], [1, 17, 4, 2, 9], [max(1, bytes.size)], lineWidths.toArray(), randomWidths.toArray()]) {
            expectAppendEquivalent(engine, appendByWidths(engine, bytes, widths), expected)
        }
    }
}

private class AppendDropHeadings <: ExtensionDocumentProcessor {
    public prop extensionId: String {
        get() {
            "append-transform"
        }
    }
    public prop processorId: String {
        get() {
            "drop-headings"
        }
    }
    public prop version: String {
        get() {
            "1"
        }
    }
    public prop phase: ExtensionProcessingPhase {
        get() {
            ExtensionProcessingPhase.AstTransform
        }
    }
    public prop priority: Int64 {
        get() {
            100
        }
    }
    public prop deterministic: Bool {
        get() {
            true
        }
    }
    public func process(document: Document, budget: OperationBudget, cancellation: CancellationToken): Document {
        TreeRewriter.rewrite(document, {
            node => match (node.kind) {
                case NodeKind.Heading => RewriteAction.Remove
                case _ => RewriteAction.Keep
            }
        }, budget: budget, cancellation: cancellation)
    }
}

@Test
class AppendRevisionAndWorkTests {
    @TestCase
    func finalProcessorRevisionsUseOldTargetsAndRemoveDiscardedRoots(): Unit {
        let engine = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("append-transform", "1")
                    .enable(
                        ExtensionManifest("append-transform", "1.0.0", "1",
                            capabilities: ExtensionCapabilities(transform: true)))
                    .documentProcessor(AppendDropHeadings())
                    .build())
            .build()
        let source = "# drop\n\none\n\ntwo\n\n"
        let session = engine.newAppendSession()
        let replica = AppendReplica()
        replica.apply(session.feed(source))
        @Expect(replica.blocks().size, 3)
        let final = session.finish()
        var removals: Int64 = 0
        for (change in final.changes.toArray()) {
            if (let AppendChange.Remove(_) <- change) {
                removals++
            }
        }
        @Expect(removals, 1)
        replica.apply(final)
        expectAppendEquivalent(engine, replica.result.getOrThrow(), engine.parse(source))
    }

    @TestCase
    func arbitraryByteFuzzPreservesReplacementMappingsAndTerminalEncodingFailures(): Unit {
        let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfmModernV1()).build()
        var state: Int64 = 20261018
        for (caseIndex in 0..256) {
            let bytes = Array<Byte>(caseIndex % 192, repeat: 0)
            for (index in 0..bytes.size) {
                state = (state * 1103515245 + 12345) % 2147483647
                bytes[index] = UInt8(state % 256)
            }
            let expected = engine.parse(bytes, utf8Policy: Utf8Policy.ReplaceInvalid)
            for (widths in [[1], [1, 11, 3], [max(1, bytes.size)]]) {
                expectAppendEquivalent(engine, appendByWidths(engine, bytes, widths, policy: Utf8Policy.ReplaceInvalid),
                    expected)
            }
            let session = engine.newAppendSession()
            var failed = false
            var index: Int64 = 0
            while (index < bytes.size && !failed) {
                if (let AppendState.Failed(_) <- session.feed(bytes[index..index + 1]).state) {
                    failed = true
                }
                index++
            }
            if (!failed && let AppendState.Failed(_) <- session.finish().state) {
                failed = true
            }
            var batchFailed = false
            try {
                let _ = engine.parse(bytes)
            } catch (_: MarkdownException) {
                batchFailed = true
            }
            @Expect(failed, batchFailed)
        }
    }

    @TestCase
    func officialLiteralExtensionsAndFatalFragmentRangesUseDocumentCoordinates(): Unit {
        let engine = MarkdownEngine.builder().dialect(OfficialExtensions.p1Dialect()).build()
        for (source in ["\u{FEFF}---\r\nx: y\r\n---\r\n\r\n# Title {#id}\r\n\r\n[^n] ... -- ---\r\n\r\n[^n]: body\r\n",
            "text\n\n---\nx: y\n---", "---\nunclosed", "a\n\n$$\nx^2\n"]) {
            for (widths in [[1], [3, 11, 2], [source.size]]) {
                expectAppendEquivalent(engine, appendByWidths(engine, source.toArray(), widths), engine.parse(source))
            }
        }
        let bounded = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("append-bounded-note", "2")
                    .enable(ExtensionManifest("footnotes", "2.0.0", "2"))
                    .block(
                        BlockSyntax.define("footnotes", "footnote-definition").footnoteDefinition().maximumBlockBytes(4))
                    .build())
            .build()
        let source = "before\n\n[^n]: too long\n"
        let session = bounded.newAppendSession()
        let early = session.feed(source)
        let final = if (let AppendState.Failed(_) <- early.state) {
            early
        } else {
            session.finish()
        }
        if (let AppendState.Failed(error) <- final.state) {
            @Expect(error.span.getOrThrow().startByte >= "before\n\n".size, true)
            @Expect((error as LimitExceededException).getOrThrow().extensionId, Some("footnotes"))
        } else {
            @Expect(false)
        }
    }

    @TestCase
    func constructionScanAndPatchWorkGrowLinearlyForLongPendingAndClosedBlocks(): Unit {
        let engine = MarkdownEngine.builder().build()
        for (shape in [0, 1, 2, 3]) {
            var previousScan: Int64 = 0
            var previousNodes: Int64 = 0
            for (count in [32, 64, 128]) {
                let text = StringBuilder()
                if (shape == 2) {
                    text.append("```text\n")
                }
                for (_ in 0..count) {
                    text.append(match (shape) {
                        case 0 => "- item\n\n  paragraph\n\n"
                        case 1 => "[later] pending 中文😀\n"
                        case 2 => "literal 中文😀\n"
                        case _ => "closed\n\n"
                    })
                }
                if (shape == 1) {
                    text.append("\n[later]: /target\n")
                }
                let source = text.toString()
                let bytes = source.toArray()
                let session = engine.newAppendSession()
                let replica = AppendReplica()
                var start: Int64 = 0
                for (index in 0..bytes.size) {
                    if (bytes[index] == b'\n') {
                        replica.apply(session.feed(bytes[start..index + 1]))
                        start = index + 1
                    }
                }
                if (start < bytes.size) {
                    replica.apply(session.feed(bytes[start..]))
                }
                let final = session.finish()
                replica.apply(final)
                let work = final.progress
                @Expect(work.scanSteps <= bytes.size * 64, true)
                @Expect(work.nodeConstructionSteps <= bytes.size * 4, true)
                @Expect(work.patchSteps <= count * 4 + 1, true)
                if (previousScan > 0) {
                    @Expect(work.scanSteps <= previousScan * 3, true)
                    @Expect(work.nodeConstructionSteps <= previousNodes * 3, true)
                }
                previousScan = work.scanSteps
                previousNodes = work.nodeConstructionSteps
                expectAppendEquivalent(engine, replica.result.getOrThrow(), engine.parse(source))
            }
        }
    }
}
