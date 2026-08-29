#!/usr/bin/env python3
"""Regression checks for the fail-closed release evidence contract."""

from __future__ import annotations

from pathlib import Path
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "release_evidence.py"
RELEASE_GATE = ROOT / "scripts" / "release_gate.sh"

SPEC = importlib.util.spec_from_file_location("release_evidence", CHECKER)
assert SPEC is not None and SPEC.loader is not None
release_evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_evidence)


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
        self.assertIsInstance(evidence["release"]["evidenceReady"], bool)
        self.assertIsInstance(evidence["release"]["ciVerifiedAtHead"], bool)
        self.assertFalse(evidence["release"]["published"])
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        expected_ready = "ready" if evidence["release"]["evidenceReady"] else "not ready"
        expected_ci = "yes" if evidence["release"]["ciVerifiedAtHead"] else "no"
        self.assertIn(f"| Offline evidence ready | `{expected_ready}` |", readme)
        self.assertIn(f"| CI verified at evidence repository HEAD | `{expected_ci}` |", readme)
        self.assertIn("| Published release | `no` |", readme)

    def test_current_identity_rejects_corpus_and_product_tree_drift(self) -> None:
        raw = {
            "identity": {"productTreeSha256": "old-tree"},
            "corpora": {"readme-api": {"bytes": 3, "sha256": "old-corpus"}},
        }
        benchmark = {"productTreeSha256": "old-tree"}
        with patch.object(release_evidence, "benchmark_corpora",
                return_value={"readme-api": b"new"}), patch.object(
                    release_evidence, "benchmark_product_tree_sha256",
                    return_value="new-tree"):
            errors = release_evidence.validate_current_benchmark_identity(raw, benchmark)
        self.assertIn("benchmark corpus digest mismatch: readme-api", errors)
        self.assertIn("benchmark product tree does not match current sources", errors)

    def test_product_tree_identity_is_deterministic_and_content_sensitive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "src" / "parser.cj"
            source.parent.mkdir(parents=True)
            source.write_text("package markdown\n", encoding="utf-8")
            first = release_evidence.benchmark_product_tree_sha256(root)
            second = release_evidence.benchmark_product_tree_sha256(root)
            self.assertEqual(first, second)

            source.write_text("package markdown\n// changed\n", encoding="utf-8")
            self.assertNotEqual(first, release_evidence.benchmark_product_tree_sha256(root))

    def test_release_gate_checks_consistency_and_readiness(self) -> None:
        gate = RELEASE_GATE.read_text(encoding="utf-8")
        self.assertIn("python3 scripts/release_evidence.py\n", gate)
        self.assertIn("python3 scripts/release_evidence.py --evidence-ready\n", gate)
        self.assertNotIn("python3 benchmarks/measure.py\n", gate)


if __name__ == "__main__":
    unittest.main()
