#!/usr/bin/env python3
"""Export a sanitized append-cost report from verified retained samples."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_report(path: Path, text: str) -> None:
    if path.exists() and path.read_text() != text:
        raise FileExistsError("choose a new directory instead of overwriting different historical evidence")
    path.write_text(text)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{7,40}", args.revision):
        parser.error("revision must be the measured hexadecimal commit ID")
    data = json.loads(args.report.read_text())
    if data.get("schema") != "markdown.append-cost/2" or data.get("retainedSamples", 0) < 7:
        raise ValueError("unsupported or incomplete measurement")
    for row in data["samples"]:
        relative = Path(row["rawPath"])
        if relative.is_absolute() or len(relative.parts) != 1 or sha(args.report.parent / relative) != row["rawSha256"]:
            raise ValueError("retained sample bytes do not match")
    data.pop("cpu", None)
    data |= {"affinity": "one logical CPU", "productionRevision": args.revision,
        "retainedReportSha256": sha(args.report)}
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    raw = output / "append-cost-raw.json"
    write_report(raw, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    rows = [row for row in data["samples"] if not row["warmup"]]
    maximum = max(row["units"] for row in rows)

    def group(operation: str, shape: str, width: int, size: int = maximum) -> list[dict]:
        return [row for row in rows if (row["operation"], row["shape"], row["chunkBytes"], row["units"]) ==
            (operation, shape, width, size)]

    def median(values: list[dict], key: str) -> float:
        return statistics.median(row[key] for row in values)

    text = f"""# 追加与可恢复输出成本

本报告对应生产代码 `{args.revision}`、官方 STS 1.2.0、`-O2 --obf-seed 0`、单逻辑 CPU、
纯仓颉路径和六项 P1 扩展。heap 为 2GB，GC interval 为 500ms。每组使用独立进程，
丢弃首轮后保留七轮；每轮反转场景顺序。它是 MD-06 成本证据，不代替冻结 release gate。

- 产品 tree SHA-256：`{data['productTreeSha256']}`。
- 被测 library SHA-256：`{data['librarySha256']}`。
- driver source SHA-256：`{data['driverSourceSha256']}`。
- driver SHA-256：`{data['driverSha256']}`。
- 保留的完整报告 SHA-256：`{data['retainedReportSha256']}`。
- [七轮逐进程样本与原始 TSV 摘要](append-cost-raw.json)。每次 feed 的原始延迟保留在各 TSV，
  路径与 SHA-256 由 JSON 绑定。完整目录作为独立 evidence 保存，不将旧样本绑定到新代码。

## 追加输入

下表为最大输入的七轮中位数。总时延包含 replica 应用和延迟收集；feed 计时包含 chunk
切片。首块是结构闭合且语义尚待最终绑定的块，`—` 表示 finish 前没有交付。未闭合围栏
和持续的松列表会等待收尾，不补作者未输入的字符。

| 输入 | 字节 | chunk | 首块 ms | finish ms | 总计 ms | 峰值 RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
"""
    shapes = {"closed": "闭合段落", "unclosed": "未闭合围栏", "references": "后置引用/脚注", "list": "松列表"}
    for shape, title in shapes.items():
        for width in sorted({row["chunkBytes"] for row in rows if row["operation"] == "append"}):
            values = group("append", shape, width)
            first = median(values, "firstBlockNanos")
            first_text = "—" if first < 0 else f"{first / 1e6:.3f}"
            text += (f"| {title} | {values[0]['inputBytes']} | {width} | {first_text} | "
                f"{median(values, 'finishNanos') / 1e6:.3f} | {median(values, 'totalNanos') / 1e6:.3f} | "
                f"{median(values, 'peakRssKiB') / 1024:.2f} |\n")
    text += """
累计工作计数来自会话实际收费。以下是 chunk=1 时三个输入规模的扫描量；它们不代表
堆分配次数。node-construction 包含推测与回滚，patch 不保留历史批次。

| 输入 | units | 扫描步数 | 节点构造步数 | patch 步数 |
| --- | ---: | ---: | ---: | ---: |
"""
    for shape, title in shapes.items():
        for size in sorted({row["units"] for row in rows}):
            values = group("append", shape, 1, size)
            text += (f"| {title} | {size} | {median(values, 'scanSteps'):.0f} | "
                f"{median(values, 'nodeConstructionSteps'):.0f} | {median(values, 'patchSteps'):.0f} |\n")
    text += """
RSS 使用 Linux VmHWM，检查点位于独立 batch oracle 之前；包含运行时、源文本、AST、
replica 和每次 feed 的 Int64 延迟数组。它不是阶段增量或 live heap。短进程尚未触发默认
GC 时，临时分配也可能抬高峰值。单字节 feed 明显增加成本；本实现不宣称常量内存。

## 可恢复输出

计时从 session 构造前开始。sink 使用计数与 FNV checksum，不保留完整 HTML，并交替
拒绝和确认片段；结束后与同步输出的字节数和 checksum 对照。完整字节级正确性另由
标准语料暂停/恢复回归保护。

| 字节 | chunk | 构造 µs | 首次 sink 调用 µs | 总计 ms | 最大未确认字节 | 峰值 RSS MiB |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
"""
    for width in (7, 4096):
        values = group("output", "closed", width)
        text += (f"| {values[0]['inputBytes']} | {width} | {median(values, 'constructionNanos') / 1e3:.3f} | "
            f"{median(values, 'firstWriteNanos') / 1e3:.3f} | {median(values, 'totalNanos') / 1e6:.3f} | "
            f"{median(values, 'largestPendingBytes'):.0f} | {median(values, 'peakRssKiB') / 1024:.2f} |\n")
    text += """
## 复现

先用官方 STS 1.2.0 构建相同 source tree，再激活该 SDK 环境。输出目录必须尚不存在，
并位于有足够空间的磁盘目录；Linux 需要 taskset 和 /proc。

```sh
cjpm build
python3 benchmarks/measure_append.py \\
  --library-directory target/release/markdown --output "$TMPDIR/append-cost"
python3 benchmarks/summarize_append.py "$TMPDIR/append-cost/result.json" \\
  --output "$TMPDIR/append-report" --revision <measured-commit>
```

runner 检查测量期间 source/library 未变化，并记录编译器、driver、library 和 source tree
身份。调用者提供 library 的源码重建证明仍是单独责任；本报告没有声称 hosted CI、跨平台
或发布认证。七轮样本不足以给出可靠 P95，也未据此下编辑/缓存优化的采用结论。
"""
    write_report(output / "append-cost.md", text)


if __name__ == "__main__":
    main()
