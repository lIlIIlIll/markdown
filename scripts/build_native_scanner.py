#!/usr/bin/env python3
import os
import pathlib
import platform
import shutil
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
NATIVE_DIR = ROOT / "native"
DEFAULT_OUT_DIR = ROOT / "target" / "native"


def find_tool(env_name: str, default: str) -> str:
    configured = os.environ.get(env_name)
    if configured:
        return configured
    return shutil.which(default) or default


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
    out_dir.mkdir(parents=True, exist_ok=True)

    needs_build = not library.exists() or not obj.exists()
    if not needs_build:
        library_mtime = library.stat().st_mtime
        needs_build = any(path.stat().st_mtime > library_mtime for path in (source, header))
    if not needs_build:
        return 0

    if windows_msvc:
        cc = find_tool("CC", "cl")
        librarian = find_tool("AR", "lib")
        subprocess.check_call([
            cc, "/nologo", "/std:c11", "/O2", "/W4", "/WX", f"/I{NATIVE_DIR}", "/c", str(source),
            f"/Fo{obj}",
        ], cwd=str(ROOT))
        subprocess.check_call([librarian, "/nologo", f"/OUT:{library}", str(obj)], cwd=str(ROOT))
    else:
        cc = find_tool("CC", "clang")
        ar = find_tool("AR", "ar")
        command = [cc]
        if target:
            command.extend(["--target", target])
        command.extend([
            "-std=c11", "-O3", "-Wall", "-Wextra", "-Werror", "-I", str(NATIVE_DIR), "-c", str(source),
            "-o", str(obj),
        ])
        if "windows" not in target and "mingw" not in target:
            command.insert(-6, "-fPIC")
        subprocess.check_call(command, cwd=str(ROOT))
        subprocess.check_call([ar, "rcs", str(library), str(obj)], cwd=str(ROOT))
    print(f"native scanner archive: {library}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
