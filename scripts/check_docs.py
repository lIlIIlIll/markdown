#!/usr/bin/env python3
"""Validate maintained Markdown documentation without network access."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
DOC_ROOTS = [
    ROOT / "README.md",
    ROOT / "CONTRIBUTING.md",
    ROOT / "SECURITY.md",
    ROOT / "CHANGELOG.md",
]
DOC_ROOTS.extend(sorted((ROOT / "docs").rglob("*.md")))

REQUIRED_PAGES = [
    "README.md",
    "docs/README.md",
    "docs/getting-started.md",
    "docs/cookbook.md",
    "docs/troubleshooting.md",
    "docs/api.md",
    "docs/api/quick-reference.md",
    "docs/api/core.md",
    "docs/api/ast-and-source.md",
    "docs/api/rendering.md",
    "docs/api/extensions.md",
    "docs/api/editor.md",
    "docs/api/artifacts-and-services.md",
]

REQUIRED_EXAMPLES = [
    "examples/quickstart/cjpm.toml",
    "examples/quickstart/src/main.cj",
    "examples/cookbook/cjpm.toml",
    "examples/cookbook/src/main.cj",
]

REQUIRED_API_SYMBOLS = [
    "Markdown",
    "MarkdownEngine",
    "MarkdownEngineBuilder",
    "ParseResult",
    "ParseLimits",
    "MarkdownProfile",
    "Document",
    "NodeRef",
    "SourceSpan",
    "SourceBuffer",
    "HtmlRenderer",
    "HtmlOptions",
    "RenderedOutput",
    "MarkdownDialect",
    "ExtensionManifest",
    "InlineSyntax",
    "BlockSyntax",
    "RendererRule",
    "SyntaxTree",
    "CanonicalMarkdownRenderer",
    "MarkdownParseArtifact",
    "DocumentSnapshot",
    "MarkdownExtensionTestKit",
]

LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")


def markdown_target(raw: str) -> str:
    value = raw.strip()
    if value.startswith("<") and ">" in value:
        value = value[1 : value.index(">")]
    elif " " in value:
        value = value.split(" ", 1)[0]
    return unquote(value.split("#", 1)[0])


def main() -> int:
    failures: list[str] = []

    for name in REQUIRED_PAGES:
        if not (ROOT / name).is_file():
            failures.append(f"missing required page: {name}")

    for name in REQUIRED_EXAMPLES:
        if not (ROOT / name).is_file():
            failures.append(f"missing required runnable example: {name}")

    for page in DOC_ROOTS:
        text = page.read_text(encoding="utf-8")
        if text.count("```") % 2 != 0:
            failures.append(f"unbalanced fenced code block: {page.relative_to(ROOT)}")

        for raw in LINK_RE.findall(text):
            target = markdown_target(raw)
            if not target or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
                continue
            if target.startswith("/"):
                failures.append(
                    f"repository-local link must be relative: {page.relative_to(ROOT)} -> {target}"
                )
                continue
            resolved = (page.parent / target).resolve()
            try:
                resolved.relative_to(ROOT)
            except ValueError:
                failures.append(
                    f"link escapes repository: {page.relative_to(ROOT)} -> {target}"
                )
                continue
            if not resolved.exists():
                failures.append(f"broken link: {page.relative_to(ROOT)} -> {target}")

    api_text = "\n".join(
        page.read_text(encoding="utf-8") for page in sorted((ROOT / "docs" / "api").glob("*.md"))
    )
    for symbol in REQUIRED_API_SYMBOLS:
        if f"`{symbol}`" not in api_text:
            failures.append(f"required public entry point is not documented: {symbol}")

    maintained = "\n".join(page.read_text(encoding="utf-8") for page in DOC_ROOTS)
    if "markdown_cj" in maintained:
        failures.append("obsolete product name appears in maintained documentation: markdown_cj")
    if "heading.span" in maintained:
        failures.append("invalid HeadingNodeView member appears in maintained documentation: heading.span")

    quick_reference = (ROOT / "docs" / "api" / "quick-reference.md").read_text(encoding="utf-8")
    for obsolete in ("`node.id`", "`node.children`"):
        if obsolete in quick_reference:
            failures.append(f"obsolete NodeRef API appears in quick reference: {obsolete}")
    for current in ("`node.nodeId`", "`node.children()`", "`NodeChildren`"):
        if current not in quick_reference:
            failures.append(f"current NodeRef API is missing from quick reference: {current}")

    if failures:
        for failure in failures:
            print(f"docs check failed: {failure}", file=sys.stderr)
        return 1

    print(
        f"docs check passed: {len(DOC_ROOTS)} Markdown files, "
        f"{len(REQUIRED_API_SYMBOLS)} required API entry points, "
        f"{len(REQUIRED_EXAMPLES)} runnable example files"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
