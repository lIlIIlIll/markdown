# markdown 最终验收报告

## Final Status

**INCOMPLETE** — 122/125 项为 `pass`；3 项在 README benchmark corpus 变化后等待新的 canonical benchmark 和完整 release gate。

<!-- release-evidence:start -->
## Generated Release Evidence

- Version/status: `0.9.0` / `incomplete`.
- Artifact commit: `a259ba4904357d3ca393ca7ccaddce9e6da11931`.
- Evidence subject commit: `a259ba4904357d3ca393ca7ccaddce9e6da11931`; the retained execution manifest binds the clean gate commit and Git tree.
- Hosted CI verified at that HEAD: `False`; published: `False`.
- Tests: `1457/1457` passed, `0` skipped, `0` failed.
- Benchmark: CommonMark `2.27x`, GFM `2.27x`, status `stale-source-drift`.
- Raw digest: `b80123a494932c2c1b7f63fb6895ab81c9734564141f8099d9a2c6b8f8fa136f`.

One or more mandatory offline evidence gates remain incomplete. Hosted CI and publication remain separate claims.
<!-- release-evidence:end -->

## 2026-08-30 Current Documentation Evidence Repair

README、CHANGELOG 和性能页的当前测试、API 与 benchmark 数字已由 `release-evidence.json` 统一生成。该修复改变了 `readme-api` corpus，旧 canonical raw 不再证明当前文档输入。`MD-PERF-002`、`MD-REL-001` 和 `MD-QUAL-001` 暂为 `implemented_unverified`；只有新的固定 Server canonical 与完整 release gate 通过后才能恢复 `COMPLETE`。

本报告后续按时间保留历史失败、候选淘汰和当时的完成记录；这些历史段落不覆盖上述当前状态。R139/R140 仅作为历史证据保留。

## 2026-08-30 Current Audit Closure

固定 product commit `a259ba4904357d3ca393ca7ccaddce9e6da11931` 的 latest-complete Server canonical raw SHA-256 为 `b80123a494932c2c1b7f63fb6895ab81c9734564141f8099d9a2c6b8f8fa136f`。verifier 从底层 samples 独立重算 CommonMark `2.274715x`、GFM `2.267811x`、scaling、pathological、RSS 和全部 gate，派生误差为空。受测最小源码归档排除了 `.agent`、`.agents`、`.codex` 和全部构建产物。

clean full release gate exit `0`：format、docs `44/23/4`、native cache tests `5/5`、evidence tests `15/15`、bundle tests `4/4`、API checker `9/9`、API snapshot `1323`、check/build、native ASan+UBSan fuzz `10000`、full tests `1457/1457`、CommonMark `652/652`、GFM `671/671`、CLI、quickstart、cookbook、differential `25/24/1/0`、benchmark smoke `3/3`、bundle 与 evidence-ready verifier 全部通过。

`target/release-evidence/manifest.json` 绑定干净执行 commit/tree 和当前 daily SDK archive SHA-256 `6c050802d1d6d297c4c6ad2bf8b253865f33aa2a810f6ef62347162f1e18131d`，保留每步 argv、工作目录、exit code 和日志，并从 JUnit、API inventory 与 raw samples 派生声明；候选包、源码 tar、raw/report 和全部 retained files 均由 `target/release-evidence/SHA256SUMS` 覆盖。Hosted CI、远端发布和 package registry publication 仍是独立事实，不由本地 COMPLETE 结论暗示。

## 2026-08-29 Current Completion Evidence

当前修复增加 schema-v3 benchmark identity：release verifier 会重新生成 corpus，逐项检查 inventory、byte length 和 SHA-256，并比较 raw、release evidence 与当前 benchmark product tree。旧 raw 因 `readme-api` 和 product tree 漂移被确定性拒绝。

开发者文档现使用实际公开 API `node.nodeId`、`node.children()` 和 `NodeChildren`；artifact 文档说明只有实际无效 UTF-8 replacement 才产生 non-identity mapping。当前清点为 public API 1309 declarations、44 个 Markdown 文件、23 个 required API entries、4 个 runnable examples、41 个 assumptions。

当前 canonical 从 product commit `c63c52528aef6cc5ea46d4b152e08af6a5344f2f` 的最小源码归档在 Server 全新目录构建。raw SHA-256 为 `ecb844e71fdf8532b37f92a38c20ef2b77ad7e9941a7f9a31da4224cf6e73d37`；CommonMark `2.334095x`、GFM `2.466373x`，ordinary `3.538540x/1.994487x`、scaling `0.349193/1.514705`、pathological `0.700414/2.187767`、extra RSS `31224 KiB`，全部 gate 通过。A-038 的 latest-complete 规则继续生效，没有挑选历史最好值。

当前完整 release gate 在 Cangjie `1.1.0-alpha.20260829040003` 下 exit `0`，覆盖 format、docs `44/23/4`、native build contracts `4/4`、API checker `9/9`、API snapshot `1309`、check/build、ASan+UBSan fuzz `10000`、full tests `1455/1455`、CLI、quickstart、cookbook、differential `25/24/1/0`、benchmark smoke `3/3`、bundle 和 evidence-ready verifier。发布候选包为 `494310` bytes，SHA-256 `7d6c3d9800d9b9757df83ced7bfb179d056d17e89599624c47e3a38c3f44b3f6`。

## 2026-08-29 Historical Release Audit Remediation

审计报告的九项发现已按当前仓库逐项复核。产品侧修复包括：固定官方 1.1.0/1.1.3 SDK 与 checkout commit 的 CI matrix、完整 release gate、自包含 pinned differential references、buffered API 破坏性改名、`OperationBudget` 并发合同，以及区分 offline evidence、hosted CI 和 publication 的 release evidence schema v2。

当时的最终命令 `cangjie_env; CC=clang AR=ar scripts/release_gate.sh` exit `0`。门禁实际覆盖 format、docs `43/23/4`、public API `1309` declarations、check/build、native ASan+UBSan fuzz `10000`、full tests `1455/1455`、CommonMark `652/652`、GFM `671/671`、differential `25/24/1/0`、benchmark smoke `3/3`、bundle 和 evidence-ready verifier。该结果现为历史证据，不替代当前 schema-v3 rerun。

当时 `release-evidence.json` 保持 `ciVerifiedAtHead=false` 与 `published=false`。独立 hosted 证据为 run `33234237046`：commit `e8d486f20e624159c2da043e574169f9da4250dd` 的 SDK 1.1.0/1.1.3 完整 gates 均成功。该分支后来已合入 `main`；本段只保留历史追踪，不描述当前分支保护或发布状态。

## 2026-08-29 Historical Developer Documentation Acceptance

README、开发者文档首页、入门教程、六组 API reference、扩展作者文档、迁移指南和贡献指南已按当前 0.9 公开 API 与默认行为重写。`scripts/check_docs.py` 对 40 个 Markdown 文件、相对链接、code fence、旧产品名和 23 个核心 API 入口检查通过，并已加入 release gate。

当时的验证结果：public API snapshot `1311` declarations、release evidence、format、`cjpm check`、根 build、quickstart build/run 全部 exit `0`；授权环境 full suite exit `0`，`1455/1455` passed，0 skipped/error/failed。当前公开 API inventory 为 `1309`，以本报告顶部的独立审计修复为准。

### Usability follow-up

README 和文档首页现按“首次运行、按任务复制、按符号查 API”组织；新增 task-led cookbook、故障排查、API 速查和可运行 `examples/cookbook`。审计发现原示例错误地从 `HeadingNodeView` 直接读取 span；当前文档和示例已统一使用 `heading.node.span`，并由 docs gate 防止回归。

当时 `scripts/check_docs.py` 验证 `43` 个 Markdown 文件、`23` 个核心 API 入口和 `4` 个 runnable example 文件。当前 inventory 为 44 个 Markdown 文件；R139 `2.380950x` / `2.454213x` 已降为历史数字，不能再作为当前 canonical 结果。

## 2026-08-27 Parser Phase Evidence

R17 eliminated redundant link-target string validation after the target scanner had
already observed whether decoding was necessary. R20 added a versioned native line
record delimiter bit and an isolated delimiter-free inline materializer; legacy v1
accelerators remain conservative and unsupported formats fail closed. Fixed Server
CPU 24 bidirectional R20/R17 measurements preserved checksums. Forward ratios were
`0.970483` CommonMark parse, `0.996234` CommonMark HTML, `0.951194` GFM parse and
`0.985218` GFM HTML; reverse-normalized ratios were `0.966195`, `0.985243`,
`0.980318` and `0.996376`. The retained target improvements are about 9% on CJK and
many-reference parse workloads.

Local validation passed `1444/1444` tests, `9/9` API-checker tests, the 1277-declaration
v0.9 public API snapshot, and 1000 coverage-guided native scanner runs with ASan and
UBSan clean. The full format gate still reports only the pre-existing/shared
`src/ast_test.cj` formatting drift. This phase evidence intentionally does not replace
the canonical release benchmark; `MD-PERF-002`, `MD-REL-001` and `MD-QUAL-001` remain
blocked until the full current-source release ratios satisfy the PRD threshold.

R21 subsequently made delimiter-free text coalescing conditional on an actual
Text-producing escape/entity/backtick lowering. Bidirectional R21/R20 aggregate
ratios were `0.954436`/`0.948190` CommonMark parse, `0.977939`/`0.983093`
CommonMark HTML, `0.975448`/`0.959328` GFM parse and `0.986151`/`0.984167`
GFM HTML; full tests passed `1445/1445`. R22's attempted single-line paragraph
child-array transfer was rejected after it provided less than 1.1% parse gain,
did not improve CommonMark HTML, and produced a reverse ordinary HTML regression.
The parser was restored byte-for-byte to retained R21.

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
| `pass` | 125 |
| `implemented_unverified` | 0 |
| `pending` | 0 |
| `blocked` | 0 |

## Itemized Verdict

| ID | Source | Status | Evidence / reason |
| --- | --- | --- | --- |
| `MD-GOV-001` | PRD §1, §4, §54.1-7 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-002` | PRD §6.1, §11.4, §48.3, §54.3-6 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-003` | PRD §6.2, §24.1, §54.7, §54.30-31 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-GOV-004` | PRD §6.3, §10.1-2, §54.8-10 | `pass` | 0.9 arena/value-view main path and explicit fused execution are implemented; the misleading AST-walk Event adapter was removed and the real source Event API is tracked separately for 1.1. |
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
| `MD-AST-001` | PRD §20.1, §42.4, §54.25 | `pass` | Document-owned chunked arena, NodeRef, typed value views, compact origin metadata and consumer migration are implemented and full-suite verified. |
| `MD-AST-002` | PRD §20.2-3 | `pass` | The 0.9 arena/value-view representation is the sole runtime AST; parser, renderer, transforms, editor, artifact and traversal no longer depend on the 0.8 object tree. |
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
| `MD-EVT-001` | PRD §27, §54.10 | `pass` | Source-driven Resolved mode performs reference collection before transient block lowering; RawBlock sessions emit closed blocks across arbitrary UTF-8 chunks with non-final semantics; event values retain no Document/NodeRef. Focused 7/7 and full 1454/1454 tests pass, and explicit fused/full execution tests remain green. |
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
| `MD-PERF-002` | PRD §45.4, §51.7, §52 | `pass` | Current fixed-Server canonical is identity-bound and passes CommonMark 2.334095x, GFM 2.466373x, ordinary, scaling, pathological and RSS gates. |
| `MD-PERF-003` | PRD §45.5 | `pass` | 2026-08-18: owned byte input, SourceSlice literals, explicit parser frames, bounded output, ordinary/pathological scaling, and RSS tests passed |
| `MD-OBS-001` | PRD §46 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DOC-001` | PRD §47, §49, §51.7 | `pass` | 2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed |
| `MD-DOC-002` | PRD §47, §49, §51.7 | `pass` | 2026-08-18: examples/quickstart built and ran using only the public package API |
| `MD-COMP-001` | PRD §48.1-2 | `pass` | The 0.9 API snapshot verifies 1309 declarations; migration and compatibility docs include the buffered API breaking cleanup. |
| `MD-COMP-002` | PRD §48.3-6 | `pass` | SPI v2, artifact v2 and the final 0.9 AST surface are snapshotted and tested; the removed AST-walk Event facade is explicitly excluded from the stable contract. |
| `MD-REL-001` | PRD §49, §50 M6, §51 | `pass` | The complete release gate passes through bundle and evidence-ready verification; hosted CI and publication remain separate claims. |
| `MD-QUAL-001` | PRD §51.7, §52 | `pass` | Current correctness, compatibility, security, consumer, conformance and performance gates all pass. |

## Validation Evidence

The first two rows are authoritative. Later rows are retained as historical
slice or rejection evidence and do not replace the current result.

| Command | Exit | Result |
| --- | ---: | --- |
| Server CPU 24 `MARKDOWN_BENCH_* python3 benchmarks/measure.py` on clean commit `c63c525` | 0 | CommonMark 2.334095x, GFM 2.466373x; every timing, scaling, pathological and RSS gate true; raw SHA-256 ecb844e7...73d37 |
| `/home/elliot/.codex/scripts/codex_cangjie_env --cwd /home/elliot/playground/markdown -- scripts/release_gate.sh` | 0 | format; docs 44/23/4; native build 4/4; API checker 9/9; API 1309; check/build; native ASan+UBSan fuzz 10000; tests 1455/1455; CLI; both consumers; differential 25/24/1/0; benchmark smoke 3/3; bundle; evidence-ready; final output `release gate: pass` |
| Historical R140 Server fresh archive `CC=/usr/bin/clang AR=/usr/bin/ar scripts/release_gate.sh` | 0 | format; API 1311; check/build; native ASan+UBSan fuzz 10000; tests 1455/1455; CLI; quickstart; differential 25/24/1/0; benchmark smoke 3/3; bundle; historical release-ready verifier |
| `python3 scripts/test_benchmark_input_profiles.py` | 0 | 7/7, including generated-evidence corpus stability, fail-closed marker validation and runtime/driver optimization identity |
| `python3 scripts/release_evidence.py --evidence-ready` | 0 | offline artifact, archive, SDK, harness, drivers, raw digest, ratios and generated projections are consistent; hosted CI/publication are explicitly false |
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
| historical `python3 scripts/release_evidence.py --release-ready` | 1 (expected) | pre-R139 draft evidence correctly failed closed; superseded by the passing current row above |
| `python3 scripts/differential_test.py` | 0 | 25 comparisons: 24 exact, 1 classified, 0 unexpected |
| `cjpm bench --filter MarkdownReleaseBenchmarks ...` | 0 | 3/3 benchmark smoke cases; socket permission required |
| remote `python3` wrapper importing `benchmarks/measure.py` on authorized SSH Server (CPU 24) | 1 | 2026-08-19 final candidate: CommonMark 6.137x, GFM 5.459x, ordinary/scaling and RSS gates pass, ratio and pathological slope gates fail; same-SDK paired baseline 6.945x/5.670x |
| `MARKDOWN_BENCH_CPU=24 ... python3 benchmarks/measure.py` on authorized SSH Server | 1 | 2026-08-20 current candidate: CommonMark 5.261x, GFM 4.129x; scaling, pathological and RSS gates pass; only both 2.5x ratio gates fail; raw SHA-256 9ac920...8573 |
| `MARKDOWN_BENCH_CPU=24 ... python3 benchmarks/measure.py` on authorized SSH Server | 1 | 2026-08-21 retained candidate: CommonMark 4.469x, GFM 4.028x; scaling, pathological and RSS gates pass; only both 2.5x ratio gates fail; raw SHA-256 aaac470...0e03 |
| `MARKDOWN_BENCH_CPU=24 ... python3 benchmarks/measure.py` on authorized SSH Server, per-corpus alternating pairs | 1 | 2026-08-21 current renderer/reference-link candidate: CommonMark 4.329x, GFM 3.276x; slope 0.961, adjacent 2.400, pathological slope 0.866, RSS 59632 KiB pass; only both 2.5x ratio gates fail; raw SHA-256 1a6bc4...c011 |
| `python3 /tmp/markdown_pair_link_attribute_cache.py baseline-first ...` on Server CPU 24 | 0 | S0 run 1 checksums matched; many-reference GFM 0.97497 and GFM geomean 1.01269 failed 0.95/0.98 stop-go limits; raw SHA-256 8dd1a3...055d |
| `python3 /tmp/markdown_pair_link_attribute_cache.py candidate-first ...` on Server CPU 24 | 0 | S0 run 2 checksums matched; many-reference GFM 0.97300 and GFM geomean 0.99982 failed 0.95/0.98 stop-go limits; raw SHA-256 1a45f6...d18c |
| historical 2026-08-18 `scripts/release_gate.sh` | 1 | failed closed at the then-current performance gate; superseded by R140 exit 0 above |
| `cjpm bundle --skip-test` after the full 1410-test gate | 0 | target/markdown-1.0.0.cjp; 343528 bytes; SHA-256 aab2e233b88b495c0221eb36e673c0d6a19184721b1776620525283098882529 |
| `cjpm test --no-color --no-progress --report-path /tmp/markdown-p0-final-tests-2 --report-format xml` | 0 | 1413 passed, 0 skipped/error/failed |
| `cjpm bundle --skip-test` for 0.8.0 | 0 | target/markdown-0.8.0.cjp; 374 KiB; SHA-256 8782dcc16ea5063e70e51ac74efdbc87c33fdd19885beaa63feeebfb67cfd527 |
| `cjpm test --no-color --no-progress --report-path /tmp/markdown-p1-input-profile-full-tests --report-format xml` | 0 | 1414 passed, 0 skipped/error/failed |
| `cjpm test` (2026-08-25 indexed SourcePositionMap full rerun) | 0 | 1415 passed, 0 skipped/error/failed; indexed CRLF/Unicode/replacement/checkpoint case passed |
| `cjpm test` (2026-08-25 shared CST arena full rerun) | 0 | 1416 passed, 0 skipped/error/failed; arena ranges, defensive copy and query indexes passed |
| `cjpm bench --filter MarkdownReleaseBenchmarks --no-color` (after CST arena change) | 0 | 3/3 benchmark smoke cases passed; not canonical performance evidence |
| `cjpm test` (2026-08-25 SemVer final rerun) | 0 | 1417 passed, 0 skipped/error/failed; prerelease/build/invalid/overflow cases passed |

## Final Bidirectional Audit

- PRD → requirements: the complete 3754-line PRD was reread. All 52 normative
  sections are covered; sections 2, 3 and 5 are descriptive summary/background/
  vision. All 33 explicit `IN`/`PAR`/`AST`/`SEC` IDs are mapped.
- requirements → implementation/tests: 125 stable IDs are unique and all 125 are
  `pass`. Every required field and acceptance list is non-empty. The ledger has
  488 concrete implementation/test path references, all of which exist, and no
  generic `src/*_test.cj` placeholder remains.
- current execution evidence: R139/R140 are historical. The schema-v3 canonical
  run is bound to source commit, archive, product tree, corpus, SDK, harness and
  drivers; both mandatory performance ratios and every non-ratio gate pass. The
  complete release gate also exits 0.
- assumptions: 41 assumption IDs are unique, all are resolved/adopted or
  explicitly non-normative, and every assumption is referenced from the notes of
  its affected ledger items. The verified private vulnerability channel is no
  longer recorded as blocked.
- placeholder audit: product and CLI sources contain no `TODO`, `FIXME`,
  `unimplemented`, `not implemented`, `panic(` placeholder, and tests contain no
  `@Skip` or `@Ignore` marker.


## Release Decision

**COMPLETE.** The 0.9.0 breaking pre-GA preview is offline evidence-ready. All
125 requirements pass, the latest complete canonical satisfies both `2.5x`
thresholds, and the complete release gate exits 0. No waiver, threshold reduction
or best-of-reruns selection is used. Hosted CI verification and publication remain
explicitly separate claims.

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

## 2026-08-25 Previous Canonical Release Benchmark Acceptance

The previous canonical remote release benchmark bound product commit
`0275f27a1d8fea38262127b245ca5e4c81c9b3a8`, Cangjie SDK
`1.1.0-alpha.20260803040049`, the minimal source archive, benchmark harness,
markdown release driver, and both reference drivers. The frozen CommonMark and
GFM corpus digests match `release-evidence.json`; the raw report SHA-256 is
`1b025514500df45128e92a5fb72c77897773222e72f98e95c72db1ee89e23f57`.

The full fixed-CPU run exited `1`: CommonMark parse-only measured `5.842342x`
versus cmark and GFM parse+HTML measured `4.982426x` versus cmark-gfm. Ordinary
ratios, normal and pathological scaling, adjacent growth, and 10 MiB additional
RSS all pass. Only the two mandatory `2.5x` ratios fail. SourceMap overhead was
`2.31%`; CST/snapshot overhead was `1040.41%`.

Therefore `MD-PERF-002`, `MD-REL-001`, and `MD-QUAL-001` remain `blocked`, and
the final status remains **INCOMPLETE**. No threshold or assertion was weakened.

## 2026-08-25 Trusted Owned UTF-8 Fast Path and Canonical Acceptance

Profiling attributed about `24.49%` of the ordinary owned-input workload to
redundant UTF-8 validation. Product commit
`34113ea6f47a3bcd57b80ca9ee5c6063873dd5bb` now uses the existing
trusted-valid, ownership-transfer contract of `OwnedUtf8Input.take` to create
its source string with `unsafe { String.withRawData(bytes) }`. Safe byte,
stream, Strict and ReplaceInvalid entry points retain their validation and
replacement behavior. Assumption A-034 records the validity and aliasing
preconditions rather than silently broadening the unsafe surface.

The final fixed-CPU product A/B preserved all output checksums and measured
candidate/baseline ratios of `0.921434` for CommonMark and `0.964209` for GFM;
reverse-order confirmation measured `0.909810` and `0.954436`, while the
baseline/baseline A/A ratios were `0.997942` and `1.002247`. Format, package
check, 8/8 API checker tests, 3/3 input-profile tests, 3/3 release-evidence
tests and the socket-enabled `1423/1423` full suite passed.

The historical 2026-08-26 remote release run was bound to workspace commit anchor
`2454b0626c2fb0fe590a59bc1f79a8d4e864c856`, exact source archive SHA-256
`621d01282d0dedbf736d874a18841658297f8e45142bc11f9a30855afff92a00`,
the frozen corpora, SDK, harness and all three drivers. Raw SHA-256
`76f6e5e873ac1526d1f54ed350483cda46d3d3c9e534529a39326b9f068391db`
measured CommonMark `5.768261x` and GFM `4.265438x`. Ordinary ratios, scaling,
pathological scaling and RSS pass; only the two mandatory `2.5x` ratio gates
fail. The evidence tree is explicitly dirty; the archive and driver hashes are
the exact tested identity until these changes are committed.

At this historical checkpoint the ledger was 116/125 pass, with 4 pending, 2
implemented_unverified and 3 blocked. The current summary at the top of this report supersedes it.
No gate, assertion or benchmark profile was weakened.

## 2026-08-27 Reusable Input and Canonical Acceptance

`ReusableUtf8Input` validates and defensively copies once, or accepts an
explicit unsafe ownership transfer, then exposes immutable storage to repeated
full-AST parses. Canonical CommonMark/GFM modes now reuse that buffer while
still creating the complete arena AST, NodeId, SourceSpan, SourceBuffer and
ParseResult every iteration. String, byte array, owned bytes, reusable bytes
and stream inputs remain separately reported.

The fixed Server bidirectional promotion guard preserved checksums. Forward
R24/R21 ratios were `0.949117`, `0.998415`, `0.984257` and `0.994762` for
CommonMark parse/HTML and GFM parse/HTML; reverse-normalized ratios were
`0.943764`, `0.989614`, `0.982903` and `0.986682`. R21/R21 A/A quantified the
remaining drift. Full local tests passed `1446/1446`, API checker tests passed
`9/9`, input-profile contracts passed `4/4`, and the public API snapshot
verified `1281` declarations.

The R24 canonical raw at that checkpoint was SHA-256
`257d20140685382cdf3d1b95a67db3d54aa02c0c514e88bf7a5c71714ac2b502`.
It binds the exact source archive, corrected harness, candidate driver, SDK and
both frozen reference drivers. CommonMark is `4.859602x` and GFM is
`4.329331x`; ordinary, normal/pathological scaling, adjacent growth and RSS
all pass. The two mandatory `2.5x` ratios fail, so `MD-PERF-002`,
`MD-REL-001` and `MD-QUAL-001` remain blocked and the final status remains
**INCOMPLETE**. It has now been superseded by the R29 canonical result below.

## 2026-08-27 Post-R24 Candidate Audit

Perf on the reusable-input canonical driver attributed `24.51%` of ordinary
samples to the native line scan, `22.06%` to GC phase transition and `4.17%`
to the full-input reference precheck. Three isolated candidates were evaluated
with the same fixed Server CPU and exact R24 baseline:

- R25 runtime AVX2 scanning regressed ordinary GFM parse by `24.6%` and target
  profiles by as much as `17.6%`.
- R26 compact native record allocation had no aggregate parse win and regressed
  CJK/readme profiles by `5-7%`.
- R27 bracket classification improved long-line CommonMark parse, but repeated
  readme CommonMark parse regressions of `8.0-8.5%` and large-code GFM HTML
  regressions of `6.0-9.0%` in opposite initial ordering.

All three candidates were exactly reverted to the R24 source bytes. Their raw
hashes are recorded in `progress.md` and `requirements.yaml`; none replaces the
sole canonical raw or changes a requirement status. The final status remains
**INCOMPLETE**.

R28 retains a narrower optimization that uses the already-produced line
classification only to prove the absence of `[` before running the old
full-input reference precheck. It preserves the old path whenever that proof
is unavailable. Full tests passed `1446/1446`; two fixed-CPU ordinary runs
reduced instructions by `11.3-13.2%` and cycles by `10.3-11.3%`, with identical
checksums. Bidirectional 11-corpus guards found no stable regression above
`10%`; a reverse-only deep-list HTML outlier was not reproduced by the focused
24-round repeat and was within the observed baseline/baseline drift. Raw hashes
are recorded in the ledger. R28 remains phase evidence only: it does not replace
the canonical full release report, and the final status remains **INCOMPLETE**.

## 2026-08-27 R29 Direct Line Storage and Canonical Acceptance

R29 fills the exact-size `Array<LineRecord>` returned by the native scan
directly, eliminating `ArrayList` growth and the final `toArray()` copy. Its
forward/reverse seven-corpus guard measured CommonMark parse
`0.917786/0.923710`, CommonMark HTML `0.990531/0.984202`, GFM parse
`0.953607/0.969530`, and GFM HTML `0.975985/0.975257`; no stable single-corpus
regression exceeded `10%`. Full tests passed `1446/1446`.

The then-canonical R29 raw was SHA-256
`985b4256e4b16ed009417f80e589cbb485298c7295c5581d2fe1483bb0287ca6`.
It binds archive `303a2ea5...1212`, harness `41b06872...8c86`, driver
`6c15b592...d5b`, the fixed SDK, frozen corpora and both reference drivers.
CommonMark was `3.959023x` and GFM was `3.534119x`; ordinary, scaling,
pathological scaling, adjacent growth and RSS all pass. CommonMark therefore
meets the interim `4.0x` target, but both mandatory `2.5x` ratios still fail.
`MD-PERF-002`, `MD-REL-001` and `MD-QUAL-001` remain blocked, and the final
status remains **INCOMPLETE**.

R30 tested a narrower-range SSE2 special-byte prefilter. Native build contracts
passed `4/4` and `5000` coverage-guided ASan+UBSan runs were clean, but the
bidirectional fixed-CPU guard showed GFM parse regressions of
`1.008164/1.020540`, with reverse ordinary at `1.050196`. The candidate was
rejected and the scanner was exactly restored to the R29 source bytes; the R29
canonical report remains authoritative.

A same-binary reusable-input diagnostic also showed the pure Cangjie scanner
at `1.206221x` the native path across seven CommonMark corpora, so the String
input profile is not used as a scanner-only comparison. R31 then tested
line-count block-buffer reservation, but its initial guard was only `0.989871`
for CommonMark parse and regressed GFM parse to `1.013699`, including deep-list
at `1.056944`. It failed the stop/go benefit threshold, was rejected, and the
parser was exactly restored to the R29 bytes.

R32 then removed the intermediate paragraph child array through an internal
list-consuming arena overload. Despite reducing a nominal copy, its first
guard regressed CommonMark parse to `1.021885`, pathological CommonMark parse
to `1.088450`, GFM parse to `1.007309`, and GFM HTML to `1.010970`. The
candidate was rejected; arena, parser and factory sources were verified
byte-identical to R29 after rollback.

R33 replaced the scanner's nine SSE2 comparisons with a whole-function SSSE3
nibble lookup selected once per parse. Build contracts and `5000` sanitizer
fuzz runs passed, but CommonMark parse, long-line and ordinary GFM regressed;
it was rejected. R34/R34b then delayed delimiter byte-array materialization.
Correctness passed, and pathological GFM improved, but long-line CommonMark
HTML regressed in both orderings and reverse CommonMark HTML regressed `6.03%`
overall. R35's trusted-arena count-write removal was neutral overall and
regressed deep-list/official guards. All three candidates were rejected and
the four product hot-path files were verified byte-identical to R29. The
canonical R29 report remains the sole acceptance evidence.

A fresh CJK profile then showed GC `18.86%`, delimiter-free inline parsing
`8.87%`, allocation/memset `8.05%`, arena append `4.22%`, and native scanner
only `2.58%` (`7030` samples, `0` lost). R36 isolated Unicode byte-run advance
inside that fast path, but it did not improve CJK/emoji and regressed ordinary
GFM parse `11.70%`. It was rejected and the parser was restored exactly.

## 2026-08-27 R37-R39 Allocation, Table and Scanner Audit

R37's leaf `containsLink` fast return passed parser `9/9`, but reverse GFM parse
regressed `4.16%` overall, including CJK `6.48%` and ordinary `9.58%`. R38 then
reused table-start ranges and passed parser `9/9` plus the GFM corpus `671/671`;
its target large-table parse gain was only `0.96%`, while official-spec GFM
parse regressed `12.75%`. Both candidates were rejected and restored exactly.

Fresh R29 profiling captured `3746` large-table GFM samples and `3545`
ordinary CommonMark samples, with zero lost. Large-table remained dominated by
GC (`19.25%`), `tableRow` (`9.66%`), allocation (`7.04%`) and arena append
(`6.24%`). Ordinary attributed `30.07%` to the native scanner, `22.85%` to
allocation/memset and `14.45%` to GC. This led to R39b's runtime-gated SSE4.2
equal-any scanner. It passed `4/4` build contracts, an actual C11 `-O3 -Werror`
build, `5000` coverage-guided ASan+UBSan runs and the full `1446/1446` suite.
Two 5000-iteration counter pairs reduced ordinary CommonMark instructions by
`39.8-41.6%` and cycles by `11.3-14.2%`, with identical checksum.

The complete release benchmark nevertheless rejected R39b: raw SHA-256
`727a748afe9b8d62a8817e6490d82d2f4764837a4d2511a4d718aa48c1db7bb0`
measured CommonMark `4.557093x` and GFM `3.410048x`. GFM improved slightly, but
CommonMark regressed from canonical R29 `3.959023x`, and both mandatory `2.5x`
gates still failed. The scanner was restored exactly to R29 and the repository
canonical raw was not overwritten. `MD-PERF-002`, `MD-REL-001` and
`MD-QUAL-001` remain blocked; the final status remains **INCOMPLETE**.

## 2026-08-27 Arena AST and Compatibility Closure

The v0.9 arena migration was re-audited end to end. The current runtime has one
semantic AST representation: `Document` owns fixed node/child chunks and
`NodeRef`/typed value views provide immutable access. Parser and all maintained
AST consumers use that representation; the repository contains no 0.8
`MarkdownNode` object tree or legacy decoder.

`python3 scripts/test_check_public_api.py` passed `9/9`, and
`python3 scripts/check_public_api.py` verified `1281` declarations. The external
quickstart rebuilt and its release executable ran successfully against the
curated public packages. Combined with the restored `1446/1446` full suite,
these results make `MD-AST-001`, `MD-AST-002`, `MD-COMP-001` and `MD-COMP-002`
`pass`.

The ledger is now `120/125 pass`, `2 pending`, `0 implemented_unverified` and
`3 blocked`. `MD-GOV-004` and `MD-EVT-001` remain pending because the current
event adapter still walks a complete AST; the final status remains
**INCOMPLETE**.

## 2026-08-27 Event Scope Correction

A-037 resolves the conflict between the Event behavior in PRD §27 and the
frozen delivery decision in §54.10: the genuine source Event API is a 1.1
requirement. The 0.9 AST-walk array adapter and all of its public exports were
removed rather than misrepresented as streaming or low allocation. The explicit
fused HTML path remains capability-preserving and does not replace the full-AST
canonical benchmark.

The intentional v0.9 API snapshot now verifies at `1263` declarations; API
checker tests passed `9/9` and `cjpm check` passed. `MD-GOV-004` is therefore
`pass`, while `MD-EVT-001` remains pending for a true Resolved/RawBlock source
implementation in 1.1. The ledger is `121/125 pass`, `1 pending`, `0
implemented_unverified` and `3 blocked`; final status remains **INCOMPLETE**.

## 2026-08-27 R40-R42 Performance Continuation

R40's sparse orphan exclusion design passed the complete `1444/1444` suite only
after adding a general reachability fallback, but that final safe version had no
stable aggregate benefit and regressed ordinary CommonMark HTML by
`14.75%`/`18.72%`. R41's delayed delimiter-free Text lowering also failed
promotion: official-spec GFM parse regressed `7.85%`/`13.77%`. Both candidates
were restored byte-identically to R29; their raw reports remain rejection
evidence and do not replace canonical data.

R42 targets a measured table hotspot instead. The existing table-row scan now
also classifies inline-special, delimiter and possible autolink bytes, allowing
plain cells to skip redundant String searches while candidate cells preserve
the full GFM autolink path. Large-table GFM parse improved by `11.75%`/`13.55%`
and GFM HTML by `6.54%`/`5.86%` in bidirectional 1 MiB paired guards. A separate
100-iteration counter run reduced instructions `13.3%`, branches `14.0%`, cycles
`12.8%` and wall time `12.8%`. Raw SHA-256 values are
`7d25486f17909f87a856b2f7f98ff9c4cfba97ce96123f9f918bed96495104e8`
and `434e0dd5d6ff705b57678432497ee8c56181eeeb17fd70011d995e9a627eaae2`.

`cjpm check`, the parser-focused `9/9`, and the complete `1444/1444` suite pass.
The complete identity-bound R42 rerun used source archive SHA-256
`594940702b94a46b5b66466f14d24df021ae176ede15748bffafed95273595a0`, driver
SHA-256 `6b725e7e3b7d3c8d98d6d12c7a5d1528b6f91256675319c1ed08706a58657d28`
and the frozen harness, SDK and reference drivers. Under A-038, the latest
complete repeat is authoritative rather than the numerically best run. Raw
SHA-256 `d636de0310088c5f1c15dac5dbf9de3ef0fca52f94086aca62272125d118fa00`
measured CommonMark `4.444100x`, GFM `3.569983x`, scaling slope `0.803683`,
maximum adjacent growth `2.089015`, pathological slope `1.022853`, pathological
maximum adjacent growth `2.280959`, and extra RSS `48436 KiB`. All non-ratio
gates pass; the three performance-dependent requirements remain blocked and
final status is **INCOMPLETE**.

## 2026-08-27 R43 Reference Normalization Reuse

R43 removes one duplicate label-normalization allocation per valid reference
definition by returning the value already computed during definition parsing to
the collection/index step. `cjpm check`, ParserBehaviorTest `9/9`, and the full
socket-enabled suite `1444/1444` passed. Fixed Server 1 MiB forward/reverse
guards preserved all checksums and measured many-references CommonMark parse at
`0.967232/0.950648` candidate/baseline; six-corpus GFM parse remained
`0.996150/1.001368`. Raw SHA-256 values are
`552d64c3683963352cf265a0d7e1761530ace6288d40246b145eec9ef4431a16` and
`51cdf8be1504b5e297f4d863fca0f92b4c02f9394c46ba4a8430a8c680cf2092`.
The low-risk candidate is retained. At this checkpoint the complete R42 raw
remained canonical; the later R45 full run below supersedes it.

R44 then tested a one-entry session-local reference lookup cache. Although an
isolated stop/go appeared to improve many-references CommonMark parse, the full
six-corpus forward/reverse guard measured the target at `1.003499/1.005330` and
shifted apparent gains to unrelated HTML work. It was rejected and the parser
was restored byte-identical to R43. Full-guard raw SHA-256 values are
`a3d775fd35d255d3d9aaff6acec10795d2f04c1689eee8ba34be0eba1d9ce0e0` and
`ec53dca7e2a7e011fad8e03ffeed33b9f01af1f3cf7db7904d08fa0c662f0ceb`.

R45 compacts `InlinePiece`'s zero-or-one-node payload from an `Array<Int64>`
to one integer sentinel. Full tests pass `1444/1444`; pathological-delimiter
CommonMark parse improved `0.821443/0.794472` in forward/reverse guards, and
100-iteration counters reduced instructions `22.2%`, branches `21.1%` and
cycles `23.1%`. The six-corpus guard found no stable per-corpus regression over
`10%`. Target raw SHA-256 values are
`564e50085ba4dc30e7782f08fd67295874d675e9cd3b47f90448d2ce16161754` and
`636220571323387f4f188297f63e20682b0c6968cf9017e4f1632b2c65c287c7`;
cross-profile hashes are `edbc79f04030365132a64f6ee881f14a46f683f7e115788d40fa9cbc6bf33409`
and `d5cfba496b9825dc057f64928da0711f400a36e88a79ff4290164d6ec7435c07`.
R45 is retained. Its full identity-bound canonical run used minimal source
archive SHA-256 `a2f90a62b1fdcf91bc7aac996b1de3c872539c7b2855ef9cd5c7291564295b93`,
fresh driver SHA-256 `9c84d30737f2c220407459ae8aaccc9e9da32ce9cd1094a159da301b0a4f86fe`
and raw SHA-256 `72f9897cf38f703d83e73b039481985d02872bdf3e691c3dd18c1f747127530d`.
Per A-038 it is now the sole canonical result: CommonMark `4.296935x`, GFM
`3.838531x`, scaling slope `0.855694`, maximum adjacent `2.009294`, pathological
slope `0.862328`, pathological maximum adjacent `1.890727`, and extra RSS
`50488 KiB`. All non-ratio gates pass; the performance and dependent release
requirements remain blocked.

R49-R52 then remove avoidable inline temporaries without changing the complete
AST contract. Text lowering is delayed until the final piece sequence, GFM
autolink expansion only visits candidate Text values, and scanner record v3
marks whether escape/entity/code lowering is possible. Scanner-proven
delimiter-free lines without those markers build nodes directly; legacy v1/v2
accelerators stay on the conservative path. Parser `9/9`, CommonMark `652/652`,
GFM `671/671`, native ASan+UBSan fuzz `1000`, and full tests `1444/1444` pass.
The final canonical archive/driver/raw SHA-256 values are
`d2d9d9548e11be867279e7efe830907866aa851c1248af74ab65b97b83395dab`,
`88822e124489c3c828bbd9769bfa17076df4ed98d13cb64dd1493e3ba5bab766`,
and `52a2b063af9d738e69ca2980bf20fb90a3b587f32a13508ec5efecbe3a1fc691`.
At that checkpoint, A-038 made R52 the sole canonical result: CommonMark
`4.229764x`, GFM `3.225310x`; every non-ratio performance gate passed, while
both `2.5x` ratios failed. R55 below supersedes this historical checkpoint.

R53/R53a URI encoding and code-layout candidates were rejected after ordinary
GFM HTML regressed in both isolated directions. R54 native SSE comparison reuse
was likewise rejected after mixed four-profile guards and a larger emitted
function. Their raw SHA-256 values are recorded in `progress.md` and the
corresponding sources were restored byte-identically.

R55 directly consumes parser-owned paragraph, list, table, and table-row child
lists in the chunked arena, removing the intermediate array while preserving
the unified node-limit check and public defensive-copy path. Check, focused
parser, CommonMark, GFM, and full `1444/1444` tests pass. Forward/reverse
eight-corpus guards improve CommonMark parse to `0.952010/0.965033` and GFM
parse to `0.984632/0.973244`, with no stable same-corpus regression over `10%`.
Per A-038 R55 supersedes R52 as the sole canonical result. Archive, driver, and
raw SHA-256 values are
`b2c5f7b779b9c13b6e9a27b4588755d885ec704b150b376a2d3fd6116d0e5f35`,
`079c6b3473232519a81963607ad9f7b3bc283d282661ed96fb79f7d525028db0`,
and `4806319a20fadd02559559e741ee81fed240582b87b7e018144473a30d456e23`.
CommonMark is `4.198183x`, GFM `3.176074x`, and every non-ratio performance
gate passes. Both `2.5x` ratios still fail, so the final status remains
**INCOMPLETE**.

R57 removes the delimiter arena's separate active bitmap and reuses a reserved
negative integer link value for inactive records. Full tests pass `1444/1444`.
Pathological CommonMark/GFM parse improved to `0.941392/0.952226` and
`0.885504/0.892718` in forward/reverse target runs; perf stat independently
measured instructions `0.896826` and branches `0.871495`. Eight-corpus,
four-profile guards found no same-corpus regression over `10%` in both
directions. A separate 24-round large-table GFM parse repeat measured
`0.966326/0.980403`, so the sequential counter anomaly did not reproduce as an
end-to-end regression.

Per A-038 R57 supersedes R55 as the sole canonical result. Archive, driver, and
raw SHA-256 values are
`b29ff1457ca1ceca20ea14b1330ce42c8d82b5bd4b10cf433238c16cab113b38`,
`d5a242c3e2402cfc31405c15506b240b39e3a9b6d4172005cbd55f97f9012313`,
and `c8c1f9a3bc4ac89616020f6fb1e9bfb9bcb46a58dbe22c513114e33b7c0a0873`.
CommonMark is `3.832106x`, GFM `3.235215x`, and all non-ratio gates pass.
Both `2.5x` ratios still fail, so the final status remains **INCOMPLETE**.

R59 directly materializes scanner-proven plain table-cell Text from source spans,
and R60 sends a single Text cell through the existing escaped node writer without
allocating a generic inline render frame. Both retain complex-inline, extension,
source-map, budget and cancellation behavior. R59 passed parser `9/9`, GFM corpus
`671/671` and full `1444/1444`; R60 passed renderer `11/11` and full `1444/1444`.
Their bidirectional guards found no stable same-corpus regression above `10%`.

Per A-038 R60 now supersedes R57 as the sole canonical result. Archive, driver,
and raw SHA-256 values are
`b79cd108f8a1afa5b4818c9ab0626d8284beed97895db50c9e71184085b7d69d`,
`81c82f3d690cfeb9e01b03e9c5b35884ad19436c8d05c7cbab23ee78b742dcb5`,
and `30f3a7000ad0b57e11857cee33a9f72c9681b704d16ba2981ba08aaaba53f613`.
CommonMark is `4.030330x`, GFM `3.270682x`; scaling, pathological scaling,
ordinary and RSS gates pass. Both `2.5x` ratios still fail, so the final status
remains **INCOMPLETE**.

R61's ASCII-only delimiter flanking candidate passed all `1444` tests but was
rejected after the bidirectional guard regressed both parse aggregates and a
24-round repeat confirmed official-spec GFM parse at combined `1.072661`.
Although pathological GFM parse improved to combined `0.916092`, the candidate
was restored exactly to the R60 parser bytes and does not alter canonical data.

R62's lazy final-closing-bracket scan also passed all `1444` tests. Its initial
official-spec CommonMark gain did not reproduce: the eight-corpus combined
CommonMark parse ratio was `0.998351`, while GFM parse/HTML were `1.010088` and
`1.005630`; the 24-round repeat put official-spec at `0.990401` and CJK at
`1.030063`. R62 was rejected and the parser was again restored byte-identically
to R60. Neither rejected candidate changes the canonical evidence or status.

R63 reused the scanner `ArrayList<InlinePiece>` directly during delimiter
resolution. It passed all `1444` tests and improved pathological CommonMark
parse to combined `0.917806`, but official-spec GFM parse regressed in both
orders to combined `1.091799`. The candidate was rejected and the parser was
restored byte-identically to R60; canonical evidence remains unchanged.

R64 pre-reserved the maximum additional wrapper capacity before the same direct
mutation. Parser `9/9` passed, but official-spec GFM regressed further to
combined `1.127157`, while the pathological CommonMark gain disappeared. This
rules out dynamic list growth as the sole cause. R64 was rejected and restored;
canonical evidence remains unchanged.

R65 retains the fixed delimiter arena and accumulates delimiter bytes during the
existing scan, removing the resolver's second full piece traversal. Check,
Parser `9/9` and full `1444/1444` pass. The eight-corpus combined geomeans were
`0.993696` CommonMark parse, `0.999986` CommonMark HTML, `0.993595` GFM parse
and `1.002597` GFM HTML, with no stable same-corpus regression above `10%`.

Per A-038, R65 supersedes R60 as the sole canonical result. Archive, driver and
raw SHA-256 values are
`d05f78e676a374cd579459078bdf517fc5e15dac4879860ddd086eef9a30cc04`,
`a1048827aea26427625a7870a386d7b2e87c5b09ef44983741d21c1372d7440a`,
and `442842c801231d738b423aaf8e00b61cba6359c22a1d1a6ae5f1c48f72ed6d41`.
CommonMark is `3.873240x`, GFM `3.230493x`; all non-ratio gates pass. Both
`2.5x` ratios still fail, so final status remains **INCOMPLETE**.

R66 then sized the two delimiter opener arrays by actual marker-run counts. It
passed `cjpm check` and Parser `9/9`, and improved pathological CommonMark/GFM
parse to combined `0.940734/0.968965`. Official-spec GFM nevertheless regressed
in both orders to combined `1.119772`, above the stable `10%` single-corpus
guard. R66 was rejected and the parser restored byte-identically to R65; it
does not replace the canonical raw report or change the final status.

R67 and R68 tried to isolate the same capacity reduction inside the resolver.
R67 used marker bytes directly and R68 used `min(pieceCount, markerBytes)`, so
R68 could never allocate more than R65. Both passed check and Parser `9/9`, but
official-spec GFM still regressed to combined `1.120056` and `1.140556`.
Neither pathological profile improved under R68. Both candidates were rejected
and R65 restored exactly; opener-capacity tuning is no longer treated as a
viable performance axis.

R69 removed the common single-line reference-definition builder and repeated
string materialization. It passed check and CommonMark `652/652`, and improved
many-references CommonMark parse to combined `0.961278`. Official-spec GFM
again regressed in both orders to combined `1.126636`, so the candidate was
rejected and R65 restored exactly. The recurrence across unrelated source
changes requires binary layout/GC attribution before further micro-optimization.

The R65/R69 symbol comparison showed only the changed reference function became
smaller; later `materializePieceLinks` and `ParserSession.parse` shifted by
`0xa0`. A 1000-iteration DWARF perf pair captured `13020/13223` samples with
zero lost and only `+1.61%` event-count difference; GC share changed from
`17.98%` to `18.29%`. R70 then proved moving the unchanged member in source
does not alter release symbol order or addresses. It was rejected without a
wall-time guard and R65 restored exactly.

R71 moved the unchanged reference parser across a type boundary and passed
Parser `9/9`, CommonMark `652/652`, and a six-profile guard without a stable
`>10%` regression. Reapplying the fast path as R72 still shifted later hot
functions and regressed official GFM by combined `1.133615`, so it was rejected.
R73 showed that separate `.cj` files are still emitted as one package layout
unit. R74 halved delimiter index-buffer width, but a 48-round repeat confirmed
official-GFM regression `1.125367/1.111131` (combined `1.118226`), so it too was
rejected.

R75 then added paragraph checkpoints so a cross-line delimiter reparse could
discard provisional per-line nodes. The generic rollback copied the retained
arena prefix and produced a severe official-corpus regression, so it was
rejected. Retained R76 implements trusted same-chunk tail truncation while
keeping the existing cross-chunk fallback. Arena `12/12`, Parser `9/9`,
CommonMark `652/652`, GFM `671/671`, and full `1445/1445` passed. Its full
four-profile guard improved GFM parse to combined `0.941748`, kept the other
profile geomeans within `1.3%`, and had no stable same-corpus regression above
`10%`. R77's scanner-flag replacement was rejected after a checksum mismatch
proved it changed CommonMark HTML semantics; the parser was restored exactly to
R76.

R76 profiling on official-spec 256 KiB, 1000 parse iterations captured
`11458/12945` CommonMark/GFM samples with zero lost. GC phase accounted for
`19.79%/19.95%`; `memset`, `parseInline`, scanner, block parser and reference
work remained the next attributable costs. R78 explored fixed parser-owned
node/child tails, but was abandoned before timing because release codegen could
not be cleanly qualified under concurrent resource pressure; the arena was
restored exactly and no performance claim is made.

Retained R79 avoids provisional per-line AST construction when a continued
paragraph beginning with `*`, `_`, or backtick is guaranteed to use the existing
combined-inline path. Remote full tests pass `1445/1445`. Its target guard has
checksum parity, and the bidirectional eight-corpus guard measured CommonMark
parse `0.924020`, CommonMark HTML `0.943399`, GFM parse `0.959517`, and GFM HTML
`0.956656`, with no stable same-corpus regression above `10%`. Target/full raw
SHA-256 values are
`d11db969be616e047e5c04bc2c6d9a42e93a98c52384b27410ff19ee2fae6c33` and
`a532e70e07f0e2c2d435f4037b652f9d28ec5d0fe0bb9ba982d4133ef52ecfe2`.
The identity-bound full release benchmark is complete. Per A-038, R96 now
supersedes R81. Its conservative single-fenced-document range path preserves the
complete AST contract, passes local and remote `1446/1446`, and improves the
1 MiB large-code target to `0.556121` of R81 without a stable cross-profile
regression.

R96 is the sole canonical release result. Archive, driver, and raw
SHA-256 values are
`4dc6173426eacc58b338d4c4e56f067dfcd8a2ee44c84a2fcb657ac2cdc188d3`,
`65955eb767949dac25ca98cb5505ad4b4ffdb348a2d99b24ccbb2e2ee71ba137`,
and `60eb13f017215daa942729f0f3f374e1de7e65c25eb2ef154d7a5f2e14ac5d8b`.
CommonMark is `3.309682x`, GFM `2.988521x`; every non-ratio performance gate
passes. The two `2.5x` ratios remain blocked, so final status is **INCOMPLETE**.

R98-R101 did not change this acceptance projection. A plain-paragraph document
candidate improved selected CommonMark corpora, but its first effective form
bypassed third-party scanner record validation and failed the same two cases in
both local and remote full suites. The corrected form restored those contracts
but introduced a stable `>10%` large-code regression. The candidate was rejected
and product bytes restored exactly to R96; no candidate raw replaced the
canonical release evidence.

R102 subsequently retained the scanner trust boundary and specialized only the
post-selection CommonMark paragraph materializer for pipe-prefixed documents
that are proven free of inline-special and hard-break bytes. It preserves the
complete arena AST and all limit/source contracts. Local and remote suites pass
`1447/1447`; the 24-round target guard improved large-table CommonMark parse to
`0.647552` of R96 with A/A `0.998878`, while the 48-round large-code and twelve-
profile broad guards had no stable regression above `10%`.

At that checkpoint, A-038 made R102 the sole canonical release result. Archive, driver and raw
SHA-256 values are
`3fea7d9ef88c888c1d22ef4cc4c0d89ff31a750812d90940149703aee41f1c5a`,
`d82e26e4ea4935bfa33695eb22da77c10ca568c204bf36c66d9fc8f69cc9bb7d`,
and `f84bbcc09cd2fadfafbad427c6ed5690026f02515b7e68d4acf790cc0d203d56`.
CommonMark is `3.282625x`, GFM `2.992156x`; all non-ratio gates pass, but both
`2.5x` ratios remain blocked. Final status remains **INCOMPLETE**.

R103-R112 do not change the R102 acceptance projection. Arena-capacity candidates
produced stable dense-AST or GFM regressions; the fence-only R106 repeat was
`1.104012` large-code GFM HTML against A/A `1.000891`, and the profile-gated
R107 still measured `1.091578`. A subsequent optional C terminal-fence scan
duplicated the full-input work and regressed CommonMark by `28.6%`; replacing
its scalar loop with `memchr` still regressed by `21.0%`. Every candidate and
the temporary accelerator API were removed, and all touched files were verified
byte-identical to R102. R110's Array-backed single-pass helper was also rejected
after a stable `10.2%` GFM HTML regression. R111's scalar-to-newline scanner
experiment passed local sanitizer fuzz/check/build and improved ordinary
CommonMark by `1.9%`, but regressed large-code CommonMark by `13.2%`; its raw
SHA-256 is `cffe28c456a3213e7190be0b380d46d4d9adcf72ad0f6f959d646d885451ab15`.
The scanner was restored exactly to R102. The canonical raw, counts and
`INCOMPLETE` verdict remained unchanged. R112's unconditional AVX2 classifier
was then rejected after a stable `22.1%` large-table CommonMark regression.

R113 retains AVX2 only for non-pipe-prefixed input. Sanitizer fuzz, focused
native-on/off behavior and remote `1447/1447` tests pass; target and broad guards
have no stable single-corpus regression above `10%`. Its complete identity-bound
Server run now supersedes R102 with CommonMark `3.176050x`, GFM `2.975849x`,
ordinary `4.789793x/1.938199x`, scaling slope `0.850345`, pathological slope
`0.617786` and extra RSS `48900 KiB`. Raw SHA-256 is
`aba81c2325dd579776e3f5c9403aa10190d20316b8ca6a823da406ad9aeeb82a`.
Both `2.5x` ratios still fail, so the final verdict remains **INCOMPLETE**.

R114 adds a conservative per-line reference-opener classification to packed
scanner records and skips impossible reference-definition lines. ASan+UBSan
scanner fuzz passed `1000` runs, focused Input/Parser tests passed `12/12` and
`11/11`, and the remote full suite passed `1447/1447`. Target and broad paired
guards had no stable regression above `10%`; their raw SHA-256 values are
`5173c4ea881fcd86328c5ccc6a1805516398f5d7880f518be7f99b9df113036f` and
`6eb756be5c4da28080470b7046ed0051072963cd0c0cd3a122316f7ab04c98c5`.

Per A-038, the complete identity-bound R114 Server run supersedes R113 even
though unchanged cmark/cmark-gfm medians moved substantially relative to the
direct product A/B. Raw SHA-256 is
`0b63fdec8d2812c8207769057f4b447452c559d8252fa18460f756059efd9836`;
CommonMark is `3.295073x`, GFM `3.183832x`, and ordinary is
`6.645361x/2.481399x`. Scaling, pathological scaling and RSS pass, but both
`2.5x` ratios and ordinary CommonMark `5x` fail. The final verdict remains
**INCOMPLETE**.

R115 removes the native scanner's packed-record prefix copy without changing
the complete AST execution model. The legacy accelerator method remains
adapted, invalid prefix counts fail closed, focused Input behavior passes
`12/12`, the public API snapshot verifies `1269` declarations, and the remote
full suite passes `1447/1447`. Target and broad guard raw SHA-256 values are
`c3998e8e648fd679da5fc8cbc5822e2853d01ec801b2a67b65f6bffa8625ecb1` and
`38547f3a09de4ad58ec7ab905474b3dab17136e99e02c2e56415e0e955a9abf9`.

Per A-038, the complete identity-bound R115 Server run supersedes R114.
Archive, driver and raw SHA-256 values are
`e0219aa1567e0ec2d7001cb3c0fe4eb9bb303e3a5431c4c317a8b19afc36bb99`,
`4d19daed81a7671080b2abec445d7356e2f1f388e52e934934b22fb3e7e4b42e`, and
`200a2f8f9d891eedc98e825fd2b4ebae5725accc2be30418d67da449946c2f25`.
CommonMark is `2.915703x`, GFM `3.078800x`, and ordinary is
`4.847819x/2.767217x`. Scaling, pathological scaling, ordinary and RSS gates
pass, but both `2.5x` ratios fail. The final verdict remains **INCOMPLETE**.

R116-R119 then tested the remaining line/string allocation hypothesis without
changing the full-AST benchmark contract. The shared-source `LineText`
candidate passed full tests `1447/1447` but regressed official-spec CommonMark
by more than `50%` in both directions. An isolated allocation-free HTML matcher
passed focused validation, yet its twelve-profile broad guard regressed
CommonMark parse/HTML and GFM HTML geomeans to `1.015504/1.029341/1.006955`.
Broad raw SHA-256 is
`0df5ffdd413cc6d2be4736776b2d763c4c9a16019cefa5dcdb617dd61767439f`.
All product candidates were rejected and restored byte-identically to R115;
only a dense-newline scanner fallback equivalence regression was retained.
Canonical performance evidence and the **INCOMPLETE** verdict therefore remain
R115-bound.

R120 additionally isolated HTML block-tag classification without a temporary
array. Its official and ordinary GFM ratios reversed sign between forward and
reverse corpus order, so it was rejected as non-attributable. Raw SHA-256 values
are `79022665fa692cf31a081ff8ce2f5f7cbbe2175fe6a0752c46d97624e9fdfe37` and
`eccaa4ca3bc8f2a8cfffd7de085412a3eb2a31a69277571fc8bbc7a835c3e332`.
The parser remains byte-identical to R115 and the verdict is unchanged.

## 2026-08-28 Source-driven Event API closure

`MarkdownSourceEvent` values contain only kinds, source ranges, attributes and
semantic text; they cannot retain `Document` or `NodeRef`. Resolved execution
collects references before lowering transient top-level blocks and rolls each
block back immediately after emission. RawBlock execution buffers incomplete
UTF-8 and unfinished blocks, emits proven-closed blocks before `finish()`, and
marks all events non-final. Document processors fail closed because they require
the full AST, while FullAst/PreferFused/RequireFused HTML execution remains
explicit and capability-preserving.

`SourceEventApiTest` passed 7/7; the complete suite passed 1454/1454 with zero
skipped/error/failed. Format passed, API checker self-tests passed 9/9, and the
v0.9 snapshot verified 1311 declarations. `MD-EVT-001` is therefore `pass`.
The ledger is 122/125 pass with only `MD-PERF-002`, `MD-REL-001` and
`MD-QUAL-001` blocked; final status remains **INCOMPLETE**.
