#!/usr/bin/env python3
"""Collect A/A and alternating A/B samples from the isolated CST experiment."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--sizes", type=int, nargs="+", default=[16384, 65536, 262144])
    parser.add_argument("--phases", nargs="+", default=["parse", "snapshot", "cst", "map", "equal-edit", "variable-edit",
        "encode", "write", "decode", "read-decode", "render", "source-map"])
    parser.add_argument("--candidates", nargs="+", choices=["sorted", "bitmap", "local"], default=["sorted", "bitmap"])
    parser.add_argument("--repeat-from", type=Path, help="Prior report: preset each batch to at least 500ms from baseline medians")
    args = parser.parse_args()
    if args.runs < 7 or args.cpu not in os.sched_getaffinity(0):
        parser.error("at least seven samples and an available CPU are required")
    build = args.build.resolve()
    metadata = json.loads((build / "build.json").read_text())
    executable = build / "target/release/bin/main"
    if sha(executable) != metadata["executableSha256"]:
        raise ValueError("probe executable changed")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    harness_hash = sha(Path(__file__))
    (output / "measure_editor_cost.py").write_bytes(Path(__file__).read_bytes())
    environment = os.environ | {"TMPDIR": str(output), "TMP": str(output), "TEMP": str(output),
        "cjHeapSize": "2GB", "cjGCInterval": "500ms", "LC_ALL": "C.UTF-8", "TZ": "UTC"}
    cases = [(phase, size) for phase in args.phases for size in args.sizes]
    repeats = {case: 1 for case in cases}
    if args.repeat_from:
        prior = json.loads(args.repeat_from.read_text())
        for phase, size in cases:
            times = [row["nanos"] for row in prior["rows"] if row["phase"] == phase and row["requestedBytes"] == size
                and row["mode"] == "before" and not row["warmup"]]
            repeats[phase, size] = max(1, min(1024, math.ceil(500_000_000 / statistics.median(times))))
    rows = []
    for sample in range(args.runs + 1):
        for phase, size in cases if sample % 2 == 0 else reversed(cases):
            pairs = [("aa", "before")] + [(name, {"sorted": "candidate", "bitmap": "bitmap", "local": "local"}[name]) for name in args.candidates]
            for pair, candidate in pairs:
                modes = ["before", candidate] if sample % 2 else [candidate, "before"]
                for leg, mode in enumerate(modes):
                    name = f"{phase}-{size}-{sample}-{pair}-{leg}.log"
                    with (output / name).open("w") as log:
                        command = ["taskset", "-c", str(args.cpu), str(executable), mode, phase, str(size), str(output / "artifact.bin")]
                        if args.repeat_from: command.append(str(repeats[phase, size]))
                        result = subprocess.run(command, env=environment,
                            stdout=log, stderr=subprocess.STDOUT, timeout=120)
                    text = (output / name).read_text()
                    if result.returncode or "PASS editor cost probe\n" not in text or "Exception:" in text:
                        raise ValueError(f"probe failed: {name}")
                    metrics = next(line for line in text.splitlines() if line.startswith("metrics\t")).split("\t")
                    row = dict(zip(("nanos", "astRecordConstructions", "syntaxTokenConstructions", "syntaxNodeConstructions",
                        "chargedScanSteps", "mapTokenVisits", "lexerBytesConsumed"), map(int, metrics[1:]), strict=True))
                    row |= {"batchNanos": row["nanos"], "repetitions": repeats[phase, size]}
                    row["nanos"] /= repeats[phase, size]
                    row |= {"sample": sample, "warmup": sample == 0, "pair": pair, "leg": leg, "mode": mode,
                        "phase": phase, "requestedBytes": size, "rawPath": name, "rawSha256": sha(output / name)}
                    for label in ("rssBefore", "rssAfter"):
                        line = next(line for line in text.splitlines() if line.startswith(label + "\t"))
                        for name_rss, key in (("VmHWM", "peakRssKiB"), ("VmRSS", "residentKiB")):
                            row[f"{label}_{key}"] = int(re.search(name_rss + r":\s*(\d+) kB", line)[1])
                    rows.append(row)
        print(f"Completed editor cost sample {sample}: {len(cases) * (2 + 2 * len(args.candidates))} equivalent processes", flush=True)
    comparisons = []
    for phase, size in cases:
        aa_noise = []
        for sample in range(1, args.runs + 1):
            aa = [row for row in rows if row["phase"] == phase and row["requestedBytes"] == size
                and row["sample"] == sample and row["pair"] == "aa"]
            aa_noise.append(abs(aa[1]["nanos"] / aa[0]["nanos"] - 1))
        noise = max(aa_noise)
        for pair in args.candidates:
            values = [row for row in rows if not row["warmup"] and row["phase"] == phase
                and row["requestedBytes"] == size and row["pair"] == pair]
            baseline = [row for row in values if row["mode"] == "before"]
            candidate = [row for row in values if row["mode"] != "before"]
            before = statistics.median(row["nanos"] for row in baseline)
            after = statistics.median(row["nanos"] for row in candidate)
            saving = 1 - after / before
            rss_ratio = statistics.median(row["rssAfter_peakRssKiB"] for row in candidate) / statistics.median(
                row["rssAfter_peakRssKiB"] for row in baseline)
            comparisons.append({"phase": phase, "requestedBytes": size, "candidate": pair,
                "baselineMedianNanos": before, "candidateMedianNanos": after, "medianSaving": saving,
                "maximumAaDeviation": noise, "peakRssRatio": rss_ratio,
                "thresholdPass": saving >= 0.10 and saving > 2 * noise and rss_ratio <= 1.20})
    report = {"schema": "markdown.editor-cost/1", "build": metadata, "cpu": args.cpu,
        "measurementHarnessSha256": harness_hash,
        "heap": "2GB", "gcInterval": "500ms", "retainedSamples": args.runs, "rows": rows, "comparisons": comparisons,
        "policy": "median saving >=10%, greater than twice maximum absolute paired A/A ratio deviation; median peak RSS <=1.20x",
        "notes": ["Constructor and charged-work counters are instrumentation, not heap allocator counts.",
            "RSS includes setup, runtime and retained inputs; after/before VmRSS is not a live-heap measurement.",
            "Ten edits per sequence include complete source/CST/map/digest construction and the hit-count print.",
            "Oracle checks occur after the elapsed timer and RSS checkpoints.",
            "write includes encode plus close, without fsync; read-decode uses warm filesystem cache.",
            "One warmup round is excluded. Cases reverse order and A/B legs alternate; no P95 claim.",
            "Both candidate modes use the same executable and preserve every semantic span boundary."]}
    if args.repeat_from:
        report["batchCalibrationReportSha256"] = sha(args.repeat_from)
        report["batchCalibration"] = "ceil(500ms / prior baseline median), fixed before new measurements; counters are batch totals, nanos normalized per operation"
    if sha(executable) != metadata["executableSha256"] or sha(Path(__file__)) != harness_hash:
        raise ValueError("probe executable or harness changed during measurement")
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS editor cost A/A and A/B matrix", flush=True)


if __name__ == "__main__":
    main()
