#!/usr/bin/env python3
import hashlib
import json
import os
import pathlib
import platform
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
NATIVE_DIR = ROOT / "native"
DEFAULT_OUT_DIR = ROOT / "target" / "native"
CACHE_SCHEMA_VERSION = 3
ENVIRONMENT_SCHEMA_VERSION = 1
CACHE_MANIFEST_NAME = "markdown_scanner.cache.json"
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
WINDOWS_TOOLCHAIN_ENVIRONMENT_KEYS = (
    "COMSPEC",
    "INCLUDE",
    "LIB",
    "LIBPATH",
    "PATHEXT",
    "SYSTEMROOT",
    "SystemRoot",
    "UniversalCRTSdkDir",
    "UCRTVersion",
    "VCINSTALLDIR",
    "VCToolsInstallDir",
    "WindowsSDKVersion",
    "WindowsSdkDir",
)
DARWIN_TOOLCHAIN_ENVIRONMENT_KEYS = (
    "DEVELOPER_DIR",
    "MACOSX_DEPLOYMENT_TARGET",
    "SDKROOT",
)


def find_tool(env_name: str, default: str,
        environment: dict[str, str] | None = None) -> str:
    build_environment = os.environ if environment is None else environment
    configured = build_environment.get(env_name) or default
    resolved = shutil.which(configured, path=build_environment.get("PATH"))
    if resolved:
        return str(pathlib.Path(resolved).resolve())
    return configured


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_identity(path: pathlib.Path) -> dict[str, object]:
    if not path.is_file():
        raise RuntimeError(f"native scanner build did not produce: {path}")
    size = path.stat().st_size
    if size <= 0:
        raise RuntimeError(f"native scanner build produced an empty file: {path}")
    return {
        "path": str(path.resolve()),
        "bytes": size,
        "sha256": file_sha256(path),
    }


def canonical_json_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def native_child_environment(source: dict[str, str], out_dir: pathlib.Path,
        compiler: str, archiver: str, target: str,
        windows_msvc: bool) -> dict[str, str]:
    home = (out_dir / ".native-build-home").resolve()
    temporary = (out_dir / ".native-build-tmp").resolve()
    home.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary.mkdir(mode=0o700, parents=True, exist_ok=True)
    path_entries = []
    for entry in (pathlib.Path(compiler).resolve().parent,
            pathlib.Path(archiver).resolve().parent,
            pathlib.Path("/usr/bin"), pathlib.Path("/bin")):
        value = str(entry)
        if value not in path_entries:
            path_entries.append(value)
    environment = {
        "HOME": str(home),
        "LANG": "C",
        "LC_ALL": "C",
        "PATH": os.pathsep.join(path_entries),
        "SOURCE_DATE_EPOCH": "0",
        "TMPDIR": str(temporary),
        "TZ": "UTC",
    }
    if windows_msvc:
        environment["TEMP"] = str(temporary)
        environment["TMP"] = str(temporary)
        for name in WINDOWS_TOOLCHAIN_ENVIRONMENT_KEYS:
            if source.get(name):
                environment[name] = source[name]
    elif "apple" in target or "darwin" in target or platform.system() == "Darwin":
        for name in DARWIN_TOOLCHAIN_ENVIRONMENT_KEYS:
            if source.get(name):
                environment[name] = source[name]
    if not set(environment).issubset(NATIVE_BUILD_ENVIRONMENT_KEYS):
        raise RuntimeError("native scanner child environment escaped its allowlist")
    return {name: environment[name] for name in sorted(environment)}


def environment_identity(environment: dict[str, str]) -> dict[str, object]:
    if not set(environment).issubset(NATIVE_BUILD_ENVIRONMENT_KEYS) or any(
            not isinstance(value, str) for value in environment.values()):
        raise RuntimeError("native scanner child environment is not allowlisted")
    variables = {name: environment[name] for name in sorted(environment)}
    return {
        "schemaVersion": ENVIRONMENT_SCHEMA_VERSION,
        "allowlist": sorted(NATIVE_BUILD_ENVIRONMENT_KEYS),
        "variables": variables,
        "sha256": canonical_json_sha256(variables),
    }


def output_manifest(plan: dict[str, object], obj: pathlib.Path,
        library: pathlib.Path) -> dict[str, object]:
    return {
        **plan,
        "object": file_identity(obj),
        "archive": file_identity(library),
    }


def cache_matches(actual: object, plan: dict[str, object], obj: pathlib.Path,
        library: pathlib.Path) -> bool:
    if not isinstance(actual, dict) or not obj.is_file() or not library.is_file():
        return False
    try:
        expected = output_manifest(plan, obj, library)
    except (OSError, RuntimeError):
        return False
    return actual == expected


def tool_identity(tool: str, environment: dict[str, str]) -> dict[str, object]:
    resolved = pathlib.Path(tool).resolve()
    identity = file_identity(resolved)
    arguments = [str(resolved), "/?"] if resolved.name.lower() in \
        ("cl", "cl.exe", "lib", "lib.exe") \
        else [str(resolved), "--version"]
    result = subprocess.run(arguments, text=True, capture_output=True, check=False,
        env=environment)
    if not result.stdout and not result.stderr:
        raise RuntimeError(f"native scanner tool version output is empty: {resolved}")
    identity["version"] = {
        "command": arguments,
        "exitCode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    return identity


def write_manifest_atomic(path: pathlib.Path, manifest: dict[str, object]) -> None:
    serialized = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent,
            prefix=f".{path.name}.", delete=False) as stream:
        temporary = pathlib.Path(stream.name)
        stream.write(serialized)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def build_plan(target: str, windows_msvc: bool, out_dir: pathlib.Path,
        source: pathlib.Path, header: pathlib.Path,
        environment: dict[str, str] | None = None
        ) -> tuple[list[str], list[str], dict[str, object]]:
    host_environment = dict(os.environ if environment is None else environment)
    obj = out_dir / ("markdown_scanner.obj" if windows_msvc else "markdown_scanner.o")
    library = out_dir / ("markdown_scanner.lib" if windows_msvc else "libmarkdown_scanner.a")
    compile_flags = shlex.split(host_environment.get("MARKDOWN_NATIVE_CFLAGS", ""))
    archive_flags = shlex.split(host_environment.get("MARKDOWN_NATIVE_ARFLAGS", ""))
    if windows_msvc:
        cc = find_tool("CC", "cl", host_environment)
        librarian = find_tool("AR", "lib", host_environment)
        compile_command = [
            cc, "/nologo", "/std:c11", "/O2", "/W4", "/WX", *compile_flags,
            f"/I{NATIVE_DIR}", "/c", str(source), f"/Fo{obj}",
        ]
        archive_command = [librarian, "/nologo", *archive_flags, f"/OUT:{library}", str(obj)]
        platform_branch = "windows-msvc"
    else:
        cc = find_tool("CC", "clang", host_environment)
        librarian = find_tool("AR", "ar", host_environment)
        compile_command = [cc]
        if target:
            compile_command.extend(["-target", target])
        compile_command.extend(["-std=c11", "-O3", "-Wall", "-Wextra", "-Werror"])
        if "windows" not in target and "mingw" not in target:
            compile_command.append("-fPIC")
        compile_command.extend([
            *compile_flags, "-I", str(NATIVE_DIR), "-c", str(source), "-o", str(obj),
        ])
        archive_command = [librarian, "rcs", *archive_flags, str(library), str(obj)]
        platform_branch = "gnu-like"
    child_environment = native_child_environment(host_environment, out_dir,
        cc, librarian, target, windows_msvc)
    manifest: dict[str, object] = {
        "schemaVersion": CACHE_SCHEMA_VERSION,
        "sourceSha256": file_sha256(source),
        "headerSha256": file_sha256(header),
        "target": target,
        "platformBranch": platform_branch,
        "compiler": tool_identity(cc, child_environment),
        "archiver": tool_identity(librarian, child_environment),
        "compileCommand": compile_command,
        "archiveCommand": archive_command,
        "buildEnvironment": environment_identity(child_environment),
    }
    return compile_command, archive_command, manifest


def main() -> int:
    out_dir = DEFAULT_OUT_DIR
    enabled = False
    target = os.environ.get("TARGET", "")
    args = list(sys.argv[1:])
    while args:
        option = args.pop(0)
        if option == "--enable":
            enabled = True
        elif option == "--out-dir" and args:
            out_dir = pathlib.Path(args.pop(0)).resolve()
        elif option == "--target" and args:
            target = args.pop(0)
        else:
            raise SystemExit("usage: build_native_scanner.py --enable [--target TRIPLE] [--out-dir DIR]")

    if not enabled:
        print("native scanner disabled; pass --enable to build it")
        return 0

    source = NATIVE_DIR / "markdown_scanner.c"
    header = NATIVE_DIR / "markdown_scanner.h"
    windows_msvc = "windows-msvc" in target or (not target and platform.system() == "Windows")
    obj = out_dir / ("markdown_scanner.obj" if windows_msvc else "markdown_scanner.o")
    library = out_dir / ("markdown_scanner.lib" if windows_msvc else "libmarkdown_scanner.a")
    manifest_path = out_dir / CACHE_MANIFEST_NAME
    out_dir.mkdir(parents=True, exist_ok=True)

    host_environment = dict(os.environ)
    compile_command, archive_command, expected_manifest = build_plan(
        target, windows_msvc, out_dir, source, header, host_environment
    )
    environment_record = expected_manifest["buildEnvironment"]
    if not isinstance(environment_record, dict) or \
            not isinstance(environment_record.get("variables"), dict):
        raise RuntimeError("native scanner child environment identity is invalid")
    child_environment = dict(environment_record["variables"])
    actual_manifest: object = None
    if manifest_path.exists():
        try:
            actual_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            actual_manifest = None
    if cache_matches(actual_manifest, expected_manifest, obj, library):
        print(f"native scanner cache hit: {library}")
        return 0
    obj.unlink(missing_ok=True)
    library.unlink(missing_ok=True)
    subprocess.check_call(compile_command, cwd=str(ROOT), env=child_environment)
    file_identity(obj)
    subprocess.check_call(archive_command, cwd=str(ROOT), env=child_environment)
    complete_manifest = output_manifest(expected_manifest, obj, library)
    write_manifest_atomic(manifest_path, complete_manifest)
    print(f"native scanner archive: {library}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
