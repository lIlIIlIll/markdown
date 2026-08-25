#!/usr/bin/env python3
"""Build and run coverage-guided plus ASan/UBSan scanner fuzz smoke gates."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def compiler() -> str:
    configured = os.environ.get("CC")
    if configured:
        return configured
    return shutil.which("clang") or "clang"


def compile_binary(cc: str, output: Path, harness: Path, sanitizers: str) -> None:
    subprocess.check_call([
        cc,
        "-std=c11",
        "-O1",
        "-g",
        f"-fsanitize={sanitizers}",
        "-fno-omit-frame-pointer",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I",
        str(ROOT / "native"),
        str(ROOT / "native" / "markdown_scanner.c"),
        str(harness),
        "-o",
        str(output),
    ])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=10000)
    args = parser.parse_args()
    if args.runs <= 0:
        parser.error("--runs must be positive")

    cc = compiler()
    with tempfile.TemporaryDirectory(prefix="markdown-native-fuzz-") as directory:
        temporary = Path(directory)
        sanitizer = temporary / "scanner-sanitizer"
        fuzzer = temporary / "scanner-fuzzer"
        corpus = temporary / "corpus"
        shutil.copytree(ROOT / "tests/fuzz/native-scanner-corpus", corpus)
        compile_binary(cc, sanitizer, ROOT / "tests/fuzz/native_scanner_sanitizer.c", "address,undefined")
        subprocess.check_call([str(sanitizer)], env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"})
        compile_binary(cc, fuzzer, ROOT / "tests/fuzz/native_scanner_fuzz.c", "fuzzer,address,undefined")
        subprocess.check_call([
            str(fuzzer),
            f"-runs={args.runs}",
            "-max_len=65536",
            "-timeout=5",
            "-verbosity=0",
            str(corpus),
        ], env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1",
            "UBSAN_OPTIONS": "halt_on_error=1:print_stacktrace=1"})
    print(f"native scanner fuzz: pass ({args.runs} coverage-guided runs; ASan+UBSan clean)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
