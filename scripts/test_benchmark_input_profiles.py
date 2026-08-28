#!/usr/bin/env python3
"""Verify that public input APIs have distinct, executable benchmark profiles."""

from __future__ import annotations

import ast
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "benchmarks" / "driver" / "target" / "release" / "bin" / "main"
MEASURE = ROOT / "benchmarks" / "measure.py"
MODES = (
    "commonmark-parse",
    "commonmark-parse-string",
    "commonmark-parse-bytes",
    "commonmark-parse-owned",
    "commonmark-parse-stream",
)
GFM_MODES = ("gfm-parse", "gfm-html")


class BenchmarkInputProfilesTest(unittest.TestCase):
    def test_measurement_schema_uses_python_literals(self) -> None:
        tree = ast.parse(MEASURE.read_text(encoding="utf-8"), filename=str(MEASURE))
        names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
        self.assertTrue({"false", "true", "null"}.isdisjoint(names), names)

    def test_measurement_schema_declares_every_public_input_profile(self) -> None:
        source = MEASURE.read_text(encoding="utf-8")
        self.assertIn('"inputProfiles": {', source)
        for mode in MODES:
            self.assertIn(f'"driverMode": "{mode}"', source)
        for identity_field in (
            "sourceCommit",
            "productSourceArchiveSha256",
            "benchmarkHarnessSha256",
            "markdownDriverSha256",
            "cmarkDriverSha256",
            "cmarkGfmDriverSha256",
        ):
            self.assertIn(f'"{identity_field}"', source)
        self.assertIn('"phaseProfiles": {"gfm": gfm_phases}', source)
        self.assertIn('"diagnosticOnly": True', source)
        self.assertIn('"gfm-parse"', source)

    def test_driver_profiles_produce_the_same_parse_checksum(self) -> None:
        self.assertTrue(DRIVER.exists(), f"benchmark driver is not built: {DRIVER}")
        source = "# heading\r\n\r\nText *em* 😀\n".encode()
        checksums: list[str] = []
        for mode in MODES:
            result = subprocess.run(
                [str(DRIVER), mode, "2"],
                input=source,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            checksums.append(result.stdout.decode().strip())
        self.assertEqual(len(set(checksums)), 1, checksums)

    def test_gfm_phase_profiles_are_executable(self) -> None:
        self.assertTrue(DRIVER.exists(), f"benchmark driver is not built: {DRIVER}")
        source = "| a | b |\n| - | - |\n| ~~x~~ | https://example.com |\n".encode()
        for mode in GFM_MODES:
            result = subprocess.run(
                [str(DRIVER), mode, "2"],
                input=source,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertGreater(int(result.stdout.decode().strip()), 0)


if __name__ == "__main__":
    unittest.main()
