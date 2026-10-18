#!/usr/bin/env python3
"""Export immutable editor/cache experiments after verifying every retained log.

This exports historical exploratory measurements, not a release certification.
No timing, identity or acceptance threshold is rewritten for a newer product.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


REPORTS = {
    "editor-cost-matrix-v3": "95b04371b7e2f9fc47fcd9f5359d916689876ebd2f17c7f8c690ac12ae38e8a2",
    "editor-cost-matrix-v4": "2ccbee73674cecd6506c3e1e1cd686e3f299847f1b81e14628711e7d4a0a068b",
    "editor-local-matrix-v6": "8a5e95971d6eb8812d5bfadf4ff4503ef6aed7057db01ace06acb7d5a88fd614",
    "cache-cost-matrix-v8": "15591e26f75a8937800615c9331c51449131994e6d9cffb293ba1ceb517cf134",
    "cache-shared-cost-v9": "6ad93a16eca0560ee3884d10df117bf6b861ab6d866ed3b77c82ec741f032e0e",
    "public-encode-cost-final": "1c28e54453ab92f9842782ffc8ba2be351be3f9d92ece2786985b4aa34dbbf88",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def retained_path(directory: Path, name: str) -> Path:
    path = Path(name)
    if path.is_absolute() or len(path.parts) != 1:
        raise ValueError("expected a retained file in the measurement directory")
    target = directory / path
    if target.is_symlink() or not target.is_file():
        raise ValueError("missing regular retained evidence")
    return target


def write(path: Path, value: str) -> None:
    if path.exists() and path.read_text() != value:
        raise FileExistsError("refusing to replace different historical evidence")
    path.write_text(value)


def table(rows: list[dict]) -> str:
    text = "| 阶段 / 候选 | KiB | 基线 ms | 候选 ms | 中位节省 % | 最大 A/A % | RSS 比 | 统计门槛 |\n"
    text += "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n"
    for row in rows:
        label = "/".join(filter(None, [row.get("phase", "encode"), row.get("candidate", "")]))
        text += (f"| {label} | {row['requestedBytes'] // 1024} | {row['baselineMedianNanos'] / 1e6:.3f} | "
                 f"{row['candidateMedianNanos'] / 1e6:.3f} | {100 * row['medianSaving']:.2f} | "
                 f"{100 * row['maximumAaDeviation']:.2f} | {row['peakRssRatio']:.3f} | "
                 f"{'PASS' if row['thresholdPass'] else '未通过'} |\n")
    return text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    experiments = {}
    for name, digest in REPORTS.items():
        directory = args.evidence_root / name
        report_path = directory / "result.json"
        if sha(report_path) != digest:
            raise ValueError(f"historical report changed: {name}")
        data = json.loads(report_path.read_text())
        for row in data["rows"] + data.get("calibration", []):
            raw = retained_path(directory, row["rawPath"])
            if sha(raw) != row["rawSha256"]:
                raise ValueError(f"sample changed: {name}/{raw.name}")
            text = raw.read_text()
            if "Exception:" in text or "PASS " not in text:
                raise ValueError("retained process did not finish its oracle")
            hits = re.findall(r"(?m)^editHits\t(\d+)\t(\d+)$", text)
            if hits:
                row["editSequenceCount"] = len(hits)
                row["totalFastPathHits"] = sum(int(hit) for hit, _ in hits)
                row["totalEdits"] = sum(int(count) for _, count in hits)
        inputs = data.get("inputs", [])
        for entry in inputs.values() if isinstance(inputs, dict) else inputs:
            name_field = "path" if "path" in entry else "wirePath"
            if name_field in entry:
                path = retained_path(directory, entry[name_field])
                if sha(path) != entry.get("sha256", entry.get("wireSha256")):
                    raise ValueError("retained measurement input changed")
        # Export all raw numeric rows and original file digests. A CPU number is
        # machine-local; the affinity policy is the relevant public constraint.
        data.pop("cpu", None)
        data["affinity"] = "one logical CPU per experiment"
        data["retainedReportSha256"] = digest
        serialized = json.dumps(data, ensure_ascii=False)
        if re.search(r"/home/|/Users/|[A-Z]:\\\\Users\\\\", serialized):
            raise ValueError("environment path in public projection")
        experiments[name] = data
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    projection = {"schema": "markdown.editor-cache-experiments/1", "experiments": experiments,
                  "certification": "exploratory only; not frozen release or source-to-binary replay"}
    write(output / "editor-cache-cost-raw.json", json.dumps(projection, ensure_ascii=False, indent=2) + "\n")
    text = """# 编辑与缓存：测量和取舍

结论：保留生产中的等长局部编辑、诚实的完整回退和 source-reparse snapshot reader。
本轮没有采用 CST 合并、变长局部编辑、直接 AST/CST reader 或 source hash 复用。
受限缓存原型测得收益，但仍缺通用语法认证；其他候选未达到预先固定的整体采用门槛。
这些结论不表示已经证明候选在所有负载下无收益。

## 身份与方法

被测生产修订为 `d90f112`（v3/v4）及 `8fa725e`（v6/v8/v9/public），对应产品 tree
`e601aadd050b9ee92730448fcee73a949b0a6f94121869a4ee61d8a30104ee87` 和
`3c3fa3fc336fd2c83e04ca132157edd934c18a4cebc1798d55c4a75c041173ef`。
官方 STS 1.2.0，`-O2 --obf-seed 0`，单逻辑 CPU，heap 2GB、GC interval 500ms，
CommonMark 0.31.2、native 关闭，无扩展。输入为含中文、emoji、CRLF 的段落/标题，
目标规模 16/64/256KiB；每个编辑序列含十次操作。v3 同时分离 parse、snapshot、CST、
map、encode/write、decode/read-decode、render 和 SourceMap，共 12 个阶段。

每组一轮预热后保留七轮，独立进程，A/A 配对，交替 A/B 并反转场景顺序。后续批次
在测量前由基线 pilot 固定到约 500ms（最多 1024 次），没有按结果调门槛。
采用要求为中位节省至少 10%、大于七对 A/A 的**最大绝对比值偏差的两倍**，且中位
峰值 RSS 不超过 1.20 倍。RSS 是进程 VmHWM，包含 runtime、setup、保留输入和批次
垃圾；不是 live heap 或阶段额外内存。构造器/扫描/map 访问计数不等于堆分配次数。
无 P95、冷存储、零回退或冻结 release gate 结论。

[完整逐进程数值、比较、输入及日志 SHA-256](editor-cache-cost-raw.json) 保留预热与失败门槛，
没有挑选通过的规模。导出器逐个验证原始日志和输入字节；历史 source/executable/
instrumenter 身份保持原值。当前格式化后的探针不会冒充当时源码的精确重放。

## CST 与编辑

v3 共 1728 个进程，比较标量 Text token 基线、排序边界和 byte bitmap 合并；所有
oracle 通过。候选保留全部语义 span 边界，未把 source events 换成完整 AST 结果。
v4 是预先按 v3 基线校准批次数的有界跟进，共 288 个进程；九组中八组未通过 A/A
门槛，仅 64KiB 等长编辑通过，因此没有扩大到生产。以下列出 v4 的全部九组。

"""
    text += table(experiments["editor-cost-matrix-v4"]["comparisons"])
    text += """
v6 另做真实受限变长候选：普通段落/标题插入删除、无引用/扩展，保留未变节点身份，
执行 source/arena 坐标重建、结构验证和完整 CST/map/hash。中间插入、删除分别与全解析
对照，最终序列 oracle 全通过；96 个进程的中位数没有收益。A/A 本身为 22–37%，
因此也不把负收益中位数称为可靠回退。

"""
    text += table(experiments["editor-local-matrix-v6"]["comparisons"])
    text += """
256KiB 的十次编辑，扫描收费从 5,059,660 降到 276,070，但 AST record 构造仍为 92,030，
CST token 构造仍为 2,207,835，map token 访问仍为 6,439,445。减少 parser 扫描不足以
抵消坐标/CST/map/hash 成本。生产等长路径十次命中十次；该变长序列十次完整回退，
候选则十次局部命中。命中率只描述这个输入，不推广到任意编辑；raw rows 包含实际
editHits 汇总。跨块及引用/脚注/标题依赖的完整回退另由公开语义测试验证。

## 缓存恢复的受限可行性

v8 比较 MCJ3 source 重解析、恢复 AST 后完整重建 CST/map/hash、恢复 AST+token 后重建
层级/map/hash。576 个进程通过节点数、HTML+SourceMap、每个 CST token 的 raw/span
及生产 binary semantic digest 的字节对照。原型只支持 <=1MiB 的普通 Doc/Para/Heading/
Text，无引用/扩展。它校验版本/配置/checksum、UTF-8、范围、后序图归属、单一根、
token 覆盖和尾随数据，但**故意未实现通用 source grammar 认证**。checksum 不能替代
这一步。结果是乐观可行性下界，不能将该 reader 交付给不可信任意缓存。

| 输入目标 KiB | source wire bytes | AST wire bytes | AST+token wire bytes |
| ---: | ---: | ---: | ---: |
"""
    cache = experiments["cache-cost-matrix-v8"]
    for size in (16384, 65536, 262144):
        counts = {row["mode"]: row["wireBytes"] for row in cache["inputs"] if row["requestedBytes"] == size}
        text += f"| {size // 1024} | {counts['source']} | {counts['ast']} | {counts['direct']} |\n"
    text += "\n以下完整列出 warm-filesystem read+decode；byte-array decode 是另列阶段，64/256KiB 未通过噪声门槛。\n\n"
    text += table([row for row in cache["comparisons"] if row["phase"] == "cache-read-decode"])
    text += """
AST wire 约为 source 的 1.25–1.31 倍，AST+token 为 2.06–2.15 倍。AST 恢复在该受限
warm-FS 场景测得 30–41% 中位节省，直接 token 恢复为 23–34%。较大的格式、尚缺的
通用校验和未覆盖语义使其不能替代当前简单 reader；不能把不采用写成“未测得收益”。
写入包括 encode+close、不含 fsync；未清空操作系统页缓存，不宣称冷盘加速。新的
decoder 进程仅保留所选 wire，不预建源 AST/CST 或其他格式以抬高基线。

## 最小完整校验候选与公开复核

v9 不增加格式：仍为 MCJ3、完整 source parse 和 AST digest，只复用不可变 snapshot
已验证 source digest；CST 复用前仍逐字比较 source。384 个插桩进程中 encode 三组通过
预设门槛，decode/read 未通过，后者从未应用。短暂应用 encode 候选后，1620 项完整
测试通过，1371 份公开 API 产物逐字节相同并通过读取/重编码/HTML/source/CST 检查。
输入包括固定 CM 652 + GFM 671 以及四个公开 profile 下的 48 份语义 fixture。

随后用两份**未插桩正式库**独立测了 96 个进程，全部三组如下：

"""
    text += table(experiments["public-encode-cost-final"]["comparisons"])
    text += """
256KiB 组 A/A 最大偏差 33.04%，因此即使三个规模的中位数均有节省，也不能认证整体
收益。未重新跑到通过、放宽门槛或只采用较小规模；生产 encode 修改已撤回。原库
重新构建 SHA-256 为 `7442475095517d3a9123dc09ebb8e496303f08239bdfde01cf644fd77647e163`，
与原基线字节一致。候选库为
`1e4dc4eab014a0fb9ecf73d3b27b508f8548bc668017bbe0a8313e3c508c0776`。
独立 byte proof 输入 SHA-256 为
`e31c7db59beb677f15c75f1264483a4209c60a7019dc420eb7e82001721af52b`。

## 决策与复现边界

| 候选 | 决策 | 依据 |
| --- | --- | --- |
| CST Text 合并 | 不采用 | 大部分目标组未越过预设 A/A 噪声门槛 |
| 变长局部编辑 | 不采用 | 完整坐标/CST/map/hash 后未测得中位收益，噪声不支持可靠回退结论 |
| AST 或 AST+token wire | 不交付 | 受限负载有收益，但通用语法认证未完成，格式更大 |
| source digest 复用 | 不采用 | 插桩门槛通过，正式公开库复核的最大规模噪声门槛失败 |

探针与命令见 [probe README](../../benchmarks/probes/README.md)。生产 source 基线归档
SHA-256 为 `073ec1a90c74c24ed9225d1634d619d590c043a32e340627616e5b6ec0668850`。
这批实验的修改源码、原始日志、执行文件和 build.json 独立保留；v3 的早期 Python runner
后来扩展过，未在原运行前单独复制，因此不声称 v3 runner 的精确离线重放。
新复现须生成新目录及身份，不能覆盖或重绑本报告。后续兼容清理、能力开关和富内容
测量使用各自新修订；本文不认证它们，也不替代最后的冻结性能和 release 门禁。
"""
    write(output / "editor-cache-cost.md", text)
    print(f"Verified and exported {sum(len(data['rows']) for data in experiments.values())} process rows")


if __name__ == "__main__":
    main()
