# AST and transformations

The public AST is immutable, acyclic, deterministic, and safe for concurrent reads. `ImmutableArray` defensively copies constructor arrays. Every parsed node has a UTF-8 `SourceSpan` and deterministic `NodeId`; IDs are stable within one Document, not across edits.

Use `walk()`, `MarkdownVisitor`, `AstQuery`, or `TreeRewriter`. Rewrites are iterative, preserve untouched branches, support keep/replace/remove/insert/replace-children/map-text, consume transform budget, honor cancellation, and validate invariants before returning.

Third-party nodes use `CustomBlock`/`CustomInline` with extension identity, semantic version, local kind, typed payload, children, span, and origin.

