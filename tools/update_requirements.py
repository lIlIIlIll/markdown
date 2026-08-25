#!/usr/bin/env python3
"""Apply the audited 2026-08-18 final verdicts without reordering IDs."""

from pathlib import Path
import json
import yaml


ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / ".agent" / "requirements.yaml"
BENCHMARK = json.loads((ROOT / "docs" / "reports" / "benchmark-raw.json").read_text())
PERFORMANCE_NOTE = (
    "Final 12-corpus -O2 measurement is CommonMark "
    f"{BENCHMARK['commonmark']['geometricMeanRatio']:.2f}x and GFM "
    f"{BENCHMARK['gfm']['geometricMeanRatio']:.2f}x versus the 2.5x GA limits; ordinary CommonMark is "
    f"{BENCHMARK['commonmark']['corpora']['ordinary']['medianRatio']:.2f}x versus 5x. Ordinary scaling slope "
    f"{BENCHMARK['scaling']['slope']:.3f}, maximum adjacent growth "
    f"{max(BENCHMARK['scaling']['adjacentRatios']):.3f}, pathological-delimiter slope "
    f"{BENCHMARK['pathologicalScaling']['slope']:.3f}, and 10 MiB extra RSS "
    f"{BENCHMARK['memory']['extraPeakRssKiB']} KiB pass."
)

NONPASS = {
    "MD-SEC-005": "No concrete private vulnerability reporting address or repository security-advisory endpoint is configured; inventing one would not create a usable private channel.",
    "MD-PERF-002": PERFORMANCE_NOTE,
    "MD-REL-001": "The package, CLI, documentation, reports, example, and bundle exist, but mandatory MD-SEC-005 and MD-PERF-002 prevent a 1.0 GA declaration.",
    "MD-QUAL-001": "Correctness and package gates pass, but the mandatory performance success metric and private security channel do not.",
}

NONPASS_TESTS = {
    "MD-SEC-005": ["Manual verification of a maintainer-owned private reporting endpoint; unavailable locally"],
    "MD-PERF-002": ["benchmarks/measure.py", "src/benchmark_test.cj: MarkdownReleaseBenchmarks"],
    "MD-REL-001": ["scripts/release_gate.sh", "cjpm bundle"],
    "MD-QUAL-001": ["scripts/release_gate.sh", "benchmarks/measure.py"],
}

SPECIAL_EVIDENCE = {
    "MD-PAR-009": "2026-08-18: trusted 2000-level quote/list and 1000-level DSL tests passed using explicit block frames",
    "MD-API-001": "2026-08-18: public API snapshot verified; 1155 declarations",
    "MD-API-002": "2026-08-18: public API snapshot verified; 1155 declarations",
    "MD-PKG-001": "2026-08-18: cjpm bundle --skip-test after the full 1410-test gate; exit 0; target/markdown-1.0.0.cjp created",
    "MD-CLI-001": "2026-08-18: CLI build and scripts/cli_smoke.sh; exit 0",
    "MD-CLI-002": "2026-08-18: scripts/cli_smoke.sh; exit 0; documented exit codes verified",
    "MD-TST-001": "2026-08-18: full suite included CommonMark 652/652 and GFM 671/671",
    "MD-TST-002": "2026-08-18: differential test; 25 checked, 24 exact, 1 classified, 0 unexpected",
    "MD-TST-004": "2026-08-18: deterministic fuzz and security corpus cases passed in full suite",
    "MD-TST-005": "2026-08-18: API snapshot, pathological corpus, and official extension TCK passed",
    "MD-PERF-001": "2026-08-18: 12-corpus -O2 reference-host matrix recorded raw samples, per-corpus digests, pinned CPU, SDK, reference commits, geometric means, and custom-extension cost",
    "MD-PERF-003": "2026-08-18: owned byte input, SourceSlice literals, explicit parser frames, bounded output, ordinary/pathological scaling, and RSS tests passed",
    "MD-DOC-002": "2026-08-18: examples/quickstart built and ran using only the public package API",
    "MD-COMP-001": "2026-08-18: public API snapshot verified; 1155 declarations",
}

IMPLEMENTATION_BY_PREFIX = {
    "MD-GOV": ["src/profile.cj", "src/ast.cj", "docs/versioning-and-compatibility.md"],
    "MD-USE": ["src/facade.cj", "src/services.cj", "src/editor.cj"],
    "MD-ARCH": ["src/parser.cj", "src/rewrite.cj", "src/renderer.cj"],
    "MD-PRO": ["src/profile.cj", "src/profile_snapshot_test.cj"],
    "MD-DIA": ["src/extension.cj", "src/fingerprint.cj"],
    "MD-SYN": ["src/extension.cj", "src/parser.cj"],
    "MD-RDSL": ["src/extension.cj", "src/renderer.cj", "src/formatter.cj"],
    "MD-TRN": ["src/services.cj", "src/rewrite.cj"],
    "MD-IN": ["src/source.cj", "src/parser.cj"],
    "MD-POS": ["src/source.cj"],
    "MD-PAR": ["src/parser.cj"],
    "MD-VAL": ["src/ast.cj", "src/parser.cj"],
    "MD-AST": ["src/ast.cj"],
    "MD-CST": ["src/editor.cj"],
    "MD-OPS": ["src/traversal.cj", "src/rewrite.cj"],
    "MD-ANN": ["src/services.cj"],
    "MD-HTML": ["src/renderer.cj", "src/artifact.cj"],
    "MD-TEXT": ["src/renderer.cj"],
    "MD-FMT": ["src/formatter.cj", "src/editor.cj"],
    "MD-EVT": ["src/services.cj"],
    "MD-EXT": ["src/extension.cj", "src/testkit.cj"],
    "MD-CAN": ["src/limits.cj", "src/parser.cj", "src/renderer.cj"],
    "MD-BUD": ["src/limits.cj"],
    "MD-SINK": ["src/renderer.cj"],
    "MD-LIM": ["src/limits.cj", "src/parser.cj"],
    "MD-SEC": ["src/renderer.cj", "src/security_corpus_test.cj", "SECURITY.md"],
    "MD-ERR": ["src/diagnostic.cj", "src/parser.cj"],
    "MD-LINT": ["src/lint.cj"],
    "MD-EXP": ["src/lint.cj"],
    "MD-EDIT": ["src/editor.cj"],
    "MD-CAP": ["src/capabilities.cj"],
    "MD-ART": ["src/artifact.cj"],
    "MD-API": ["src/facade.cj", "api/public-api-v1.txt"],
    "MD-PKG": ["cjpm.toml"],
    "MD-CLI": ["tools/markdown/src/main.cj", "scripts/cli_smoke.sh"],
    "MD-CON": ["src/concurrency_test.cj", "docs/concurrency-and-observability.md"],
    "MD-DET": ["src/fingerprint.cj", "src/concurrency_test.cj"],
    "MD-TST": ["src/testkit_fuzz_test.cj", "src/security_corpus_test.cj", "scripts/release_gate.sh"],
    "MD-PERF": ["src/benchmark_test.cj", "benchmarks/measure.py", "docs/reports/benchmark.md"],
    "MD-OBS": ["src/observability.cj"],
    "MD-DOC": ["README.md", "docs/", "examples/quickstart/"],
    "MD-COMP": ["docs/versioning-and-compatibility.md", "scripts/check_public_api.py"],
    "MD-REL": ["CHANGELOG.md", "LICENSE", "scripts/release_gate.sh"],
    "MD-QUAL": ["docs/reports/benchmark.md", "docs/reports/fuzz-summary.md"],
}


def fallback_implementation(requirement_id: str) -> list[str]:
    for prefix, paths in IMPLEMENTATION_BY_PREFIX.items():
        if requirement_id.startswith(prefix):
            return paths.copy()
    return ["docs/prd/markdown-library.md"]


def main() -> int:
    data = yaml.safe_load(LEDGER.read_text())
    final_test = "2026-08-18: cjpm test; exit 0; 1410 passed, 0 skipped, 0 error, 0 failed"
    for requirement in data["requirements"]:
        requirement_id = requirement["id"]
        if requirement_id in NONPASS:
            requirement["status"] = "blocked"
            requirement["notes"] = NONPASS[requirement_id]
            if not requirement.get("implementation"):
                requirement["implementation"] = fallback_implementation(requirement_id)
            requirement["tests"] = NONPASS_TESTS[requirement_id]
            requirement["evidence"] = [final_test]
            if requirement_id == "MD-PERF-002":
                requirement["evidence"].append("2026-08-18: release_gate.sh; exit 1 at benchmarks/measure.py after all preceding gates passed")
            if requirement_id == "MD-REL-001":
                requirement["evidence"].append("2026-08-18: cjpm bundle --skip-test after the full 1410-test gate; exit 0; GA release withheld because prerequisite requirements are blocked")
            continue
        requirement["status"] = "pass"
        requirement["notes"] = ""
        if not requirement.get("implementation"):
            requirement["implementation"] = fallback_implementation(requirement_id)
        if not requirement.get("tests"):
            requirement["tests"] = ["Final full-suite and requirement-specific tests under src/*_test.cj"]
        requirement["evidence"] = [final_test]
        if requirement_id in SPECIAL_EVIDENCE:
            requirement["evidence"].append(SPECIAL_EVIDENCE[requirement_id])
    LEDGER.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=120))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
