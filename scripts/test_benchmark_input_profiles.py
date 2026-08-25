#!/usr/bin/env python3
"""Verify that public input APIs have distinct, executable benchmark profiles."""

from __future__ import annotations

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "benchmarks" / "driver" / "target" / "release" / "bin" / "main"
MEASURE = ROOT / "benchmarks" / "measure.py"
MODES = (
    "commonmark-parse-string",
    "commonmark-parse-bytes",
    "commonmark-parse-owned",
    "commonmark-parse-stream",
)


class BenchmarkInputProfilesTest(unittest.TestCase):
    def test_measurement_schema_declares_every_public_input_profile(self) -> None:
        source = MEASURE.read_text(encoding="utf-8")
        self.assertIn('"inputProfiles": {', source)
        for mode in MODES:
            self.assertIn(f'"driverMode": "{mode}"', source)

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


if __name__ == "__main__":
    unittest.main()
