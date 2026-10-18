#!/usr/bin/env python3
"""Measure explicit extension switches and an already installed rich runtime.

On/off results have different intended semantics. Ratios describe feature cost,
not a speedup or equivalence between the disabled and enabled configurations.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading

from benchmark_identity import benchmark_product_tree_sha256

ROOT = Path(__file__).resolve().parents[1]
RICH_SOURCE = ('Formula $\\frac{x^2}{2} + \\sqrt{y}$!\n\n```mermaid\nflowchart LR\n A[输入] --> B[AST]\n```\n\n'
               ':::code-group\r\n```js title="main.js" {2}\r\n\ufeffconst x = 1;\r\n中😀\r\n```\r\n\r\n'
               '```javascript title="empty.js"\r\n```\r\n:::\r\n')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def workload(shape: str, units: int) -> str:
    if shape == "headings":
        return "# Same 中文😀\r\n\r\n" * units
    if shape == "footnotes":
        return "Repeated[^n] and again[^n] 中文😀.\r\n\r\n" * units + "[^n]: **note**\n\n    second paragraph.\n"
    return "---\r\nlayout: example\r\n---\r\n\r\n" + "".join(
        f"# Heading {{#section-{index}}}\r\n\r\n"
        f"Text ... -- --- $x+y$[^n{index}] 中文😀.\r\n\r\n"
        f"Term {index}\r\n: **definition**[^n{index}]\r\n\r\n"
        f"[^n{index}]: note **body**\r\n\r\n    next paragraph.\r\n\r\n" for index in range(units))


def aggregate_rss(pid: int) -> tuple[int, int]:
    """Sample owned descendants; summed RSS double-counts shared resident pages."""
    pending, seen, total = [pid], set(), 0
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        try:
            status = Path(f"/proc/{current}/status").read_text()
            match = re.search(r"(?m)^VmRSS:\s*(\d+) kB", status)
            if match:
                total += int(match[1])
            # All threads can own children. Read-only; never signal by PID.
            for task in Path(f"/proc/{current}/task").iterdir():
                pending.extend(map(int, (task / "children").read_text().split()))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return total, len(seen)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library-directory", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--allow-unsandboxed-chromium", action="store_true")
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0) or not args.allow_unsandboxed_chromium:
        parser.error("an allowed CPU and explicit Chromium configuration are required")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    library, runtime = args.library_directory.resolve(), args.runtime.resolve()
    runtime_identity = (runtime / "identity").read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{64}", runtime_identity):
        raise ValueError("invalid installed runtime identity")
    compiler = Path(shutil.which("cjc") or "missing")
    sdk = subprocess.check_output([str(compiler), "--version"], text=True).strip()
    if "1.2.0" not in sdk:
        raise ValueError("official STS 1.2.0 is required")
    flags = ["-O2", "--obf-seed", "0"]
    environment = os.environ | {"TMPDIR": str(output), "TMP": str(output), "TEMP": str(output),
        "cjHeapSize": "2GB", "cjGCInterval": "500ms", "LC_ALL": "C.UTF-8", "TZ": "UTC"}
    sources = {name: ROOT / "benchmarks" / f"{name}_workload.cj" for name in ("feature", "rich")}
    source_hashes = {name: sha(path) for name, path in sources.items()}
    library_hashes = {name: sha(library / name) for name in ("libmarkdown.a", "libmarkdown.node.a")}
    harness_hash = sha(Path(__file__))
    product_tree = benchmark_product_tree_sha256(ROOT)
    for name, source in sources.items():
        (output / source.name).write_bytes(source.read_bytes())
        command = [str(compiler), str(source), *flags, "--import-path", str(library), "-L", str(library), "-lmarkdown"]
        if name == "rich":
            command += ["-lmarkdown.node"]
        with (output / f"compile-{name}.log").open("w") as log:
            subprocess.run([*command, "-o", str(output / name)], env=environment, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
    (output / "measure_features.py").write_bytes(Path(__file__).read_bytes())

    def run(command: list[str], label: str, marker: str, monitor: bool = False) -> tuple[str, dict]:
        path = output / f"{label}.log"
        peak = [0, 0]
        stopped = threading.Event()
        with path.open("w") as log:
            process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT)

            def observe() -> None:
                while not stopped.is_set():
                    rss, count = aggregate_rss(process.pid)
                    peak[0], peak[1] = max(peak[0], rss), max(peak[1], count)
                    stopped.wait(0.02)

            observer = threading.Thread(target=observe) if monitor else None
            if observer:
                observer.start()
            try:
                status = process.wait(timeout=120)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                raise
            finally:
                stopped.set()
                if observer:
                    observer.join()
        text = path.read_text()
        if status or marker + "\n" not in text or "Exception:" in text:
            raise ValueError(f"workload did not finish: {label}")
        row = {"rawPath": path.name, "rawSha256": sha(path)}
        rss = re.search(r"VmHWM:\s*(\d+) kB", text)
        if rss:
            row["peakCangjieRssKiB"] = int(rss[1])
        if monitor:
            row |= {"sampledProcessTreePeakRssKiB": peak[0], "sampledPeakProcessCount": peak[1]}
        return text, row

    inputs = []
    for shape in ("dense", "footnotes", "headings"):
        for units in (16, 64, 256):
            path = output / f"{shape}-{units}.md"
            path.write_text(workload(shape, units))
            inputs.append({"shape": shape, "units": units, "path": path.name, "bytes": path.stat().st_size,
                           "sha256": sha(path)})
    cases = [(phase, item) for item in inputs for phase in ("parse", "snapshot", "render")]
    cases += [(phase, item) for item in inputs if item["shape"] == "dense" for phase in ("decode-hot", "decode-read")]

    def feature(mode: str, phase: str, item: dict, repetitions: int, label: str) -> dict:
        wire = output / f"{item['shape']}-{item['units']}-{mode}.bin"
        text, row = run(["taskset", "-c", str(args.cpu), str(output / "feature"), mode, phase, item["shape"],
                        str(item["units"]), str(repetitions), str(output / item["path"]), str(wire)],
                       label, "PASS feature cost workload")
        metrics = re.search(r"(?m)^metrics\t(\d+)\t(\d+)$", text)
        if metrics:
            elapsed, count = map(int, metrics.groups())
            row |= {"batchNanos": elapsed, "repetitions": count, "nanos": elapsed / count}
        summary = re.search(r"(?m)^summary\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)$", text)
        row |= dict(zip(("inputBytes", "nodeCount", "footnoteCount", "referenceCount", "headingCount"),
                        map(int, summary.groups()), strict=True))
        return row | {"mode": mode, "phase": phase, "shape": item["shape"], "units": item["units"]}

    for item in inputs:
        if item["shape"] == "dense":
            for mode in ("off", "on"):
                feature(mode, "prepare", item, 1, f"prepare-{item['units']}-{mode}")
                item[f"{mode}WireSha256"] = sha(output / f"dense-{item['units']}-{mode}.bin")
    calibration, repetitions = [], {}
    for phase, item in cases:
        row = feature("off", phase, item, 1, f"calibrate-{phase}-{item['shape']}-{item['units']}")
        calibration.append(row)
        repetitions[phase, item["shape"], item["units"]] = max(1, min(1024, math.ceil(250_000_000 / row["nanos"])))
    rows = []
    for sample in range(8):
        for phase, item in cases if sample % 2 else reversed(cases):
            for pair, modes in (("aa", ["off", "off"]), ("ab", ["off", "on"] if sample % 2 else ["on", "off"])):
                for leg, mode in enumerate(modes):
                    row = feature(mode, phase, item, repetitions[phase, item["shape"], item["units"]],
                                  f"{phase}-{item['shape']}-{item['units']}-{sample}-{pair}-{leg}")
                    rows.append(row | {"sample": sample, "warmup": sample == 0, "pair": pair, "leg": leg})
        print(f"Feature round {sample} complete: {len(cases) * 4} validated processes", flush=True)
    rich_input = output / "rich.md"
    rich_input.write_text(RICH_SOURCE)
    rich_rows = []
    phases = ("disabled", "missing", "cold", "warm", "render-fallback", "render-prepared")
    for sample in range(8):
        for phase in phases if sample % 2 else reversed(phases):
            text, row = run(["taskset", "-c", str(args.cpu), str(output / "rich"), phase, str(runtime),
                             str(output), str(rich_input), "allow-unsandboxed-chromium"],
                            f"rich-{phase}-{sample}", "PASS actual rich cost workload", monitor=True)
            values = map(int, re.search(r"(?m)^metrics\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)$", text).groups())
            row |= dict(zip(("nanos", "initializeNanos", "cacheEntries", "cacheAccountedBytes", "htmlBytes"), values, strict=True))
            rich_rows.append(row | {"phase": phase, "sample": sample, "warmup": sample == 0})
        print(f"Rich round {sample} complete: 6 actual/fallback processes", flush=True)
    if source_hashes != {name: sha(path) for name, path in sources.items()} or harness_hash != sha(Path(__file__)):
        raise ValueError("source or harness changed")
    if library_hashes != {name: sha(library / name) for name in library_hashes} or product_tree != benchmark_product_tree_sha256(ROOT):
        raise ValueError("production changed")
    report = {"schema": "markdown.feature-cost/1", "productTreeSha256": product_tree, "sdk": sdk,
        "compilerSha256": sha(compiler.resolve()), "flags": flags, "librarySha256": library_hashes,
        "sourceSha256": source_hashes, "executableSha256": {name: sha(output / name) for name in sources},
        "harnessSha256": harness_hash, "runtimeIdentity": runtime_identity, "inputs": inputs,
        "richInputSha256": sha(rich_input), "richInputBytes": rich_input.stat().st_size,
        "cpu": args.cpu, "heap": "2GB", "gcInterval": "500ms", "calibration": calibration,
        "rows": rows, "richRows": rich_rows, "retainedSamples": 7,
        "notes": ["Feature on/off intentionally have different semantics; each checks its own exact source, bindings and full-parse output oracle.",
            "CommonMark0312; dense uses all six P1 extensions, other shapes only their named extension; native disabled.",
            "One baseline pilot fixes batch to ceil(250ms / time), cap1024 before A/A and alternating A/B; first round excluded.",
            "Decode hot preloads only wire; decode read includes warm-filesystem read with a fresh engine/process, not cold storage.",
            "Source string is loaded for later oracles; render setup parses outside timer, remains in VmHWM.",
            "Rich cold has an empty application cache and starts actual Node/Chrome; warm fills cache outside timer then validates/reuses all four products.",
            "Rich renderer setup/first preparation are outside render timer but remain in process-tree RSS.",
            "20ms read-only process-tree RSS samples sum shared pages; they can miss short-lived peaks and are not physical/live-heap memory.",
            "Rich process-tree samples cover full process including setup; Cangjie VmHWM excludes external Node/Chrome.",
            "Actual backend product bytes are accounted cache size, not heap. No mock, downloads, implicit enabling or OS sandbox claim.",
            "Exploratory feature costs, not adoption, P95, frozen release or offline binary replay certification."]}
    (output / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("PASS feature and actual rich cost matrix", flush=True)


if __name__ == "__main__":
    main()
