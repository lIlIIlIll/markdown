"""Deterministic identity for source files that affect benchmarked behavior."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


PRODUCT_ROOTS = (
    "src",
    "native",
    "benchmarks/driver/src",
    "tools/markdown/src",
)
PRODUCT_FILES = (
    "cjpm.toml",
    "cjpm.lock",
    "build.cj",
    "benchmarks/benchmark_identity.py",
    "benchmarks/driver/cjpm.toml",
    "benchmarks/driver/cjpm.lock",
    "tools/markdown/cjpm.toml",
    "tools/markdown/cjpm.lock",
    "scripts/build_benchmark_driver.py",
    "scripts/build_native_scanner.py",
)

ENVIRONMENT_ATTESTATION_SCHEMA_VERSION = 1
CANGJIE_HEAP_SIZE = "2GB"
CANGJIE_GC_INTERVAL = "500ms"
CANONICAL_LOCALE = "C.UTF-8"
CANONICAL_TIMEZONE = "UTC"
SYSTEM_EXECUTABLE_PATHS = ("/usr/bin", "/bin")
BUILD_ENVIRONMENT_KEYS = (
    "CANGJIE_HOME",
    "CANGJIE_SDK_ROOT",
    "HOME",
    "LANG",
    "LC_ALL",
    "LD_LIBRARY_PATH",
    "MARKDOWN_NATIVE_SCANNER",
    "PATH",
    "TMPDIR",
    "TZ",
)
NATIVE_BUILD_ENVIRONMENT_KEYS = (
    "COMSPEC",
    "DEVELOPER_DIR",
    "HOME",
    "INCLUDE",
    "LANG",
    "LC_ALL",
    "LIB",
    "LIBPATH",
    "MACOSX_DEPLOYMENT_TARGET",
    "PATH",
    "PATHEXT",
    "SDKROOT",
    "SOURCE_DATE_EPOCH",
    "SYSTEMROOT",
    "SystemRoot",
    "TEMP",
    "TMP",
    "TMPDIR",
    "UniversalCRTSdkDir",
    "UCRTVersion",
    "VCINSTALLDIR",
    "VCToolsInstallDir",
    "WindowsSDKVersion",
    "WindowsSdkDir",
    "TZ",
)
EXECUTION_ENVIRONMENT_KEYS = tuple(sorted((*BUILD_ENVIRONMENT_KEYS,
    "cjGCInterval", "cjHeapSize")))
BLOCKED_AMBIENT_ENVIRONMENT_KEYS = (
    "CPLUS_INCLUDE_PATH",
    "C_INCLUDE_PATH",
    "COMPILER_PATH",
    "CPATH",
    "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH",
    "GLIBC_TUNABLES",
    "LD_AUDIT",
    "LD_LIBRARY_PATH",
    "LD_PRELOAD",
    "LIBRARY_PATH",
    "MALLOC_ARENA_MAX",
    "MALLOC_CONF",
    "MALLOC_MMAP_THRESHOLD_",
    "MALLOC_PERTURB_",
    "MALLOC_TRIM_THRESHOLD_",
    "MARKDOWN_NATIVE_ARFLAGS",
    "MARKDOWN_NATIVE_CFLAGS",
    "TARGET",
    "cjGCInterval",
    "cjHeapSize",
)
COMPARATOR_LOADER_DIFFERENCE_REASON = (
    "markdown4cj loads commonmark4cj from the fresh adapter target"
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


def benchmark_product_file_sha256s(root: Path) -> dict[str, str]:
    """Return the exact file set whose contents can change a benchmark binary."""
    return {
        path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in benchmark_product_files(root)
    }


def canonical_json_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def exact_environment(environment: dict[str, str], keys: tuple[str, ...],
        label: str) -> dict[str, str]:
    expected = set(keys)
    actual = set(environment)
    if actual != expected:
        missing = ", ".join(sorted(expected - actual)) or "none"
        unexpected = ", ".join(sorted(actual - expected)) or "none"
        raise ValueError(
            f"{label} environment is not allowlisted; missing: {missing}; "
            f"unexpected: {unexpected}"
        )
    if any(not isinstance(environment[name], str) for name in keys):
        raise ValueError(f"{label} environment values must be strings")
    return {name: environment[name] for name in sorted(keys)}


def canonical_build_environment(root: Path, target: str) -> dict[str, str]:
    if not root.is_absolute() or "-" not in target:
        raise ValueError(
            "canonical build environment requires an absolute SDK root and target")
    root = root.resolve()
    architecture = target.split("-", 1)[0]
    paths = (root / "bin", root / "tools" / "bin",
        *(Path(value) for value in SYSTEM_EXECUTABLE_PATHS))
    libraries = (root / "runtime" / "lib" / f"linux_{architecture}_cjnative",
        root / "tools" / "lib")
    return exact_environment({
        "CANGJIE_HOME": str(root),
        "CANGJIE_SDK_ROOT": str(root),
        "HOME": str(root / ".benchmark-home"),
        "LANG": CANONICAL_LOCALE,
        "LC_ALL": CANONICAL_LOCALE,
        "LD_LIBRARY_PATH": os.pathsep.join(str(path) for path in libraries),
        "MARKDOWN_NATIVE_SCANNER": "0",
        "PATH": os.pathsep.join(str(path) for path in paths),
        "TMPDIR": str(root / ".benchmark-tmp"),
        "TZ": CANONICAL_TIMEZONE,
    }, BUILD_ENVIRONMENT_KEYS, "benchmark build")


def canonical_execution_environments(build_environment: dict[str, str],
        comparator_library_path: Path) -> tuple[dict[str, str], dict[str, str]]:
    common = exact_environment(build_environment, BUILD_ENVIRONMENT_KEYS,
        "benchmark build")
    comparator_library_path = comparator_library_path.resolve()
    if not comparator_library_path.is_absolute():
        raise ValueError("comparator library path must be absolute")
    markdown = dict(common)
    markdown["cjGCInterval"] = CANGJIE_GC_INTERVAL
    markdown["cjHeapSize"] = CANGJIE_HEAP_SIZE
    markdown = exact_environment(markdown, EXECUTION_ENVIRONMENT_KEYS,
        "markdown execution")
    comparator = dict(markdown)
    comparator["LD_LIBRARY_PATH"] = os.pathsep.join((
        str(comparator_library_path), markdown["LD_LIBRARY_PATH"]))
    comparator = exact_environment(comparator, EXECUTION_ENVIRONMENT_KEYS,
        "markdown4cj execution")
    return markdown, comparator


def environment_record(environment: dict[str, str], keys: tuple[str, ...],
        label: str) -> dict[str, object]:
    variables = exact_environment(environment, keys, label)
    return {"variables": variables, "sha256": canonical_json_sha256(variables)}


def build_environment_attestation(environment: dict[str, str]) -> dict[str, object]:
    return {
        "schemaVersion": ENVIRONMENT_ATTESTATION_SCHEMA_VERSION,
        "allowlist": sorted(BUILD_ENVIRONMENT_KEYS),
        "blockedAmbient": sorted(BLOCKED_AMBIENT_ENVIRONMENT_KEYS),
        **environment_record(environment, BUILD_ENVIRONMENT_KEYS, "benchmark build"),
    }


def execution_environment_attestation(markdown: dict[str, str],
        comparator: dict[str, str]) -> dict[str, object]:
    left = exact_environment(markdown, EXECUTION_ENVIRONMENT_KEYS,
        "markdown execution")
    right = exact_environment(comparator, EXECUTION_ENVIRONMENT_KEYS,
        "markdown4cj execution")
    differences = {
        name: {"markdown": left.get(name, ""), "markdown4cj": right.get(name, "")}
        for name in sorted(set(left) | set(right)) if left.get(name) != right.get(name)
    }
    if set(differences) != {"LD_LIBRARY_PATH"}:
        raise ValueError("benchmark sides may differ only in LD_LIBRARY_PATH")
    differences["LD_LIBRARY_PATH"]["reason"] = COMPARATOR_LOADER_DIFFERENCE_REASON
    return {
        "schemaVersion": ENVIRONMENT_ATTESTATION_SCHEMA_VERSION,
        "allowlist": sorted(EXECUTION_ENVIRONMENT_KEYS),
        "blockedAmbient": sorted(BLOCKED_AMBIENT_ENVIRONMENT_KEYS),
        "markdown": environment_record(left, EXECUTION_ENVIRONMENT_KEYS,
            "markdown execution"),
        "markdown4cj": environment_record(right, EXECUTION_ENVIRONMENT_KEYS,
            "markdown4cj execution"),
        "differences": differences,
    }


def reject_ambient_benchmark_environment(environment: dict[str, str]) -> None:
    active = [name for name in BLOCKED_AMBIENT_ENVIRONMENT_KEYS
        if environment.get(name)]
    if active:
        raise RuntimeError("canonical benchmark rejects ambient performance variables: " +
            ", ".join(active))
