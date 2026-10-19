#!/usr/bin/env python3
"""Verify and export measured feature costs without relabelling their identity."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, text: str) -> None:
    if path.exists() and path.read_text() != text:
        raise FileExistsError("choose a new path instead of replacing historical evidence")
    path.write_text(text)


def median(rows: list[dict], key: str) -> float:
    return statistics.median(row[key] for row in rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{7,40}", args.revision):
        parser.error("supply the measured production revision")
    data = json.loads(args.report.read_text())
    if data.get("schema") != "markdown.feature-cost/1" or data.get("retainedSamples") != 7:
        raise ValueError("unsupported or incomplete measurement")
    for row in data["rows"] + data["richRows"] + data["calibration"]:
        path = Path(row["rawPath"])
        if path.is_absolute() or len(path.parts) != 1 or sha(args.report.parent / path) != row["rawSha256"]:
            raise ValueError("retained sample changed")
        text = (args.report.parent / path).read_text()
        if "Exception:" in text or "PASS " not in text:
            raise ValueError("workload oracle did not finish")
    for item in data["inputs"]:
        path = Path(item["path"])
        if path.is_absolute() or len(path.parts) != 1 or sha(args.report.parent / path) != item["sha256"]:
            raise ValueError("retained input changed")
        for mode in ("off", "on"):
            if f"{mode}WireSha256" in item:
                wire = args.report.parent / f"dense-{item['units']}-{mode}.bin"
                if sha(wire) != item[f"{mode}WireSha256"]:
                    raise ValueError("retained wire changed")
    if sha(args.report.parent / "rich.md") != data["richInputSha256"]:
        raise ValueError("rich input changed")
    data.pop("cpu", None)
    data |= {"affinity": "one logical CPU", "productionRevision": args.revision,
             "retainedReportSha256": sha(args.report)}
    serialized = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if re.search(r"/home/|/Users/", serialized):
        raise ValueError("local path in public report")
    args.output.mkdir(parents=True, exist_ok=True)
    write(args.output / "feature-cost-raw.json", serialized)
    text = f"""# 扩展开关与真实富内容成本

本报告测量功能开销：开启和关闭的预期语义不同，比例不是同工作量的加速结论。
生产修订 `{args.revision}`，产品 tree `{data['productTreeSha256']}`；官方 STS 1.2.0，
`-O2 --obf-seed 0`，CommonMark 0.31.2，native 关闭，单逻辑 CPU，heap 2GB、GC 500ms。
新增 workload 与 harness 的 SHA-256 独立记录在 [完整逐进程数据](feature-cost-raw.json)，
不将新测量重绑到旧报告。完整原始报告 SHA-256 为 `{data['retainedReportSha256']}`。

1056 个 feature 进程和 48 个真实 rich/fallback 进程均通过各自 oracle，首轮预热排除，
保留七轮。feature 每组有 A/A 和交替 on/off 配对，场景顺序每轮反转；基线单次 pilot
在测量前固定批次数为 `ceil(250ms / time)`，最多 1024 次。报告全部规模，未因波动重跑。

## 扩展密集、重复脚注和标题碰撞

dense 同时开启六项 P1 扩展，包含一次 Front Matter、显式标题 ID、公式、智能标点、
定义列表和两次脚注引用。footnotes 只开启脚注，每 unit 重复引用同一定义两次；headings
只开启标题 ID，每 unit 使用同一中文/emoji 标题。关闭时均为原始 CommonMark。
每个进程校验源码、诊断、绑定目标、回链数和唯一标题目标；snapshot/cache 还与全解析
比较 HTML+SourceMap 和每个 lossless token。两种配置不要求拥有相同 AST/输出。

以下为七轮中位数。A/A 为关闭配置的最大配对比值偏差，只用于显示测量波动。
RSS 是当前进程 VmHWM：包含 runtime、setup、保留输入和批次垃圾，计时结束后、
独立 oracle 之前记录。它不是 live heap，也不能当作每次操作新增内存。

| 输入 | units | bytes | 阶段 | off ms | on ms | on/off | 最大 A/A % | off/on RSS MiB |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
"""
    rows = [row for row in data["rows"] if not row["warmup"]]
    for item in data["inputs"]:
        for phase in ("parse", "snapshot", "render", "decode-hot", "decode-read"):
            values = [row for row in rows if row["shape"] == item["shape"] and row["units"] == item["units"]
                      and row["phase"] == phase]
            if not values:
                continue
            before = [row for row in values if row["pair"] == "ab" and row["mode"] == "off"]
            after = [row for row in values if row["pair"] == "ab" and row["mode"] == "on"]
            noise = []
            for sample in range(1, 8):
                pair = [row for row in values if row["pair"] == "aa" and row["sample"] == sample]
                if len(pair) != 2:
                    raise ValueError("incomplete A/A pair")
                noise.append(abs(pair[1]["nanos"] / pair[0]["nanos"] - 1))
            if len(before) != 7 or len(after) != 7:
                raise ValueError("incomplete on/off samples")
            a, b = median(before, "nanos"), median(after, "nanos")
            text += (f"| {item['shape']} | {item['units']} | {item['bytes']} | {phase} | {a / 1e6:.3f} | "
                     f"{b / 1e6:.3f} | {b / a:.2f} | {100 * max(noise):.2f} | "
                     f"{median(before, 'peakCangjieRssKiB') / 1024:.1f} / {median(after, 'peakCangjieRssKiB') / 1024:.1f} |\n")
    text += """
dense 最大组有 256 个脚注定义和 512 个引用；footnotes 最大组是单个定义的 512 个
引用；headings 最大组有 256 个互异目标。输入规模每次扩大四倍，完整原始数据保留节点
及绑定数量，不能把这三点样本推广为任意输入复杂度保证。追加输入的小 chunk 与长尾
成本见 [append 报告](append-cost.md)，编辑序列见 [editor/cache 报告](editor-cache-cost.md)。

decode-hot 在计时前加载 byte array；decode-read 包含文件读取，在新进程/engine 中执行，
没有预建 AST/CST。两者都运行生产 reader 的 source parse、CST/map 和校验。系统页缓存
未清除，这是应用冷启动与 warm-FS 成本，不是冷盘吞吐。缓存格式没有被称为“省去 parse”。

## 固定真实后端的首次准备与缓存命中

使用已显式安装的 KaTeX 0.19.0、Mermaid CLI 12.0.0、Shiki 4.5.0，Node 24.22.0、
Chrome 155.0.8059.84 和固定字体。runtime identity 为
`""" + data["runtimeIdentity"] + """`。
fixture 包含分式/根式、中文 flowchart、BOM/CRLF/Unicode 代码及空代码块，共四个请求。
所有四个真实结果均须 Ready，最终 HTML 验证 MathML fraction/root、彩色 token 和受控
PNG；warm 要求相同 preparation fingerprint。未安装/取消/异常/网络/进程清理的正确性
另见 [Node backend](../node-rich-backend.md) 及其真实 gate，这里不以 mock 替代成本。

下面计时只覆盖所列操作。构造 backend 仅读取显式 identity，另计中位约 0.024ms。
warm 和 prepared render 在计时前真实准备一次，因此它们的进程内存仍包含该次启动。
disabled/missing 明确返回四个相应 Unavailable；missing 是未传 backend，不会自动查找。

| 操作 | 中位 ms | 最小/最大 ms | 缓存项/计费 bytes | HTML bytes | Cangjie RSS MiB | 进程树 RSS 采样 MiB | 最大进程数采样中位 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
"""
    for phase in ("disabled", "missing", "cold", "warm", "render-fallback", "render-prepared"):
        values = [row for row in data["richRows"] if row["phase"] == phase and not row["warmup"]]
        if len(values) != 7:
            raise ValueError("incomplete rich samples")
        tree = f"{median(values, 'sampledProcessTreePeakRssKiB') / 1024:.1f}" if phase in ("cold", "warm", "render-prepared") else "—"
        text += (f"| {phase} | {median(values, 'nanos') / 1e6:.3f} | "
                 f"{min(row['nanos'] for row in values) / 1e6:.3f} / {max(row['nanos'] for row in values) / 1e6:.3f} | "
                 f"{median(values, 'cacheEntries'):.0f} / {median(values, 'cacheAccountedBytes'):.0f} | "
                 f"{median(values, 'htmlBytes'):.0f} | {median(values, 'peakCangjieRssKiB') / 1024:.2f} | "
                 f"{tree} | {median(values, 'sampledPeakProcessCount'):.0f} |\n")
    text += """
cold 包含实际 Node/Chrome 启动、全部后端及准备器验证；缓存初始为空。warm 只复用四个
已验证成功产物，仍收费、检查取消并验证配置。缓存的 6657 bytes 是受控计费量，不是
堆内存。首次准备成本和外部进程内存明显高于基础 parser，因此保持默认关闭和显式宿主
接入。七轮不能证明可靠 P95 或未来机器的延迟承诺。

进程树每 20ms 只读采样一次，覆盖该消费进程及其线程拥有的后代。RSS 求和会重复计算
共享页，也会错过短暂峰值，不能作为精确物理内存；短于采样间隔的 disabled/missing/
fallback 使用 VmHWM，树采样显示为“—”。prepared/warm 的树采样包含计时前准备，
不能把它归因于缓存命中或 render 单步。所有调用结束后没有遗留 job 目录；进程清理
本身由独立实际 backend gate 证明，不以这里的 RSS 观察代替。

## 复现

先在相同生产修订构建库，显式准备相同离线 runtime，激活 STS 1.2.0，并使用新的
磁盘输出目录。此命令只消费现有 runtime，不安装或下载。

```sh
python3 benchmarks/measure_features.py \\
  --library-directory target/release/markdown --runtime <installed-runtime> \\
  --output "$TMPDIR/feature-cost" --cpu <allowed-cpu> --allow-unsandboxed-chromium
python3 benchmarks/summarize_features.py "$TMPDIR/feature-cost/result.json" \\
  --output "$TMPDIR/feature-report" --revision <measured-production-commit>
```

导出器验证每个样本及输入 hash，不覆盖不同历史报告。no-sandbox 是受信测试环境中的
明确选择，不宣称操作系统隔离。完整构建产物、原始日志和 runtime 离线准备结果独立
保留；本成本报告不代替 source-to-binary replay、冻结性能、hosted CI 或 release gate。
"""
    write(args.output / "feature-cost.md", text)
    print("Verified all feature/rich samples and exported report")


if __name__ == "__main__":
    main()
