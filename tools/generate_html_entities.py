#!/usr/bin/env python3
"""Generate the complete HTML5 named-character-reference table for Cangjie."""

from __future__ import annotations

import html.entities
from pathlib import Path


def cj_string(value: str) -> str:
    out = ['"']
    for char in value:
        code = ord(char)
        if char == "\\": out.append("\\\\")
        elif char == '"': out.append('\\"')
        elif char == "\n": out.append("\\n")
        elif char == "\r": out.append("\\r")
        elif char == "\t": out.append("\\t")
        elif code < 0x20 or code > 0x7E: out.append(f"\\u{{{code:X}}}")
        else: out.append(char)
    out.append('"')
    return "".join(out)


def main() -> int:
    entries = {key[:-1]: value for key, value in html.entities.html5.items() if key.endswith(";")}
    lines = [
        "package markdown",
        "",
        "import std.collection.*",
        "",
        "// Generated from Python's HTML5 named character reference table.",
        "private let HTML5_NAMED_ENTITIES = HashMap<String, String>([",
    ]
    for key, value in sorted(entries.items()):
        lines.append(f"    ({cj_string(key)}, {cj_string(value)}),")
    lines.extend([
        "])",
        "",
        "internal func lookupHtml5Entity(name: String): ?String { HTML5_NAMED_ENTITIES.get(name) }",
        "",
    ])
    output = Path("src/generated_entities.cj")
    output.write_text("\n".join(lines), encoding="utf-8")
    print(f"generated {len(entries)} entities into {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
