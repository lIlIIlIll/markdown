#!/usr/bin/env python3
"""Generate or verify the deterministic markdown 1.x public API snapshot."""

from __future__ import annotations

import argparse
import difflib
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "api" / "public-api-v1.txt"
HEADER = "# markdown public API snapshot v1"
RECORD_PREFIX = re.compile(r"^[^\\:\s]+\.cj:")
PUBLIC_INIT_PREFIX = re.compile(r"^(?:public init|public unsafe init)(?![A-Za-z0-9_])")


def normalized_declarations() -> list[str]:
    declarations: list[str] = []
    for path in sorted((ROOT / "src").rglob("*.cj")):
        if path.name.endswith("_test.cj") or path.name.startswith("generated_"):
            continue
        relative = path.relative_to(ROOT / "src").as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        collecting = False
        current: list[str] = []
        parens = 0
        public_enum = False
        braces = 0
        for raw in lines:
            stripped = raw.strip()
            if collecting:
                current.append(stripped)
                if current[0].startswith("public import "):
                    parens += stripped.count("{") - stripped.count("}")
                else:
                    parens += stripped.count("(") - stripped.count(")")
                if parens <= 0 and (current[0].startswith("public import ") or "{" in stripped or
                    stripped.endswith(";")):
                    declarations.append(f"{relative}:" + " ".join(current))
                    collecting = False
                    current = []
                continue
            if stripped.startswith("public import "):
                current = [stripped]
                braces = stripped.count("{") - stripped.count("}")
                if braces > 0:
                    collecting = True
                    parens = braces
                else:
                    declarations.append(f"{relative}:" + stripped)
                continue
            if re.match(r"^public\s+(?:unsafe\s+)?(?:class|open class|struct|enum|interface|func|static func|init|operator func|override func|prop|let|var)\b", stripped):
                current = [stripped]
                parens = stripped.count("(") - stripped.count(")")
                if parens > 0 and "{" not in stripped:
                    collecting = True
                else:
                    declarations.append(f"{relative}:" + stripped)
                if re.match(r"^public\s+enum\b", stripped):
                    public_enum = True
                    braces = stripped.count("{") - stripped.count("}")
                continue
            if public_enum:
                braces += stripped.count("{") - stripped.count("}")
                if stripped.startswith("|"):
                    declarations.append(f"{relative}:enum-variant {stripped}")
                if braces <= 0:
                    public_enum = False
    return sorted(set(declarations))


def _comparison_key(record: str) -> str:
    prefix = RECORD_PREFIX.match(record)
    if prefix is None:
        return record
    declaration = record[prefix.end():]
    if PUBLIC_INIT_PREFIX.match(declaration) is None:
        return record
    if record.endswith(" {"):
        signature = record[:-2]
    elif record.endswith(" {}"):
        signature = record[:-3]
    else:
        return record
    declaration_signature = signature[prefix.end():]
    opening = declaration_signature.find("(")
    if opening < 0:
        return record
    depth = 0
    closed = False
    quote: str | None = None
    escaped = False
    for character in declaration_signature[opening:]:
        if quote is not None:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
            continue
        if character == '"' or character == "'":
            quote = character
            continue
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth < 0:
                return record
            if depth == 0:
                closed = True
    if depth != 0 or not closed or quote is not None:
        return record
    return record[:-1] if record.endswith(" {}") else record


def _validated_records(content: str, source: str) -> tuple[list[str], list[str]]:
    if not content.endswith("\n") or content.endswith("\n\n"):
        raise ValueError(f"{source}: snapshot must end with exactly one newline")
    lines = content[:-1].split("\n")
    if not lines or lines[0] != HEADER:
        raise ValueError(f"{source}: invalid or missing snapshot header")
    if lines.count(HEADER) != 1:
        raise ValueError(f"{source}: snapshot header must appear exactly once")
    records = lines[1:]
    for record in records:
        prefix = RECORD_PREFIX.match(record)
        if prefix is None or prefix.end() == len(record):
            raise ValueError(f"{source}: invalid API record: {record!r}")
    if records != sorted(records):
        raise ValueError(f"{source}: API records are not sorted")
    if len(records) != len(set(records)):
        raise ValueError(f"{source}: duplicate raw API record")
    keys: dict[str, str] = {}
    for record in records:
        key = _comparison_key(record)
        previous = keys.get(key)
        if previous is not None and previous != record:
            raise ValueError(f"{source}: canonical collision: {previous!r} and {record!r}")
        keys[key] = record
    return records, sorted(keys)


def _snapshot_content(declarations: list[str]) -> str:
    return HEADER + "\n" + "\n".join(declarations) + "\n"


def _print_raw_diff(expected: list[str], current: list[str]) -> None:
    for line in difflib.unified_diff(expected, current, fromfile="api/public-api-v1.txt", tofile="current API",
        lineterm=""):
        print(line, file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    declarations = normalized_declarations()
    content = _snapshot_content(declarations)
    try:
        current_records, current_keys = _validated_records(content, "current API")
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    if args.update:
        SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
        SNAPSHOT.write_text(content, encoding="utf-8")
        print(f"updated {SNAPSHOT.relative_to(ROOT)}")
        return 0
    if not SNAPSHOT.exists():
        print(f"missing snapshot: {SNAPSHOT.relative_to(ROOT)}", file=sys.stderr)
        return 1
    try:
        expected = SNAPSHOT.read_bytes().decode("utf-8")
        expected_records, expected_keys = _validated_records(expected, SNAPSHOT.relative_to(ROOT).as_posix())
    except (UnicodeDecodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1
    if expected_keys != current_keys:
        print("public API differs from api/public-api-v1.txt", file=sys.stderr)
        _print_raw_diff(expected_records, current_records)
        return 1
    print(f"public API snapshot verified: {len(declarations)} declarations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
