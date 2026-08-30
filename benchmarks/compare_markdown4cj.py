#!/usr/bin/env python3
"""Compare markdown with the platform-neutral markdown4cj parser core.

The pinned markdown4cj HAR targets HarmonyOS, but ``src/core`` does not. This
runner copies only that core into a fresh cjpm project, applies a fail-closed
current-SDK collection-API migration, and links a pinned commonmark4cj checkout.
No OHOS, DevEco, UI component, prism4cj, or formula-ffi source is built.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import time

from benchmark_identity import benchmark_product_tree_sha256
from measure import benchmark_corpora

ROOT = Path(__file__).resolve().parents[1]
COMPARATOR_URL = "https://gitcode.com/Cangjie-TPC/markdown4cj.git"
COMMONMARK_URL = "https://gitcode.com/Cangjie-TPC/commonmark4cj.git"
COMPARATOR_COMMIT = "f43cfb3ae1cd3092d9a8a94332c64815fc4572f9"
COMMONMARK_COMMIT = "41499e6d6e50efac71db3bba64d5300d251d9c90"
SAMPLES = 7
ITERATIONS = 3
CORPUS_BYTES = 256 * 1024
MIN_SPEEDUP = 1.20
MAX_REGRESSION = 1.10
MAX_RSS_RATIO = 1.20
HARNESS_FILES = (
    "benchmarks/compare_markdown4cj.py",
    "benchmarks/measure.py",
    "benchmarks/generate_corpus.py",
    "benchmarks/benchmark_identity.py",
)

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


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def git_text(root: Path, *arguments: str) -> str:
    result = subprocess.run(["git", *arguments], cwd=root, text=True,
        capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Git identity is unavailable")
    return result.stdout.strip()


def repository_identity() -> dict[str, object]:
    reference = os.environ.get("MARKDOWN_BENCHMARK_COMMIT", "HEAD")
    commit = git_text(ROOT, "rev-parse", f"{reference}^{{commit}}")
    tree = git_text(ROOT, "rev-parse", f"{commit}^{{tree}}")
    head_tree = git_text(ROOT, "rev-parse", "HEAD^{tree}")
    status = git_text(ROOT, "status", "--porcelain")
    if status or head_tree != tree:
        raise RuntimeError("benchmark subject must match a clean publishable Git tree")
    return {"repositoryRef": reference, "repositoryCommit": commit, "gitTree": tree,
        "productTreeSha256": benchmark_product_tree_sha256(ROOT),
        "harnessFiles": {relative: sha256(ROOT / relative) for relative in HARNESS_FILES}}


def benchmark_inputs() -> dict[str, bytes]:
    return {name: data for name, data in benchmark_corpora().items()
        if name != "custom-extension"}


def corpus_identity(inputs: dict[str, bytes]) -> list[dict[str, object]]:
    return [{"name": name, "bytes": len(data),
             "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in inputs.items()]


def checkout_pinned(repository: str, commit: str, destination: Path) -> None:
    if destination.exists():
        if destination.is_dir() and (destination / ".git").is_dir():
            state = preflight(destination, commit)
            if state["headMatches"] and state["clean"]:
                return
        raise RuntimeError(f"refusing to replace non-matching checkout: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "--quiet", str(destination)], check=True)
    subprocess.run(["git", "-C", str(destination), "remote", "add", "origin", repository],
        check=True)
    result: subprocess.CompletedProcess[str] | None = None
    for attempt in range(3):
        result = subprocess.run(["git", "-C", str(destination), "fetch", "--quiet",
            "--depth", "1", "origin", commit], text=True, capture_output=True, check=False)
        if result.returncode == 0:
            break
        if attempt < 2:
            time.sleep(2 ** attempt)
    if result is None or result.returncode != 0:
        raise RuntimeError(result.stderr.strip() if result else "comparator fetch failed")
    subprocess.run(["git", "-C", str(destination), "checkout", "--quiet", "--detach",
        "FETCH_HEAD"], check=True)
    state = preflight(destination, commit)
    if not state["headMatches"] or not state["clean"]:
        raise RuntimeError(f"pinned checkout verification failed: {destination}")


def resolve_sources(args: argparse.Namespace) -> tuple[Path, Path]:
    if args.tools_root is not None:
        if args.source is not None or args.commonmark4cj_source is not None:
            raise ValueError("use --tools-root or explicit comparator paths, not both")
        tools_root = args.tools_root.resolve()
        source = tools_root / "markdown4cj"
        commonmark = tools_root / "commonmark4cj"
        checkout_pinned(COMPARATOR_URL, COMPARATOR_COMMIT, source)
        checkout_pinned(COMMONMARK_URL, COMMONMARK_COMMIT, commonmark)
        return source, commonmark
    if args.source is None or args.commonmark4cj_source is None:
        raise ValueError("provide --tools-root or both comparator source paths")
    return args.source.resolve(), args.commonmark4cj_source.resolve()


def resolve_cpu(requested: int | None) -> int:
    available = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else [0]
    selected = available[0] if requested is None else requested
    if selected not in available:
        raise ValueError(f"CPU {selected} is outside the process affinity set {available}")
    return selected


def close_number(left: object, right: float) -> bool:
    return isinstance(left, (int, float)) and math.isclose(float(left), right,
        rel_tol=1e-12, abs_tol=1e-12)


def validate_report(report: dict[str, object], require_current_product: bool) -> list[str]:
    errors: list[str] = []
    if report.get("schemaVersion") != 3:
        errors.append("same-language report schemaVersion must be 3")
    if report.get("comparator") != {"url": COMPARATOR_URL, "commit": COMPARATOR_COMMIT}:
        errors.append("same-language report comparator identity is not pinned")
    if report.get("commonmark4cj") != {"url": COMMONMARK_URL, "commit": COMMONMARK_COMMIT}:
        errors.append("same-language report commonmark4cj identity is not pinned")
    expected_thresholds = {"minimumGeomeanSpeedup": MIN_SPEEDUP,
        "maximumPerCorpusRegression": MAX_REGRESSION,
        "maximumPeakRssRatio": MAX_RSS_RATIO}
    if report.get("thresholds") != expected_thresholds:
        errors.append("same-language report thresholds differ from the enforced profile")
    expected_protocol = {"workload": "CommonMark parse-only", "corpusBytes": CORPUS_BYTES,
        "iterationsPerProcess": ITERATIONS, "warmupsPerSide": 1,
        "samplesPerSide": SAMPLES,
        "order": "alternating; odd sample reverses order"}
    if report.get("protocol") != expected_protocol:
        errors.append("same-language report protocol differs from the enforced profile")
    environment = report.get("environment")
    if not isinstance(environment, dict) or not all(
            isinstance(environment.get(tool), dict) and
            environment[tool].get("exitCode") == 0 for tool in ("cjc", "cjpm")):
        errors.append("same-language report does not bind a successful SDK environment")
    preflight_report = report.get("preflight")
    if not isinstance(preflight_report, dict) or not all(
            isinstance(preflight_report.get(name), dict) and
            preflight_report[name].get("headMatches") is True and
            preflight_report[name].get("clean") is True
            for name in ("markdown4cj", "commonmark4cj")):
        errors.append("same-language report comparator preflight did not pass")
    identity = report.get("identity")
    inputs = benchmark_inputs()
    expected_corpora = corpus_identity(inputs)
    if not isinstance(identity, dict):
        errors.append("same-language report has no product identity")
    else:
        if identity.get("corpora") != expected_corpora:
            errors.append("same-language report corpus identity does not match current inputs")
        expected_harness = {relative: sha256(ROOT / relative) for relative in HARNESS_FILES}
        if identity.get("harnessFiles") != expected_harness:
            errors.append("same-language report harness identity does not match current files")
        if require_current_product and identity.get("productTreeSha256") != \
                benchmark_product_tree_sha256(ROOT):
            errors.append("same-language report product tree does not match current source")
    shared = report.get("sharedBehavior")
    behavior_pass = isinstance(shared, dict) and shared.get("caseCount") == len(BEHAVIOR_CASES) \
        and shared.get("passCount") == len(BEHAVIOR_CASES) and shared.get("pass") is True
    if not behavior_pass:
        errors.append("same-language shared behavior gate did not pass")
    rows = report.get("corpora")
    speedups: list[float] = []
    rss_ratios: list[float] = []
    if not isinstance(rows, dict) or set(rows) != set(inputs):
        errors.append("same-language report corpus rows are incomplete")
    else:
        for name, data in inputs.items():
            row = rows[name]
            if not isinstance(row, dict) or row.get("bytes") != len(data):
                errors.append(f"same-language corpus metadata is invalid: {name}")
                continue
            left = row.get("markdown")
            right = row.get("markdown4cj")
            if not isinstance(left, list) or not isinstance(right, list) or \
                    len(left) != SAMPLES or len(right) != SAMPLES:
                errors.append(f"same-language samples are incomplete: {name}")
                continue
            try:
                left_seconds = [float(sample["seconds"]) for sample in left]
                right_seconds = [float(sample["seconds"]) for sample in right]
                left_rss = [int(sample["peakRssKiB"]) for sample in left]
                right_rss = [int(sample["peakRssKiB"]) for sample in right]
                left_outputs = {(str(sample["stdout"]), str(sample["stdoutSha256"]))
                    for sample in left}
                right_outputs = {(str(sample["stdout"]), str(sample["stdoutSha256"]))
                    for sample in right}
            except (KeyError, TypeError, ValueError):
                errors.append(f"same-language samples are malformed: {name}")
                continue
            if min(left_seconds + right_seconds) <= 0 or min(left_rss + right_rss) <= 0:
                errors.append(f"same-language samples contain invalid values: {name}")
                continue
            if len(left_outputs) != 1 or len(right_outputs) != 1:
                errors.append(f"same-language output is unstable across samples: {name}")
                continue
            left_median = statistics.median(left_seconds)
            right_median = statistics.median(right_seconds)
            speedup = right_median / left_median
            rss_ratio = max(left_rss) / max(max(right_rss), 1)
            if not close_number(row.get("markdownMedianSeconds"), left_median):
                errors.append(f"same-language markdown median is not derived: {name}")
            if not close_number(row.get("markdown4cjMedianSeconds"), right_median):
                errors.append(f"same-language markdown4cj median is not derived: {name}")
            if not close_number(row.get("markdownSpeedup"), speedup):
                errors.append(f"same-language speedup is not derived: {name}")
            if not close_number(row.get("peakRssRatio"), rss_ratio):
                errors.append(f"same-language RSS ratio is not derived: {name}")
            speedups.append(speedup)
            rss_ratios.append(rss_ratio)
    if speedups:
        geomean = math.exp(statistics.mean(math.log(value) for value in speedups))
        promoted = behavior_pass and geomean >= MIN_SPEEDUP and \
            min(speedups) >= 1 / MAX_REGRESSION and max(rss_ratios) <= MAX_RSS_RATIO
        if not close_number(report.get("geomeanMarkdownSpeedup"), geomean):
            errors.append("same-language geometric mean is not derived from samples")
        if report.get("promotionPassed") is not promoted:
            errors.append("same-language promotion result is not derived from samples")
        expected_status = "PASS" if promoted else "MEASURED_NOT_PROMOTED"
        if report.get("status") != expected_status:
            errors.append("same-language status is not derived from samples")
    return errors


def render_markdown(report: dict[str, object]) -> str:
    identity = report["identity"]
    environment = report["environment"]
    rows = report["corpora"]
    speedups = [float(row["markdownSpeedup"]) for row in rows.values()]
    rss_ratios = [float(row["peakRssRatio"]) for row in rows.values()]
    cjc = str(environment["cjc"]["stdout"]).strip().splitlines()[0]
    table = "\n".join(
        f"| {name} | {float(row['markdownSpeedup']):.2f}× | {float(row['peakRssRatio']):.3f}× |"
        for name, row in rows.items()
    )
    return f"""# markdown4cj 同语言解析性能对比

状态：**{report['status']}（CommonMark parse-only）**

## 对比边界

- 产品提交：`{identity['repositoryCommit']}`，Git tree `{identity['gitTree']}`。
- `markdown4cj` 固定提交 `{COMPARATOR_COMMIT}`。
- `commonmark4cj` 固定提交 `{COMMONMARK_COMMIT}`，用于当前 SDK adapter。
- SDK：`{cjc}`。
- 只构建 `markdown4cj/src/core/**`。不构建 OHOS UI、DevEco、prism4cj 或 formula-ffi。
- 两侧都生成 AST；本报告不把 event parser 或 fused renderer 当作 `parse()`。

这不是 HTML renderer 对比。`markdown4cj` 没有与本库 `HtmlRenderer` 等价的 HTML
字符串入口，因此性能结论只适用于共同的 CommonMark parse-only 子集。

## 测量协议

- 同一主机、同一 SDK、release `-O2`、固定 CPU {environment['cpu']}。
- 11 个确定性语料，每个 256 KiB；每进程解析 {report['protocol']['iterationsPerProcess']} 次。
- 每侧预热 1 次，再取 {SAMPLES} 个交替样本；奇数轮反转顺序。
- 12 个共享 CommonMark 用例的 HTML 必须逐字一致。
- 门槛：几何平均至少 `{MIN_SPEEDUP:.2f}×`，单语料不得回退超过
  `{(MAX_REGRESSION - 1) * 100:.0f}%`，峰值 RSS 不得超过 comparator 的
  `{MAX_RSS_RATIO:.2f}×`。

## 当前结果

大于 `1×` 表示 `markdown` 更快。

| 语料 | parse 加速 | 峰值 RSS 比值 |
| --- | ---: | ---: |
{table}
| **几何平均** | **{float(report['geomeanMarkdownSpeedup']):.2f}×** | — |

11 个语料的最小加速为 `{min(speedups):.2f}×`。最大峰值 RSS 比值为
`{max(rss_ratios):.3f}×`。共享行为用例为
`{report['sharedBehavior']['passCount']}/{report['sharedBehavior']['caseCount']}`。

## 合入门禁

GitHub Actions 的 `Same-language benchmark (current-1.1.3)` job 对每个 push 和 PR
重新构建两侧 driver，并重新计算全部统计量。`main` 将该 job 设为 required check。

运行以下命令可以复现同一 harness：

```sh
cangjie_env
python3 benchmarks/compare_markdown4cj.py \\
  --tools-root /tmp/markdown-same-language-tools \\
  --workspace /tmp/fresh-markdown4cj-adapter \\
  --output /tmp/markdown4cj-comparison.json
```

原始样本、身份和派生统计见
[`markdown4cj-comparison-raw.json`](markdown4cj-comparison-raw.json)。
"""


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
    parser.add_argument("--source", type=Path)
    parser.add_argument("--commonmark4cj-source", type=Path)
    parser.add_argument("--tools-root", type=Path,
        help="directory in which pinned comparator checkouts are prepared")
    parser.add_argument("--workspace", type=Path, help="fresh non-existing adapter directory")
    parser.add_argument("--markdown-driver", type=Path,
        default=Path(__file__).parent / "driver/target/release/bin/main")
    parser.add_argument("--markdown-cli", type=Path,
        default=Path(__file__).parents[1] / "tools/markdown/target/release/bin/main")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--markdown-report", type=Path)
    parser.add_argument("--cpu", type=int,
        help="pinned CPU; defaults to the first CPU in the process affinity set")
    parser.add_argument("--iterations", type=int, default=ITERATIONS)
    parser.add_argument("--verify-report", type=Path)
    parser.add_argument("--require-current-product", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = arguments()
    if args.verify_report is not None:
        report = json.loads(args.verify_report.read_text(encoding="utf-8"))
        errors = validate_report(report, args.require_current_product)
        if args.markdown_report is not None and not errors:
            expected = render_markdown(report)
            if not args.markdown_report.is_file() or \
                    args.markdown_report.read_text(encoding="utf-8") != expected:
                errors.append("same-language Markdown report is not generated from raw data")
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print("same-language benchmark report verified")
        return 0
    if args.output is None or args.workspace is None:
        print("measurement requires --output and --workspace", file=sys.stderr)
        return 2
    if args.iterations != ITERATIONS:
        print(f"--iterations is fixed at {ITERATIONS} by the canonical protocol",
              file=sys.stderr)
        return 2
    try:
        source, commonmark = resolve_sources(args)
        cpu = resolve_cpu(args.cpu)
        inputs = benchmark_inputs()
        identity = repository_identity()
        identity["corpora"] = corpus_identity(inputs)
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 2
    report: dict[str, object] = {"schemaVersion": 3, "status": "BLOCKED",
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "identity": identity,
        "comparator": {"url": COMPARATOR_URL, "commit": COMPARATOR_COMMIT},
        "commonmark4cj": {"url": COMMONMARK_URL, "commit": COMMONMARK_COMMIT},
        "thresholds": {"minimumGeomeanSpeedup": MIN_SPEEDUP,
            "maximumPerCorpusRegression": MAX_REGRESSION,
            "maximumPeakRssRatio": MAX_RSS_RATIO},
        "environment": {"platform": platform.platform(), "cpu": cpu,
            "cjc": command(["cjc", "-v"], source),
            "cjpm": command(["cjpm", "--version"], source)},
        "protocol": {"workload": "CommonMark parse-only", "corpusBytes": CORPUS_BYTES,
            "iterationsPerProcess": args.iterations, "warmupsPerSide": 1,
            "samplesPerSide": SAMPLES,
            "order": "alternating; odd sample reverses order"}}
    report["preflight"] = {"markdown4cj": preflight(source, COMPARATOR_COMMIT),
                           "commonmark4cj": preflight(commonmark, COMMONMARK_COMMIT)}
    if not all(item["headMatches"] and item["clean"] for item in report["preflight"].values()):
        report["reason"] = "dirty or incorrectly pinned comparator checkout"
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    try:
        theirs, build = build_adapter(source, commonmark, args.workspace.resolve())
    except Exception as error:
        report["reason"] = str(error)
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    report["adapterBuild"] = build
    ours, cli = args.markdown_driver.resolve(), args.markdown_cli.resolve()
    if not ours.is_file() or not cli.is_file():
        report["reason"] = "build benchmarks/driver and tools/markdown first"
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    left_env = {**os.environ, "cjHeapSize": "2GB"}
    right_env = dict(left_env)
    right_env["LD_LIBRARY_PATH"] = str(args.workspace.resolve() / "target/release/commonmark4cj") + ":" + left_env.get("LD_LIBRARY_PATH", "")
    report["sharedBehavior"] = behavior(cli, theirs, cpu, left_env, right_env)
    if not report["sharedBehavior"]["pass"]:
        report["reason"] = "shared CommonMark HTML behavior mismatch"
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    rows, diagnostics, ratios = {}, {}, []
    for name, data in inputs.items():
        left_command = [str(ours), "commonmark-parse", str(args.iterations)]
        right_command = [str(theirs), "parse", str(args.iterations)]
        left_one = run([str(ours), "commonmark-parse", "1"], data, cpu, left_env)
        right_one = run([str(theirs), "parse", "1"], data, cpu, right_env)
        diagnostics[name] = {"markdown": left_one["stdout"], "markdown4cj": right_one["stdout"],
                             "equalTopLevelNodeCount": left_one["stdout"] == right_one["stdout"]}
        run(left_command, data, cpu, left_env)
        run(right_command, data, cpu, right_env)
        left_values, right_values = [], []
        for index in range(SAMPLES):
            order = ((left_command, left_env, left_values), (right_command, right_env, right_values))
            if index % 2:
                order = ((right_command, right_env, right_values), (left_command, left_env, left_values))
            for command_line, environment, destination in order:
                destination.append(run(command_line, data, cpu, environment))
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
    errors = validate_report(report, True)
    report["derivationErrors"] = errors
    if errors:
        report["status"] = "INVALID"
        report["promotionPassed"] = False
    atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.markdown_report is not None and not errors:
        atomic_write(args.markdown_report, render_markdown(report))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 2
    return 0 if promoted else 1


if __name__ == "__main__":
    raise SystemExit(main())
