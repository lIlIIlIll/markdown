#!/usr/bin/env python3
"""Compare markdown with the platform-neutral markdown4cj parser core.

The pinned markdown4cj HAR targets HarmonyOS, but ``src/core`` does not. This
runner exports that core and the commonmark4cj dependency from pinned local Git
objects, applies a fail-closed current-SDK collection-API migration, and builds
them in a fresh cjpm project. No OHOS, DevEco, UI component, prism4cj, or
formula-ffi source is built.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
from io import BytesIO
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import shlex
import signal
import stat
import statistics
import struct
import subprocess
import sys
import tarfile
import tempfile
import threading
import time

from benchmark_identity import (
    BUILD_ENVIRONMENT_KEYS,
    CANGJIE_GC_INTERVAL,
    CANGJIE_HEAP_SIZE,
    CANONICAL_LOCALE,
    CANONICAL_TIMEZONE,
    EXECUTION_ENVIRONMENT_KEYS,
    NATIVE_BUILD_ENVIRONMENT_KEYS,
    PRODUCT_FILES,
    PRODUCT_ROOTS,
    build_environment_attestation,
    canonical_build_environment,
    canonical_execution_environments,
    exact_environment,
    execution_environment_attestation,
    reject_ambient_benchmark_environment,
)
from measure import benchmark_corpora

ROOT = Path(__file__).resolve().parents[1]
COMPARATOR_URL = "https://gitcode.com/Cangjie-TPC/markdown4cj.git"
COMMONMARK_URL = "https://gitcode.com/Cangjie-TPC/commonmark4cj.git"
COMPARATOR_COMMIT = "f43cfb3ae1cd3092d9a8a94332c64815fc4572f9"
COMMONMARK_COMMIT = "41499e6d6e50efac71db3bba64d5300d251d9c90"
SAMPLES = 7
ITERATIONS = 3
CORPUS_BYTES = 256 * 1024
MIN_SPEEDUP = 1.20
MAX_REGRESSION = 1.10
MAX_RSS_RATIO = 1.20
SCHEMA_VERSION = 5
BUILD_IDENTITY_SCHEMA_VERSION = 4
NATIVE_CACHE_SCHEMA_VERSION = 3
NATIVE_ENVIRONMENT_SCHEMA_VERSION = 1
RUN_TIMEOUT_SECONDS = 600.0
SDK_URL = "https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.1.3.tar.gz&objectKey=6a19349d21f5a8178d6fd22b"
SDK_SHA256 = "2b68905afc466e665ae181595c63f96c18d75fd2c1fb6c6f0cb64e179c28d61a"
TARGET_TRIPLE = "x86_64-unknown-linux-gnu"
COMPARATOR_CORE_PATH = "markdown/src/main/cangjie/src/core"
ADAPTER_COMMONMARK_PATH = "deps/commonmark4cj"
BINARY_ARTIFACTS = {
    "markdown": "markdown-driver",
    "markdownCli": "markdown-cli",
    "markdown4cj": "markdown4cj-driver",
}
NATIVE_TOOL_ARTIFACTS = {
    "compiler": "toolchain/native/compiler",
    "archiver": "toolchain/native/archiver",
}
NATIVE_RESOURCE_ARTIFACT = "toolchain/native/clang-resource.tar"
NATIVE_RUNTIME_ROOT = Path("toolchain/native/runtime")
RUNTIME_LIBRARY_ROOT = Path("libraries/commonmark4cj")
ADAPTER_LIBRARY_PREFIX = "libcommonmark4cj"
HARNESS_FILES = (
    "benchmarks/compare_markdown4cj.py",
    "benchmarks/test_compare_markdown4cj.py",
    "benchmarks/measure.py",
    "benchmarks/generate_corpus.py",
    "benchmarks/benchmark_identity.py",
    "scripts/build_benchmark_driver.py",
    "scripts/build_native_scanner.py",
    "scripts/test_build_benchmark_driver.py",
    "scripts/test_build_native_scanner.py",
    ".github/workflows/candidate-validation.yml",
)

MANIFEST = """[dependencies]
  [dependencies.commonmark4cj]
    path = "{commonmark}"

[package]
  cjc-version = "1.0.0"
  compile-option = "--obf-seed 0 --trimpath {trimpath}"
  description = "Current-SDK benchmark adapter for markdown4cj parser core"
  link-option = ""
  name = "markdown"
  output-type = "executable"
  src-dir = "src"
  target-dir = ""
  version = "0.0.0"

[profile]
  [profile.build]
    incremental = false
    lto = ""
  [profile.customized-option]
    release = "--fast-math -O2 -Woff all"
"""

DRIVER = """package markdown
import markdown.core.*
import commonmark4cj.commonmark.*
import std.collection.*
import std.convert.*
import std.env.*

private func readInput(): String {
    let input = getStdIn()
    let bytes = ArrayList<Byte>()
    let buffer = Array<Byte>(8192, repeat: 0)
    while (true) {
        let count = input.read(buffer)
        if (count == 0) { break }
        if (count < 0) { throw IllegalStateException("stdin returned a negative byte count") }
        for (index in 0..count) { bytes.add(buffer[index]) }
    }
    String.fromUtf8(bytes.toArray())
}

main(args: Array<String>): Int64 {
    if (args.size != 2 || (args[0] != "parse" && args[0] != "render")) { return 2 }
    let iterations = try { Int64.parse(args[1]) } catch (_: Exception) { return 2 }
    if (iterations <= 0) { return 2 }
    let source = readInput()
    let engine = Markdown.create()
    if (args[0] == "render") {
        unsafe {
            print(HtmlRenderer.builder().percentEncodeUrls(true).build().render(engine.parse(source)))
        }
        return 0
    }
    var observed: Int64 = 0
    for (_ in 0..iterations) {
        let document = engine.parse(source)
        var child = document.getFirstChild()
        while (child.isSome()) {
            observed += 1
            child = child.getOrThrow().getNext()
        }
    }
    println(observed)
    0
}
"""

MIGRATIONS = {
    "core_plugin.cj": (("onTextAddedListeners.append(onTextAddedListener)",
                        "onTextAddedListeners.add(onTextAddedListener)"),),
    "markdown.cj": (("this.plugins.append(plugin)", "this.plugins.add(plugin)"),
        ("        parserBuilder.inlineParserFactory(InlineParserV2Factory()) // 使用v2版本的InlineParser\n", "")),
    "markdown_visitor.cj": (("nodes.put(node, v)", "nodes[node] = v"),),
    "node_ext.cj": (("list.append(node.getOrThrow())", "list.add(node.getOrThrow())"),),
    "node_view.cj": (("list.prepend(n.getView())", "list.add(n.getView(), at: 0)"),
        ("p.put(k, v)", "p[k] = v"),
        ("view.collector?.children.append(view)", "view.collector?.children.add(view)"),
        ("list.collector?.children.append(list)", "list.collector?.children.add(list)"),
        ("start.collector?.children.append(start)", "start.collector?.children.add(start)"),
        ("start.collector?.children.append(end)", "start.collector?.children.add(end)")),
    "props.cj": (("values.put(po.name(), value)", "values[po.name()] = value.getOrThrow()"),),
    "registry.cj": (("pending.put(plugin)", "pending.add(plugin)"),
        ("plugins.prepend(plugin)", "plugins.add(plugin, at: 0)"),
        ("plugins.append(plugin)", "plugins.add(plugin)")),
}

BEHAVIOR_CASES = {
    "heading": "# heading\n\nparagraph *em* and **strong**\n",
    "lists": "- one\n  - two\n\n1. ordered\n2. next\n",
    "quote": "> quote\n>\n> continuation\n",
    "fenced-code": "```cj\nlet x = 1 < 2\n```\n",
    "indented-code": "    let x = 1\n",
    "links": "[inline](https://example.com/a?b=c \"title\") and <https://example.com>\n",
    "references": "[label]: https://example.com/path \"title\"\n\nUse [label] repeatedly.\n",
    "unicode": "中文 😀 **粗体** 与 [链接](https://example.com/路径)\n",
    "entities": "\\*literal\\* &amp; &lt; &#35;\n",
    "breaks": "soft\nbreak  \nhard\n",
    "thematic-break": "before\n\n---\n\nafter\n",
    "inline-code": "`` code ` inside `` and `x < y`\n",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def retained_binary_identity(path: Path, artifact_path: str) -> dict[str, object]:
    return {"artifactPath": artifact_path, "bytes": path.stat().st_size,
        "sha256": sha256(path)}


def retained_library_identity(path: Path, artifact_path: str) -> dict[str, object]:
    return {**retained_binary_identity(path, artifact_path),
        "mode": stat.S_IMODE(path.stat().st_mode)}


def build_output_library_identity(path: Path) -> dict[str, object]:
    return {"path": str(path.resolve()), "bytes": path.stat().st_size,
        "sha256": sha256(path), "mode": stat.S_IMODE(path.stat().st_mode)}


def path_has_symlink_component(path: Path) -> bool:
    current = Path(path.anchor) if path.is_absolute() else Path.cwd()
    parts = path.parts[1:] if path.is_absolute() else path.parts
    for part in parts:
        current /= part
        if current.is_symlink():
            return True
    return False


def elf_dynamic_dependencies(path: Path, reject_search_paths: bool = True) -> tuple[str, ...]:
    """Read DT_NEEDED without executing the measured artifact or a host tool.

    Adapter artifacts reject embedded loader search paths. Retained native
    toolchain DSOs are already selected and bound by bytes, so their system
    RPATH/RUNPATH entries are ignored rather than used for resolution.
    """
    data = path.read_bytes()
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4:6] != b"\x02\x01":
        raise RuntimeError(f"adapter runtime artifact is not ELF64 little-endian: {path}")
    try:
        header = struct.unpack_from("<16sHHIQQQIHHHHHH", data, 0)
        if header[2] != 62 or header[1] not in (2, 3):
            raise ValueError("unexpected ELF type or machine")
        program_offset, program_size, program_count = header[5], header[9], header[10]
        if program_size != 56 or program_count in (0, 0xffff) or \
                program_offset + program_size * program_count > len(data):
            raise ValueError("invalid program header table")
        programs = [struct.unpack_from("<IIQQQQQQ", data,
            program_offset + index * program_size) for index in range(program_count)]
        for program in programs:
            file_offset, file_size, memory_size = program[2], program[5], program[6]
            if file_size > memory_size or file_offset + file_size > len(data):
                raise ValueError("invalid program segment bounds")
        dynamic_programs = [program for program in programs if program[0] == 2]
        if len(dynamic_programs) != 1:
            raise ValueError("ELF must contain exactly one PT_DYNAMIC segment")
        loads = [program for program in programs if program[0] == 1]
        dynamic = dynamic_programs[0]
        dynamic_offset, dynamic_address, dynamic_size = dynamic[2], dynamic[3], dynamic[5]
        if dynamic_size == 0 or dynamic_size % 16 != 0:
            raise ValueError("invalid PT_DYNAMIC size")

        def mapped_file_offset(address: int, size: int, label: str) -> int:
            mappings = []
            for load in loads:
                load_offset, load_address, load_file_size = load[2], load[3], load[5]
                if address >= load_address and \
                        address + size <= load_address + load_file_size:
                    mappings.append(load_offset + address - load_address)
            if len(mappings) != 1:
                raise ValueError(f"{label} has no unique PT_LOAD mapping")
            return mappings[0]

        if mapped_file_offset(dynamic_address, dynamic_size, "PT_DYNAMIC") != \
                dynamic_offset:
            raise ValueError("PT_DYNAMIC file and virtual mappings disagree")
        needed_offsets: list[int] = []
        string_address: int | None = None
        string_size: int | None = None
        terminated = False
        for cursor in range(dynamic_offset, dynamic_offset + dynamic_size, 16):
            tag, value = struct.unpack_from("<qQ", data, cursor)
            if tag == 0:  # DT_NULL: the loader ignores all following entries.
                terminated = True
                break
            if tag == 1:  # DT_NEEDED
                needed_offsets.append(value)
            elif tag == 5:  # DT_STRTAB
                if string_address is not None:
                    raise ValueError("duplicate DT_STRTAB")
                string_address = value
            elif tag == 10:  # DT_STRSZ
                if string_size is not None:
                    raise ValueError("duplicate DT_STRSZ")
                string_size = value
            elif reject_search_paths and tag in (15, 29):  # DT_RPATH / DT_RUNPATH
                raise ValueError("adapter runtime artifact must not contain RPATH or RUNPATH")
        if not terminated:
            raise ValueError("PT_DYNAMIC has no DT_NULL terminator")
        if string_address is None or string_size is None or string_size == 0:
            raise ValueError("dynamic string table identity is incomplete")
        string_offset = mapped_file_offset(string_address, string_size, "DT_STRTAB")
        dependencies: list[str] = []
        for value in needed_offsets:
            if value >= string_size:
                raise ValueError("invalid DT_NEEDED string offset")
            start = string_offset + value
            end = data.find(b"\0", start, string_offset + string_size)
            if end < 0:
                raise ValueError("unterminated DT_NEEDED name")
            name = data[start:end].decode("utf-8", errors="strict")
            if not name or Path(name).name != name:
                raise ValueError("unsafe DT_NEEDED name")
            dependencies.append(name)
        return tuple(dependencies)
    except (IndexError, struct.error, UnicodeDecodeError, ValueError) as error:
        raise RuntimeError(f"adapter runtime ELF metadata is invalid: {path}: {error}") from error


def elf_interpreter(path: Path) -> Path:
    data = path.read_bytes()
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01":
        raise RuntimeError(f"native tool is not ELF64 little-endian: {path}")
    try:
        header = struct.unpack_from("<16sHHIQQQIHHHHHH", data, 0)
        offset, size, count = header[5], header[9], header[10]
        if size != 56 or count in (0, 0xffff) or \
                offset + size * count > len(data):
            raise ValueError("invalid program header table")
        programs = [struct.unpack_from("<IIQQQQQQ", data,
            offset + index * size) for index in range(count)]
        interpreters = [program for program in programs if program[0] == 3]
        if len(interpreters) != 1:
            raise ValueError("ELF must contain one PT_INTERP")
        program = interpreters[0]
        if program[5] == 0 or program[2] + program[5] > len(data):
            raise ValueError("PT_INTERP is out of bounds")
        content = data[program[2]:program[2] + program[5]]
        if not content.endswith(b"\0") or b"\0" in content[:-1]:
            raise ValueError("invalid PT_INTERP content")
        interpreter = Path(content[:-1].decode("utf-8", errors="strict"))
        if not interpreter.is_absolute():
            raise ValueError("PT_INTERP is not absolute")
        return interpreter
    except (IndexError, struct.error, UnicodeDecodeError, ValueError) as error:
        raise RuntimeError(f"native tool interpreter metadata is invalid: {path}: {error}") \
            from error


def adapter_runtime_library_sources(binary: Path,
        library_root: Path, *, allow_static: bool = False) -> dict[str, Path]:
    """Resolve the adapter-owned recursive DT_NEEDED closure."""
    candidates: dict[str, Path] = {}
    for path in library_root.glob("*.so"):
        if not path.is_file() or path.is_symlink():
            raise RuntimeError(f"adapter runtime library is unavailable or unsafe: {path}")
        if path.name in candidates:
            raise RuntimeError(f"duplicate adapter runtime library name: {path.name}")
        candidates[path.name] = path
    pending = list(elf_dynamic_dependencies(binary))
    closure: dict[str, Path] = {}
    while pending:
        name = pending.pop()
        source = candidates.get(name)
        if source is None:
            if name.startswith(ADAPTER_LIBRARY_PREFIX):
                raise RuntimeError(f"adapter-owned runtime dependency is missing: {name}")
            continue
        if name in closure:
            continue
        closure[name] = source
        pending.extend(elf_dynamic_dependencies(source))
    if not closure and not allow_static:
        raise RuntimeError("adapter executable has no retained runtime library dependency")
    return dict(sorted(closure.items()))


def retain_execution_binaries(binary_root: Path,
        sources: dict[str, Path], runtime_libraries: dict[str, Path] | None = None
        ) -> tuple[dict[str, dict[str, object]], dict[str, dict[str, object]]]:
    if set(sources) != set(BINARY_ARTIFACTS):
        raise RuntimeError("execution binary set is incomplete")
    if binary_root.exists():
        raise RuntimeError(f"retained binary root already exists: {binary_root}")
    binary_root.parent.mkdir(parents=True, exist_ok=True)
    binary_root.mkdir()
    identities: dict[str, dict[str, object]] = {}
    for name, artifact_path in BINARY_ARTIFACTS.items():
        source = sources[name]
        if not source.is_file() or source.is_symlink():
            raise RuntimeError(f"execution binary is unavailable: {name}")
        destination = binary_root / artifact_path
        shutil.copy2(source, destination)
        identities[name] = retained_binary_identity(destination, artifact_path)
    library_identities: dict[str, dict[str, object]] = {}
    for name, source in sorted((runtime_libraries or {}).items()):
        if Path(name).name != name or not source.is_file() or source.is_symlink():
            raise RuntimeError(f"execution runtime library is unavailable or unsafe: {name}")
        if stat.S_IMODE(source.stat().st_mode) != 0o644:
            raise RuntimeError(f"execution runtime library mode is not canonical: {name}")
        artifact_path = (RUNTIME_LIBRARY_ROOT / name).as_posix()
        destination = binary_root / artifact_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        library_identities[name] = retained_library_identity(destination, artifact_path)
    return identities, library_identities


def retain_native_tools(binary_root: Path,
        build_identity: dict[str, object]) -> tuple[dict[str, dict[str, object]],
        dict[str, object], dict[str, object]]:
    native = build_identity.get("nativeScanner")
    if not isinstance(native, dict):
        raise RuntimeError("native scanner tool identity is missing")
    identities: dict[str, dict[str, object]] = {}
    for name, artifact_path in NATIVE_TOOL_ARTIFACTS.items():
        source_identity = native.get(name)
        if not isinstance(source_identity, dict):
            raise RuntimeError(f"native scanner {name} identity is missing")
        source = Path(str(source_identity.get("path", "")))
        if not source.is_file() or source.is_symlink() or \
                source.stat().st_size != source_identity.get("bytes") or \
                sha256(source) != source_identity.get("sha256"):
            raise RuntimeError(f"native scanner {name} bytes changed before retention")
        destination = binary_root / artifact_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        destination.chmod(0o755)
        identities[name] = retained_library_identity(destination, artifact_path)
    compiler = Path(str(native["compiler"]["path"]))
    version_environment = {"HOME": "/nonexistent-markdown-native-tool-home",
        "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin", "TZ": "UTC"}
    resource_result = subprocess.run([str(compiler), "-print-resource-dir"],
        text=True, capture_output=True, check=False, env=version_environment)
    resource = Path(resource_result.stdout.strip())
    if resource_result.returncode != 0 or not resource.is_dir() or \
            not resource.is_absolute():
        raise RuntimeError("native scanner compiler resource directory is unavailable")
    archive_path = binary_root / NATIVE_RESOURCE_ARTIFACT
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w", format=tarfile.PAX_FORMAT) as archive:
        for source in sorted(resource.rglob("*")):
            if not source.is_file():
                continue
            relative = source.relative_to(resource).as_posix()
            content = source.read_bytes()
            member = tarfile.TarInfo(relative)
            member.size = len(content)
            member.mode = 0o644
            member.mtime = 0
            archive.addfile(member, BytesIO(content))
    resource_identity = retained_binary_identity(archive_path,
        NATIVE_RESOURCE_ARTIFACT)
    resource_identity.update({"sourceCommand": [str(compiler),
        "-print-resource-dir"], "sourceTreeSha256": directory_tree_sha256(resource)})
    tool_sources = [Path(str(native[name]["path"]))
        for name in NATIVE_TOOL_ARTIFACTS]
    interpreter_paths = {elf_interpreter(path) for path in tool_sources}
    if len(interpreter_paths) != 1:
        raise RuntimeError("native scanner tools use different ELF interpreters")
    interpreter_path = next(iter(interpreter_paths))
    loader_source = interpreter_path.resolve()
    libraries: dict[str, Path] = {}
    ldd_environment = {"HOME": "/nonexistent-markdown-native-tool-home",
        "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin", "TZ": "UTC"}
    for tool in tool_sources:
        result = subprocess.run(["/usr/bin/ldd", str(tool)], text=True,
            capture_output=True, check=False, env=ldd_environment)
        if result.returncode != 0 or "not found" in result.stdout + result.stderr:
            raise RuntimeError("native scanner tool runtime closure is unavailable")
        for line in result.stdout.splitlines():
            value = line.strip()
            if "=>" in value:
                needed, resolved_text = value.split("=>", 1)
                name = needed.strip()
                candidate = resolved_text.strip().split(" ", 1)[0]
            else:
                candidate = value.split(" ", 1)[0]
                name = Path(candidate).name
            path = Path(candidate)
            if not path.is_absolute() or not path.is_file() or \
                    path.resolve() == loader_source:
                continue
            resolved = path.resolve()
            if Path(name).name != name:
                raise RuntimeError(f"unsafe native tool runtime library name: {name}")
            previous = libraries.get(name)
            if previous is not None and previous != resolved:
                raise RuntimeError(f"native tool runtime library name collision: {name}")
            libraries[name] = resolved
    runtime_root = binary_root / NATIVE_RUNTIME_ROOT
    runtime_root.mkdir(parents=True, exist_ok=True)
    loader_path = runtime_root / "loader"
    shutil.copy2(loader_source, loader_path)
    loader_path.chmod(0o755)
    library_identities: dict[str, dict[str, object]] = {}
    for name, source in sorted(libraries.items()):
        destination = runtime_root / "libraries" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        destination.chmod(0o644)
        library_identities[name] = retained_library_identity(destination,
            destination.relative_to(binary_root).as_posix())
    runtime_identity = {
        # Preserve the literal PT_INTERP value as the semantic identity.  The
        # loader source may resolve through a host symlink, but verifier-side
        # execution always uses the retained loader bytes below.
        "interpreterPath": str(interpreter_path),
        "loader": retained_library_identity(loader_path,
            loader_path.relative_to(binary_root).as_posix()),
        "libraries": library_identities,
    }
    return identities, resource_identity, runtime_identity


def directory_tree_sha256(root: Path) -> str:
    contents = {path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob("*") if path.is_file()}
    return directory_contents_sha256(contents)


def directory_contents_sha256(contents: dict[str, bytes]) -> str:
    digest = hashlib.sha256(b"markdown-directory-tree-v1\0")
    for name in sorted(contents):
        relative = name.encode("utf-8")
        content = contents[name]
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def command(command: list[str], cwd: Path,
        environment: dict[str, str] | None = None) -> dict[str, object]:
    controlled_environment = None if environment is None else exact_environment(
        environment, BUILD_ENVIRONMENT_KEYS, "benchmark build")
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False,
        env=controlled_environment)
    record = {"command": command, "cwd": str(cwd), "exitCode": result.returncode,
        "stdout": result.stdout, "stderr": result.stderr}
    if controlled_environment is not None:
        record["environment"] = controlled_environment
    return record


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def git_environment(executable: Path) -> dict[str, str]:
    """Return a Git environment that cannot be redirected by ambient GIT_* state."""
    return {
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "HOME": "/nonexistent-markdown-benchmark-home",
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": os.pathsep.join(dict.fromkeys(
            (str(executable.parent), "/usr/bin", "/bin"))),
        "TZ": "UTC",
    }


def git_bytes(root: Path, *arguments: str, input_data: bytes | None = None) -> bytes:
    executable_text = shutil.which("git")
    if executable_text is None:
        raise RuntimeError("Git executable is unavailable")
    if not root.is_dir():
        raise RuntimeError("Git work tree is unavailable")
    executable = Path(executable_text).resolve()
    result = subprocess.run([str(executable), "-C", str(root), *arguments],
        input=input_data, capture_output=True, check=False,
        env=git_environment(executable))
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(detail or "Git identity is unavailable")
    return result.stdout


def git_text(root: Path, *arguments: str) -> str:
    try:
        return git_bytes(root, *arguments).decode("utf-8", errors="strict").strip()
    except UnicodeDecodeError as error:
        raise RuntimeError("Git identity is not valid UTF-8") from error


def git_object_format(root: Path) -> str:
    value = git_text(root, "rev-parse", "--show-object-format")
    if value not in ("sha1", "sha256"):
        raise RuntimeError(f"unsupported Git object format: {value or 'empty'}")
    return value


def is_canonical_git_oid(value: object, object_format: str) -> bool:
    length = 40 if object_format == "sha1" else 64 if object_format == "sha256" else 0
    return isinstance(value, str) and len(value) == length and all(
        character in "0123456789abcdef" for character in value)


def validate_git_reference(value: object) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or any(
            ord(character) < 32 or ord(character) == 127 for character in value):
        raise RuntimeError("benchmark repository ref must be a non-empty canonical string")
    return value


def resolve_git_commit(root: Path, reference: object, object_format: str) -> str:
    canonical_reference = validate_git_reference(reference)
    commit = git_text(root, "rev-parse", "--verify", "--end-of-options",
        f"{canonical_reference}^{{commit}}")
    if not is_canonical_git_oid(commit, object_format):
        raise RuntimeError("Git returned a non-canonical commit object ID")
    return commit


def resolve_git_tree(root: Path, commit: str, object_format: str) -> str:
    tree = git_text(root, "rev-parse", "--verify", "--end-of-options",
        f"{commit}^{{tree}}")
    if not is_canonical_git_oid(tree, object_format):
        raise RuntimeError("Git returned a non-canonical tree object ID")
    return tree


def git_tree_entries(root: Path, commit: str,
        paths: tuple[str, ...], object_format: str) -> dict[str, str]:
    arguments = ["ls-tree", "-r", "--full-tree", "-z", commit]
    if paths:
        arguments.extend(("--", *paths))
    raw = git_bytes(root, *arguments)
    entries: dict[str, str] = {}
    for encoded_entry in raw.split(b"\0"):
        if not encoded_entry:
            continue
        try:
            metadata, encoded_path = encoded_entry.split(b"\t", 1)
            mode, kind, encoded_oid = metadata.split(b" ", 2)
            relative = encoded_path.decode("utf-8", errors="strict")
            oid = encoded_oid.decode("ascii", errors="strict")
        except (UnicodeDecodeError, ValueError) as error:
            raise RuntimeError("Git tree contains a malformed benchmark entry") from error
        if kind != b"blob" or mode not in (b"100644", b"100755"):
            raise RuntimeError(f"benchmark input is not a regular Git blob: {relative}")
        if not is_canonical_git_oid(oid, object_format):
            raise RuntimeError(f"benchmark input has a non-canonical object ID: {relative}")
        if relative in entries:
            raise RuntimeError(f"benchmark input appears more than once: {relative}")
        entries[relative] = oid
    return entries


def git_blob_contents(root: Path, entries: dict[str, str],
        object_format: str) -> dict[str, bytes]:
    ordered = sorted(entries.items())
    request = b"".join(f"{oid}\n".encode("ascii") for _, oid in ordered)
    stream = BytesIO(git_bytes(root, "cat-file", "--batch", input_data=request))
    contents: dict[str, bytes] = {}
    for relative, expected_oid in ordered:
        header = stream.readline().rstrip(b"\n")
        parts = header.split(b" ")
        if len(parts) != 3:
            raise RuntimeError(f"Git blob is unavailable: {relative}")
        try:
            actual_oid = parts[0].decode("ascii", errors="strict")
            size = int(parts[2])
        except (UnicodeDecodeError, ValueError) as error:
            raise RuntimeError(f"Git blob header is malformed: {relative}") from error
        if actual_oid != expected_oid or parts[1] != b"blob" or size < 0 or \
                not is_canonical_git_oid(actual_oid, object_format):
            raise RuntimeError(f"Git blob identity is invalid: {relative}")
        content = stream.read(size)
        if len(content) != size or stream.read(1) != b"\n":
            raise RuntimeError(f"Git blob content is truncated: {relative}")
        contents[relative] = content
    if stream.read(1):
        raise RuntimeError("Git returned unexpected benchmark blob data")
    return contents


@contextmanager
def local_git_repository(source: Path):
    """Yield a local Git repository, materializing a bundle when necessary."""
    supplied = source.absolute()
    if source.is_symlink() or path_has_symlink_component(supplied):
        raise RuntimeError(f"local Git source contains a symlink: {supplied}")
    resolved = source.resolve()
    if resolved.is_dir():
        try:
            git_text(resolved, "rev-parse", "--git-dir")
        except RuntimeError as error:
            raise RuntimeError(f"local Git object store is invalid: {resolved}: {error}") \
                from error
        bare = git_text(resolved, "rev-parse", "--is-bare-repository")
        git_dir = Path(git_text(resolved, "rev-parse", "--absolute-git-dir")).resolve()
        if bare == "true":
            if git_dir != resolved:
                raise RuntimeError("local bare Git source is not the exact repository root")
        elif bare == "false":
            top = Path(git_text(resolved, "rev-parse", "--show-toplevel")).resolve()
            metadata = resolved / ".git"
            if top != resolved:
                raise RuntimeError("local Git source is nested below its worktree root")
            if not metadata.is_dir() or metadata.is_symlink() or \
                    git_dir != metadata.resolve():
                raise RuntimeError("local Git worktree uses unsafe external metadata")
        else:
            raise RuntimeError("local Git source has an invalid repository kind")
        common_dir_text = git_text(resolved, "rev-parse", "--git-common-dir")
        common_dir = Path(common_dir_text)
        if not common_dir.is_absolute():
            common_dir = (resolved / common_dir).resolve()
        else:
            common_dir = common_dir.resolve()
        forbidden_metadata = (common_dir / "info/grafts", common_dir / "shallow",
            common_dir / "objects/info/alternates")
        if any(path.exists() for path in forbidden_metadata):
            raise RuntimeError(
                "local Git source uses graft, shallow, or alternate object interpretation")
        yield resolved
        return
    if not resolved.is_file() or resolved.is_symlink():
        raise RuntimeError(f"local Git source is unavailable: {resolved}")
    executable_text = shutil.which("git")
    if executable_text is None:
        raise RuntimeError("Git executable is unavailable")
    executable = Path(executable_text).resolve()
    with tempfile.TemporaryDirectory(prefix="markdown-comparator-bundle-") as temporary:
        repository = Path(temporary) / "repository.git"
        result = subprocess.run([str(executable), "clone", "--quiet", "--bare",
            str(resolved), str(repository)], capture_output=True, check=False,
            env=git_environment(executable))
        if result.returncode != 0:
            detail = result.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(detail or f"local Git bundle is invalid: {resolved}")
        yield repository


def scoped_repository_snapshot(source: Path, expected_commit: str,
        scope: str) -> tuple[dict[str, object], dict[str, bytes]]:
    """Read one fixed commit and selected blobs without consulting its work tree."""
    with local_git_repository(source) as repository:
        object_format = git_object_format(repository)
        commit = resolve_git_commit(repository, expected_commit, object_format)
        if commit != expected_commit:
            raise RuntimeError("local Git source did not resolve the pinned commit")
        tree = resolve_git_tree(repository, commit, object_format)
        paths = (scope,) if scope else ()
        entries = git_tree_entries(repository, commit, paths, object_format)
        prefix = f"{scope}/" if scope else ""
        if scope and (not entries or any(not name.startswith(prefix) for name in entries)):
            raise RuntimeError(f"pinned Git source has no canonical scope: {scope}")
        contents = git_blob_contents(repository, entries, object_format)
    selected = {name[len(prefix):] if prefix else name: content
        for name, content in contents.items()}
    if not selected:
        raise RuntimeError("pinned Git source contains no regular files")
    files = {name: hashlib.sha256(content).hexdigest()
        for name, content in sorted(selected.items())}
    identity = {"gitObjectFormat": object_format, "repositoryCommit": commit,
        "gitTree": tree, "sourcePath": scope,
        "sourceTreeSha256": directory_contents_sha256(selected),
        "sourceFileCount": len(selected), "sourceFiles": files}
    return identity, selected


def adapted_core_contents(core: dict[str, bytes]) -> tuple[
        dict[str, bytes], list[dict[str, object]]]:
    adapted = dict(core)
    applied: list[dict[str, object]] = []
    for filename, replacements in MIGRATIONS.items():
        content = adapted.get(filename)
        if content is None:
            raise RuntimeError(f"migration source file is missing: {filename}")
        try:
            text = content.decode("utf-8", errors="strict")
        except UnicodeDecodeError as error:
            raise RuntimeError(f"migration source is not valid UTF-8: {filename}") from error
        for before, after in replacements:
            count = text.count(before)
            if count == 0:
                raise RuntimeError(f"migration source not found: {filename}: {before}")
            text = text.replace(before, after)
            applied.append({"file": filename, "before": before, "after": after,
                "count": count})
        adapted[filename] = text.encode("utf-8")
    return adapted, applied


def manifest_with_trimpath(content: bytes, trimpath: str) -> bytes:
    try:
        text = content.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise RuntimeError("comparator dependency manifest is not valid UTF-8") from error
    match = re.search(r'^(\s*compile-option\s*=\s*")([^"]*)("\s*)$', text,
        flags=re.MULTILINE)
    if match is None:
        marker = "[package]\n"
        if text.count(marker) != 1:
            raise RuntimeError("comparator dependency manifest has no canonical package table")
        return text.replace(marker,
            f'{marker}  compile-option = "--obf-seed 0 --trimpath {trimpath}"\n', 1).encode("utf-8")
    if "--trimpath" in match.group(2):
        raise RuntimeError("comparator dependency manifest compile-option is unsupported")
    replacement = f'{match.group(1)}{match.group(2)} --obf-seed 0 --trimpath {trimpath}{match.group(3)}'
    return (text[:match.start()] + replacement + text[match.end():]).encode("utf-8")


def adapter_dependency_manifest(content: bytes, trimpath: str) -> bytes:
    """Create the deterministic static dependency manifest used by the adapter."""
    text = manifest_with_trimpath(content, trimpath).decode("utf-8")
    for before, after, label in (
            ('output-type = "dynamic"', 'output-type = "static"', "output type"),
            ("incremental = true", "incremental = false", "incremental mode")):
        if text.count(before) != 1:
            raise RuntimeError(
                f"comparator dependency manifest has no canonical {label}")
        text = text.replace(before, after, 1)
    return text.encode("utf-8")


def adapter_source_inputs(comparator_source: Path,
        commonmark_source: Path) -> tuple[dict[str, object], dict[str, bytes],
        dict[str, bytes]]:
    comparator, core = scoped_repository_snapshot(comparator_source,
        COMPARATOR_COMMIT, COMPARATOR_CORE_PATH)
    commonmark, commonmark_contents = scoped_repository_snapshot(commonmark_source,
        COMMONMARK_COMMIT, "")
    adapted, migrations = adapted_core_contents(core)
    manifest = MANIFEST.format(commonmark=ADAPTER_COMMONMARK_PATH,
        trimpath="@BUILD_ROOT@").encode("utf-8")
    dependency_manifest = commonmark_contents.get("cjpm.toml")
    if dependency_manifest is None:
        raise RuntimeError("commonmark4cj dependency manifest is missing")
    normalized_dependency_manifest = adapter_dependency_manifest(dependency_manifest,
        "@BUILD_ROOT@")
    driver = DRIVER.encode("utf-8")
    provenance: dict[str, object] = {
        "repositories": {"markdown4cj": comparator,
            "commonmark4cj": commonmark},
        "coreSourceTreeSha256": comparator["sourceTreeSha256"],
        "coreSourceFiles": comparator["sourceFiles"],
        "adaptedSourceTreeSha256": directory_contents_sha256(adapted),
        "adaptedSourceFiles": {name: hashlib.sha256(content).hexdigest()
            for name, content in sorted(adapted.items())},
        "migrations": migrations,
        "manifestTemplateSha256": hashlib.sha256(MANIFEST.encode("utf-8")).hexdigest(),
        "driverTemplateSha256": hashlib.sha256(DRIVER.encode("utf-8")).hexdigest(),
        "normalizedManifestSha256": hashlib.sha256(manifest).hexdigest(),
        "normalizedDependencyManifestSha256": hashlib.sha256(
            normalized_dependency_manifest).hexdigest(),
        "driverSha256": hashlib.sha256(driver).hexdigest(),
    }
    provenance["adapterInputSha256"] = canonical_json_sha256(provenance)
    return provenance, adapted, commonmark_contents


def write_source_files(root: Path, contents: dict[str, bytes]) -> None:
    for relative, content in sorted(contents.items()):
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise RuntimeError(f"unsafe Git source path: {relative}")
        destination = root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)


def product_source_contents(source: Path, reference: object) -> dict[str, bytes]:
    """Read every benchmark product input from retained Git objects."""
    with local_git_repository(source) as repository:
        object_format = git_object_format(repository)
        commit = resolve_git_commit(repository, reference, object_format)
        entries = git_tree_entries(repository, commit,
            (*PRODUCT_FILES, *PRODUCT_ROOTS), object_format)
        contents = git_blob_contents(repository, entries, object_format)
    expected_tree, _ = product_identity(contents)
    if not contents or not is_sha256(expected_tree):
        raise RuntimeError("retained product Git source has no rebuild inputs")
    return contents


def product_identity(contents: dict[str, bytes]) -> tuple[str, dict[str, str]]:
    digest = hashlib.sha256(b"markdown-benchmark-product-tree-v1\0")
    files: dict[str, str] = {}
    for relative in sorted(contents):
        encoded_relative = relative.encode("utf-8")
        content = contents[relative]
        digest.update(len(encoded_relative).to_bytes(8, "big"))
        digest.update(encoded_relative)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
        files[relative] = hashlib.sha256(content).hexdigest()
    return digest.hexdigest(), files


def git_repository_snapshot(root: Path, reference: object) -> dict[str, object]:
    object_format = git_object_format(root)
    commit = resolve_git_commit(root, reference, object_format)
    tree = resolve_git_tree(root, commit, object_format)
    product_entries = git_tree_entries(root, commit,
        (*PRODUCT_FILES, *PRODUCT_ROOTS), object_format)
    if any(relative not in PRODUCT_FILES and not any(
            relative.startswith(f"{directory}/") for directory in PRODUCT_ROOTS)
            for relative in product_entries):
        raise RuntimeError("Git returned a product path outside the identity manifest")
    product_contents = git_blob_contents(root, product_entries, object_format)
    product_tree, product_files = product_identity(product_contents)
    harness_entries = git_tree_entries(root, commit, HARNESS_FILES, object_format)
    if set(harness_entries) != set(HARNESS_FILES):
        missing = ", ".join(sorted(set(HARNESS_FILES) - set(harness_entries)))
        raise RuntimeError(f"benchmark harness blob is missing from declared commit: {missing}")
    harness_contents = git_blob_contents(root, harness_entries, object_format)
    harness_files = {relative: hashlib.sha256(content).hexdigest()
        for relative, content in sorted(harness_contents.items())}
    return {"gitObjectFormat": object_format, "repositoryRef": reference,
        "repositoryCommit": commit, "gitTree": tree,
        "productTreeSha256": product_tree, "productFiles": product_files,
        "harnessFiles": harness_files}


def retained_product_snapshot(source: Path, reference: object,
        require_source_head: bool) -> tuple[dict[str, object], bool]:
    """Derive product identity from retained Git objects, never ambient ROOT Git."""
    resolved = source.resolve()
    with local_git_repository(resolved) as repository:
        snapshot = git_repository_snapshot(repository, reference)
        object_format = str(snapshot["gitObjectFormat"])
        head_commit = resolve_git_commit(repository, "HEAD", object_format)
        head_tree = resolve_git_tree(repository, head_commit, object_format)
        matches_head = head_commit == snapshot["repositoryCommit"] and \
            head_tree == snapshot["gitTree"]
        if require_source_head and resolved.is_dir() and \
                git_text(repository, "rev-parse", "--is-bare-repository") == "false":
            matches_head = matches_head and not git_bytes(repository, "status",
                "--porcelain=v1", "--untracked-files=all")
    return snapshot, matches_head


def current_tree_is_snapshot(root: Path, snapshot: dict[str, object]) -> bool:
    object_format = str(snapshot["gitObjectFormat"])
    head_commit = resolve_git_commit(root, "HEAD", object_format)
    head_tree = resolve_git_tree(root, head_commit, object_format)
    status = git_bytes(root, "status", "--porcelain=v1", "--untracked-files=all")
    return not status and head_tree == snapshot["gitTree"]


def repository_identity() -> dict[str, object]:
    reference = os.environ.get("MARKDOWN_BENCHMARK_COMMIT", "HEAD")
    snapshot = git_repository_snapshot(ROOT, reference)
    if not current_tree_is_snapshot(ROOT, snapshot):
        raise RuntimeError("benchmark subject must match a clean publishable Git tree")
    return {key: snapshot[key] for key in ("gitObjectFormat", "repositoryRef",
        "repositoryCommit", "gitTree", "productTreeSha256", "harnessFiles")}


def benchmark_inputs() -> dict[str, bytes]:
    return {name: data for name, data in benchmark_corpora().items()
        if name != "custom-extension"}


def corpus_identity(inputs: dict[str, bytes]) -> list[dict[str, object]]:
    return [{"name": name, "bytes": len(data),
             "sha256": hashlib.sha256(data).hexdigest()}
            for name, data in inputs.items()]


def checkout_pinned(repository: str, commit: str, destination: Path) -> None:
    if destination.exists():
        if destination.is_dir() and (destination / ".git").is_dir():
            state = preflight(destination, commit)
            if state["headMatches"] and state["clean"]:
                return
        raise RuntimeError(f"refusing to replace non-matching checkout: {destination}")
    executable_text = shutil.which("git")
    if executable_text is None:
        raise RuntimeError("Git executable is unavailable")
    executable = Path(executable_text).resolve()
    environment = git_environment(executable)
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(executable), "init", "--quiet", str(destination)], check=True,
        env=environment)
    subprocess.run([str(executable), "-C", str(destination), "remote", "add", "origin",
        repository], check=True, env=environment)
    result: subprocess.CompletedProcess[str] | None = None
    for attempt in range(3):
        result = subprocess.run([str(executable), "-C", str(destination), "fetch", "--quiet",
            "origin", commit], text=True, capture_output=True, check=False,
            env=environment)
        if result.returncode == 0:
            break
        if attempt < 2:
            time.sleep(2 ** attempt)
    if result is None or result.returncode != 0:
        raise RuntimeError(result.stderr.strip() if result else "comparator fetch failed")
    subprocess.run([str(executable), "-C", str(destination), "checkout", "--quiet",
        "--detach", "FETCH_HEAD"], check=True, env=environment)
    state = preflight(destination, commit)
    if not state["headMatches"] or not state["clean"]:
        raise RuntimeError(f"pinned checkout verification failed: {destination}")


def resolve_sources(args: argparse.Namespace) -> tuple[Path, Path]:
    if args.tools_root is not None:
        if args.source is not None or args.commonmark4cj_source is not None:
            raise ValueError("use --tools-root or explicit comparator paths, not both")
        tools_root = args.tools_root.resolve()
        source = tools_root / "markdown4cj"
        commonmark = tools_root / "commonmark4cj"
        checkout_pinned(COMPARATOR_URL, COMPARATOR_COMMIT, source)
        checkout_pinned(COMMONMARK_URL, COMMONMARK_COMMIT, commonmark)
        return source, commonmark
    if args.source is None or args.commonmark4cj_source is None:
        raise ValueError("provide --tools-root or both comparator source paths")
    return args.source.resolve(), args.commonmark4cj_source.resolve()


def resolve_verification_sources(args: argparse.Namespace) -> tuple[Path, Path]:
    if args.tools_root is not None:
        if args.source is not None or args.commonmark4cj_source is not None:
            raise ValueError("use --tools-root or explicit comparator paths, not both")
        tools_root = args.tools_root.resolve()
        source = tools_root / "markdown4cj"
        commonmark = tools_root / "commonmark4cj"
    else:
        if args.source is None or args.commonmark4cj_source is None:
            raise ValueError(
                "report verification requires --tools-root or both explicit comparator Git inputs")
        source = args.source.resolve()
        commonmark = args.commonmark4cj_source.resolve()
    if not source.exists() or not commonmark.exists():
        raise ValueError("report verification comparator Git input is unavailable")
    return source, commonmark


def resolve_verification_binary_root(args: argparse.Namespace) -> Path:
    binary_root = getattr(args, "binary_root", None)
    if binary_root is None:
        raise ValueError("report verification requires --binary-root")
    if path_has_symlink_component(binary_root):
        raise ValueError("report verification retained binary root must not be a symlink")
    resolved = binary_root.resolve()
    if not resolved.is_dir():
        raise ValueError("report verification retained binary root is unavailable")
    return resolved


def resolve_verification_product_source(args: argparse.Namespace) -> Path:
    product_source = getattr(args, "product_source", None)
    if product_source is None:
        raise ValueError("report verification requires --product-source")
    resolved = product_source.resolve()
    if not resolved.exists():
        raise ValueError("report verification retained product Git input is unavailable")
    return resolved


def resolve_cpu(requested: int | None) -> int:
    available = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else [0]
    selected = available[0] if requested is None else requested
    if selected not in available:
        raise ValueError(f"CPU {selected} is outside the process affinity set {available}")
    return selected


def close_number(left: object, right: float) -> bool:
    return not isinstance(left, bool) and isinstance(left, (int, float)) and \
        math.isfinite(float(left)) and math.isfinite(right) and \
        math.isclose(float(left), right, rel_tol=1e-12, abs_tol=1e-12)


def canonical_json_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def is_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(
        character in "0123456789abcdef" for character in value)


def validate_command_record(value: object, label: str,
        expected_command: list[str] | None = None) -> list[str]:
    if not isinstance(value, dict):
        return [f"{label} command record is missing"]
    errors: list[str] = []
    command_value = value.get("command")
    if expected_command is not None and command_value != expected_command:
        errors.append(f"{label} command is not canonical")
    elif not isinstance(command_value, list) or not command_value or not all(
            isinstance(item, str) and item for item in command_value):
        errors.append(f"{label} command is incomplete")
    if not isinstance(value.get("cwd"), str) or not value.get("cwd"):
        errors.append(f"{label} working directory is missing")
    if value.get("exitCode") != 0:
        errors.append(f"{label} command did not succeed")
    if not isinstance(value.get("stdout"), str) or not isinstance(value.get("stderr"), str):
        errors.append(f"{label} command output is missing")
    return errors


def validate_binary_identity(value: object, label: str) -> list[str]:
    if not isinstance(value, dict):
        return [f"{label} binary identity is missing"]
    errors: list[str] = []
    if not isinstance(value.get("path"), str) or not value.get("path"):
        errors.append(f"{label} binary path is missing")
    if isinstance(value.get("bytes"), bool) or not isinstance(value.get("bytes"), int) or \
            value.get("bytes", 0) <= 0:
        errors.append(f"{label} binary length is invalid")
    if not is_sha256(value.get("sha256")):
        errors.append(f"{label} binary digest is invalid")
    return errors


def binary_bytes_identity(value: object) -> tuple[object, object]:
    if not isinstance(value, dict):
        return None, None
    return value.get("bytes"), value.get("sha256")


def validate_retained_binaries(report: dict[str, object],
        binary_root: Path | None) -> list[str]:
    binary_inputs = report.get("binaryInputs")
    if binary_root is None and isinstance(binary_inputs, dict) and \
            isinstance(binary_inputs.get("root"), str):
        binary_root = Path(binary_inputs["root"])
    if binary_root is None:
        return ["same-language verification requires an explicit retained binary root"]
    root = binary_root.resolve()
    if not root.is_dir() or path_has_symlink_component(binary_root):
        return ["same-language retained binary root is unavailable or unsafe"]
    errors: list[str] = []
    runtime_report = report.get("runtimeLibraries")
    if not isinstance(runtime_report, dict):
        runtime_report = {}
        errors.append("same-language retained runtime library closure is missing")
    expected_library_paths: set[str] = set()
    for name, value in runtime_report.items():
        artifact_path = (RUNTIME_LIBRARY_ROOT / str(name)).as_posix()
        if not isinstance(name, str) or Path(name).name != name or \
                not isinstance(value, dict) or set(value) != {
                    "artifactPath", "bytes", "sha256", "mode"} or \
                value.get("artifactPath") != artifact_path:
            errors.append(
                f"same-language retained runtime library identity is not canonical: {name}")
            continue
        if value.get("mode") != 0o644:
            errors.append(
                f"same-language retained runtime library mode is not canonical: {name}")
        expected_library_paths.add(artifact_path)
    native_tools = report.get("nativeTools")
    expected_native_paths: set[str] = set()
    if not isinstance(native_tools, dict) or set(native_tools) != \
            set(NATIVE_TOOL_ARTIFACTS):
        errors.append("same-language retained native tool set is incomplete")
        native_tools = {}
    for name, artifact_path in NATIVE_TOOL_ARTIFACTS.items():
        value = native_tools.get(name)
        if not isinstance(value, dict) or set(value) != {
                "artifactPath", "bytes", "sha256", "mode"} or \
                value.get("artifactPath") != artifact_path or \
                value.get("mode") != 0o755:
            errors.append(f"same-language retained native {name} identity is not canonical")
            continue
        expected_native_paths.add(artifact_path)
    resource_identity = report.get("nativeCompilerResource")
    if not isinstance(resource_identity, dict) or set(resource_identity) != {
            "artifactPath", "bytes", "sha256", "sourceCommand",
            "sourceTreeSha256"} or \
            resource_identity.get("artifactPath") != NATIVE_RESOURCE_ARTIFACT or \
            not is_sha256(resource_identity.get("sourceTreeSha256")):
        errors.append("same-language retained compiler resource identity is incomplete")
        resource_identity = None
    native_runtime = report.get("nativeToolRuntime")
    expected_native_runtime_paths: set[str] = set()
    if not isinstance(native_runtime, dict) or set(native_runtime) != {
            "interpreterPath", "loader", "libraries"} or \
            native_runtime.get("interpreterPath") != "/lib64/ld-linux-x86-64.so.2" or \
            not isinstance(native_runtime.get("libraries"),
                dict) or not native_runtime["libraries"]:
        errors.append("same-language retained native tool runtime closure is incomplete")
        native_runtime = None
    else:
        runtime_values = {"loader": native_runtime["loader"],
            **native_runtime["libraries"]}
        for name, value in runtime_values.items():
            expected_path = (NATIVE_RUNTIME_ROOT / "loader").as_posix() \
                if name == "loader" else \
                (NATIVE_RUNTIME_ROOT / "libraries" / name).as_posix()
            if not isinstance(value, dict) or set(value) != {
                    "artifactPath", "bytes", "sha256", "mode"} or \
                    value.get("artifactPath") != expected_path or \
                    value.get("mode") != (0o755 if name == "loader" else 0o644):
                errors.append(
                    f"same-language retained native runtime identity is not canonical: {name}")
                continue
            expected_native_runtime_paths.add(expected_path)
    try:
        observed_paths = list(root.rglob("*"))
        observed = {path.relative_to(root).as_posix() for path in observed_paths}
    except (OSError, ValueError) as error:
        return [f"same-language retained binary root cannot be inspected: {error}"]
    if any(path.is_symlink() for path in observed_paths):
        errors.append("same-language retained binary root contains a symlink")
    expected_paths = set(BINARY_ARTIFACTS.values()) | expected_library_paths | \
        expected_native_paths | expected_native_runtime_paths
    if resource_identity is not None:
        expected_paths.add(NATIVE_RESOURCE_ARTIFACT)
    for artifact_path in expected_library_paths | expected_native_paths | \
            expected_native_runtime_paths:
        parent = Path(artifact_path).parent
        while parent != Path("."):
            expected_paths.add(parent.as_posix())
            parent = parent.parent
    missing = sorted(expected_paths - observed)
    extra = sorted(observed - expected_paths)
    if missing:
        errors.append(
            f"same-language retained binaries are missing: {', '.join(missing)}")
    if extra:
        errors.append(
            f"same-language retained binary root has unexpected entries: {', '.join(extra)}")
    drivers = report.get("drivers")
    actual: dict[str, dict[str, object]] = {}
    for name, artifact_path in BINARY_ARTIFACTS.items():
        value = drivers.get(name) if isinstance(drivers, dict) else None
        if not isinstance(value, dict) or set(value) != {
                "artifactPath", "bytes", "sha256"}:
            errors.append(f"same-language {name} retained binary identity is incomplete")
            continue
        reported_path = value.get("artifactPath")
        path = Path(str(reported_path))
        if reported_path != artifact_path or path.is_absolute() or \
                path.parts != (artifact_path,):
            errors.append(f"same-language {name} retained binary path is not canonical")
            continue
        retained = root / path
        if not retained.is_file() or retained.is_symlink():
            errors.append(f"same-language {name} retained binary is unavailable or unsafe")
            continue
        try:
            identity = retained_binary_identity(retained, artifact_path)
        except OSError as error:
            errors.append(f"same-language {name} retained binary cannot be read: {error}")
            continue
        actual[name] = identity
        if value != identity:
            errors.append(
                f"same-language {name} retained binary bytes do not match the report")
    actual_libraries: dict[str, dict[str, object]] = {}
    for name, value in runtime_report.items():
        if not isinstance(name, str) or not isinstance(value, dict):
            continue
        artifact_path = (RUNTIME_LIBRARY_ROOT / name).as_posix()
        if value.get("artifactPath") != artifact_path:
            continue
        retained = root / artifact_path
        if not retained.is_file() or retained.is_symlink():
            errors.append(
                f"same-language retained runtime library is unavailable or unsafe: {name}")
            continue
        try:
            identity = retained_library_identity(retained, artifact_path)
        except OSError as error:
            errors.append(
                f"same-language retained runtime library cannot be read: {name}: {error}")
            continue
        actual_libraries[name] = identity
        if value != identity:
            errors.append(
                f"same-language retained runtime library bytes or mode do not match: {name}")
    native_identity = report.get("buildIdentity")
    native_build = native_identity.get("nativeScanner") \
        if isinstance(native_identity, dict) else None
    for name, artifact_path in NATIVE_TOOL_ARTIFACTS.items():
        value = native_tools.get(name)
        retained = root / artifact_path
        if not isinstance(value, dict) or not retained.is_file() or \
                retained.is_symlink():
            continue
        actual_tool = retained_library_identity(retained, artifact_path)
        if value != actual_tool:
            errors.append(f"same-language retained native {name} bytes do not match")
        source_tool = native_build.get(name) if isinstance(native_build, dict) else None
        if binary_bytes_identity(source_tool) != binary_bytes_identity(actual_tool):
            errors.append(f"same-language retained native {name} is not bound to the build tool")
    if isinstance(resource_identity, dict):
        resource_path = root / NATIVE_RESOURCE_ARTIFACT
        actual_resource = retained_binary_identity(resource_path,
            NATIVE_RESOURCE_ARTIFACT) if resource_path.is_file() and \
            not resource_path.is_symlink() else None
        if actual_resource is None or any(actual_resource.get(field) !=
                resource_identity.get(field) for field in
                ("artifactPath", "bytes", "sha256")):
            errors.append("same-language retained compiler resource bytes do not match")
        compiler = native_build.get("compiler") if isinstance(native_build, dict) else None
        if not isinstance(compiler, dict) or \
                resource_identity.get("sourceCommand") != [compiler.get("path"),
                    "-print-resource-dir"]:
            errors.append("same-language retained compiler resource is not bound to the build tool")
    if isinstance(native_runtime, dict):
        runtime_values = {"loader": native_runtime["loader"],
            **native_runtime["libraries"]}
        for name, value in runtime_values.items():
            artifact_path = str(value.get("artifactPath", "")) \
                if isinstance(value, dict) else ""
            retained = root / artifact_path
            actual_runtime = retained_library_identity(retained, artifact_path) \
                if retained.is_file() and not retained.is_symlink() else None
            if actual_runtime != value:
                errors.append(
                    f"same-language retained native runtime bytes do not match: {name}")
        try:
            libraries = native_runtime["libraries"]
            loader_name = Path(str(native_runtime["interpreterPath"])).name
            pending = [root / artifact for artifact in NATIVE_TOOL_ARTIFACTS.values()]
            visited: set[str] = set()
            while pending:
                artifact = pending.pop()
                for dependency in elf_dynamic_dependencies(artifact,
                        reject_search_paths=False):
                    if dependency == loader_name:
                        continue
                    if dependency in visited:
                        continue
                    if dependency not in libraries:
                        raise RuntimeError(
                            f"native runtime dependency is missing: {dependency}")
                    visited.add(dependency)
                    pending.append(root / NATIVE_RUNTIME_ROOT / "libraries" /
                        dependency)
            if visited != set(libraries):
                raise RuntimeError("native runtime closure has unreferenced libraries")
            loader = root / NATIVE_RUNTIME_ROOT / "loader"
            for artifact in (root / artifact for artifact in
                    NATIVE_TOOL_ARTIFACTS.values()):
                if str(elf_interpreter(artifact)) != native_runtime["interpreterPath"]:
                    raise RuntimeError("native runtime PT_INTERP path is inconsistent")
        except (OSError, RuntimeError) as error:
            errors.append(f"same-language retained native runtime closure is invalid: {error}")
    adapter_executable = root / BINARY_ARTIFACTS["markdown4cj"]
    try:
        closure = adapter_runtime_library_sources(adapter_executable,
            root / RUNTIME_LIBRARY_ROOT, allow_static=True)
        if set(closure) != set(actual_libraries):
            errors.append(
                "same-language retained runtime library closure is not derived from the adapter executable")
    except (OSError, RuntimeError) as error:
        errors.append(f"same-language retained runtime library closure is invalid: {error}")
    build_identity = report.get("buildIdentity")
    builds = build_identity.get("builds") if isinstance(build_identity, dict) else None
    for build_name, driver_name in (("markdownDriver", "markdown"),
            ("markdownCli", "markdownCli")):
        build = builds.get(build_name) if isinstance(builds, dict) else None
        declared = build.get("binary") if isinstance(build, dict) else None
        if driver_name in actual and binary_bytes_identity(declared) != \
                binary_bytes_identity(actual[driver_name]):
            errors.append(
                f"same-language {driver_name} retained bytes are not bound to the build output")
    adapter = report.get("adapterBuild")
    adapter_binary = adapter.get("binary") if isinstance(adapter, dict) else None
    build_output = adapter.get("buildOutputBinary") if isinstance(adapter, dict) else None
    if "markdown4cj" in actual:
        if adapter_binary != actual["markdown4cj"]:
            errors.append(
                "same-language markdown4cj retained bytes are not bound to adapterBuild")
        if binary_bytes_identity(build_output) != \
                binary_bytes_identity(actual["markdown4cj"]):
            errors.append(
                "same-language markdown4cj retained bytes are not bound to the adapter build output")
    retained_adapter_libraries = adapter.get("runtimeLibraries") \
        if isinstance(adapter, dict) else None
    if retained_adapter_libraries != runtime_report:
        errors.append(
            "same-language retained runtime libraries are not bound to adapterBuild")
    build_output_libraries = adapter.get("buildOutputRuntimeLibraries") \
        if isinstance(adapter, dict) else None
    if not isinstance(build_output_libraries, dict) or \
            set(build_output_libraries) != set(actual_libraries):
        errors.append(
            "same-language adapter build runtime library closure is incomplete")
    else:
        for name, identity in actual_libraries.items():
            build_output_identity = build_output_libraries.get(name)
            adapter_cwd = Path(str(adapter.get("cwd", ""))) \
                if isinstance(adapter, dict) else Path("")
            expected_build_path = str((adapter_cwd /
                "target/release/commonmark4cj" / name).resolve()) \
                if adapter_cwd.is_absolute() else ""
            if not isinstance(build_output_identity, dict) or set(
                    build_output_identity) != {"path", "bytes", "sha256", "mode"} or \
                    build_output_identity.get("path") != expected_build_path or \
                    (build_output_identity.get("bytes"),
                     build_output_identity.get("sha256"),
                     build_output_identity.get("mode")) != \
                    (identity.get("bytes"), identity.get("sha256"), identity.get("mode")):
                errors.append(
                    f"same-language retained runtime library is not bound to the adapter build output: {name}")
    return errors


def validate_rebuilt_binaries(report: dict[str, object], binary_root: Path,
        rebuilt_binaries: dict[str, Path],
        rebuilt_runtime_libraries: dict[str, Path]) -> list[str]:
    """Bind retained executables to independently rebuilt source outputs.

    Report digests are deliberately not accepted as the rebuild oracle: this
    function compares the actual retained bytes to actual fresh-build bytes.
    """
    errors: list[str] = []
    if set(rebuilt_binaries) != set(BINARY_ARTIFACTS):
        return ["same-language reproducible rebuild executable set is incomplete"]
    for name, artifact_path in BINARY_ARTIFACTS.items():
        retained = binary_root / artifact_path
        rebuilt = rebuilt_binaries[name]
        try:
            equal = retained.is_file() and not retained.is_symlink() and \
                rebuilt.is_file() and not rebuilt.is_symlink() and \
                retained.read_bytes() == rebuilt.read_bytes()
        except OSError:
            equal = False
        if not equal:
            errors.append(
                f"same-language {name} retained binary is not reproducible from attested inputs")
    runtime_report = report.get("runtimeLibraries")
    expected_names = set(runtime_report) if isinstance(runtime_report, dict) else set()
    if set(rebuilt_runtime_libraries) != expected_names:
        errors.append("same-language reproducible rebuild runtime library set differs")
        return errors
    for name in sorted(expected_names):
        retained = binary_root / RUNTIME_LIBRARY_ROOT / name
        rebuilt = rebuilt_runtime_libraries[name]
        try:
            equal = retained.is_file() and not retained.is_symlink() and \
                rebuilt.is_file() and not rebuilt.is_symlink() and \
                retained.read_bytes() == rebuilt.read_bytes() and \
                stat.S_IMODE(retained.stat().st_mode) == \
                stat.S_IMODE(rebuilt.stat().st_mode)
        except OSError:
            equal = False
        if not equal:
            errors.append(
                f"same-language retained runtime library is not reproducible from attested inputs: {name}")
    return errors


def verified_native_tool(value: object, label: str, binary_root: Path) -> Path:
    if not isinstance(value, dict):
        raise RuntimeError(f"attested native {label} is missing")
    artifact_path = NATIVE_TOOL_ARTIFACTS[label]
    path = binary_root / artifact_path
    if not path.is_file() or path.is_symlink() or \
            path.stat().st_size != value.get("bytes") or \
            sha256(path) != value.get("sha256"):
        raise RuntimeError(f"attested native {label} bytes are unavailable")
    version = value.get("version")
    if not isinstance(version, dict) or not isinstance(version.get("command"), list) or \
            len(version["command"]) != 2 or version["command"][1] != "--version":
        raise RuntimeError(f"attested native {label} version command is invalid")
    environment = {"HOME": "/nonexistent-markdown-native-tool-home",
        "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin", "TZ": "UTC"}
    loader = binary_root / NATIVE_RUNTIME_ROOT / "loader"
    libraries = binary_root / NATIVE_RUNTIME_ROOT / "libraries"
    if not loader.is_file() or loader.is_symlink() or not libraries.is_dir():
        raise RuntimeError("retained native tool runtime closure is unavailable")
    result = subprocess.run([str(loader), "--library-path", str(libraries),
        str(path), "--version"], text=True,
        capture_output=True, check=False, env=environment)
    def normalized_version(text: object) -> str:
        return "\n".join("InstalledDir: @RELOCATED@" if line.startswith(
            "InstalledDir:") else line for line in str(text).split("\n"))
    if result.returncode != version.get("exitCode") or \
            normalized_version(result.stdout) != normalized_version(
                version.get("stdout")) or \
            normalized_version(result.stderr) != normalized_version(
                version.get("stderr")):
        raise RuntimeError(f"attested native {label} version output changed")
    return path


def reproducibly_rebuild_binaries(report: dict[str, object], product_source: Path,
        comparator_source: Path, commonmark_source: Path, sdk_archive: Path,
        binary_root: Path
        ) -> tuple[dict[str, Path], dict[str, Path]]:
    """Rebuild all measured binaries in fresh directories from retained inputs."""
    build_identity = report.get("buildIdentity")
    identity = report.get("identity")
    if not isinstance(build_identity, dict) or not isinstance(identity, dict):
        raise RuntimeError("reproducible rebuild identity is incomplete")
    sdk = build_identity.get("sdk")
    native = build_identity.get("nativeScanner")
    if not isinstance(sdk, dict) or not isinstance(native, dict):
        raise RuntimeError("reproducible rebuild toolchain identity is incomplete")
    archive = sdk_archive.resolve()
    if not archive.is_file() or archive.is_symlink() or \
            archive.stat().st_size != sdk.get("archiveBytes") or \
            sha256(archive) != sdk.get("archiveSha256") or \
            sdk.get("archiveSha256") != SDK_SHA256:
        raise RuntimeError("retained SDK archive does not match the attested build input")
    compiler = verified_native_tool(native.get("compiler"), "compiler", binary_root)
    archiver = verified_native_tool(native.get("archiver"), "archiver", binary_root)
    contents = product_source_contents(product_source, identity.get("repositoryRef"))
    expected_tree, _ = product_identity(contents)
    if expected_tree != identity.get("productTreeSha256"):
        raise RuntimeError("retained product Git objects differ from the rebuild identity")

    temporary = tempfile.TemporaryDirectory(prefix="markdown-reproducible-build-")
    # Keep the directory alive by attaching it to the returned path objects'
    # owner container; the caller validates bytes before this function returns.
    try:
        root = Path(temporary.name)
        product = root / "markdown"
        write_source_files(product, contents)
        resource_archive = binary_root / NATIVE_RESOURCE_ARTIFACT
        resource_root = root / "clang-resource"
        resource_root.mkdir()
        with tarfile.open(resource_archive, "r:") as archive_bundle:
            members = archive_bundle.getmembers()
            if not members:
                raise RuntimeError("retained compiler resource archive is empty")
            archive_bundle.extractall(resource_root, members=members, filter="data")
        resource_identity = report.get("nativeCompilerResource")
        if not isinstance(resource_identity, dict) or \
                directory_tree_sha256(resource_root) != \
                resource_identity.get("sourceTreeSha256"):
            raise RuntimeError("retained compiler resource tree digest changed")
        loader = binary_root / NATIVE_RUNTIME_ROOT / "loader"
        libraries = binary_root / NATIVE_RUNTIME_ROOT / "libraries"
        launchers: dict[str, Path] = {}
        for name, tool in (("compiler", compiler), ("archiver", archiver)):
            launcher = root / f"native-{name}"
            launcher.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(value)
                for value in (str(loader), "--library-path", str(libraries),
                    str(tool))) + ' "$@"\n', encoding="utf-8")
            launcher.chmod(0o755)
            launchers[name] = launcher
        native_environment = {
            "AR": str(launchers["archiver"]), "CC": str(launchers["compiler"]),
            "HOME": str(root / "native-home"), "LANG": "C", "LC_ALL": "C",
            "PATH": os.pathsep.join(dict.fromkeys((str(compiler.parent),
                str(archiver.parent), "/usr/bin", "/bin"))),
            "TZ": "UTC",
            "MARKDOWN_NATIVE_CFLAGS": f"-resource-dir {resource_root}",
        }
        (root / "native-home").mkdir()
        native_result = subprocess.run([sys.executable,
            str(product / "scripts/build_native_scanner.py"), "--enable",
            "--target", TARGET_TRIPLE], cwd=product, env=native_environment,
            text=True, capture_output=True, check=False)
        if native_result.returncode != 0:
            raise RuntimeError("reproducible native scanner rebuild failed: " +
                (native_result.stderr.strip() or native_result.stdout.strip()))
        identity_output = root / "rebuild-identity.json"
        sdk_extract = root / "sdk"
        product_environment = dict(native_environment)
        product_environment.pop("MARKDOWN_NATIVE_CFLAGS")
        build_result = subprocess.run([sys.executable,
            str(product / "scripts/build_benchmark_driver.py"), "--mode", "canonical",
            "--build-cli", "--identity-output", str(identity_output),
            "--sdk-url", SDK_URL, "--sdk-sha256", SDK_SHA256,
            "--sdk-archive", str(archive), "--sdk-extract-dir", str(sdk_extract),
            "--target", TARGET_TRIPLE], cwd=product, env=product_environment,
            text=True, capture_output=True, check=False)
        if build_result.returncode != 0:
            raise RuntimeError("reproducible product rebuild failed: " +
                (build_result.stderr.strip() or build_result.stdout.strip()))
        rebuilt_identity = json.loads(identity_output.read_text(encoding="utf-8"))
        cjpm, sdk_environment = attested_sdk_environment(rebuilt_identity)
        adapter_workspace = root / "adapter"
        comparator, _ = build_adapter(comparator_source, commonmark_source,
            adapter_workspace, cjpm, sdk_environment)
        runtime = adapter_runtime_library_sources(comparator,
            adapter_workspace / "target/release/commonmark4cj", allow_static=True)
        rebuilt = {
            "markdown": product / "benchmarks/driver/target/release/bin/main",
            "markdownCli": product / "tools/markdown/target/release/bin/main",
            "markdown4cj": comparator,
        }
        # Compare while the fresh directory still exists, then return stable
        # copies so callers can keep the validation logic independently tested.
        output_root = Path(tempfile.mkdtemp(prefix="markdown-rebuilt-artifacts-"))
        try:
            copied: dict[str, Path] = {}
            for name, path in rebuilt.items():
                destination = output_root / BINARY_ARTIFACTS[name]
                shutil.copy2(path, destination)
                copied[name] = destination
            copied_runtime: dict[str, Path] = {}
            for name, path in runtime.items():
                destination = output_root / RUNTIME_LIBRARY_ROOT / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
                copied_runtime[name] = destination
            return copied, copied_runtime
        except Exception:
            shutil.rmtree(output_root, ignore_errors=True)
            raise
    finally:
        temporary.cleanup()


def verify_reproducible_binaries(report: dict[str, object], binary_root: Path,
        product_source: Path, comparator_source: Path, commonmark_source: Path,
        sdk_archive: Path) -> list[str]:
    rebuilt_root: Path | None = None
    try:
        rebuilt, runtime = reproducibly_rebuild_binaries(report, product_source,
            comparator_source, commonmark_source, sdk_archive, binary_root)
        rebuilt_root = next(iter(rebuilt.values())).parent
        return validate_rebuilt_binaries(report, binary_root, rebuilt, runtime)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        return [f"same-language reproducible binary verification failed: {error}"]
    finally:
        if rebuilt_root is not None:
            shutil.rmtree(rebuilt_root, ignore_errors=True)


def validate_native_tool_identity(value: object, label: str) -> list[str]:
    errors = validate_binary_identity(value, label)
    if not isinstance(value, dict):
        return errors
    if set(value) != {"path", "bytes", "sha256", "version"}:
        errors.append(f"{label} identity fields are incomplete")
    path = Path(str(value.get("path", "")))
    if not path.is_absolute():
        errors.append(f"{label} path is not absolute")
    version = value.get("version")
    if not isinstance(version, dict) or set(version) != {
            "command", "exitCode", "stdout", "stderr"} or \
            isinstance(version.get("exitCode"), bool) or \
            not isinstance(version.get("exitCode"), int) or \
            not isinstance(version.get("stdout"), str) or \
            not isinstance(version.get("stderr"), str) or \
            not (version.get("stdout") or version.get("stderr")):
        errors.append(f"{label} version identity is invalid")
    else:
        command = version.get("command")
        if not isinstance(command, list) or len(command) != 2 or \
                command[0] != value.get("path") or command[1] not in ("--version", "/?"):
            errors.append(f"{label} version command is not bound")
    return errors


def validate_native_environment(value: object, compiler: object,
        archiver: object, obj: object) -> list[str]:
    if not isinstance(value, dict) or set(value) != {
            "schemaVersion", "allowlist", "variables", "sha256"} or \
            value.get("schemaVersion") != NATIVE_ENVIRONMENT_SCHEMA_VERSION or \
            value.get("allowlist") != sorted(NATIVE_BUILD_ENVIRONMENT_KEYS):
        return ["same-language native scanner child environment identity is incomplete"]
    variables = value.get("variables")
    if not isinstance(variables, dict) or \
            not set(variables).issubset(NATIVE_BUILD_ENVIRONMENT_KEYS) or \
            any(not isinstance(name, str) or not isinstance(item, str)
                for name, item in variables.items()) or \
            value.get("sha256") != canonical_json_sha256(variables):
        return ["same-language native scanner child environment digest is invalid"]
    if not isinstance(compiler, dict) or not isinstance(archiver, dict) or \
            not isinstance(obj, dict):
        return []
    native_dir = Path(str(obj.get("path", ""))).parent
    path = os.pathsep.join(dict.fromkeys((
        str(Path(str(compiler.get("path", ""))).parent),
        str(Path(str(archiver.get("path", ""))).parent), "/usr/bin", "/bin")))
    expected = {
        "HOME": str(native_dir / ".native-build-home"),
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": path,
        "SOURCE_DATE_EPOCH": "0",
        "TMPDIR": str(native_dir / ".native-build-tmp"),
        "TZ": "UTC",
    }
    if variables != expected:
        return ["same-language native scanner child environment is not canonical"]
    return []


def validate_repository_identity(value: object, require_current_product: bool,
        product_source: Path | None = None) -> tuple[list[str], dict[str, object] | None]:
    if not isinstance(value, dict):
        return ["same-language report has no product identity"], None
    errors: list[str] = []
    expected_fields = {"gitObjectFormat", "repositoryRef", "repositoryCommit",
        "gitTree", "productTreeSha256", "harnessFiles", "corpora"}
    if set(value) != expected_fields:
        errors.append("same-language Git identity fields are incomplete")
    try:
        snapshot, matches_source_head = retained_product_snapshot(
            product_source if product_source is not None else ROOT,
            value.get("repositoryRef"), require_current_product)
    except (OSError, RuntimeError) as error:
        errors.append(f"same-language declared Git source cannot be verified: {error}")
        return errors, None
    object_format = str(snapshot["gitObjectFormat"])
    if value.get("gitObjectFormat") != object_format:
        errors.append("same-language Git object format is not derived")
    for field, label in (("repositoryCommit", "commit"), ("gitTree", "tree")):
        if not is_canonical_git_oid(value.get(field), object_format):
            errors.append(f"same-language repository {label} is not a canonical object ID")
        if value.get(field) != snapshot[field]:
            errors.append(f"same-language repository {label} is not derived from its ref")
    if not is_sha256(value.get("productTreeSha256")) or \
            value.get("productTreeSha256") != snapshot["productTreeSha256"]:
        errors.append(
            "same-language report product tree does not match the declared Git commit")
    if value.get("harnessFiles") != snapshot["harnessFiles"]:
        errors.append(
            "same-language report harness identity does not match the declared Git commit")
    if require_current_product:
        if not matches_source_head:
            errors.append(
                "same-language declared Git source is not the retained product source HEAD")
    return errors, snapshot


def validate_build_identity(value: object, drivers: object,
        source_snapshot: dict[str, object] | None) -> list[str]:
    if not isinstance(value, dict):
        return ["same-language report has no benchmark build identity"]
    errors: list[str] = []
    expected_files = source_snapshot.get("productFiles") \
        if isinstance(source_snapshot, dict) else None
    expected_product_tree = source_snapshot.get("productTreeSha256") \
        if isinstance(source_snapshot, dict) else None
    if not isinstance(expected_files, dict) or not is_sha256(expected_product_tree):
        errors.append(
            "same-language build source cannot be verified from the declared Git commit")
        expected_files = {}
        expected_product_tree = None
    required_source_files = ("native/markdown_scanner.c",
        "native/markdown_scanner.h", "benchmarks/driver/cjpm.toml",
        "tools/markdown/cjpm.toml")
    if any(not is_sha256(expected_files.get(relative))
            for relative in required_source_files):
        errors.append(
            "same-language declared Git commit lacks required benchmark build inputs")
    if value.get("schemaVersion") != BUILD_IDENTITY_SCHEMA_VERSION:
        errors.append("same-language build identity schema is unsupported")
    sdk = value.get("sdk")
    expected_sdk = {"archiveUrl": SDK_URL, "archiveSha256": SDK_SHA256,
        "target": TARGET_TRIPLE}
    if not isinstance(sdk, dict) or any(sdk.get(key) != expected for key, expected in
            expected_sdk.items()) or not isinstance(sdk.get("archiveBytes"), int) or \
            sdk.get("archiveBytes", 0) <= 0:
        errors.append("same-language build identity SDK attestation is not canonical")
    sdk_root = Path(str(sdk.get("root", ""))) if isinstance(sdk, dict) else Path("")
    if not sdk_root.is_absolute():
        errors.append("same-language build identity SDK root is missing")
    extraction = Path(str(sdk.get("extraction", ""))) if isinstance(sdk, dict) else Path("")
    if not extraction.is_absolute():
        errors.append("same-language build identity SDK extraction root is missing")
    elif sdk_root.is_absolute():
        try:
            sdk_root.relative_to(extraction)
        except ValueError:
            errors.append("same-language SDK root is outside the fresh extraction")
    if not isinstance(sdk, dict) or not Path(str(sdk.get("archivePath", ""))).is_absolute() or \
            not is_sha256(sdk.get("envsetupSha256")):
        errors.append("same-language build identity SDK extraction is incomplete")
    identity_environment = sdk.get("environment") if isinstance(sdk, dict) else None
    command_environment = None
    if sdk_root.is_absolute():
        try:
            command_environment = canonical_build_environment(sdk_root, TARGET_TRIPLE)
        except ValueError:
            command_environment = None
    expected_environment_attestation = build_environment_attestation(
        command_environment) if command_environment is not None else None
    if identity_environment != expected_environment_attestation:
        errors.append("same-language build identity SDK environment is not canonical")
    tools = value.get("tools")
    if not isinstance(tools, dict):
        errors.append("same-language build identity has no tool versions")
    else:
        for name, suffix in (("cjc", "-v"), ("cjpm", "--version")):
            record = tools.get(name)
            tool_path = str(record.get("path", "")) if isinstance(record, dict) else ""
            arguments = [tool_path, suffix]
            errors.extend(validate_command_record(record, f"same-language {name}", arguments))
            if not isinstance(record, dict) or not isinstance(record.get("path"), str) or \
                    not Path(str(record.get("path"))).is_absolute():
                errors.append(f"same-language {name} resolved path is missing")
            elif sdk_root.is_absolute():
                try:
                    Path(str(record.get("path"))).relative_to(sdk_root)
                except ValueError:
                    errors.append(f"same-language {name} is outside the attested SDK root")
            errors.extend(validate_binary_identity(record, f"same-language {name} tool"))
            if isinstance(record, dict) and record.get("environment") != command_environment:
                errors.append(f"same-language {name} command environment is not attested")
        cjc_path = Path(str(tools.get("cjc", {}).get("path", ""))) \
            if isinstance(tools.get("cjc"), dict) else Path("")
        cjpm_path = Path(str(tools.get("cjpm", {}).get("path", ""))) \
            if isinstance(tools.get("cjpm"), dict) else Path("")
        if cjc_path != sdk_root / "bin" / "cjc":
            errors.append("same-language cjc path is not canonical for the extracted SDK")
        if cjpm_path not in (sdk_root / "bin" / "cjpm", sdk_root / "tools" / "bin" / "cjpm"):
            errors.append("same-language cjpm path is not canonical for the extracted SDK")
        cjc = tools.get("cjc")
        if isinstance(cjc, dict) and f"Target: {TARGET_TRIPLE}" not in \
                str(cjc.get("stdout", "")) + str(cjc.get("stderr", "")):
            errors.append("same-language cjc version does not attest the target triple")
    source = value.get("sourceIdentity")
    if not isinstance(source, dict) or source.get("files") != expected_files:
        errors.append(
            "same-language build input file identity does not match the declared Git source")
    if not isinstance(source, dict) or \
            source.get("productTreeSha256") != expected_product_tree:
        errors.append(
            "same-language build product tree does not match the declared Git source")
    native = value.get("nativeScanner")
    if not isinstance(native, dict):
        errors.append("same-language native scanner build identity is missing")
    else:
        if set(native) != {"cacheManifest", "cacheManifestSha256", "compiler",
                "archiver", "buildEnvironment", "object", "archive"}:
            errors.append("same-language native scanner identity fields are incomplete")
        obj = native.get("object")
        archive = native.get("archive")
        compiler_identity = native.get("compiler")
        archiver_identity = native.get("archiver")
        environment_identity = native.get("buildEnvironment")
        errors.extend(validate_native_tool_identity(compiler_identity,
            "same-language native scanner compiler"))
        errors.extend(validate_native_tool_identity(archiver_identity,
            "same-language native scanner archiver"))
        errors.extend(validate_native_environment(environment_identity,
            compiler_identity, archiver_identity, obj))
        manifest = native.get("cacheManifest")
        if not isinstance(manifest, dict) or \
                manifest.get("schemaVersion") != NATIVE_CACHE_SCHEMA_VERSION:
            errors.append("same-language native scanner manifest schema is unsupported")
        elif manifest.get("target") != TARGET_TRIPLE:
            errors.append("same-language native scanner target is not canonical")
        else:
            if native.get("cacheManifestSha256") != canonical_json_sha256(manifest):
                errors.append("same-language native scanner manifest digest is not derived")
            if manifest.get("sourceSha256") != \
                    expected_files.get("native/markdown_scanner.c") or \
                    manifest.get("headerSha256") != \
                    expected_files.get("native/markdown_scanner.h"):
                errors.append("same-language native scanner source identity is stale")
            for field in ("compileCommand", "archiveCommand"):
                if not isinstance(manifest.get(field), list) or not manifest.get(field):
                    errors.append(f"same-language native scanner {field} is missing")
            compile_command = manifest.get("compileCommand")
            archive_command = manifest.get("archiveCommand")
            compiler = manifest.get("compiler")
            archiver = manifest.get("archiver")
            if compiler != compiler_identity or archiver != archiver_identity:
                errors.append(
                    "same-language native scanner tool identity is not bound to its manifest")
            if manifest.get("buildEnvironment") != environment_identity:
                errors.append(
                    "same-language native scanner environment is not bound to its manifest")
            if isinstance(compile_command, list) and compile_command and \
                    isinstance(compiler, dict) and compile_command[0] != compiler.get("path"):
                errors.append("same-language native scanner compiler command is not bound")
            if isinstance(archive_command, list) and archive_command and \
                    isinstance(archiver, dict) and archive_command[0] != archiver.get("path"):
                errors.append("same-language native scanner archiver command is not bound")
        errors.extend(validate_binary_identity(native.get("object"),
            "same-language native scanner object"))
        errors.extend(validate_binary_identity(native.get("archive"),
            "same-language native scanner archive"))
        manifest = native.get("cacheManifest")
        if isinstance(manifest, dict):
            if manifest.get("object") != obj:
                errors.append("same-language native scanner object is not bound to its manifest")
            if manifest.get("archive") != archive:
                errors.append("same-language native scanner archive is not bound to its manifest")
        if isinstance(obj, dict) and isinstance(manifest, dict) and \
                isinstance(manifest.get("compileCommand"), list):
            object_path = str(obj.get("path", ""))
            if not any(object_path == str(argument) or str(argument).endswith(object_path)
                    for argument in manifest["compileCommand"]):
                errors.append("same-language native scanner object is not bound to its command")
        if isinstance(archive, dict) and isinstance(obj, dict) and \
                isinstance(manifest, dict) and \
                isinstance(manifest.get("archiveCommand"), list):
            archive_path = str(archive.get("path", ""))
            if not any(archive_path == str(argument) or str(argument).endswith(archive_path)
                    for argument in manifest["archiveCommand"]):
                errors.append("same-language native scanner archive is not bound to its command")
            object_path = str(obj.get("path", ""))
            if not any(object_path == str(argument) or str(argument).endswith(object_path)
                    for argument in manifest["archiveCommand"]):
                errors.append("same-language native scanner archive input is not bound")
    builds = value.get("builds")
    expected_builds = {
        "markdownDriver": ("-O2 --lto thin --obf-seed 0", "-L ../../target/native -lmarkdown_scanner",
            "benchmarks/driver/cjpm.toml"),
        "markdownCli": ("-O2 --obf-seed 0", "", "tools/markdown/cjpm.toml"),
    }
    if not isinstance(builds, dict) or set(builds) != set(expected_builds):
        errors.append("same-language executable build records are incomplete")
    else:
        cjpm_path = str(tools.get("cjpm", {}).get("path", "")) \
            if isinstance(tools, dict) and isinstance(tools.get("cjpm"), dict) else ""
        for name, (compile_option, link_option, manifest_path) in expected_builds.items():
            build = builds[name]
            if not isinstance(build, dict):
                errors.append(f"same-language {name} build record is missing")
                continue
            errors.extend(validate_command_record(build.get("build"),
                f"same-language {name} build", [cjpm_path, "build", "-j", "1"]))
            build_command = build.get("build")
            if isinstance(build_command, dict) and \
                    build_command.get("environment") != command_environment:
                errors.append(f"same-language {name} build environment is not attested")
            trim_path = build.get("trimPath")
            expected_cwd = str((Path(str(trim_path)) /
                ("benchmarks/driver" if name == "markdownDriver" else
                 "tools/markdown")).resolve()) if isinstance(trim_path, str) else ""
            if not isinstance(trim_path, str) or not Path(trim_path).is_absolute() or \
                    not isinstance(build_command, dict) or \
                    build_command.get("cwd") != expected_cwd:
                errors.append(f"same-language {name} trimpath is not canonical")
            if build.get("mode") != "canonical" or \
                    build.get("compileOption") != \
                    f"{compile_option} --trimpath {trim_path}" or \
                    build.get("linkOption") != link_option:
                errors.append(f"same-language {name} build flags are not canonical")
            if build.get("sourceProductTreeSha256") != expected_product_tree:
                errors.append(f"same-language {name} build source identity is stale")
            expected_manifest = expected_files.get(manifest_path)
            if not is_sha256(expected_manifest) or \
                    build.get("canonicalManifestSha256") != expected_manifest or \
                    not is_sha256(build.get("effectiveManifestSha256")):
                errors.append(f"same-language {name} manifest identity is stale")
            if build.get("canonicalRootManifestSha256") != \
                    expected_files.get("cjpm.toml") or \
                    not is_sha256(build.get("effectiveRootManifestSha256")):
                errors.append(f"same-language {name} root manifest identity is stale")
            errors.extend(validate_binary_identity(build.get("binary"),
                f"same-language {name}"))
    if isinstance(builds, dict) and isinstance(drivers, dict):
        pairs = (("markdownDriver", "markdown"), ("markdownCli", "markdownCli"))
        for build_name, driver_name in pairs:
            build = builds.get(build_name)
            driver = drivers.get(driver_name)
            if not isinstance(build, dict) or not isinstance(build.get("binary"), dict) or \
                    not isinstance(driver, dict) or \
                    binary_bytes_identity(driver) != \
                    binary_bytes_identity(build["binary"]):
                errors.append(f"same-language {driver_name} digest is not bound to its build")
    return errors


def output_identity(result: dict[str, object]) -> dict[str, object]:
    return {"bytes": result["stdoutBytes"], "sha256": result["stdoutSha256"]}


def parity_record(left: dict[str, object], right: dict[str, object]) -> dict[str, object]:
    left_identity = output_identity(left)
    right_identity = output_identity(right)
    equal = left_identity == right_identity
    return {"markdown": left_identity, "markdown4cj": right_identity,
        "equalSpecHtml": equal}


def validate_output_identity(value: object, label: str) -> list[str]:
    if not isinstance(value, dict) or set(value) != {"bytes", "sha256"}:
        return [f"{label} output identity is missing"]
    errors: list[str] = []
    if not isinstance(value.get("bytes"), int) or value.get("bytes", -1) < 0:
        errors.append(f"{label} output length is invalid")
    if not is_sha256(value.get("sha256")):
        errors.append(f"{label} output digest is invalid")
    return errors


def parity_is_equal(value: object) -> bool:
    if not isinstance(value, dict):
        return False
    left = value.get("markdown")
    right = value.get("markdown4cj")
    return isinstance(left, dict) and set(left) == {"bytes", "sha256"} and \
        isinstance(right, dict) and set(right) == {"bytes", "sha256"} and \
        isinstance(left.get("bytes"), int) and left.get("bytes", -1) >= 0 and \
        is_sha256(left.get("sha256")) and left == right


def validate_parity(value: object, label: str) -> tuple[list[str], bool]:
    if not isinstance(value, dict):
        return [f"{label} semantic parity record is missing"], False
    errors = validate_output_identity(value.get("markdown"), f"{label} markdown")
    errors.extend(validate_output_identity(value.get("markdown4cj"),
        f"{label} markdown4cj"))
    equal = parity_is_equal(value)
    if value.get("equalSpecHtml") is not equal:
        errors.append(f"{label} semantic equality is not derived from digests")
    if not equal:
        errors.append(f"{label} exact spec HTML differs")
    return errors, equal


def validate_adapter_build(value: object, drivers: object,
        build_identity: object, provenance: dict[str, object] | None) -> list[str]:
    if not isinstance(value, dict):
        return ["same-language comparator adapter build identity is missing"]
    tools = build_identity.get("tools") if isinstance(build_identity, dict) else None
    cjpm = tools.get("cjpm") if isinstance(tools, dict) else None
    cjpm_path = str(cjpm.get("path", "")) if isinstance(cjpm, dict) else ""
    errors = validate_command_record(value, "same-language comparator adapter build",
        [cjpm_path, "build", "-j", "1", "-V"])
    sdk = build_identity.get("sdk") if isinstance(build_identity, dict) else None
    identity_environment = sdk.get("environment") if isinstance(sdk, dict) else None
    command_environment = identity_environment.get("variables") \
        if isinstance(identity_environment, dict) else None
    if value.get("environment") != command_environment:
        errors.append("same-language comparator adapter build environment is not attested")
    if provenance is None:
        errors.append("same-language comparator adapter source inputs are unverifiable")
    else:
        exact_fields = ("migrations", "manifestTemplateSha256",
            "driverTemplateSha256", "normalizedManifestSha256",
            "normalizedDependencyManifestSha256", "driverSha256",
            "coreSourceTreeSha256", "coreSourceFiles",
            "adaptedSourceTreeSha256", "adaptedSourceFiles",
            "adapterInputSha256")
        for field in exact_fields:
            if value.get(field) != provenance.get(field):
                errors.append(
                    f"same-language comparator adapter {field} is not derived from pinned Git objects")
        if value.get("binarySourceIdentitySha256") != \
                provenance.get("adapterInputSha256"):
            errors.append(
                "same-language comparator binary is not bound to its source inputs")
        trim_path = value.get("trimPath")
        if not isinstance(trim_path, str) or not Path(trim_path).is_absolute() or \
                value.get("cwd") != trim_path or \
                value.get("manifestSha256") != hashlib.sha256(MANIFEST.format(
                    commonmark=ADAPTER_COMMONMARK_PATH,
                    trimpath=trim_path).encode("utf-8")).hexdigest() or \
                not is_sha256(value.get("dependencyManifestSha256")):
            errors.append("same-language comparator trimpath manifest is not canonical")
    if value.get("excluded") != ["components/**", "plugin/**", "cj_res/**"] or \
            value.get("ohosImportCount") != 0:
        errors.append("same-language comparator adapter scope is not platform-neutral")
    errors.extend(validate_binary_identity(value.get("buildOutputBinary"),
        "same-language comparator adapter build output"))
    if isinstance(drivers, dict) and isinstance(value.get("binary"), dict):
        driver = drivers.get("markdown4cj")
        if not isinstance(driver, dict) or driver != value["binary"]:
            errors.append("same-language comparator binary is not bound to its build")
        if binary_bytes_identity(value.get("buildOutputBinary")) != \
                binary_bytes_identity(value["binary"]):
            errors.append(
                "same-language comparator retained binary differs from its build output")
    return errors


def validate_execution_environment(environment: object, build_identity: object,
        adapter_build: object, execution_binary_root: Path | None) -> list[str]:
    if not isinstance(environment, dict) or set(environment) != {
            "platform", "cpu", "tools", "processes"}:
        return ["same-language report does not bind its complete execution environment"]
    errors: list[str] = []
    if not isinstance(environment.get("platform"), str) or not environment["platform"] or \
            isinstance(environment.get("cpu"), bool) or \
            not isinstance(environment.get("cpu"), int):
        errors.append("same-language report does not bind its execution environment")
    sdk = build_identity.get("sdk") if isinstance(build_identity, dict) else None
    sdk_root = Path(str(sdk.get("root", ""))) if isinstance(sdk, dict) else Path("")
    if execution_binary_root is None:
        errors.append("same-language retained binary root is unavailable for environment validation")
        return errors
    retained_library_root = execution_binary_root / RUNTIME_LIBRARY_ROOT
    if not sdk_root.is_absolute() or not retained_library_root.is_absolute():
        errors.append("same-language process environment inputs are incomplete")
        return errors
    try:
        build_environment = canonical_build_environment(sdk_root, TARGET_TRIPLE)
        markdown, comparator = canonical_execution_environments(build_environment,
            retained_library_root)
        expected = execution_environment_attestation(markdown, comparator)
    except ValueError:
        errors.append("same-language process environment inputs are invalid")
        return errors
    if environment.get("processes") != expected:
        errors.append("same-language process environments are not canonical or derived")
    return errors


def validate_comparator_sources(report: dict[str, object],
        comparator_source: Path | None,
        commonmark_source: Path | None) -> tuple[list[str], dict[str, object] | None]:
    source_inputs = report.get("sourceInputs")
    if comparator_source is None and commonmark_source is None and \
            isinstance(source_inputs, dict):
        markdown4cj = source_inputs.get("markdown4cj")
        commonmark4cj = source_inputs.get("commonmark4cj")
        if isinstance(markdown4cj, str) and isinstance(commonmark4cj, str):
            comparator_source = Path(markdown4cj)
            commonmark_source = Path(commonmark4cj)
    if comparator_source is None or commonmark_source is None:
        return ["same-language verification requires explicit local comparator Git inputs"], None
    try:
        provenance, _, _ = adapter_source_inputs(comparator_source, commonmark_source)
    except (OSError, RuntimeError) as error:
        return [f"same-language pinned comparator Git objects cannot be verified: {error}"], None
    errors: list[str] = []
    if report.get("sourceRepositories") != provenance.get("repositories"):
        errors.append(
            "same-language comparator repository identities are not derived from pinned Git objects")
    return errors, provenance


def validate_report(report: dict[str, object], require_current_product: bool,
        comparator_source: Path | None = None,
        commonmark_source: Path | None = None,
        binary_root: Path | None = None,
        product_source: Path | None = None) -> list[str]:
    errors: list[str] = []
    effective_binary_root = binary_root
    binary_inputs = report.get("binaryInputs")
    execution_binary_root: Path | None = None
    if not isinstance(binary_inputs, dict) or set(binary_inputs) != {"root"} or \
            not isinstance(binary_inputs.get("root"), str) or \
            not Path(binary_inputs["root"]).is_absolute():
        errors.append("same-language recorded retained binary root is invalid")
    else:
        execution_binary_root = Path(binary_inputs["root"])
    if effective_binary_root is None and isinstance(binary_inputs, dict) and \
            isinstance(binary_inputs.get("root"), str):
        effective_binary_root = Path(binary_inputs["root"])
    if report.get("schemaVersion") != SCHEMA_VERSION:
        return [f"same-language report schemaVersion must be {SCHEMA_VERSION}; rerun the canonical benchmark"]
    if report.get("comparator") != {"url": COMPARATOR_URL, "commit": COMPARATOR_COMMIT}:
        errors.append("same-language report comparator identity is not pinned")
    if report.get("commonmark4cj") != {"url": COMMONMARK_URL, "commit": COMMONMARK_COMMIT}:
        errors.append("same-language report commonmark4cj identity is not pinned")
    expected_thresholds = {"minimumGeomeanSpeedup": MIN_SPEEDUP,
        "maximumPerCorpusRegression": MAX_REGRESSION,
        "maximumPeakRssRatio": MAX_RSS_RATIO}
    if report.get("thresholds") != expected_thresholds:
        errors.append("same-language report thresholds differ from the enforced profile")
    expected_protocol = {"workload": "CommonMark parse-only", "corpusBytes": CORPUS_BYTES,
        "iterationsPerProcess": ITERATIONS, "warmupsPerSide": 1,
        "samplesPerSide": SAMPLES,
        "order": "alternating; odd sample reverses order",
        "semanticGate": "untimed exact CommonMark spec-HTML byte length and SHA-256 from commonmark-spec-html for every corpus"}
    if report.get("protocol") != expected_protocol:
        errors.append("same-language report protocol differs from the enforced profile")
    environment = report.get("environment")
    source_errors, comparator_provenance = validate_comparator_sources(report,
        comparator_source, commonmark_source)
    errors.extend(source_errors)
    identity = report.get("identity")
    inputs = benchmark_inputs()
    expected_corpora = corpus_identity(inputs)
    identity_errors, source_snapshot = validate_repository_identity(identity,
        require_current_product, product_source)
    errors.extend(identity_errors)
    if isinstance(identity, dict) and identity.get("corpora") != expected_corpora:
        errors.append("same-language report corpus identity does not match current inputs")
    drivers = report.get("drivers")
    if not isinstance(drivers, dict) or set(drivers) != \
            {"markdown", "markdownCli", "markdown4cj"}:
        errors.append("same-language driver identities are incomplete")
    errors.extend(validate_retained_binaries(report, effective_binary_root))
    build_identity = report.get("buildIdentity")
    errors.extend(validate_build_identity(build_identity, drivers, source_snapshot))
    if isinstance(environment, dict) and isinstance(build_identity, dict) and \
            environment.get("tools") != build_identity.get("tools"):
        errors.append("same-language environment tools are not bound to the build identity")
    adapter_build = report.get("adapterBuild")
    errors.extend(validate_adapter_build(adapter_build, drivers, build_identity,
        comparator_provenance))
    errors.extend(validate_execution_environment(environment, build_identity,
        adapter_build, execution_binary_root))
    shared = report.get("sharedBehavior")
    behavior_equal: list[bool] = []
    if not isinstance(shared, dict) or not isinstance(shared.get("cases"), dict) or \
            set(shared["cases"]) != set(BEHAVIOR_CASES):
        errors.append("same-language shared behavior cases are incomplete")
    else:
        for name, source_text in BEHAVIOR_CASES.items():
            case = shared["cases"][name]
            source_bytes = source_text.encode("utf-8")
            if not isinstance(case, dict) or case.get("sourceBytes") != len(source_bytes) or \
                    case.get("sourceSha256") != hashlib.sha256(source_bytes).hexdigest():
                errors.append(f"same-language shared behavior source is stale: {name}")
                behavior_equal.append(False)
                continue
            parity_errors, equal = validate_parity(case.get("specHtml"),
                f"same-language shared behavior {name}")
            errors.extend(parity_errors)
            behavior_equal.append(equal)
    derived_behavior_pass = len(behavior_equal) == len(BEHAVIOR_CASES) and all(behavior_equal)
    behavior_pass = isinstance(shared, dict) and \
        shared.get("caseCount") == len(BEHAVIOR_CASES) and \
        shared.get("passCount") == sum(behavior_equal) and \
        shared.get("pass") is derived_behavior_pass and derived_behavior_pass
    if not behavior_pass:
        errors.append("same-language shared behavior gate did not pass")
    corpus_semantics = report.get("corpusSemantics")
    corpus_equal: list[bool] = []
    if not isinstance(corpus_semantics, dict) or set(corpus_semantics) != set(inputs):
        errors.append("same-language timed corpus semantic records are incomplete")
    else:
        for name, data in inputs.items():
            semantic = corpus_semantics[name]
            if not isinstance(semantic, dict) or semantic.get("sourceBytes") != len(data) or \
                    semantic.get("sourceSha256") != hashlib.sha256(data).hexdigest():
                errors.append(f"same-language timed corpus semantic source is stale: {name}")
                corpus_equal.append(False)
                continue
            parity_errors, equal = validate_parity(semantic.get("specHtml"),
                f"same-language timed corpus {name}")
            errors.extend(parity_errors)
            corpus_equal.append(equal)
    corpus_semantics_pass = len(corpus_equal) == len(inputs) and all(corpus_equal)
    rows = report.get("corpora")
    speedups: list[float] = []
    rss_ratios: list[float] = []
    if not isinstance(rows, dict) or set(rows) != set(inputs):
        errors.append("same-language report corpus rows are incomplete")
    else:
        for name, data in inputs.items():
            row = rows[name]
            if not isinstance(row, dict) or row.get("bytes") != len(data):
                errors.append(f"same-language corpus metadata is invalid: {name}")
                continue
            left = row.get("markdown")
            right = row.get("markdown4cj")
            if not isinstance(left, list) or not isinstance(right, list) or \
                    len(left) != SAMPLES or len(right) != SAMPLES:
                errors.append(f"same-language samples are incomplete: {name}")
                continue
            try:
                for samples in (left, right):
                    if not all(not isinstance(sample.get("seconds"), bool) and
                            isinstance(sample.get("seconds"), (int, float)) and
                            not isinstance(sample.get("peakRssKiB"), bool) and
                            isinstance(sample.get("peakRssKiB"), int)
                            for sample in samples):
                        raise TypeError("sample metrics are not numeric")
                left_seconds = [float(sample["seconds"]) for sample in left]
                right_seconds = [float(sample["seconds"]) for sample in right]
                left_rss = [int(sample["peakRssKiB"]) for sample in left]
                right_rss = [int(sample["peakRssKiB"]) for sample in right]
                for side, samples in (("markdown", left), ("markdown4cj", right)):
                    for sample in samples:
                        stdout = sample["stdout"]
                        if not isinstance(stdout, str):
                            raise TypeError("stdout is not UTF-8 text")
                        encoded = stdout.encode("utf-8")
                        if sample.get("stdoutBytes") != len(encoded) or \
                                sample.get("stdoutSha256") != hashlib.sha256(encoded).hexdigest():
                            errors.append(f"same-language {side} output digest is not derived: {name}")
                left_outputs = {(str(sample["stdout"]), int(sample["stdoutBytes"]),
                    str(sample["stdoutSha256"])) for sample in left}
                right_outputs = {(str(sample["stdout"]), int(sample["stdoutBytes"]),
                    str(sample["stdoutSha256"])) for sample in right}
            except (KeyError, TypeError, ValueError):
                errors.append(f"same-language samples are malformed: {name}")
                continue
            if not all(math.isfinite(value) for value in left_seconds + right_seconds) or \
                    min(left_seconds + right_seconds) <= 0 or \
                    min(left_rss + right_rss) <= 0:
                errors.append(f"same-language samples contain invalid values: {name}")
                continue
            if len(left_outputs) != 1 or len(right_outputs) != 1:
                errors.append(f"same-language output is unstable across samples: {name}")
                continue
            left_median = statistics.median(left_seconds)
            right_median = statistics.median(right_seconds)
            speedup = right_median / left_median
            rss_ratio = max(left_rss) / max(max(right_rss), 1)
            if not close_number(row.get("markdownMedianSeconds"), left_median):
                errors.append(f"same-language markdown median is not derived: {name}")
            if not close_number(row.get("markdown4cjMedianSeconds"), right_median):
                errors.append(f"same-language markdown4cj median is not derived: {name}")
            if not close_number(row.get("markdownSpeedup"), speedup):
                errors.append(f"same-language speedup is not derived: {name}")
            if not close_number(row.get("peakRssRatio"), rss_ratio):
                errors.append(f"same-language RSS ratio is not derived: {name}")
            speedups.append(speedup)
            rss_ratios.append(rss_ratio)
    if speedups:
        geomean = math.exp(statistics.mean(math.log(value) for value in speedups))
        promoted = behavior_pass and corpus_semantics_pass and geomean >= MIN_SPEEDUP and \
            min(speedups) >= 1 / MAX_REGRESSION and max(rss_ratios) <= MAX_RSS_RATIO
        if not close_number(report.get("geomeanMarkdownSpeedup"), geomean):
            errors.append("same-language geometric mean is not derived from samples")
        if report.get("promotionPassed") is not promoted:
            errors.append("same-language promotion result is not derived from samples")
        expected_status = "PASS" if promoted else "MEASURED_NOT_PROMOTED"
        if report.get("status") != expected_status:
            errors.append("same-language status is not derived from samples")
    return errors


def render_markdown(report: dict[str, object]) -> str:
    identity = report["identity"]
    environment = report["environment"]
    runtime = environment["processes"]["markdown"]["variables"]
    rows = report["corpora"]
    speedups = [float(row["markdownSpeedup"]) for row in rows.values()]
    rss_ratios = [float(row["peakRssRatio"]) for row in rows.values()]
    cjc = str(environment["tools"]["cjc"]["stdout"]).strip().splitlines()[0]
    table = "\n".join(
        f"| {name} | {float(row['markdownSpeedup']):.2f}× | {float(row['peakRssRatio']):.3f}× |"
        for name, row in rows.items()
    )
    return f"""# markdown4cj 同语言解析性能对比

状态：**{report['status']}（CommonMark parse-only）**

## 对比边界

- 产品提交：`{identity['repositoryCommit']}`，Git tree `{identity['gitTree']}`。
- `markdown4cj` 固定提交 `{COMPARATOR_COMMIT}`。
- `commonmark4cj` 固定提交 `{COMMONMARK_COMMIT}`，用于当前 SDK adapter。
- SDK：`{cjc}`。
- 只构建 `markdown4cj/src/core/**`。不构建 OHOS UI、DevEco、prism4cj 或 formula-ffi。
- 两侧都生成 AST；本报告不把 event parser 或 fused renderer 当作 `parse()`。

这不是 HTML renderer 性能对比。HTML 只在计时区间外作为逐语料语义门禁；性能结论
只适用于共同的 CommonMark parse-only 子集。

## 测量协议

- 同一主机、同一 SDK、release `-O2`、固定 CPU {environment['cpu']}。
- 两侧显式使用 `cjHeapSize={runtime['cjHeapSize']}`、
  `cjGCInterval={runtime['cjGCInterval']}`、`LC_ALL={runtime['LC_ALL']}` 和
  `TZ={runtime['TZ']}`。子进程不继承主机环境。
- 两侧环境的唯一差异是 comparator 的 `LD_LIBRARY_PATH` 增加 retained binary root 的
  `libraries/commonmark4cj` 目录。raw report 记录并校验该差异。
- 11 个确定性语料，每个 256 KiB；每进程解析 {report['protocol']['iterationsPerProcess']} 次。
- 每侧预热 1 次，再取 {SAMPLES} 个交替样本；奇数轮反转顺序。
- 12 个共享 CommonMark 用例以及每个被计时语料的 spec-HTML 摘要和长度必须一致；
  语义检查在计时区间外执行。
- 门槛：几何平均至少 `{MIN_SPEEDUP:.2f}×`，单语料不得回退超过
  `{(MAX_REGRESSION - 1) * 100:.0f}%`，峰值 RSS 不得超过 comparator 的
  `{MAX_RSS_RATIO:.2f}×`。

## 当前结果

大于 `1×` 表示 `markdown` 更快。

| 语料 | parse 加速 | 峰值 RSS 比值 |
| --- | ---: | ---: |
{table}
| **几何平均** | **{float(report['geomeanMarkdownSpeedup']):.2f}×** | — |

11 个语料的最小加速为 `{min(speedups):.2f}×`。最大峰值 RSS 比值为
`{max(rss_ratios):.3f}×`。共享行为用例为
`{report['sharedBehavior']['passCount']}/{report['sharedBehavior']['caseCount']}`。

## 合入门禁

GitHub Actions 的 `Same-language benchmark (current-1.1.3)` job 对每个 push 和 PR
重新构建两侧 driver，并重新计算全部统计量。`main` 将该 job 设为 required check。

运行以下命令可以复现同一 harness：

```sh
unset LD_PRELOAD LD_LIBRARY_PATH LIBRARY_PATH
unset MARKDOWN_NATIVE_ARFLAGS MARKDOWN_NATIVE_CFLAGS TARGET
unset cjHeapSize cjGCInterval
CC=clang AR=ar python3 scripts/build_native_scanner.py \\
  --enable --target {TARGET_TRIPLE}
python3 scripts/build_benchmark_driver.py --mode canonical --build-cli \\
  --identity-output /tmp/markdown-build-identity.json \\
  --sdk-url '{SDK_URL}' --sdk-sha256 {SDK_SHA256} \\
  --sdk-archive /path/to/cangjie-sdk.tar.gz \\
  --sdk-extract-dir /tmp/fresh-cangjie-sdk-verified \\
  --target {TARGET_TRIPLE}
python3 benchmarks/compare_markdown4cj.py \\
  --tools-root /tmp/markdown-same-language-tools \\
  --workspace /tmp/fresh-markdown4cj-adapter \\
  --binary-root /tmp/markdown4cj-retained-binaries \\
  --build-identity /tmp/markdown-build-identity.json \\
  --output /tmp/markdown4cj-comparison.json

python3 benchmarks/compare_markdown4cj.py \\
  --source /tmp/markdown-same-language-tools/markdown4cj \\
  --commonmark4cj-source /tmp/markdown-same-language-tools/commonmark4cj \\
  --product-source /tmp/markdown-product.bundle \\
  --binary-root /tmp/markdown4cj-retained-binaries \\
  --sdk-archive /path/to/cangjie-sdk.tar.gz \\
  --verify-report /tmp/markdown4cj-comparison.json \\
  --require-current-product
```

验证器不会信任 raw report 中的 preflight 布尔值或 source-tree 摘要。上述三个显式
Git 输入可以是 checkout、bare object store 或 bundle；验证器从固定 commit 的 objects
重新计算产品 commit、tree、product tree、harness blobs，并从 comparator commits
重新计算两侧 tree、完整 `commonmark4cj` 依赖内容、选择的 core blobs、迁移结果、driver
与 manifest。它还从 `--binary-root` 读取测量实际执行的三份 binary，并重新解析
comparator adapter-owned ELF `PT_DYNAMIC`/`DT_NEEDED` 闭包。验证器读取 loader 使用的
program headers，不信任可独立分歧的 section table，并拒绝 `DT_RPATH`/`DT_RUNPATH`。
当前固定 adapter 只需 `libcommonmark4cj.commonmark.so`；未链接的 base、table 和 strikethrough DSO 不会被盲目
保留。验证器重新计算每个 artifact 的相对路径、长度、SHA-256 与 mode，并与 retained、
adapter build 和 build output 三方核对。缺少、额外、交换、symlink、路径逃逸、mode 或
bytes 漂移都会导致验证失败。最后，验证器从 retained Git objects、SDK archive 和
attested native tools 在全新目录重建三份 executable 与 runtime DSO closure，并逐字节
比较 measured artifacts。同步修改 binary 与 raw digest 不能绕过该检查。

原始样本、身份和派生统计见
[`markdown4cj-comparison-raw.json`](markdown4cj-comparison-raw.json)。
"""


def preflight(source: Path, expected: str) -> dict[str, object]:
    try:
        object_format = git_object_format(source)
        head = resolve_git_commit(source, "HEAD", object_format)
        status = git_bytes(source, "status", "--porcelain=v1", "--untracked-files=all")
    except (OSError, RuntimeError):
        return {"head": "", "headMatches": False, "clean": False}
    return {"head": head, "headMatches": head == expected, "clean": not status}


def attested_sdk_environment(build_identity: dict[str, object]) -> tuple[Path, dict[str, str]]:
    sdk = build_identity.get("sdk")
    tools = build_identity.get("tools")
    if not isinstance(sdk, dict) or not isinstance(tools, dict):
        raise RuntimeError("attested SDK identity is incomplete")
    archive = Path(str(sdk.get("archivePath", "")))
    if not archive.is_file() or archive.stat().st_size != sdk.get("archiveBytes") or \
            sha256(archive) != sdk.get("archiveSha256"):
        raise RuntimeError("attested SDK archive changed after the product build")
    envsetup = Path(str(sdk.get("root", ""))) / "envsetup.sh"
    if not envsetup.is_file() or sha256(envsetup) != sdk.get("envsetupSha256"):
        raise RuntimeError("attested SDK environment setup changed after extraction")
    cjpm = tools.get("cjpm")
    cjc = tools.get("cjc")
    if not isinstance(cjpm, dict) or not isinstance(cjc, dict):
        raise RuntimeError("attested SDK tools are incomplete")
    for name, record in (("cjpm", cjpm), ("cjc", cjc)):
        path = Path(str(record.get("path", "")))
        if not path.is_file() or path.stat().st_size != record.get("bytes") or \
                sha256(path) != record.get("sha256"):
            raise RuntimeError(f"attested SDK {name} changed after the product build")
    identity_environment = sdk.get("environment")
    if not isinstance(identity_environment, dict):
        raise RuntimeError("attested SDK environment is incomplete")
    root = Path(str(sdk.get("root", "")))
    environment = canonical_build_environment(root, TARGET_TRIPLE)
    if identity_environment != build_environment_attestation(environment):
        raise RuntimeError("attested SDK environment is not canonical")
    for name in ("HOME", "TMPDIR"):
        path = Path(environment[name])
        if not path.is_dir():
            raise RuntimeError(f"attested SDK {name} directory is unavailable")
    if Path(shutil.which("cjpm", path=environment["PATH"]) or "").resolve() != \
            Path(str(cjpm["path"])).resolve() or \
            Path(shutil.which("cjc", path=environment["PATH"]) or "").resolve() != \
            Path(str(cjc["path"])).resolve():
        raise RuntimeError("attested SDK tools are shadowed during comparator build")
    return Path(str(cjpm["path"])), environment


def build_adapter(source: Path, commonmark: Path, workspace: Path, cjpm: Path,
        environment: dict[str, str]) -> tuple[Path, dict[str, object]]:
    provenance, adapted, commonmark_contents = adapter_source_inputs(source,
        commonmark)
    workspace.mkdir(parents=True, exist_ok=False)
    target = workspace / "src/core"
    write_source_files(target, adapted)
    write_source_files(workspace / ADAPTER_COMMONMARK_PATH, commonmark_contents)
    (workspace / "cjpm.toml").write_text(MANIFEST.format(
        commonmark=ADAPTER_COMMONMARK_PATH, trimpath=str(workspace.resolve())),
        encoding="utf-8")
    (workspace / "src/main.cj").write_text(DRIVER, encoding="utf-8")
    dependency_manifest_path = workspace / ADAPTER_COMMONMARK_PATH / "cjpm.toml"
    dependency_manifest_path.write_bytes(adapter_dependency_manifest(
        dependency_manifest_path.read_bytes(), str(workspace.resolve())))
    build = command([str(cjpm), "build", "-j", "1", "-V"], workspace, environment)
    build.update({key: value for key, value in provenance.items()
                  if key != "repositories"})
    build.update({"binarySourceIdentitySha256": provenance["adapterInputSha256"],
                  "excluded": ["components/**", "plugin/**", "cj_res/**"],
                  "ohosImportCount": sum(path.read_text(encoding="utf-8").count("ohos.")
                      for path in target.rglob("*.cj")),
                  "trimPath": str(workspace.resolve()),
                  "manifestSha256": sha256(workspace / "cjpm.toml"),
                  "dependencyManifestSha256": sha256(dependency_manifest_path),
                  "driverSha256": sha256(workspace / "src/main.cj")})
    binary = workspace / "target/release/bin/main"
    if build["exitCode"] != 0 or not binary.is_file() or build["ohosImportCount"] != 0:
        raise RuntimeError("current-SDK markdown4cj core adapter failed")
    build["binary"] = {"path": str(binary.resolve()), "bytes": binary.stat().st_size,
        "sha256": sha256(binary)}
    runtime_libraries = adapter_runtime_library_sources(binary,
        workspace / "target/release/commonmark4cj", allow_static=True)
    for path in runtime_libraries.values():
        path.chmod(0o644)
    build["buildOutputRuntimeLibraries"] = {name: build_output_library_identity(path)
        for name, path in runtime_libraries.items()}
    return binary, build


def run(command_line: list[str], data: bytes, cpu: int, environment: dict[str, str],
        timeout_seconds: float = RUN_TIMEOUT_SECONDS) -> dict[str, object]:
    if not math.isfinite(timeout_seconds) or timeout_seconds <= 0:
        raise ValueError("driver timeout must be a positive finite number")
    controlled_environment = exact_environment(environment,
        EXECUTION_ENVIRONMENT_KEYS, "benchmark execution")
    required = {
        "LANG": CANONICAL_LOCALE,
        "LC_ALL": CANONICAL_LOCALE,
        "TZ": CANONICAL_TIMEZONE,
        "cjHeapSize": CANGJIE_HEAP_SIZE,
        "cjGCInterval": CANGJIE_GC_INTERVAL,
    }
    if any(controlled_environment.get(name) != value
            for name, value in required.items()):
        raise ValueError("benchmark execution environment has noncanonical runtime controls")
    started = time.perf_counter_ns()
    command = ["taskset", "-c", str(cpu), *command_line]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=controlled_environment, start_new_session=True)
    completed: list[tuple[bytes, bytes]] = []
    communication_errors: list[Exception] = []

    def communicate() -> None:
        try:
            completed.append(process.communicate(input=data))
        except Exception as error:  # Preserve unexpected pipe failures after cleanup.
            communication_errors.append(error)

    def kill_process_group() -> None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    worker = threading.Thread(target=communicate, name="markdown-benchmark-pipes")
    try:
        worker.start()
    except BaseException:
        kill_process_group()
        process.wait()
        raise
    peak = 0
    deadline = time.monotonic() + timeout_seconds
    timed_out = False
    try:
        while worker.is_alive():
            try:
                for line in Path(f"/proc/{process.pid}/status").read_text().splitlines():
                    if line.startswith("VmRSS:"):
                        peak = max(peak, int(line.split()[1]))
                        break
            except OSError:
                # The process may disappear between the procfs lookup and the
                # status read. Linux reports that race as ENOENT or ESRCH,
                # depending on where the task exits.
                pass
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                worker.join(0)
                if not worker.is_alive():
                    break
                timed_out = True
                kill_process_group()
                break
            worker.join(min(0.002, remaining))
    except BaseException:
        kill_process_group()
        worker.join()
        raise
    worker.join()
    if communication_errors:
        kill_process_group()
        process.wait()
        raise communication_errors[0]
    if len(completed) != 1:
        raise RuntimeError("driver pipe collection did not complete")
    stdout, stderr = completed[0]
    if timed_out:
        raise subprocess.TimeoutExpired(command, timeout_seconds, output=stdout, stderr=stderr)
    if process.returncode != 0:
        raise RuntimeError(f"driver failed ({process.returncode}): {stderr.decode(errors='replace')}")
    return {"seconds": (time.perf_counter_ns() - started) / 1e9, "peakRssKiB": peak,
            "stdout": stdout.decode("utf-8"), "stdoutBytes": len(stdout),
            "stdoutSha256": hashlib.sha256(stdout).hexdigest()}


def spec_html_parity(ours: Path, theirs: Path, data: bytes, cpu: int,
        left_env: dict[str, str], right_env: dict[str, str]) -> dict[str, object]:
    left = run([str(ours), "render", "--to", "spec-html", "--profile",
        "commonmark-0.31.2"], data, cpu, left_env)
    right = run([str(theirs), "render", "1"], data, cpu, right_env)
    return parity_record(left, right)


def benchmark_spec_html_parity(ours: Path, theirs: Path, data: bytes, cpu: int,
        left_env: dict[str, str], right_env: dict[str, str]) -> dict[str, object]:
    left = run([str(ours), "commonmark-spec-html", "1"], data, cpu, left_env)
    right = run([str(theirs), "render", "1"], data, cpu, right_env)
    return parity_record(left, right)


def behavior(ours: Path, theirs: Path, cpu: int, left_env: dict[str, str],
        right_env: dict[str, str]) -> dict[str, object]:
    rows = {}
    for name, source in BEHAVIOR_CASES.items():
        data = source.encode("utf-8")
        parity = spec_html_parity(ours, theirs, data, cpu, left_env, right_env)
        rows[name] = {"sourceBytes": len(data),
            "sourceSha256": hashlib.sha256(data).hexdigest(), "specHtml": parity}
    equal = [parity_is_equal(row["specHtml"]) for row in rows.values()]
    return {"caseCount": len(rows), "passCount": sum(equal),
            "pass": all(equal), "cases": rows}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--commonmark4cj-source", type=Path)
    parser.add_argument("--tools-root", type=Path,
        help="directory in which pinned comparator checkouts are prepared")
    parser.add_argument("--workspace", type=Path, help="fresh non-existing adapter directory")
    parser.add_argument("--binary-root", type=Path,
        help="fresh measurement output or retained verification binary directory")
    parser.add_argument("--product-source", type=Path,
        help="retained product Git checkout, bare object store, or bundle")
    parser.add_argument("--sdk-archive", type=Path,
        help="retained SDK archive used to reproducibly rebuild measured binaries")
    parser.add_argument("--markdown-driver", type=Path,
        default=Path(__file__).parent / "driver/target/release/bin/main")
    parser.add_argument("--markdown-cli", type=Path,
        default=Path(__file__).parents[1] / "tools/markdown/target/release/bin/main")
    parser.add_argument("--build-identity", type=Path,
        default=Path(__file__).parents[1] / "target/same-language-benchmark-build-identity.json")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--markdown-report", type=Path)
    parser.add_argument("--cpu", type=int,
        help="pinned CPU; defaults to the first CPU in the process affinity set")
    parser.add_argument("--iterations", type=int, default=ITERATIONS)
    parser.add_argument("--verify-report", type=Path)
    parser.add_argument("--require-current-product", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = arguments()
    if args.verify_report is not None:
        try:
            source, commonmark = resolve_verification_sources(args)
            binary_root = resolve_verification_binary_root(args)
            product_source = resolve_verification_product_source(args)
            sdk_archive = getattr(args, "sdk_archive", None)
            if sdk_archive is None:
                raise ValueError("report verification requires --sdk-archive")
            report = json.loads(args.verify_report.read_text(encoding="utf-8"))
        except (OSError, ValueError, json.JSONDecodeError) as error:
            print(str(error), file=sys.stderr)
            return 2
        errors = validate_report(report, args.require_current_product,
            source, commonmark, binary_root, product_source)
        if not errors:
            errors.extend(verify_reproducible_binaries(report, binary_root,
                product_source, source, commonmark, sdk_archive))
        if args.markdown_report is not None and not errors:
            expected = render_markdown(report)
            if not args.markdown_report.is_file() or \
                    args.markdown_report.read_text(encoding="utf-8") != expected:
                errors.append("same-language Markdown report is not generated from raw data")
        if errors:
            print("\n".join(errors), file=sys.stderr)
            return 1
        print("same-language benchmark report verified")
        return 0
    if args.output is None or args.workspace is None or args.binary_root is None:
        print("measurement requires --output, --workspace and --binary-root", file=sys.stderr)
        return 2
    if args.iterations != ITERATIONS:
        print(f"--iterations is fixed at {ITERATIONS} by the canonical protocol",
              file=sys.stderr)
        return 2
    try:
        reject_ambient_benchmark_environment(dict(os.environ))
        source, commonmark = resolve_sources(args)
        cpu = resolve_cpu(args.cpu)
        inputs = benchmark_inputs()
        identity = repository_identity()
        source_snapshot = git_repository_snapshot(ROOT, identity["repositoryRef"])
        identity["corpora"] = corpus_identity(inputs)
        build_identity = json.loads(args.build_identity.read_text(encoding="utf-8"))
        comparator_provenance, _, _ = adapter_source_inputs(source, commonmark)
        binary_root = args.binary_root.resolve()
        if binary_root.exists():
            raise RuntimeError(f"retained binary root already exists: {binary_root}")
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 2
    report: dict[str, object] = {"schemaVersion": SCHEMA_VERSION, "status": "BLOCKED",
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "identity": identity,
        "buildIdentity": build_identity,
        "sourceInputs": {"markdown4cj": str(source.resolve()),
            "commonmark4cj": str(commonmark.resolve())},
        "binaryInputs": {"root": str(binary_root)},
        "sourceRepositories": comparator_provenance["repositories"],
        "comparator": {"url": COMPARATOR_URL, "commit": COMPARATOR_COMMIT},
        "commonmark4cj": {"url": COMMONMARK_URL, "commit": COMMONMARK_COMMIT},
        "thresholds": {"minimumGeomeanSpeedup": MIN_SPEEDUP,
            "maximumPerCorpusRegression": MAX_REGRESSION,
            "maximumPeakRssRatio": MAX_RSS_RATIO},
        "environment": {"platform": platform.platform(), "cpu": cpu,
            "tools": build_identity.get("tools") if isinstance(build_identity, dict) else None},
        "protocol": {"workload": "CommonMark parse-only", "corpusBytes": CORPUS_BYTES,
            "iterationsPerProcess": args.iterations, "warmupsPerSide": 1,
            "samplesPerSide": SAMPLES,
            "order": "alternating; odd sample reverses order",
            "semanticGate": "untimed exact CommonMark spec-HTML byte length and SHA-256 from commonmark-spec-html for every corpus"}}
    ours, cli = args.markdown_driver.resolve(), args.markdown_cli.resolve()
    if not ours.is_file() or not cli.is_file():
        report["reason"] = "build benchmarks/driver and tools/markdown first"
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    product_outputs = {
        "markdown": {"path": str(ours), "bytes": ours.stat().st_size, "sha256": sha256(ours)},
        "markdownCli": {"path": str(cli), "bytes": cli.stat().st_size, "sha256": sha256(cli)},
    }
    build_errors = validate_build_identity(build_identity, product_outputs,
        source_snapshot)
    if build_errors:
        report["reason"] = "; ".join(build_errors)
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    try:
        cjpm, sdk_environment = attested_sdk_environment(build_identity)
        theirs, build = build_adapter(source, commonmark, args.workspace.resolve(), cjpm,
            sdk_environment)
    except Exception as error:
        report["reason"] = str(error)
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    try:
        runtime_sources = adapter_runtime_library_sources(theirs,
            args.workspace.resolve() / "target/release/commonmark4cj",
            allow_static=True)
        drivers, runtime_libraries = retain_execution_binaries(binary_root,
            {"markdown": ours, "markdownCli": cli, "markdown4cj": theirs},
            runtime_sources)
        native_tools, native_resource, native_runtime = retain_native_tools(
            binary_root, build_identity)
    except Exception as error:
        report["reason"] = str(error)
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 2
    build["buildOutputBinary"] = build["binary"]
    build["binary"] = drivers["markdown4cj"]
    build["runtimeLibraries"] = runtime_libraries
    report["adapterBuild"] = build
    report["drivers"] = drivers
    report["runtimeLibraries"] = runtime_libraries
    report["nativeTools"] = native_tools
    report["nativeCompilerResource"] = native_resource
    report["nativeToolRuntime"] = native_runtime
    ours = binary_root / BINARY_ARTIFACTS["markdown"]
    cli = binary_root / BINARY_ARTIFACTS["markdownCli"]
    theirs = binary_root / BINARY_ARTIFACTS["markdown4cj"]
    left_env, right_env = canonical_execution_environments(sdk_environment,
        binary_root / RUNTIME_LIBRARY_ROOT)
    report["environment"]["processes"] = execution_environment_attestation(
        left_env, right_env)
    report["sharedBehavior"] = behavior(cli, theirs, cpu, left_env, right_env)
    if not report["sharedBehavior"]["pass"]:
        report["reason"] = "shared CommonMark exact spec-HTML behavior mismatch"
        report["status"] = "SEMANTIC_MISMATCH"
        report["promotionPassed"] = False
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 1
    corpus_semantics = {}
    for name, data in inputs.items():
        corpus_semantics[name] = {"sourceBytes": len(data),
            "sourceSha256": hashlib.sha256(data).hexdigest(),
            "specHtml": benchmark_spec_html_parity(
                ours, theirs, data, cpu, left_env, right_env)}
    report["corpusSemantics"] = corpus_semantics
    if not all(parity_is_equal(value["specHtml"])
            for value in corpus_semantics.values()):
        report["reason"] = "timed corpus exact spec-HTML behavior mismatch"
        report["status"] = "SEMANTIC_MISMATCH"
        report["promotionPassed"] = False
        atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return 1
    rows, ratios = {}, []
    for name, data in inputs.items():
        left_command = [str(ours), "commonmark-parse", str(args.iterations)]
        right_command = [str(theirs), "parse", str(args.iterations)]
        run(left_command, data, cpu, left_env)
        run(right_command, data, cpu, right_env)
        left_values, right_values = [], []
        for index in range(SAMPLES):
            order = ((left_command, left_env, left_values), (right_command, right_env, right_values))
            if index % 2:
                order = ((right_command, right_env, right_values), (left_command, left_env, left_values))
            for command_line, environment, destination in order:
                destination.append(run(command_line, data, cpu, environment))
        left_median = statistics.median(row["seconds"] for row in left_values)
        right_median = statistics.median(row["seconds"] for row in right_values)
        speedup = right_median / left_median
        rss_ratio = max(row["peakRssKiB"] for row in left_values) / max(max(row["peakRssKiB"] for row in right_values), 1)
        ratios.append(speedup)
        rows[name] = {"bytes": len(data), "markdown": left_values, "markdown4cj": right_values,
                      "markdownMedianSeconds": left_median, "markdown4cjMedianSeconds": right_median,
                      "markdownSpeedup": speedup, "peakRssRatio": rss_ratio}
    geomean = math.exp(statistics.mean(math.log(value) for value in ratios))
    promoted = report["sharedBehavior"]["pass"] and all(parity_is_equal(
        value["specHtml"]) for value in corpus_semantics.values()) and \
        geomean >= MIN_SPEEDUP and min(ratios) >= 1 / MAX_REGRESSION and max(
        row["peakRssRatio"] for row in rows.values()) <= MAX_RSS_RATIO
    report.update({"status": "PASS" if promoted else "MEASURED_NOT_PROMOTED",
        "corpora": rows,
        "geomeanMarkdownSpeedup": geomean, "promotionPassed": promoted})
    errors = validate_report(report, True, source, commonmark, binary_root, ROOT)
    report["derivationErrors"] = errors
    if errors:
        report["status"] = "INVALID"
        report["promotionPassed"] = False
    atomic_write(args.output, json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    if args.markdown_report is not None and not errors:
        atomic_write(args.markdown_report, render_markdown(report))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 2
    return 0 if promoted else 1


if __name__ == "__main__":
    raise SystemExit(main())
