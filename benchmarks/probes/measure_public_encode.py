#!/usr/bin/env python3
"""Verify encode costs with two uninstrumented libraries through the public API."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from library_inputs import library_digest, library_inputs, library_link_arguments


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before-library", type=Path, required=True)
    parser.add_argument("--after-library", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0):
        parser.error("an available CPU is required")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).with_name("public_encode_cost.cj")
    harness_hash = sha(Path(__file__))
    compiler = shutil.which("cjc")
    version = subprocess.check_output([compiler, "--version"], text=True)
    if "1.2.0" not in version:
        parser.error("official STS 1.2.0 is required")
    (output / "measure_public_encode.py").write_bytes(Path(__file__).read_bytes())
    (output / "public_encode_cost.cj").write_bytes(source.read_bytes())
    environment = os.environ | {"TMPDIR": str(output), "TMP": str(output), "TEMP": str(output),
        "cjHeapSize": "2GB", "cjGCInterval": "500ms", "LC_ALL": "C.UTF-8", "TZ": "UTC"}
    libraries = {"before": args.before_library.resolve(), "after": args.after_library.resolve()}
    library_hashes = {name: library_digest(path) for name, path in libraries.items()}
    helper = Path(__file__).resolve().parents[1] / "library_inputs.py"
    helper_hash = sha(helper)
    shutil.copy2(helper, output / "library_inputs.py")
    executables = {}
    for name, library in libraries.items():
        executable = output / name
        with (output / f"compile-{name}.log").open("w") as log:
            subprocess.run(["cjc", str(source), "-O2", "--obf-seed", "0", "--import-path", str(library),
                *library_link_arguments(library), "-o", str(executable)], env=environment,
                stdout=log, stderr=subprocess.STDOUT, check=True)
        executables[name] = executable
    inputs = {}
    prefix = "# heading\n\nalpha中文😀 paragraph\r\n\r\n".encode()
    line = "paragraph plain text for edit measurement 中文😀.\r\n\r\n".encode()
    for size in (16384, 65536, 262144):
        data = prefix + line * math.ceil((size - len(prefix)) / len(line))
        path = output / f"input-{size}.md"
        path.write_bytes(data)
        inputs[size] = {"path": path.name, "sha256": sha(path), "bytes": len(data)}

    def run(name: str, size: int, repetitions: int, label: str) -> dict:
        path = output / f"{label}.log"
        with path.open("w") as log:
            result = subprocess.run(["taskset", "-c", str(args.cpu), str(executables[name]),
                str(output / inputs[size]["path"]), str(repetitions)], env=environment,
                stdout=log, stderr=subprocess.STDOUT, timeout=120)
        text = path.read_text()
        marker = f"PASS public encode workload {inputs[size]['sha256']}\n"
        if result.returncode or marker not in text or "Exception:" in text:
            raise ValueError(f"public workload failed: {label}")
        metrics = next(line for line in text.splitlines() if line.startswith("metrics\t")).split("\t")
        elapsed, count, total, tail = map(int, metrics[1:])
        rss = int(re.search(r"VmHWM:\s*(\d+) kB", text)[1])
        return {"library": name, "requestedBytes": size, "batchNanos": elapsed, "repetitions": count,
            "nanos": elapsed / count, "outputBytes": total // count, "tailChecksum": tail // count,
            "peakRssKiB": rss, "rawPath": path.name, "rawSha256": sha(path)}

    calibration = []
    repetitions = {}
    for size in inputs:
        values = [run("before", size, 1, f"calibrate-{size}-{index}") for index in range(3)]
        calibration.extend(values)
        repetitions[size] = min(1024, max(1, math.ceil(500_000_000 / statistics.median(row["nanos"] for row in values))))
    rows = []
    for sample in range(8):
        for size in inputs if sample % 2 else reversed(inputs):
            for pair, names in (("aa", ["before", "before"]), ("ab", ["before", "after"] if sample % 2 else ["after", "before"])):
                for leg, name in enumerate(names):
                    row = run(name, size, repetitions[size], f"{size}-{sample}-{pair}-{leg}")
                    rows.append(row | {"sample": sample, "warmup": sample == 0, "pair": pair, "leg": leg})
        print(f"Completed public encode sample {sample}: 12 processes", flush=True)
    comparisons = []
    for size in inputs:
        noise = []
        for sample in range(1, 8):
            pair = [row for row in rows if row["requestedBytes"] == size and row["sample"] == sample and row["pair"] == "aa"]
            noise.append(abs(pair[1]["nanos"] / pair[0]["nanos"] - 1))
        pair = [row for row in rows if row["requestedBytes"] == size and not row["warmup"] and row["pair"] == "ab"]
        before = [row for row in pair if row["library"] == "before"]
        after = [row for row in pair if row["library"] == "after"]
        baseline = statistics.median(row["nanos"] for row in before)
        candidate = statistics.median(row["nanos"] for row in after)
        saving = 1 - candidate / baseline
        ratio = statistics.median(row["peakRssKiB"] for row in after) / statistics.median(row["peakRssKiB"] for row in before)
        if len({row["outputBytes"] for row in pair}) != 1 or len({row["tailChecksum"] for row in pair}) != 1:
            raise ValueError("public encoded output summaries differ")
        comparisons.append({"requestedBytes": size, "baselineMedianNanos": baseline, "candidateMedianNanos": candidate,
            "medianSaving": saving, "maximumAaDeviation": max(noise), "peakRssRatio": ratio,
            "thresholdPass": saving >= 0.10 and saving > 2 * max(noise) and ratio <= 1.20})
    if (sha(Path(__file__)) != harness_hash or sha(helper) != helper_hash
            or {name: library_digest(path) for name, path in libraries.items()} != library_hashes):
        raise ValueError("harness or libraries changed during measurement")
    report = {"schema": "markdown.public-encode-cost/2", "librarySha256": library_hashes,
        "libraryInputs": {name: library_inputs(path) for name, path in libraries.items()},
        "libraryInputsHelperSha256": helper_hash,
        "sdk": version.strip(), "compilerSha256": sha(Path(compiler).resolve()), "flags": ["-O2", "--obf-seed", "0"],
        "harnessSha256": harness_hash, "consumerSourceSha256": sha(source),
        "executableSha256": {name: sha(path) for name, path in executables.items()},
        "cpu": args.cpu, "heap": "2GB", "gcInterval": "500ms", "inputs": inputs,
        "calibration": calibration, "rows": rows, "comparisons": comparisons,
        "policy": "saving>=10%, >2x maximum paired AA deviation, median peakRSS<=1.20x; seven retained pairs",
        "notes": ["Uninstrumented public API consumer; snapshot setup precedes encode timer, is paid by both sides and remains in RSS.",
            "Batch count frozen from three baseline pilots to ceil(500ms/median), max1024. Nanos normalized per encode.",
            "One excluded warmup, reversed size order, alternating AB legs. No P95 claim.",
            "Output consumed by byte count/tail checksum; a separate1371-case public proof checks every wire byte.",
            "VmHWM includes runtime/setup/retained snapshot and batch garbage; oracle follows checkpoint.",
            "Caller supplies libraries; their source-to-binary replay is a separate proof, not claimed here."]}
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS public uninstrumented encode matrix", flush=True)


if __name__ == "__main__":
    main()
