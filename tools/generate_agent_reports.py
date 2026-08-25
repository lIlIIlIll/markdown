#!/usr/bin/env python3
"""Render progress and acceptance projections from the sole requirements ledger."""

from collections import Counter
from pathlib import Path
import json
import yaml


ROOT = Path(__file__).resolve().parents[1]
AGENT = ROOT / ".agent"
requirements = yaml.safe_load((AGENT / "requirements.yaml").read_text())["requirements"]
benchmark = json.loads((ROOT / "docs" / "reports" / "benchmark-raw.json").read_text())
counts = Counter(item["status"] for item in requirements)
nonpass = [item for item in requirements if item["status"] != "pass"]
benchmark_result = (
    "final 12-corpus GA FAIL: CommonMark "
    f"{benchmark['commonmark']['geometricMeanRatio']:.2f}x, GFM {benchmark['gfm']['geometricMeanRatio']:.2f}x, "
    f"ordinary CommonMark {benchmark['commonmark']['corpora']['ordinary']['medianRatio']:.2f}x; ordinary slope "
    f"{benchmark['scaling']['slope']:.3f}, pathological slope "
    f"{benchmark['pathologicalScaling']['slope']:.3f}, RSS {benchmark['memory']['extraPeakRssKiB']} KiB pass"
)

validation = [
    ("`scripts/check_format.sh`", "0", "all Cangjie source matches cjfmt"),
    ("`cjlint -f src`", "0", "0 mandatory; 472 advisory diagnostics"),
    ("`cjpm check`", "0", "dependency graph valid"),
    ("`cjpm build`", "0", "root static library, `-O2`"),
    ("`cjpm test --no-color --no-progress --report-path /tmp/markdown-final-tests --report-format xml`", "0", "1410 passed, 0 skipped/error/failed"),
    ("CommonMark/GFM cases inside full suite", "0", "652/652 and 671/671"),
    ("`cd tools/markdown && cjpm build`; `scripts/cli_smoke.sh`", "0", "CLI build and exit 0/2/3/4/5/6 smoke"),
    ("`cd examples/quickstart && cjpm build && cjpm run`", "0", "public consumer example built and ran"),
    ("`python3 scripts/check_public_api.py`", "0", "1155 public declarations match snapshot"),
    ("`python3 scripts/differential_test.py`", "0", "25 comparisons: 24 exact, 1 classified, 0 unexpected"),
    ("`cjpm bench --filter MarkdownReleaseBenchmarks ...`", "0", "3/3 benchmark smoke cases"),
    ("`python3 benchmarks/measure.py`", "1", benchmark_result),
    ("`scripts/release_gate.sh`", "1", "fail-closed at performance after format/API/check/build/1410 tests/CLI/example/differential/benchmark smoke passed"),
    ("`cjpm bundle --skip-test` after the full 1410-test gate", "0", "target/markdown-1.0.0.cjp; 343528 bytes; SHA-256 aab2e233b88b495c0221eb36e673c0d6a19184721b1776620525283098882529"),
]

progress = f"""# markdown 当前进度

更新时间：2026-08-18  
当前阶段：最终审计完成；性能和私密安全报告渠道未达 GA  
整体结论：**INCOMPLETE**。正确性、规范、构建和打包门槛已通过，但需求账本仍有 4 个 `blocked` 项。

## 需求概览

| 状态 | 数量 |
| --- | ---: |
| 总数 | {len(requirements)} |
| `pass` | {counts['pass']} |
| `implemented_unverified` | {counts['implemented_unverified']} |
| `pending` | {counts['pending']} |
| `blocked` | {counts['blocked']} |

`requirements.yaml` 是唯一状态账本；本文件只用于会话恢复。

## 已完成主链路

- CommonMark 0.31.2 与 GFM 0.29 官方语料分别 652/652、671/671。
- String/bytes/stream/chunked 输入、不可变 AST、byte/UTF-16/visual 位置、SourceSlice、partial-result 隔离。
- Spec/GFM/Safe HTML、Plain Text、Canonical Markdown、Sink、sanitizer 和暂停/恢复 adapter。
- Dialect/Syntax/Renderer DSL、typed 参数、bounded Parser SPI、SHA-256 fingerprints、TCK。
- Walker/Visitor/Query/Rewriter、transform、annotation、events、CST/token map、snapshot、range/preserving edit、lint/fix/explain、source map、artifact。
- CLI、consumer quickstart、API snapshot、差分测试、安全/fuzz corpus、benchmark harness、完整 cjpm bundle。

## 当前非通过项

"""
for item in nonpass:
    progress += f"- `{item['id']}` — `{item['status']}` — {item.get('notes') or item['description']}\n"

progress += "\n## 最后验证\n\n| 命令 | Exit | 结果 |\n| --- | ---: | --- |\n"
for command, exit_code, result in validation:
    progress += f"| {command} | {exit_code} | {result} |\n"
progress += """

## 工作区安全

- HEAD 保持 `71b95a518e701d16f02dbb9c5282c476b4ea5613`。
- merge-base/common base 保持 `0133d479d2e8c8f03076233fd630bd3924d64db5`。
- 初始 dirty 仅 `.agent/` 与 `docs/`；当前实现文件均保持未提交。
- 未执行 reset、clean、stash、checkout、rebase、commit、push 或 PR 操作。
- 未发现并发漂移；GitButler 最终仍显示单一 `zz [uncommitted]` 工作区。

## 恢复顺序

1. 从 `requirements.yaml` 读取 4 个 blocked 项，不从本摘要猜测。
2. 为 `MD-SEC-005` 配置真实可用的私密漏洞报告渠道。
3. 对 `MD-PERF-002` 继续执行 measure → perf profile → allocation/lifetime 优化 → 全量正确性 → 重测；不得放宽阈值。
4. 两个前置项通过后重跑全部 gate，并将 `MD-REL-001`、`MD-QUAL-001` 改为 pass。
5. 只在 125/125 `pass` 时声明 COMPLETE。
"""
(AGENT / "progress.md").write_text(progress)

acceptance = f"""# markdown 最终验收报告

## Final Status

**INCOMPLETE** — 125 项需求中 {counts['pass']} 项为 `pass`，仍有 {len(nonpass)} 项 blocked；性能 GA 数值已实测失败，私密安全报告渠道未配置。

## Requirement Summary

| 状态 | 数量 |
| --- | ---: |
| `pass` | {counts['pass']} |
| `implemented_unverified` | {counts['implemented_unverified']} |
| `pending` | {counts['pending']} |
| `blocked` | {counts['blocked']} |

## Itemized Verdict

| ID | Source | Status | Evidence / reason |
| --- | --- | --- | --- |
"""
for item in requirements:
    if item["status"] == "pass":
        detail = item.get("evidence", ["verified"])[-1]
    else:
        detail = item.get("notes") or "Acceptance remains incomplete."
    detail = str(detail).replace("|", "\\|").replace("\n", " ")
    acceptance += f"| `{item['id']}` | {item['source']} | `{item['status']}` | {detail} |\n"

acceptance += "\n## Validation Evidence\n\n| Command | Exit | Result |\n| --- | ---: | --- |\n"
for command, exit_code, result in validation:
    acceptance += f"| {command} | {exit_code} | {result} |\n"

acceptance += """

## Release Decision

The package must not be released or described as COMPLETE. The final bundle
succeeded, but `benchmarks/measure.py` exits 1 and no usable private security
reporting channel is configured. No waiver or threshold reduction was applied.
"""
(AGENT / "acceptance-report.md").write_text(acceptance)
