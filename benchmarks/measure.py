#!/usr/bin/env python3
"""Run the frozen markdown release benchmark protocol and publish evidence."""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time

from generate_corpus import corpus, ordinary_corpus, COMMONMARK, GFM


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "benchmarks/driver/target/release/bin/main"
CMARK = Path(os.environ.get("MARKDOWN_CMARK_DRIVER", "/tmp/markdown-cmark-reference-driver"))
CMARK_GFM = Path(os.environ.get("MARKDOWN_CMARK_GFM_DRIVER", "/tmp/markdown-cmark-gfm-reference-driver"))
REPORT_JSON = ROOT / "docs/reports/benchmark-raw.json"
REPORT_MD = ROOT / "docs/reports/benchmark.md"
CPU = os.environ.get("MARKDOWN_BENCH_CPU", "2")
MATRIX_BYTES = 256 * 1024
MATRIX_ITERATIONS = 3
PATHOLOGICAL_SIZES = (64, 128, 256, 512)


def run_sample(command: list[str], data: bytes) -> dict[str, float | int | str]:
    started = time.perf_counter_ns()
    environment = dict(os.environ)
    environment["cjHeapSize"] = "2GB"
    process = subprocess.Popen(["taskset", "-c", CPU, *command], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    assert process.stdin is not None
    process.stdin.write(data)
    process.stdin.close()
    peak_kib = 0
    while process.poll() is None:
        try:
            status = Path(f"/proc/{process.pid}/status").read_text()
            for line in status.splitlines():
                if line.startswith("VmRSS:"):
                    peak_kib = max(peak_kib, int(line.split()[1]))
                    break
        except FileNotFoundError:
            pass
        time.sleep(0.002)
    stdout = process.stdout.read().decode() if process.stdout else ""
    stderr = process.stderr.read().decode() if process.stderr else ""
    elapsed = (time.perf_counter_ns() - started) / 1_000_000_000
    if process.returncode != 0:
        raise RuntimeError(f"benchmark failed: {' '.join(command)}\n{stderr}")
    return {"seconds": elapsed, "peakRssKiB": peak_kib, "checksum": stdout.strip()}


def samples(command: list[str], data: bytes, count: int = 7) -> list[dict[str, float | int | str]]:
    run_sample(command, data)  # warmup, intentionally excluded
    return [run_sample(command, data) for _ in range(count)]


def paired_samples(left: list[str], right: list[str], data: bytes,
        count: int = 7) -> tuple[list[dict[str, float | int | str]], list[dict[str, float | int | str]]]:
    run_sample(left, data)
    run_sample(right, data)
    left_values: list[dict[str, float | int | str]] = []
    right_values: list[dict[str, float | int | str]] = []
    for sample_index in range(count):
        order = ((left, left_values), (right, right_values)) if sample_index % 2 == 0 else (
            (right, right_values), (left, left_values))
        for command, destination in order:
            destination.append(run_sample(command, data))
    return left_values, right_values


def median_seconds(values: list[dict[str, float | int | str]]) -> float:
    return statistics.median(float(value["seconds"]) for value in values)


def geometric_mean(values: list[float]) -> float:
    return math.exp(statistics.mean(math.log(value) for value in values))


def sized(data: bytes, size: int = MATRIX_BYTES) -> bytes:
    if not data:
        data = b"\n"
    return valid_utf8_prefix((data * (size // len(data) + 1))[:size], size)


def valid_utf8_prefix(data: bytes, size: int) -> bytes:
    prefix = data[:size]
    while True:
        try:
            prefix.decode("utf-8")
            break
        except UnicodeDecodeError as error:
            prefix = prefix[:error.start]
    return prefix + b" " * (size - len(prefix))


def benchmark_corpora() -> dict[str, bytes]:
    official = (ROOT / "tests/spec/commonmark-0.31.2/spec.txt").read_bytes()
    docs = (ROOT / "README.md").read_bytes() + (ROOT / "docs/api.md").read_bytes()
    code = b"```cj\n" + (b"let parsed = Markdown.parse(\"# heading\")\n" * 8192) + b"```\n"
    table = (b"| name | value | note |\n| :--- | ---: | :---: |\n| row | 42 | ok |\n" * 4096)
    references = (b"[label]: https://example.com/path \"title\"\n\nUse [label] repeatedly.\n\n" * 4096)
    cjk = ("中文段落与链接 [示例](https://example.com/路径)。\n\n" * 4096).encode()
    emoji = ("😀 🚀 ✅ emphasis **works** and `code`.\n\n" * 4096).encode()
    deep = (("> " * 64) + "- nested item\n").encode() * 512
    delimiters = ((b"*_*_*_*_ [unclosed `code ~~strike ") * 8192)
    long_line = (b"long-line-word " * 32768) + b"\n"
    ordinary = ordinary_corpus(MATRIX_BYTES)
    extension = (b"$$\nx + y\n$$\n\n[^note]: **body**\n\nText [^note] and $x$.\n\n" * 4096)
    return {name: sized(value) for name, value in {
        "official-spec": official, "readme-api": docs, "large-code": code, "large-table": table,
        "many-references": references, "cjk": cjk, "emoji": emoji, "deep-list": deep,
        "pathological-delimiters": delimiters, "long-line": long_line, "ordinary": ordinary,
        "custom-extension": extension,
    }.items()}


def pathological_delimiter_corpus(size: int) -> bytes:
    template = b"*_*_*_*_ [unclosed `code ~~strike "
    return (template * (size // len(template) + 1))[:size]


def comparison_matrix(mode: str, reference: Path, corpora: dict[str, bytes]) -> tuple[dict[str, object], float]:
    report: dict[str, object] = {}
    ratios: list[float] = []
    for name, data in corpora.items():
        if name == "custom-extension":
            continue
        ours, theirs = paired_samples([str(DRIVER), mode, str(MATRIX_ITERATIONS)],
            [str(reference), str(MATRIX_ITERATIONS)], data)
        ratio = median_seconds(ours) / median_seconds(theirs)
        ratios.append(ratio)
        report[name] = {"markdown": ours, "reference": theirs, "medianRatio": ratio}
    return report, geometric_mean(ratios)


def slope(points: list[tuple[int, float]]) -> float:
    xs = [math.log(float(size)) for size, _ in points]
    ys = [math.log(duration) for _, duration in points]
    xmean = statistics.mean(xs)
    ymean = statistics.mean(ys)
    return sum((x - xmean) * (y - ymean) for x, y in zip(xs, ys)) / sum((x - xmean) ** 2 for x in xs)


def cpu_model() -> str:
    for line in Path("/proc/cpuinfo").read_text().splitlines():
        if line.startswith("model name"):
            return line.split(":", 1)[1].strip()
    return "unknown"


def main() -> int:
    for executable in (DRIVER, CMARK, CMARK_GFM):
        if not executable.exists():
            raise SystemExit(f"missing benchmark executable: {executable}")
    one_mib_common = corpus(COMMONMARK, 1024 * 1024)
    corpora = benchmark_corpora()
    common_matrix, common_ratio = comparison_matrix("commonmark-parse", CMARK, corpora)
    gfm_matrix, gfm_ratio = comparison_matrix("gfm-html", CMARK_GFM, corpora)
    ordinary_common_ratio = float(common_matrix["ordinary"]["medianRatio"])
    ordinary_gfm_ratio = float(gfm_matrix["ordinary"]["medianRatio"])
    extension_samples = samples([str(DRIVER), "extension-html", str(MATRIX_ITERATIONS)], corpora["custom-extension"])
    common_one_mib = samples([str(DRIVER), "commonmark-parse", "1"], one_mib_common)
    input_profile_samples = {
        "string": samples([str(DRIVER), "commonmark-parse-string", "1"], one_mib_common),
        "bytes": samples([str(DRIVER), "commonmark-parse-bytes", "1"], one_mib_common),
        "ownedBytes": samples([str(DRIVER), "commonmark-parse-owned", "1"], one_mib_common),
        "inputStream": samples([str(DRIVER), "commonmark-parse-stream", "1"], one_mib_common),
    }
    common_html = samples([str(DRIVER), "commonmark-html", "1"], one_mib_common)
    source_map = samples([str(DRIVER), "commonmark-source-map", "1"], one_mib_common)
    cst = samples([str(DRIVER), "commonmark-cst", "1"], one_mib_common)
    source_map_overhead = median_seconds(source_map) / median_seconds(common_html) - 1.0
    cst_overhead = median_seconds(cst) / median_seconds(common_one_mib) - 1.0

    scaling: dict[str, list[dict[str, float | int | str]]] = {}
    points: list[tuple[int, float]] = []
    for mib in (1, 2, 4, 8, 16):
        data = ordinary_corpus(mib * 1024 * 1024)
        values = samples([str(DRIVER), "commonmark-parse", "1"], data)
        scaling[str(mib)] = values
        points.append((mib, median_seconds(values)))
    growth_slope = slope(points)
    adjacent = [points[index + 1][1] / points[index][1] for index in range(len(points) - 1)]

    pathological_scaling: dict[str, list[dict[str, float | int | str]]] = {}
    pathological_points: list[tuple[int, float]] = []
    for kib in PATHOLOGICAL_SIZES:
        values = samples([str(DRIVER), "commonmark-parse", "1"],
            pathological_delimiter_corpus(kib * 1024), count=5)
        pathological_scaling[str(kib)] = values
        pathological_points.append((kib, median_seconds(values)))
    pathological_slope = slope(pathological_points)
    pathological_adjacent = [pathological_points[index + 1][1] / pathological_points[index][1]
        for index in range(len(pathological_points) - 1)]

    baseline = samples([str(DRIVER), "commonmark-parse", "1"], b"", count=3)
    ten_mib = samples([str(DRIVER), "commonmark-parse", "1"],
        ordinary_corpus(10 * 1024 * 1024), count=3)
    extra_rss_kib = (
        max(int(value["peakRssKiB"]) for value in ten_mib)
        - max(int(value["peakRssKiB"]) for value in baseline)
    )

    gates = {
        "commonmarkRatioLe2_5": common_ratio <= 2.5,
        "gfmRatioLe2_5": gfm_ratio <= 2.5,
        "ordinaryRepresentativeLe5": max(ordinary_common_ratio, ordinary_gfm_ratio) <= 5.0,
        "growthSlopeLe1_35": growth_slope <= 1.35,
        "adjacentGrowthLe3": max(adjacent) <= 3.0,
        "pathologicalSlopeLe1_35": pathological_slope <= 1.35,
        "tenMiBExtraRssLe8x": extra_rss_kib <= 80 * 1024,
    }
    report = {
        "environment": {"platform": platform.platform(), "machine": platform.machine(),
            "cpu": cpu_model(), "pinnedCpu": int(CPU), "cangjieOptimization": "-O2",
            "cangjieHeapSize": "2GB",
            "cmark": "0.31.1 bb3678d7a73cb02d35c8876ecd097072636200a8",
            "cmarkGfm": "0.29.0.gfm.13 587a12bb54d95ac37241377e6ddc93ea0e45439b"},
        "corpora": {name: {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()}
            for name, value in corpora.items()},
        "comparisonProtocol": {"iterationsPerProcess": MATRIX_ITERATIONS, "samples": 7,
            "ordering": "per-corpus alternating pair with reversed order on odd samples",
            "statistic": "geometric mean of per-corpus median ratios"},
        "commonmark": {"corpora": common_matrix, "geometricMeanRatio": common_ratio},
        "gfm": {"corpora": gfm_matrix, "geometricMeanRatio": gfm_ratio},
        "optionalFeatures": {"commonmarkParse": common_one_mib, "commonmarkHtml": common_html, "sourceMap": source_map,
            "cst": cst, "customExtensionHtml": extension_samples, "sourceMapTimeOverhead": source_map_overhead,
            "cstTimeOverhead": cst_overhead},
        "inputProfiles": {
            "string": {"driverMode": "commonmark-parse-string", "perParseConversionOrCopy": "none",
                "processPreparation": "stdin bytes are decoded once before repeated parse calls",
                "nativeScanner": false, "samples": input_profile_samples["string"]},
            "bytes": {"driverMode": "commonmark-parse-bytes",
                "perParseConversionOrCopy": "defensive byte copy and UTF-8 decode",
                "processPreparation": "stdin bytes retained by driver", "nativeScanner": true,
                "samples": input_profile_samples["bytes"]},
            "ownedBytes": {"driverMode": "commonmark-parse-owned",
                "perParseConversionOrCopy": "driver clone required for each ownership transfer",
                "processPreparation": "stdin bytes retained by driver", "nativeScanner": true,
                "samples": input_profile_samples["ownedBytes"]},
            "inputStream": {"driverMode": "commonmark-parse-stream",
                "perParseConversionOrCopy": "full stream buffering and UTF-8 decode",
                "processPreparation": "new in-memory stream per parse", "nativeScanner": true,
                "samples": input_profile_samples["inputStream"]},
        },
        "scaling": {"samples": scaling, "slope": growth_slope, "adjacentRatios": adjacent},
        "pathologicalScaling": {"samples": pathological_scaling, "slope": pathological_slope,
            "adjacentRatios": pathological_adjacent},
        "memory": {"baseline": baseline, "tenMiB": ten_mib, "extraPeakRssKiB": extra_rss_kib},
        "gates": gates,
    }
    REPORT_JSON.write_text(json.dumps(report, indent=2) + "\n")
    status = "PASS" if all(gates.values()) else "FAIL"
    REPORT_MD.write_text(
        "# Release benchmark report\n\n"
        f"Status: **{status}**\n\n"
        f"- CommonMark parse-only geometric mean ratio vs cmark: `{common_ratio:.2f}x` (limit `2.5x`).\n"
        f"- GFM parse+HTML geometric mean ratio vs cmark-gfm: `{gfm_ratio:.2f}x` (limit `2.5x`).\n"
        f"- Ordinary representative ratios: CommonMark `{ordinary_common_ratio:.2f}x`, GFM `{ordinary_gfm_ratio:.2f}x` (limit `5x`).\n"
        f"- 1–16 MiB log-log slope: `{growth_slope:.3f}` (limit `1.35`).\n"
        f"- Maximum adjacent doubling ratio: `{max(adjacent):.3f}` (limit `3.0`).\n"
        f"- Pathological delimiter 64–512 KiB log-log slope: `{pathological_slope:.3f}` (limit `1.35`).\n"
        f"- Pathological delimiter maximum adjacent doubling ratio: `{max(pathological_adjacent):.3f}` "
        "(informational; process startup and allocator thresholds make a single doubling noisy).\n"
        f"- 10 MiB extra peak RSS: `{extra_rss_kib} KiB` (limit `81920 KiB`).\n\n"
        f"- SourceMap time overhead vs parse+HTML: `{source_map_overhead * 100:.1f}%`.\n"
        f"- CST/snapshot time overhead vs parse-only: `{cst_overhead * 100:.1f}%`.\n\n"
        "Raw samples, corpus digests, tool commits, CPU pin, and environment are in "
        "`benchmark-raw.json`.\n"
    )
    print(json.dumps({"status": status, "commonmarkRatio": common_ratio, "gfmRatio": gfm_ratio,
        "slope": growth_slope, "maxAdjacent": max(adjacent), "pathologicalSlope": pathological_slope,
        "pathologicalMaxAdjacent": max(pathological_adjacent), "extraRssKiB": extra_rss_kib}))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
