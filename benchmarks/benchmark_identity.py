"""Deterministic identity for source files that affect benchmarked behavior."""

from __future__ import annotations

import hashlib
from pathlib import Path


PRODUCT_ROOTS = (
    "src",
    "native",
    "benchmarks/driver/src",
)
PRODUCT_FILES = (
    "cjpm.toml",
    "cjpm.lock",
    "build.cj",
    "benchmarks/benchmark_identity.py",
    "benchmarks/driver/cjpm.toml",
    "benchmarks/driver/cjpm.lock",
)


def benchmark_product_files(root: Path) -> list[Path]:
    files = [root / name for name in PRODUCT_FILES if (root / name).is_file()]
    for name in PRODUCT_ROOTS:
        directory = root / name
        if directory.is_dir():
            files.extend(path for path in directory.rglob("*") if path.is_file())
    return sorted(set(files), key=lambda path: path.relative_to(root).as_posix())


def benchmark_product_tree_sha256(root: Path) -> str:
    digest = hashlib.sha256(b"markdown-benchmark-product-tree-v1\0")
    for path in benchmark_product_files(root):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        content = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()
