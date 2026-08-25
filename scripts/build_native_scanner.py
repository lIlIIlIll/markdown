#!/usr/bin/env python3
import os
import pathlib
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
    args = list(sys.argv[1:])
    while args:
        option = args.pop(0)
        if option == "--out-dir" and args:
            out_dir = pathlib.Path(args.pop(0)).resolve()
        else:
            raise SystemExit("usage: build_native_scanner.py [--out-dir DIR]")

    source = NATIVE_DIR / "markdown_scanner.c"
    header = NATIVE_DIR / "markdown_scanner.h"
    obj = out_dir / "markdown_scanner.o"
    library = out_dir / "libmarkdown_scanner.a"
    out_dir.mkdir(parents=True, exist_ok=True)

    needs_build = not library.exists() or not obj.exists()
    if not needs_build:
        library_mtime = library.stat().st_mtime
        needs_build = any(path.stat().st_mtime > library_mtime for path in (source, header))
    if not needs_build:
        return 0

    cc = find_tool("CC", "/usr/lib/llvm15/bin/clang")
    ar = find_tool("AR", "ar")
    subprocess.check_call([
        cc,
        "-std=c11",
        "-O3",
        "-fPIC",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I",
        str(NATIVE_DIR),
        "-c",
        str(source),
        "-o",
        str(obj),
    ], cwd=str(ROOT))
    subprocess.check_call([ar, "rcs", str(library), str(obj)], cwd=str(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
