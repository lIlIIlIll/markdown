#!/usr/bin/env python3
"""Compare markdown with the platform-neutral markdown4cj parser core.

The pinned markdown4cj HAR targets HarmonyOS, but ``src/core`` does not. This
runner copies only that core into a fresh cjpm project, applies a fail-closed
current-SDK collection-API migration, and links a pinned commonmark4cj checkout.
No OHOS, DevEco, UI component, prism4cj, or formula-ffi source is built.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import time

from measure import benchmark_corpora

COMPARATOR_COMMIT = "f43cfb3ae1cd3092d9a8a94332c64815fc4572f9"
COMMONMARK_COMMIT = "41499e6d6e50efac71db3bba64d5300d251d9c90"
SAMPLES = 7
MIN_SPEEDUP = 1.20
MAX_REGRESSION = 1.10
MAX_RSS_RATIO = 1.20

MANIFEST = """[dependencies]
  [dependencies.commonmark4cj]
    path = "{commonmark}"

[package]
  cjc-version = "1.0.0"
  compile-option = ""
  description = "Current-SDK benchmark adapter for markdown4cj parser core"
  link-option = ""
  name = "markdown"
  output-type = "executable"
  src-dir = "src"
  target-dir = ""
  version = "0.0.0"

[profile]
  [profile.build]
    incremental = false
    lto = ""
  [profile.customized-option]
    release = "--fast-math -O2 -Woff all"
"""

DRIVER = """package markdown
import markdown.core.*
import commonmark4cj.commonmark.*
import std.collection.*
import std.convert.*
import std.env.*

private func readInput(): String {
    let input = getStdIn()
    let bytes = ArrayList<Byte>()
    let buffer = Array<Byte>(8192, repeat: 0)
    while (true) {
        let count = input.read(buffer)
        if (count == 0) { break }
        if (count < 0) { throw IllegalStateException("stdin returned a negative byte count") }
        for (index in 0..count) { bytes.add(buffer[index]) }
    }
    String.fromUtf8(bytes.toArray())
}

main(args: Array<String>): Int64 {
    if (args.size != 2 || (args[0] != "parse" && args[0] != "render")) { return 2 }
    let iterations = try { Int64.parse(args[1]) } catch (_: Exception) { return 2 }
    if (iterations <= 0) { return 2 }
    let source = readInput()
    let engine = Markdown.create()
    if (args[0] == "render") {
        println(HtmlRenderer.builder().percentEncodeUrls(true).build().render(engine.parse(source)))
        return 0
    }
    var observed: Int64 = 0
    for (_ in 0..iterations) {
        let document = engine.parse(source)
        var child = document.getFirstChild()
        while (child.isSome()) {
            observed += 1
            child = child.getOrThrow().getNext()
        }
    }
    println(observed)
    0
}
"""

MIGRATIONS = {
    "core_plugin.cj": (("onTextAddedListeners.append(onTextAddedListener)",
                        "onTextAddedListeners.add(onTextAddedListener)"),),
    "markdown.cj": (("this.plugins.append(plugin)", "this.plugins.add(plugin)"),
        ("        parserBuilder.inlineParserFactory(InlineParserV2Factory()) // 使用v2版本的InlineParser\n", "")),
    "markdown_visitor.cj": (("nodes.put(node, v)", "nodes[node] = v"),),
    "node_ext.cj": (("list.append(node.getOrThrow())", "list.add(node.getOrThrow())"),),
    "node_view.cj": (("list.prepend(n.getView())", "list.add(n.getView(), at: 0)"),
        ("p.put(k, v)", "p[k] = v"),
        ("view.collector?.children.append(view)", "view.collector?.children.add(view)"),
        ("list.collector?.children.append(list)", "list.collector?.children.add(list)"),
        ("start.collector?.children.append(start)", "start.collector?.children.add(start)"),
        ("start.collector?.children.append(end)", "start.collector?.children.add(end)")),
    "props.cj": (("values.put(po.name(), value)", "values[po.name()] = value.getOrThrow()"),),
    "registry.cj": (("pending.put(plugin)", "pending.add(plugin)"),
        ("plugins.prepend(plugin)", "plugins.add(plugin, at: 0)"),
        ("plugins.append(plugin)", "plugins.add(plugin)")),
}

BEHAVIOR_CASES = {
    "heading": "# heading\n\nparagraph *em* and **strong**\n",
    "lists": "- one\n  - two\n\n1. ordered\n2. next\n",
    "quote": "> quote\n>\n> continuation\n",
    "fenced-code": "```cj\nlet x = 1 < 2\n```\n",
    "indented-code": "    let x = 1\n",
    "links": "[inline](https://example.com/a?b=c \"title\") and <https://example.com>\n",
    "references": "[label]: https://example.com/path \"title\"\n\nUse [label] repeatedly.\n",
    "unicode": "中文 😀 **粗体** 与 [链接](https://example.com/路径)\n",
    "entities": "\\*literal\\* &amp; &lt; &#35;\n",
    "breaks": "soft\nbreak  \nhard\n",
    "thematic-break": "before\n\n---\n\nafter\n",
    "inline-code": "`` code ` inside `` and `x < y`\n",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(command: list[str], cwd: Path) -> dict[str, object]:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    return {"command": command, "cwd": str(cwd), "exitCode": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr}


def preflight(source: Path, expected: str) -> dict[str, object]:
    head = command(["git", "rev-parse", "HEAD"], source)
    status = command(["git", "status", "--porcelain"], source)
    return {"head": str(head["stdout"]).strip(),
            "headMatches": str(head["stdout"]).strip() == expected,
            "clean": status["exitCode"] == 0 and status["stdout"] == ""}


def build_adapter(source: Path, commonmark: Path, workspace: Path) -> tuple[Path, dict[str, object]]:
    workspace.mkdir(parents=True, exist_ok=False)
    target = workspace / "src/core"
    shutil.copytree(source / "markdown/src/main/cangjie/src/core", target)
    applied = []
    for filename, replacements in MIGRATIONS.items():
        path = target / filename
        text = path.read_text()
        for before, after in replacements:
            count = text.count(before)
            if count == 0:
                raise RuntimeError(f"migration source not found: {filename}: {before}")
            text = text.replace(before, after)
            applied.append({"file": filename, "before": before, "after": after, "count": count})
        path.write_text(text)
    (workspace / "cjpm.toml").write_text(MANIFEST.format(commonmark=commonmark.resolve()))
    (workspace / "src/main.cj").write_text(DRIVER)
    build = command(["cjpm", "build", "-V"], workspace)
    build.update({"migrations": applied, "excluded": ["components/**", "plugin/**", "cj_res/**"],
                  "ohosImportCount": sum(path.read_text().count("ohos.") for path in target.glob("*.cj"))})
    binary = workspace / "target/release/bin/main"
    if build["exitCode"] != 0 or not binary.is_file() or build["ohosImportCount"] != 0:
        raise RuntimeError("current-SDK markdown4cj core adapter failed")
    return binary, build


def run(command_line: list[str], data: bytes, cpu: int, environment: dict[str, str]) -> dict[str, object]:
    started = time.perf_counter_ns()
    process = subprocess.Popen(["taskset", "-c", str(cpu), *command_line], stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    assert process.stdin is not None
    process.stdin.write(data)
    process.stdin.close()
    peak = 0
    while process.poll() is None:
        try:
            for line in Path(f"/proc/{process.pid}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    peak = max(peak, int(line.split()[1]))
                    break
        except FileNotFoundError:
            pass
        time.sleep(0.002)
    stdout = process.stdout.read() if process.stdout else b""
    stderr = process.stderr.read() if process.stderr else b""
    if process.returncode != 0:
        raise RuntimeError(f"driver failed ({process.returncode}): {stderr.decode(errors='replace')}")
    return {"seconds": (time.perf_counter_ns() - started) / 1e9, "peakRssKiB": peak,
            "stdout": stdout.decode().strip(), "stdoutSha256": hashlib.sha256(stdout).hexdigest()}


def behavior(ours: Path, theirs: Path, cpu: int, left_env: dict[str, str],
        right_env: dict[str, str]) -> dict[str, object]:
    rows = {}
    for name, source in BEHAVIOR_CASES.items():
        left = str(run([str(ours), "render"], source.encode(), cpu, left_env)["stdout"]).rstrip("\n")
        right = str(run([str(theirs), "render", "1"], source.encode(), cpu, right_env)["stdout"]).rstrip("\n")
        rows[name] = {"equalHtml": left == right, "markdownSha256": hashlib.sha256(left.encode()).hexdigest(),
                      "markdown4cjSha256": hashlib.sha256(right.encode()).hexdigest()}
    return {"caseCount": len(rows), "passCount": sum(row["equalHtml"] for row in rows.values()),
            "pass": all(row["equalHtml"] for row in rows.values()), "cases": rows}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--commonmark4cj-source", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True, help="fresh non-existing directory")
    parser.add_argument("--markdown-driver", type=Path,
        default=Path(__file__).parent / "driver/target/release/bin/main")
    parser.add_argument("--markdown-cli", type=Path,
        default=Path(__file__).parents[1] / "tools/markdown/target/release/bin/main")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=2)
    parser.add_argument("--iterations", type=int, default=3)
    return parser.parse_args()


def main() -> int:
    args = arguments()
    source, commonmark = args.source.resolve(), args.commonmark4cj_source.resolve()
    report: dict[str, object] = {"schemaVersion": 2, "status": "BLOCKED",
        "comparator": {"url": "https://gitcode.com/Cangjie-TPC/markdown4cj.git", "commit": COMPARATOR_COMMIT},
        "commonmark4cj": {"url": "https://gitcode.com/Cangjie-TPC/commonmark4cj.git", "commit": COMMONMARK_COMMIT},
        "environment": {"platform": platform.platform(), "cpu": args.cpu,
            "cjc": command(["cjc", "-v"], source), "cjpm": command(["cjpm", "--version"], source)},
        "protocol": {"workload": "CommonMark parse-only", "corpusBytes": 262144,
            "iterationsPerProcess": args.iterations, "warmupsPerSide": 1, "samplesPerSide": SAMPLES,
            "order": "alternating; odd sample reverses order"}}
    report["preflight"] = {"markdown4cj": preflight(source, COMPARATOR_COMMIT),
                           "commonmark4cj": preflight(commonmark, COMMONMARK_COMMIT)}
    if not all(item["headMatches"] and item["clean"] for item in report["preflight"].values()):
        report["reason"] = "dirty or incorrectly pinned comparator checkout"
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    try:
        theirs, build = build_adapter(source, commonmark, args.workspace.resolve())
    except Exception as error:
        report["reason"] = str(error)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    report["adapterBuild"] = build
    ours, cli = args.markdown_driver.resolve(), args.markdown_cli.resolve()
    if not ours.is_file() or not cli.is_file():
        report["reason"] = "build benchmarks/driver and tools/markdown first"
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    left_env = {**os.environ, "cjHeapSize": "2GB"}
    right_env = dict(left_env)
    right_env["LD_LIBRARY_PATH"] = str(args.workspace.resolve() / "target/release/commonmark4cj") + ":" + left_env.get("LD_LIBRARY_PATH", "")
    report["sharedBehavior"] = behavior(cli, theirs, args.cpu, left_env, right_env)
    if not report["sharedBehavior"]["pass"]:
        report["reason"] = "shared CommonMark HTML behavior mismatch"
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    rows, diagnostics, ratios = {}, {}, []
    for name, data in benchmark_corpora().items():
        if name == "custom-extension":
            continue
        left_command = [str(ours), "commonmark-parse", str(args.iterations)]
        right_command = [str(theirs), "parse", str(args.iterations)]
        left_one = run([str(ours), "commonmark-parse", "1"], data, args.cpu, left_env)
        right_one = run([str(theirs), "parse", "1"], data, args.cpu, right_env)
        diagnostics[name] = {"markdown": left_one["stdout"], "markdown4cj": right_one["stdout"],
                             "equalTopLevelNodeCount": left_one["stdout"] == right_one["stdout"]}
        run(left_command, data, args.cpu, left_env)
        run(right_command, data, args.cpu, right_env)
        left_values, right_values = [], []
        for index in range(SAMPLES):
            order = ((left_command, left_env, left_values), (right_command, right_env, right_values))
            if index % 2:
                order = ((right_command, right_env, right_values), (left_command, left_env, left_values))
            for command_line, environment, destination in order:
                destination.append(run(command_line, data, args.cpu, environment))
        left_median = statistics.median(row["seconds"] for row in left_values)
        right_median = statistics.median(row["seconds"] for row in right_values)
        speedup = right_median / left_median
        rss_ratio = max(row["peakRssKiB"] for row in left_values) / max(max(row["peakRssKiB"] for row in right_values), 1)
        ratios.append(speedup)
        rows[name] = {"bytes": len(data), "markdown": left_values, "markdown4cj": right_values,
                      "markdownMedianSeconds": left_median, "markdown4cjMedianSeconds": right_median,
                      "markdownSpeedup": speedup, "peakRssRatio": rss_ratio}
    geomean = math.exp(statistics.mean(math.log(value) for value in ratios))
    promoted = geomean >= MIN_SPEEDUP and min(ratios) >= 1 / MAX_REGRESSION and max(
        row["peakRssRatio"] for row in rows.values()) <= MAX_RSS_RATIO
    report.update({"status": "PASS" if promoted else "MEASURED_NOT_PROMOTED",
        "drivers": {"markdown": {"path": str(ours), "sha256": sha256(ours)},
                    "markdown4cj": {"path": str(theirs), "sha256": sha256(theirs)}},
        "structuralDiagnostics": diagnostics, "corpora": rows,
        "geomeanMarkdownSpeedup": geomean, "promotionPassed": promoted})
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return 0 if promoted else 1


if __name__ == "__main__":
    raise SystemExit(main())
