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
COMMONMARK_JS_DRIVER = ROOT / "scripts" / "commonmark_js_driver.mjs"
DIFFERENTIAL_SETUP = ROOT / "scripts" / "setup_differential_tools.sh"
DIFFERENTIAL_TEST = ROOT / "scripts" / "differential_test.py"

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

    def test_generated_sections_include_all_current_metrics(self) -> None:
        evidence = json.loads((ROOT / "release-evidence.json").read_text(encoding="utf-8"))
        readme = release_evidence.readme_block(evidence)
        changelog = release_evidence.changelog_block(evidence)
        performance = release_evidence.performance_block(evidence)
        tests = evidence["tests"]
        api = evidence["api"]
        conformance = evidence["conformance"]
        benchmark = evidence["benchmark"]
        self.assertIn(
            f"| Tests | `{tests['passed']}/{tests['total']}` passed; "
            f"`{tests['skipped']}` skipped; `{tests['failed']}` failed |",
            readme,
        )
        for name, label in (("commonmark", "CommonMark"), ("gfm", "GFM")):
            result = conformance[name]
            self.assertIn(
                f"| {label} conformance | `{result['passed']}/{result['total']}` |",
                readme,
            )
        self.assertIn(
            f"| Public API snapshot | `{api['declarations']}` declarations |", readme
        )
        self.assertIn(
            f"{'canonical' if benchmark['status'] == 'current' else 'last complete'} "
            f"CommonMark ratio `{benchmark['commonmarkRatio']:.6f}x`",
            changelog,
        )
        self.assertIn(
            f"{'canonical' if benchmark['status'] == 'current' else 'last complete'} "
            f"GFM ratio `{benchmark['gfmRatio']:.6f}x`",
            changelog,
        )
        self.assertIn(
            f"| CommonMark 完整 AST parse | cmark 0.31.1 | "
            f"`{benchmark['commonmarkRatio']:.6f}x` |",
            performance,
        )
        self.assertIn(
            f"| GFM 完整 AST + HTML | cmark-gfm 0.29 | "
            f"`{benchmark['gfmRatio']:.6f}x` |",
            performance,
        )

    def test_replace_section_owns_the_complete_current_section(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "README.md"
            path.write_text(
                "# Example\n\n## Evidence\n\nstale metric\n\n## Next\n\nkeep me\n",
                encoding="utf-8",
            )
            expected = release_evidence.replace_section(
                path, "## Evidence", "## Next", "generated metric"
            )
        self.assertEqual(
            expected,
            "# Example\n\n## Evidence\n\ngenerated metric\n\n## Next\n\nkeep me\n",
        )

    def test_incomplete_release_can_project_current_failing_benchmark(self) -> None:
        evidence = json.loads((ROOT / "release-evidence.json").read_text(encoding="utf-8"))
        if evidence["benchmark"]["status"] == "current" and not evidence["release"]["evidenceReady"]:
            raw = json.loads((ROOT / evidence["benchmark"]["rawPath"]).read_text(encoding="utf-8"))
            if not all(raw["gates"].values()):
                result = self.run_checker()
                self.assertEqual(result.returncode, 0, result.stderr)
                ready = self.run_checker("--evidence-ready")
                self.assertNotEqual(ready.returncode, 0, ready.stdout)
                self.assertIn("canonical benchmark gates failed", ready.stderr)

    def test_current_evidence_enforces_declared_readiness(self) -> None:
        result = self.run_checker("--evidence-ready")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("evidence-ready validation requires an execution manifest", result.stderr)

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
            "identity": {
                "productTreeSha256": "old-tree",
                "benchmarkHarnessSha256": "old-harness",
            },
            "corpora": {"readme-api": {"bytes": 3, "sha256": "old-corpus"}},
        }
        benchmark = {
            "productTreeSha256": "old-tree",
            "benchmarkHarnessSha256": "old-harness",
        }
        with patch.object(release_evidence, "benchmark_corpora",
                return_value={"readme-api": b"new"}), patch.object(
                    release_evidence, "benchmark_product_tree_sha256",
                    return_value="new-tree"), patch.object(
                    release_evidence, "benchmark_harness_sha256", return_value="new-harness"), patch.object(
                    release_evidence, "validate_benchmark_derivations", return_value=[]):
            errors = release_evidence.validate_current_benchmark_identity(raw, benchmark)
        self.assertIn("benchmark corpus digest mismatch: readme-api", errors)
        self.assertIn("benchmark product tree does not match current sources", errors)
        self.assertIn("benchmark harness does not match current harness files", errors)

    def test_current_identity_recomputes_benchmark_summary_from_samples(self) -> None:
        raw = json.loads((ROOT / "docs/reports/benchmark-raw.json").read_text(encoding="utf-8"))
        raw["commonmark"]["geometricMeanRatio"] = 0.01
        raw["scaling"]["slope"] = 0.01
        raw["memory"]["extraPeakRssKiB"] = 0
        raw["gates"]["commonmarkRatioLe2_5"] = False
        errors = release_evidence.validate_benchmark_derivations(raw)
        self.assertIn("benchmark derived value mismatch: commonmark.geometricMeanRatio", errors)
        self.assertIn("benchmark derived value mismatch: scaling.slope", errors)
        self.assertIn("benchmark derived value mismatch: memory.extraPeakRssKiB", errors)
        self.assertIn("benchmark derived value mismatch: gates.commonmarkRatioLe2_5", errors)

    def test_current_identity_rejects_unreachable_commit(self) -> None:
        errors = release_evidence.validate_reachable_commit(
            "0000000000000000000000000000000000000000", "benchmark source"
        )
        self.assertEqual(
            errors,
            [
                "benchmark source commit is not reachable from repository HEAD: "
                "0000000000000000000000000000000000000000"
            ],
        )

    def test_execution_manifest_requires_sdk_archive_sha256(self) -> None:
        self.assertEqual(
            release_evidence.validate_sdk_archive_identity({"toolchain": {}}),
            ["release execution manifest has no valid SDK archive SHA-256"],
        )
        self.assertEqual(
            release_evidence.validate_sdk_archive_identity({
                "toolchain": {"sdkArchiveSha256": "g" * 64}
            }),
            ["release execution manifest has no valid SDK archive SHA-256"],
        )
        self.assertEqual(
            release_evidence.validate_sdk_archive_identity({
                "toolchain": {"sdkArchiveSha256": "0" * 64}
            }),
            [],
        )

    def test_execution_identity_accepts_publishable_commit_with_exact_workspace_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Evidence Test"],
                cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "evidence@example.invalid"],
                cwd=root, check=True)
            source = root / "src" / "parser.cj"
            source.parent.mkdir()
            source.write_text("same tree\n", encoding="utf-8")
            subprocess.run(["git", "add", "src/parser.cj"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "test: publishable"],
                cwd=root, check=True)
            publishable = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True
            ).strip()
            tree = subprocess.check_output(
                ["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True
            ).strip()
            subprocess.run(
                ["git", "commit", "--allow-empty", "-qm", "test: workspace"],
                cwd=root, check=True,
            )
            workspace = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True
            ).strip()
            manifest = {"repositoryCommit": publishable, "gitTree": tree}
            with patch.object(release_evidence, "ROOT", root):
                with patch.dict("os.environ", {"MARKDOWN_RELEASE_COMMIT": publishable}):
                    self.assertEqual(
                        release_evidence.validate_execution_repository_identity(manifest), []
                    )
                with patch.dict("os.environ", {"MARKDOWN_RELEASE_COMMIT": workspace}):
                    self.assertIn(
                        "release execution commit does not match MARKDOWN_RELEASE_COMMIT",
                        release_evidence.validate_execution_repository_identity(manifest),
                    )

    def test_commit_git_tree_must_match_declared_tree(self) -> None:
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        errors = release_evidence.validate_commit_git_tree(head, "benchmark source", "0" * 40)
        self.assertEqual(
            errors,
            [f"benchmark source Git tree does not match commit: {head}"],
        )
    def test_reachable_ancestor_cannot_alias_a_different_product_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Audit Test"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "audit@example.invalid"],
                cwd=root, check=True)
            source = root / "src" / "parser.cj"
            source.parent.mkdir()
            source.write_text("package markdown\n", encoding="utf-8")
            subprocess.run(["git", "add", "src/parser.cj"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "test: baseline"], cwd=root, check=True)
            parent = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True
            ).strip()
            source.write_text("package markdown\n// changed\n", encoding="utf-8")
            subprocess.run(["git", "commit", "-qam", "test: change product"], cwd=root, check=True)
            head = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True
            ).strip()
            expected = release_evidence.benchmark_product_tree_sha256_at_commit(head, root)
            parent_tree = release_evidence.benchmark_product_tree_sha256_at_commit(parent, root)
            self.assertNotEqual(expected, parent_tree)
            with patch.object(release_evidence, "ROOT", root):
                errors = release_evidence.validate_commit_product_tree(
                    parent, "benchmark source", expected
                )
            self.assertEqual(
                errors,
                [f"benchmark source commit product tree does not match benchmark identity: {parent}"],
            )
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
        self.assertIn("python3 scripts/test_release_evidence_bundle.py\n", gate)
        self.assertIn("python3 scripts/release_evidence.py --evidence-ready \\\n", gate)
        self.assertIn('--execution-manifest "$evidence_dir/manifest.json"', gate)
        self.assertIn("release_evidence_bundle.py", gate)
        self.assertNotIn("python3 benchmarks/measure.py\n", gate)

    def test_release_gate_isolates_differential_tools_per_checkout(self) -> None:
        gate = RELEASE_GATE.read_text(encoding="utf-8")
        self.assertIn(
            'export MARKDOWN_DIFFERENTIAL_ROOT="$repo_root/target/differential-tools"\n',
            gate,
        )
        self.assertLess(
            gate.index("export MARKDOWN_DIFFERENTIAL_ROOT="),
            gate.index("scripts/setup_differential_tools.sh"),
        )

    def test_commonmark_js_driver_avoids_top_level_await(self) -> None:
        driver = COMMONMARK_JS_DRIVER.read_text(encoding="utf-8")
        self.assertNotIn(" await ", driver)
        self.assertIn("import(moduleUrl).then((commonmark) => {", driver)

    def test_commonmark_js_oracle_uses_committed_integrity_lock(self) -> None:
        setup = DIFFERENTIAL_SETUP.read_text(encoding="utf-8")
        differential = DIFFERENTIAL_TEST.read_text(encoding="utf-8")
        lock = json.loads((ROOT / "tests/differential/commonmark-js/package-lock.json")
            .read_text(encoding="utf-8"))
        self.assertIn('npm --prefix "$commonmark_js_dir" ci --ignore-scripts', setup)
        self.assertNotIn("--no-package-lock", setup)
        self.assertEqual(lock["lockfileVersion"], 3)
        for name in ("entities", "mdurl", "minimist"):
            self.assertIn("integrity", lock["packages"][f"node_modules/{name}"])
        self.assertIn('"commonmarkJsPackageLockSha256"', differential)


if __name__ == "__main__":
    unittest.main()
