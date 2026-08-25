# Benchmark method

Use release builds on the pinned reference host. Record SDK/compiler, CPU affinity, corpus digest, reference implementation version, warmup, raw samples, median/geometric mean, peak additional memory, and optional feature overhead.

The corpus includes official examples, README/API docs, large code/table/reference documents, CJK, emoji, deep lists, pathological delimiters, long lines, and extensions. Scaling uses 1/2/4/8/16 MiB with at least seven samples; log-log slope above 1.35 or adjacent doubling above 3.0 fails.

Allocation strategy:

- String input uses one identity SourceBuffer byte view; strict ordinary bytes
  omit the former per-byte identity offset table.
- `OwnedUtf8Input.take` is an explicit unsafe ownership-transfer entry that
  requires already-valid UTF-8 and avoids both cloning and revalidating the
  transferred byte array; the normal Array API retains validation and its
  immutable defensive copy.
- Text literals of at least 256 bytes and exact LF fenced-code/raw-HTML
  literals use `SourceSlice`; decoded/normalized/small values use `Copy`.
- Parser scratch collections are owned only by one `ParserSession` and become
  unreachable together at parse completion, providing an arena-equivalent
  lifetime without exposing allocator state in the AST.
- The semantic parser does not allocate one token per character. Lossless CST
  tokens are opt-in and their separately measured time overhead is reported.
  A CST owns one token arena; nested syntax nodes hold immutable range views,
  while public `toArray()` calls still return defensive copies. AST/CST and
  byte-offset/token queries use construction-time indexes.
- Renderers write directly to bounded Sink instances. Entity data is generated
  once as shared read-only tables.
- Stable public node classes are retained instead of an ABI-risk compact tagged
  representation; the measured RSS gate, rather than an unverified size claim,
  decides acceptance.
- Reference definitions are indexed once per parse session. Effective labels
  are resolved through a hash map, delimiter link detection reuses that index,
  and already-trimmed lowercase ASCII labels avoid the normalization builder.
- `MD_Markdown_ScanLines` performs no I/O, locking, blocking, or Cangjie
  callbacks, but the whole-input byte loop is not annotated `@FastNative`
  because its total execution time is input-dependent and cannot be proven
  short and bounded. Long parser and allocation work remains in cancellable
  Cangjie code.

Input APIs are reported separately under `inputProfiles` in every newly
generated raw benchmark. `commonmark-parse` remains a compatibility alias for
`commonmark-parse-owned`; it must not be presented as the default String facade.
The benchmark driver explicitly imports `markdown.native.NativeLineScanner`,
injects it into every engine, and links the checked native archive. The root
library defaults to the pure-Cangjie scanner and carries no foreign link
dependency; benchmark metadata must therefore keep `nativeScanner` explicit.
The String profile performs one process-preparation decode from benchmark stdin
and no conversion inside each parse call. Array input performs defensive copy
and decoding per parse, owned input clones in the driver to create a fresh
ownership transfer, and stream input performs full buffering and decoding.

## 2026-08-23 benchmark dependency transition

Dependency H `db4392e2` makes the paired seven-sample ordering, CPU/reference
overrides, and owned-input benchmark workload part of the committed protocol.
The pre-H raw SHA-256 `48dbad5298825c627ebaa914909c79f7680949e9487158cd843e67dc9af54fa2`
and ratios `6.449555x`/`5.695987x` are historical pre-dependency measurements,
not final acceptance evidence; no trend or projection is inferred from them.
Historical UInt32 `4.089529x`/`3.396847x` is likewise invalid for the current
candidate. The fresh committed-H archive run at
`/tmp/markdown-project-f001-20260823-RydvVhT9` produced raw SHA-256
`9acd3c7b7e2077462daeff0032f8a43e4d507fab3fe21dda244a663bc3f950d0`.
It used 11 256 KiB comparison corpora, 3 iterations per process, and 7 paired
samples per side. CommonMark was `6.234490x` and GFM `4.845909x`; ordinary,
scaling slope, adjacent growth, pathological slope, and RSS gates passed, but
both ratio gates failed. This is retained as a historical dependency-transition
run, not as the current release value. The sole canonical release result is
declared in `release-evidence.json` and rendered into README,
`docs/reports/benchmark.md`, and the acceptance report. The current 2026-08-25 canonical
run is bound to source commit `34113ea6f47a3bcd57b80ca9ee5c6063873dd5bb`,
Cangjie SDK `1.1.0-alpha.20260803040049`, the source archive, benchmark harness,
and all three drivers. It measured CommonMark `5.731996x` and GFM `5.013855x`;
all non-ratio gates passed, so `MD-PERF-002` remains blocked only by the two
`2.5x` ratio limits. The evidence tree is still dirty until the reproducibility
raw data and generated reports are committed.

Reference provisioning reports `lockGenerationDeterminism: not claimed / not
tested` and `sealedLockOfflineConsumptionReproducible: true`. Its official
npm runtime license report records 217 reachable package instances: 216
`declared_raw`, one generic `text_only`, and zero failed. The supported claim is
only `license evidence closure complete`; no SPDX or legal conclusion is made.
