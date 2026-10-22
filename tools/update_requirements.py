#!/usr/bin/env python3
"""Refresh current requirement source links without changing acceptance evidence."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / ".agent" / "requirements.yaml"

IMPLEMENTATION_BY_PREFIX = {
    "MD-GOV": ["src/core/profile.cj", "src/core/ast.cj", "docs/versioning-and-compatibility.md"],
    "MD-USE": ["src/engine/parser.cj", "src/core/services.cj", "src/editor/editor.cj"],
    "MD-ARCH": ["src/engine/parser.cj", "src/core/rewrite.cj", "src/render/renderer.cj"],
    "MD-PRO": ["src/core/profile.cj", "src/integration/profile_snapshot_test.cj"],
    "MD-DIA": ["src/extensions/extension.cj", "src/core/fingerprint.cj"],
    "MD-SYN": ["src/extensions/extension.cj", "src/engine/parser.cj"],
    "MD-RDSL": ["src/extensions/extension.cj", "src/render/renderer.cj", "src/render/formatter.cj"],
    "MD-TRN": ["src/core/services.cj", "src/core/rewrite.cj"],
    "MD-IN": ["src/core/source.cj", "src/engine/parser.cj"],
    "MD-POS": ["src/core/source.cj"],
    "MD-PAR": ["src/engine/parser.cj"],
    "MD-VAL": ["src/core/ast.cj", "src/engine/parser.cj"],
    "MD-AST": ["src/core/ast.cj"],
    "MD-CST": ["src/editor/editor.cj"],
    "MD-OPS": ["src/core/traversal.cj", "src/core/rewrite.cj"],
    "MD-ANN": ["src/core/services.cj"],
    "MD-HTML": ["src/render/renderer.cj", "src/artifact/artifact.cj"],
    "MD-TEXT": ["src/render/renderer.cj"],
    "MD-FMT": ["src/render/formatter.cj", "src/editor/editor.cj"],
    "MD-EVT": ["src/core/services.cj"],
    "MD-EXT": ["src/extensions/extension.cj", "src/testkit/testkit.cj"],
    "MD-CAN": ["src/core/limits.cj", "src/engine/parser.cj", "src/render/renderer.cj"],
    "MD-BUD": ["src/core/limits.cj"],
    "MD-SINK": ["src/render/renderer.cj"],
    "MD-LIM": ["src/core/limits.cj", "src/engine/parser.cj"],
    "MD-SEC": ["src/render/renderer.cj", "src/integration/security_corpus_test.cj", "SECURITY.md"],
    "MD-ERR": ["src/core/diagnostic.cj", "src/engine/parser.cj"],
    "MD-LINT": ["src/editor/lint.cj"],
    "MD-EXP": ["src/engine/lint.cj"],
    "MD-EDIT": ["src/editor/editor.cj"],
    "MD-CAP": ["src/engine/capabilities.cj"],
    "MD-ART": ["src/artifact/artifact.cj"],
    "MD-API": ["src/engine/parser.cj", "api/public-api.txt"],
    "MD-PKG": ["cjpm.toml"],
    "MD-CLI": ["tools/markdown/src/main.cj", "scripts/cli_smoke.sh"],
    "MD-CON": ["src/integration/concurrency_test.cj", "docs/concurrency-and-observability.md"],
    "MD-DET": ["src/core/fingerprint.cj", "src/integration/concurrency_test.cj"],
    "MD-TST": ["src/integration/testkit_fuzz_test.cj", "src/integration/security_corpus_test.cj", "scripts/release_gate.sh"],
    "MD-PERF": ["src/integration/benchmark_test.cj", "benchmarks/measure.py", "docs/reports/benchmark.md"],
    "MD-OBS": ["src/engine/observability.cj"],
    "MD-DOC": ["README.md", "docs/", "examples/quickstart/"],
    "MD-COMP": ["docs/versioning-and-compatibility.md", "scripts/check_public_api.py"],
    "MD-REL": ["CHANGELOG.md", "LICENSE", "scripts/release_gate.sh"],
    "MD-QUAL": ["docs/reports/benchmark.md", "docs/reports/fuzz-summary.md"],
}


def main() -> int:
    text = LEDGER.read_text(encoding="utf-8")
    tests = {p.name: p.relative_to(ROOT).as_posix()
        for p in (ROOT / "src" / "integration").glob("*_test.cj")}

    def refresh_tests(section: re.Match[str]) -> str:
        return re.sub(r"src/[\w/]+_test\.cj",
            lambda match: tests.get(Path(match.group()).name, match.group()), section.group())

    def refresh(match: re.Match[str]) -> str:
        block = match.group()
        identifier = match.group("id")
        for prefix, paths in IMPLEMENTATION_BY_PREFIX.items():
            if identifier.startswith(prefix):
                block = re.sub(r"(?m)^  implementation:\n(?:  - .*\n)+",
                    "  implementation:\n" + "".join(f"  - {path}\n" for path in paths), block, count=1)
                break
        return re.sub(r"(?m)^  tests:\n(?:  - .*\n)+", refresh_tests, block, count=1)

    text = re.sub(r"(?ms)^- id: (?P<id>[^\n]+)\n.*?(?=^- id: |\Z)", refresh, text)
    LEDGER.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
