#!/usr/bin/env python3
"""Pinned smoke differential against test-only CommonMark implementations."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
MARKDOWN = ROOT / "tools/markdown/target/release/bin/main"
CMARK = Path("/tmp/markdown-cmark-0.31.1/build/src/cmark")
CMARK_GFM = Path("/tmp/markdown-cmark-gfm-0.29.0.gfm.13/build/src/cmark-gfm")
COMMONMARK_JS = Path("/tmp/markdown-commonmark-js/node_modules/.bin/commonmark")

COMMONMARK_CASES = [
    "# heading\n",
    "paragraph with **strong** and *emphasis*.\n",
    "> quote\n>\n> second\n",
    "1. one\n2. two\n",
    "```cj\nlet x = 1\n```\n",
    "[link](https://example.com \"title\")\n",
    "<span>raw</span>\n",
    "A  \nhard break\n",
    "&amp; &#x41;\n",
    "---\n",
]

GFM_CASES = [
    "| a | b |\n| :- | -: |\n| 1 | 2 |\n",
    "- [x] done\n- [ ] todo\n",
    "~~deleted~~\n",
    "www.example.com and user@example.com\n",
    "<script>alert(1)</script>\n",
]

EXPECTED_DIFFERENCES = {
    ("gfm", 2, "cmark-gfm-0.29.0.gfm.13"): {
        "category": "serializer difference",
        "rationale": "markdown emits explicit task-list class tokens and HTML5 void-tag syntax; task state and disabled checkbox semantics are equivalent",
    },
}


def run(command: list[str], source: str) -> str:
    result = subprocess.run(command, input=source, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr}")
    return result.stdout


def main() -> int:
    missing = [str(path) for path in (MARKDOWN, CMARK, CMARK_GFM, COMMONMARK_JS) if not path.exists()]
    if missing:
        print("missing differential tools: " + ", ".join(missing), file=sys.stderr)
        return 2
    differences: list[dict[str, object]] = []
    checked = 0
    for index, source in enumerate(COMMONMARK_CASES, 1):
        ours = run([str(MARKDOWN), "render", "--profile", "commonmark-0.31.2", "--to", "spec-html"], source)
        references = {
            "cmark-0.31.1": run([str(CMARK), "--unsafe"], source),
            "commonmark.js-0.31.2": run([str(COMMONMARK_JS)], source),
        }
        for implementation, output in references.items():
            checked += 1
            if output != ours:
                differences.append({"suite": "commonmark", "case": index,
                    "implementation": implementation, "source": source,
                    "markdown": ours, "reference": output})
    gfm_extensions = ["--unsafe", "-e", "table", "-e", "strikethrough", "-e", "autolink",
        "-e", "tagfilter", "-e", "tasklist"]
    for index, source in enumerate(GFM_CASES, 1):
        ours = run([str(MARKDOWN), "render", "--profile", "gfm-0.29", "--to", "spec-html"], source)
        output = run([str(CMARK_GFM), *gfm_extensions], source)
        checked += 1
        if output != ours:
            differences.append({"suite": "gfm", "case": index, "implementation": "cmark-gfm-0.29.0.gfm.13",
                "source": source, "markdown": ours, "reference": output})
    classified: list[dict[str, object]] = []
    unexpected: list[dict[str, object]] = []
    for difference in differences:
        key = (str(difference["suite"]), int(difference["case"]), str(difference["implementation"]))
        if key in EXPECTED_DIFFERENCES:
            classified.append({**difference, **EXPECTED_DIFFERENCES[key]})
        else:
            unexpected.append(difference)
    report = {"checked": checked, "exactMatches": checked - len(differences),
        "classifiedDifferences": len(classified), "unexpectedDifferences": len(unexpected),
        "classifications": classified, "unexpected": unexpected}
    report_path = ROOT / "docs/reports/differential-smoke.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: report[key] for key in
        ("checked", "exactMatches", "classifiedDifferences", "unexpectedDifferences")}))
    return 1 if unexpected else 0


if __name__ == "__main__":
    raise SystemExit(main())
