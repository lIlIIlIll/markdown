# Public API map

- Core (`markdown.core`): `MarkdownEngineBuilder`, `MarkdownEngine`, `ParseResult`, `BufferedInputSession`, AST and source positions.
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

The low-allocation source Event API is scheduled for 1.1. Version 0.9 does not
expose an AST-walk adapter as a streaming API.
- Editor: lint/fix/explain, snapshots, preserving edits, artifacts.
- Convenience: `Markdown.parse`, `toSafeHtml`, `toSpecHtml`, `toText`, `format`.

The root `markdown` package remains a compatibility facade. New consumers should
prefer curated subpackage imports so that experimental document tooling does not
become an accidental dependency. All examples under `examples/quickstart`
compile against public symbols only.
