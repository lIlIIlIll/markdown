#!/usr/bin/env python3
"""Generate and verify API documentation with the pinned cjdoc release."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import tomllib
from urllib.request import urlopen

from check_api_docs import MARKER, ROOT, VERSION, validate, validate_contract

BINARY_URL = "https://github.com/lIlIIlIll/cjdoc/releases/download/v0.7.3/cjdoc-0.7.3-linux-x64"
BINARY_SHA256 = "6e5f0393dfdbea75bc84d51cd1bf1765ac2b819a19c270c93c5a3092c526f775"
REPOSITORY_URL = "https://github.com/lIlIIlIll/markdown"


def checked_binary(path: Path, environment: dict[str, str]) -> Path:
    path = path.resolve(strict=True)
    with path.open("rb") as binary_file:
        digest = hashlib.file_digest(binary_file, "sha256").hexdigest()
    if digest != BINARY_SHA256:
        raise ValueError("cjdoc binary SHA-256 differs from the pinned v0.7.3 Linux release")
    result = subprocess.run([str(path), "--version"], check=True, capture_output=True,
                            text=True, env=environment, timeout=30)
    if result.stdout.strip() != f"cjdoc {VERSION}":
        raise ValueError("cjdoc release version differs from the pinned version")
    return path


@contextmanager
def work_directory():
    # RUNNER_TEMP is disk-backed on hosted Linux runners. Locally, /tmp may be
    # tmpfs and a full generated site is large, so use the documented cache root.
    parent = Path(os.environ.get("RUNNER_TEMP", str(Path.home() / ".cache" / "agent-tmp")))
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not os.environ.get("RUNNER_TEMP"):
        parent.chmod(0o700)
    filesystem = subprocess.check_output(["stat", "-f", "-c", "%T", str(parent)], text=True).strip()
    if filesystem == "tmpfs":
        raise ValueError("API documentation work directory must be disk-backed, not tmpfs")
    if shutil.disk_usage(parent).free < 1024 * 1024 * 1024:
        raise ValueError("API documentation generation requires at least 1 GiB free disk space")
    with tempfile.TemporaryDirectory(prefix="markdown-api-docs-", dir=parent) as child:
        yield Path(child)


def source_revision(requested: str | None) -> str | None:
    revision = requested or os.environ.get("GITHUB_SHA")
    if revision is None:
        branch = subprocess.run(["git", "symbolic-ref", "--quiet", "--short", "HEAD"],
                                cwd=ROOT, capture_output=True, text=True).stdout.strip()
        if branch.startswith("gitbutler/"):
            return None
        revision = "HEAD"
    try:
        resolved = subprocess.check_output(["git", "rev-parse", "--verify", revision + "^{commit}"],
                                           cwd=ROOT, text=True).strip()
        clean = subprocess.run(["git", "diff", "--quiet", resolved, "--", "src", "cjpm.toml"],
                               cwd=ROOT, check=False).returncode == 0
        untracked = subprocess.check_output(
            ["git", "ls-files", "--others", "--exclude-standard", "--", "src"], cwd=ROOT, text=True)
        clean = clean and not untracked.strip()
    except subprocess.CalledProcessError as error:
        raise ValueError("cannot resolve documentation source revision") from error
    if not clean:
        if requested or os.environ.get("GITHUB_SHA"):
            raise ValueError("requested source revision does not match the generated source tree")
        return None
    return resolved


def publish_directory(staged: Path, output: Path, transaction: Path) -> None:
    backup = transaction / "previous-output"
    if output.is_symlink() or (output.exists() and not output.is_dir()):
        raise ValueError("output must be a directory, not a symlink or file")
    if output.exists():
        marker_path = output / MARKER
        if not marker_path.is_file():
            raise ValueError("refusing to replace an output directory not owned by this generator")
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        if marker.get("generator") != "markdown-api-docs/1":
            raise ValueError("refusing to replace output with an unknown ownership marker")
        output.rename(backup)
    try:
        staged.rename(output)
    except BaseException:
        if backup.exists():
            backup.rename(output)
        raise


def evidence_path(path: Path) -> str:
    if path.is_relative_to(ROOT):
        return str(path.relative_to(ROOT))
    if path.is_relative_to(Path.home()):
        return "$HOME/" + str(path.relative_to(Path.home()))
    return str(path)


def sanitize_diagnostic(value: str, environment: dict[str, str]) -> str:
    replacements = [(str(ROOT), "<repo>"), (str(Path.home()), "$HOME")]
    for key, replacement in (("TMPDIR", "<work>"), ("CANGJIE_HOME", "<sdk>"), ("CANGJIE_ROOT", "<sdk>")):
        if environment.get(key):
            replacements.append((environment[key], replacement))
    for original, replacement in sorted(replacements, key=lambda item: len(item[0]), reverse=True):
        value = value.replace(original, replacement)
    return value


def run_logged(command: list[str], *, environment: dict[str, str], log: Path) -> None:
    # Keep command-line paths out of the diagnostic record. The stage label and
    # binary's own output are enough to diagnose a failed generation or render.
    try:
        with log.open("w", encoding="utf-8") as diagnostic:
            subprocess.run(command, cwd=ROOT, env=environment, check=True, timeout=3600,
                           stdout=diagnostic, stderr=subprocess.STDOUT)
    finally:
        if log.is_file():
            contents = sanitize_diagnostic(log.read_text(encoding="utf-8", errors="replace"), environment)
            log.write_text(contents, encoding="utf-8")
            lines = contents.splitlines()
            if lines:
                print("\n".join(lines[-80:]), file=sys.stderr, flush=True)


def generate(args: argparse.Namespace) -> dict[str, int]:
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise ValueError("the pinned cjdoc release executable requires Linux x86-64")
    output = args.output.absolute()
    if output == ROOT or not output.name or output.is_symlink():
        raise ValueError("choose a dedicated output directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    if subprocess.check_output(["stat", "-f", "-c", "%T", str(output.parent)], text=True).strip() == "tmpfs":
        raise ValueError("API documentation output must be disk-backed, not tmpfs")
    # cjdoc holds an output-parent lock. A new private parent for every run
    # prevents an interrupted/OOM process from blocking future generations.
    # Failed transactions are retained as evidence; only success cleans them.
    transaction = Path(tempfile.mkdtemp(prefix=".api-docs-", dir=output.parent))
    staged = transaction / "site"
    stage = "prepare"
    environment = os.environ.copy()
    try:
        revision = source_revision(args.revision)
        if revision is None:
            print("Local preview: source links omitted because the source has no matching published commit.", flush=True)
        with work_directory() as work:
            environment.update(TMPDIR=str(work), TMP=str(work), TEMP=str(work), cjHeapSize="1GB")
            if args.cjdoc:
                binary = checked_binary(args.cjdoc, environment)
            else:
                downloaded = work / "cjdoc"
                with urlopen(BINARY_URL, timeout=120) as response, downloaded.open("wb") as target:
                    shutil.copyfileobj(response, target)
                downloaded.chmod(0o700)
                binary = checked_binary(downloaded, environment)
            package = tomllib.loads((ROOT / "cjpm.toml").read_text(encoding="utf-8"))["package"]
            command = [str(binary), "generate", "--project", str(ROOT),
                       "--semantic", "source", "--audience", "external", "--locale", "zh-CN",
                       "--lint-profile", "standard", "--format", "json", "--format", "coverage",
                       "--cache-dir", str(work / "source-cache"),
                       "--output", str(staged)]
            if not args.skip_examples:
                command.append("--check-examples")
            if revision:
                command += ["--repository-url", REPOSITORY_URL, "--repository-revision", revision,
                            "--repository-root", str(ROOT)]
            stage = "generate JSON, coverage and examples"
            print("Generating API data and checking examples...", flush=True)
            run_logged(command, environment=environment, log=transaction / "generate.log")
            marker = {"generator": "markdown-api-docs/1", "cjdocVersion": VERSION,
                      "examplesChecked": not args.skip_examples, "sourceRevision": revision}
            (staged / MARKER).write_text(json.dumps(marker, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            stage = "documentation contract"
            validate_contract(staged, ROOT / "api" / "public-api.txt", require_examples=not args.skip_examples)
            stage = "render HTML"
            print("API documentation contract passed; rendering the checked Doc IR...", flush=True)
            rendered = transaction / "rendered"
            run_logged([str(binary), "render", "--input", str(staged / "docs.json"),
                        "--format", "html", "--locale", "zh-CN", "--doc-version", package["version"],
                        "--output", str(rendered)],
                       environment=environment, log=transaction / "render.log")
            # Keep the authoritative JSON and reports from the one source pass;
            # consume only HTML from render's separately owned output tree.
            (rendered / "html").rename(staged / "html")
            stage = "final site verification"
            counts = validate(staged, ROOT / "api" / "public-api.txt", require_examples=not args.skip_examples)
            stage = "publish output"
            publish_directory(staged, output, transaction)
    except BaseException as error:
        if isinstance(error, subprocess.CalledProcessError):
            diagnostic = f"cjdoc process exited with status {error.returncode}; see the stage log"
        elif isinstance(error, subprocess.TimeoutExpired):
            diagnostic = "cjdoc process exceeded its time limit; see the stage log"
        else:
            diagnostic = sanitize_diagnostic(str(error), environment)
        (transaction / "failure.txt").write_text(f"Stage: {stage}\n{diagnostic}\n", encoding="utf-8")
        print(f"API documentation failed during {stage}. Evidence retained: {evidence_path(transaction)}", file=sys.stderr, flush=True)
        raise
    else:
        shutil.rmtree(transaction)
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "target" / "api-docs")
    parser.add_argument("--cjdoc", type=Path, help="offline binary; pinned checksum and version still required")
    parser.add_argument("--revision", help="exact source commit for GitHub source links; must match source tree")
    examples = parser.add_mutually_exclusive_group()
    examples.add_argument("--skip-examples", action="store_true", help="local preview only; do not publish")
    examples.add_argument("--check-examples", action="store_true", help="check examples (the default)")
    args = parser.parse_args()
    try:
        counts = generate(args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"API documentation generation failed: {error}", file=sys.stderr)
        return 1
    print("API documentation generated and verified: " + ", ".join(f"{n} {k}" for k, n in counts.items()))
    print(f"Open {args.output / 'html' / 'index.html'}")
    if args.skip_examples:
        print("Preview only: examples were not checked; this output is not ready to publish.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
