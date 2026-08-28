# Changelog

All notable changes follow Keep a Changelog and Semantic Versioning.

## 0.9.0 - Unreleased

This is an explicitly breaking pre-GA release. It introduces the arena-backed
AST contract, trigger-declared parser SPI v2, explicit fused-render execution
selection, and artifact schema v2. The 0.8 object-tree AST and AST-walk event
representation are not retained as runtime adapters. The source Event API is
scheduled for 1.1 and is not exposed as an AST-backed compatibility facade.

## 0.8.0 - 2026-08-25

This is a pre-GA preview, not a 1.0 compatibility freeze. Correctness,
artifact, fingerprint and SourceMap contracts may still change before GA; the
remaining performance and release-evidence gates are tracked explicitly.

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
