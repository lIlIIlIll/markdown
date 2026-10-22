#!/usr/bin/env python3
"""Build benchmark executables and optionally emit a fail-closed build identity."""

from __future__ import annotations

import argparse
import copy
from contextlib import contextmanager
from dataclasses import dataclass, replace
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import shlex
import subprocess
import sys
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "benchmarks" / "driver"
CLI = ROOT / "tools" / "markdown"
NATIVE = ROOT / "target" / "native"
NATIVE_MANIFEST = NATIVE / "markdown_scanner.cache.json"
CANONICAL_OPTIMIZATION = "-O2 --lto thin --obf-seed 0"
IDENTITY_SCHEMA_VERSION = 6
NATIVE_CACHE_SCHEMA_VERSION = 3
NATIVE_ENVIRONMENT_SCHEMA_VERSION = 1

sys.path.insert(0, str(ROOT / "benchmarks"))
from benchmark_identity import (  # noqa: E402
    BUILD_ENVIRONMENT_KEYS,
    NATIVE_BUILD_ENVIRONMENT_KEYS,
    benchmark_product_file_sha256s,
    benchmark_product_tree_sha256,
    build_environment_attestation,
    canonical_build_environment,
    exact_environment,
    reject_ambient_benchmark_environment,
)
import link_inputs  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_json_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")
    temporary.replace(path)


@dataclass(frozen=True)
class SdkToolchain:
    archive: Path
    archive_sha256: str
    extraction: Path
    root: Path
    envsetup: Path
    cjc: Path
    cjpm: Path
    environment: dict[str, str]
    link_inputs: dict[str, object] | None = None


def command_record(arguments: list[str], cwd: Path, *, check: bool,
        environment: dict[str, str] | None = None) -> dict[str, object]:
    controlled_environment = None if environment is None else exact_environment(
        environment, BUILD_ENVIRONMENT_KEYS, "benchmark build")
    result = subprocess.run(arguments, cwd=cwd, text=True, capture_output=True,
        check=False, env=controlled_environment)
    record: dict[str, object] = {
        "command": arguments,
        "cwd": str(cwd.resolve()),
        "exitCode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    if controlled_environment is not None:
        record["environment"] = controlled_environment
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, arguments,
            output=result.stdout, stderr=result.stderr)
    return record


def tool_record(arguments: list[str], *, environment: dict[str, str] | None = None
        ) -> dict[str, object]:
    executable = shutil.which(arguments[0], path=(environment or os.environ).get("PATH"))
    if executable is None:
        raise RuntimeError(f"required tool is unavailable: {arguments[0]}")
    resolved = Path(executable).resolve()
    record = command_record([str(resolved), *arguments[1:]], ROOT, check=True,
        environment=environment)
    record.update(binary_identity(resolved))
    return record


def verify_sdk_archive(archive: Path, expected_sha256: str) -> tuple[Path, str]:
    resolved = archive.resolve()
    if not resolved.is_file():
        raise RuntimeError(f"SDK archive does not exist: {resolved}")
    actual = sha256(resolved)
    if actual != expected_sha256:
        raise RuntimeError("SDK archive digest does not match --sdk-sha256")
    return resolved, actual


def sdk_environment(root: Path, target: str) -> dict[str, str]:
    environment = canonical_build_environment(root, target)
    for name in ("HOME", "TMPDIR"):
        Path(environment[name]).mkdir(mode=0o700, parents=True, exist_ok=True)
    return environment


def sdk_archive_members(bundle: tarfile.TarFile, destination: Path) -> list[tarfile.TarInfo]:
    """Validate SDK members without relying on version-specific symlink filtering."""
    members = bundle.getmembers()
    if not members:
        raise RuntimeError("SDK archive is empty")
    by_name: dict[str, tarfile.TarInfo] = {}
    normalized: list[tuple[str, tarfile.TarInfo]] = []
    for member in members:
        raw = member.name.rstrip("/")
        name = posixpath.normpath(raw)
        if not raw or posixpath.isabs(raw) or name in (".", "..") or \
                name.startswith("../"):
            raise RuntimeError(f"SDK archive path escapes extraction root: {member.name}")
        if name in by_name:
            raise RuntimeError(f"SDK archive contains a duplicate path: {name}")
        if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
            raise RuntimeError(f"SDK archive contains an unsupported member: {name}")
        by_name[name] = member
        normalized.append((name, member))

    symlinks = {name for name, member in normalized if member.issym()}
    links: dict[str, str] = {}
    for name, member in normalized:
        parts = name.split("/")
        if any("/".join(parts[:index]) in symlinks for index in range(1, len(parts))):
            raise RuntimeError(f"SDK archive member traverses a symlink: {name}")
        if member.issym():
            if not member.linkname or posixpath.isabs(member.linkname):
                raise RuntimeError(f"SDK archive symlink is not relative: {name}")
            target = posixpath.normpath(posixpath.join(posixpath.dirname(name),
                member.linkname))
        elif member.islnk():
            if not member.linkname or posixpath.isabs(member.linkname):
                raise RuntimeError(f"SDK archive hard link is not relative: {name}")
            target = posixpath.normpath(member.linkname)
        else:
            continue
        if target in (".", "..") or target.startswith("../") or target not in by_name:
            raise RuntimeError(f"SDK archive link target is outside the archive: {name}")
        links[name] = target

    for name in links:
        visited = {name}
        target = links[name]
        while target in links:
            if target in visited:
                raise RuntimeError(f"SDK archive contains a link cycle: {name}")
            visited.add(target)
            target = links[target]
        if target not in by_name:
            raise RuntimeError(f"SDK archive link target is unavailable: {name}")

    filtered: list[tarfile.TarInfo] = []
    for name, member in normalized:
        if member.issym() or member.islnk():
            safe_member = copy.copy(member)
            safe_member.name = name
            safe_member.mode = 0o777
            safe_member.uid = 0
            safe_member.gid = 0
            safe_member.uname = ""
            safe_member.gname = ""
        else:
            safe_member = tarfile.data_filter(member, str(destination))
            if safe_member is None:
                continue
            safe_member.mode = 0o755 if safe_member.isdir() or \
                (safe_member.mode & 0o111) else 0o644
        filtered.append(safe_member)
    return filtered


def extract_sdk_archive(archive: Path, destination: Path, target: str) -> SdkToolchain:
    destination = destination.resolve()
    if destination.exists():
        raise RuntimeError(f"SDK extraction destination must not exist: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.mkdir(mode=0o700)
    try:
        with tarfile.open(archive, mode="r:*") as bundle:
            filtered = sdk_archive_members(bundle, destination)
            bundle.extractall(destination, members=filtered, filter="fully_trusted")
        roots = []
        for envsetup in destination.rglob("envsetup.sh"):
            root = envsetup.parent.resolve()
            cjc = root / "bin" / "cjc"
            cjpm_candidates = [root / "bin" / "cjpm", root / "tools" / "bin" / "cjpm"]
            cjpm = [path for path in cjpm_candidates if path.is_file()]
            if cjc.is_file() and len(cjpm) == 1:
                roots.append((root, envsetup.resolve(), cjc.resolve(), cjpm[0].resolve()))
        if len(roots) != 1:
            raise RuntimeError("SDK archive must contain exactly one usable Cangjie SDK root")
        root, envsetup, cjc, cjpm = roots[0]
        for name, tool in (("cjc", cjc), ("cjpm", cjpm)):
            if not os.access(tool, os.X_OK):
                raise RuntimeError(f"extracted SDK {name} is not executable")
        environment = sdk_environment(root, target)
        if Path(shutil.which("cjc", path=environment["PATH"]) or "").resolve() != cjc or \
                Path(shutil.which("cjpm", path=environment["PATH"]) or "").resolve() != cjpm:
            raise RuntimeError("extracted SDK tools are shadowed by another SDK")
        return SdkToolchain(archive=archive, archive_sha256=sha256(archive),
            extraction=destination, root=root, envsetup=envsetup, cjc=cjc, cjpm=cjpm,
            environment=environment)
    except Exception:
        shutil.rmtree(destination)
        raise


def prepare_sdk(args: argparse.Namespace) -> SdkToolchain:
    archive, actual = verify_sdk_archive(args.sdk_archive, args.sdk_sha256)
    sdk = extract_sdk_archive(archive, args.sdk_extract_dir, args.target)
    if sdk.archive_sha256 != actual:
        shutil.rmtree(sdk.extraction)
        raise RuntimeError("SDK archive changed while it was being extracted")
    return sdk


def prepare_link_inputs(sdk: SdkToolchain, retained: Path | None = None) -> SdkToolchain:
    if retained is None:
        root = sdk.extraction.with_name(sdk.extraction.name + "-link-inputs")
        root.mkdir()
        identity = link_inputs.capture_inputs(sdk.root, sdk.environment, root / "sysroot")
        atomic_json(root / "identity.json", identity)
    else:
        root = retained.resolve()
        identity = json.loads((root / "identity.json").read_text(encoding="utf-8"))
        link_inputs.validate_inputs(root / "sysroot", identity)
    launcher = sdk.extraction.with_name(sdk.extraction.name + "-linker")
    link_inputs.install_cpp_runtime(root / "sysroot", identity, sdk.root)
    options = link_inputs.compiler_options(root / "sysroot", identity, sdk.root, launcher)
    return replace(sdk, link_inputs={"root": str(root), "launcher": str(launcher),
        "identity": identity, "compilerOptions": options})




def manifest_option(text: str, name: str) -> str:
    match = re.search(rf'^\s*{re.escape(name)}\s*=\s*"([^"]*)"\s*$', text,
        flags=re.MULTILINE)
    if match is None:
        raise ValueError(f"missing manifest option: {name}")
    return match.group(1)


def trimpath_manifest(text: str, source_root: Path, extra_options: list[str] | None = None) -> str:
    option = manifest_option(text, "compile-option")
    if "--trimpath" in option:
        raise ValueError("benchmark manifest already contains --trimpath")
    options = f"{option} --trimpath {source_root.resolve()}"
    if extra_options:
        options += " " + shlex.join(extra_options)
    replacement = 'compile-option = ' + json.dumps(options)
    return re.sub(r'^\s*compile-option\s*=\s*"[^"]*"\s*$', replacement,
        text, count=1, flags=re.MULTILINE)


@contextmanager
def reproducible_manifests(source_root: Path, package: Path, extra_options: list[str] | None = None):
    paths = (source_root / "cjpm.toml", package / "cjpm.toml")
    originals = {path: path.read_text(encoding="utf-8") for path in paths}
    try:
        for path, text in originals.items():
            path.write_text(trimpath_manifest(text, source_root, extra_options), encoding="utf-8")
        yield originals
    finally:
        for path, text in originals.items():
            path.write_text(text, encoding="utf-8")


def binary_identity(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise RuntimeError(f"build did not produce executable: {path}")
    return {"path": str(path.resolve()), "bytes": path.stat().st_size,
        "sha256": sha256(path)}


def prepare_build_workspace(destination: Path) -> Path:
    destination = destination.resolve()
    if destination.exists():
        raise RuntimeError(f"benchmark build workspace must not exist: {destination}")
    (destination / "benchmarks").mkdir(parents=True)
    (destination / "tools").mkdir()
    (destination / "scripts").mkdir()
    shutil.copytree(ROOT / "src", destination / "src")
    shutil.copytree(ROOT / "native", destination / "native")
    shutil.copytree(DRIVER, destination / "benchmarks" / "driver",
        ignore=shutil.ignore_patterns("target", "__pycache__"))
    shutil.copytree(CLI, destination / "tools" / "markdown",
        ignore=shutil.ignore_patterns("target", "__pycache__"))
    for name in ("cjpm.toml", "cjpm.lock", "build.cj"):
        shutil.copy2(ROOT / name, destination / name)
    shutil.copy2(ROOT / "benchmarks" / "benchmark_identity.py",
        destination / "benchmarks" / "benchmark_identity.py")
    for name in ("build_benchmark_driver.py", "build_native_scanner.py"):
        shutil.copy2(ROOT / "scripts" / name, destination / "scripts" / name)
    shutil.copy2(ROOT / "benchmarks/link_inputs.py", destination / "benchmarks/link_inputs.py")
    native = destination / "target" / "native"
    native.mkdir(parents=True)
    copied = 0
    for name in ("libmarkdown_scanner.a", "markdown_scanner.lib"):
        source = NATIVE / name
        if source.is_file():
            shutil.copy2(source, native / name)
            copied += 1
    if copied != 1:
        raise RuntimeError("fresh benchmark build requires exactly one native scanner archive")
    if benchmark_product_tree_sha256(destination) != benchmark_product_tree_sha256(ROOT):
        raise RuntimeError("fresh benchmark build workspace does not match current product source")
    return destination


def build_canonical(sdk: SdkToolchain | None = None,
        source_root: Path = ROOT) -> dict[str, object]:
    package = source_root / "benchmarks" / "driver"
    manifest_path = package / "cjpm.toml"
    canonical_manifest = manifest_path.read_text(encoding="utf-8")
    canonical_root_manifest = (source_root / "cjpm.toml").read_text(encoding="utf-8")
    source_identity = benchmark_product_tree_sha256(source_root)
    cjpm = str(sdk.cjpm) if sdk is not None else "cjpm"
    if source_root != ROOT:
        with reproducible_manifests(source_root, package,
                sdk.link_inputs["compilerOptions"] if sdk is not None and sdk.link_inputs else None):
            manifest = manifest_path.read_text(encoding="utf-8")
            root_manifest = (source_root / "cjpm.toml").read_text(encoding="utf-8")
            build = command_record([cjpm, "build", "-j", "1"], package, check=True,
                environment=sdk.environment if sdk is not None else None)
    else:
        manifest = canonical_manifest
        root_manifest = canonical_root_manifest
        build = command_record([cjpm, "build", "-j", "1"], package, check=True,
            environment=sdk.environment if sdk is not None else None)
    built = package / "target" / "release" / "bin" / "main"
    destination = DRIVER / "target" / "release" / "bin" / "main"
    if source_root != ROOT:
        if not built.is_file():
            raise RuntimeError(f"fresh build did not produce executable: {built}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built, destination)
    return {"mode": "canonical", "build": build,
        "sourceProductTreeSha256": source_identity,
        "trimPath": str(source_root.resolve()) if source_root != ROOT else None,
        "compileOption": manifest_option(manifest, "compile-option"),
        "linkOption": manifest_option(manifest, "link-option"),
        "canonicalManifestSha256": sha256(DRIVER / "cjpm.toml"),
        "effectiveManifestSha256": hashlib.sha256(manifest.encode("utf-8")).hexdigest(),
        "canonicalRootManifestSha256": hashlib.sha256(
            canonical_root_manifest.encode("utf-8")).hexdigest(),
        "effectiveRootManifestSha256": hashlib.sha256(
            root_manifest.encode("utf-8")).hexdigest(),
        "binary": binary_identity(destination)}




def build_cli(sdk: SdkToolchain | None = None, source_root: Path = ROOT
        ) -> dict[str, object]:
    package = source_root / "tools" / "markdown"
    manifest_path = package / "cjpm.toml"
    canonical_manifest = manifest_path.read_text(encoding="utf-8")
    canonical_root_manifest = (source_root / "cjpm.toml").read_text(encoding="utf-8")
    source_identity = benchmark_product_tree_sha256(source_root)
    cjpm = str(sdk.cjpm) if sdk is not None else "cjpm"
    if source_root != ROOT:
        with reproducible_manifests(source_root, package,
                sdk.link_inputs["compilerOptions"] if sdk is not None and sdk.link_inputs else None):
            manifest = manifest_path.read_text(encoding="utf-8")
            root_manifest = (source_root / "cjpm.toml").read_text(encoding="utf-8")
            build = command_record([cjpm, "build", "-j", "1"], package, check=True,
                environment=sdk.environment if sdk is not None else None)
    else:
        manifest = canonical_manifest
        root_manifest = canonical_root_manifest
        build = command_record([cjpm, "build", "-j", "1"], package, check=True,
            environment=sdk.environment if sdk is not None else None)
    built = package / "target" / "release" / "bin" / "main"
    destination = CLI / "target" / "release" / "bin" / "main"
    if source_root != ROOT:
        if not built.is_file():
            raise RuntimeError(f"fresh build did not produce executable: {built}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built, destination)
    return {"mode": "canonical", "build": build,
        "sourceProductTreeSha256": source_identity,
        "trimPath": str(source_root.resolve()) if source_root != ROOT else None,
        "compileOption": manifest_option(manifest, "compile-option"),
        "linkOption": manifest_option(manifest, "link-option"),
        "canonicalManifestSha256": sha256(CLI / "cjpm.toml"),
        "effectiveManifestSha256": hashlib.sha256(manifest.encode("utf-8")).hexdigest(),
        "canonicalRootManifestSha256": hashlib.sha256(
            canonical_root_manifest.encode("utf-8")).hexdigest(),
        "effectiveRootManifestSha256": hashlib.sha256(
            root_manifest.encode("utf-8")).hexdigest(),
        "binary": binary_identity(destination)}


def native_environment_variables(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or set(value) != {
            "schemaVersion", "allowlist", "variables", "sha256"} or \
            value.get("schemaVersion") != NATIVE_ENVIRONMENT_SCHEMA_VERSION or \
            value.get("allowlist") != sorted(NATIVE_BUILD_ENVIRONMENT_KEYS):
        raise RuntimeError("native scanner child environment identity is incomplete")
    variables = value.get("variables")
    if not isinstance(variables, dict) or \
            not set(variables).issubset(NATIVE_BUILD_ENVIRONMENT_KEYS) or \
            any(not isinstance(name, str) or not isinstance(item, str)
                for name, item in variables.items()) or \
            value.get("sha256") != canonical_json_sha256(variables):
        raise RuntimeError("native scanner child environment digest is invalid")
    return dict(variables)


def validate_native_tool(value: object, label: str,
        environment: dict[str, str]) -> dict[str, object]:
    if not isinstance(value, dict):
        raise RuntimeError(f"native scanner {label} identity is missing")
    path = Path(str(value.get("path", "")))
    if not path.is_absolute() or path.resolve() != path:
        raise RuntimeError(f"native scanner {label} path is not resolved")
    actual = binary_identity(path)
    if any(value.get(name) != actual[name] for name in ("path", "bytes", "sha256")):
        raise RuntimeError(f"native scanner {label} binary digest changed")
    version = value.get("version")
    if not isinstance(version, dict) or set(version) != {
            "command", "exitCode", "stdout", "stderr"} or \
            isinstance(version.get("exitCode"), bool) or \
            not isinstance(version.get("exitCode"), int) or \
            not isinstance(version.get("stdout"), str) or \
            not isinstance(version.get("stderr"), str) or \
            not (version.get("stdout") or version.get("stderr")):
        raise RuntimeError(f"native scanner {label} version identity is invalid")
    command = version.get("command")
    if not isinstance(command, list) or len(command) != 2 or command[0] != str(path) or \
            not all(isinstance(argument, str) and argument for argument in command):
        raise RuntimeError(f"native scanner {label} version command is not bound")
    result = subprocess.run(command, text=True, capture_output=True, check=False,
        env=environment)
    if {"command": command, "exitCode": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr} != version:
        raise RuntimeError(f"native scanner {label} version output changed")
    return value


def native_identity(target: str) -> dict[str, object]:
    if not NATIVE_MANIFEST.is_file():
        raise RuntimeError("native scanner cache manifest is required for build identity")
    manifest = json.loads(NATIVE_MANIFEST.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or \
            manifest.get("schemaVersion") != NATIVE_CACHE_SCHEMA_VERSION:
        raise RuntimeError("native scanner cache manifest schema is unsupported")
    if manifest.get("target") != target:
        raise RuntimeError("native scanner target does not match benchmark target")
    if manifest.get("sourceSha256") != sha256(ROOT / "native/markdown_scanner.c") or \
            manifest.get("headerSha256") != sha256(ROOT / "native/markdown_scanner.h"):
        raise RuntimeError("native scanner source identity is stale")
    build_environment = native_environment_variables(manifest.get("buildEnvironment"))
    for key in ("compileCommand", "archiveCommand", "compiler", "archiver",
            "object", "archive"):
        if key not in manifest:
            raise RuntimeError(f"native scanner manifest is missing {key}")
    compiler = validate_native_tool(manifest["compiler"], "compiler",
        build_environment)
    archiver = validate_native_tool(manifest["archiver"], "archiver",
        build_environment)
    expected_environment = {
        "HOME": str((NATIVE / ".native-build-home").resolve()),
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": os.pathsep.join(dict.fromkeys((
            str(Path(str(compiler["path"])).parent),
            str(Path(str(archiver["path"])).parent), "/usr/bin", "/bin"))),
        "SOURCE_DATE_EPOCH": "0",
        "TMPDIR": str((NATIVE / ".native-build-tmp").resolve()),
        "TZ": "UTC",
    }
    if build_environment != expected_environment:
        raise RuntimeError("native scanner child environment is not canonical")
    compile_command = manifest["compileCommand"]
    archive_command = manifest["archiveCommand"]
    if not isinstance(compile_command, list) or not compile_command or \
            compile_command[0] != compiler["path"]:
        raise RuntimeError("native scanner compiler command is not bound")
    if not isinstance(archive_command, list) or not archive_command or \
            archive_command[0] != archiver["path"]:
        raise RuntimeError("native scanner archiver command is not bound")
    archive_candidates = [path for path in (
        NATIVE / "libmarkdown_scanner.a", NATIVE / "markdown_scanner.lib")
        if path.is_file()]
    object_candidates = [path for path in (
        NATIVE / "markdown_scanner.o", NATIVE / "markdown_scanner.obj")
        if path.is_file()]
    if len(archive_candidates) != 1:
        raise RuntimeError("native scanner archive identity is ambiguous or missing")
    if len(object_candidates) != 1:
        raise RuntimeError("native scanner object identity is ambiguous or missing")
    archive = archive_candidates[0]
    obj = object_candidates[0]
    archive_identity = binary_identity(archive)
    object_identity = binary_identity(obj)
    if manifest["archive"] != archive_identity:
        raise RuntimeError("native scanner archive digest does not match its cache manifest")
    if manifest["object"] != object_identity:
        raise RuntimeError("native scanner object digest does not match its cache manifest")
    object_path = object_identity["path"]
    archive_path = archive_identity["path"]
    if not any(str(argument) == object_path or str(argument).endswith(object_path)
            for argument in compile_command):
        raise RuntimeError("native scanner object is not bound to its compiler command")
    if not any(str(argument) == archive_path or str(argument).endswith(archive_path)
            for argument in archive_command) or not any(
                str(argument) == object_path or str(argument).endswith(object_path)
                for argument in archive_command):
        raise RuntimeError("native scanner archive command is not bound to its inputs")
    return {"cacheManifest": manifest,
        "cacheManifestSha256": canonical_json_sha256(manifest),
        "compiler": compiler,
        "archiver": archiver,
        "buildEnvironment": manifest["buildEnvironment"],
        "object": object_identity,
        "archive": archive_identity}


def build_identity(args: argparse.Namespace, driver: dict[str, object],
        cli: dict[str, object], sdk: SdkToolchain) -> dict[str, object]:
    cjc = tool_record([str(sdk.cjc), "-v"], environment=sdk.environment)
    cjpm = tool_record([str(sdk.cjpm), "--version"], environment=sdk.environment)
    expected_environment = exact_environment(sdk.environment,
        BUILD_ENVIRONMENT_KEYS, "benchmark build")
    if expected_environment != canonical_build_environment(sdk.root, args.target):
        raise RuntimeError("attested SDK build environment is not canonical")
    for name, build in (("markdownDriver", driver), ("markdownCli", cli)):
        build_command = build.get("build") if isinstance(build, dict) else None
        command = build_command.get("command") if isinstance(build_command, dict) else None
        if not isinstance(command, list) or not command or command[0] != str(sdk.cjpm):
            raise RuntimeError(f"{name} was not built by the attested SDK cjpm")
        if build_command.get("environment") != expected_environment:
            raise RuntimeError(f"{name} was not built in the attested SDK environment")
        if build.get("sourceProductTreeSha256") != benchmark_product_tree_sha256(ROOT):
            raise RuntimeError(f"{name} source changed while the benchmark was being built")
    if f"Target: {args.target}" not in str(cjc["stdout"] + cjc["stderr"]):
        raise RuntimeError("cjc target does not match --target")
    if sdk.link_inputs is None:
        raise RuntimeError("attested builds require retained Cangjie system link inputs")
    link_inputs.validate_inputs(Path(str(sdk.link_inputs["root"])) / "sysroot",
        sdk.link_inputs["identity"])
    link_inputs.validate_cpp_runtime(sdk.root.parent / "cpp-runtime", sdk.link_inputs["identity"])
    return {
        "schemaVersion": IDENTITY_SCHEMA_VERSION,
        "sdk": {"archiveUrl": args.sdk_url, "archivePath": str(sdk.archive),
            "archiveSha256": sdk.archive_sha256,
            "archiveBytes": sdk.archive.stat().st_size, "target": args.target,
            "extraction": str(sdk.extraction), "root": str(sdk.root),
            "envsetupSha256": sha256(sdk.envsetup),
            "environment": build_environment_attestation(sdk.environment)},
        "tools": {"cjc": cjc, "cjpm": cjpm},
        "sourceIdentity": {
            "productTreeSha256": benchmark_product_tree_sha256(ROOT),
            "files": benchmark_product_file_sha256s(ROOT),
        },
        "nativeScanner": native_identity(args.target),
        "linkInputs": sdk.link_inputs,
        "builds": {"markdownDriver": driver, "markdownCli": cli},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-cli", action="store_true")
    parser.add_argument("--identity-output", type=Path)
    parser.add_argument("--sdk-url")
    parser.add_argument("--sdk-sha256")
    parser.add_argument("--sdk-archive", type=Path)
    parser.add_argument("--sdk-extract-dir", type=Path)
    parser.add_argument("--target")
    parser.add_argument("--link-inputs-root", type=Path,
        help="verified retained link-input directory; otherwise capture the measurement host inputs")
    args = parser.parse_args()
    identity_values = (args.sdk_url, args.sdk_sha256, args.sdk_archive,
        args.sdk_extract_dir, args.target)
    if args.identity_output is not None and (not args.build_cli or not all(identity_values)):
        parser.error("--identity-output requires --build-cli and complete SDK URL/SHA/archive/extract-dir/target")
    if args.sdk_sha256 is not None and not re.fullmatch(r"[0-9a-f]{64}", args.sdk_sha256):
        parser.error("--sdk-sha256 must be a lowercase SHA-256 digest")

    try:
        if args.identity_output is not None:
            reject_ambient_benchmark_environment(dict(os.environ))
        sdk = prepare_sdk(args) if args.identity_output is not None else None
        if sdk is not None:
            sdk = prepare_link_inputs(sdk, args.link_inputs_root)
        if sdk is not None:
            with tempfile.TemporaryDirectory(prefix="markdown-pinned-sdk-build-") as temporary:
                build_root = prepare_build_workspace(Path(temporary) / "markdown")
                driver = build_canonical(sdk, build_root)
                cli = build_cli(sdk, build_root)
        else:
            driver = build_canonical(sdk)
            cli = build_cli(sdk) if args.build_cli else None
        if args.identity_output is not None:
            assert cli is not None and sdk is not None
            atomic_json(args.identity_output, build_identity(args, driver, cli, sdk))
            print(f"benchmark build identity: {args.identity_output}")
    except subprocess.CalledProcessError as error:
        if error.output:
            print(error.output, end="", file=sys.stdout)
        if error.stderr:
            print(error.stderr, end="", file=sys.stderr)
        return error.returncode
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print("benchmark driver build mode: canonical")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
