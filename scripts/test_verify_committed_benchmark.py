#!/usr/bin/env python3
"""Regression tests for selecting and unpacking canonical benchmark inputs."""

from io import BytesIO
import json
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import verify_committed_benchmark as verifier


class CanonicalBenchmarkInputsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="markdown-canonical-inputs-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def archive(self, entries):
        data = BytesIO()
        with tarfile.open(fileobj=data, mode="w") as bundle:
            for name, kind, value in entries:
                entry = tarfile.TarInfo(name)
                entry.mode = 0o755
                entry.type = kind
                entry.size = len(value) if kind == tarfile.REGTYPE else 0
                entry.linkname = "outside" if kind == tarfile.SYMTYPE else ""
                bundle.addfile(entry, BytesIO(value) if kind == tarfile.REGTYPE else None)
        destination = self.root / "artifact.zip"
        with zipfile.ZipFile(destination, "w") as bundle:
            bundle.writestr(verifier.ARCHIVE_NAME, data.getvalue())
        return destination

    def identity(self):
        return {"schemaVersion": 1, "repository": "owner/project", "runId": 10,
            "artifactId": 20, "artifactSha256": "a" * 64, "reportSha256": "b" * 64}

    def test_report_must_match_pinned_digest(self):
        report = self.root / "report.json"
        report.write_text("{}")
        manifest = self.root / "manifest.json"
        identity = self.identity()
        manifest.write_text(json.dumps(identity))
        with self.assertRaisesRegex(ValueError, "committed report differs"):
            verifier.load_identity(manifest, report)
        identity["reportSha256"] = verifier.sha256(report)
        manifest.write_text(json.dumps(identity))
        self.assertEqual(verifier.load_identity(manifest, report), identity)

    def test_artifact_run_digest_expiry_and_size_are_bound(self):
        identity = self.identity()
        valid = {"id": 20, "name": verifier.ARTIFACT_NAME, "expired": False,
            "workflow_run": {"id": 10}, "digest": "sha256:" + "a" * 64,
            "size_in_bytes": 100}
        verifier.validate_artifact(valid, identity)
        for replacement in ({"id": 21}, {"workflow_run": {"id": 11}},
                {"digest": "sha256:" + "c" * 64}, {"expired": True},
                {"name": "other"}, {"size_in_bytes": verifier.MAX_ARCHIVE_BYTES + 1}):
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                verifier.validate_artifact(valid | replacement, identity)

    def test_archive_digest_is_checked_before_extraction(self):
        archive = self.archive([("binary", tarfile.REGTYPE, b"executable")])
        destination = self.root / "unpacked"
        with self.assertRaisesRegex(ValueError, "digest differs"):
            verifier.extract_inputs(archive, destination, "0" * 64)
        self.assertFalse(destination.exists())

    def test_regular_files_retain_executable_modes(self):
        archive = self.archive([("./binaries/driver", tarfile.REGTYPE, b"executable")])
        inputs = verifier.extract_inputs(archive, self.root / "unpacked", verifier.sha256(archive))
        driver = inputs / "binaries/driver"
        self.assertEqual(driver.read_bytes(), b"executable")
        self.assertEqual(stat.S_IMODE(driver.stat().st_mode), 0o755)

    def test_tar_rejects_traversal_links_and_duplicate_paths(self):
        cases = [[("../outside", tarfile.REGTYPE, b"bad")],
            [("/outside", tarfile.REGTYPE, b"bad")],
            [("link", tarfile.SYMTYPE, b"")],
            [("driver", tarfile.REGTYPE, b"a"), ("./driver", tarfile.REGTYPE, b"b")]]
        for index, entries in enumerate(cases):
            with self.subTest(entries=entries):
                archive = self.archive(entries)
                with self.assertRaises(ValueError):
                    verifier.extract_inputs(archive, self.root / str(index), verifier.sha256(archive))
        self.assertFalse((self.root / "outside").exists())

    def test_extraction_limits_and_extra_zip_entries_fail_closed(self):
        archive = self.archive([("driver", tarfile.REGTYPE, b"abcdef")])
        with patch.object(verifier, "MAX_EXTRACTED_BYTES", 2), self.assertRaises(ValueError):
            verifier.extract_inputs(archive, self.root / "large", verifier.sha256(archive))
        with zipfile.ZipFile(archive, "a") as bundle:
            bundle.writestr("extra", b"unexpected")
        with self.assertRaisesRegex(ValueError, "one bounded evidence tar"):
            verifier.extract_inputs(archive, self.root / "extra", verifier.sha256(archive))

    def test_verification_uses_committed_report_and_current_product(self):
        inputs = self.root / "inputs"
        inputs.mkdir()
        report = self.root / "report.json"
        report.write_text("{}")
        (inputs / "markdown4cj-comparison-raw.json").write_bytes(report.read_bytes())
        product = self.root / "current-product"
        with patch.object(verifier.subprocess, "run") as run:
            verifier.verify_inputs(inputs, report, self.root / "report.md", product)
        command = run.call_args.args[0]
        self.assertEqual(command[command.index("--product-source") + 1], str(product))
        self.assertEqual(command[command.index("--binary-root") + 1], str(inputs / "binaries"))
        self.assertIn("--require-current-product", command)
        self.assertTrue(run.call_args.kwargs["check"])
        (inputs / "markdown4cj-comparison-raw.json").write_text('{"changed":true}')
        with patch.object(verifier.subprocess, "run") as run, self.assertRaises(ValueError):
            verifier.verify_inputs(inputs, report, self.root / "report.md", product)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
