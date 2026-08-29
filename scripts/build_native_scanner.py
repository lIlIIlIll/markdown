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
CACHE_SCHEMA_VERSION = 1
CACHE_MANIFEST_NAME = "markdown_scanner.cache.json"


def find_tool(env_name: str, default: str) -> str:
    configured = os.environ.get(env_name) or default
    resolved = shutil.which(configured)
    if resolved:
        return str(pathlib.Path(resolved).resolve())
    return configured


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_version(tool: str) -> str:
    arguments = [tool, "/?"] if pathlib.Path(tool).name.lower() in ("cl", "cl.exe", "lib", "lib.exe") \
        else [tool, "--version"]
    result = subprocess.run(arguments, text=True, capture_output=True, check=False)
    output = (result.stdout + result.stderr).strip()
    if not output:
        return f"exit={result.returncode};no-version-output"
    return output


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
        source: pathlib.Path, header: pathlib.Path) -> tuple[list[str], list[str], dict[str, object]]:
    obj = out_dir / ("markdown_scanner.obj" if windows_msvc else "markdown_scanner.o")
    library = out_dir / ("markdown_scanner.lib" if windows_msvc else "libmarkdown_scanner.a")
    compile_flags = shlex.split(os.environ.get("MARKDOWN_NATIVE_CFLAGS", ""))
    archive_flags = shlex.split(os.environ.get("MARKDOWN_NATIVE_ARFLAGS", ""))
    if windows_msvc:
        cc = find_tool("CC", "cl")
        librarian = find_tool("AR", "lib")
        compile_command = [
            cc, "/nologo", "/std:c11", "/O2", "/W4", "/WX", *compile_flags,
            f"/I{NATIVE_DIR}", "/c", str(source), f"/Fo{obj}",
        ]
        archive_command = [librarian, "/nologo", *archive_flags, f"/OUT:{library}", str(obj)]
        platform_branch = "windows-msvc"
    else:
        cc = find_tool("CC", "clang")
        librarian = find_tool("AR", "ar")
        compile_command = [cc]
        if target:
            compile_command.extend(["--target", target])
        compile_command.extend(["-std=c11", "-O3", "-Wall", "-Wextra", "-Werror"])
        if "windows" not in target and "mingw" not in target:
            compile_command.append("-fPIC")
        compile_command.extend([
            *compile_flags, "-I", str(NATIVE_DIR), "-c", str(source), "-o", str(obj),
        ])
        archive_command = [librarian, "rcs", *archive_flags, str(library), str(obj)]
        platform_branch = "gnu-like"
    manifest: dict[str, object] = {
        "schemaVersion": CACHE_SCHEMA_VERSION,
        "sourceSha256": file_sha256(source),
        "headerSha256": file_sha256(header),
        "target": target,
        "platformBranch": platform_branch,
        "compiler": {"path": cc, "version": tool_version(cc)},
        "archiver": {"path": librarian, "version": tool_version(librarian)},
        "compileCommand": compile_command,
        "archiveCommand": archive_command,
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

    compile_command, archive_command, expected_manifest = build_plan(
        target, windows_msvc, out_dir, source, header
    )
    actual_manifest: object = None
    if manifest_path.exists():
        try:
            actual_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            actual_manifest = None
    if library.exists() and obj.exists() and actual_manifest == expected_manifest:
        print(f"native scanner cache hit: {library}")
        return 0
    subprocess.check_call(compile_command, cwd=str(ROOT))
    subprocess.check_call(archive_command, cwd=str(ROOT))
    write_manifest_atomic(manifest_path, expected_manifest)
    print(f"native scanner archive: {library}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
