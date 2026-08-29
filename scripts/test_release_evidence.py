#!/usr/bin/env python3
"""Regression checks for the fail-closed release evidence contract."""

from __future__ import annotations

from pathlib import Path
import json
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

    def test_current_evidence_enforces_declared_readiness(self) -> None:
        result = self.run_checker("--evidence-ready")
        evidence = json.loads((ROOT / "release-evidence.json").read_text(encoding="utf-8"))
        if evidence["release"]["status"] == "evidence-ready" and evidence["release"]["evidenceReady"]:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("release evidence verified", result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("offline evidence status is not evidence-ready", result.stderr)

    def test_ci_and_publication_are_separate_from_offline_evidence(self) -> None:
        evidence = json.loads((ROOT / "release-evidence.json").read_text(encoding="utf-8"))
        self.assertTrue(evidence["release"]["evidenceReady"])
        self.assertFalse(evidence["release"]["ciVerifiedAtHead"])
        self.assertFalse(evidence["release"]["published"])
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("| Offline evidence ready | `ready` |", readme)
        self.assertIn("| CI verified at evidence repository HEAD | `no` |", readme)
        self.assertIn("| Published release | `no` |", readme)

    def test_release_gate_checks_consistency_and_readiness(self) -> None:
        gate = RELEASE_GATE.read_text(encoding="utf-8")
        self.assertIn("python3 scripts/release_evidence.py\n", gate)
        self.assertIn("python3 scripts/release_evidence.py --evidence-ready\n", gate)
        self.assertNotIn("python3 benchmarks/measure.py\n", gate)


if __name__ == "__main__":
    unittest.main()
