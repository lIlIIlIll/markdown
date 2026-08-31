#!/usr/bin/env python3
"""Contract tests for optional and target-aware native scanner builds."""

from __future__ import annotations

import importlib.util
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_native_scanner", ROOT / "scripts/build_native_scanner.py")
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NativeScannerBuildTest(unittest.TestCase):
    @staticmethod
    def fake_tool_identity(tool: str,
            _environment: dict[str, str]) -> dict[str, object]:
        encoded = tool.encode("utf-8")
        return {"path": tool, "bytes": len(encoded),
            "sha256": hashlib.sha256(encoded).hexdigest(),
            "version": {"command": [tool, "--version"], "exitCode": 0,
                "stdout": f"{tool}-version\n", "stderr": ""}}

    @staticmethod
    def fake_build(calls: list[list[str]],
            environments: list[dict[str, str]] | None = None):
        def invoke(command: list[str], **_: object) -> None:
            calls.append(command)
            if environments is not None:
                environment = _.get("env")
                assert isinstance(environment, dict)
                environments.append(environment)
            output: Path | None = None
            if "-o" in command:
                output = Path(command[command.index("-o") + 1])
                content = b"object"
            else:
                msvc_object = next((value[3:] for value in command
                    if value.startswith("/Fo")), None)
                msvc_archive = next((value[5:] for value in command
                    if value.startswith("/OUT:")), None)
                if msvc_object is not None:
                    output = Path(msvc_object)
                    content = b"object"
                elif msvc_archive is not None:
                    output = Path(msvc_archive)
                    content = b"archive"
                else:
                    output = Path(command[-2])
                    content = b"archive"
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
        return invoke

    def run_main(self, *arguments: str) -> tuple[int, list[list[str]]]:
        calls: list[list[str]] = []
        with tempfile.TemporaryDirectory(prefix="markdown-native-build-test-") as directory:
            with mock.patch.object(sys, "argv", ["build_native_scanner.py", *arguments, "--out-dir", directory]), \
                    mock.patch.object(MODULE.subprocess, "check_call",
                        side_effect=self.fake_build(calls)), \
                    mock.patch.object(MODULE, "find_tool",
                        side_effect=lambda _, default, _environment: default), \
                    mock.patch.object(MODULE, "tool_identity",
                        side_effect=self.fake_tool_identity):
                result = MODULE.main()
        return result, calls

    def test_default_is_a_true_noop(self) -> None:
        result, calls = self.run_main()
        self.assertEqual(result, 0)
        self.assertEqual(calls, [])

    def test_linux_cross_target_uses_target_aware_clang_and_archive(self) -> None:
        result, calls = self.run_main("--enable", "--target", "aarch64-unknown-linux-gnu")
        self.assertEqual(result, 0)
        self.assertEqual(calls[0][0], "clang")
        self.assertIn("-target", calls[0])
        self.assertIn("aarch64-unknown-linux-gnu", calls[0])
        self.assertIn("-fPIC", calls[0])
        self.assertTrue(calls[1][-2].endswith("libmarkdown_scanner.a"))

    def test_mingw_uses_gnu_archive_without_pic(self) -> None:
        _, calls = self.run_main("--enable", "--target", "x86_64-w64-mingw32")
        self.assertNotIn("-fPIC", calls[0])
        self.assertTrue(calls[1][-2].endswith("libmarkdown_scanner.a"))

    def test_msvc_uses_obj_and_lib_tool(self) -> None:
        _, calls = self.run_main("--enable", "--target", "x86_64-windows-msvc")
        self.assertEqual(calls[0][0], "cl")
        self.assertEqual(calls[1][0], "lib")
        self.assertTrue(any(value.endswith("markdown_scanner.obj") for value in calls[0]))
        self.assertTrue(any("markdown_scanner.lib" in value for value in calls[1]))

    def test_cache_identity_binds_target_tools_flags_and_content(self) -> None:
        with tempfile.TemporaryDirectory(prefix="markdown-native-plan-test-") as directory:
            out_dir = Path(directory)
            source = out_dir / "scanner.c"
            header = out_dir / "scanner.h"
            source.write_text("int scan(void) { return 1; }\n", encoding="utf-8")
            header.write_text("int scan(void);\n", encoding="utf-8")
            with mock.patch.object(MODULE, "find_tool",
                    side_effect=lambda name, _, _environment: f"/{name.lower()}"), \
                    mock.patch.object(MODULE, "tool_identity",
                        side_effect=self.fake_tool_identity), \
                    mock.patch.dict(MODULE.os.environ, {
                        "MARKDOWN_NATIVE_CFLAGS": "-DPROFILE=1",
                        "MARKDOWN_NATIVE_ARFLAGS": "D",
                    }, clear=False):
                _, _, first = MODULE.build_plan(
                    "aarch64-unknown-linux-gnu", False, out_dir, source, header
                )
                _, _, second = MODULE.build_plan(
                    "x86_64-unknown-linux-gnu", False, out_dir, source, header
                )
            self.assertNotEqual(first, second)
            self.assertEqual(first["target"], "aarch64-unknown-linux-gnu")
            self.assertEqual(first["compiler"], self.fake_tool_identity("/cc", {}))
            self.assertIn("-DPROFILE=1", first["compileCommand"])
            self.assertIn("D", first["archiveCommand"])

            source.write_text("int scan(void) { return 2; }\n", encoding="utf-8")
            with mock.patch.object(MODULE, "find_tool",
                    side_effect=lambda name, _, _environment: f"/{name.lower()}"), \
                    mock.patch.object(MODULE, "tool_identity",
                        side_effect=self.fake_tool_identity):
                _, _, changed = MODULE.build_plan(
                    "aarch64-unknown-linux-gnu", False, out_dir, source, header
                )
            self.assertNotEqual(first["sourceSha256"], changed["sourceSha256"])

    def run_cached_build(self, out_dir: Path,
            environments: list[dict[str, str]] | None = None) -> list[list[str]]:
        calls: list[list[str]] = []
        with mock.patch.object(sys, "argv", ["build_native_scanner.py", "--enable",
                    "--target", "x86_64-unknown-linux-gnu", "--out-dir", str(out_dir)]), \
                mock.patch.object(MODULE.subprocess, "check_call",
                    side_effect=self.fake_build(calls, environments)), \
                mock.patch.object(MODULE, "find_tool",
                    side_effect=lambda _, default, _environment: default), \
                mock.patch.object(MODULE, "tool_identity",
                    side_effect=self.fake_tool_identity):
            self.assertEqual(MODULE.main(), 0)
        return calls

    def test_cache_hit_recomputes_and_binds_object_and_archive_digests(self) -> None:
        with tempfile.TemporaryDirectory(prefix="markdown-native-cache-test-") as directory:
            out_dir = Path(directory)
            self.assertEqual(len(self.run_cached_build(out_dir)), 2)
            self.assertEqual(self.run_cached_build(out_dir), [])
            manifest = json.loads(
                (out_dir / MODULE.CACHE_MANIFEST_NAME).read_text(encoding="utf-8"))
            self.assertEqual(manifest["schemaVersion"], 3)
            for field, filename in (("object", "markdown_scanner.o"),
                    ("archive", "libmarkdown_scanner.a")):
                path = out_dir / filename
                self.assertEqual(manifest[field], MODULE.file_identity(path))

    def test_tampered_object_invalidates_cache_and_rebuilds_both_outputs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="markdown-native-cache-test-") as directory:
            out_dir = Path(directory)
            self.run_cached_build(out_dir)
            (out_dir / "markdown_scanner.o").write_bytes(b"tampered-object")
            self.assertEqual(len(self.run_cached_build(out_dir)), 2)
            manifest = json.loads(
                (out_dir / MODULE.CACHE_MANIFEST_NAME).read_text(encoding="utf-8"))
            self.assertEqual(manifest["object"],
                MODULE.file_identity(out_dir / "markdown_scanner.o"))
            self.assertEqual(manifest["archive"],
                MODULE.file_identity(out_dir / "libmarkdown_scanner.a"))

    def test_tampered_archive_invalidates_cache_and_rebuilds_both_outputs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="markdown-native-cache-test-") as directory:
            out_dir = Path(directory)
            self.run_cached_build(out_dir)
            (out_dir / "libmarkdown_scanner.a").write_bytes(b"tampered-archive")
            self.assertEqual(len(self.run_cached_build(out_dir)), 2)
            manifest = json.loads(
                (out_dir / MODULE.CACHE_MANIFEST_NAME).read_text(encoding="utf-8"))
            self.assertEqual(manifest["object"],
                MODULE.file_identity(out_dir / "markdown_scanner.o"))
            self.assertEqual(manifest["archive"],
                MODULE.file_identity(out_dir / "libmarkdown_scanner.a"))

    def test_ambient_variables_cannot_reach_the_child_or_change_the_cache(self) -> None:
        for name in ("CPATH", "LIBRARY_PATH", "LD_PRELOAD",
                "CCC_OVERRIDE_OPTIONS", "MARKDOWN_RANDOM_UNKNOWN"):
            with self.subTest(variable=name), \
                    tempfile.TemporaryDirectory(
                        prefix="markdown-native-environment-test-") as directory:
                out_dir = Path(directory)
                clean = dict(MODULE.os.environ)
                clean.pop(name, None)
                polluted = {**clean, name: f"/tmp/{name.lower()}-pollution"}
                observed: list[dict[str, str]] = []
                with mock.patch.object(MODULE.os, "environ", polluted):
                    self.assertEqual(len(self.run_cached_build(out_dir, observed)), 2)
                self.assertEqual(len(observed), 2)
                self.assertNotIn(name, observed[0])
                self.assertEqual(observed[0], observed[1])
                with mock.patch.object(MODULE.os, "environ", clean):
                    self.assertEqual(self.run_cached_build(out_dir), [])
                manifest = json.loads((out_dir / MODULE.CACHE_MANIFEST_NAME).read_text(
                    encoding="utf-8"))
                environment = manifest["buildEnvironment"]
                self.assertEqual(environment["variables"], observed[0])
                self.assertEqual(environment["allowlist"],
                    sorted(MODULE.NATIVE_BUILD_ENVIRONMENT_KEYS))
                self.assertEqual(environment["sha256"],
                    MODULE.canonical_json_sha256(environment["variables"]))

    def test_same_version_text_does_not_hide_a_changed_tool_binary(self) -> None:
        with tempfile.TemporaryDirectory(
                prefix="markdown-native-tool-test-") as directory:
            out_dir = Path(directory)
            compiler = out_dir / "compiler-wrapper"
            archiver = out_dir / "archiver-wrapper"
            compiler.write_text("#!/bin/sh\necho stable-version\n", encoding="utf-8")
            archiver.write_text("#!/bin/sh\necho stable-version\n", encoding="utf-8")
            compiler.chmod(0o755)
            archiver.chmod(0o755)
            source = out_dir / "scanner.c"
            header = out_dir / "scanner.h"
            source.write_text("int scan(void) { return 1; }\n", encoding="utf-8")
            header.write_text("int scan(void);\n", encoding="utf-8")
            tools = {"CC": str(compiler), "AR": str(archiver)}
            host = {"PATH": "/usr/bin:/bin", **tools}
            first = MODULE.build_plan("x86_64-unknown-linux-gnu", False,
                out_dir, source, header, host)[2]
            compiler.write_text(
                "#!/bin/sh\n# changed wrapper\necho stable-version\n", encoding="utf-8")
            compiler.chmod(0o755)
            second = MODULE.build_plan("x86_64-unknown-linux-gnu", False,
                out_dir, source, header, host)[2]
            self.assertEqual(first["compiler"]["version"],
                second["compiler"]["version"])
            self.assertNotEqual(first["compiler"]["sha256"],
                second["compiler"]["sha256"])
            self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main()
