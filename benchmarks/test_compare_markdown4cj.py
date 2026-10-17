#!/usr/bin/env python3
"""Regression tests for the same-language benchmark gate."""

from __future__ import annotations

import copy
import hashlib
from io import StringIO
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
from types import SimpleNamespace
import tempfile
import time
import unittest
from unittest.mock import patch

import compare_markdown4cj as comparison
from benchmark_identity import benchmark_product_file_sha256s, \
    benchmark_product_tree_sha256


ORIGINAL_ROOT = comparison.ROOT
IDENTITY_REPOSITORY: tempfile.TemporaryDirectory[str] | None = None
IDENTITY_ROOT: Path | None = None
ANCESTOR_COMMIT = ""
COMPARATOR_ROOT: Path | None = None
COMMONMARK_ROOT: Path | None = None
BINARY_ROOT: Path | None = None
ORIGINAL_COMPARATOR_COMMIT = comparison.COMPARATOR_COMMIT
ORIGINAL_COMMONMARK_COMMIT = comparison.COMMONMARK_COMMIT


def elf64_with_needed(names: tuple[str, ...], *, include_dynamic: bool = True,
        duplicate_dynamic: bool = False, terminate: bool = True,
        string_address: int | None = None, path_tag: int | None = None,
        interpreter: str | None = None) -> bytes:
    strings = bytearray(b"\0")
    offsets = []
    for name in names:
        offsets.append(len(strings))
        strings.extend(name.encode("utf-8") + b"\0")
    dynamic_offset = 0x200
    dynamic_entry_count = len(offsets) + 2 + (1 if terminate else 0) + \
        (1 if path_tag is not None else 0)
    dynamic_size = dynamic_entry_count * 16
    string_offset = dynamic_offset + dynamic_size
    base_address = 0x400000
    dynamic = b"".join(struct.pack("<qQ", 1, offset) for offset in offsets)
    dynamic += struct.pack("<qQ", 5,
        base_address + string_offset if string_address is None else string_address)
    dynamic += struct.pack("<qQ", 10, len(strings))
    if path_tag is not None:
        dynamic += struct.pack("<qQ", path_tag, 0)
    if terminate:
        dynamic += struct.pack("<qQ", 0, 0)
    dynamic_count = (2 if duplicate_dynamic else 1) if include_dynamic else 0
    program_count = 1 + dynamic_count + (1 if interpreter is not None else 0)
    interpreter_bytes = (interpreter.encode("utf-8") + b"\0") \
        if interpreter is not None else b""
    interpreter_offset = string_offset + len(strings)
    file_size = interpreter_offset + len(interpreter_bytes)
    header = struct.pack("<16sHHIQQQIHHHHHH",
        b"\x7fELF\x02\x01\x01" + b"\0" * 9, 3, 62, 1, 0, 64,
        0, 0, 64, 56, program_count, 0, 0, 0)
    load = struct.pack("<IIQQQQQQ", 1, 5, 0, base_address, base_address,
        file_size, file_size, 0x1000)
    dynamic_program = struct.pack("<IIQQQQQQ", 2, 6, dynamic_offset,
        base_address + dynamic_offset, base_address + dynamic_offset,
        len(dynamic), len(dynamic), 8)
    interpreter_program = struct.pack("<IIQQQQQQ", 3, 4, interpreter_offset,
        base_address + interpreter_offset, base_address + interpreter_offset,
        len(interpreter_bytes), len(interpreter_bytes), 1) \
        if interpreter is not None else b""
    programs = load + (dynamic_program * dynamic_count) + interpreter_program
    padding = b"\0" * (dynamic_offset - len(header) - len(programs))
    return header + programs + padding + dynamic + bytes(strings) + interpreter_bytes


def elf64_with_fake_section_needed(program_names: tuple[str, ...],
        section_names: tuple[str, ...]) -> bytes:
    data = bytearray(elf64_with_needed(program_names))
    strings = bytearray(b"\0")
    offsets = []
    for name in section_names:
        offsets.append(len(strings))
        strings.extend(name.encode("utf-8") + b"\0")
    dynamic = b"".join(struct.pack("<qQ", 1, offset) for offset in offsets) + \
        struct.pack("<qQ", 0, 0)
    dynamic_offset = len(data)
    data.extend(dynamic)
    string_offset = dynamic_offset + len(dynamic)
    data.extend(strings)
    section_offset = (len(data) + 7) & ~7
    data.extend(b"\0" * (section_offset - len(data)))
    null_section = b"\0" * 64
    dynamic_section = struct.pack("<IIQQQQIIQQ", 0, 6, 0, 0,
        dynamic_offset, len(dynamic), 2, 0, 8, 16)
    string_section = struct.pack("<IIQQQQIIQQ", 0, 3, 0, 0,
        string_offset, len(strings), 0, 0, 1, 0)
    data.extend(null_section + dynamic_section + string_section)
    struct.pack_into("<Q", data, 40, section_offset)
    struct.pack_into("<H", data, 58, 64)
    struct.pack_into("<H", data, 60, 3)
    return bytes(data)


def test_git(root: Path, *arguments: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *arguments], text=True,
        capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "test Git command failed")
    return result.stdout.strip()


def setUpModule() -> None:
    global IDENTITY_REPOSITORY, IDENTITY_ROOT, ANCESTOR_COMMIT
    global COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT
    IDENTITY_REPOSITORY = tempfile.TemporaryDirectory(
        prefix="markdown-benchmark-git-identity-")
    root = Path(IDENTITY_REPOSITORY.name) / "markdown"
    root.mkdir()
    relative_paths = set(benchmark_product_file_sha256s(ORIGINAL_ROOT)) | \
        set(comparison.HARNESS_FILES)
    for relative in sorted(relative_paths):
        source = ORIGINAL_ROOT / relative
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    test_git(root, "init", "--quiet")
    test_git(root, "config", "user.name", "Benchmark Identity Test")
    test_git(root, "config", "user.email", "benchmark-identity@example.invalid")
    test_git(root, "config", "core.hooksPath", os.devnull)
    test_git(root, "add", "--all")
    test_git(root, "commit", "--quiet", "-m", "baseline benchmark identity")
    ANCESTOR_COMMIT = test_git(root, "rev-parse", "HEAD")
    marker = root / "src/git_identity_current_marker.cj"
    marker.write_text("package markdown\n", encoding="utf-8")
    test_git(root, "add", marker.relative_to(root).as_posix())
    test_git(root, "commit", "--quiet", "-m", "current benchmark identity")
    IDENTITY_ROOT = root
    comparison.ROOT = root

    comparator = Path(IDENTITY_REPOSITORY.name) / "markdown4cj"
    core = comparator / comparison.COMPARATOR_CORE_PATH
    core.mkdir(parents=True)
    for filename, replacements in comparison.MIGRATIONS.items():
        text = "".join(before if before.endswith("\n") else before + "\n"
            for before, _ in replacements)
        (core / filename).write_text(text, encoding="utf-8")
    nested = core / "nested/extra.cj"
    nested.parent.mkdir()
    nested.write_text("package markdown.core\n", encoding="utf-8")
    test_git(comparator, "init", "--quiet")
    test_git(comparator, "config", "user.name", "Comparator Identity Test")
    test_git(comparator, "config", "user.email", "comparator@example.invalid")
    test_git(comparator, "config", "core.hooksPath", os.devnull)
    test_git(comparator, "add", "-f", "--all")
    test_git(comparator, "commit", "--quiet", "-m", "pinned comparator")
    comparison.COMPARATOR_COMMIT = test_git(comparator, "rev-parse", "HEAD")
    COMPARATOR_ROOT = comparator

    commonmark = Path(IDENTITY_REPOSITORY.name) / "commonmark4cj"
    (commonmark / "src").mkdir(parents=True)
    (commonmark / "cjpm.toml").write_text(
        "[package]\n  name = \"commonmark4cj\"\n"
        "  output-type = \"dynamic\"\n"
        "  compile-option = \"\"\n"
        "\n[profile]\n  [profile.build]\n    incremental = true\n",
        encoding="utf-8")
    (commonmark / "src/commonmark.cj").write_text("package commonmark4cj\n",
        encoding="utf-8")
    test_git(commonmark, "init", "--quiet")
    test_git(commonmark, "config", "user.name", "Comparator Identity Test")
    test_git(commonmark, "config", "user.email", "comparator@example.invalid")
    test_git(commonmark, "config", "core.hooksPath", os.devnull)
    test_git(commonmark, "add", "-f", "--all")
    test_git(commonmark, "commit", "--quiet", "-m", "pinned commonmark")
    comparison.COMMONMARK_COMMIT = test_git(commonmark, "rev-parse", "HEAD")
    COMMONMARK_ROOT = commonmark

    binary_root = Path(IDENTITY_REPOSITORY.name) / "retained-binaries"
    binary_root.mkdir()
    for name, artifact_path in comparison.BINARY_ARTIFACTS.items():
        path = binary_root / artifact_path
        if name == "markdown4cj":
            path.write_bytes(elf64_with_needed(()))
        else:
            path.write_bytes(f"{name}-retained-executable\n".encode("utf-8"))
        path.chmod(0o755)
    for name, artifact_path in comparison.NATIVE_TOOL_ARTIFACTS.items():
        tool = binary_root / artifact_path
        tool.parent.mkdir(parents=True, exist_ok=True)
        tool.write_bytes(elf64_with_needed(("libc.so.6",),
            interpreter="/lib64/ld-linux-x86-64.so.2"))
        tool.chmod(0o755)
    resource_source = Path(IDENTITY_REPOSITORY.name) / "clang-resource"
    resource_source.mkdir()
    (resource_source / "stddef.h").write_text("/* retained */\n", encoding="utf-8")
    resource_archive = binary_root / comparison.NATIVE_RESOURCE_ARTIFACT
    resource_archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(resource_archive, "w") as bundle:
        bundle.add(resource_source / "stddef.h", arcname="stddef.h")
    runtime_root = binary_root / comparison.NATIVE_RUNTIME_ROOT
    runtime_root.mkdir(parents=True)
    loader = runtime_root / "loader"
    loader.write_bytes(Path("/lib64/ld-linux-x86-64.so.2").read_bytes())
    loader.chmod(0o755)
    runtime_library = runtime_root / "libraries/libc.so.6"
    runtime_library.parent.mkdir()
    runtime_library.write_bytes(elf64_with_needed(("ld-linux-x86-64.so.2",)))
    runtime_library.chmod(0o644)
    BINARY_ROOT = binary_root


def tearDownModule() -> None:
    global IDENTITY_REPOSITORY, IDENTITY_ROOT, COMPARATOR_ROOT, COMMONMARK_ROOT
    global BINARY_ROOT
    comparison.ROOT = ORIGINAL_ROOT
    comparison.COMPARATOR_COMMIT = ORIGINAL_COMPARATOR_COMMIT
    comparison.COMMONMARK_COMMIT = ORIGINAL_COMMONMARK_COMMIT
    if IDENTITY_REPOSITORY is not None:
        IDENTITY_REPOSITORY.cleanup()
    IDENTITY_REPOSITORY = None
    IDENTITY_ROOT = None
    COMPARATOR_ROOT = None
    COMMONMARK_ROOT = None
    BINARY_ROOT = None


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def output(data: bytes = b"<p>x</p>\n") -> dict[str, object]:
    return {"bytes": len(data), "sha256": digest(data)}


def parity(data: bytes = b"<p>x</p>\n") -> dict[str, object]:
    identity = output(data)
    return {"markdown": dict(identity), "markdown4cj": dict(identity),
        "equalSpecHtml": True}


def sample(seconds: float, rss: int) -> dict[str, object]:
    stdout = "1\n"
    encoded = stdout.encode("utf-8")
    return {"seconds": seconds, "peakRssKiB": rss, "stdout": stdout,
        "stdoutBytes": len(encoded), "stdoutSha256": digest(encoded)}


def sdk_command_environment(root: str = "/fresh/cangjie") -> dict[str, str]:
    return comparison.canonical_build_environment(Path(root),
        comparison.TARGET_TRIPLE)


def process_environments(root: str = "/fresh/cangjie") -> tuple[dict[str, str], dict[str, str]]:
    assert BINARY_ROOT is not None
    return comparison.canonical_execution_environments(
        sdk_command_environment(root), BINARY_ROOT / comparison.RUNTIME_LIBRARY_ROOT)


def tool_record(path: str, suffix: str, stdout: str) -> dict[str, object]:
    return {"path": path, "command": [path, suffix], "cwd": "/workspace/markdown",
        "exitCode": 0, "stdout": stdout, "stderr": "", "bytes": 1234,
        "sha256": digest(path.encode("utf-8")),
        "environment": sdk_command_environment()}


def binary(path: str, value: str, length: int = 1234) -> dict[str, object]:
    return {"path": path, "bytes": length, "sha256": value}


def build_record(name: str, binary_identity: dict[str, object],
        source_snapshot: dict[str, object]) -> dict[str, object]:
    if name == "markdownDriver":
        manifest_relative = "benchmarks/driver/cjpm.toml"
        compile_option = "-O2 --lto thin --obf-seed 0"
        link_option = "-L ../../target/native -lmarkdown_scanner"
    else:
        manifest_relative = "tools/markdown/cjpm.toml"
        compile_option = "-O2 --obf-seed 0"
        link_option = ""
    manifest = comparison.ROOT / manifest_relative
    source_files = source_snapshot["productFiles"]
    assert isinstance(source_files, dict)
    manifest_digest = source_files[manifest_relative]
    trim_path = str(comparison.ROOT.resolve())
    return {"mode": "canonical",
        "sourceProductTreeSha256": source_snapshot["productTreeSha256"],
        "trimPath": trim_path,
        "build": {"command": ["/fresh/cangjie/tools/bin/cjpm", "build", "-j", "1"],
            "cwd": str(manifest.parent),
            "exitCode": 0, "stdout": "build succeeded\n", "stderr": "",
            "environment": sdk_command_environment()},
        "compileOption": f"{compile_option} --trimpath {trim_path}",
        "linkOption": link_option,
        "canonicalManifestSha256": manifest_digest,
        "effectiveManifestSha256": "e" * 64,
        "canonicalRootManifestSha256": source_files["cjpm.toml"],
        "effectiveRootManifestSha256": "f" * 64,
        "binary": binary_identity}


def valid_report() -> dict[str, object]:
    assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
    assert BINARY_ROOT is not None
    inputs = comparison.benchmark_inputs()
    with patch.dict(os.environ, {"MARKDOWN_BENCHMARK_COMMIT": "HEAD"}):
        identity = comparison.repository_identity()
    source_snapshot = comparison.git_repository_snapshot(comparison.ROOT, "HEAD")
    identity["corpora"] = comparison.corpus_identity(inputs)
    source_files = source_snapshot["productFiles"]
    assert isinstance(source_files, dict)
    rows = {}
    semantics = {}
    for name, data in inputs.items():
        left = [sample(1.0, 100) for _ in range(comparison.SAMPLES)]
        right = [sample(2.0, 200) for _ in range(comparison.SAMPLES)]
        rows[name] = {"bytes": len(data), "markdown": left, "markdown4cj": right,
            "markdownMedianSeconds": 1.0, "markdown4cjMedianSeconds": 2.0,
            "markdownSpeedup": 2.0, "peakRssRatio": 0.5}
        semantics[name] = {"sourceBytes": len(data),
            "sourceSha256": digest(data), "specHtml": parity()}
    shared_cases = {}
    for name, source in comparison.BEHAVIOR_CASES.items():
        data = source.encode("utf-8")
        shared_cases[name] = {"sourceBytes": len(data),
            "sourceSha256": digest(data), "specHtml": parity()}

    retained = {name: comparison.retained_binary_identity(
        BINARY_ROOT / artifact_path, artifact_path)
        for name, artifact_path in comparison.BINARY_ARTIFACTS.items()}
    retained_runtime = {path.name: comparison.retained_library_identity(
        path, path.relative_to(BINARY_ROOT).as_posix())
        for path in (BINARY_ROOT / comparison.RUNTIME_LIBRARY_ROOT).glob("*.so")}
    markdown_binary = binary("/workspace/markdown/benchmarks/driver/main",
        str(retained["markdown"]["sha256"]), int(retained["markdown"]["bytes"]))
    cli_binary = binary("/workspace/markdown/tools/markdown/main",
        str(retained["markdownCli"]["sha256"]), int(retained["markdownCli"]["bytes"]))
    comparator_binary = binary("/tmp/adapter/main",
        str(retained["markdown4cj"]["sha256"]),
        int(retained["markdown4cj"]["bytes"]))
    cjc = tool_record("/fresh/cangjie/bin/cjc", "-v",
        f"Cangjie Compiler: test\nTarget: {comparison.TARGET_TRIPLE}\n")
    cjpm = tool_record("/fresh/cangjie/tools/bin/cjpm", "--version", "cjpm test\n")
    native_object = binary(
        "/workspace/markdown/target/native/markdown_scanner.o", "4" * 64)
    native_archive = binary(
        "/workspace/markdown/target/native/libmarkdown_scanner.a", "5" * 64)
    retained_native = {name: comparison.retained_library_identity(
        BINARY_ROOT / artifact_path, artifact_path)
        for name, artifact_path in comparison.NATIVE_TOOL_ARTIFACTS.items()}
    retained_resource = comparison.retained_binary_identity(
        BINARY_ROOT / comparison.NATIVE_RESOURCE_ARTIFACT,
        comparison.NATIVE_RESOURCE_ARTIFACT)
    retained_native_runtime = {
        "interpreterPath": "/lib64/ld-linux-x86-64.so.2",
        "loader": comparison.retained_library_identity(
            BINARY_ROOT / comparison.NATIVE_RUNTIME_ROOT / "loader",
            (comparison.NATIVE_RUNTIME_ROOT / "loader").as_posix()),
        "libraries": {"libc.so.6": comparison.retained_library_identity(
            BINARY_ROOT / comparison.NATIVE_RUNTIME_ROOT / "libraries/libc.so.6",
            (comparison.NATIVE_RUNTIME_ROOT / "libraries/libc.so.6").as_posix())},
    }
    native_compiler = binary("/usr/bin/clang",
        str(retained_native["compiler"]["sha256"]),
        int(retained_native["compiler"]["bytes"]))
    native_compiler["version"] = {"command": ["/usr/bin/clang", "--version"],
        "exitCode": 0, "stdout": "clang test\n", "stderr": ""}
    native_archiver = binary("/usr/bin/ar",
        str(retained_native["archiver"]["sha256"]),
        int(retained_native["archiver"]["bytes"]))
    native_archiver["version"] = {"command": ["/usr/bin/ar", "--version"],
        "exitCode": 0, "stdout": "ar test\n", "stderr": ""}
    native_environment = {
        "HOME": "/workspace/markdown/target/native/.native-build-home",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": "/usr/bin:/bin",
        "SOURCE_DATE_EPOCH": "0",
        "TMPDIR": "/workspace/markdown/target/native/.native-build-tmp",
        "TZ": "UTC",
    }
    native_manifest = {
        "schemaVersion": comparison.NATIVE_CACHE_SCHEMA_VERSION,
        "sourceSha256": source_files["native/markdown_scanner.c"],
        "headerSha256": source_files["native/markdown_scanner.h"],
        "target": comparison.TARGET_TRIPLE,
        "platformBranch": "gnu-like",
        "compiler": native_compiler,
        "archiver": native_archiver,
        "compileCommand": ["/usr/bin/clang", "-target", comparison.TARGET_TRIPLE,
            "-O3", "-c", "native/markdown_scanner.c", "-o", native_object["path"]],
        "archiveCommand": ["/usr/bin/ar", "rcs",
            native_archive["path"], native_object["path"]],
        "buildEnvironment": {
            "schemaVersion": comparison.NATIVE_ENVIRONMENT_SCHEMA_VERSION,
            "allowlist": sorted(comparison.NATIVE_BUILD_ENVIRONMENT_KEYS),
            "variables": native_environment,
            "sha256": comparison.canonical_json_sha256(native_environment),
        },
        "object": dict(native_object),
        "archive": dict(native_archive),
    }
    build_identity = {
        "schemaVersion": comparison.BUILD_IDENTITY_SCHEMA_VERSION,
        "sdk": {"archiveUrl": comparison.SDK_URL,
            "archiveSha256": comparison.SDK_SHA256, "archiveBytes": 100,
            "archivePath": "/tmp/cangjie-sdk.tar.gz",
            "target": comparison.TARGET_TRIPLE, "extraction": "/fresh",
            "root": "/fresh/cangjie", "envsetupSha256": "a" * 64,
            "environment": comparison.build_environment_attestation(
                sdk_command_environment())},
        "tools": {"cjc": cjc, "cjpm": cjpm},
        "sourceIdentity": {
            "productTreeSha256": source_snapshot["productTreeSha256"],
            "files": dict(source_files)},
        "nativeScanner": {"cacheManifest": native_manifest,
            "cacheManifestSha256": comparison.canonical_json_sha256(native_manifest),
            "compiler": copy.deepcopy(native_compiler),
            "archiver": copy.deepcopy(native_archiver),
            "buildEnvironment": copy.deepcopy(native_manifest["buildEnvironment"]),
            "object": native_object, "archive": native_archive},
        "builds": {
            "markdownDriver": build_record("markdownDriver", markdown_binary,
                source_snapshot),
            "markdownCli": build_record("markdownCli", cli_binary,
                source_snapshot),
        },
    }
    provenance, _, _ = comparison.adapter_source_inputs(COMPARATOR_ROOT,
        COMMONMARK_ROOT)
    adapter_build = {"command": ["/fresh/cangjie/tools/bin/cjpm", "build", "-j", "1", "-V"],
        "cwd": "/tmp/adapter",
        "exitCode": 0, "stdout": "build succeeded\n", "stderr": "",
        "environment": sdk_command_environment(),
        "excluded": ["components/**", "plugin/**", "cj_res/**"],
        "ohosImportCount": 0,
        **{key: copy.deepcopy(value) for key, value in provenance.items()
            if key != "repositories"},
        "trimPath": "/tmp/adapter",
        "manifestSha256": digest(comparison.MANIFEST.format(
            commonmark=comparison.ADAPTER_COMMONMARK_PATH,
            trimpath="/tmp/adapter").encode("utf-8")),
        "dependencyManifestSha256": digest(comparison.adapter_dependency_manifest(
            (COMMONMARK_ROOT / "cjpm.toml").read_bytes(),
            "/tmp/adapter")),
        "binarySourceIdentitySha256": provenance["adapterInputSha256"],
        "buildOutputBinary": comparator_binary,
        "buildOutputRuntimeLibraries": {name: {
            "path": f"/tmp/adapter/target/release/commonmark4cj/{name}",
            "bytes": identity["bytes"], "sha256": identity["sha256"],
            "mode": identity["mode"]}
            for name, identity in retained_runtime.items()},
        "binary": copy.deepcopy(retained["markdown4cj"]),
        "runtimeLibraries": copy.deepcopy(retained_runtime)}
    left_environment, right_environment = process_environments()
    return {"schemaVersion": comparison.SCHEMA_VERSION, "status": "PASS",
        "identity": identity,
        "buildIdentity": build_identity,
        "sourceInputs": {"markdown4cj": str(COMPARATOR_ROOT),
            "commonmark4cj": str(COMMONMARK_ROOT)},
        "binaryInputs": {"root": str(BINARY_ROOT)},
        "sourceRepositories": copy.deepcopy(provenance["repositories"]),
        "drivers": copy.deepcopy(retained),
        "runtimeLibraries": copy.deepcopy(retained_runtime),
        "nativeTools": copy.deepcopy(retained_native),
        "nativeCompilerResource": {**retained_resource,
            "sourceCommand": ["/usr/bin/clang", "-print-resource-dir"],
            "sourceTreeSha256": comparison.directory_tree_sha256(
                Path(IDENTITY_REPOSITORY.name) / "clang-resource")},
        "nativeToolRuntime": copy.deepcopy(retained_native_runtime),
        "adapterBuild": adapter_build,
        "comparator": {"url": comparison.COMPARATOR_URL,
            "commit": comparison.COMPARATOR_COMMIT},
        "commonmark4cj": {"url": comparison.COMMONMARK_URL,
            "commit": comparison.COMMONMARK_COMMIT},
        "thresholds": {"minimumGeomeanSpeedup": comparison.MIN_SPEEDUP,
            "maximumPerCorpusRegression": comparison.MAX_REGRESSION,
            "maximumPeakRssRatio": comparison.MAX_RSS_RATIO},
        "environment": {"platform": "Linux-test", "cpu": 2,
            "tools": build_identity["tools"],
            "processes": comparison.execution_environment_attestation(
                left_environment, right_environment)},
        "protocol": {"workload": "CommonMark parse-only",
            "corpusBytes": comparison.CORPUS_BYTES,
            "iterationsPerProcess": comparison.ITERATIONS, "warmupsPerSide": 1,
            "samplesPerSide": comparison.SAMPLES,
            "order": "alternating; odd sample reverses order",
            "semanticGate": "untimed exact CommonMark spec-HTML byte length and SHA-256 from commonmark-spec-html for every corpus"},
        "sharedBehavior": {"caseCount": len(comparison.BEHAVIOR_CASES),
            "passCount": len(comparison.BEHAVIOR_CASES), "pass": True,
            "cases": shared_cases},
        "corpusSemantics": semantics,
        "corpora": rows, "geomeanMarkdownSpeedup": 2.0, "promotionPassed": True}


def bind_report_to_snapshot(report: dict[str, object], reference: str,
        snapshot: dict[str, object]) -> None:
    identity = report["identity"]
    assert isinstance(identity, dict)
    identity.update({"gitObjectFormat": snapshot["gitObjectFormat"],
        "repositoryRef": reference, "repositoryCommit": snapshot["repositoryCommit"],
        "gitTree": snapshot["gitTree"],
        "productTreeSha256": snapshot["productTreeSha256"],
        "harnessFiles": copy.deepcopy(snapshot["harnessFiles"])})
    build_identity = report["buildIdentity"]
    assert isinstance(build_identity, dict)
    source_files = snapshot["productFiles"]
    assert isinstance(source_files, dict)
    build_identity["sourceIdentity"] = {
        "productTreeSha256": snapshot["productTreeSha256"],
        "files": dict(source_files),
    }
    native = build_identity["nativeScanner"]
    assert isinstance(native, dict)
    manifest = native["cacheManifest"]
    assert isinstance(manifest, dict)
    manifest["sourceSha256"] = source_files["native/markdown_scanner.c"]
    manifest["headerSha256"] = source_files["native/markdown_scanner.h"]
    native["cacheManifestSha256"] = comparison.canonical_json_sha256(manifest)
    builds = build_identity["builds"]
    assert isinstance(builds, dict)
    for name, manifest_path in (("markdownDriver", "benchmarks/driver/cjpm.toml"),
            ("markdownCli", "tools/markdown/cjpm.toml")):
        build = builds[name]
        assert isinstance(build, dict)
        build["sourceProductTreeSha256"] = snapshot["productTreeSha256"]
        build["canonicalManifestSha256"] = source_files[manifest_path]
        build["effectiveManifestSha256"] = source_files[manifest_path]


class SameLanguageBenchmarkTest(unittest.TestCase):
    def test_adapter_dependency_manifest_is_static_and_deterministic(self) -> None:
        manifest = comparison.adapter_dependency_manifest(
            b'[package]\n  compile-option = ""\n  output-type = "dynamic"\n'
            b'\n[profile]\n  [profile.build]\n    incremental = true\n',
            "/tmp/fresh-adapter")
        self.assertIn(b'compile-option = " --obf-seed 0 --trimpath /tmp/fresh-adapter"',
            manifest)
        self.assertIn(b'output-type = "static"', manifest)
        self.assertIn(b'incremental = false', manifest)

    def test_adapter_dependency_manifest_rejects_unpinned_layout(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "canonical output type"):
            comparison.adapter_dependency_manifest(
                b'[package]\n  compile-option = ""\n'
                b'\n[profile]\n  [profile.build]\n    incremental = true\n',
                "/tmp/fresh-adapter")

    def test_static_adapter_closure_requires_explicit_opt_in(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "main"
            binary.write_bytes(elf64_with_needed(()))
            libraries = root / "libraries"
            libraries.mkdir()
            with self.assertRaisesRegex(RuntimeError, "no retained runtime"):
                comparison.adapter_runtime_library_sources(binary, libraries)
            self.assertEqual(comparison.adapter_runtime_library_sources(
                binary, libraries, allow_static=True), {})

    def test_elf_dependencies_use_loader_program_headers_not_sections(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "adapter"
            artifact.write_bytes(elf64_with_fake_section_needed(
                ("libcommonmark4cj.commonmark.so",),
                ("libcommonmark4cj.table.so",)))
            dependencies = comparison.elf_dynamic_dependencies(artifact)
        self.assertEqual(dependencies, ("libcommonmark4cj.commonmark.so",))

    def test_elf_dependencies_reject_missing_or_duplicate_dynamic_segments(self) -> None:
        for label, data in (("missing", elf64_with_needed((), include_dynamic=False)),
                ("duplicate", elf64_with_needed((), duplicate_dynamic=True))):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                artifact = Path(temporary) / "adapter"
                artifact.write_bytes(data)
                with self.assertRaisesRegex(RuntimeError, "exactly one PT_DYNAMIC"):
                    comparison.elf_dynamic_dependencies(artifact)

    def test_elf_dependencies_reject_unmapped_string_table(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "adapter"
            artifact.write_bytes(elf64_with_needed(("libx.so",),
                string_address=0x900000))
            with self.assertRaisesRegex(RuntimeError, "no unique PT_LOAD mapping"):
                comparison.elf_dynamic_dependencies(artifact)

    def test_elf_dependencies_reject_missing_null_and_truncated_segments(self) -> None:
        for label, data, message in (
                ("null", elf64_with_needed(("libx.so",), terminate=False),
                    "no DT_NULL"),
                ("truncated", elf64_with_needed(("libx.so",))[:-1],
                    "segment bounds")):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                artifact = Path(temporary) / "adapter"
                artifact.write_bytes(data)
                with self.assertRaisesRegex(RuntimeError, message):
                    comparison.elf_dynamic_dependencies(artifact)

    def test_elf_dependencies_reject_rpath_and_runpath(self) -> None:
        for tag in (15, 29):
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as temporary:
                artifact = Path(temporary) / "adapter"
                artifact.write_bytes(elf64_with_needed(("libx.so",), path_tag=tag))
                with self.assertRaisesRegex(RuntimeError, "RPATH or RUNPATH"):
                    comparison.elf_dynamic_dependencies(artifact)

    def test_native_runtime_dependency_scan_ignores_but_does_not_use_search_paths(self) -> None:
        for tag in (15, 29):
            with self.subTest(tag=tag), tempfile.TemporaryDirectory() as temporary:
                artifact = Path(temporary) / "native-runtime-library"
                artifact.write_bytes(elf64_with_needed(("libx.so",), path_tag=tag))
                self.assertEqual(comparison.elf_dynamic_dependencies(artifact,
                    reject_search_paths=False), ("libx.so",))

    def test_elf_dependencies_reject_ambiguous_load_mapping(self) -> None:
        data = bytearray(elf64_with_needed(("libx.so",)))
        load = bytes(data[64:120])
        data[176:232] = load
        struct.pack_into("<H", data, 56, 3)
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "adapter"
            artifact.write_bytes(data)
            with self.assertRaisesRegex(RuntimeError, "no unique PT_LOAD mapping"):
                comparison.elf_dynamic_dependencies(artifact)

    def test_elf_dependencies_reject_unsafe_needed_name(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "adapter"
            artifact.write_bytes(elf64_with_needed(("../libescape.so",)))
            with self.assertRaisesRegex(RuntimeError, "unsafe DT_NEEDED"):
                comparison.elf_dynamic_dependencies(artifact)

    def test_adapter_runtime_closure_retains_only_linked_libraries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "main"
            binary.write_bytes(elf64_with_needed(
                ("libcommonmark4cj.commonmark.so", "libcangjie-runtime.so")))
            libraries = root / "commonmark4cj"
            libraries.mkdir()
            for name in ("libcommonmark4cj.so",
                    "libcommonmark4cj.commonmark.so",
                    "libcommonmark4cj.strikethrough.so",
                    "libcommonmark4cj.table.so"):
                path = libraries / name
                path.write_bytes(elf64_with_needed(()))
                path.chmod(0o755)
            closure = comparison.adapter_runtime_library_sources(binary, libraries)
        self.assertEqual(set(closure), {"libcommonmark4cj.commonmark.so"})

    def test_adapter_runtime_closure_rejects_missing_adapter_owned_dso(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "main"
            binary.write_bytes(elf64_with_needed(("libcommonmark4cj.table.so",)))
            libraries = root / "commonmark4cj"
            libraries.mkdir()
            with self.assertRaisesRegex(RuntimeError,
                    "adapter-owned runtime dependency is missing"):
                comparison.adapter_runtime_library_sources(binary, libraries)

    def test_retain_execution_binaries_copies_exact_runtime_closure(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sources = {}
            for name in comparison.BINARY_ARTIFACTS:
                source = root / f"source-{name}"
                source.write_bytes(name.encode("utf-8"))
                source.chmod(0o755)
                sources[name] = source
            library = root / "libcommonmark4cj.commonmark.so"
            library.write_bytes(elf64_with_needed(()))
            library.chmod(0o644)
            binary_root = root / "retained"
            drivers, libraries = comparison.retain_execution_binaries(binary_root,
                sources, {library.name: library})
            retained = binary_root / comparison.RUNTIME_LIBRARY_ROOT / library.name
            self.assertEqual(set(drivers), set(comparison.BINARY_ARTIFACTS))
            self.assertEqual(set(libraries), {library.name})
            self.assertEqual(retained.read_bytes(), library.read_bytes())
            self.assertEqual(libraries[library.name]["mode"], 0o644)

    def test_retain_execution_binaries_rejects_noncanonical_library_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sources = {}
            for name in comparison.BINARY_ARTIFACTS:
                source = root / f"source-{name}"
                source.write_bytes(name.encode("utf-8"))
                sources[name] = source
            library = root / "libcommonmark4cj.commonmark.so"
            library.write_bytes(elf64_with_needed(()))
            library.chmod(0o755)
            with self.assertRaisesRegex(RuntimeError, "mode is not canonical"):
                comparison.retain_execution_binaries(root / "retained", sources,
                    {library.name: library})

    def test_static_comparator_uses_identical_execution_environment(self) -> None:
        report = valid_report()
        processes = report["environment"]["processes"]
        self.assertEqual(processes["markdown"]["variables"],
            processes["markdown4cj"]["variables"])
        self.assertEqual(processes["differences"], {})

    def test_valid_report_rederives_every_gate(self) -> None:
        self.assertEqual(comparison.validate_report(valid_report(), True), [])

    def test_native_runtime_loader_satisfies_only_its_named_dependency(self) -> None:
        assert BINARY_ROOT is not None
        runtime_path = BINARY_ROOT / comparison.NATIVE_RUNTIME_ROOT / "libraries/libc.so.6"
        original = runtime_path.read_bytes()
        try:
            runtime_path.write_bytes(elf64_with_needed(("libmissing.so",)))
            report = valid_report()
            report["nativeToolRuntime"]["libraries"]["libc.so.6"] = \
                comparison.retained_library_identity(runtime_path,
                    (comparison.NATIVE_RUNTIME_ROOT / "libraries/libc.so.6").as_posix())
            errors = comparison.validate_report(report, True)
            self.assertTrue(any("native runtime dependency is missing: libmissing.so" in error
                for error in errors), errors)
        finally:
            runtime_path.write_bytes(original)

    def test_adapter_source_digests_are_rederived_from_pinned_git_blobs(self) -> None:
        for field, forged in (("coreSourceTreeSha256", "0" * 64),
                ("adaptedSourceTreeSha256", "1" * 64)):
            with self.subTest(field=field):
                report = valid_report()
                report["adapterBuild"][field] = forged
                errors = comparison.validate_report(report, True)
                self.assertTrue(any(field in error and "pinned Git objects" in error
                    for error in errors), errors)

    def test_adapter_file_manifests_and_migrations_are_rederived(self) -> None:
        mutations = (
            lambda build: build["coreSourceFiles"].update(
                {next(iter(build["coreSourceFiles"])): "0" * 64}),
            lambda build: build["adaptedSourceFiles"].update(
                {next(iter(build["adaptedSourceFiles"])): "1" * 64}),
            lambda build: build["migrations"][0].update({"count": 999}),
            lambda build: build.update({"manifestSha256": "2" * 64}),
            lambda build: build.update({"driverSha256": "3" * 64}),
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                report = valid_report()
                mutation(report["adapterBuild"])
                errors = comparison.validate_report(report, True)
                self.assertTrue(any("not derived from pinned Git objects" in error or
                    "trimpath manifest is not canonical" in error
                    for error in errors), errors)

    def test_comparator_repository_identity_is_rederived(self) -> None:
        report = valid_report()
        report["sourceRepositories"]["markdown4cj"]["gitTree"] = "0" * 40
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language comparator repository identities are not derived from pinned Git objects",
            errors)

    def test_commonmark_dependency_content_is_bound(self) -> None:
        report = valid_report()
        report["sourceRepositories"]["commonmark4cj"][
            "sourceTreeSha256"] = "0" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language comparator repository identities are not derived from pinned Git objects",
            errors)

    def test_forged_preflight_booleans_cannot_replace_git_objects(self) -> None:
        report = valid_report()
        report["preflight"] = {"markdown4cj": {"headMatches": True, "clean": True},
            "commonmark4cj": {"headMatches": True, "clean": True}}
        report["sourceInputs"] = {"markdown4cj": "/missing/markdown4cj",
            "commonmark4cj": "/missing/commonmark4cj"}
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("Git objects cannot be verified" in error for error in errors),
            errors)

    def test_missing_pinned_commit_object_fails_closed(self) -> None:
        assert IDENTITY_ROOT is not None and COMMONMARK_ROOT is not None
        report = valid_report()
        report["sourceInputs"] = {"markdown4cj": str(IDENTITY_ROOT),
            "commonmark4cj": str(COMMONMARK_ROOT)}
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("Git objects cannot be verified" in error for error in errors),
            errors)

    def test_explicit_git_inputs_are_required(self) -> None:
        report = valid_report()
        del report["sourceInputs"]
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language verification requires explicit local comparator Git inputs",
            errors)

    def test_explicit_git_inputs_override_stale_recorded_locations(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        report = valid_report()
        report["sourceInputs"] = {"markdown4cj": "/old/markdown4cj",
            "commonmark4cj": "/old/commonmark4cj"}
        self.assertEqual(comparison.validate_report(report, True,
            COMPARATOR_ROOT, COMMONMARK_ROOT), [])

    def test_nested_product_worktree_directory_is_rejected(self) -> None:
        assert IDENTITY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None and BINARY_ROOT is not None
        errors = comparison.validate_report(valid_report(), True,
            COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, IDENTITY_ROOT / "src")
        self.assertTrue(any("nested below its worktree root" in error
            for error in errors), errors)

    def test_nested_comparator_worktree_directory_is_rejected(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        errors = comparison.validate_report(valid_report(), True,
            COMPARATOR_ROOT / comparison.COMPARATOR_CORE_PATH,
            COMMONMARK_ROOT)
        self.assertTrue(any("nested below its worktree root" in error
            for error in errors), errors)

    def test_nested_commonmark_worktree_directory_is_rejected(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        errors = comparison.validate_report(valid_report(), True,
            COMPARATOR_ROOT, COMMONMARK_ROOT / "src")
        self.assertTrue(any("nested below its worktree root" in error
            for error in errors), errors)

    def test_external_git_metadata_indirection_is_rejected(self) -> None:
        assert IDENTITY_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            linked = Path(temporary) / "linked"
            test_git(Path(temporary), "clone", "--quiet", "--shared",
                str(IDENTITY_ROOT), str(linked))
            metadata = linked / ".git"
            actual = Path(test_git(linked, "rev-parse", "--absolute-git-dir"))
            moved = Path(temporary) / "external.git"
            metadata.rename(moved)
            metadata.write_text(f"gitdir: {moved}\n", encoding="utf-8")
            self.assertNotEqual(actual.resolve(), moved.resolve())
            with self.assertRaisesRegex(RuntimeError, "unsafe external metadata"):
                with comparison.local_git_repository(linked):
                    pass

    def test_product_replace_ref_cannot_change_pinned_snapshot(self) -> None:
        assert IDENTITY_ROOT is not None
        reference = test_git(IDENTITY_ROOT, "rev-parse", "HEAD")
        expected = comparison.git_repository_snapshot(IDENTITY_ROOT, reference)
        test_git(IDENTITY_ROOT, "replace", reference, ANCESTOR_COMMIT)
        try:
            actual = comparison.git_repository_snapshot(IDENTITY_ROOT, reference)
        finally:
            test_git(IDENTITY_ROOT, "replace", "-d", reference)
        self.assertEqual(actual, expected)

    def test_comparator_replace_ref_cannot_change_pinned_snapshot(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        expected, _, _ = comparison.adapter_source_inputs(COMPARATOR_ROOT,
            COMMONMARK_ROOT)
        forged = COMPARATOR_ROOT / comparison.COMPARATOR_CORE_PATH / "forged.cj"
        forged.write_text("package markdown.core\n", encoding="utf-8")
        test_git(COMPARATOR_ROOT, "add", "-f", "--all")
        test_git(COMPARATOR_ROOT, "commit", "--quiet", "-m", "forged comparator")
        forged_commit = test_git(COMPARATOR_ROOT, "rev-parse", "HEAD")
        test_git(COMPARATOR_ROOT, "replace", comparison.COMPARATOR_COMMIT,
            forged_commit)
        try:
            actual, _, _ = comparison.adapter_source_inputs(COMPARATOR_ROOT,
                COMMONMARK_ROOT)
        finally:
            test_git(COMPARATOR_ROOT, "replace", "-d", comparison.COMPARATOR_COMMIT)
        self.assertEqual(actual, expected)

    def test_commonmark_replace_ref_cannot_change_pinned_snapshot(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        expected, _, _ = comparison.adapter_source_inputs(COMPARATOR_ROOT,
            COMMONMARK_ROOT)
        forged = COMMONMARK_ROOT / "src/forged.cj"
        forged.write_text("package commonmark4cj\n", encoding="utf-8")
        test_git(COMMONMARK_ROOT, "add", "-f", "--all")
        test_git(COMMONMARK_ROOT, "commit", "--quiet", "-m", "forged commonmark")
        forged_commit = test_git(COMMONMARK_ROOT, "rev-parse", "HEAD")
        test_git(COMMONMARK_ROOT, "replace", comparison.COMMONMARK_COMMIT,
            forged_commit)
        try:
            actual, _, _ = comparison.adapter_source_inputs(COMPARATOR_ROOT,
                COMMONMARK_ROOT)
        finally:
            test_git(COMMONMARK_ROOT, "replace", "-d", comparison.COMMONMARK_COMMIT)
        self.assertEqual(actual, expected)

    def test_alternate_object_store_is_rejected(self) -> None:
        assert IDENTITY_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            shared = Path(temporary) / "shared"
            test_git(Path(temporary), "clone", "--quiet", "--shared",
                str(IDENTITY_ROOT), str(shared))
            with self.assertRaisesRegex(RuntimeError, "alternate object interpretation"):
                with comparison.local_git_repository(shared):
                    pass

    def test_git_bundle_is_a_supported_offline_input(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            comparator_bundle = Path(temporary) / "markdown4cj.bundle"
            commonmark_bundle = Path(temporary) / "commonmark4cj.bundle"
            test_git(COMPARATOR_ROOT, "bundle", "create", str(comparator_bundle), "--all")
            test_git(COMMONMARK_ROOT, "bundle", "create", str(commonmark_bundle), "--all")
            report = valid_report()
            report["sourceInputs"] = {"markdown4cj": str(comparator_bundle),
                "commonmark4cj": str(commonmark_bundle)}
            self.assertEqual(comparison.validate_report(report, True), [])

    def test_adapter_identity_is_independent_of_checkout_location(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        expected, _, _ = comparison.adapter_source_inputs(COMPARATOR_ROOT,
            COMMONMARK_ROOT)
        with tempfile.TemporaryDirectory() as temporary:
            comparator = Path(temporary) / "relocated-comparator.git"
            commonmark = Path(temporary) / "relocated-commonmark.git"
            test_git(Path(temporary), "clone", "--quiet", "--bare",
                str(COMPARATOR_ROOT), str(comparator))
            test_git(Path(temporary), "clone", "--quiet", "--bare",
                str(COMMONMARK_ROOT), str(commonmark))
            actual, _, _ = comparison.adapter_source_inputs(comparator, commonmark)
        self.assertEqual(actual, expected)

    def test_binary_is_bound_to_rederived_adapter_inputs(self) -> None:
        report = valid_report()
        report["adapterBuild"]["binarySourceIdentitySha256"] = "0" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language comparator binary is not bound to its source inputs", errors)

    def test_synchronized_product_binary_digest_forgery_is_rejected(self) -> None:
        report = valid_report()
        report["drivers"]["markdown"]["sha256"] = "0" * 64
        report["buildIdentity"]["builds"]["markdownDriver"]["binary"][
            "sha256"] = "0" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language markdown retained binary bytes do not match the report", errors)

    def test_synchronized_comparator_binary_digest_forgery_is_rejected(self) -> None:
        report = valid_report()
        for identity in (report["drivers"]["markdown4cj"],
                report["adapterBuild"]["binary"],
                report["adapterBuild"]["buildOutputBinary"]):
            identity["sha256"] = "0" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language markdown4cj retained binary bytes do not match the report",
            errors)

    def test_synchronized_product_binary_bytes_and_report_cannot_forge_rebuild(self) -> None:
        assert BINARY_ROOT is not None
        report = valid_report()
        with tempfile.TemporaryDirectory() as temporary:
            retained_root = Path(temporary) / "retained"
            rebuilt_root = Path(temporary) / "rebuilt"
            shutil.copytree(BINARY_ROOT, retained_root)
            shutil.copytree(BINARY_ROOT, rebuilt_root)
            forged = retained_root / comparison.BINARY_ARTIFACTS["markdown"]
            forged.write_bytes(b"synchronized forged product executable")
            identity = comparison.retained_binary_identity(forged,
                comparison.BINARY_ARTIFACTS["markdown"])
            report["drivers"]["markdown"] = copy.deepcopy(identity)
            report["buildIdentity"]["builds"]["markdownDriver"]["binary"] = {
                "path": "/workspace/markdown/benchmarks/driver/main",
                "bytes": identity["bytes"], "sha256": identity["sha256"]}
            rebuilt = {name: rebuilt_root / artifact
                for name, artifact in comparison.BINARY_ARTIFACTS.items()}
            runtime = {path.name: path for path in
                (rebuilt_root / comparison.RUNTIME_LIBRARY_ROOT).glob("*.so")}
            errors = comparison.validate_rebuilt_binaries(report, retained_root,
                rebuilt, runtime)
        self.assertIn(
            "same-language markdown retained binary is not reproducible from attested inputs",
            errors)

    def test_synchronized_comparator_binary_bytes_and_report_cannot_forge_rebuild(self) -> None:
        assert BINARY_ROOT is not None
        report = valid_report()
        with tempfile.TemporaryDirectory() as temporary:
            retained_root = Path(temporary) / "retained"
            rebuilt_root = Path(temporary) / "rebuilt"
            shutil.copytree(BINARY_ROOT, retained_root)
            shutil.copytree(BINARY_ROOT, rebuilt_root)
            forged = retained_root / comparison.BINARY_ARTIFACTS["markdown4cj"]
            forged.write_bytes(elf64_with_needed(
                ("libcommonmark4cj.commonmark.so",)) + b"forged")
            identity = comparison.retained_binary_identity(forged,
                comparison.BINARY_ARTIFACTS["markdown4cj"])
            report["drivers"]["markdown4cj"] = copy.deepcopy(identity)
            report["adapterBuild"]["binary"] = copy.deepcopy(identity)
            report["adapterBuild"]["buildOutputBinary"].update({
                "bytes": identity["bytes"], "sha256": identity["sha256"]})
            rebuilt = {name: rebuilt_root / artifact
                for name, artifact in comparison.BINARY_ARTIFACTS.items()}
            runtime = {path.name: path for path in
                (rebuilt_root / comparison.RUNTIME_LIBRARY_ROOT).glob("*.so")}
            errors = comparison.validate_rebuilt_binaries(report, retained_root,
                rebuilt, runtime)
        self.assertIn(
            "same-language markdown4cj retained binary is not reproducible from attested inputs",
            errors)

    def test_swapped_retained_binary_identities_are_rejected(self) -> None:
        report = valid_report()
        report["drivers"]["markdown"], report["drivers"]["markdownCli"] = \
            report["drivers"]["markdownCli"], report["drivers"]["markdown"]
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("retained binary path is not canonical" in error
            for error in errors), errors)

    def test_missing_retained_binary_fails_closed(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "binaries"
            shutil.copytree(BINARY_ROOT, root)
            (root / comparison.BINARY_ARTIFACTS["markdownCli"]).unlink()
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertTrue(any("retained binaries are missing" in error for error in errors),
            errors)

    def test_extra_retained_binary_fails_closed(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "binaries"
            shutil.copytree(BINARY_ROOT, root)
            (root / "unattested-helper").write_bytes(b"extra")
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertTrue(any("unexpected entries" in error for error in errors), errors)

    def test_retained_binary_path_escape_is_rejected(self) -> None:
        report = valid_report()
        report["drivers"]["markdown"]["artifactPath"] = "../markdown-driver"
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language markdown retained binary path is not canonical", errors)

    def test_tampered_retained_binary_fails_closed(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "binaries"
            shutil.copytree(BINARY_ROOT, root)
            (root / comparison.BINARY_ARTIFACTS["markdown"]).write_bytes(b"tampered")
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertIn(
            "same-language markdown retained binary bytes do not match the report", errors)

    def test_static_adapter_rejects_declared_runtime_library(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        report = valid_report()
        report["runtimeLibraries"] = {
            "libcommonmark4cj.commonmark.so": {
                "artifactPath": "libraries/commonmark4cj/libcommonmark4cj.commonmark.so",
                "bytes": 128, "sha256": "0" * 64, "mode": 0o644}}
        report["adapterBuild"]["runtimeLibraries"] = copy.deepcopy(
            report["runtimeLibraries"])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "binaries"
            shutil.copytree(BINARY_ROOT, root)
            errors = comparison.validate_report(report, True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertTrue(any("runtime library" in error for error in errors), errors)

    def test_retained_bundle_can_be_relocated_for_offline_verification(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "relocated-binaries"
            shutil.copytree(BINARY_ROOT, root)
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertEqual(errors, [])

    def test_retained_binary_root_with_symlinked_parent_fails_closed(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            real_parent = root / "real"
            real_parent.mkdir()
            shutil.copytree(BINARY_ROOT, real_parent / "binaries")
            linked_parent = root / "linked"
            linked_parent.symlink_to(real_parent, target_is_directory=True)
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, linked_parent / "binaries")
        self.assertTrue(any("root is unavailable or unsafe" in error
            for error in errors), errors)

    def test_extra_retained_runtime_library_fails_closed(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "binaries"
            shutil.copytree(BINARY_ROOT, root)
            extra = root / comparison.RUNTIME_LIBRARY_ROOT / "libunexpected.so"
            extra.parent.mkdir(parents=True)
            extra.write_bytes(elf64_with_needed(()))
            extra.chmod(0o755)
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertTrue(any("unexpected entries" in error for error in errors), errors)

    def test_static_adapter_runtime_library_path_escape_is_rejected(self) -> None:
        report = valid_report()
        report["runtimeLibraries"] = {"libcommonmark4cj.commonmark.so": {
            "artifactPath": "../libcommonmark4cj.commonmark.so", "bytes": 128,
            "sha256": "0" * 64, "mode": 0o644}}
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("runtime library identity is not canonical" in error
            for error in errors), errors)

    def test_static_adapter_rejects_unexpected_runtime_symlink(self) -> None:
        assert BINARY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "binaries"
            shutil.copytree(BINARY_ROOT, root)
            library = root / comparison.RUNTIME_LIBRARY_ROOT / \
                "libcommonmark4cj.commonmark.so"
            library.parent.mkdir(parents=True)
            replacement = root / "outside.so"
            replacement.write_bytes(elf64_with_needed(()))
            library.symlink_to(replacement)
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, root)
        self.assertTrue(any("contains a symlink" in error for error in errors), errors)

    def test_adapter_build_exports_pinned_objects_not_dirty_worktree_files(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            comparator = root / "markdown4cj"
            commonmark = root / "commonmark4cj"
            test_git(root, "clone", "--quiet", str(COMPARATOR_ROOT), str(comparator))
            test_git(root, "clone", "--quiet", str(COMMONMARK_ROOT), str(commonmark))
            dirty = comparator / comparison.COMPARATOR_CORE_PATH / "core_plugin.cj"
            dirty.write_text("uncommitted attacker-controlled source\n", encoding="utf-8")
            workspace = root / "adapter"

            def fake_build(command: list[str], cwd: Path,
                    environment: dict[str, str] | None = None) -> dict[str, object]:
                output = cwd / "target/release/bin/main"
                output.parent.mkdir(parents=True)
                output.write_bytes(elf64_with_needed(
                    ("libcommonmark4cj.commonmark.so",)))
                output.chmod(0o755)
                library = cwd / "target/release/commonmark4cj" / \
                    "libcommonmark4cj.commonmark.so"
                library.parent.mkdir(parents=True)
                library.write_bytes(elf64_with_needed(()))
                library.chmod(0o755)
                return {"command": command, "cwd": str(cwd), "exitCode": 0,
                    "stdout": "build succeeded\n", "stderr": "",
                    "environment": environment}

            with patch.object(comparison, "command", side_effect=fake_build):
                _, build = comparison.build_adapter(comparator, commonmark, workspace,
                    Path("/fresh/cangjie/tools/bin/cjpm"), sdk_command_environment())
            self.assertEqual(build["buildOutputRuntimeLibraries"][
                "libcommonmark4cj.commonmark.so"]["mode"], 0o644)
            provenance, adapted, commonmark_contents = comparison.adapter_source_inputs(
                comparator, commonmark)
            self.assertEqual((workspace / "src/core/core_plugin.cj").read_bytes(),
                adapted["core_plugin.cj"])
            self.assertNotEqual(dirty.read_bytes(), adapted["core_plugin.cj"])
            self.assertEqual((workspace / "deps/commonmark4cj/cjpm.toml").read_bytes(),
                comparison.adapter_dependency_manifest(commonmark_contents["cjpm.toml"],
                    str(workspace.resolve())))
            self.assertEqual(build["adapterInputSha256"],
                provenance["adapterInputSha256"])

    def test_declared_commit_product_identity_matches_clean_workspace_algorithm(self) -> None:
        snapshot = comparison.git_repository_snapshot(comparison.ROOT, "HEAD")
        self.assertEqual(snapshot["productTreeSha256"],
            benchmark_product_tree_sha256(comparison.ROOT))
        self.assertEqual(snapshot["productFiles"],
            benchmark_product_file_sha256s(comparison.ROOT))

    def test_repository_identity_records_an_immutable_commit(self) -> None:
        identity = comparison.repository_identity()
        self.assertEqual(identity["repositoryRef"], identity["repositoryCommit"])

    def test_evidence_only_commit_preserves_current_product_verification(self) -> None:
        assert IDENTITY_ROOT is not None
        report = valid_report()
        with tempfile.TemporaryDirectory() as temporary:
            product = Path(temporary) / "product"
            test_git(Path(temporary), "clone", "--quiet", str(IDENTITY_ROOT), str(product))
            test_git(product, "config", "user.name", "Benchmark Identity Test")
            test_git(product, "config", "user.email", "benchmark@example.test")
            test_git(product, "config", "core.hooksPath", os.devnull)
            (product / "evidence.md").write_text('Measured evidence.\n')
            test_git(product, "add", "evidence.md")
            test_git(product, "commit", "--quiet", "-m", "docs: retain measured evidence")
            errors = comparison.validate_report(report, True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, product)
        self.assertEqual(errors, [])

    def test_movable_repository_ref_is_rejected(self) -> None:
        report = valid_report()
        report["identity"]["repositoryRef"] = "HEAD"
        self.assertIn("same-language repository ref must be an immutable canonical object ID",
            comparison.validate_report(report, True))

    def test_harness_change_invalidates_measured_product(self) -> None:
        assert IDENTITY_ROOT is not None
        report = valid_report()
        with tempfile.TemporaryDirectory() as temporary:
            product = Path(temporary) / "product"
            test_git(Path(temporary), "clone", "--quiet", str(IDENTITY_ROOT), str(product))
            test_git(product, "config", "user.name", "Benchmark Identity Test")
            test_git(product, "config", "user.email", "benchmark@example.test")
            test_git(product, "config", "core.hooksPath", os.devnull)
            harness = product / comparison.HARNESS_FILES[0]
            harness.write_bytes(harness.read_bytes() + b"\n# Changed harness.\n")
            test_git(product, "add", comparison.HARNESS_FILES[0])
            test_git(product, "commit", "--quiet", "-m", "test: change harness")
            errors = comparison.validate_report(report, True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, product)
        self.assertIn(
            "same-language declared Git source is not the retained product source HEAD", errors)

    def test_empty_repository_ref_is_rejected(self) -> None:
        report = valid_report()
        report["identity"]["repositoryRef"] = ""
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("ref must be a non-empty" in error for error in errors))

    def test_noncanonical_commit_and_tree_object_ids_are_rejected(self) -> None:
        for field, label in (("repositoryCommit", "commit"), ("gitTree", "tree")):
            with self.subTest(field=field):
                report = valid_report()
                report["identity"][field] = "A" * 40
                errors = comparison.validate_report(report, True)
                self.assertTrue(any(
                    f"repository {label} is not a canonical object ID" in error
                    for error in errors))

    def test_repository_ref_must_resolve_to_the_declared_commit(self) -> None:
        report = valid_report()
        report["identity"]["repositoryRef"] = ANCESTOR_COMMIT
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language repository commit is not derived from its ref", errors)

    def test_git_tree_is_derived_from_the_declared_commit(self) -> None:
        report = valid_report()
        ancestor = comparison.git_repository_snapshot(
            comparison.ROOT, ANCESTOR_COMMIT)
        report["identity"]["gitTree"] = ancestor["gitTree"]
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language repository tree is not derived from its ref", errors)

    def test_nonexistent_declared_commit_fails_closed(self) -> None:
        report = valid_report()
        report["identity"]["repositoryRef"] = "f" * 40
        errors = comparison.validate_report(report, True)
        self.assertTrue(any(
            "declared Git source cannot be verified" in error for error in errors))

    def test_reachable_ancestor_cannot_claim_current_product_blobs(self) -> None:
        report = valid_report()
        ancestor = comparison.git_repository_snapshot(
            comparison.ROOT, ANCESTOR_COMMIT)
        identity = report["identity"]
        identity.update({"repositoryRef": ANCESTOR_COMMIT,
            "repositoryCommit": ancestor["repositoryCommit"],
            "gitTree": ancestor["gitTree"]})
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language report product tree does not match the declared Git commit",
            errors)
        self.assertIn(
            "same-language build input file identity does not match the declared Git source",
            errors)

    def test_self_consistent_ancestor_is_not_the_current_release_subject(self) -> None:
        report = valid_report()
        ancestor = comparison.git_repository_snapshot(
            comparison.ROOT, ANCESTOR_COMMIT)
        bind_report_to_snapshot(report, ANCESTOR_COMMIT, ancestor)
        self.assertEqual(comparison.validate_report(report, False), [])
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language declared Git source is not the retained product source HEAD",
            errors)

    def test_retained_product_bundle_supports_relocated_offline_verification(self) -> None:
        assert IDENTITY_ROOT is not None and COMPARATOR_ROOT is not None
        assert COMMONMARK_ROOT is not None and BINARY_ROOT is not None
        report = valid_report()
        with tempfile.TemporaryDirectory() as temporary:
            retained = Path(temporary) / "relocated"
            retained.mkdir()
            product = retained / "markdown.bundle"
            comparator = retained / "markdown4cj.bundle"
            commonmark = retained / "commonmark4cj.bundle"
            binaries = retained / "binaries"
            test_git(IDENTITY_ROOT, "bundle", "create", str(product), "HEAD")
            test_git(COMPARATOR_ROOT, "bundle", "create", str(comparator), "--all")
            test_git(COMMONMARK_ROOT, "bundle", "create", str(commonmark), "--all")
            shutil.copytree(BINARY_ROOT, binaries)
            no_git_root = retained / "verifier-without-git"
            no_git_root.mkdir()
            with patch.object(comparison, "ROOT", no_git_root):
                errors = comparison.validate_report(report, True,
                    comparator, commonmark, binaries, product)
        self.assertEqual(errors, [])

    def test_missing_retained_product_bundle_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "missing.bundle"
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, missing)
        self.assertTrue(any("declared Git source cannot be verified" in error
            for error in errors), errors)

    def test_retained_product_bundle_with_wrong_commit_fails_closed(self) -> None:
        assert IDENTITY_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            product = Path(temporary) / "ancestor.bundle"
            reference = "refs/heads/benchmark-ancestor-test"
            test_git(IDENTITY_ROOT, "update-ref", reference, ANCESTOR_COMMIT)
            try:
                test_git(IDENTITY_ROOT, "bundle", "create", str(product), reference)
                errors = comparison.validate_report(valid_report(), True,
                    COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, product)
            finally:
                test_git(IDENTITY_ROOT, "update-ref", "-d", reference)
        self.assertTrue(any("declared Git source cannot be verified" in error
            for error in errors), errors)

    def test_tampered_retained_product_bundle_fails_closed(self) -> None:
        assert IDENTITY_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            product = Path(temporary) / "markdown.bundle"
            test_git(IDENTITY_ROOT, "bundle", "create", str(product), "HEAD")
            content = bytearray(product.read_bytes())
            content[len(content) // 2] ^= 1
            product.write_bytes(content)
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, product)
        self.assertTrue(any("declared Git source cannot be verified" in error
            for error in errors), errors)

    def test_tampered_product_blob_in_checkout_fails_closed(self) -> None:
        assert IDENTITY_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            product = Path(temporary) / "product"
            test_git(Path(temporary), "clone", "--quiet", str(IDENTITY_ROOT),
                str(product))
            source = product / "native/markdown_scanner.c"
            source.write_bytes(source.read_bytes() + b"\n/* tampered */\n")
            errors = comparison.validate_report(valid_report(), True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, product)
        self.assertIn(
            "same-language declared Git source is not the retained product source HEAD",
            errors)

    def test_reachable_ancestor_cannot_masquerade_with_current_product_bundle(self) -> None:
        assert IDENTITY_ROOT is not None
        report = valid_report()
        ancestor = comparison.git_repository_snapshot(IDENTITY_ROOT, ANCESTOR_COMMIT)
        bind_report_to_snapshot(report, ANCESTOR_COMMIT, ancestor)
        with tempfile.TemporaryDirectory() as temporary:
            product = Path(temporary) / "markdown.bundle"
            test_git(IDENTITY_ROOT, "bundle", "create", str(product), "--all")
            errors = comparison.validate_report(report, True,
                COMPARATOR_ROOT, COMMONMARK_ROOT, BINARY_ROOT, product)
        self.assertIn(
            "same-language declared Git source is not the retained product source HEAD",
            errors)

    def test_non_git_verification_environment_fails_closed(self) -> None:
        report = valid_report()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "not-a-repository"
            root.mkdir()
            with patch.object(comparison, "ROOT", root):
                errors = comparison.validate_report(report, True)
        self.assertTrue(any(
            "declared Git source cannot be verified" in error for error in errors))

    def test_ambient_git_dir_cannot_redirect_identity_resolution(self) -> None:
        expected = valid_report()["identity"]
        assert IDENTITY_ROOT is not None
        with patch.dict(os.environ, {"GIT_DIR": str(IDENTITY_ROOT / ".git"),
                "GIT_WORK_TREE": str(ORIGINAL_ROOT)}):
            actual = comparison.repository_identity()
        for field in ("repositoryCommit", "gitTree", "productTreeSha256",
                "harnessFiles"):
            self.assertEqual(actual[field], expected[field])

    def test_git_object_format_is_derived(self) -> None:
        report = valid_report()
        report["identity"]["gitObjectFormat"] = "sha256"
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language Git object format is not derived", errors)

    def test_old_schema_requires_a_fresh_canonical_run(self) -> None:
        report = valid_report()
        report["schemaVersion"] = 4
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("rerun the canonical benchmark" in error for error in errors))

    def test_forged_speedup_is_rejected(self) -> None:
        report = valid_report()
        first = next(iter(report["corpora"].values()))
        first["markdownSpeedup"] = 20.0
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("speedup is not derived" in error for error in errors))

    def test_timed_corpus_semantic_mismatch_cannot_be_marked_equal(self) -> None:
        report = valid_report()
        first = next(iter(report["corpusSemantics"].values()))
        first["specHtml"]["markdown4cj"]["sha256"] = "f" * 64
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("semantic equality is not derived" in error for error in errors))
        self.assertTrue(any("exact spec HTML differs" in error for error in errors))
        self.assertTrue(any("promotion result is not derived" in error for error in errors))

    def test_missing_timed_corpus_semantics_is_rejected(self) -> None:
        report = valid_report()
        report["corpusSemantics"].pop(next(iter(report["corpusSemantics"])))
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language timed corpus semantic records are incomplete", errors)

    def test_shared_behavior_aggregate_cannot_hide_case_mismatch(self) -> None:
        report = valid_report()
        first = next(iter(report["sharedBehavior"]["cases"].values()))
        first["specHtml"]["markdown4cj"]["bytes"] += 1
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("shared behavior" in error and "differs" in error for error in errors))
        self.assertIn("same-language shared behavior gate did not pass", errors)

    def test_output_newline_is_part_of_semantic_identity(self) -> None:
        left = {"stdoutBytes": 2, "stdoutSha256": digest(b"x\n")}
        right = {"stdoutBytes": 1, "stdoutSha256": digest(b"x")}
        record = comparison.parity_record(left, right)
        self.assertFalse(record["equalSpecHtml"])

    def test_forged_timed_output_digest_is_rejected(self) -> None:
        report = valid_report()
        first = next(iter(report["corpora"].values()))
        first["markdown"][0]["stdoutSha256"] = "0" * 64
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("output digest is not derived" in error for error in errors))

    def test_non_finite_sample_is_rejected(self) -> None:
        report = valid_report()
        first = next(iter(report["corpora"].values()))
        first["markdown4cj"][0]["seconds"] = float("inf")
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("samples contain invalid values" in error for error in errors))

    def test_sdk_attestation_is_required(self) -> None:
        report = valid_report()
        del report["buildIdentity"]["sdk"]["archiveUrl"]
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language build identity SDK attestation is not canonical", errors)

    def test_path_cjpm_build_cannot_claim_the_pinned_sdk(self) -> None:
        report = valid_report()
        report["buildIdentity"]["builds"]["markdownDriver"]["build"]["command"] = [
            "cjpm", "build"]
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language markdownDriver build command is not canonical", errors)

    def test_comparator_must_use_the_same_attested_cjpm(self) -> None:
        report = valid_report()
        report["adapterBuild"]["command"] = ["/daily/tools/bin/cjpm", "build", "-V"]
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language comparator adapter build command is not canonical", errors)

    def test_tool_binary_digest_is_required(self) -> None:
        report = valid_report()
        del report["buildIdentity"]["tools"]["cjpm"]["sha256"]
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language cjpm tool binary digest is invalid", errors)

    def test_changed_extracted_tool_is_rejected_before_comparator_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "cangjie"
            cjc = root / "bin" / "cjc"
            cjpm = root / "tools" / "bin" / "cjpm"
            envsetup = root / "envsetup.sh"
            cjc.parent.mkdir(parents=True)
            cjpm.parent.mkdir(parents=True)
            cjc.write_bytes(b"cjc")
            cjpm.write_bytes(b"cjpm")
            envsetup.write_bytes(b"envsetup")
            cjc.chmod(0o755)
            cjpm.chmod(0o755)
            identity = valid_report()["buildIdentity"]
            archive = Path(temporary) / "sdk.tar.gz"
            archive.write_bytes(b"archive")
            identity["sdk"].update({"archivePath": str(archive),
                "archiveBytes": archive.stat().st_size,
                "archiveSha256": digest(archive.read_bytes()),
                "envsetupSha256": digest(envsetup.read_bytes())})
            identity["sdk"]["root"] = str(root)
            identity["sdk"]["environment"] = comparison.build_environment_attestation(
                sdk_command_environment(str(root)))
            for name, path in (("cjc", cjc), ("cjpm", cjpm)):
                identity["tools"][name].update({"path": str(path),
                    "bytes": path.stat().st_size,
                    "sha256": digest(path.read_bytes())})
            cjpm.write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "cjpm changed"):
                comparison.attested_sdk_environment(identity)

    def test_attested_sdk_child_environment_ignores_ambient_pollution(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "cangjie"
            cjc = root / "bin/cjc"
            cjpm = root / "tools/bin/cjpm"
            envsetup = root / "envsetup.sh"
            cjc.parent.mkdir(parents=True)
            cjpm.parent.mkdir(parents=True)
            cjc.write_bytes(b"cjc")
            cjpm.write_bytes(b"cjpm")
            envsetup.write_bytes(b"envsetup")
            cjc.chmod(0o755)
            cjpm.chmod(0o755)
            environment = sdk_command_environment(str(root))
            Path(environment["HOME"]).mkdir()
            Path(environment["TMPDIR"]).mkdir()
            archive = Path(temporary) / "sdk.tar.gz"
            archive.write_bytes(b"archive")
            identity = valid_report()["buildIdentity"]
            identity["sdk"].update({"archivePath": str(archive),
                "archiveBytes": archive.stat().st_size,
                "archiveSha256": digest(archive.read_bytes()),
                "root": str(root), "envsetupSha256": digest(envsetup.read_bytes()),
                "environment": comparison.build_environment_attestation(environment)})
            for name, path in (("cjc", cjc), ("cjpm", cjpm)):
                identity["tools"][name].update({"path": str(path),
                    "bytes": path.stat().st_size, "sha256": digest(path.read_bytes())})
            pollution = {"LD_PRELOAD": "/host/instrumentation.so",
                "LIBRARY_PATH": "/host/linker", "cjHeapSize": "64MB",
                "cjGCInterval": "1ms", "LC_ALL": "tr_TR.UTF-8"}
            with patch.dict(os.environ, pollution):
                _, observed = comparison.attested_sdk_environment(identity)
            self.assertEqual(observed, environment)
            self.assertFalse({"LD_PRELOAD", "LIBRARY_PATH", "cjHeapSize",
                "cjGCInterval"} & set(observed))
            self.assertEqual(observed["LC_ALL"], comparison.CANONICAL_LOCALE)

    def test_build_input_identity_is_fail_closed(self) -> None:
        report = valid_report()
        files = report["buildIdentity"]["sourceIdentity"]["files"]
        files.pop(next(iter(files)))
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language build input file identity does not match the declared Git source",
            errors)

    def test_build_environment_cannot_add_an_unattested_variable(self) -> None:
        report = valid_report()
        attestation = report["buildIdentity"]["sdk"]["environment"]
        attestation["variables"]["LD_PRELOAD"] = "/tmp/instrumentation.so"
        attestation["allowlist"].append("LD_PRELOAD")
        attestation["allowlist"].sort()
        attestation["sha256"] = comparison.canonical_json_sha256(
            attestation["variables"])
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language build identity SDK environment is not canonical", errors)

    def test_execution_environment_heap_gc_and_locale_are_derived(self) -> None:
        for name, value in (("cjHeapSize", "64MB"), ("cjGCInterval", "1ms"),
                ("LC_ALL", "tr_TR.UTF-8")):
            with self.subTest(name=name):
                report = valid_report()
                record = report["environment"]["processes"]["markdown"]
                record["variables"][name] = value
                record["sha256"] = comparison.canonical_json_sha256(record["variables"])
                errors = comparison.validate_report(report, True)
                self.assertIn(
                    "same-language process environments are not canonical or derived", errors)

    def test_static_comparator_loader_difference_is_rejected(self) -> None:
        report = valid_report()
        processes = report["environment"]["processes"]
        processes["differences"]["LD_LIBRARY_PATH"] = {
            "markdown": "/sdk/runtime", "markdown4cj": "/forged/runtime"}
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language process environments are not canonical or derived", errors)

    def test_measurement_rejects_ambient_performance_controls(self) -> None:
        for name in ("LD_PRELOAD", "LD_LIBRARY_PATH", "LIBRARY_PATH",
                "MARKDOWN_NATIVE_CFLAGS", "TARGET", "cjHeapSize", "cjGCInterval"):
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, name):
                comparison.reject_ambient_benchmark_environment({name: "polluted"})

    def test_native_object_digest_must_match_the_cache_manifest(self) -> None:
        report = valid_report()
        report["buildIdentity"]["nativeScanner"]["object"]["sha256"] = "6" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language native scanner object is not bound to its manifest", errors)

    def test_native_archive_digest_must_match_the_cache_manifest(self) -> None:
        report = valid_report()
        native = report["buildIdentity"]["nativeScanner"]
        native["cacheManifest"]["archive"]["sha256"] = "6" * 64
        native["cacheManifestSha256"] = comparison.canonical_json_sha256(
            native["cacheManifest"])
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language native scanner archive is not bound to its manifest", errors)

    def test_native_manifest_digest_must_cover_output_identities(self) -> None:
        report = valid_report()
        report["buildIdentity"]["nativeScanner"]["cacheManifest"]["object"][
            "sha256"] = "6" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language native scanner manifest digest is not derived", errors)

    def test_native_manifest_rejects_an_unknown_child_environment_variable(self) -> None:
        report = valid_report()
        native = report["buildIdentity"]["nativeScanner"]
        environment = native["cacheManifest"]["buildEnvironment"]
        environment["variables"]["MARKDOWN_RANDOM_UNKNOWN"] = \
            "/tmp/instrumentation.so"
        environment["sha256"] = comparison.canonical_json_sha256(
            environment["variables"])
        native["buildEnvironment"] = copy.deepcopy(environment)
        native["cacheManifestSha256"] = comparison.canonical_json_sha256(
            native["cacheManifest"])
        errors = comparison.validate_report(report, True)
        self.assertIn(
            "same-language native scanner child environment digest is invalid", errors)

    def test_native_tool_binary_digest_and_version_command_are_required(self) -> None:
        for mutation, expected in (
                (lambda tool: tool.pop("sha256"), "compiler binary digest is invalid"),
                (lambda tool: tool["version"].update(
                    {"command": ["/tmp/wrapper", "--version"]}),
                    "compiler version command is not bound")):
            with self.subTest(expected=expected):
                report = valid_report()
                native = report["buildIdentity"]["nativeScanner"]
                mutation(native["cacheManifest"]["compiler"])
                mutation(native["compiler"])
                native["cacheManifestSha256"] = comparison.canonical_json_sha256(
                    native["cacheManifest"])
                errors = comparison.validate_report(report, True)
                self.assertTrue(any(expected in error for error in errors), errors)

    def test_driver_digest_must_match_build_output(self) -> None:
        report = valid_report()
        report["drivers"]["markdown"]["sha256"] = "9" * 64
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language markdown digest is not bound to its build", errors)

    def test_weakened_threshold_is_rejected(self) -> None:
        report = valid_report()
        report["thresholds"]["minimumGeomeanSpeedup"] = 0.1
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language report thresholds differ from the enforced profile", errors)

    def test_shortened_protocol_is_rejected(self) -> None:
        report = valid_report()
        report["protocol"]["samplesPerSide"] = 1
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language report protocol differs from the enforced profile", errors)

    def test_unstable_driver_output_is_rejected(self) -> None:
        report = valid_report()
        first = next(iter(report["corpora"].values()))
        first["markdown"][0]["stdout"] = "2\n"
        first["markdown"][0]["stdoutSha256"] = digest(b"2\n")
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("output is unstable" in error for error in errors))

    def test_report_renderer_uses_raw_values(self) -> None:
        rendered = comparison.render_markdown(valid_report())
        self.assertIn("**2.00×**", rendered)
        self.assertIn("12/12", rendered)
        self.assertIn("Same-language benchmark (sts-1.2.0)", rendered)
        self.assertIn("语义检查在计时区间外执行", rendered)

    def test_default_cpu_uses_affinity_set(self) -> None:
        with patch.object(comparison.os, "sched_getaffinity", return_value={7, 9}):
            self.assertEqual(comparison.resolve_cpu(None), 7)
            self.assertEqual(comparison.resolve_cpu(9), 9)
            with self.assertRaises(ValueError):
                comparison.resolve_cpu(2)

    def test_noncanonical_iterations_fail_before_setup(self) -> None:
        args = SimpleNamespace(verify_report=None, output=Path("unused.json"),
            workspace=Path("unused-workspace"), binary_root=Path("unused-binaries"),
            iterations=comparison.ITERATIONS + 1)
        with patch.object(comparison, "arguments", return_value=args), \
                patch.object(comparison, "resolve_sources") as resolve_sources, \
                patch("sys.stderr", new_callable=StringIO) as stderr:
            self.assertEqual(comparison.main(), 2)
        resolve_sources.assert_not_called()
        self.assertIn("fixed at", stderr.getvalue())

    def test_verify_mode_requires_explicit_offline_git_inputs(self) -> None:
        args = SimpleNamespace(verify_report=Path("unused.json"), tools_root=None,
            source=None, commonmark4cj_source=None, markdown_report=None,
            require_current_product=True)
        with patch.object(comparison, "arguments", return_value=args), \
                patch("sys.stderr", new_callable=StringIO) as stderr:
            self.assertEqual(comparison.main(), 2)
        self.assertIn("requires --tools-root or both explicit comparator Git inputs",
            stderr.getvalue())

    def test_verify_mode_requires_explicit_retained_binary_root(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        args = SimpleNamespace(verify_report=Path("unused.json"), tools_root=None,
            source=COMPARATOR_ROOT, commonmark4cj_source=COMMONMARK_ROOT,
            binary_root=None, markdown_report=None, require_current_product=True)
        with patch.object(comparison, "arguments", return_value=args), \
                patch("sys.stderr", new_callable=StringIO) as stderr:
            self.assertEqual(comparison.main(), 2)
        self.assertIn("requires --binary-root", stderr.getvalue())

    def test_verify_mode_requires_explicit_retained_product_source(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        assert BINARY_ROOT is not None
        args = SimpleNamespace(verify_report=Path("unused.json"), tools_root=None,
            source=COMPARATOR_ROOT, commonmark4cj_source=COMMONMARK_ROOT,
            binary_root=BINARY_ROOT, product_source=None, markdown_report=None,
            require_current_product=True)
        with patch.object(comparison, "arguments", return_value=args), \
                patch("sys.stderr", new_callable=StringIO) as stderr:
            self.assertEqual(comparison.main(), 2)
        self.assertIn("requires --product-source", stderr.getvalue())

    def test_required_workflow_retains_and_offline_verifies_product_source(self) -> None:
        workflow = (ORIGINAL_ROOT / ".github/workflows/candidate-validation.yml").read_text(
            encoding="utf-8")
        self.assertIn("product-source/markdown.bundle HEAD", workflow)
        self.assertEqual(workflow.count(
            "--product-source target/same-language-benchmark/product-source/markdown.bundle"),
            2)
        self.assertIn("git archive HEAD | tar -x", workflow)
        self.assertIn('"${offline_root}/benchmarks/compare_markdown4cj.py"', workflow)
        self.assertIn(
            '"${RUNNER_TEMP}/markdown-same-language-offline/benchmarks/compare_markdown4cj.py"',
            workflow)
        self.assertIn("toolchain/cangjie-sdk-linux-x64-1.2.0.tar.gz", workflow)
        self.assertEqual(workflow.count(
            "--sdk-archive target/same-language-benchmark/toolchain/cangjie-sdk-linux-x64-1.2.0.tar.gz"),
            2)

    def test_verify_mode_requires_retained_sdk_archive(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        assert BINARY_ROOT is not None and IDENTITY_ROOT is not None
        args = SimpleNamespace(verify_report=Path("unused.json"), tools_root=None,
            source=COMPARATOR_ROOT, commonmark4cj_source=COMMONMARK_ROOT,
            binary_root=BINARY_ROOT, product_source=IDENTITY_ROOT,
            sdk_archive=None, markdown_report=None, require_current_product=True)
        with patch.object(comparison, "arguments", return_value=args), \
                patch("sys.stderr", new_callable=StringIO) as stderr:
            self.assertEqual(comparison.main(), 2)
        self.assertIn("requires --sdk-archive", stderr.getvalue())

    def test_verify_mode_rebuilds_before_accepting_report(self) -> None:
        assert COMPARATOR_ROOT is not None and COMMONMARK_ROOT is not None
        assert BINARY_ROOT is not None and IDENTITY_ROOT is not None
        with tempfile.TemporaryDirectory() as temporary:
            raw = Path(temporary) / "raw.json"
            raw.write_text("{}\n", encoding="utf-8")
            archive = Path(temporary) / "sdk.tar.gz"
            archive.write_bytes(b"sdk")
            args = SimpleNamespace(verify_report=raw, tools_root=None,
                source=COMPARATOR_ROOT, commonmark4cj_source=COMMONMARK_ROOT,
                binary_root=BINARY_ROOT, product_source=IDENTITY_ROOT,
                sdk_archive=archive, markdown_report=None,
                require_current_product=True)
            with patch.object(comparison, "arguments", return_value=args), \
                    patch.object(comparison, "validate_report", return_value=[]), \
                    patch.object(comparison, "verify_reproducible_binaries",
                        return_value=[]) as rebuild, \
                    patch("sys.stdout", new_callable=StringIO):
                self.assertEqual(comparison.main(), 0)
            rebuild.assert_called_once_with({}, BINARY_ROOT, IDENTITY_ROOT,
                COMPARATOR_ROOT, COMMONMARK_ROOT, archive)

    def test_measurement_main_rejects_ambient_pollution_before_setup(self) -> None:
        args = SimpleNamespace(verify_report=None, output=Path("unused.json"),
            workspace=Path("unused-workspace"), binary_root=Path("unused-binaries"),
            iterations=comparison.ITERATIONS)
        with patch.object(comparison, "arguments", return_value=args), \
                patch.object(comparison, "resolve_sources") as resolve_sources, \
                patch.dict(os.environ, {"LD_PRELOAD": "/tmp/instrumentation.so"},
                    clear=True), \
                patch("sys.stderr", new_callable=StringIO) as stderr:
            self.assertEqual(comparison.main(), 2)
        resolve_sources.assert_not_called()
        self.assertIn("LD_PRELOAD", stderr.getvalue())

    def test_run_drains_large_stdout_and_stderr_without_deadlock(self) -> None:
        stdout = ("stdout-文\n" * 32768).encode("utf-8")
        stderr = ("stderr-文\n" * 32768).encode("utf-8")
        script = ("import os\n"
            "for _ in range(32768): os.write(1, 'stdout-文\\n'.encode())\n"
            "for _ in range(32768): os.write(2, 'stderr-文\\n'.encode())\n")
        result = comparison.run([sys.executable, "-c", script], b"",
            comparison.resolve_cpu(None), process_environments()[0],
            timeout_seconds=10.0)
        self.assertGreater(len(stdout), 256 * 1024)
        self.assertGreater(len(stderr), 256 * 1024)
        self.assertEqual(result["stdout"], stdout.decode("utf-8"))
        self.assertEqual(result["stdoutBytes"], len(stdout))
        self.assertEqual(result["stdoutSha256"], digest(stdout))
        self.assertGreater(result["peakRssKiB"], 0)

    def test_run_rejects_a_variable_outside_the_execution_allowlist(self) -> None:
        environment = process_environments()[0]
        environment["LD_PRELOAD"] = "/tmp/instrumentation.so"
        with self.assertRaisesRegex(ValueError, "unexpected: LD_PRELOAD"):
            comparison.run([sys.executable, "-c", "pass"], b"",
                comparison.resolve_cpu(None), environment, timeout_seconds=1.0)

    def test_run_drains_large_stderr_before_reporting_failure(self) -> None:
        stderr = b"failure-detail\n" * 24500 + b"failure-tail\n"
        script = ("import os\n"
            "for _ in range(24500): os.write(2, b'failure-detail\\n')\n"
            "os.write(2, b'failure-tail\\n')\n"
            "raise SystemExit(23)\n")
        with self.assertRaisesRegex(RuntimeError, r"driver failed \(23\):") as caught:
            comparison.run([sys.executable, "-c", script], b"",
                comparison.resolve_cpu(None), process_environments()[0],
                timeout_seconds=10.0)
        self.assertGreater(len(stderr), 256 * 1024)
        self.assertIn("failure-tail", str(caught.exception))

    def test_run_tolerates_procfs_exit_race(self) -> None:
        script = "import time; time.sleep(0.02); print('ok')"
        with patch.object(comparison.Path, "read_text",
                side_effect=ProcessLookupError(3, "No such process")):
            result = comparison.run([sys.executable, "-c", script], b"",
                comparison.resolve_cpu(None), process_environments()[0],
                timeout_seconds=1.0)
        self.assertEqual(result["stdout"], "ok\n")

    def test_run_kills_timed_out_driver_after_draining_pipes(self) -> None:
        script = ("import os, subprocess, sys\n"
            "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])\n"
            "os.write(1, b'before-timeout')\n")
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired) as caught:
            comparison.run([sys.executable, "-c", script], b"",
                comparison.resolve_cpu(None), process_environments()[0],
                timeout_seconds=0.5)
        self.assertLess(time.monotonic() - started, 3.0)
        self.assertEqual(caught.exception.output, b"before-timeout")


if __name__ == "__main__":
    unittest.main()
