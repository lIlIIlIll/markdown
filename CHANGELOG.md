# Changelog

All notable changes follow Keep a Changelog and Semantic Versioning.

## 1.0.0 - 2026-08-17

### Added

- CommonMark 0.31.2 and GFM 0.29 profiles with direct official conformance suites.
- Immutable AST, byte-accurate source spans, UTF-16/visual mapping, and source slices.
- Bounded String, byte, stream, and chunked parsing with cancellation and diagnostics.
- Spec, GFM, safe HTML, plain text, and canonical Markdown rendering.
- Versioned dialect/syntax/renderer DSL, fingerprints, extension TCK, and capabilities.
- Walker, visitor, query, immutable rewrite, transform, lint/fix/explain, snapshot,
  lossless token, preserving-format, source-map, event, annotation, and artifact APIs.
- `markdown` CLI, quickstart, API snapshot, fuzz/security corpora, and benchmarks.

### Security

- Safe HTML is the default; raw HTML is escaped and remote/data images are denied.
- Input, nesting, work, extension, node, URL, literal, and output limits are enforced.

### Known release blockers

- The local reference-host benchmark currently exceeds the PRD GA ratios. This
  release entry remains a candidate until `docs/reports/benchmark.md` passes.
