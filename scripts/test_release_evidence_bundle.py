#!/usr/bin/env python3
"""Tests for metrics derived from retained release evidence files."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release_evidence_bundle", ROOT / "scripts/release_evidence_bundle.py"
)
assert SPEC is not None and SPEC.loader is not None
bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bundle)


class ReleaseEvidenceBundleTest(unittest.TestCase):
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
