# Benchmark method

Use release builds on the pinned reference host. Record SDK/compiler, CPU affinity, corpus digest, reference implementation version, warmup, raw samples, median/geometric mean, peak additional memory, and optional feature overhead.

The corpus includes official examples, README/API docs, large code/table/reference documents, CJK, emoji, deep lists, pathological delimiters, long lines, and extensions. The README/API profile replaces the generated `release-evidence` block with one fixed marker before sizing and hashing the input. Benchmark results can therefore be written back without recursively changing the next run's corpus; missing or duplicate markers fail closed. Scaling uses 1/2/4/8/16 MiB with at least seven samples; log-log slope above 1.35 or adjacent doubling above 3.0 fails.

Allocation strategy:

- String input uses one identity SourceBuffer byte view; strict ordinary bytes
  omit the former per-byte identity offset table.
- `OwnedUtf8Input.take` is an explicit unsafe ownership-transfer entry that
  requires already-valid UTF-8 and avoids both cloning and revalidating the
  transferred byte array; the normal Array API retains validation and its
  immutable defensive copy.
- `ReusableUtf8Input` validates and defensively copies once, or accepts the
  same explicit unsafe ownership transfer, then reuses immutable UTF-8 storage
  across parses. Every parse still creates a complete AST, NodeId,
  SourceSpan, SourceBuffer, and ParseResult.
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
generated raw benchmark. Canonical `commonmark-parse` uses one
`ReusableUtf8Input`; `commonmark-parse-owned` separately measures the cost of
cloning and transferring a fresh byte array for each parse. Neither profile is
presented as the default String facade, and neither disables the public AST or
source-position contract.
The benchmark driver explicitly imports `markdown.native.NativeLineScanner`,
injects it into every engine, and links the checked native archive. The root
library defaults to the pure-Cangjie scanner and carries no foreign link
dependency; benchmark metadata must therefore keep `nativeScanner` explicit.
The reusable profile performs one validation or unsafe ownership transfer at
process preparation and no input conversion inside each parse call. The String
profile performs one process-preparation decode from benchmark stdin and no
conversion inside each parse call. Array input performs defensive copy and
decoding per parse, owned input clones in the driver to create a fresh ownership
transfer, and stream input performs full buffering and decoding.

The driver also exposes `gfm-parse` as a diagnostic profile. It uses the same
GFM profile, trusted limits, owned-byte input, and native scanner as `gfm-html`,
but observes the completed AST without rendering it. Newly generated raw reports
store alternating parse-only and parse-plus-HTML samples under
`phaseProfiles.gfm` for five 1 MiB corpora. The reported renderer duration is an
inference from the difference between two independent medians, not an internal
timer. This profile locates parser-versus-renderer work; it does not replace the
canonical GFM parse-plus-HTML comparison or any release gate.

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
`docs/reports/benchmark.md`, and the acceptance report. The current 2026-08-28 R79 canonical
run is bound to workspace commit anchor `2454b0626c2fb0fe590a59bc1f79a8d4e864c856`,
Cangjie SDK `1.1.0-alpha.20260803040049`, source archive SHA-256
`837ad48e1ce6db3e0d7487739c8fde8aa135275f60bc5dad90367f7371e988de`, benchmark harness,
and driver SHA-256 `8b750a8172b473e55cba494545a787c7b5379b1693d89be3cacd22d8f275ea4c`.
It measured CommonMark `3.827122x` and GFM `2.954111x`;
all non-ratio gates passed, so `MD-PERF-002` remains blocked only by the two
`2.5x` ratio limits. Raw SHA-256 is
`394a769e9f408cb18daf4acf9b27c7b3897cca84122c6d238c2c94c01caef486`.
The exact workspace archive and driver are bound, but the evidence tree remains
explicitly dirty until the implementation and generated reports are committed.

Reference provisioning reports `lockGenerationDeterminism: not claimed / not
tested` and `sealedLockOfflineConsumptionReproducible: true`. Its official
npm runtime license report records 217 reachable package instances: 216
`declared_raw`, one generic `text_only`, and zero failed. The supported claim is
only `license evidence closure complete`; no SPDX or legal conclusion is made.
