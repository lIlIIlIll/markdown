#!/usr/bin/env python3
"""Compare complete source-reparse, AST and AST/CST prototype cache paths.

The restricted prototypes deliberately omit general source-grammar certification.
They are optimistic feasibility bounds and must never be treated as production
decoders or release evidence.
"""
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
    parser.add_argument("--candidates", nargs="+", choices=["ast", "direct", "shared"], default=["ast", "direct"])
    args = parser.parse_args()
    if args.runs < 7 or args.cpu not in os.sched_getaffinity(0):
        parser.error("at least seven retained samples and an available CPU are required")
    build = args.build.resolve()
    metadata = json.loads((build / "build.json").read_text())
    executable = build / "target/release/bin/main"
    if sha(executable) != metadata["executableSha256"]:
        raise ValueError("probe executable does not match")
    for name, digest in metadata["instrumentedFiles"].items():
        if sha(build / name) != digest:
            raise ValueError("retained instrumented source does not match")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    harness_hash = sha(Path(__file__))
    (output / "measure_cache_cost.py").write_bytes(Path(__file__).read_bytes())
    environment = os.environ | {"TMPDIR": str(output), "TMP": str(output), "TEMP": str(output),
        "cjHeapSize": "2GB", "cjGCInterval": "500ms", "LC_ALL": "C.UTF-8", "TZ": "UTC"}

    def run(mode: str, phase: str, size: int, wire: Path, name: str, repetitions: int = 1) -> tuple[str, dict]:
        with (output / name).open("w") as log:
            result = subprocess.run(["taskset", "-c", str(args.cpu), str(executable), mode, phase, str(size),
                str(wire), str(repetitions)], env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        text = (output / name).read_text()
        if result.returncode or "PASS editor cost probe\n" not in text or "Exception:" in text:
            raise ValueError(f"cache probe did not finish: {name}")
        metrics = next((line for line in text.splitlines() if line.startswith("metrics\t")), None)
        row = {"rawPath": name, "rawSha256": sha(output / name), "repetitions": repetitions}
        if metrics:
            row |= dict(zip(("batchNanos", "astRecordConstructions", "syntaxTokenConstructions", "syntaxNodeConstructions",
                "chargedScanSteps", "mapTokenVisits", "lexerBytesConsumed"), map(int, metrics.split("\t")[1:]), strict=True))
            row["nanos"] = row["batchNanos"] / repetitions
            for label in ("rssBefore", "rssAfter"):
                line = next(line for line in text.splitlines() if line.startswith(label + "\t"))
                for field, key in (("VmHWM", "peakRssKiB"), ("VmRSS", "residentKiB")):
                    row[f"{label}_{key}"] = int(re.search(field + r":\s*(\d+) kB", line)[1])
        return text, row

    inputs = []
    for size in args.sizes:
        for mode in ["source", *args.candidates]:
            wire = output / f"input-{mode}-{size}.bin"
            text, row = run(mode, "cache-prepare", size, wire, f"prepare-{mode}-{size}.log")
            inputs.append(row | {"mode": mode, "requestedBytes": size, "wirePath": wire.name,
                "wireBytes": wire.stat().st_size, "wireSha256": sha(wire)})
    if "shared" in args.candidates:
        for size in args.sizes:
            hashes = [entry["wireSha256"] for entry in inputs if entry["requestedBytes"] == size and entry["mode"] in ("source", "shared")]
            if len(set(hashes)) != 1:
                raise ValueError("shared digest candidate changed the wire bytes")
    phases = ("cache-encode", "cache-write", "cache-decode", "cache-read-decode")
    cases = [(phase, size) for phase in phases for size in args.sizes]
    calibration = []
    repetitions = {}
    for phase, size in cases:
        samples = []
        for index in range(3):
            wire = output / (f"input-source-{size}.bin" if "decode" in phase else f"work-source-{size}.bin")
            _, row = run("source", phase, size, wire, f"calibrate-{phase}-{size}-{index}.log")
            calibration.append(row | {"phase": phase, "requestedBytes": size})
            samples.append(row["nanos"])
        repetitions[phase, size] = min(1024, max(1, math.ceil(500_000_000 / statistics.median(samples))))
    rows = []
    for sample in range(args.runs + 1):
        for phase, size in cases if sample % 2 == 0 else reversed(cases):
            for pair, candidate in [("aa", "source")] + [(mode, mode) for mode in args.candidates]:
                modes = ["source", candidate] if sample % 2 else [candidate, "source"]
                for leg, mode in enumerate(modes):
                    wire = output / (f"input-{mode}-{size}.bin" if "decode" in phase else f"work-{mode}-{size}.bin")
                    _, row = run(mode, phase, size, wire, f"{phase}-{size}-{sample}-{pair}-{leg}.log", repetitions[phase, size])
                    rows.append(row | {"phase": phase, "requestedBytes": size, "sample": sample,
                        "warmup": sample == 0, "pair": pair, "leg": leg, "mode": mode})
        print(f"Completed cache cost sample {sample}: {len(cases) * (2 + 2 * len(args.candidates))} equivalent processes", flush=True)
    comparisons = []
    for phase, size in cases:
        noise = []
        for sample in range(1, args.runs + 1):
            values = [row for row in rows if row["phase"] == phase and row["requestedBytes"] == size
                and row["sample"] == sample and row["pair"] == "aa"]
            noise.append(abs(values[1]["nanos"] / values[0]["nanos"] - 1))
        for mode in args.candidates:
            values = [row for row in rows if row["phase"] == phase and row["requestedBytes"] == size
                and not row["warmup"] and row["pair"] == mode]
            before = [row for row in values if row["mode"] == "source"]
            after = [row for row in values if row["mode"] == mode]
            baseline = statistics.median(row["nanos"] for row in before)
            candidate = statistics.median(row["nanos"] for row in after)
            saving = 1 - candidate / baseline
            ratio = statistics.median(row["rssAfter_peakRssKiB"] for row in after) / statistics.median(
                row["rssAfter_peakRssKiB"] for row in before)
            comparisons.append({"phase": phase, "requestedBytes": size, "candidate": mode,
                "baselineMedianNanos": baseline, "candidateMedianNanos": candidate, "medianSaving": saving,
                "maximumAaDeviation": max(noise), "peakRssRatio": ratio,
                "thresholdPass": saving >= 0.10 and saving > 2 * max(noise) and ratio <= 1.20})
    for entry in inputs:
        if sha(output / entry["wirePath"]) != entry["wireSha256"]:
            raise ValueError("prepared input changed")
    if sha(executable) != metadata["executableSha256"] or sha(Path(__file__)) != harness_hash:
        raise ValueError("executable or measurement harness changed")
    report = {"schema": "markdown.cache-cost/1", "build": metadata, "measurementHarnessSha256": harness_hash,
        "cpu": args.cpu, "heap": "2GB", "gcInterval": "500ms", "retainedSamples": args.runs,
        "calibration": calibration, "inputs": inputs, "rows": rows, "comparisons": comparisons,
        "policy": "median saving >=10%, >2x maximum absolute paired AA ratio deviation; median peak RSS <=1.20x",
        "notes": ["Shared mode retains production source reparse, AST digest and byte-identical MCJ3; reuses verified source digests after CST equality check.",
            "AST/direct modes: restricted primitive AST and token format <=1MiB source; unknown kinds/payloads rejected.",
            "Prototype structure/UTF8/config/checksum validation is not complete general source-grammar certification.",
            "Optimistic feasibility bounds only, not production decoders or release/offline-replay proof.",
            "A fresh decoder process retains only its selected wire, not a prebuilt source AST/CST or other wire variants.",
            "Byte-array decode and warm-filesystem read+decode are separate. No cold-storage claim.",
            "Encode/write setup includes a source snapshot; write includes close and no fsync.",
            "Batch counts calibrated from three baseline pilots before sampling to ceil(500ms/median), capped1024.",
            "Counters are actual batch constructor/charged work totals, not heap allocation; nanos normalized per operation.",
            "VmRSS/HWM include runtime/setup/retained inputs. Checks and independent batch oracle follow timer/RSS.",
            "Seven retained pairs, excluded warmup, reversed case order and alternating AB legs. No P95 claim."]}
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS cache cost A/A and A/B matrix", flush=True)


if __name__ == "__main__":
    main()
