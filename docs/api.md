# Public API map

- Core (`markdown.core`): `MarkdownEngineBuilder`, `MarkdownEngine`, `ParseResult`, source-driven Event API, buffered input, AST and source positions.
- Rendering (`markdown.render`): HTML/plain text/Markdown renderers, source maps, sinks and explicitly buffered async output.
- Extensions (`markdown.extensions`): dialect, syntax, SPI, renderer rules and manifests.
- Editor (`markdown.editor`): CST, query, rewrite, transform, lint/fix and preserving edits.
- Artifacts/documents/testkit: isolated in `markdown.artifact`, `markdown.document` and `markdown.testkit`.
- Native accelerator (`markdown.native`): optional `NativeLineScanner`; the root package has no foreign or linker dependency.
- Source: `SourceBuffer`, `SourceSpan`, `SourcePosition`, `Utf16Position`, `SyntaxTree`, snapshots/edits.
- AST: typed block/inline nodes, `NodeId`, `NodeOrigin`, custom nodes.
- Extension: dialect/syntax/renderer builders, manifests, compiled dialect and fingerprint.
- Output: `HtmlRenderer`, `PlainTextRenderer`, `CanonicalMarkdownRenderer`, `TextSink`, source maps.
- Tools: Walker, Visitor, Query, TreeRewriter, TransformPipeline and AnnotationStore.

- Events: `MarkdownEventMode`, `MarkdownSourceEvent`, `MarkdownEventSink`,
  `EventParseResult`, `EventParseSummary` and `RawBlockEventSession`.
- Editor: lint/fix/explain, snapshots, preserving edits, artifacts.
- Convenience: `Markdown.parse`, `toSafeHtml`, `toSpecHtml`, `toText`, `format`.

The root `markdown` package remains a compatibility facade. New consumers should
prefer curated subpackage imports so that experimental document tooling does not
become an accidental dependency. All examples under `examples/quickstart`
compile against public symbols only.

## Source events

`ResolvedEventMode` performs a reference-index pass and then emits final
semantic events directly from transient parser blocks. The event values contain
only kinds, source ranges, attributes and text values; they do not retain a
`Document` or `NodeRef`.

```cangjie
let result = MarkdownEngine.builder().build().parseEvents(
    "[label][id]\n\n[id]: /target\n"
)
for (event in result.events.toArray()) {
    match (event.kind) {
        case MarkdownSourceEventKind.Text => println(event.semanticValue.getOrThrow())
        case _ => ()
    }
}
```

Use `emitEvents(source, sink)` when the consumer can process events without
retaining an array. `RawBlockEventMode` is deliberately non-final: use
`newRawBlockEventSession()`, call `feed()` for arbitrary UTF-8 chunks, and
consume events returned for blocks proven closed by later input. `finish()`
emits the last buffered block and `DocumentEnd`. Chunked raw execution may
buffer one unfinished top-level block and never claims reference resolution.

The existing buffered parse/async adapters remain distinct from this Event
API. They do not become incremental AST parsing merely because raw block events
can be emitted before `finish()`.
