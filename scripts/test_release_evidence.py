#!/usr/bin/env python3
"""Regression checks for the fail-closed release evidence contract."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "release_evidence.py"
RELEASE_GATE = ROOT / "scripts" / "release_gate.sh"


class ReleaseEvidenceTest(unittest.TestCase):
    def run_checker(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_generated_reports_match_canonical_evidence(self) -> None:
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("release evidence verified", result.stdout)

    def test_draft_evidence_cannot_pass_release_ready_gate(self) -> None:
        result = self.run_checker("--release-ready")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("release status is not ready/complete", result.stderr)
        self.assertIn("source commit is unbound", result.stderr)
        self.assertIn("benchmark is not current", result.stderr)
        self.assertIn("benchmark source commit or SDK is unbound", result.stderr)

    def test_release_gate_checks_consistency_and_readiness(self) -> None:
        gate = RELEASE_GATE.read_text(encoding="utf-8")
        self.assertIn("python3 scripts/release_evidence.py\n", gate)
        self.assertIn("python3 scripts/release_evidence.py --release-ready\n", gate)


if __name__ == "__main__":
    unittest.main()
