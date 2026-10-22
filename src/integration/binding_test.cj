package markdown.integration

import markdown.artifact.{BinaryArtifactCodec, BinaryArtifactLoadResult, MarkdownParseArtifact}
import markdown.core.{AstInvariantValidator, AstQuery, BindingOptions, CancellationSource, CustomPayload, 
    FootnoteDefinitionPayload, FootnoteReferencePayload, LimitExceededException, MarkdownErrorCode, MarkdownException, 
    MarkdownProfile, NodeKind, OperationBudget, ParseLimits, ParseOutcome, SourceSpan, Utf8Policy}
import markdown.editor.{DocumentSnapshot, MarkdownLinter}
import markdown.engine.MarkdownEngine
import markdown.extensions.{BlockSyntax, DialectParserOptions, ExtensionManifest, InlinePayloadEmitter, InlineSyntax, 
    InlineSyntaxMatch, MarkdownDialect, OfficialExtensions}
import markdown.render.{CanonicalMarkdownRenderer, HtmlRenderer, PlainTextRenderer}
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

private func footnoteTestEngine(options!: BindingOptions = BindingOptions()): MarkdownEngine {
    let dialect = OfficialExtensions.footnotes(MarkdownDialect.define("notes", "2")).build()
    MarkdownEngine.builder().dialect(dialect).bindingOptions(options).build()
}

private class InvalidFootnoteSourceEmitter <: InlinePayloadEmitter {
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        FootnoteReferencePayload(value.rawLiteral, SourceSpan(0, 1))
    }
}

@Test
class DocumentBindingTests {
    @TestCase
    func semanticPayloadCannotClaimUnrelatedSourceAndDefinitionBytesAreBounded(): Unit {
        let invalid = MarkdownDialect
            .define("invalid-note", "1")
            .enable(ExtensionManifest("invalid-note", "1.0.0", "1"))
            .inline(
                InlineSyntax
                    .define("invalid-note", "note")
                    .delimiter("!")
                    .content(false)
                    .emitContent(false)
                    .emit(InvalidFootnoteSourceEmitter()))
            .build()
        let engine = MarkdownEngine.builder().dialect(invalid).build()
        match (engine.tryParse("!x!")) {
            case ParseOutcome.Failure(error) => @Expect(error.phase, "bind")
            case _ => @Expect(false)
        }
        let small = OfficialExtensions.footnotes(MarkdownDialect.define("small-notes", "2"))
        // Replace the official definition declaration in a separate manifest
        // so the configured body bound is exercised through the public DSL.
        let bounded = MarkdownDialect
            .define("bounded-note", "2")
            .enable(ExtensionManifest("footnotes", "2.0.0", "2"))
            .block(BlockSyntax.define("footnotes", "footnote-definition").footnoteDefinition().maximumBlockBytes(8))
            .build()
        @ExpectThrows[LimitExceededException](MarkdownEngine.builder().dialect(bounded).build()
            .parse("[^a]: long body"))
        let cancelled = CancellationSource()
        cancelled.cancel()
        @ExpectThrows[MarkdownException](MarkdownEngine.builder().dialect(small.build()).build()
            .parse("x[^a]\n\n[^a]: y", cancellation: cancelled.token))
    }

    @TestCase
    func escapedLabelsAndUnclosedReferencesUseBoundedDeclaredScanning(): Unit {
        let engine = footnoteTestEngine()
        let result = engine.parse("x[^a\\]b]\n\n[^a\\]b]: y")
        @Expect(result.document.bindings.footnotes.size, 1)
        let node = AstQuery
            .byNodeId(result.document, result.document.bindings.footnotes[0].references[0].reference)
            .getOrThrow()
        match (node.asCustomInline().getOrThrow().payload) {
            case value: FootnoteReferencePayload =>
                @Expect(value.labelRaw, "a\\]b")
                @Expect(value.labelNormalized, "a]b")
            case _ => @Expect(false)
        }
        @Expect(HtmlRenderer().render(engine.parse(CanonicalMarkdownRenderer().render(result.document)).document),
            HtmlRenderer().render(result.document))
        let first = StringBuilder()
        for (_ in 0..1000) {
            first.append("[^unclosed\n")
        }
        let budget = OperationBudget.safe()
        let largerBudget = OperationBudget.safe()
        let _ = engine.parse(first.toString(), budget: budget)
        let _ = engine.parse(first.toString() + first.toString(), budget: largerBudget)
        @Expect(largerBudget.usedScanSteps() > budget.usedScanSteps(), true)
        @Expect(largerBudget.usedScanSteps() <= 3 * budget.usedScanSteps(), true)
    }

    @TestCase
    func ordinaryReferencesInsideFootnotesUseSharedBlockBoundariesAndFirstDefinitionOrder(): Unit {
        let engine = footnoteTestEngine()
        let source = "[outer][target] note[^n]\n\n[^n]: [inside][target]\n\n    [target]: /first \"title\"\n\n    ```\n\n    [fake]: /wrong\n    ```\n\n    > [quoted]: /quote\n\n[target]: /second\n\n[fake] [quoted]\n"
        let result = engine.parse(source)
        @Expect(result.document.references.size, 3)
        @Expect(result.document.references[0].destination, "/first")
        @Expect(result.document.references[0].isEffective, true)
        @Expect(result.source.slice(result.document.references[0].sourceSpan), "[target]: /first \"title\"")
        @Expect(result.document.references[2].isEffective, false)
        let links = AstQuery.links(result.document)
        @Expect(links.size, 3)
        @Expect(links[0].destination, "/first")
        @Expect(links[1].destination, "/first")
        @Expect(links[2].destination, "/quote")
        let html = HtmlRenderer().render(result.document)
        @Expect(html.contains("[fake]"), true)
        @Expect(html.contains("href=\"/wrong\""), false)
        @Expect(HtmlRenderer().render(engine.parse(CanonicalMarkdownRenderer().render(result.document)).document), html)
        @Expect(DocumentSnapshot.parse(engine, source).syntaxTree.losslessText(), source)
    }

    @TestCase
    func postDefinedFootnotesShareNumberingTargetsBacklinksAndSourceAcrossOutputs(): Unit {
        let source = "first[^ B ], again[^b], then[^a].\n\n[^a]: later number\n\n[^b]: first number\n\n[^unused]: hidden\n"
        let engine = footnoteTestEngine(options: BindingOptions(idScope: "chapter-a"))
        let result = engine.parse(source)
        let notes = result.document.bindings.footnotes
        @Expect(notes.size, 2)
        @Expect(notes[0].number, 1)
        @Expect(notes[0].references.size, 2)
        @Expect(notes[1].number, 2)
        @Expect(notes[1].references.size, 1)
        let ids = HashSet<String>()
        let html = engine.htmlRenderer().renderWithSourceMap(result.document)
        for (note in notes.toArray()) {
            @Expect(ids.add(note.definitionId), true)
            @Expect(html.content.contains("id=\"${note.definitionId}\""), true)
            for (reference in note.references.toArray()) {
                @Expect(reference.definition, note.definition)
                @Expect(ids.add(reference.referenceId), true)
                @Expect(html.content.contains("href=\"#${reference.definitionId}\""), true)
                @Expect(html.content.contains("href=\"#${reference.referenceId}\""), true)
                let node = AstQuery.byNodeId(result.document, reference.reference).getOrThrow()
                let ranges = html.outputRanges(reference.reference)
                @Expect(ranges.size > 0, true)
                @Expect(html.sourceSpanAt(ranges[0].startByte), node.span)
            }
        }
        @Expect(html.content.contains("hidden"), false)
        @Expect(PlainTextRenderer().render(result.document).contains("first[1], again[1], then[2]"), true)
        let markdown = CanonicalMarkdownRenderer().render(result.document)
        @Expect(markdown.contains("[^unused]: hidden"), true)
        @Expect(engine.htmlRenderer().render(engine.parse(markdown).document), html.content)
        for (node in AstQuery.customNodes(result.document)) {
            match (node.kind) {
                case NodeKind.CustomInline => match (node.asCustomInline().getOrThrow().payload) {
                    case payload: FootnoteReferencePayload => @Expect(result.source.slice(payload.labelSpan), payload.labelRaw)
                    case _ => @Expect(false)
                }
                case NodeKind.CustomBlock => match (node.asCustomBlock().getOrThrow().payload) {
                    case payload: FootnoteDefinitionPayload => @Expect(result.source.slice(payload.labelSpan), payload.labelRaw)
                    case _ => @Expect(false)
                }
                case _ => @Expect(false)
            }
        }
        let snapshot = DocumentSnapshot.parse(engine, source)
        @Expect(snapshot.syntaxTree.losslessText(), source)
        let restored = BinaryArtifactCodec.read(engine, BinaryArtifactCodec.encode(snapshot).bytes())
        @Expect(engine.htmlRenderer().render(restored.result.document), html.content)
    }

    @TestCase
    func undefinedDuplicateUnusedAndCodeSyntaxHaveExplicitIndependentBehavior(): Unit {
        let engine = footnoteTestEngine()
        let source = "[^missing] [^n]\n\n[^n]: first\n\n[^n]: duplicate\n\n[^unused]: not shown\n\n```\n[^fake]: code\n```\n\n`[^fake]`"
        let result = engine.parse(source)
        @Expect(result.document.bindings.footnotes.size, 1)
        @Expect(result.diagnostics.size, 2)
        let html = HtmlRenderer().render(result.document)
        @Expect(html.contains("[^missing]"), true)
        @Expect(html.contains("<p>first</p>"), true)
        @Expect(html.contains("duplicate"), false)
        @Expect(html.contains("not shown"), false)
        @Expect(html.contains("[^fake]: code"), true)
        @Expect(html.contains("<code>[^fake]</code>"), true)
        @Expect(engine.parse("[^n]").document.bindings.footnotes.size, 0)
        let invalid = engine.parse("[^&#32;]: visible")
        @Expect(invalid.document.bindings.footnotes.size, 0)
        @Expect(invalid.diagnostics[0].code, "MD4003_INVALID_FOOTNOTE")
        @Expect(PlainTextRenderer().render(invalid.document), "[^&#32;]: visible")
        @Expect(MarkdownLinter(engine).lint(DocumentSnapshot.parse(engine, source)).size >= result.diagnostics.size, true)
        let strict = footnoteTestEngine(options: BindingOptions(strictUndefinedFootnotes: true))
        match (strict.tryParse("[^missing]")) {
            case ParseOutcome.Failure(error) =>
                @Expect(if (let MarkdownErrorCode.InvalidReference <- error.code) { true } else { false })
                @Expect(error.phase, "bind")
            case ParseOutcome.Success(_) => @Expect(false)
        }
    }

    @TestCase
    func nestedReachableFootnotesAndCyclesAreBoundedAndKeepNormalBlockContent(): Unit {
        let source = "body[^a]\n\n[^a]: first **bold** [ok](guide.md)\n\n    next[^b]\n\n    - item\n\n    > quoted\n\n    ```txt\n    code[^fake]\n    ```\n\n[^b]: child[^a]\n"
        let engine = footnoteTestEngine()
        let result = engine.parse(source)
        AstInvariantValidator().validate(result.document)
        let notes = result.document.bindings.footnotes
        @Expect(notes.size, 2)
        @Expect(notes[0].references.size, 2)
        @Expect(notes[1].references.size, 1)
        @Expect(result.diagnostics.size, 0)
        let html = HtmlRenderer().render(result.document)
        @Expect(html.contains("<strong>bold</strong>"), true)
        @Expect(html.contains("href=\"guide.md\""), true)
        @Expect(html.contains("<ul>"), true)
        @Expect(html.contains("<blockquote>"), true)
        @Expect(html.contains("code[^fake]"), true)
        let markdown = CanonicalMarkdownRenderer().render(result.document)
        @Expect(HtmlRenderer().render(engine.parse(markdown).document), html)
    }

    @TestCase
    func fragmentScopesAndCacheIdentityKeepIndependentPreparedDocumentsSeparate(): Unit {
        let first = footnoteTestEngine(options: BindingOptions(idScope: "first"))
        let second = footnoteTestEngine(options: BindingOptions(idScope: "second"))
        let source = "x[^a]\n\n[^a]: y"
        let snapshot = DocumentSnapshot.parse(first, source)
        let other = second.parse(source)
        @Expect(snapshot.result.document.bindings.footnotes[0].definitionId == other.document.bindings.footnotes[0].definitionId, false)
        match (BinaryArtifactCodec.decode(second, BinaryArtifactCodec.encode(snapshot))) {
            case BinaryArtifactLoadResult.CacheMiss(_) => @Expect(true)
            case _ => @Expect(false)
        }
        @ExpectThrows[MarkdownException](MarkdownParseArtifact.create(second, snapshot.result))
        @ExpectThrows[IllegalArgumentException](BindingOptions(idScope: "invalid scope"))
    }

    @TestCase
    func gfmPipeNormalizationKeepsRawLabelsPositionsAndInlineMarkdownSemantics(): Unit {
        let dialect = OfficialExtensions
            .footnotes(MarkdownDialect.define("gfm-notes", "2").base(MarkdownProfile.gfmModernV1()))
            .build()
        let engine = MarkdownEngine.builder().dialect(dialect).build()
        let source = "| **H** |\r\n| --- |\r\n| [^a\\|b] and `x\\|y` |\r\n\r\n[^a|b]: 中文😀\r\n"
        let result = engine.parse(source)
        @Expect(result.diagnostics.size, 0)
        @Expect(result.document.bindings.footnotes.size, 1)
        let reference = result.document.bindings.footnotes[0].references[0]
        let node = AstQuery.byNodeId(result.document, reference.reference).getOrThrow()
        match (node.asCustomInline().getOrThrow().payload) {
            case value: FootnoteReferencePayload =>
                @Expect(value.labelRaw, "a\\|b")
                @Expect(value.labelNormalized, "a|b")
                @Expect(result.source.slice(value.labelSpan), "a\\|b")
            case _ => @Expect(false)
        }
        let html = HtmlRenderer().render(result.document)
        @Expect(html.contains("<strong>H</strong>"), true)
        @Expect(html.contains("<code>x|y</code>"), true)
        let markdown = CanonicalMarkdownRenderer().render(result.document)
        @Expect(HtmlRenderer().render(engine.parse(markdown).document), html)
        AstInvariantValidator().validate(result.document)
    }

    @TestCase
    func containerOffsetsAndUtf8ReplacementKeepExactLabelRanges(): Unit {
        let engine = footnoteTestEngine()
        let source = "> 中文[^q]\r\n>\r\n> [^q]: 😀 first\r\n>\r\n>     second\r\n"
        let result = engine.parse(source)
        @Expect(result.document.bindings.footnotes.size, 1)
        let note = result.document.bindings.footnotes[0]
        let reference = AstQuery.byNodeId(result.document, note.references[0].reference).getOrThrow()
        @Expect(result.source.slice(reference.span.getOrThrow()), "[^q]")
        let html = HtmlRenderer().render(result.document)
        @Expect(html.contains("😀 first"), true)
        @Expect(html.contains("<p>second</p>"), true)
        let replaced = engine.parse([b'[', b'^', 0xFF, b']'], utf8Policy: Utf8Policy.ReplaceInvalid)
        let refs = AstQuery.customNodes(replaced.document)
        @Expect(refs.size, 1)
        match (refs[0].asCustomInline().getOrThrow().payload) {
            case value: FootnoteReferencePayload =>
                @Expect(value.labelRaw, "�")
                @Expect(value.labelSpan, SourceSpan(2, 3))
                @Expect(replaced.source.slice(value.labelSpan), "�")
            case _ => @Expect(false)
        }
        @Expect(HtmlRenderer().render(replaced.document).contains("[^�]"), true)
    }

    @TestCase
    func referenceAndGeneratedAnchorWorkShareTheConfiguredBudget(): Unit {
        let base = ParseLimits.safe()
        let limits = ParseLimits(base.maximumInputBytes, base.maximumLineBytes, base.maximumNestingDepth,
            base.maximumAstNodes, 4, base.maximumTableColumns, base.maximumUrlBytes, base.maximumLiteralBytes,
            base.maximumOutputBytes, base.maximumExtensionCaptureBytes, base.maximumExtensionLookaheadBytes)
        let dialect = OfficialExtensions.footnotes(MarkdownDialect.define("bounded-notes", "2")).build()
        let engine = MarkdownEngine.builder().dialect(dialect).limits(limits).build()
        @ExpectThrows[LimitExceededException](engine.parse("x[^a]\n\n[^a]: y"))
        @Expect(footnoteTestEngine().parse("x[^a]\n\n[^a]: y").document.bindings.footnotes.size, 1)
    }

    @TestCase
    func disablingExtensionSyntaxPreservesStandardCaretReferenceLinks(): Unit {
        let builder = OfficialExtensions.footnotes(MarkdownDialect.define("disabled-notes", "2"))
        let engine = MarkdownEngine
            .builder()
            .dialect(builder.parserOptions(DialectParserOptions(extensionsEnabled: false)).build())
            .build()
        let source = "[^n]\n\n[^n]: /target"
        let result = engine.parse(source)
        @Expect(result.document.bindings.footnotes.size, 0)
        @Expect(AstQuery.customNodes(result.document).size, 0)
        @Expect(HtmlRenderer().render(result.document), MarkdownEngine.builder().build().renderHtml(source).html)
    }
}
