#!/usr/bin/env python3
"""Contract tests for optional and target-aware native scanner builds."""

from __future__ import annotations

import importlib.util
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
    def run_main(self, *arguments: str) -> tuple[int, list[list[str]]]:
        calls: list[list[str]] = []
        with tempfile.TemporaryDirectory(prefix="markdown-native-build-test-") as directory:
            with mock.patch.object(sys, "argv", ["build_native_scanner.py", *arguments, "--out-dir", directory]), \
                    mock.patch.object(MODULE.subprocess, "check_call", side_effect=lambda command, **_: calls.append(command)), \
                    mock.patch.object(MODULE, "find_tool", side_effect=lambda _, default: default), \
                    mock.patch.object(MODULE, "tool_version", side_effect=lambda tool: f"{tool}-version"):
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
        self.assertIn("--target", calls[0])
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
            with mock.patch.object(MODULE, "find_tool", side_effect=lambda name, _: f"/{name.lower()}"), \
                    mock.patch.object(MODULE, "tool_version", side_effect=lambda tool: f"{tool}-v1"), \
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
            self.assertEqual(first["compiler"], {"path": "/cc", "version": "/cc-v1"})
            self.assertIn("-DPROFILE=1", first["compileCommand"])
            self.assertIn("D", first["archiveCommand"])

            source.write_text("int scan(void) { return 2; }\n", encoding="utf-8")
            with mock.patch.object(MODULE, "find_tool", side_effect=lambda name, _: f"/{name.lower()}"), \
                    mock.patch.object(MODULE, "tool_version", side_effect=lambda tool: f"{tool}-v1"):
                _, _, changed = MODULE.build_plan(
                    "aarch64-unknown-linux-gnu", False, out_dir, source, header
                )
            self.assertNotEqual(first["sourceSha256"], changed["sourceSha256"])


if __name__ == "__main__":
    unittest.main()
