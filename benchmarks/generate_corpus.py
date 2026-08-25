#!/usr/bin/env python3
"""Generate deterministic benchmark corpora of an exact byte size."""

from __future__ import annotations

import argparse
from pathlib import Path


COMMONMARK = (
    "## Section {n}\n\n"
    "CJK 中文 😀 text with [link](https://example.com/{n}) and `code`.\n\n"
    "> quote\n> - nested item\n\n"
    "```cj\nlet value = {n}\n```\n\n"
)
GFM = (
    "| name | value |\n| :--- | ---: |\n| row {n} | {n} |\n\n"
    "- [x] task {n}\n- [ ] pending\n\n"
    "~~strike~~ https://example.com/{n}\n\n"
)
ORDINARY = (("ordinary text with CJK 中文 and emoji 😀. " * 96) + "\n\n")


def corpus(template: str, size: int) -> bytes:
    chunks: list[bytes] = []
    length = 0
    index = 0
    while length < size:
        chunk = template.format(n=index).encode()
        chunks.append(chunk)
        length += len(chunk)
        index += 1
    return valid_utf8_size(b"".join(chunks), size)


def ordinary_corpus(size: int) -> bytes:
    chunk = ORDINARY.encode()
    return valid_utf8_size(chunk * (size // len(chunk) + 1), size)


def valid_utf8_size(data: bytes, size: int) -> bytes:
    prefix = data[:size]
    while True:
        try:
            prefix.decode("utf-8")
            break
        except UnicodeDecodeError as error:
            prefix = prefix[:error.start]
    return prefix + b" " * (size - len(prefix))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("commonmark", "gfm", "ordinary"))
    parser.add_argument("size", type=int)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.size <= 0:
        parser.error("size must be positive")
    if args.kind == "ordinary":
        args.output.write_bytes(ordinary_corpus(args.size))
    else:
        args.output.write_bytes(corpus(COMMONMARK if args.kind == "commonmark" else GFM, args.size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
