#!/usr/bin/env python3
"""Collect and independently verify the release-gate evidence bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "target" / "release-evidence"
sys.path.insert(0, str(ROOT / "benchmarks"))
sys.path.insert(0, str(ROOT / "scripts"))

from benchmark_identity import benchmark_product_tree_sha256
from check_public_api import normalized_declarations
from release_statistics import validate_benchmark_derivations


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments], cwd=ROOT, text=True, capture_output=True, check=False
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Git identity is unavailable")
    return result.stdout.strip()


def release_subject_identity() -> tuple[str, str, str]:
    """Resolve the publishable commit represented by the current work tree.

    GitButler checks out a synthetic workspace commit.  Callers can set
    MARKDOWN_RELEASE_COMMIT to the publishable branch tip; ordinary checkouts
    continue to use HEAD.
    """
    reference = os.environ.get("MARKDOWN_RELEASE_COMMIT", "HEAD")
    commit = git("rev-parse", f"{reference}^{{commit}}")
    tree = git("rev-parse", f"{commit}^{{tree}}")
    return reference, commit, tree


def working_tree_matches_subject(subject_tree: str) -> bool:
    return (
        not git("status", "--porcelain")
        and git("rev-parse", "HEAD^{tree}") == subject_tree
    )


def command_output(*arguments: str) -> str | None:
    result = subprocess.run(arguments, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        return None
    return (result.stdout + result.stderr).strip()


def atomic_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def initialize(output: Path) -> None:
    if output.exists():
        shutil.rmtree(output)
    for stale in (ROOT / "target" / "release-tests", ROOT / "target" / "release-bench"):
        if stale.exists():
            shutil.rmtree(stale)
    (output / "logs").mkdir(parents=True)
    repository_ref, repository_commit, git_tree = release_subject_identity()
    atomic_json(output / "context.json", {
        "schemaVersion": 1,
        "repositoryRef": repository_ref,
        "repositoryCommit": repository_commit,
        "gitTree": git_tree,
        "productTreeSha256": benchmark_product_tree_sha256(ROOT),
        "runner": {
            "os": os.uname().sysname,
            "release": os.uname().release,
            "machine": os.uname().machine,
            "githubRunnerImage": os.environ.get("ImageOS"),
        },
        "toolchain": {
            "cangjie": command_output("cjc", "-v"),
            "sdkArchiveSha256": os.environ.get("MARKDOWN_SDK_ARCHIVE_SHA256"),
            "benchmarkDriverMode": os.environ.get("MARKDOWN_BENCHMARK_DRIVER_MODE", "canonical"),
            "cc": command_output(os.environ.get("CC", "clang"), "--version"),
            "ar": command_output(os.environ.get("AR", "ar"), "--version"),
        },
    })
    (output / "steps.jsonl").write_text("", encoding="utf-8")


def record(output: Path, name: str, working_directory: str, exit_code: int,
        command: list[str], log: str) -> None:
    record_value = {
        "name": name,
        "workingDirectory": working_directory,
        "command": command,
        "exitCode": exit_code,
        "log": log,
    }
    with (output / "steps.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record_value, sort_keys=True) + "\n")


def copy_path(source: Path, destination: Path) -> None:
    if not source.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)
    else:
        shutil.copy2(source, destination)


def snapshot_artifacts(output: Path) -> None:
    """Copy volatile target artifacts before a later cjpm command can clean them."""
    copy_path(ROOT / "target" / "release-tests", output / "junit")
    copy_path(ROOT / "target" / "release-bench", output / "benchmark-smoke")
    copy_path(ROOT / "docs" / "reports" / "differential-smoke.json",
        output / "reports" / "differential-smoke.json")
    copy_path(ROOT / "docs" / "reports" / "benchmark-raw.json",
        output / "reports" / "benchmark-raw.json")
    copy_path(ROOT / "api" / "public-api-v0.9.txt", output / "api" / "public-api-v0.9.txt")
    for bundle in sorted((ROOT / "target").glob("*.cjp")):
        copy_path(bundle, output / "candidate" / bundle.name)


def junit_metrics(directory: Path) -> tuple[dict[str, int], dict[str, dict[str, int]]]:
    totals = {"total": 0, "passed": 0, "skipped": 0, "failures": 0, "errors": 0}
    suites: dict[str, dict[str, int]] = {}
    for path in sorted(directory.rglob("*.xml")):
        root = ET.parse(path).getroot()
        suite_values = {
            "total": int(root.attrib.get("tests", "0")),
            "skipped": int(root.attrib.get("skipped", "0")),
            "failures": int(root.attrib.get("failures", "0")),
            "errors": int(root.attrib.get("errors", "0")),
        }
        suite_values["passed"] = (
            suite_values["total"] - suite_values["skipped"]
            - suite_values["failures"] - suite_values["errors"]
        )
        if suite_values["passed"] < 0:
            raise ValueError(f"invalid JUnit counts in {path}")
        name = root.attrib.get("name", path.stem)
        suites[name] = suite_values
        for key in totals:
            totals[key] += suite_values[key]
    return totals, suites


def load_steps(path: Path) -> list[dict[str, object]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


def finalize(output: Path, gate_exit: int) -> None:
    snapshot_artifacts(output)
    source_archive = output / "source" / "repository.tar"
    source_archive.parent.mkdir(parents=True, exist_ok=True)
    context = json.loads((output / "context.json").read_text(encoding="utf-8"))
    repository_commit = context["repositoryCommit"]
    archive = subprocess.run(
        ["git", "archive", "--format=tar", f"--output={source_archive}",
         repository_commit],
        cwd=ROOT, capture_output=True, check=False,
    )
    if archive.returncode != 0 and source_archive.exists():
        source_archive.unlink()

    steps = load_steps(output / "steps.jsonl")
    tests: dict[str, int] | None = None
    suites: dict[str, dict[str, int]] = {}
    junit = output / "junit"
    if junit.exists():
        tests, suites = junit_metrics(junit)
    benchmark_path = output / "reports" / "benchmark-raw.json"
    benchmark_errors: list[str] | None = None
    if benchmark_path.exists():
        benchmark_errors = validate_benchmark_derivations(
            json.loads(benchmark_path.read_text(encoding="utf-8"))
        )
    snapshot = output / "api" / "public-api-v0.9.txt"
    manifest = {
        "schemaVersion": 1,
        **context,
        "treeState": (
            "clean" if working_tree_matches_subject(context["gitTree"]) else "dirty"
        ),
        "gateExitCode": gate_exit,
        "sourceArchiveSha256": sha256(source_archive) if source_archive.exists() else None,
        "steps": steps,
        "tests": tests,
        "conformance": {
            "commonmark": suites.get("markdown.CommonMark0312ConformanceTest"),
            "gfm": suites.get("markdown.Gfm029ConformanceTest"),
        },
        "api": {
            "declarations": len(normalized_declarations()),
            "snapshotSha256": sha256(snapshot) if snapshot.exists() else None,
        },
        "benchmark": {
            "rawSha256": sha256(benchmark_path) if benchmark_path.exists() else None,
            "derivationErrors": benchmark_errors,
        },
    }
    atomic_json(output / "manifest.json", manifest)
    paths = sorted(
        path for path in output.rglob("*")
        if path.is_file() and path.name != "SHA256SUMS"
    )
    (output / "SHA256SUMS").write_text(
        "".join(f"{sha256(path)}  {path.relative_to(output).as_posix()}\n" for path in paths),
        encoding="utf-8",
    )


def publish(output: Path, destination: Path) -> None:
    """Atomically replace the retained bundle with a copy of the working bundle."""
    temporary = destination.with_name(destination.name + ".tmp")
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(output, temporary)
    if destination.exists():
        shutil.rmtree(destination)
    temporary.replace(destination)


def verify_checksums(output: Path) -> list[str]:
    errors: list[str] = []
    sums = output / "SHA256SUMS"
    if not sums.is_file():
        return ["release evidence bundle is missing SHA256SUMS"]
    listed: set[str] = set()
    for line_number, line in enumerate(sums.read_text(encoding="utf-8").splitlines(), start=1):
        parts = line.split("  ", 1)
        if len(parts) != 2:
            errors.append(f"release evidence checksum entry is malformed at line {line_number}")
            continue
        expected, relative = parts
        relative_path = Path(relative)
        if relative_path.is_absolute() or ".." in relative_path.parts or relative == "SHA256SUMS":
            errors.append(f"release evidence checksum path is invalid: {relative}")
            continue
        if relative in listed:
            errors.append(f"release evidence checksum path is duplicated: {relative}")
            continue
        listed.add(relative)
        path = output / relative
        if not path.is_file() or sha256(path) != expected:
            errors.append(f"release evidence checksum mismatch: {relative}")
    retained = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file() and path.name != "SHA256SUMS"
    }
    for relative in sorted(retained - listed):
        errors.append(f"release evidence file is missing from SHA256SUMS: {relative}")
    for relative in sorted(listed - retained):
        if f"release evidence checksum mismatch: {relative}" not in errors:
            errors.append(f"release evidence checksum lists a missing file: {relative}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("init")
    record_parser = subparsers.add_parser("record")
    record_parser.add_argument("--name", required=True)
    record_parser.add_argument("--working-directory", required=True)
    record_parser.add_argument("--exit-code", type=int, required=True)
    record_parser.add_argument("--log", required=True)
    record_parser.add_argument("argv", nargs=argparse.REMAINDER)
    finalize_parser = subparsers.add_parser("finalize")
    finalize_parser.add_argument("--gate-exit", type=int, required=True)
    subparsers.add_parser("snapshot")
    publish_parser = subparsers.add_parser("publish")
    publish_parser.add_argument("--destination", type=Path, required=True)
    subparsers.add_parser("verify")
    args = parser.parse_args()
    output = args.output.resolve()
    if args.command == "init":
        initialize(output)
    elif args.command == "record":
        command = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
        record(output, args.name, args.working_directory, args.exit_code, command, args.log)
    elif args.command == "finalize":
        finalize(output, args.gate_exit)
    elif args.command == "snapshot":
        snapshot_artifacts(output)
    elif args.command == "publish":
        publish(output, args.destination.resolve())
    else:
        errors = verify_checksums(output)
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print("release evidence bundle checksums verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
