# Fuzz and pathological-input summary

Date: 2026-08-18

- Deterministic seed: `20260817`.
- Public-pipeline cases: 500 generated inputs, all passed String/bytes/chunked
  equivalence, AST invariants, Safe HTML, canonical formatter idempotence,
  identity rewrite, and artifact load.
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

Command evidence: final `cjpm test` reported 1410 passed, 0 skipped, 0 error,
0 failed. This is a deterministic in-process fuzz/property smoke suite, not a
claim of exhaustive coverage by a coverage-guided native fuzzer. No unhandled
crash was observed in the published corpus. Any future crash must be minimized
and added as a versioned regression before release.
