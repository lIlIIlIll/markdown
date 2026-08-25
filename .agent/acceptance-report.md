# markdown 最终验收报告

## Final Status

**INCOMPLETE** — 125 项需求中 122 项为 `pass`，仍有 3 项 blocked；私密安全报告渠道已启用并验证，性能 GA 数值仍实测失败。

<!-- release-evidence:start -->
## Generated Release Evidence

- Version/status: `0.8.0` / `draft`.
- Source identity: `UNBOUND`; tree state `dirty`.
- Tests: `1423/1423` passed, `0` skipped, `0` failed.
- Benchmark: CommonMark `6.98x`, GFM `5.99x`, status `stale-unbound`.
- Raw digest: `a107300090f599152ffd8e9020465666ed1b3b91c7e2fccd783ddcfc29d897d9`.

Because source commit and benchmark SDK are unbound, this evidence is not
release-ready and cannot change the overall `INCOMPLETE` verdict.
<!-- release-evidence:end -->

2026-08-23 dependency transition：H `db4392e2` commits the paired seven-sample
protocol and owned-input driver. Pre-H raw `48dbad...` and
`6.449555x`/`5.695987x` are historical pre-dependency measurements, not final
acceptance evidence; UInt32 `4.089529x`/`3.396847x` is also historical and
superseded. Fresh validation must come from the committed H stack, and
the committed-H preliminary archive has now passed typed UInt64 no-cast ABI,
API 1155, tests 1410/1410, CLI, differential 25/24/1/0, benchmark smoke,
quickstart, and bundle. Fresh final formal raw SHA-256
`9acd3c7b7e2077462daeff0032f8a43e4d507fab3fe21dda244a663bc3f950d0`
measured CommonMark `6.234490x` and GFM `4.845909x`; both exceed `2.5x`, so
`MD-PERF-002` remains blocked. The reused reference root passed its fresh
seal/path/binary identity check.

## Requirement Summary

| 状态 | 数量 |
| --- | ---: |
| `pass` | 122 |
| `implemented_unverified` | 0 |
| `pending` | 0 |
| `blocked` | 3 |

## Itemized Verdict

| ID | Source | Status | Evidence / reason |
| --- | --- | --- | --- |
| `MD-GOV-001` | PRD §1, §4, §54.1-7 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-002` | PRD §6.1, §11.4, §48.3, §54.3-6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-003` | PRD §6.2, §24.1, §54.7, §54.30-31 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-004` | PRD §6.3, §10.1-2, §54.8-10 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-005` | PRD §8, §29, §53.4-6, §54.14-16, §54.27, §54.33, §54.36 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-USE-001` | PRD §9.1-6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ARCH-001` | PRD §10.1-2, §55 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ARCH-002` | PRD §10.3, §40 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PRO-001` | PRD §11.1-3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DIA-001` | PRD §12.1, §39.2, §51.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DIA-002` | PRD §12.2-3, §54.19 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DIA-003` | PRD §12.4-5, §53.8, §54.20 | `pass` | 2026-08-25: canonical length-prefix adversarial cases and full 1413-test suite pass |
| `MD-DIA-004` | PRD §12.6, §51.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SYN-001` | PRD §6.4, §13.1, §54.12, §54.15, §54.17-18 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SYN-002` | PRD §13.2-3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SYN-003` | PRD §13.4, §18.10 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SYN-004` | PRD §13.5, §51.2, §53.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SYN-005` | PRD §13.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-RDSL-001` | PRD §14.1, §28.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-RDSL-002` | PRD §14.2, §51.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-RDSL-003` | PRD §14.3, §32.6, §54.32 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-RDSL-004` | PRD §14.5, §26.6, §51.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-TRN-001` | PRD §15, §22.6, §54.14 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-001` | PRD §16 IN-001, §51.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-002` | PRD §16 IN-002, §51.3 | `pass` | 2026-08-25: 256 arbitrary-byte Strict/ReplaceInvalid chunk-differential cases and full 1419-test suite passed |
| `MD-IN-003` | PRD §16 IN-003, §51.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-004` | PRD §16 IN-004-005, §39.4, §44.3, §51.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-005` | PRD §16 IN-006-007 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-006` | PRD §16 IN-008, §51.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-007` | PRD §16 IN-009, §45.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-IN-008` | PRD §16 IN-010, §51.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-POS-001` | PRD §17.1-3, §51.4, §54.21 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-POS-002` | PRD §17.4, §53.7 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-POS-003` | PRD §17.5, §51.4, §54.22 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-POS-004` | PRD §17.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-001` | PRD §18 PAR-001, §10.1 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-002` | PRD §18 PAR-002, §20.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-003` | PRD §18 PAR-003, §20.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-004` | PRD §18 PAR-004 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-005` | PRD §18 PAR-005 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-006` | PRD §18 PAR-006 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-007` | PRD §18 PAR-007, §24.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-008` | PRD §6.7, §18 PAR-008 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-PAR-009` | PRD §18 PAR-009, §51.3, §54.28 | `pass` | 2026-08-18: trusted 2000-level quote/list and 1000-level DSL tests passed using explicit block frames |
| `MD-PAR-010` | PRD §6.5, §18 PAR-010, §43 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-VAL-001` | PRD §19.1-3, §51.4, §54.23 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-VAL-002` | PRD §19.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-AST-001` | PRD §20.1, §42.4, §54.25 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-AST-002` | PRD §20.2-3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-AST-003` | PRD §20.4, §36.4, §51.4, §54.24 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-AST-004` | PRD §20.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-AST-005` | PRD §20.6, §48.4, §51.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-AST-006` | PRD §20.7, §50 M5, §51.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-CST-001` | PRD §21.1-2, §54.9 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-CST-002` | PRD §21.3-4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-CST-003` | PRD §21.5, §26.5, §54.39 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-OPS-001` | PRD §22 AST-001-003, §51.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-OPS-002` | PRD §22 AST-004-005, §39.8, §51.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-OPS-003` | PRD §22 AST-006 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ANN-001` | PRD §23, §42.10 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-HTML-001` | PRD §24.1, §51.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-HTML-002` | PRD §24.2, §44.5, §51.5-6 | `pass` | 2026-08-25: exact data-image MIME and Safe `_blank` rel hardening; full 1418-test suite passed |
| `MD-HTML-003` | PRD §24.3, §51.5-6, §54.29 | `pass` | 2026-08-25: MIME parameters/prefix collision and rel-token deduplication regressions passed |
| `MD-HTML-004` | PRD §24.4-5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-HTML-005` | PRD §24.6, §53.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-HTML-006` | PRD §24.7 | `pass` | 2026-08-25: write-time SourceMap tag-collision cases and full 1413-test suite pass |
| `MD-TEXT-001` | PRD §25, §51.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FMT-001` | PRD §26.1, §51.5, §54.38 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FMT-002` | PRD §26.2, §26.4, §44.4, §51.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FMT-003` | PRD §26.5, §54.39 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FMT-004` | PRD §26.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EVT-001` | PRD §27, §54.10 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXT-001` | PRD §28.1-2, §54.34 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXT-002` | PRD §28.3-4, §37, §54.34 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXT-003` | PRD §28.5, §53.5, §54.33 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXT-004` | PRD §28.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXT-005` | PRD §28.7, §44.8, §51.2, §54.35 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXT-006` | PRD §29 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-CAN-001` | PRD §30.1, §51.6, §54.26 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-CAN-002` | PRD §30.2, §51.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-BUD-001` | PRD §30.3-4, §51.6, §54.27 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SINK-001` | PRD §30.5, §39.6, §45.4, §51.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-LIM-001` | PRD §6.6, §31, §51.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-LIM-002` | PRD §31, §54.28 | `pass` | 2026-08-25: low AST-node, multiline literal and Parser SPI attacks plus full 1413-test suite pass |
| `MD-SEC-001` | PRD §32 SEC-001, §49, §54.36-37 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SEC-002` | PRD §32 SEC-002, §44.7, §51.6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SEC-003` | PRD §32 SEC-003-005 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SEC-004` | PRD §32 SEC-006, §51.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-SEC-005` | PRD §32 SEC-007, §51.6-7 | `pass` | 2026-08-24: GitHub official API returned `{"enabled":true}`; SECURITY.md and docs/security.md link the private advisory form. |
| `MD-ERR-001` | PRD §33.1 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ERR-002` | PRD §33.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ERR-003` | PRD §33.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ERR-004` | PRD §33.4 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-LINT-001` | PRD §34 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-LINT-002` | PRD §34 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EXP-001` | PRD §35 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EDIT-001` | PRD §36.1-2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-EDIT-002` | PRD §36.3-4, §54.40 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FUT-001` | PRD §7.3, §8.13, §54.16 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FUT-002` | PRD §7.3, §8.16, §53.5 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-FUT-003` | PRD §7.3 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-CAP-001` | PRD §37, §47.18, §51.2 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-ART-001` | PRD §38 | `pass` | 2026-08-25: ReplaceInvalid artifact rejection and full 1413-test suite pass |
| `MD-API-001` | PRD §39.1-8 | `pass` | 2026-08-18: public API snapshot verified; 1155 declarations |
| `MD-API-002` | PRD §39.9, §6.1 | `pass` | 2026-08-18: public API snapshot verified; 1155 declarations |
| `MD-PKG-001` | PRD §40, §49 | `pass` | 2026-08-19: Cangjie core remains std-only; CLI, benchmark driver and quickstart explicitly link the bounded static `libmarkdown_scanner` asset; bundle and consumer fixtures are validated |
| `MD-CLI-001` | PRD §41.1-6, §49 | `pass` | 2026-08-18: CLI build and scripts/cli_smoke.sh; exit 0 |
| `MD-CLI-002` | PRD §41.7 | `pass` | 2026-08-18: scripts/cli_smoke.sh; exit 0; documented exit codes verified |
| `MD-CON-001` | PRD §42 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DET-001` | PRD §6.5, §43, §52 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-TST-001` | PRD §4, §44.1, §51.1, §52 | `pass` | 2026-08-18: full suite included CommonMark 652/652 and GFM 671/671 |
| `MD-TST-002` | PRD §44.2 | `pass` | 2026-08-18: differential test; 25 checked, 24 exact, 1 classified, 0 unexpected |
| `MD-TST-003` | PRD §44.3-4, §51.3, §52 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-TST-004` | PRD §44.5-6, §51.6-7 | `pass` | 2026-08-25: arbitrary-byte fuzz found and guards two UTF-8 boundary crashes; full 1419-test suite passed |
| `MD-TST-005` | PRD §44.7-9, §51.7 | `pass` | 2026-08-18: API snapshot, pathological corpus, and official extension TCK passed |
| `MD-PERF-001` | PRD §45.1-3 | `pass` | 2026-08-18: 12-corpus -O2 reference-host matrix recorded raw samples, per-corpus digests, pinned CPU, SDK, reference commits, geometric means, and custom-extension cost |
| `MD-PERF-002` | PRD §45.4, §51.7, §52 | `blocked` | 2026-08-21 current candidate on Server CPU 24: CommonMark 4.329x and GFM 3.276x versus 2.5x limits. Scaling slope 0.961, adjacent 2.400, pathological slope 0.866 and extra RSS 59632 KiB pass; only both ratio gates fail. |
| `MD-PERF-003` | PRD §45.5 | `pass` | 2026-08-18: owned byte input, SourceSlice literals, explicit parser frames, bounded output, ordinary/pathological scaling, and RSS tests passed |
| `MD-OBS-001` | PRD §46 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DOC-001` | PRD §47, §49, §51.7 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DOC-002` | PRD §47, §49, §51.7 | `pass` | 2026-08-18: examples/quickstart built and ran using only the public package API |
| `MD-COMP-001` | PRD §48.1-2 | `pass` | 2026-08-18: public API snapshot verified; 1155 declarations |
| `MD-COMP-002` | PRD §48.3-6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-REL-001` | PRD §49, §50 M6, §51 | `blocked` | The package, CLI, documentation, reports, example, bundle, and private reporting channel exist, but mandatory MD-PERF-002 prevents a 1.0 GA declaration. |
| `MD-QUAL-001` | PRD §51.7, §52 | `blocked` | Correctness, package, and private security reporting gates pass, but the mandatory performance success metric does not. |

## Validation Evidence

| Command | Exit | Result |
| --- | ---: | --- |
| `scripts/check_format.sh` | 0 | all Cangjie source matches cjfmt |
| `cjlint -f src` | 0 | 0 errors; 476 advisory diagnostics |
| `cjpm check` | 0 | dependency graph valid |
| `cjpm build` | 0 | root static library, `-O2` |
| `cjpm test` (2026-08-21 current renderer candidate, local socket-enabled rerun) | 0 | 1411 passed, 0 skipped/error/failed |
| CommonMark/GFM cases inside full suite | 0 | 652/652 and 671/671 |
| `cd tools/markdown && cjpm build`; `scripts/cli_smoke.sh` | 0 | CLI build and exit 0/2/3/4/5/6/7 smoke; explicit native archive link |
| `cd examples/quickstart && cjpm build && cjpm run` | 0 | public consumer example built and ran; explicit native archive link |
| `python3 scripts/check_public_api.py` | 0 | 1155 public declarations match snapshot |
| `python3 scripts/test_check_public_api.py` | 0 | 8/8 checker regression tests passed |
| `python3 scripts/test_release_evidence.py` | 0 | 3/3 consistency and fail-closed regressions passed |
| `python3 scripts/test_benchmark_input_profiles.py` | 0 | String/Array/Owned/Stream modes execute and produce identical parse checksums |
| `python3 scripts/release_evidence.py` | 0 | README, benchmark report, acceptance projection, raw/corpus/API digests and ratios match the canonical evidence file |
| `python3 scripts/release_evidence.py --release-ready` | 1 (expected) | correctly rejects draft, dirty/unbound source and stale/unbound benchmark identity |
| `python3 scripts/differential_test.py` | 0 | 25 comparisons: 24 exact, 1 classified, 0 unexpected |
| `cjpm bench --filter MarkdownReleaseBenchmarks ...` | 0 | 3/3 benchmark smoke cases; socket permission required |
| remote `python3` wrapper importing `benchmarks/measure.py` on authorized SSH Server (CPU 24) | 1 | 2026-08-19 final candidate: CommonMark 6.137x, GFM 5.459x, ordinary/scaling and RSS gates pass, ratio and pathological slope gates fail; same-SDK paired baseline 6.945x/5.670x |
| `MARKDOWN_BENCH_CPU=24 ... python3 benchmarks/measure.py` on authorized SSH Server | 1 | 2026-08-20 current candidate: CommonMark 5.261x, GFM 4.129x; scaling, pathological and RSS gates pass; only both 2.5x ratio gates fail; raw SHA-256 9ac920...8573 |
| `MARKDOWN_BENCH_CPU=24 ... python3 benchmarks/measure.py` on authorized SSH Server | 1 | 2026-08-21 retained candidate: CommonMark 4.469x, GFM 4.028x; scaling, pathological and RSS gates pass; only both 2.5x ratio gates fail; raw SHA-256 aaac470...0e03 |
| `MARKDOWN_BENCH_CPU=24 ... python3 benchmarks/measure.py` on authorized SSH Server, per-corpus alternating pairs | 1 | 2026-08-21 current renderer/reference-link candidate: CommonMark 4.329x, GFM 3.276x; slope 0.961, adjacent 2.400, pathological slope 0.866, RSS 59632 KiB pass; only both 2.5x ratio gates fail; raw SHA-256 1a6bc4...c011 |
| `python3 /tmp/markdown_pair_link_attribute_cache.py baseline-first ...` on Server CPU 24 | 0 | S0 run 1 checksums matched; many-reference GFM 0.97497 and GFM geomean 1.01269 failed 0.95/0.98 stop-go limits; raw SHA-256 8dd1a3...055d |
| `python3 /tmp/markdown_pair_link_attribute_cache.py candidate-first ...` on Server CPU 24 | 0 | S0 run 2 checksums matched; many-reference GFM 0.97300 and GFM geomean 0.99982 failed 0.95/0.98 stop-go limits; raw SHA-256 1a45f6...d18c |
| `scripts/release_gate.sh` | 1 | fail-closed at performance after format/API/check/build/1410 tests/CLI/example/differential/benchmark smoke passed |
| `cjpm bundle --skip-test` after the full 1410-test gate | 0 | target/markdown-1.0.0.cjp; 343528 bytes; SHA-256 aab2e233b88b495c0221eb36e673c0d6a19184721b1776620525283098882529 |
| `cjpm test --no-color --no-progress --report-path /tmp/markdown-p0-final-tests-2 --report-format xml` | 0 | 1413 passed, 0 skipped/error/failed |
| `cjpm bundle --skip-test` for 0.8.0 | 0 | target/markdown-0.8.0.cjp; 374 KiB; SHA-256 8782dcc16ea5063e70e51ac74efdbc87c33fdd19885beaa63feeebfb67cfd527 |
| `cjpm test --no-color --no-progress --report-path /tmp/markdown-p1-input-profile-full-tests --report-format xml` | 0 | 1414 passed, 0 skipped/error/failed |
| `cjpm test` (2026-08-25 indexed SourcePositionMap full rerun) | 0 | 1415 passed, 0 skipped/error/failed; indexed CRLF/Unicode/replacement/checkpoint case passed |
| `cjpm test` (2026-08-25 shared CST arena full rerun) | 0 | 1416 passed, 0 skipped/error/failed; arena ranges, defensive copy and query indexes passed |
| `cjpm bench --filter MarkdownReleaseBenchmarks --no-color` (after CST arena change) | 0 | 3/3 benchmark smoke cases passed; not canonical performance evidence |
| `cjpm test` (2026-08-25 SemVer final rerun) | 0 | 1417 passed, 0 skipped/error/failed; prerelease/build/invalid/overflow cases passed |


## Release Decision

The package must not be released or described as COMPLETE. The final bundle
succeeded, and GitHub Private Vulnerability Reporting is enabled, but
`benchmarks/measure.py` exits 1. No waiver or threshold reduction was applied.

## 2026-08-18 Performance Investigation Addendum

The follow-up investigation used the authorized SSH Server with fixed CPU 24,
1 MiB fixed corpora, alternating paired runs, and `perf record -F 99 -g
--call-graph fp`. PMU counter output was discarded because its relative error
was unusable. The call graphs consistently put the dominant cost after line
scanning: Maple GC tracing/forwarding, parser allocations, string validation,
and `collectReferences`; the C scanner is a minor share.

Several bounded experiments were measured and reverted because they were not
safe cross-profile improvements: an extra reference flag, a special-character
gate, native malloc records, 32-bit packed records, and a reduced record
capacity estimate. Some improved CommonMark-only samples, but the GFM paired
controls showed regressions or could not separate the effect from load phase.
The final source remains the previously validated `uwv` implementation, with
no unverified performance patch. This does not change the blocked status of
`MD-PERF-002`.

## 2026-08-18 Remote Release Benchmark Rerun

The complete release harness was rerun on the idle authorized SSH Server from
the pushed `f13b8a3` snapshot. Environment: Linux 5.15, Xeon Gold 6248R,
CPU 24, performance governor, glibc 2.35, Cangjie `-O2`, heap 2GB, 7 samples
and 3 iterations per sample. The harness exited 1 with the following gates:

- CommonMark geometric mean: `4.084x` — fail (`2.5x` limit).
- GFM geometric mean: `3.229x` — fail (`2.5x` limit).
- Ordinary representative ratios: CommonMark `3.875x`, GFM `2.957x` — pass (`5x` limit).
- Scaling slope `0.989`, maximum adjacent growth `2.103` — pass.
- Pathological slope `1.237` — pass; maximum adjacent `4.337` is informational.
- 10 MiB extra RSS `68288 KiB` — pass (`81920 KiB` limit).

The raw report and per-corpus samples are in
[`docs/reports/benchmark-raw.json`](../docs/reports/benchmark-raw.json), with
the generated summary in [`docs/reports/benchmark.md`](../docs/reports/benchmark.md).
The result confirms `MD-PERF-002` remains `blocked`; no threshold was changed.

## 2026-08-19 InlinePiece Allocation Candidate

The next bounded candidate changed `InlinePiece` in `src/parser.cj` from a
per-fragment class allocation to a value struct while retaining the mutable
`InlinePieceLink` delimiter chain. The candidate passed format, check, both
builds, and the complete local test suite (`1410/1410`). On the fixed Server
CPU 24 and the same pinned SDK, a 12-round alternating 1 MiB paired run had
matching checksums and only a modest median improvement: CommonMark
`0.4761775515` to `0.470497035` (`1.207%`), GFM `1.3829321625` to
`1.3663628375` (`1.213%`). The paired JSON SHA-256 is
`da1f7157c34ae124d71e1d4354fadca6545a3b0cb92f6be392f1c2217d5d5296` and the
candidate archive SHA-256 is
`f4e0a5c34b4a35c6cb07bc278a3cb3c8904365676145f8b426118cea45c99992`.

The complete release harness for this candidate was started but the SSH
Server actively closed the connection before its raw report could be read.
No release ratio, scaling, or RSS result is inferred from the paired run or
from local profiling. `MD-PERF-002` therefore remains `blocked`; no threshold
was weakened. The local profile still points to string validation, the C line
scanner, Maple GC/reference copying, and parser allocation as the next
hotspot classes. At that time the foreign scanner still carried `@FastNative`
and no long parser/GC path was annotated. A 2026-08-22 audit later removed the
scanner annotation because whole-input call duration could not be proven short
and bounded, despite the C implementation having no I/O, locks, or Cangjie
callbacks.

An additional `InlinePieceLink` indexed-struct rewrite was tested locally and
passed all `1410/1410` tests, but a fixed-CPU six-round run with 100 parses per
sample had median paired ratio `1.0434` and candidate speedup `0.9897`.
Because this did not establish a stable cross-profile gain, it was reverted;
the pushed candidate contains only the smaller `InlinePiece` value-struct
change.

## 2026-08-19 Current Candidate Full Release Rerun

The current `perf-cffi-scan` archive was rebuilt on the authorized `Server`
using CPU 24, Linux 5.15, Xeon Gold 6248R, Cangjie
`1.1.0-alpha.20260803040049`, `-O2`, and a 2 GiB heap. The archive SHA-256 is
`dc5f5dc6f12d5567e26efb028bf3d4e87cd0cb3aa5bcac598bccb98a0a33754b`; the
remote driver SHA-256 is
`f1e0431ed96ebe9eaab640787d2921ece2765c5c538c1d2fe3814077a330443f`.
The harness used 7 samples and 3 iterations and exited `1` after writing the
raw report. Its fetched report SHA-256 is
`f88ec9fa944411df4aaa560d1e9dd9fd51d240704ca3543c188c316023204ae1`.

The measured gates are:

- CommonMark geometric mean `6.980369x`: fail, limit `2.5x`.
- GFM geometric mean `5.989632x`: fail, limit `2.5x`.
- Ordinary representative ratios `3.512038x` and `2.709449x`: pass, limit `5x`.
- Scaling slope `0.923963`, maximum adjacent `1.955930`: pass.
- Pathological slope `0.962821`: pass.
- 10 MiB extra peak RSS `80120 KiB`: pass.

SourceMap overhead was `112.16%` and CST overhead `1038.97%`. The canonical
raw report is now stored at
[`docs/reports/benchmark-raw.json`](../docs/reports/benchmark-raw.json), with
the summary at [`docs/reports/benchmark.md`](../docs/reports/benchmark.md).
`MD-PERF-002` remains `blocked` solely because the CommonMark and GFM ratio
gates fail.

## 2026-08-19 Parser/reference-index optimization

The authorized `Server` was rerun with CPU 24 and the pinned Cangjie
`1.1.0-alpha.20260803040049` SDK. PMU profiling remained unavailable because
`perf_event_paranoid=4`; no hardware-counter claim is made. The retained
candidate adds a per-parse effective-reference hash index, uses it for both
reference resolution and delimiter link detection, and fast-paths labels that
are already trimmed lowercase ASCII. At that time the existing scanner still
used `@FastNative` and was not expanded. A 2026-08-22 audit later removed that
annotation because a whole-input byte loop has input-dependent total duration;
the native archive boundary remains, and the C implementation still performs
no I/O, locks, or Cangjie callbacks.

The final cjfmt-normalized candidate archive SHA-256 is
`1162a0350b22efbeb969279ad89d2b4898b3a8612cbcb5aedbdf26abfd072845`; the
12-round alternating 1 MiB result SHA-256 is
`4df43fc1dba76d6189bd690252e65fbd08b0aea05110501bb75734a1331682f8`.
Checksums matched for every paired corpus. Candidate speedups were measured
for CommonMark/GFM respectively: ordinary `1.162x`/`1.032x`, many references
`1.268x`/`1.157x`, large table `1.035x`/`0.996x`, pathological `1.010x`/`1.017x`,
and CJK `1.016x`/`1.002x`.

The candidate passed the complete `cjpm test` gate (`1410/1410`, zero
skipped/errors/failures). The complete release harness still exited `1`:
CommonMark `6.137x`, GFM `5.459x`, normal scaling slope `0.877`, pathological
slope `1.402`, and extra RSS `80600 KiB`. A same-SDK paired baseline exited
`1` at `6.945x`/`5.670x`; this demonstrates a real relative improvement but
does not satisfy the PRD's 2.5x ratio or pathological slope limits. The
requirement therefore remains `blocked`, and the final status remains
`INCOMPLETE`.

## 2026-08-21 S0 Reference URI Attribute Cache Rejection

The bounded per-render reference URI attribute cache candidate was built on
the pinned Server SDK and compared on CPU 24 against the retained direct
reference-link renderer. The candidate and baseline driver SHA-256 values were
`70e51613b2d7bf4689d215e4f131e32a5afc8cdbb1394b6c7cc1239c0967c924` and
`d4e7fa6f6cf53d72b6a59ad66daff43457df8da1580e97764d543d899e04ff18`.

Two independent 1 MiB, 12-round alternating runs used all 11 benchmark corpora
and reversed the initial order in the second run. Their raw JSON SHA-256 values
are `8dd1a38961bd3deff4dfbfe103bb5fe6620ea7239355afb6b6b3087cc7d6055d`
and `1a45f6e495962ab4bb10c1695b6bddd4e76a22c69e46fd8aedde905e531ed18c`.
Every checksum matched, but many-reference GFM was `0.97497` and `0.97300`
against a required maximum of `0.95`; GFM geomean was `1.01269` and `0.99982`
against `0.98`. The candidate therefore failed the frozen stop/go gate.

The cache, helper, parameter propagation, and three cache-only tests were fully
reverted. The retained renderer SHA-256 is again
`cc0e4fe45cc4544c7cade20d5fda744a95446cab8aebd2e74d4b32fc1a8fb26c`.
Format and check passed, the socket-enabled full suite passed `1411/1411`, and
the API checker passed 8 regression tests plus the 1155-declaration snapshot.
Per the frozen protocol, no formal release benchmark was run and the canonical
benchmark reports were not overwritten. The last formal ratios remain
CommonMark `4.329382x` and GFM `3.276393x`, so `MD-PERF-002` remains `blocked`.

The final workspace audit also found that the pre-existing current
`docs/reports/benchmark-raw.json` is a local CPU 2 Arch run (SHA-256
`adecf410140ed0bfc65528473fadd7cba6b2c458a438b88dfa021bafa6b05f8b`,
CommonMark `4.579341x`, GFM `3.968396x`), not the authorized Server evidence.
This S0 implementation did not modify that file and does not use it to replace
the last validated Server result. A future successful formal Server run must
reconcile the canonical report and ledger together.

## 2026-08-25 Product Name Normalization

The repository, product, root package, public namespace, CLI command, current
documentation, and historical in-repository records now consistently use
`markdown`. The CLI project moved to `tools/markdown`; its internal
`markdown_cli` package name only distinguishes it from the root dependency.
The external comparator `markdown4cj` retains its official name.

The generated `tools/markdown/build-script-cache` was removed after validation,
and the repository now ignores `**/build-script-cache/` recursively so nested
CLI and example builds cannot reintroduce host-specific prebuild binaries.

The migration updated labels and report schema field names without changing
stored benchmark samples or ratios. The post-migration SHA-256 values are
`a107300090f599152ffd8e9020465666ed1b3b91c7e2fccd783ddcfc29d897d9` for
`benchmark-raw.json`, `a8387ff89585a32eb445cb82e02e7732226875c141f4d8bd10c8db5a6f48e590`
for `benchmark.md`, `6d67ac4a9db3d6a64aaebfeb56d498658a3a248ecbf2787aa87889a03ac882a7`
for the same-language raw report, and
`a6faf8d59555294552ce8ec603c072b858b447730ede6978d62bb389d1fe78ef`
for its rendered report.

The legacy product-name scan returned no source, documentation, report, or
ledger matches. Python compilation, YAML/JSON parsing, format, root package
check, CLI release build and smoke, 8 API-checker tests, the 1155-declaration
snapshot, and the socket-enabled full suite all passed; the latter executed
`1410/1410` tests. This branding change does not alter the existing overall
`INCOMPLETE` verdict or the blocked performance gate.

## 2026-08-25 P0 Correctness and Resource Contract Acceptance

The construction path now enforces AST-node and accumulated literal limits
before the next oversized allocation. Built-in parsing and Parser SPI node IDs
share the bounded allocator. Multiline fenced code, HTML, extension literals,
inline literals and merged text are covered by targeted attack regressions.

Fingerprint preimages now use typed length-prefixed fields. Adversarial field
splits, all former delimiters, Unicode, empty fields, manifest registration
order, semantic rule order, renderer policy fields, engine identity and binary
AST semantics are no longer represented by ambiguous delimiter concatenation.

HTML SourceMap ranges are emitted with renderer writes, so generated tag bytes
cannot capture visible text mappings; point queries use binary search. Artifact
schema v1 now rejects non-identity UTF-8 replacement mappings before encoding,
including the `[0xFF]` versus encoded `U+FFFD` identity ambiguity.

Final local evidence: `scripts/check_format.sh`, `cjpm check`, `cjpm build`, the
8 API checker tests and the 1155-declaration public API snapshot all exited 0.
The final socket-enabled full suite exited 0 with `1413/1413` passed and no
skips, errors or failures. No canonical benchmark report was overwritten by
this correctness slice.

The overall verdict remains **INCOMPLETE**: version `0.8.0`, hosted CI and the
single `release-evidence.json` are implemented, but the canonical benchmark is
still `stale-unbound`. Performance, release and quality requirements remain
blocked in the authoritative ledger until a clean committed candidate is rerun.

## 2026-08-25 Safe Renderer Hardening Acceptance

Data-image MIME allowlisting now compares the complete media type before URI
parameters instead of accepting string prefixes. Safe external `_blank` links
always include deduplicated `noopener noreferrer`; compatibility renderers keep
their prior output contract. The targeted regression and the complete
socket-enabled suite passed, with `1418/1418` tests and no skips, errors or
failures. Public API signatures are unchanged.

## 2026-08-25 Arbitrary-byte Fuzz Acceptance

The deterministic byte corpus now covers both UTF-8 policies and varied chunk
partitions. It found invalid UTF-8 slicing in GFM email autolinks and HTML block
ASCII normalization; both paths now preserve decoded UTF-8 boundaries. The
targeted regression and complete suite passed with `1419/1419` tests and no
skips, errors or failures. The parser benchmark smoke also passed `3/3`; it is
not treated as canonical release-performance evidence.

## 2026-08-25 Optional Native and Execution Surface Acceptance

The core package now has no foreign declaration or linker option. A fresh
default build completed with deliberately nonexistent `CC` and `AR` paths;
the C scanner is available only through the `markdown.native` package and an
explicit `AcceleratedMarkdownEngine`. The target-aware build helper passed
4/4 Linux, MinGW and MSVC command-contract tests. On the available Linux host,
the archive and benchmark consumer linked successfully. Other target families
still require their real SDK/linker release runners; no cross-platform result
is inferred from mocked command tests.

Stream, chunk, partial/failure and async-output APIs now expose their buffered
execution contracts in names, documentation and `ExecutionModelCapabilities`.
They do not claim completed-prefix parsing, early AST production, or reduced
peak memory. Curated `markdown.core`, `render`, `extensions`, `editor`,
`artifact`, `document` and `testkit` packages reduce new-consumer imports while
the root package remains the compatibility umbrella. Internal-only
`NodeIdAllocator` and `Sha256` were removed from the public snapshot, which now
contains 1192 declarations.

The native scanner gate completed 10,000 coverage-guided libFuzzer runs and
the deterministic ASan/UBSan harness with no sanitizer finding. Four seed
files and the minimized historical invalid-UTF-8/GFM crash input are checked
in and replayed. Final format, check, pure/native/consumer builds, CLI smoke,
8/8 API-checker tests, 4/4 build-helper tests, 2/2 input-profile tests and the
full `1423/1423` Cangjie suite passed.

The overall verdict remains **INCOMPLETE** with 122/125 requirements passing:
`MD-PERF-002`, `MD-REL-001` and `MD-QUAL-001` remain blocked. This slice did not
replace the canonical remote release benchmark.
