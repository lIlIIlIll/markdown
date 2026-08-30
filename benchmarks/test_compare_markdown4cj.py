#!/usr/bin/env python3
"""Regression tests for the same-language benchmark gate."""

from __future__ import annotations

import unittest
from unittest.mock import patch

import compare_markdown4cj as comparison


def sample(seconds: float, rss: int) -> dict[str, object]:
    return {"seconds": seconds, "peakRssKiB": rss, "stdout": "1",
        "stdoutSha256": "0" * 64}


def valid_report() -> dict[str, object]:
    inputs = comparison.benchmark_inputs()
    rows = {}
    for name, data in inputs.items():
        left = [sample(1.0, 100) for _ in range(comparison.SAMPLES)]
        right = [sample(2.0, 200) for _ in range(comparison.SAMPLES)]
        rows[name] = {"bytes": len(data), "markdown": left, "markdown4cj": right,
            "markdownMedianSeconds": 1.0, "markdown4cjMedianSeconds": 2.0,
            "markdownSpeedup": 2.0, "peakRssRatio": 0.5}
    return {"schemaVersion": 3, "status": "PASS",
        "identity": {"repositoryCommit": "a" * 40, "gitTree": "b" * 40,
            "productTreeSha256": comparison.benchmark_product_tree_sha256(comparison.ROOT),
            "harnessFiles": {relative: comparison.sha256(comparison.ROOT / relative)
                for relative in comparison.HARNESS_FILES},
            "corpora": comparison.corpus_identity(inputs)},
        "comparator": {"url": comparison.COMPARATOR_URL,
            "commit": comparison.COMPARATOR_COMMIT},
        "commonmark4cj": {"url": comparison.COMMONMARK_URL,
            "commit": comparison.COMMONMARK_COMMIT},
        "thresholds": {"minimumGeomeanSpeedup": comparison.MIN_SPEEDUP,
            "maximumPerCorpusRegression": comparison.MAX_REGRESSION,
            "maximumPeakRssRatio": comparison.MAX_RSS_RATIO},
        "environment": {"cpu": 2,
            "cjc": {"exitCode": 0, "stdout": "Cangjie Compiler: test\n"},
            "cjpm": {"exitCode": 0, "stdout": "cjpm test\n"}},
        "protocol": {"workload": "CommonMark parse-only",
            "corpusBytes": comparison.CORPUS_BYTES,
            "iterationsPerProcess": comparison.ITERATIONS, "warmupsPerSide": 1,
            "samplesPerSide": comparison.SAMPLES,
            "order": "alternating; odd sample reverses order"},
        "preflight": {"markdown4cj": {"headMatches": True, "clean": True},
            "commonmark4cj": {"headMatches": True, "clean": True}},
        "sharedBehavior": {"caseCount": len(comparison.BEHAVIOR_CASES),
            "passCount": len(comparison.BEHAVIOR_CASES), "pass": True},
        "corpora": rows, "geomeanMarkdownSpeedup": 2.0, "promotionPassed": True}


class SameLanguageBenchmarkTest(unittest.TestCase):
    def test_valid_report_rederives_every_gate(self) -> None:
        self.assertEqual(comparison.validate_report(valid_report(), True), [])

    def test_forged_speedup_is_rejected(self) -> None:
        report = valid_report()
        first = next(iter(report["corpora"].values()))
        first["markdownSpeedup"] = 20.0
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("speedup is not derived" in error for error in errors))

    def test_weakened_threshold_is_rejected(self) -> None:
        report = valid_report()
        report["thresholds"]["minimumGeomeanSpeedup"] = 0.1
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language report thresholds differ from the enforced profile", errors)

    def test_shortened_protocol_is_rejected(self) -> None:
        report = valid_report()
        report["protocol"]["samplesPerSide"] = 1
        errors = comparison.validate_report(report, True)
        self.assertIn("same-language report protocol differs from the enforced profile", errors)

    def test_unstable_driver_output_is_rejected(self) -> None:
        report = valid_report()
        first = next(iter(report["corpora"].values()))
        first["markdown"][0]["stdout"] = "2"
        errors = comparison.validate_report(report, True)
        self.assertTrue(any("output is unstable" in error for error in errors))

    def test_report_renderer_uses_raw_values(self) -> None:
        rendered = comparison.render_markdown(valid_report())
        self.assertIn("**2.00×**", rendered)
        self.assertIn("12/12", rendered)
        self.assertIn("Same-language benchmark (current-1.1.3)", rendered)

    def test_default_cpu_uses_affinity_set(self) -> None:
        with patch.object(comparison.os, "sched_getaffinity", return_value={7, 9}):
            self.assertEqual(comparison.resolve_cpu(None), 7)
            self.assertEqual(comparison.resolve_cpu(9), 9)
            with self.assertRaises(ValueError):
                comparison.resolve_cpu(2)


if __name__ == "__main__":
    unittest.main()
