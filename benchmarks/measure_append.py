#!/usr/bin/env python3
"""Measure public append/output operations against an explicitly built library.

Run under the selected SDK environment. Reports are exploratory workload
evidence, not a substitute for the frozen release benchmark or its replay proof.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess

from benchmark_identity import benchmark_product_tree_sha256

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=7)
    parser.add_argument("--units", nargs="+", type=int, default=[64, 256, 1024])
    parser.add_argument("--widths", nargs="+", type=int, default=[1, 7, 4096])
    parser.add_argument("--cpu", type=int)
    args = parser.parse_args()
    if args.runs < 7 or any(n <= 0 for n in args.units + args.widths):
        parser.error("at least seven samples and positive sizes are required")
    cpu = min(os.sched_getaffinity(0)) if args.cpu is None else args.cpu
    if cpu not in os.sched_getaffinity(0):
        parser.error("selected CPU is outside the process affinity")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    library = args.library_directory.resolve()
    product_tree = benchmark_product_tree_sha256(ROOT)
    library_hash = digest(library / "libmarkdown.a")
    source = ROOT / "benchmarks/append_workload.cj"
    executable = output / "append_workload"
    environment = os.environ | {
        "TMPDIR": str(output), "TMP": str(output), "TEMP": str(output),
        "cjHeapSize": "2GB", "cjGCInterval": "500ms",
        "LC_ALL": "C.UTF-8", "LANG": "C.UTF-8", "TZ": "UTC",
    }
    compiler = shutil.which("cjc")
    if compiler is None:
        parser.error("activate the official STS 1.2.0 SDK first")
    version = subprocess.check_output([compiler, "--version"], text=True)
    if "1.2.0" not in version:
        parser.error("official STS 1.2.0 is required")
    command = [compiler, str(source), "-O2", "--obf-seed", "0", "--import-path", str(library),
        "-L", str(library), "-lmarkdown", "-o", str(executable)]
    with (output / "compile.log").open("w") as log:
        subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    cases = [("append", shape, size, width)
        for shape in ("closed", "unclosed", "references", "list")
        for size in args.units for width in args.widths]
    cases += [("output", "closed", size, width) for size in args.units for width in (7, 4096)]
    rows = []
    for sample in range(args.runs + 1):
        ordered = cases if sample % 2 == 0 else list(reversed(cases))
        for operation, shape, size, width in ordered:
            name = f"{operation}-{shape}-{size}-{width}-{sample}.tsv"
            with (output / name).open("w") as log:
                result = subprocess.run(["taskset", "-c", str(cpu), str(executable), operation, shape,
                    str(size), str(width)], env=environment, stdout=log, stderr=subprocess.STDOUT, timeout=180)
            text = (output / name).read_text()
            if result.returncode or "PASS workload equivalence\n" not in text or "Exception:" in text:
                raise ValueError(f"workload did not complete: {name}")
            lines = [line.split("\t") for line in text.splitlines()]
            rss = int(" ".join(next(line[1:] for line in lines if line[0] == "rss")).split()[1])
            data = [int(n) for n in next(line[1:] for line in lines if line[0] == operation)]
            fields = ("inputBytes", "chunkBytes", "firstBlockNanos", "firstBlockInputBytes", "finishNanos",
                "totalNanos", "scanSteps", "nodeConstructionSteps", "patchSteps", "feedCount") if operation == "append" else (
                "inputBytes", "chunkBytes", "constructionNanos", "firstWriteNanos", "totalNanos", "sinkCalls",
                "outputBytes", "largestPendingBytes")
            feeds = [int(line[2]) for line in lines if line[0] == "feed"]
            row = dict(zip(fields, data, strict=True)) | {
                "operation": operation, "shape": shape, "units": size, "sample": sample,
                "warmup": sample == 0, "peakRssKiB": rss, "rawPath": name, "rawSha256": digest(output / name),
            }
            if feeds:
                row |= {"feedMedianNanos": statistics.median(feeds), "feedMaximumNanos": max(feeds),
                    "feedTotalNanos": sum(feeds), "latencyStorageValues": len(feeds)}
            rows.append(row)
        print(f"Completed sample {sample}: {len(cases)} equivalent workloads", flush=True)
    report = {
        "schema": "markdown.append-cost/1", "sdk": version.strip(), "compilerSha256": digest(Path(compiler).resolve()),
        "driverSourceSha256": digest(source), "driverSha256": digest(executable),
        "librarySha256": library_hash, "productTreeSha256": product_tree,
        "cpu": cpu, "flags": ["-O2", "--obf-seed", "0"], "native": False,
        "heap": "2GB", "gcInterval": "500ms", "retainedSamples": args.runs, "samples": rows,
        "notes": [
            "Caller supplies the built library; source-to-library replay is a separate proof.",
            "Each case uses a fresh process; sample zero warms filesystem and host caches and is excluded.",
            "Case order reverses on alternate samples; no reliable P95 claim is made.",
            "Append total includes replica application and latency collection; feed timers include chunk slicing.",
            "RSS is Linux VmHWM before independent batch oracle, including runtime, retained source/AST and latency array.",
            "Node-construction/scan/patch counts are actual charged work, not heap allocator or RSS measurements.",
            "Output uses a counting FNV sink; no complete HTML is retained by the sink. Oracle follows RSS checkpoint.",
            "First block -1 means no feed yielded a closed block before finish; input generation is excluded from timers.",
        ],
    }
    if benchmark_product_tree_sha256(ROOT) != product_tree or digest(library / "libmarkdown.a") != library_hash:
        raise ValueError("source or library changed during measurement")
    (output / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("PASS append/output resource matrix", flush=True)


if __name__ == "__main__":
    main()
