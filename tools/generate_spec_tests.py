#!/usr/bin/env python3
"""Generate one Cangjie unittest case per official embedded spec example."""

from __future__ import annotations

import argparse
import ast
import re
from pathlib import Path


def cj_string(value: str) -> str:
    out: list[str] = ['"']
    for char in value:
        code = ord(char)
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\r":
            out.append("\\r")
        elif char == "\t":
            out.append("\\t")
        elif code < 0x20 or code == 0x7F or code == 0xFFFD:
            out.append(f"\\u{{{code:X}}}")
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def load_examples(spec_dir: Path) -> list[dict[str, object]]:
    source = spec_dir / "spec_tests.py"
    tree = ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
    functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "get_tests"]
    if len(functions) != 1:
        raise ValueError("the pinned spec extractor must define exactly one get_tests function")
    # Use the pinned extractor without importing its command-line renderer or HTML normalizer.
    namespace = {"re": re}
    exec(compile(ast.Module(body=functions, type_ignores=[]), str(source), "exec"), namespace)
    return list(namespace["get_tests"](str(spec_dir / "spec.txt")))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec-dir", type=Path, required=True)
    parser.add_argument("--profile", choices=("commonmark", "gfm"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    examples = load_examples(args.spec_dir)
    class_name = "CommonMark0312ConformanceTest" if args.profile == "commonmark" else "Gfm029ConformanceTest"
    lines = [
        "package markdown.integration",
        "import markdown.core.MarkdownProfile",
        "import markdown.engine.MarkdownEngine",
        "import markdown.render.{HtmlOptions, HtmlRenderer}",
        "",
        "import std.unittest.*",
        "import std.unittest.testmacro.*",
        "",
        "// Generated from pinned official spec.txt; do not edit by hand.",
        "@Test",
        f"class {class_name} {{",
    ]
    for example in examples:
        number = int(example["example"])
        extension_case = args.profile == "gfm" and "(extension)" in str(example["section"])
        profile = "MarkdownProfile.gfm029()" if extension_case else (
            "MarkdownProfile.gfm029CommonMarkBase()" if args.profile == "gfm" else "MarkdownProfile.commonMark0312()"
        )
        html_options = (
            "unsafe { HtmlOptions.gfmCompatible() }"
            if extension_case
            else "unsafe { HtmlOptions.specCompatible() }"
        )
        markdown = cj_string(str(example["markdown"]))
        html = cj_string(str(example["html"]))
        lines.extend(
            [
                "    @TestCase",
                f"    func example{number:04d}(): Unit {{",
                f"        let document = MarkdownEngine.builder().profile({profile}).build().parse({markdown}).document",
                f"        @Expect(HtmlRenderer(options: {html_options}).render(document), {html})",
                "    }",
                "",
            ]
        )
    lines.append("}")
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"generated {len(examples)} cases into {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
