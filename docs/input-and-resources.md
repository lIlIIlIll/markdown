# Input, cancellation, and budgets

`MarkdownEngine` accepts String, UTF-8 bytes, `InputStream`, and `ChunkedParseSession`. Chunk sessions produce final semantics only at `finish()` and reject feeds after finish. All forms share profiles, limits, budgets, cancellation, diagnostics, and AST validation.

`ParseLimits.safe()` bounds input, line, depth, nodes, references, table columns, URL, literal, output, capture, and lookahead. `trusted()` raises sizes but never disables overflow/capacity/acyclic/stack/output protections. `OperationBudget` separately bounds scans, delimiters, callbacks, transforms, rendered nodes, and bytes. The host owns wall-clock deadlines via `CancellationToken`.

`SourceBuffer.sourceSlice` and `LiteralStorage.Copy`/`Slice` make ownership
explicit. Plain Text nodes and exact LF code/HTML literals default to
`SourceSlice`; normalized/decoded values use `Copy`. Strict byte decoding no
longer allocates an identity offset table. `detach()` recursively converts
Text/CodeBlock/HtmlBlock slices to owned text. `SourcePositionMap` exposes
byte, UTF-16, and visual positions without modifying source. The normal `parse`
entry throws on hard failure and therefore returns no AST. Only explicit
`parsePartial` returns `isComplete=false`, `stoppedAt`, `unfinishedPhase`, and
structured errors; partial results are rejected by artifact creation.
