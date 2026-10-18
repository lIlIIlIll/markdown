#!/usr/bin/env python3
"""Explicit Linux runtime preparation. Offline by default; never called by parsing."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "backends/node"
PINS = {
    "node-v24.22.0-linux-x64.tar.xz": (
        "https://nodejs.org/dist/v24.22.0/node-v24.22.0-linux-x64.tar.xz",
        "cc2f601cee82d9a5a233302fe307abc600727035fd7d2c3a3571755989e95008"),
    "chrome-linux64.zip": (
        "https://storage.googleapis.com/chrome-for-testing-public/155.0.8059.84/linux64/chrome-linux64.zip",
        "cf0f049892dea22e6a6db26d47ed0d7776b7158edcbec4634086633df8bafcbc"),
    "NotoSansCJKsc-Regular.otf": (
        "https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
        "2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b"),
    "NotoSansCJK-LICENSE.txt": (
        "https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/LICENSE",
        "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"),
}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1048576):
            value.update(chunk)
    return value.hexdigest()


def acquire(directory: Path, name: str, online: bool) -> Path:
    url, expected = PINS[name]
    target = directory / name
    if not target.is_file():
        if not online:
            raise ValueError(f"offline input missing: {name}")
        pending = directory / f".{name}.{os.getpid()}.part"
        try:
            with urllib.request.urlopen(url, timeout=60) as response, pending.open("xb") as output:
                while chunk := response.read(1048576):
                    output.write(chunk)
            if digest(pending) != expected:
                raise ValueError(f"download digest mismatch: {name}")
            pending.replace(target)
        finally:
            pending.unlink(missing_ok=True)
    if digest(target) != expected:
        raise ValueError(f"input digest mismatch: {name}")
    return target


def extract(node: Path, chrome: Path, output: Path) -> None:
    with tarfile.open(node) as archive:
        archive.extractall(output, filter="data")
    (output / "node-v24.22.0-linux-x64").rename(output / "node")
    with zipfile.ZipFile(chrome) as archive:
        for member in archive.infolist():
            path = PurePosixPath(member.filename)
            mode = member.external_attr >> 16
            if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(mode):
                raise ValueError("unsafe Chrome archive entry")
            target = Path(archive.extract(member, output))
            if not member.is_dir():
                target.chmod((mode & 0o777) or 0o644)
    (output / "chrome-linux64").rename(output / "chrome")


def notices(output: Path, lock: dict) -> None:
    lines = ["# Runtime third-party inputs", "", "Generated from the pinned lock and retained vendor license files.", "",
        "Node 24.22.0: node/LICENSE", "Chrome for Testing 155.0.8059.84: retained vendor notices in chrome/", 
        "Noto Sans CJK 2.004: fonts/NotoSansCJK-LICENSE.txt (SIL OFL 1.1)", "", "## npm closure", ""]
    license_root = output / "licenses"
    license_root.mkdir()
    for relative, record in sorted(lock["packages"].items()):
        if not relative:
            continue
        package = output / relative
        if not package.is_dir() and record.get("optional"):
            continue
        metadata = json.loads((package / "package.json").read_text())
        name = metadata.get("name", relative)
        license_id = metadata.get("license", record.get("license", "SEE PACKAGE"))
        if not isinstance(license_id, str):
            license_id = json.dumps(license_id, sort_keys=True)
        lines.append(f"- {name}@{metadata['version']}: {license_id}; `{relative}`")
        for source in sorted(package.iterdir()):
            if source.is_file() and source.name.lower().startswith(("license", "licence", "copying", "notice")):
                destination = license_root / relative / source.name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
    (output / "THIRD_PARTY_NOTICES.md").write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True, help="retained archives and npm-cache directory")
    parser.add_argument("--output", type=Path, required=True, help="new empty runtime directory")
    parser.add_argument("--online", action="store_true", help="explicitly allow pinned downloads and official npm registry")
    args = parser.parse_args()
    if sys.version_info < (3, 12) or sys.platform != "linux" or os.uname().machine != "x86_64":
        raise ValueError("runtime preparation requires Linux x86_64 and Python 3.12+")
    inputs = args.inputs.resolve()
    output = args.output.resolve()
    if inputs == output or inputs.is_relative_to(output) or output.is_relative_to(inputs):
        raise ValueError("runtime and input directories must be independent")
    if output.exists() and any(output.iterdir()):
        raise ValueError("runtime output must be empty")
    inputs.mkdir(parents=True, exist_ok=True, mode=0o700)
    paths = {name: acquire(inputs, name, args.online) for name in PINS}
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    output.chmod(0o700)
    extract(paths["node-v24.22.0-linux-x64.tar.xz"], paths["chrome-linux64.zip"], output)
    for name in ["package.json", "package-lock.json", "protocol.mjs", "boundary.mjs", "worker.mjs", "supervisor.py"]:
        shutil.copyfile(SOURCES / name, output / name)
    fonts = output / "fonts"
    fonts.mkdir()
    for name in ["NotoSansCJKsc-Regular.otf", "NotoSansCJK-LICENSE.txt"]:
        shutil.copyfile(paths[name], fonts / name)
    (fonts / "font.css").write_text('@font-face{font-family:MarkdownRich;src:url("./NotoSansCJKsc-Regular.otf") format("opentype");font-weight:400;font-style:normal;font-display:block}\n')
    lock = json.loads((output / "package-lock.json").read_text())
    for record in lock["packages"].values():
        if "resolved" in record and not record["resolved"].startswith("https://registry.npmjs.org/"):
            raise ValueError("lock contains a non-official registry")
    with tempfile.TemporaryDirectory(prefix="markdown-rich-setup-", dir=inputs) as scratch:
        work = Path(scratch)
        for name in ["user.conf", "global.conf"]:
            (work / name).touch(mode=0o600)
        environment = {"PATH": f"{output / 'node/bin'}:/usr/bin:/bin", "HOME": scratch, "LANG": "C.UTF-8", "TZ": "UTC",
            "TMPDIR": scratch, "TMP": scratch, "TEMP": scratch, "PUPPETEER_SKIP_DOWNLOAD": "true"}
        command = [str(output / "node/bin/node"), str(output / "node/lib/node_modules/npm/bin/npm-cli.js"), "ci",
            "--ignore-scripts", "--no-audit", "--no-fund", "--registry=https://registry.npmjs.org",
            f"--cache={inputs / 'npm-cache'}", f"--userconfig={work / 'user.conf'}", f"--globalconfig={work / 'global.conf'}"]
        if not args.online:
            command.append("--offline")
        subprocess.run(command, cwd=output, env=environment, check=True, timeout=600)
    notices(output, lock)
    files = {}
    for path in sorted(output.rglob("*")):
        if not path.is_file():
            continue
        if not path.resolve().is_relative_to(output):
            raise ValueError("runtime contains an outside symlink")
        files[path.relative_to(output).as_posix()] = digest(path)
    manifest = {"schemaVersion": 1, "producerVersion": "1", "pins": {name: value[1] for name, value in PINS.items()}, "files": files}
    encoded = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
    (output / "manifest.json").write_bytes(encoded)
    (output / "identity").write_text(hashlib.sha256(encoded).hexdigest() + "\n")
    print(f"Runtime ready: {len(files)} verified files; identity {(output / 'identity').read_text().strip()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Runtime preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
