# Public API map

- Parsing: `MarkdownEngineBuilder`, `MarkdownEngine`, `ParseResult`, `ChunkedParseSession`.
- Source: `SourceBuffer`, `SourceSpan`, `SourcePosition`, `Utf16Position`, `SyntaxTree`, snapshots/edits.
- AST: typed block/inline nodes, `NodeId`, `NodeOrigin`, custom nodes.
- Extension: dialect/syntax/renderer builders, manifests, compiled dialect and fingerprint.
- Output: `HtmlRenderer`, `PlainTextRenderer`, `CanonicalMarkdownRenderer`, `TextSink`, source maps.
- Tools: Walker, Visitor, Query, TreeRewriter, TransformPipeline, AnnotationStore, Event API.
- Editor: lint/fix/explain, snapshots, preserving edits, artifacts.
- Convenience: `Markdown.parse`, `toSafeHtml`, `toSpecHtml`, `toText`, `format`.

All examples under `examples/quickstart` compile against these public symbols only.
