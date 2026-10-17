#!/usr/bin/env python3
"""Verify a committed report with its pinned, retained CI inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MAX_ARCHIVE_BYTES = 2 * 1024**3
MAX_EXTRACTED_BYTES = 4 * 1024**3
MAX_FILES = 10000
ARTIFACT_NAME = "same-language-benchmark-sts-1.2.0"
ARCHIVE_NAME = "same-language-benchmark.tar"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load_identity(manifest: Path, report: Path) -> dict:
    value = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or set(value) != {
        "schemaVersion", "repository", "runId", "artifactId",
        "artifactSha256", "reportSha256",
    } or value["schemaVersion"] != 1:
        raise ValueError("unsupported canonical benchmark input manifest")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value["repository"]):
        raise ValueError("invalid canonical benchmark repository")
    for key in ("runId", "artifactId"):
        if type(value[key]) is not int or value[key] <= 0:
            raise ValueError("invalid canonical benchmark artifact identity")
    for key in ("artifactSha256", "reportSha256"):
        if not isinstance(value[key], str) or not re.fullmatch(r"[0-9a-f]{64}", value[key]):
            raise ValueError("invalid canonical benchmark digest")
    if sha256(report) != value["reportSha256"]:
        raise ValueError("committed report differs from the pinned CI report")
    return value


def validate_artifact(metadata: dict, identity: dict) -> None:
    if metadata.get("id") != identity["artifactId"] or \
            metadata.get("name") != ARTIFACT_NAME or metadata.get("expired") is not False or \
            metadata.get("workflow_run", {}).get("id") != identity["runId"] or \
            metadata.get("digest") != "sha256:" + identity["artifactSha256"]:
        raise ValueError("canonical CI artifact identity differs or has expired")
    size = metadata.get("size_in_bytes")
    if type(size) is not int or not 0 < size <= MAX_ARCHIVE_BYTES:
        raise ValueError("canonical CI artifact exceeds the download limit")


def download_artifact(identity: dict, destination: Path) -> None:
    endpoint = f"repos/{identity['repository']}/actions/artifacts/{identity['artifactId']}"
    metadata = json.loads(subprocess.check_output(["gh", "api", endpoint], text=True))
    validate_artifact(metadata, identity)
    # gh streams binary responses unchanged. No token is placed in arguments.
    with destination.open("xb") as output:
        subprocess.run(["gh", "api", "--allow-escape-sequences", endpoint + "/zip"],
            stdout=output, check=True, timeout=600)


def safe_member_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or "\\" in name or path.is_absolute() or ".." in path.parts:
        raise ValueError("unsafe canonical evidence member path")
    return path


def extract_inputs(archive: Path, destination: Path, expected_digest: str) -> Path:
    if archive.stat().st_size > MAX_ARCHIVE_BYTES or sha256(archive) != expected_digest:
        raise ValueError("canonical CI artifact digest differs")
    destination.mkdir()
    container = destination / ARCHIVE_NAME
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        if len(entries) != 1 or entries[0].filename != ARCHIVE_NAME or \
                entries[0].file_size > MAX_EXTRACTED_BYTES or \
                stat.S_ISLNK(entries[0].external_attr >> 16):
            raise ValueError("canonical CI artifact must contain one bounded evidence tar")
        with bundle.open(entries[0]) as source, container.open("xb") as output:
            shutil.copyfileobj(source, output)
    inputs = destination / "inputs"
    inputs.mkdir()
    seen: set[PurePosixPath] = set()
    total = 0
    with tarfile.open(container, "r:") as bundle:
        for index, entry in enumerate(bundle):
            path = safe_member_path(entry.name)
            if index >= MAX_FILES or path in seen:
                raise ValueError("canonical evidence has duplicate or excessive members")
            seen.add(path)
            if not entry.isfile() and not entry.isdir():
                raise ValueError("canonical evidence links and special files are forbidden")
            total += entry.size
            if total > MAX_EXTRACTED_BYTES:
                raise ValueError("canonical evidence exceeds the extraction limit")
            target = inputs.joinpath(*path.parts)
            if entry.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                source = bundle.extractfile(entry)
                assert source is not None
                with source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(entry.mode & 0o777)
    container.unlink()
    return inputs


def verify_inputs(inputs: Path, report: Path, markdown_report: Path, product_source: Path) -> None:
    if sha256(inputs / "markdown4cj-comparison-raw.json") != sha256(report):
        raise ValueError("retained CI report differs from the committed report")
    subprocess.run([
        sys.executable, str(ROOT / "benchmarks/compare_markdown4cj.py"),
        "--source", str(inputs / "comparator-sources/markdown4cj.bundle"),
        "--commonmark4cj-source", str(inputs / "comparator-sources/commonmark4cj.bundle"),
        "--product-source", str(product_source),
        "--binary-root", str(inputs / "binaries"),
        "--sdk-archive", str(inputs / "toolchain/cangjie-sdk-linux-x64-1.2.0.tar.gz"),
        "--verify-report", str(report), "--markdown-report", str(markdown_report),
        "--require-current-product",
    ], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / ".github/benchmark-evidence.json")
    parser.add_argument("--report", type=Path,
        default=ROOT / "docs/reports/markdown4cj-comparison-raw.json")
    parser.add_argument("--markdown-report", type=Path,
        default=ROOT / "docs/reports/markdown4cj-comparison.md")
    parser.add_argument("--work-dir", type=Path, required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--download", action="store_true")
    source.add_argument("--artifact-archive", type=Path)
    args = parser.parse_args()
    try:
        identity = load_identity(args.manifest, args.report)
        args.work_dir.mkdir(parents=True, exist_ok=False)
        archive = args.artifact_archive
        if args.download:
            archive = args.work_dir / "artifact.zip"
            download_artifact(identity, archive)
        inputs = extract_inputs(archive, args.work_dir / "evidence", identity["artifactSha256"])
        verify_inputs(inputs, args.report.resolve(), args.markdown_report.resolve(), ROOT)
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError, zipfile.BadZipFile,
            subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print("committed canonical benchmark and retained CI inputs verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
