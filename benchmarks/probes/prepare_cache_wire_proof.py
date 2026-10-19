#!/usr/bin/env python3
"""Frame pinned standard inputs and semantic fixtures for a public API byte proof."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def number(value: int) -> bytes:
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def string(value: str) -> bytes:
    data = value.encode("utf-8")
    return number(len(data)) + data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    cases = []
    corpora = []
    for profile, name in ((0, "commonmark-0.31.2"), (1, "gfm-0.29")):
        directory = ROOT / "tests/spec" / name
        # Reuse the pinned reader itself without importing its optional renderer
        # and legacy normalization dependencies. No corpus text is executed.
        module = ast.parse((directory / "spec_tests.py").read_text())
        reader = next(node for node in module.body if isinstance(node, ast.FunctionDef) and node.name == "get_tests")
        namespace = {"re": re}
        exec(compile(ast.Module(body=[reader], type_ignores=[]), f"{name}/spec_tests.py", "exec"), namespace)
        data = namespace["get_tests"](directory / "spec.txt")
        cases.extend((profile, case["markdown"]) for case in data)
        corpora.append({"name": name, "count": len(data), "sha256": hashlib.sha256((directory / "spec.txt").read_bytes()).hexdigest()})
    fixtures = [
        "", "\ufeff# 标题\r\n\r\ntext\r\n", "# café\n\ncafe\u0301 😀 &amp;\n", "A\x00B\n",
        "# Same {#same}\n\n# Same\n\n[go](#same) x[^n] x[^n]\n\n[^n]: **body**\n\n    next\n",
        "Term\n: definition[^n]\n\n  next\n\n[^n]: note\n",
        "$$\r\nx^2 + \\frac{1}{2}\r\n$$\r\n\ninline $x+y$ and `a---b` ... -- ---\n",
        "\ufeff---\r\nlayout: example\r\n---\r\n\r\nbody\n",
        ':::code-group\r\n```js "中文" {1}\r\n\ufeffconst x = "😀";\r\n```\r\n```text\r\n\r\n```\r\n:::\r\n',
        "# Same\n\n# Same\n\n[missing](#other) [^unknown]\n\n[^dup]: first\n[^dup]: second\n",
        "| a \\| b | c |\n| --- | --- |\n| x | ~~y~~ |\n",
        "> - **nested**\r\n>\r\n>   paragraph 中文😀\r\n",
    ]
    for profile in (0, 1, 2, 3):
        cases.extend((profile, source) for source in fixtures)
    data = string("MD-PROBE-WIRE-PROOF/1") + number(len(cases)) + b"".join(number(profile) + string(source) for profile, source in cases)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        raise FileExistsError("choose a new proof input path")
    args.output.write_bytes(data)
    metadata = {"schema": "markdown.cache-wire-proof/1", "cases": len(cases), "corpora": corpora,
        "semanticFixturesPerProfile": len(fixtures), "sha256": hashlib.sha256(data).hexdigest(),
        "generatorSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "note": "Includes every input returned by the pinned corpus readers under public profiles; this compares bytes, not spec HTML conformance."}
    args.output.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Prepared {len(cases)} public cache wire cases", flush=True)


if __name__ == "__main__":
    main()
