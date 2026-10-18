#!/usr/bin/env python3
"""Run an explicit, installed-runtime Cangjie rich backend gate. No downloads."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str], log: Path, environment: dict[str, str], timeout: int) -> str:
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, env=environment, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    text = log.read_text()
    if result.returncode:
        raise ValueError(f"{log.name} failed with exit {result.returncode}")
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--work-directory", type=Path, required=True)
    parser.add_argument("--library-directory", type=Path, default=ROOT / "target/release/markdown")
    parser.add_argument("--allow-unsandboxed-chromium", action="store_true")
    parser.add_argument("--browser", action="store_true")
    parser.add_argument("--supervisor-tests", action="store_true")
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    library = args.library_directory.resolve()
    work = Path(tempfile.mkdtemp(prefix="markdown-rich-gate-", dir=args.work_directory))
    print(f"Gate artifacts: {work}", flush=True)
    environment = os.environ | {"TMPDIR": str(work), "TMP": str(work), "TEMP": str(work)}
    compiler = run(["cjc", "--version"], work / "compiler.log", environment, 10)
    if "1.2.0" not in compiler:
        raise ValueError("official STS 1.2.0 is required")
    run(["cjc", str(ROOT / "tests/rich_backend/main.cj"), "-O2", "--import-path", str(library), "-L", str(library),
        "-lmarkdown.core", "-lmarkdown.extensions", "-lmarkdown.render", "-lmarkdown.node", "-lmarkdown",
        "-o", str(work / "consumer")], work / "compile.log", environment, 120)
    result = run([str(work / "consumer"), str(runtime), str(work), str(args.allow_unsandboxed_chromium).lower()],
        work / "consumer.log", environment, 45)
    if not result.startswith("PASS actual STS1.2") or "BEGINHTML\n" not in result or "\nENDHTML" not in result:
        raise ValueError("consumer did not complete actual preparation")
    fixture = work / "actual.html"
    fixture.write_text(result.split("BEGINHTML\n", 1)[1].split("\nENDHTML", 1)[0])
    if args.browser:
        descriptor = os.open(work, os.O_RDONLY | os.O_DIRECTORY)
        try:
            short = f"/proc/{os.getpid()}/fd/{descriptor}"
            browser_environment = environment | {"TMPDIR": short, "TMP": short, "TEMP": short}
            run([str(runtime / "node/bin/node"), str(ROOT / "tests/browser/rich_content.mjs"), "--fixture", str(fixture),
                "--runtime-root", str(runtime), "--output", str(work / "browser"), "--allow-no-sandbox",
                str(args.allow_unsandboxed_chromium).lower()], work / "browser.log", browser_environment, 45)
        finally:
            os.close(descriptor)
    if args.supervisor_tests:
        run([sys.executable, str(ROOT / "tests/rich_backend/test_supervisor.py"), "--node", str(runtime / "node/bin/node"),
            "--work-directory", str(work)], work / "supervisor.log", environment, 90)
        command = [sys.executable, str(ROOT / "tests/rich_backend/test_browser_processes.py"), "--runtime", str(runtime),
            "--work-directory", str(work), "--output", str(work / "browser-processes.json")]
        if args.allow_unsandboxed_chromium:
            command.append("--allow-unsandboxed-chromium")
        run(command, work / "browser-processes.log", environment, 90)
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    report = {"status": "PASS", "cangjie": "1.2.0", "runtimeIdentity": (runtime / "identity").read_text().strip(),
        "consumerSha256": digest(ROOT / "tests/rich_backend/main.cj"), "librarySha256": digest(library / "libmarkdown.a"),
        "nodeLibrarySha256": digest(library / "libmarkdown.node.a"), "fixtureSha256": digest(fixture),
        "linkedLibrarySha256s": {name: digest(library / name) for name in
            ["libmarkdown.core.a", "libmarkdown.extensions.a", "libmarkdown.render.a", "libmarkdown.node.a", "libmarkdown.a"]},
        "browserGate": args.browser, "supervisorFixtureCases": 7 if args.supervisor_tests else 0,
        "actualBrowserProcessCases": 2 if args.supervisor_tests else 0,
        "allowUnsandboxedChromium": args.allow_unsandboxed_chromium, "osSandboxClaim": False}
    (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Node rich gate failed: {error}", file=sys.stderr)
        raise SystemExit(1)
