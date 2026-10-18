"""Retain Linux startup objects and libraries for the SDK's fixed LLD linker."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shlex
import stat
import subprocess
import tempfile

SCHEMA_VERSION = 1
MAX_FILES = 128
MAX_BYTES = 128 * 1024**2
SCRIPT_WORDS = {"OUTPUT_FORMAT", "GROUP", "AS_NEEDED", "INPUT", "elf64-x86-64"}
SDK_CPP_ROOT = PurePosixPath("usr/lib/markdown-sdk-runtime")
SDK_CPP_LIBRARIES = ("libstdc++.so.6", "libgcc_s.so.1")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_digest(value: object) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True,
        separators=(",", ":")).encode()).hexdigest()


def script_references(data: bytes) -> list[str]:
    if data.startswith(b"\x7fELF") or data.startswith(b"!<arch>\n"):
        return []
    text = re.sub(r"/\*.*?\*/", "", data.decode("ascii"), flags=re.S)
    tokens = re.findall(r"/[^\s();]+|-l[^\s();]+|[A-Za-z0-9_.+-]+|[();]", text)
    if re.sub(r"\s+", "", "".join(tokens)) != re.sub(r"\s+", "", text):
        raise ValueError("unsupported system linker script syntax")
    references = []
    depth = 0
    for token in tokens:
        if token == "(":
            depth += 1
        elif token == ")":
            depth -= 1
        elif token.startswith("/"):
            validate_relative_path(token[1:])
            references.append(token)
        elif token.startswith("-l"):
            if not re.fullmatch(r"-l:?[A-Za-z0-9_.+-]+", token):
                raise ValueError("invalid system linker script library")
            references.append(token)
        elif token not in SCRIPT_WORDS and token != ";":
            raise ValueError("unsupported system linker script directive")
        if depth < 0:
            raise ValueError("unbalanced system linker script")
    if depth:
        raise ValueError("unbalanced system linker script")
    return references


def validate_relative_path(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or "\\" in value or \
            str(path) != value or not re.fullmatch(r"(?:usr/)?lib(?:64)?/.+", value):
        raise ValueError("system link input is outside library directories")
    return path


def inventory(root: Path) -> dict[str, dict]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("system link input root must be a real directory")
    files = {}
    total = 0
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("retained system link input must not be a symlink")
        if path.is_dir():
            continue
        relative = path.relative_to(root).as_posix()
        validate_relative_path(relative)
        if not path.is_file():
            raise ValueError("retained system link input is not a regular file")
        total += path.stat().st_size
        if len(files) >= MAX_FILES or total > MAX_BYTES:
            raise ValueError("retained system link inputs exceed limits")
        files[relative] = {"sha256": digest(path), "bytes": path.stat().st_size,
            "mode": stat.S_IMODE(path.stat().st_mode)}
    if not files:
        raise ValueError("retained system link inputs are empty")
    return files


def validate_identity(identity: dict) -> dict:
    if not isinstance(identity, dict) or set(identity) != {
        "schemaVersion", "target", "files", "libraryDirectories", "treeSha256",
    } or type(identity["schemaVersion"]) is not int or identity["schemaVersion"] != SCHEMA_VERSION or \
            identity["target"] != "x86_64-unknown-linux-gnu":
        raise ValueError("unsupported system link input identity")
    files = identity["files"]
    if not isinstance(files, dict) or not 0 < len(files) <= MAX_FILES:
        raise ValueError("invalid system link input file set")
    total = 0
    for relative, value in files.items():
        if not isinstance(relative, str):
            raise ValueError("invalid system link input path")
        validate_relative_path(relative)
        if not isinstance(value, dict) or set(value) != {"sha256", "bytes", "mode"} or \
                type(value["bytes"]) is not int or value["bytes"] < 0 or \
                value["mode"] != 0o644 or not isinstance(value["sha256"], str) or \
                not re.fullmatch(r"[0-9a-f]{64}", value["sha256"]):
            raise ValueError("invalid system link input file identity")
        total += value["bytes"]
    if total > MAX_BYTES or canonical_digest(files) != identity["treeSha256"]:
        raise ValueError("invalid system link input tree identity")
    directories = identity["libraryDirectories"]
    if not isinstance(directories, list) or not directories or \
            any(not isinstance(value, str) for value in directories) or \
            directories != sorted(set(directories)):
        raise ValueError("invalid system link library directories")
    for directory in directories:
        validate_relative_path(directory + "/input")
    if directories != sorted({str(PurePosixPath(value).parent) for value in files}):
        raise ValueError("system link library directories are not derived")
    return identity


def validate_inputs(root: Path, identity: dict) -> dict:
    validate_identity(identity)
    actual = inventory(root)
    if actual != identity["files"]:
        raise ValueError("retained system link input identity differs")
    directories = identity["libraryDirectories"]
    for relative in actual:
        for reference in script_references((root / relative).read_bytes()):
            if reference.startswith("/"):
                if reference[1:] not in actual:
                    raise ValueError("system linker script references an unretained input")
            else:
                library_file(reference, [root / value for value in directories])
    return identity


def library_file(option: str, directories: list[Path]) -> Path:
    names = [option[3:]] if option.startswith("-l:") else \
        [f"lib{option[2:]}.so", f"lib{option[2:]}.a"]
    for directory in directories:
        for name in names:
            candidate = directory / name
            if candidate.is_file():
                return candidate.absolute()
    raise ValueError(f"system linker library cannot be resolved: {option}")


def sdk_cpp_sources(sdk_root: Path, environment: dict[str, str]) -> dict[str, Path]:
    sources: dict[str, Path] = {}
    tools = [sdk_root / "bin/cjc", sdk_root / "bin/cjc-frontend"]
    tools.extend(sdk_root / "third_party/llvm/bin" / name for name in ("opt", "llc", "lld"))
    for tool in tools:
        result = subprocess.run(["/usr/bin/ldd", str(tool)], env=environment,
            text=True, capture_output=True, check=True, timeout=30)
        for line in result.stdout.splitlines():
            match = re.match(r"\s*(libstdc\+\+\.so\.6|libgcc_s\.so\.1)\s*=>\s*(/\S+)", line)
            if match is None:
                continue
            name, path = match.groups()
            source = Path(path)
            if name in sources and digest(sources[name]) != digest(source):
                raise ValueError("SDK tools load inconsistent C++ runtime libraries")
            sources[name] = source
    if set(sources) != set(SDK_CPP_LIBRARIES):
        raise ValueError("SDK C++ runtime libraries cannot be derived")
    return sources


def install_cpp_runtime(root: Path, identity: dict, sdk_root: Path) -> Path:
    validate_inputs(root, identity)
    if any((SDK_CPP_ROOT / name).as_posix() not in identity["files"] for name in SDK_CPP_LIBRARIES):
        raise ValueError("retained SDK C++ runtime library is missing")
    destination = sdk_root.parent / "cpp-runtime"
    destination.mkdir(exist_ok=False)
    for name in SDK_CPP_LIBRARIES:
        relative = (SDK_CPP_ROOT / name).as_posix()
        (destination / name).write_bytes((root / relative).read_bytes())
        (destination / name).chmod(0o644)
    validate_cpp_runtime(destination, identity)
    return destination


def validate_cpp_runtime(directory: Path, identity: dict) -> None:
    if directory.is_symlink() or not directory.is_dir() or \
            {value.name for value in directory.iterdir()} != set(SDK_CPP_LIBRARIES):
        raise ValueError("SDK C++ runtime directory is incomplete or unsafe")
    for name in SDK_CPP_LIBRARIES:
        expected = identity["files"].get((SDK_CPP_ROOT / name).as_posix())
        path = directory / name
        if not isinstance(expected, dict) or path.is_symlink() or not path.is_file() or \
                {"sha256": digest(path), "bytes": path.stat().st_size,
                 "mode": stat.S_IMODE(path.stat().st_mode)} != expected:
            raise ValueError("SDK C++ runtime bytes or mode differ from retained inputs")


def capture_inputs(sdk_root: Path, environment: dict[str, str], destination: Path) -> dict:
    """Discover once on the measurement host; rebuilds use only retained files."""
    destination.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="markdown-link-input-probe-") as temporary:
        work = Path(temporary)
        (work / "probe.cj").write_text("main() {}\n", encoding="utf-8")
        result = subprocess.run([str(sdk_root / "bin/cjc"), str(work / "probe.cj"),
            "-O2", "-j1", "-V", "--output-dir", str(work), "-o", "probe"],
            env=environment, text=True, capture_output=True, check=True)
    commands = []
    for line in (result.stdout + result.stderr).splitlines():
        if line.startswith("'"):
            command = shlex.split(line)
            if command and Path(command[0]).name in {"ld", "ld.bfd", "ld.gold", "ld.lld", "lld"}:
                commands.append(command)
    if len(commands) != 1:
        raise ValueError("cannot derive the SDK's default system link inputs")
    command = commands[0]
    linker = subprocess.run([command[0], "--verbose"], env=environment,
        text=True, capture_output=True, check=True)
    defaults = re.findall(r'SEARCH_DIR\("=?([^"\n]+)"\)', linker.stdout)
    directories = [Path(option[2:]) for option in command if option.startswith("-L")]
    directories.extend(Path(value) for value in defaults)
    if not directories or any(not path.is_absolute() for path in directories):
        raise ValueError("system linker search directories are unavailable")
    pending = [Path(option) for option in command if option.startswith("/") and option.endswith(".o")
        and Path(option).name != "probe.o"]
    pending.extend(library_file(option, directories) for option in command if option.startswith("-l"))
    seen = set()
    library_directories = set()
    total = 0
    sdk = sdk_root.resolve()
    while pending:
        source = pending.pop()
        if source.resolve().is_relative_to(sdk):
            continue
        relative = source.absolute().as_posix().lstrip("/")
        validate_relative_path(relative)
        if relative in seen:
            continue
        seen.add(relative)
        data = source.read_bytes()
        total += len(data)
        if len(seen) > MAX_FILES or total > MAX_BYTES:
            raise ValueError("system link inputs exceed retention limits")
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o644)
        library_directories.add(str(PurePosixPath(relative).parent))
        for reference in script_references(data):
            pending.append(Path(reference) if reference.startswith("/") else
                library_file(reference, directories))
    for name, source in sdk_cpp_sources(sdk_root, environment).items():
        target = destination.joinpath(*SDK_CPP_ROOT.parts) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        target.chmod(0o644)
        library_directories.add(str(SDK_CPP_ROOT))
    files = inventory(destination)
    identity = {"schemaVersion": SCHEMA_VERSION, "target": "x86_64-unknown-linux-gnu",
        "files": files, "libraryDirectories": sorted(library_directories),
        "treeSha256": canonical_digest(files)}
    return validate_inputs(destination, identity)


def compiler_options(root: Path, identity: dict, sdk_root: Path, launcher: Path) -> list[str]:
    validate_inputs(root, identity)
    linker = sdk_root / "third_party/llvm/bin/lld"
    if not linker.is_file():
        raise ValueError("the attested SDK LLD linker is missing")
    launcher.mkdir(parents=True, exist_ok=False)
    path = launcher / "ld"
    libraries = shlex.quote(str(sdk_root / "third_party/llvm/lib"))
    path.write_text("#!/bin/sh\nexport LD_LIBRARY_PATH=" + libraries +
        '${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\nexec ' + shlex.quote(str(linker)) +
        ' -flavor gnu "$@"\n', encoding="utf-8")
    path.chmod(0o755)
    return option_arguments(root, identity, launcher)


def option_arguments(root: Path, identity: dict, launcher: Path) -> list[str]:
    options = ["-j1", "--sysroot", str(root), "--toolchain", str(launcher),
        "--link-option=--sysroot=" + str(root), "--link-option=--threads=1",
        "--link-option=--thinlto-jobs=1"]
    options.extend("--link-option=-L" + str(root / value)
        for value in identity["libraryDirectories"])
    return options
