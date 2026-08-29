#!/usr/bin/env python3
"""Build the benchmark driver without mutating its canonical manifest."""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "benchmarks" / "driver"
CANONICAL_OPTIMIZATION = '-O2 --lto thin'
COMPATIBILITY_OPTIMIZATION = '-O2'


def compatibility_manifest(source: str, root: Path) -> str:
    replacements = {
        f'compile-option = "{CANONICAL_OPTIMIZATION}"':
            f'compile-option = "{COMPATIBILITY_OPTIMIZATION}"',
        'link-option = "-L ../../target/native -lmarkdown_scanner"':
            f'link-option = "-L {root / "target" / "native"} -lmarkdown_scanner"',
        'markdown = { path = "../.." }': f'markdown = {{ path = "{root}" }}',
    }
    result = source
    for old, new in replacements.items():
        if result.count(old) != 1:
            raise ValueError(f"expected exactly one manifest entry: {old}")
        result = result.replace(old, new)
    return result


def build_canonical() -> None:
    subprocess.run(["cjpm", "build"], cwd=DRIVER, check=True)


def build_compatibility() -> None:
    manifest = (DRIVER / "cjpm.toml").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="markdown-benchmark-driver-") as temporary:
        checkout = Path(temporary)
        shutil.copytree(DRIVER / "src", checkout / "src")
        shutil.copy2(DRIVER / "cjpm.lock", checkout / "cjpm.lock")
        (checkout / "cjpm.toml").write_text(
            compatibility_manifest(manifest, ROOT), encoding="utf-8"
        )
        subprocess.run(["cjpm", "build"], cwd=checkout, check=True)
        built = checkout / "target" / "release" / "bin" / "main"
        destination = DRIVER / "target" / "release" / "bin" / "main"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built, destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode", choices=("canonical", "compatibility"), default="canonical"
    )
    args = parser.parse_args()
    if args.mode == "canonical":
        build_canonical()
    else:
        build_compatibility()
    print(f"benchmark driver build mode: {args.mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
