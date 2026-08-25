# Fuzz and pathological-input summary

Date: 2026-08-25

- Deterministic seed: `20260817`.
- Public-pipeline cases: 500 generated inputs, all passed String/bytes/chunked
  equivalence, AST invariants, Safe HTML, canonical formatter idempotence,
  identity rewrite, and artifact load.
- Arbitrary-byte cases: 256 inputs up to 191 bytes using seed `20260825`;
  Strict and ReplaceInvalid were compared between all-at-once and varied chunk
  partitions, including decoded text, original byte length, diagnostics, HTML
  and AST invariants. The new corpus found and now guards two UTF-8 boundary
  crashes in GFM email autolink and HTML-block ASCII normalization.
- Historical corpus: the exact 16-byte input for the 2026-08-25 UTF-8/GFM
  failure is retained under `tests/fuzz/crashes` and replayed in the Cangjie
  suite across Strict/ReplaceInvalid and partitioned buffered input.
- Native scanner: `scripts/fuzz_native_scanner.py` builds an ASan+UBSan
  deterministic boundary harness and a libFuzzer binary. The release smoke gate
  executes 10,000 coverage-guided runs against the checked-in seed corpus.
- DSL compiler cases: 128 generated bounded/unbounded delimiter declarations;
  all accepted/rejected according to the declared bounds.
- Extension TCK: 10/10 checks passed, including one-byte chunks, spans, safe
  output, deterministic replay, cancellation, budget failure, formatter
  semantics, fuzz mutations, and fingerprint stability.
- Security corpus: raw HTML, event attributes, mixed-case/control-obfuscated
  URI schemes, data/remote images, iframe/script, and bidi input passed.
- Pathological corpus: delimiter storms, 8,000 unclosed brackets, 2,000 HTML
  openers, 2,000 references, 1,024-column table, 1 MiB line, 2,000-level
  quote/list nesting, 1,000-level nested DSL blocks, and output amplification
  passed without unhandled crash or host stack overflow.

The Cangjie property suite and the native coverage/sanitizer gate are separate;
neither is presented as exhaustive. Any future crash must be minimized and
added as a versioned regression before release.
