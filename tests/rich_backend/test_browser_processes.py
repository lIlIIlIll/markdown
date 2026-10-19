"""Qualify cancellation and Node crash with the actual pinned Chromium tree."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import tempfile
import time


def request() -> bytes:
    uint = lambda value: struct.pack(">I", value)
    string = lambda value: uint(len(value.encode())) + value.encode()
    limits = [128, 1048576, 4194304, 8388608, 33554432, 65536, 128, 131072, 4194304]
    source = "flowchart LR\n" + "\n".join(f" A{index} --> A{index + 1}" for index in range(200))
    data = b"MDRICH-REQUEST/1\n" + b"".join(uint(value) for value in limits) + uint(8)
    for _ in range(8):
        data += b"\x01\x00" + string("mermaid") + string(source)
    return uint(len(data)) + data


def descendants(parent: int) -> dict[int, bytes]:
    result = {}
    pending = [parent]
    while pending:
        pid = pending.pop()
        try:
            children = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
        except FileNotFoundError:
            continue
        for raw in children:
            child = int(raw)
            if child in result:
                continue
            try:
                result[child] = Path(f"/proc/{child}/cmdline").read_bytes().split(b"\0")[0]
            except FileNotFoundError:
                continue
            pending.append(child)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--work-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--allow-unsandboxed-chromium", action="store_true")
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    results = []
    for mode in ["cancel", "node-crash"]:
        with tempfile.TemporaryDirectory(prefix="markdown-rich-process-gate-", dir=args.work_directory) as directory:
            command = [sys.executable, "-I", "-S", str(runtime / "supervisor.py"), "--runtime-root", str(runtime),
                "--identity", (runtime / "identity").read_text().strip(), "--work-directory", directory,
                "--parent-pid", str(os.getpid()), "--timeout-ms", "30000", "--maximum-output-bytes", "33560000",
                "--theme", "github-light", "--diagram-theme", "default"]
            if args.allow_unsandboxed_chromium:
                command.append("--allow-no-sandbox")
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            observed = {}
            try:
                process.stdin.write(request()); process.stdin.flush()
                if process.stdout.readline() != b"MDRICH-SUPERVISOR/1\n":
                    raise ValueError("supervisor did not bootstrap actual browser job")
                deadline = time.monotonic() + 15
                while process.poll() is None:
                    observed = descendants(process.pid)
                    node = next((pid for pid, executable in observed.items() if executable == os.fsencode(runtime / "node/bin/node")), None)
                    chrome = any(executable == os.fsencode(runtime / "chrome/chrome") for executable in observed.values())
                    if node and chrome and len(observed) >= 5:
                        break
                    if time.monotonic() >= deadline:
                        raise ValueError("actual browser descendants did not become observable")
                    time.sleep(0.01)
                else:
                    raise ValueError("actual browser job exited before lifecycle observation")
                started = time.monotonic()
                if mode == "cancel":
                    process.terminate()
                else:
                    os.kill(node, signal.SIGKILL)
                output, errors = process.communicate(timeout=8)
                expected = 130 if mode == "cancel" else 70
                if process.returncode != expected or errors:
                    raise ValueError(f"actual {mode} returned {process.returncode}")
                if any(Path(f"/proc/{pid}").exists() for pid in observed):
                    raise ValueError("actual browser descendant was not reaped")
                if list(Path(directory).iterdir()):
                    raise ValueError("actual browser job directory remains")
                results.append({"case": mode, "status": "PASS", "observedDescendants": len(observed),
                    "allReaped": True, "cleanupMilliseconds": round((time.monotonic() - started) * 1000, 2)})
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.communicate(timeout=8)
    report = {"status": "PASS", "cases": results, "osSandboxClaim": False}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
