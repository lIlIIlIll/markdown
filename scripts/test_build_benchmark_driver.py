#!/usr/bin/env python3
"""Regression tests for the benchmark driver compatibility build."""

from __future__ import annotations

from pathlib import Path
import unittest

import build_benchmark_driver


class BenchmarkDriverBuildTest(unittest.TestCase):
    def test_compatibility_manifest_changes_only_build_paths_and_lto(self) -> None:
        root = Path("/workspace/markdown")
        source = """[package]
  compile-option = "-O2 --lto thin"
  link-option = "-L ../../target/native -lmarkdown_scanner"

[dependencies]
  markdown = { path = "../.." }
"""
        self.assertEqual(
            build_benchmark_driver.compatibility_manifest(source, root),
            """[package]
  compile-option = "-O2"
  link-option = "-L /workspace/markdown/target/native -lmarkdown_scanner"

[dependencies]
  markdown = { path = "/workspace/markdown" }
""",
        )

    def test_compatibility_manifest_fails_closed_on_manifest_drift(self) -> None:
        with self.assertRaisesRegex(ValueError, "expected exactly one manifest entry"):
            build_benchmark_driver.compatibility_manifest(
                'compile-option = "-O2"\n', Path("/workspace/markdown")
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
