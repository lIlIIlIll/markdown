#!/usr/bin/env python3
"""Tests for metrics derived from retained release evidence files."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release_evidence_bundle", ROOT / "scripts/release_evidence_bundle.py"
)
assert SPEC is not None and SPEC.loader is not None
bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bundle)


class ReleaseEvidenceBundleTest(unittest.TestCase):
    def test_explicit_release_commit_uses_publishable_identity_with_same_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Evidence Test"],
                cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "evidence@example.invalid"],
                cwd=root, check=True)
            source = root / "src" / "parser.cj"
            source.parent.mkdir()
            source.write_text("package markdown\n", encoding="utf-8")
            subprocess.run(["git", "add", "src/parser.cj"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "test: publishable"],
                cwd=root, check=True)
            publishable = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True
            ).strip()
            subprocess.run(
                ["git", "commit", "--allow-empty", "-qm", "test: workspace"],
                cwd=root, check=True,
            )

            original_root = bundle.ROOT
            bundle.ROOT = root
            try:
                with patch.dict("os.environ", {"MARKDOWN_RELEASE_COMMIT": publishable}):
                    reference, commit, tree = bundle.release_subject_identity()
                self.assertEqual(reference, publishable)
                self.assertEqual(commit, publishable)
                self.assertTrue(bundle.working_tree_matches_subject(tree))
                source.write_text("package markdown\n// dirty\n", encoding="utf-8")
                self.assertFalse(bundle.working_tree_matches_subject(tree))
            finally:
                bundle.ROOT = original_root

    def test_junit_counts_are_derived_from_xml(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "commonmark.xml").write_text(
                '<testsuite name="markdown.CommonMark0312ConformanceTest" '
                'tests="3" failures="0" errors="0" skipped="1"/>\n', encoding="utf-8"
            )
            (root / "other.xml").write_text(
                '<testsuite name="markdown.OtherTest" tests="2" failures="1" '
                'errors="0" skipped="0"/>\n', encoding="utf-8"
            )
            totals, suites = bundle.junit_metrics(root)
        self.assertEqual(totals, {
            "total": 5, "passed": 3, "skipped": 1, "failures": 1, "errors": 0,
        })
        self.assertEqual(suites["markdown.CommonMark0312ConformanceTest"]["passed"], 2)

    def test_checksum_verification_rejects_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "result.json"
            artifact.write_text(json.dumps({"passed": 1}) + "\n", encoding="utf-8")
            (root / "SHA256SUMS").write_text(
                f"{bundle.sha256(artifact)}  result.json\n", encoding="utf-8"
            )
            self.assertEqual(bundle.verify_checksums(root), [])
            artifact.write_text(json.dumps({"passed": 999}) + "\n", encoding="utf-8")
            self.assertEqual(
                bundle.verify_checksums(root),
                ["release evidence checksum mismatch: result.json"],
            )

    def test_checksum_verification_rejects_unlisted_and_stale_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "result.json"
            artifact.write_text(json.dumps({"passed": 1}) + "\n", encoding="utf-8")
            (root / "SHA256SUMS").write_text(
                f"{bundle.sha256(artifact)}  result.json\n", encoding="utf-8"
            )
            injected = root / "candidate" / "injected.cjp"
            injected.parent.mkdir()
            injected.write_bytes(b"untrusted")
            self.assertEqual(
                bundle.verify_checksums(root),
                ["release evidence file is missing from SHA256SUMS: candidate/injected.cjp"],
            )
            injected.unlink()
            artifact.unlink()
            self.assertEqual(
                bundle.verify_checksums(root),
                ["release evidence checksum mismatch: result.json"],
            )

    def test_snapshot_survives_target_cleanup_and_publish(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            work = root / "work"
            retained = root / "retained"
            report = root / "target" / "release-tests" / "report.xml"
            report.parent.mkdir(parents=True)
            report.write_text('<testsuite name="x" tests="1"/>\n', encoding="utf-8")
            original_root = bundle.ROOT
            bundle.ROOT = root
            try:
                bundle.snapshot_artifacts(work)
                shutil.rmtree(root / "target")
                bundle.snapshot_artifacts(work)
                bundle.publish(work, retained)
            finally:
                bundle.ROOT = original_root
            self.assertEqual(
                (retained / "junit" / "report.xml").read_text(encoding="utf-8"),
                '<testsuite name="x" tests="1"/>\n',
            )


if __name__ == "__main__":
    unittest.main()
