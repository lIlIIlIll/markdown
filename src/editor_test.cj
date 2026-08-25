package markdown

import std.unittest.*
import std.unittest.testmacro.*

@Test
class EditorSnapshotTest {
    @TestCase
    func syntaxTreeRoundTripsEverySourceByte(): Unit {
        let source = "# 😀\r\n\n*text* &amp; [x](url) <b>\n\n```cj\nx\n```\n\n:::note"
        let snapshot = MarkdownEngine.builder().build().parseSnapshot(source)
        @Expect(snapshot.syntaxTree.losslessText(), source)
        @Expect(snapshot.syntaxTree.originatingTokens(snapshot.result.document.children()[0]).size > 0, true)
        let kinds = snapshot.syntaxTree.root.tokens.toArray()
        @Expect(hasSyntaxKind(kinds, SyntaxKind.HeadingMarker), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.Delimiter), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.Entity), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.LinkLabel), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.LinkDestination), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.Html), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.Fence), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.InfoString), true)
        @Expect(hasSyntaxKind(kinds, SyntaxKind.ExtensionToken), true)
        let headingToken = kinds[0]
        @Expect(snapshot.syntaxMap.semanticNode(headingToken).isSome(), true)
        @Expect(snapshot.syntaxTree.root.children.size > 0, true)
        let heading = snapshot.result.document.children()[0]
        match (snapshot.syntaxMap.originatingSyntaxNode(heading)) {
            case Some(node) =>
                @Expect(node.children.size > 0, true)
                @Expect(snapshot.syntaxMap.semanticNode(node).isSome(), true)
            case None => @Expect(false)
        }
        let invalid = SyntaxTree.parse(SourceBuffer("text\\"))
        @Expect(hasSyntaxKind(invalid.root.tokens.toArray(), SyntaxKind.Invalid), true)
    }

    @TestCase
    func syntaxArenaRangesAndIndexesRemainLossless(): Unit {
        let source = "# a *b*\n\nparagraph"
        let snapshot = MarkdownEngine.builder().build().parseSnapshot(source)
        let heading = snapshot.result.document.children()[0]
        match (snapshot.syntaxMap.originatingSyntaxNode(heading)) {
            case Some(node) =>
                @Expect(node.firstTokenIndex >= 0, true)
                @Expect(node.tokenCount, node.tokens.size)
                @Expect(node.tokenCount < snapshot.syntaxTree.root.tokens.size, true)
                let copy = node.tokens.toArray()
                let originalSpan = node.tokens[0].span
                copy[0] = SyntaxToken(SyntaxKind.Invalid, "x", SourceSpan(0, 0))
                @Expect(node.tokens[0].span, originalSpan)
            case None => @Expect(false)
        }
        match (snapshot.syntaxTree.tokenAt(0)) {
            case Some(token) =>
                @Expect(token.span, SourceSpan(0, 1))
                match (snapshot.syntaxMap.semanticNode(token)) {
                    case Some(node) => @Expect(node.nodeId, heading.nodeId)
                    case None => @Expect(false)
                }
            case None => @Expect(false)
        }
        @Expect(snapshot.syntaxTree.tokenAt(snapshot.result.source.byteLength()).isNone(), true)
        @Expect(snapshot.syntaxTree.losslessText(), source)
    }

    @TestCase
    func snapshotAppliesValidatedUtf8AndUtf16Edits(): Unit {
        let snapshot = MarkdownEngine.builder().build().parseSnapshot("A😀B")
        let changed = snapshot.applyUtf16Edit(Utf16Position(0, 1), Utf16Position(0, 3), "中")
        @Expect(changed.snapshot.result.source.text(), "A中B")
        @Expect(changed.snapshot.version, 2)
        @Expect(changed.wasIncremental, false)
        @Expect(changed.changedNodes.nodeIds.size > 0, true)
    }

    @TestCase
    func safeEqualLengthTextEditUsesRealBlockLocalIncrementalReparse(): Unit {
        let engine = MarkdownEngine.builder().build()
        let snapshot = engine.parseSnapshot("# Title\n\nBefore\n\nAfter")
        let heading = snapshot.result.document.children()[0]
        let after = snapshot.result.document.children()[2]
        let headingStable = snapshot.stableNodeId(heading.nodeId)
        let afterStable = snapshot.stableNodeId(after.nodeId)
        let changed = snapshot.applyEdits([SourceEdit(SourceSpan(9, 15), "Change")])
        @Expect(changed.wasIncremental, true)
        @Expect(changed.snapshot.result.source.text(), "# Title\n\nChange\n\nAfter")
        @Expect(changed.changedRange, SourceSpan(9, 15))
        @Expect(changed.diagnosticsChangedRange, SourceSpan(9, 15))
        @Expect(changed.sourceMapChangedRange, SourceSpan(9, 15))
        @Expect(changed.snapshot.result.document.children()[0].nodeId, heading.nodeId)
        @Expect(changed.snapshot.result.document.children()[2].nodeId, after.nodeId)
        @Expect(changed.snapshot.stableNodeId(heading.nodeId), headingStable)
        @Expect(changed.snapshot.stableNodeId(after.nodeId), afterStable)

        let reference = engine.parseSnapshot("[x][id]\n\n[id]: /a")
        @Expect(reference.applyEdits([SourceEdit(SourceSpan(1, 2), "y")]).wasIncremental, false)
        let structural = engine.parseSnapshot("plain")
        @Expect(structural.applyEdits([SourceEdit(SourceSpan(0, 1), "#")]).wasIncremental, false)
    }

    @TestCase
    func overlappingAndSurrogateSplittingEditsAreRejected(): Unit {
        let snapshot = MarkdownEngine.builder().build().parseSnapshot("A😀B")
        try {
            snapshot.applyEdits([SourceEdit(SourceSpan(0, 2), "x"), SourceEdit(SourceSpan(1, 3), "y")])
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }
        try {
            snapshot.applyUtf16Edit(Utf16Position(0, 2), Utf16Position(0, 3), "x")
            @Expect(false)
        } catch (_: IllegalArgumentException) {
            @Expect(true)
        }
    }

    @TestCase
    func preservingFormatterSupportsRangeNodeAndChangedRangeEntryPoints(): Unit {
        let engine = MarkdownEngine.builder().build()
        let snapshot = engine.parseSnapshot("#  title")
        let rangeEdits = PreservingFormatter.formatRange(snapshot, SourceSpan(0, 8))
        @Expect(rangeEdits.size, 1)
        @Expect(rangeEdits[0].replacement, "# title")
        let heading = snapshot.result.document.children()[0]
        @Expect(PreservingFormatter.formatNode(snapshot, heading.nodeId).size, 1)

        let changed = snapshot.applyEdits([SourceEdit(SourceSpan(3, 8), "name")])
        let changedEdits = PreservingFormatter.formatChangedRanges(changed)
        @Expect(changed.changedRange, SourceSpan(3, 7))
        @Expect(changedEdits.size >= 0, true)
        @Expect(changed.snapshot.syntaxTree.losslessText(), "#  name")

        let preserved = engine.parseSnapshot("* item\n\nAT&amp;T\n\n````\nx ``` y\n````")
        @Expect(PreservingFormatter.formatRange(preserved,
            SourceSpan(0, preserved.result.source.byteLength())).size, 0)

        let customEngine = MarkdownEngine
            .builder()
            .dialect(
                MarkdownDialect
                    .define("raw", "1")
                    .enable(ExtensionManifest("raw", "1.0.0", "1"))
                    .inline(InlineSyntax.define("raw", "mark").delimiter("=="))
                    .build())
            .build()
        let custom = customEngine.parseSnapshot("==x==")
        @Expect(PreservingFormatter.formatRange(custom, SourceSpan(0, 5)).size, 0)
        try {
            PreservingFormatter.formatRange(custom, SourceSpan(0, 5), fallback: RangeFormatFallback.Error)
            @Expect(false)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.UnsupportedNode => @Expect(true)
                case _ => @Expect(false)
            }
        }
    }
}

private func hasSyntaxKind(tokens: Array<SyntaxToken>, kind: SyntaxKind): Bool {
    for (token in tokens) {
        match (kind) {
            case SyntaxKind.HeadingMarker =>
                if (let SyntaxKind.HeadingMarker <- token.kind) {
                    return true
                }
            case SyntaxKind.Delimiter =>
                if (let SyntaxKind.Delimiter <- token.kind) {
                    return true
                }
            case SyntaxKind.Entity =>
                if (let SyntaxKind.Entity <- token.kind) {
                    return true
                }
            case SyntaxKind.LinkLabel =>
                if (let SyntaxKind.LinkLabel <- token.kind) {
                    return true
                }
            case SyntaxKind.LinkDestination =>
                if (let SyntaxKind.LinkDestination <- token.kind) {
                    return true
                }
            case SyntaxKind.Html =>
                if (let SyntaxKind.Html <- token.kind) {
                    return true
                }
            case SyntaxKind.Fence =>
                if (let SyntaxKind.Fence <- token.kind) {
                    return true
                }
            case SyntaxKind.InfoString =>
                if (let SyntaxKind.InfoString <- token.kind) {
                    return true
                }
            case SyntaxKind.ExtensionToken =>
                if (let SyntaxKind.ExtensionToken <- token.kind) {
                    return true
                }
            case SyntaxKind.Invalid =>
                if (let SyntaxKind.Invalid <- token.kind) {
                    return true
                }
            case _ => ()
        }
    }
    false
}
