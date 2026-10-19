#!/usr/bin/env python3
"""Generate or verify the deterministic markdown 0.10 pre-GA public API snapshot."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import difflib
from pathlib import Path
import re
import sys
import unicodedata
from urllib.parse import quote, unquote_to_bytes


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "api" / "public-api-v0.10.txt"
HEADER = "# markdown public API snapshot v0.10"
# Python's ``\w`` does not admit combining marks even though Cangjie accepts
# them as XID_Continue characters.  Cover the Unicode combining-mark blocks
# here, then validate actual declaration tokens with ``str.isidentifier``.
COMBINING_MARK_PATTERN = r"\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f"
IDENTIFIER_PATTERN = rf"[^\W\d](?:\w|[{COMBINING_MARK_PATTERN}])*"
CANONICAL_PACKAGE_NAME = rf"{IDENTIFIER_PATTERN}(?:\.{IDENTIFIER_PATTERN})*"
ANNOTATION_NAME = rf"{IDENTIFIER_PATTERN}(?:\.{IDENTIFIER_PATTERN})*"
RECORD_PREFIX = re.compile(
    rf"^(?P<path>[^\\:\s]+\.cj):package=(?P<package>{CANONICAL_PACKAGE_NAME}):")
OWNER_SEGMENT = r"(?:class|struct|interface|enum|extend)/[A-Za-z0-9_.~%\-]+"
OWNER_PREFIX = re.compile(
    rf"^owner=(?P<owner>{OWNER_SEGMENT}(?:>{OWNER_SEGMENT})*):")
PACKAGE_NAME = rf"{IDENTIFIER_PATTERN}(?:\s*\.\s*{IDENTIFIER_PATTERN})*"
PACKAGE_DECLARATION = re.compile(
    rf"^package\s+(?P<name>{PACKAGE_NAME})\s*;?$")
PACKAGE_PREFIX = re.compile(
    rf"^\s*package\s+(?P<name>{PACKAGE_NAME})\s*;")

VISIBILITY_MODIFIERS = frozenset(("public", "protected", "private", "internal"))
DECLARATION_MODIFIERS = frozenset((
    "public", "protected", "private", "internal", "open", "abstract", "sealed",
    "static", "const", "unsafe", "override", "redef", "mut", "foreign",
))
TYPE_KINDS = frozenset(("class", "struct", "enum", "interface"))
CALLABLE_KINDS = frozenset(("func", "init", "operator func", "named-constructor", "prop"))


@dataclass(frozen=True)
class TypeScope:
    kind: str
    name: str
    owner: str
    body_depth: int
    effective_public: bool
    externally_subclassable: bool


@dataclass(frozen=True)
class LexicalContext:
    kind: str
    quote: str | None = None
    triple_quote: bool = False
    escaped: bool = False
    raw_hashes: int = 0
    brace_depth: int = 0


@dataclass(frozen=True)
class LexicalState:
    block_comment_depth: int = 0
    contexts: tuple[LexicalContext, ...] = ()


@dataclass(frozen=True)
class LexedLine:
    raw: str
    code: str
    semantic: str
    literal: tuple[bool, ...]
    comment: tuple[bool, ...]
    brace_delta: int
    brace_openings: int
    lexical_continuation: bool


@dataclass
class PendingScope:
    kind: str
    name: str
    parent_owner: str | None
    effective_public: bool
    externally_subclassable: bool
    record_public: bool
    parts: list[str]
    annotations: list[str]


@dataclass
class PendingDeclaration:
    owner: str | None
    prefix: str
    parts: list[str]
    balance: int
    mode: str
    scope: TypeScope | None
    annotations: list[str]


@dataclass(frozen=True)
class DeclarationHead:
    kind: str
    modifiers: tuple[str, ...]
    visibility: str | None
    name: str | None
    keyword_start: int
    keyword_end: int


@dataclass(frozen=True)
class IdentityToken:
    kind: str
    text: str


def _owner_record(relative: str, package: str, owner: str | None, declaration: str) -> str:
    owner_prefix = f"owner={owner}:" if owner is not None else ""
    return f"{relative}:package={package}:{owner_prefix}{declaration}"


def _owner_segment(kind: str, identity: str) -> str:
    return f"{kind}/{quote(identity, safe='')}"


def _lex_line(raw: str, state: LexicalState) -> tuple[LexedLine, LexicalState]:
    """Lex one line, including recursively nested string interpolations."""
    code: list[str] = []
    semantic: list[str] = []
    literal: list[bool] = []
    comment: list[bool] = []

    def append(text: str, code_text: str, *, is_literal: bool = False,
        is_comment: bool = False) -> None:
        semantic.extend(text)
        code.extend(code_text)
        literal.extend(is_literal for _ in text)
        comment.extend(is_comment for _ in text)

    block_depth = state.block_comment_depth
    contexts = list(state.contexts)

    def replace_top(context: LexicalContext) -> None:
        contexts[-1] = context

    def push_string(quote_character: str, *, triple: bool = False,
        raw_hash_count: int = 0) -> None:
        contexts.append(LexicalContext(
            "string", quote_character, triple, False, raw_hash_count, 0))

    index = 0
    while index < len(raw):
        character = raw[index]
        following = raw[index + 1] if index + 1 < len(raw) else ""
        top = contexts[-1] if contexts else None
        if top is not None and top.kind == "string":
            if top.raw_hashes > 0:
                if character == '"':
                    closing = '"' + "#" * top.raw_hashes
                    closing_end = index + len(closing)
                    if (raw.startswith(closing, index) and
                        (closing_end == len(raw) or raw[closing_end] != "#")):
                        append(closing, " " * len(closing), is_literal=True)
                        index = closing_end
                        contexts.pop()
                        continue
                append(character, " ", is_literal=True)
                index += 1
                continue
            delimiter = top.quote * (3 if top.triple_quote else 1)
            if not top.escaped and raw.startswith(delimiter, index):
                append(delimiter, " " * len(delimiter), is_literal=True)
                index += len(delimiter)
                contexts.pop()
                continue
            if (top.quote == '"' and not top.escaped and character == "$" and
                following == "{"):
                append("${", "  ", is_literal=True)
                contexts.append(LexicalContext("interpolation", brace_depth=1))
                index += 2
                continue
            append(character, " ", is_literal=True)
            if top.escaped:
                replace_top(LexicalContext(
                    "string", top.quote, top.triple_quote, False, top.raw_hashes, 0))
            elif character == "\\":
                replace_top(LexicalContext(
                    "string", top.quote, top.triple_quote, True, top.raw_hashes, 0))
            index += 1
            continue
        if block_depth > 0:
            if character == "/" and following == "*":
                block_depth += 1
                append("  ", "  ", is_comment=True)
                index += 2
                continue
            if character == "*" and following == "/":
                block_depth -= 1
                append("  ", "  ", is_comment=True)
                index += 2
            else:
                append(" ", " ", is_comment=True)
                index += 1
            continue
        if top is not None and top.kind == "interpolation":
            if character == "/" and following == "/":
                newline = raw.find("\n", index)
                end = len(raw) if newline < 0 else newline
                append(" " * (end - index), " " * (end - index), is_comment=True)
                if newline < 0:
                    break
                append("\n", "\n")
                index = newline + 1
                continue
            if character == "/" and following == "*":
                append("  ", "  ", is_comment=True)
                block_depth = 1
                index += 2
                continue
            if character == "#":
                delimiter_end = index
                while delimiter_end < len(raw) and raw[delimiter_end] == "#":
                    delimiter_end += 1
                if delimiter_end < len(raw) and raw[delimiter_end] == '"':
                    opener = raw[index:delimiter_end + 1]
                    append(opener, " " * len(opener), is_literal=True)
                    push_string('"', raw_hash_count=delimiter_end - index)
                    index = delimiter_end + 1
                    continue
            if raw.startswith('"""', index) or raw.startswith("'''", index):
                append(character * 3, "   ", is_literal=True)
                push_string(character, triple=True)
                index += 3
                continue
            if character in ('"', "'"):
                append(character, " ", is_literal=True)
                push_string(character)
                index += 1
                continue
            if character == "{":
                replace_top(LexicalContext("interpolation", brace_depth=top.brace_depth + 1))
            elif character == "}":
                if top.brace_depth <= 0:
                    raise ValueError("unbalanced string interpolation")
                if top.brace_depth == 1:
                    contexts.pop()
                else:
                    replace_top(LexicalContext("interpolation", brace_depth=top.brace_depth - 1))
            append(character, " ")
            index += 1
            continue
        if character == "/" and following == "/":
            newline = raw.find("\n", index)
            end = len(raw) if newline < 0 else newline
            append(" " * (end - index), " " * (end - index), is_comment=True)
            if newline < 0:
                break
            append("\n", "\n")
            index = newline + 1
            continue
        if character == "/" and following == "*":
            append("  ", "  ", is_comment=True)
            block_depth = 1
            index += 2
            continue
        if character == "#":
            delimiter_end = index
            while delimiter_end < len(raw) and raw[delimiter_end] == "#":
                delimiter_end += 1
            if delimiter_end < len(raw) and raw[delimiter_end] == '"':
                opener = raw[index:delimiter_end + 1]
                append(opener, " " * len(opener), is_literal=True)
                push_string('"', raw_hash_count=delimiter_end - index)
                index = delimiter_end + 1
                continue
        if raw.startswith('"""', index) or raw.startswith("'''", index):
            append(character * 3, "   ", is_literal=True)
            push_string(character, triple=True)
            index += 3
            continue
        if character in ('"', "'"):
            append(character, " ", is_literal=True)
            push_string(character)
            index += 1
            continue
        append(character, character)
        index += 1
    code_text = "".join(code)
    semantic_text = "".join(semantic)
    if (len(code_text) != len(raw) or len(semantic_text) != len(raw) or
        len(literal) != len(raw) or len(comment) != len(raw)):
        raise ValueError("internal lexical mask length mismatch")
    openings = code_text.count("{")
    delta = openings - code_text.count("}")
    return (
        LexedLine(raw, code_text, semantic_text, tuple(literal), tuple(comment), delta, openings,
            block_depth > 0 or bool(contexts)),
        LexicalState(block_depth, tuple(contexts)),
    )


def _lexically_open(state: LexicalState) -> bool:
    return state.block_comment_depth > 0 or bool(state.contexts)


def _top_context_is_string(state: LexicalState) -> bool:
    return bool(state.contexts) and state.contexts[-1].kind == "string"


def _lex_source(lines: list[str]) -> list[LexedLine]:
    state = LexicalState()
    result: list[LexedLine] = []
    for raw in lines:
        line, state = _lex_line(raw, state)
        result.append(line)
    if _lexically_open(state):
        raise ValueError("unterminated comment or string literal while collecting public API")
    return result


def _source_package(lines: list[LexedLine], relative: str) -> str:
    packages: list[str] = []
    brace_depth = 0
    for line in lines:
        stripped = line.code.strip()
        if stripped and brace_depth == 0:
            match = PACKAGE_DECLARATION.fullmatch(stripped)
            if match is not None:
                packages.append(_canonical_package_name(match.group("name")))
        brace_depth += line.brace_delta
    if len(packages) != 1:
        raise ValueError(f"{relative}: expected exactly one canonical package declaration")
    return packages[0]


def _trivia_stripped_text(parts: list[str]) -> str:
    """Remove comments/outer whitespace while preserving literal bytes and newlines."""
    output: list[str] = []
    state = LexicalState()
    pending_space = False
    comment_gap = False
    for part_index, raw in enumerate(parts):
        line, state = _lex_line(raw, state)
        for index, character in enumerate(raw):
            if line.literal[index]:
                if pending_space and output:
                    output.append(" ")
                pending_space = False
                comment_gap = False
                if character == "%":
                    output.append("%25")
                elif character == "\r":
                    output.append("%0D")
                else:
                    output.append(character)
                continue
            if line.comment[index]:
                comment_gap = True
                continue
            if character.isspace():
                pending_space = True
                continue
            if comment_gap and not pending_space and output:
                output.append(" ")
            elif pending_space and output:
                output.append(" ")
            pending_space = False
            comment_gap = False
            output.append(character)
        if part_index + 1 < len(parts):
            if _top_context_is_string(state):
                output.append("%0A")
            elif state.block_comment_depth > 0:
                comment_gap = True
            else:
                pending_space = True
                comment_gap = False
    if _lexically_open(state):
        raise ValueError("unterminated comment or string literal in public API declaration")
    return "".join(output).strip()


# Longest-match punctuation lexemes from the Cangjie 1.1.3 lexer.  ``?.`` is
# retained as a source-level adjacency token because separating it changes the
# optional-chain spelling even though the compiler exposes ``?`` and ``.`` as
# individual TokenKinds.
MULTI_CHARACTER_TOKENS = tuple(sorted((
    ">>=", "<<=", "**=", "&&=", "||=", "..=", "...",
    "=>", "->", "<-", "<:", "==", "!=", "<=", ">=", "&&", "||", "|>", "~>",
    "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>",
    "**", "??", "?.", "::", "..", "!in", "@!",
), key=len, reverse=True))
SPACED_TOKENS = frozenset((
    "=", "=>", "->", "<:", "+", "-", "*", "/", "%", "==", "!=", "<=", ">=",
    "&&", "||", "&", "|", "^", "+=", "-=", "*=", "/=", "%=", "&&=", "||=",
    "&=", "|=", "^=", "<<", ">>", "<<=", ">>=", "**", "**=", "??", "|>", "~>",
    "..", "..=", "<-", "!in",
))

# Tokens which cannot terminate an otherwise balanced declaration.  This is
# deliberately token-based: suffix checks conflate ``|>`` with ``>`` and split
# compound assignments such as ``&&=`` into unrelated punctuation.
DECLARATION_TRAILING_CONTINUATION_TOKENS = frozenset((
    "=", "=>", "->", "<-", "<:", ":", ",", ".", "?.", "::",
    "+", "-", "*", "/", "%", "**", "&", "|", "^", "<<", ">>",
    "&&", "||", "??", "|>", "~>",
    "==", "!=", "<=", ">=", "<", "is", "as", "in", "!in",
    "+=", "-=", "*=", "/=", "%=", "**=", "&=", "|=", "^=", "<<=", ">>=",
    "&&=", "||=", "..", "..=", "where",
))
DECLARATION_LEADING_CONTINUATION_TOKENS = frozenset((
    "<:", "&", ":", "=", ",", "->", "=>", "<-", ")", "]", ">", ".", "?.",
    "::", "+", "-", "*", "/", "%", "**", "&&", "||", "??", "|>", "~>",
    "==", "!=", "<=", ">=", "^", "<<", ">>", "+=", "-=", "*=", "/=", "%=",
    "**=", "&=", "|=", "^=", "<<=", ">>=", "&&=", "||=", "..", "..=",
    "where", "as", "is", "in", "!in",
))


def _nfc_identifier(value: str) -> str:
    """Normalize an identifier token without touching literal token bytes."""
    if value.startswith("`") and value.endswith("`"):
        return "`" + unicodedata.normalize("NFC", value[1:-1]) + "`"
    return unicodedata.normalize("NFC", value)


def _canonical_package_name(value: str) -> str:
    compact = re.sub(r"\s+", "", value)
    return ".".join(unicodedata.normalize("NFC", part) for part in compact.split("."))


def _is_plain_identifier(value: str) -> bool:
    return bool(value) and value.isidentifier()


def _is_identifier_token(value: str) -> bool:
    if value.startswith("`") or value.endswith("`"):
        return (len(value) >= 3 and value.startswith("`") and value.endswith("`") and
            "`" not in value[1:-1] and _is_plain_identifier(value[1:-1]))
    return _is_plain_identifier(value)


def _identifier_start(character: str) -> bool:
    return character == "_" or (not character.isdigit() and character.isidentifier())


def _identifier_continue(character: str) -> bool:
    return character == "_" or ("_" + character).isidentifier()


def _ascii_digit(character: str, base: int = 10) -> bool:
    if "0" <= character <= "9":
        return ord(character) - ord("0") < base
    if base == 16 and "a" <= character.lower() <= "f":
        return True
    return False


def _scan_number_literal(text: str, start: int, literal: tuple[bool, ...]) -> int:
    """Return the end of one valid-shaped Cangjie numeric token.

    The scanner mirrors the SDK's decimal/radix, fractional, exponent and
    built-in suffix boundaries.  Most importantly, a dot belongs to a number
    only when it begins a fractional part; member and range dots stay tokens.
    """
    length = len(text)

    def available(index: int) -> bool:
        return index < length and not literal[index]

    index = start
    base = 10
    radix_prefix = False
    if (available(index) and text[index] == "." and available(index + 1) and
        _ascii_digit(text[index + 1])):
        index += 1
    elif (available(index + 1) and text[index] == "0" and
        text[index + 1].lower() in ("x", "o", "b")):
        base = {"x": 16, "o": 8, "b": 2}[text[index + 1].lower()]
        radix_prefix = True
        index += 2

    while available(index) and (_ascii_digit(text[index], base) or text[index] == "_"):
        index += 1

    integer_suffix = re.match(r"(?:i|u)(?:8|16|32|64)", text[index:])
    if integer_suffix is not None:
        suffix_end = index + integer_suffix.end()
        if not available(suffix_end) or not _identifier_continue(text[suffix_end]):
            return suffix_end

    if (available(index) and text[index] == "." and
        not (available(index + 1) and text[index + 1] == ".") and
        available(index + 1) and _ascii_digit(text[index + 1], base)):
        index += 1
        while available(index) and (_ascii_digit(text[index], base) or text[index] == "_"):
            index += 1

    exponent = "pP" if radix_prefix else "eE"
    if available(index) and text[index] in exponent:
        candidate = index + 1
        if available(candidate) and text[candidate] == "-":
            candidate += 1
        digit_start = candidate
        while available(candidate) and (_ascii_digit(text[candidate]) or text[candidate] == "_"):
            candidate += 1
        if candidate > digit_start:
            index = candidate

    if not radix_prefix and available(index) and text[index] == "f":
        float_suffix = re.match(r"f(?:16|32|64)", text[index:])
        if float_suffix is not None:
            suffix_end = index + float_suffix.end()
            if not available(suffix_end) or not _identifier_continue(text[suffix_end]):
                index = suffix_end
    return index


def _identity_tokens(text: str) -> list[IdentityToken]:
    line, state = _lex_line(text, LexicalState())
    if _lexically_open(state):
        raise ValueError("unterminated literal in public API identity")
    result: list[IdentityToken] = []
    index = 0
    while index < len(text):
        if line.literal[index]:
            end = index + 1
            while end < len(text) and line.literal[end]:
                end += 1
            result.append(IdentityToken("literal", text[index:end]))
            index = end
            continue
        character = text[index]
        if character.isspace() or line.comment[index]:
            index += 1
            continue
        if character == "`":
            end = text.find("`", index + 1)
            if end < 0:
                raise ValueError("unterminated escaped identifier in public API")
            value = text[index:end + 1]
            if not _is_identifier_token(value):
                raise ValueError(f"invalid escaped identifier in public API: {value!r}")
            result.append(IdentityToken("identifier", _nfc_identifier(value)))
            index = end + 1
            continue
        if _identifier_start(character):
            end = index + 1
            while end < len(text) and _identifier_continue(text[end]):
                end += 1
            value = text[index:end]
            if not _is_plain_identifier(value):
                raise ValueError(f"invalid identifier in public API: {value!r}")
            result.append(IdentityToken("identifier", _nfc_identifier(value)))
            index = end
            continue
        if ("0" <= character <= "9" or
            (character == "." and index + 1 < len(text) and
                "0" <= text[index + 1] <= "9")):
            end = _scan_number_literal(text, index, line.literal)
            result.append(IdentityToken("number", text[index:end]))
            index = end
            continue
        matched = next((token for token in MULTI_CHARACTER_TOKENS
            if text.startswith(token, index)), None)
        if matched is not None:
            result.append(IdentityToken("symbol", matched))
            index += len(matched)
            continue
        result.append(IdentityToken("symbol", character))
        index += 1
    return _split_contextual_angle_tokens(result)


def _generic_identity_close(
    tokens: list[IdentityToken],
    opening: int,
) -> tuple[int, str] | None:
    depth = 1
    for index in range(opening + 1, len(tokens)):
        value = tokens[index].text
        if value == "<":
            depth += 1
        elif value == ">":
            depth -= 1
        elif value == ">>":
            depth -= 2
        elif value == ">=":
            depth -= 1
        elif depth == 1 and value in (";", "{", "}"):
            return None
        if depth <= 0:
            return index, value
    return None


def _identity_generic_open(
    tokens: list[IdentityToken],
    index: int,
    in_default: bool,
) -> bool:
    if index == 0 or tokens[index - 1].kind != "identifier":
        return False
    closing = _generic_identity_close(tokens, index)
    if closing is None:
        return False
    closing_index, closing_token = closing
    if not in_default:
        return True
    owner = tokens[index - 1].text.strip("`")
    owner_is_type_shaped = (bool(owner) and
        (owner[0].isupper() or not owner[0].isascii()))
    following_index = closing_index + 1
    if closing_token in (">>", ">="):
        following_text = ">" if closing_token == ">>" else "="
    else:
        following_text = (tokens[following_index].text
            if following_index < len(tokens) else "")
    return owner_is_type_shaped or following_text in ("(", "[", ".", "?")


def _split_contextual_angle_tokens(tokens: list[IdentityToken]) -> list[IdentityToken]:
    """Split compact generic closers without weakening shift/comparison operators."""
    result: list[IdentityToken] = []
    angle_depth = 0
    in_default = False
    type_alias = any(token.text == "type" for token in tokens[:8])
    for index, token in enumerate(tokens):
        value = token.text
        if value == "<" and _identity_generic_open(tokens, index, in_default):
            angle_depth += 1
            result.append(token)
            continue
        if value == ">" and angle_depth > 0:
            angle_depth -= 1
            result.append(token)
            continue
        if value == ">>" and angle_depth >= 2:
            result.extend((IdentityToken("symbol", ">"), IdentityToken("symbol", ">")))
            angle_depth -= 2
            continue
        if value == ">=" and angle_depth > 0:
            result.extend((IdentityToken("symbol", ">"), IdentityToken("symbol", "=")))
            angle_depth -= 1
            in_default = not type_alias
            continue
        result.append(token)
        if value == "=" and angle_depth == 0:
            in_default = not type_alias
    return result


def _identity_token_needs_space(previous: IdentityToken, current: IdentityToken) -> bool:
    if previous.text in SPACED_TOKENS or current.text in SPACED_TOKENS:
        return True
    if previous.text + current.text in MULTI_CHARACTER_TOKENS:
        return True
    if ((previous.kind == "number" and current.text == ".") or
        (previous.text == "." and current.kind == "number")):
        return True
    if previous.text in (":", ",", ";"):
        return True
    if previous.text == "func" and current.text == "[":
        return True
    if current.text in (")", "]", "}", ",", ";", ":", ".", "(", "[", "<", ">"):
        return False
    if previous.text in ("(", "[", "{", ".", "@", "<", "!", "?"):
        return False
    if current.text in ("!", "?"):
        return False
    if current.kind == "literal" and previous.text == "}":
        return False
    return True


def _canonical_parts(parts: list[str]) -> str:
    stripped = _trivia_stripped_text(parts)
    tokens = _identity_tokens(stripped)
    if not tokens:
        return ""
    output = [tokens[0].text]
    for previous, current in zip(tokens, tokens[1:]):
        if _identity_token_needs_space(previous, current):
            output.append(" ")
        output.append(current.text)
    return "".join(output)


def _declaration_identity_tokens(parts: list[str]) -> list[IdentityToken]:
    """Return semantic tokens after removing trivia but preserving literals."""
    return _identity_tokens(_trivia_stripped_text(parts))


def _word_tokens(code: str) -> list[tuple[str, int, int]]:
    result: list[tuple[str, int, int]] = []
    index = 0
    while index < len(code):
        character = code[index]
        if character.isspace():
            index += 1
            continue
        if character == "`":
            end = code.find("`", index + 1)
            if end < 0:
                raise ValueError("unterminated escaped identifier in public API declaration")
            value = code[index:end + 1]
            if not _is_identifier_token(value):
                raise ValueError(f"invalid escaped identifier in public API declaration: {value!r}")
            result.append((_nfc_identifier(value), index, end + 1))
            index = end + 1
            continue
        if _identifier_start(character):
            end = index + 1
            while end < len(code) and _identifier_continue(code[end]):
                end += 1
            value = code[index:end]
            if not _is_plain_identifier(value):
                raise ValueError(f"invalid identifier in public API declaration: {value!r}")
            result.append((_nfc_identifier(value), index, end))
            index = end
            continue
        result.append((character, index, index + 1))
        index += 1
    return result


def _matching_delimiter(code: str, opening: int, opener: str, closer: str) -> int | None:
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == opener:
            depth += 1
        elif code[index] == closer:
            depth -= 1
            if depth == 0:
                return index
            if depth < 0:
                raise ValueError("unbalanced public API declaration")
    return None


def _annotation_end_in_code(code: str) -> int | None:
    cursor = 0
    found = False
    while True:
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        if cursor >= len(code) or code[cursor] != "@":
            return cursor if found else 0
        found = True
        name = re.match(rf"@{ANNOTATION_NAME}", code[cursor:])
        if name is None:
            raise ValueError("cannot normalize public API annotation")
        cursor += name.end()
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        if cursor < len(code) and code[cursor] == "[":
            closing = _matching_delimiter(code, cursor, "[", "]")
            if closing is None:
                return None
            cursor = closing + 1


def _annotation_prefix_end(declaration: str) -> int:
    """Return the first declaration byte after consecutive canonical annotations."""
    line, state = _lex_line(declaration, LexicalState())
    if _lexically_open(state):
        raise ValueError("unterminated literal in public API declaration")
    end = _annotation_end_in_code(line.code)
    if end is None:
        raise ValueError("unterminated public API annotation")
    return end


def _annotation_prefix_extent(raw: str) -> int | None:
    """Return a same-line annotation prefix end, or None when it continues."""
    line, _ = _lex_line(raw, LexicalState())
    return _annotation_end_in_code(line.code)


def _annotation_balance_extent(code: str, initial_balance: int) -> tuple[int, int | None]:
    balance = initial_balance
    end: int | None = None
    started = initial_balance > 0
    for index, character in enumerate(code):
        if character in "([{":
            balance += 1
            started = True
        elif character in ")]}":
            balance -= 1
            if balance < 0:
                raise ValueError("unbalanced public API annotation")
            if started and balance == 0:
                end = index + 1
                break
    return balance, end


def _canonical_annotation(parts: list[str]) -> str:
    canonical = _canonical_parts(parts)
    return re.sub(rf"^(@{ANNOTATION_NAME})\s+\[", r"\1[", canonical)


def _declaration_head(declaration: str, owner_name: str | None = None) -> DeclarationHead | None:
    line, state = _lex_line(declaration, LexicalState())
    if _lexically_open(state):
        raise ValueError("unterminated literal in public API declaration")
    start = _annotation_prefix_end(declaration)
    tokens = _word_tokens(line.code[start:])
    tokens = [(value, first + start, end + start) for value, first, end in tokens]
    if not tokens:
        return None
    modifiers: list[str] = []
    cursor = 0
    while cursor < len(tokens) and tokens[cursor][0] in DECLARATION_MODIFIERS:
        modifiers.append(tokens[cursor][0])
        cursor += 1
    visibilities = set(modifiers) & VISIBILITY_MODIFIERS
    if len(visibilities) > 1:
        raise ValueError("conflicting visibility modifiers in public API declaration")
    visibility = next(iter(visibilities), None)
    if cursor >= len(tokens):
        return None
    value, first, end = tokens[cursor]
    kind: str | None = None
    name: str | None = None
    keyword_end = end
    if value in TYPE_KINDS:
        kind = value
        if cursor + 1 < len(tokens) and _is_identifier_token(tokens[cursor + 1][0]):
            name = tokens[cursor + 1][0]
        else:
            raise ValueError(f"{value} declaration is missing its name")
    elif value in ("func", "init", "prop", "type", "extend", "import", "let", "var"):
        kind = {"let": "field", "var": "field", "type": "type-alias"}.get(value, value)
    elif value == "operator" and cursor + 1 < len(tokens) and tokens[cursor + 1][0] == "func":
        kind = "operator func"
        keyword_end = tokens[cursor + 1][2]
    elif (owner_name is not None and value == owner_name and cursor + 1 < len(tokens) and
        tokens[cursor + 1][0] == "("):
        kind = "named-constructor"
        name = value
    elif "const" in modifiers and _is_identifier_token(value):
        kind = "field"
        name = value
    if kind is None:
        return None
    return DeclarationHead(kind, tuple(modifiers), visibility, name, first, keyword_end)


def _annotated_declaration(annotations: list[str], declaration: str) -> str:
    if not annotations:
        return declaration
    return " ".join(annotations + [declaration])


def _generic_angle_end(code: str, opening: int, limit: int) -> int | None:
    depth = 0
    for index in range(opening, limit):
        character = code[index]
        previous = code[index - 1] if index > opening else ""
        following = code[index + 1] if index + 1 < limit else ""
        if character == "<" and following != ":":
            depth += 1
        elif character == ">" and previous != "-":
            depth -= 1
            if depth == 0:
                return index
            if depth < 0:
                return None
        elif depth > 0 and character in "{};=":
            return None
    return None


def _is_generic_angle_open(code: str, opening: int, limit: int, in_default: bool) -> bool:
    if code[opening:opening + 2] == "<:":
        return False
    closing = _generic_angle_end(code, opening, limit)
    if closing is None:
        return False
    if not in_default:
        return True
    content = code[opening + 1:closing].strip()
    first_name = re.search(r"[A-Za-z_][A-Za-z0-9_]*", content)
    if first_name is None:
        return False
    type_shaped = (first_name.group(0)[0].isupper() or
        re.search(r"\.[A-Z][A-Za-z0-9_]*", content) is not None or
        content.startswith(("?", "(", "[")))
    if not type_shaped:
        return False
    cursor = closing + 1
    while cursor < limit and code[cursor].isspace():
        cursor += 1
    return cursor >= limit or code[cursor] in "([.?!)],"


def _constructor_parameter_members(declaration: str, scope: TypeScope) -> list[str]:
    head = _declaration_head(declaration, scope.name)
    if head is None or head.kind != "named-constructor":
        return []
    line, state = _lex_line(declaration, LexicalState())
    if _lexically_open(state):
        raise ValueError("unterminated literal in constructor declaration")
    opening = line.code.find("(", head.keyword_end)
    if opening < 0:
        raise ValueError("same-name constructor is missing its parameter list")
    closing = _matching_delimiter(line.code, opening, "(", ")")
    if closing is None:
        raise ValueError("same-name constructor has an unterminated parameter list")
    segments: list[tuple[int, int]] = []
    start = opening + 1
    depths = {"(": 0, "[": 0, "{": 0, "<": 0}
    pairs = {")": "(", "]": "[", "}": "{", ">": "<"}
    in_default = False
    for index in range(opening + 1, closing):
        character = line.code[index]
        previous = line.code[index - 1] if index > 0 else ""
        following = line.code[index + 1] if index + 1 < len(line.code) else ""
        if character in "([{":
            depths[character] += 1
        elif character == "<" and _is_generic_angle_open(
            line.code, index, closing, in_default):
            depths["<"] += 1
        elif character in ")]}":
            key = pairs[character]
            depths[key] -= 1
        elif character == ">" and previous != "-" and depths["<"] > 0:
            depths["<"] -= 1
        elif (character == "=" and all(value == 0 for value in depths.values()) and
            previous not in ("=", "!", "<", ">") and following not in ("=", ">")):
            in_default = True
        elif character == "," and all(value == 0 for value in depths.values()):
            segments.append((start, index))
            start = index + 1
            in_default = False
        if any(value < 0 for value in depths.values()):
            raise ValueError("unbalanced same-name constructor parameter")
    if any(depths.values()):
        raise ValueError("unbalanced same-name constructor parameter")
    segments.append((start, closing))
    result: list[str] = []
    for first, end in segments:
        parameter = declaration[first:end].strip()
        if not parameter:
            continue
        parameter_head = _declaration_head(parameter)
        if parameter_head is None:
            if re.search(r"\b(?:public|protected)\b", line.code[first:end]):
                raise ValueError("cannot normalize visible constructor parameter member")
            continue
        visible = (parameter_head.kind == "field" and
            (parameter_head.visibility == "public" or
                (parameter_head.visibility == "protected" and scope.externally_subclassable)))
        if visible:
            result.append("constructor-member " + parameter)
        elif parameter_head.visibility in ("public", "protected") and parameter_head.kind != "field":
            raise ValueError("cannot normalize visible constructor parameter member")
    return result


def _append_declaration(
    declarations: list[str],
    relative: str,
    package: str,
    owner: str | None,
    declaration: str,
    *,
    prefix: str = "",
    annotations: list[str] | None = None,
    scope: TypeScope | None = None,
) -> None:
    try:
        canonical = _stable_api_declaration(
            _canonical_parts(declaration.split("\n")), scope.name if scope is not None else None)
    except ValueError as error:
        raise ValueError(
            f"{relative}: cannot normalize declaration {declaration!r}: {error}") from error
    decorated = _annotated_declaration(annotations or [], prefix + canonical)
    declarations.append(_owner_record(relative, package, owner, decorated))
    if scope is not None:
        for member in _constructor_parameter_members(canonical, scope):
            declarations.append(_owner_record(relative, package, owner, member))


def _structural_body_opening(declaration: str, owner_name: str | None = None) -> int | None:
    """Locate a callable/property body, excluding literals and default closures."""
    semantic = declaration.strip()
    line, state = _lex_line(semantic, LexicalState())
    if _lexically_open(state):
        raise ValueError("unterminated literal in public API declaration")
    code = line.code
    head = _declaration_head(semantic, owner_name)
    if head is None or head.kind not in CALLABLE_KINDS:
        return None
    paren_depth = 0
    bracket_depth = 0
    for index, character in enumerate(code):
        if character == "(":
            paren_depth += 1
        elif character == ")":
            paren_depth -= 1
        elif character == "[":
            bracket_depth += 1
        elif character == "]":
            bracket_depth -= 1
        elif character == "{" and paren_depth == 0 and bracket_depth == 0:
            return index
        if paren_depth < 0 or bracket_depth < 0:
            raise ValueError("unbalanced public API declaration")
    if paren_depth != 0 or bracket_depth != 0:
        return None
    return None


def _stable_api_declaration(declaration: str, owner_name: str | None = None) -> str:
    """Keep API identity and replace an implementation body with its opening marker."""
    semantic = declaration.strip()
    head = _declaration_head(semantic, owner_name)
    if head is not None and head.kind == "import":
        semantic = re.sub(r"\s*\.\s*", ".", semantic)
    elif head is not None and head.kind in (
        "func", "init", "operator func", "named-constructor",
    ):
        line, state = _lex_line(semantic, LexicalState())
        if _lexically_open(state):
            raise ValueError("unterminated literal in public API declaration")
        parameters = line.code.find("(", head.keyword_end)
        if parameters >= 0:
            semantic = semantic[:parameters].rstrip() + semantic[parameters:]
    opening = _structural_body_opening(semantic, owner_name)
    return semantic[:opening + 1].rstrip() if opening is not None else semantic


def _type_alias_has_target(declaration: str) -> bool:
    line, state = _lex_line(declaration, LexicalState())
    if _lexically_open(state):
        raise ValueError("unterminated literal in public type alias")
    assignment = line.code.find("=")
    return assignment >= 0 and bool(line.code[assignment + 1:].strip().removesuffix(";").strip())


def _type_alias_delimiter_delta(fragment: str) -> int:
    """Track multiline type groupings without treating -> or <: as generic delimiters."""
    delta = 0
    for index, character in enumerate(fragment):
        previous = fragment[index - 1] if index > 0 else ""
        following = fragment[index + 1] if index + 1 < len(fragment) else ""
        if character in "([":
            delta += 1
        elif character in ")]":
            delta -= 1
        elif character == "<" and following != ":":
            delta += 1
        elif character == ">" and previous != "-":
            delta -= 1
    return delta


def _next_significant(lines: list[LexedLine], index: int) -> LexedLine | None:
    cursor = index + 1
    while cursor < len(lines):
        if lines[cursor].code.strip():
            return lines[cursor]
        cursor += 1
    return None


def _next_significant_index(lines: list[LexedLine], index: int) -> int | None:
    cursor = index + 1
    while cursor < len(lines):
        if lines[cursor].code.strip():
            return cursor
        cursor += 1
    return None


def _merge_lexed_lines(lines: list[LexedLine]) -> LexedLine:
    """Re-lex logical source joined across physical lines, retaining open literal state."""
    merged, _ = _lex_line("\n".join(line.raw for line in lines), LexicalState())
    return merged


def _merge_dotted_package_lines(lines: list[LexedLine]) -> list[LexedLine]:
    """Join only grammar-required package continuations, independent of indentation."""
    result = list(lines)
    brace_depth = 0
    index = 0
    while index < len(result):
        line = result[index]
        stripped = line.code.strip()
        if brace_depth == 0 and re.match(r"package\b", stripped) is not None:
            while True:
                following_index = _next_significant_index(result, index)
                if following_index is None:
                    break
                following = result[following_index].code.strip()
                requires_token = stripped == "package" or stripped.rstrip().endswith(".")
                continues_with_dot = following.startswith(".")
                if not requires_token and not continues_with_dot:
                    break
                line = _merge_lexed_lines(
                    [line, *result[index + 1:following_index + 1]])
                result[index:following_index + 1] = [line]
                stripped = line.code.strip()
        brace_depth += line.brace_delta
        index += 1
    return result


def _declaration_shape(parts: list[str]) -> str:
    """Return comment-free syntax with each literal byte represented as an atom."""
    output: list[str] = []
    for part_index, line in enumerate(_lex_source(parts)):
        for index, character in enumerate(line.raw):
            if line.comment[index]:
                output.append(" ")
            elif line.literal[index]:
                output.append("L")
            else:
                output.append(line.code[index])
        if part_index + 1 < len(parts):
            output.append("\n")
    return "".join(output)


def _previous_nonspace(text: str, index: int) -> str:
    cursor = index - 1
    while cursor >= 0 and text[cursor].isspace():
        cursor -= 1
    return text[cursor] if cursor >= 0 else ""


def _declaration_delimiter_depths(
    shape: str,
    head: DeclarationHead | None,
) -> tuple[int, int, int, int]:
    parens = 0
    brackets = 0
    braces = 0
    angles = 0
    field_initializer = False
    for index, character in enumerate(shape):
        previous = shape[index - 1] if index > 0 else ""
        following = shape[index + 1] if index + 1 < len(shape) else ""
        if character == "(":
            parens += 1
        elif character == ")":
            parens -= 1
        elif character == "[":
            brackets += 1
        elif character == "]":
            brackets -= 1
        elif character == "{":
            braces += 1
        elif character == "}":
            braces -= 1
        elif (head is not None and head.kind == "field" and character == "=" and
            parens == 0 and brackets == 0 and braces == 0 and
            previous not in ("=", "!", "<", ">") and following not in ("=", ">")):
            field_initializer = True
        elif character == "<" and following != ":":
            type_context = (head is not None and head.kind == "type-alias")
            if (not type_context and head is not None and not field_initializer and
                parens == 0 and braces == 0):
                before = _previous_nonspace(shape, index)
                type_context = bool(before) and (before.isalnum() or before in "_.)]>?")
            if type_context:
                angles += 1
        elif character == ">" and previous != "-" and angles > 0:
            angles -= 1
        if min(parens, brackets, braces, angles) < 0:
            raise ValueError("unbalanced public API declaration continuation")
    return parens, brackets, braces, angles


def _declaration_head_requires_more(shape: str, head: DeclarationHead | None) -> bool:
    if head is None:
        return False
    tail = shape[head.keyword_end:]
    if head.kind in ("func", "init", "operator func", "named-constructor"):
        return "(" not in tail
    if head.kind == "prop":
        return ":" not in tail
    if head.kind == "field":
        return ":" not in tail and "=" not in tail
    if head.kind == "import":
        return not tail.strip()
    return False


def _declaration_prefix_requires_next(
    line: LexedLine,
    owner_name: str | None,
) -> bool:
    """Recognize declaration prefixes whose next grammar token is mandatory."""
    stripped = line.code.strip()
    tokens = _word_tokens(stripped)
    if not tokens:
        return False
    cursor = 0
    while cursor < len(tokens) and tokens[cursor][0] in DECLARATION_MODIFIERS:
        cursor += 1
    if cursor == len(tokens):
        return cursor > 0
    keyword = tokens[cursor][0]
    if keyword in TYPE_KINDS:
        return (cursor + 1 >= len(tokens) or
            not _is_identifier_token(tokens[cursor + 1][0]))
    if keyword == "operator":
        return cursor + 1 >= len(tokens)
    if owner_name is not None and keyword == owner_name:
        return cursor + 1 >= len(tokens)
    try:
        head = _declaration_head(stripped, owner_name)
    except ValueError as error:
        message = str(error)
        if "declaration is missing its name" in message:
            return True
        raise
    if head is None:
        return False
    return _declaration_head_requires_more(stripped, head)


def _declaration_continues(
    lines: list[LexedLine],
    index: int,
    parts: list[str],
    mode: str,
    scope: TypeScope | None,
) -> bool:
    """Decide continuation from grammar structure, never from indentation."""
    if lines[index].code.rstrip().endswith(";"):
        return False
    try:
        canonical = _canonical_parts(parts)
        shape = _declaration_shape(parts).rstrip()
    except ValueError:
        return True
    owner_name = scope.name if scope is not None else None
    head = _declaration_head(canonical, owner_name)
    if (mode == "signature" and head is not None and head.kind in CALLABLE_KINDS and
        _structural_body_opening(canonical, owner_name) is not None):
        return False
    parens, brackets, braces, angles = _declaration_delimiter_depths(shape, head)
    if parens > 0 or brackets > 0 or braces > 0 or angles > 0:
        return True
    if _declaration_head_requires_more(shape, head):
        return True
    if mode == "import" and re.search(r"\.\s*\*$", shape) is not None:
        return False
    tokens = _declaration_identity_tokens(parts)
    if tokens and tokens[-1].text in DECLARATION_TRAILING_CONTINUATION_TOKENS:
        return True
    following = _next_significant(lines, index)
    if following is None:
        return False
    next_code = following.code.strip()
    if not next_code:
        return False
    if head is not None and head.kind in CALLABLE_KINDS and next_code.startswith("{"):
        return True
    # ``following`` may be the first physical line of a multiline literal.
    # Its precomputed code mask is safe to tokenize without requiring that
    # literal to close on this line.
    next_tokens = _identity_tokens(following.code.strip())
    return bool(next_tokens and
        next_tokens[0].text in DECLARATION_LEADING_CONTINUATION_TOKENS)


def _advance_scopes(scopes: list[TypeScope], brace_depth: int, line: LexedLine) -> int:
    brace_depth += line.brace_delta
    while scopes and brace_depth < scopes[-1].body_depth:
        scopes.pop()
    return brace_depth


def _slice_lexed_line(line: LexedLine, start: int, end: int, *, last: bool) -> LexedLine:
    raw = line.raw[start:end]
    code = line.code[start:end]
    semantic = line.semantic[start:end]
    literal = line.literal[start:end]
    comment = line.comment[start:end]
    openings = code.count("{")
    return LexedLine(
        raw,
        code,
        semantic,
        literal,
        comment,
        openings - code.count("}"),
        openings,
        line.lexical_continuation if last else False,
    )


def _valid_package_tail_start(line: LexedLine) -> bool:
    stripped = line.code.strip()
    if not stripped:
        return not any(line.literal)
    if stripped.startswith("@") or PACKAGE_PREFIX.match(line.code) is not None:
        return True
    if re.match(r"main\s*\(", stripped) is not None:
        return True
    try:
        return _declaration_head(stripped) is not None
    except ValueError:
        return False


def _split_package_declaration_lines(
    lines: list[LexedLine],
    relative: str,
) -> list[LexedLine]:
    """Isolate a canonical package declaration from same-line top-level source."""
    result: list[LexedLine] = []
    brace_depth = 0
    for original in lines:
        queue = [original]
        while queue:
            line = queue.pop(0)
            match = PACKAGE_PREFIX.match(line.code) if brace_depth == 0 else None
            if match is None or match.end() == len(line.raw):
                result.append(line)
                continue
            package_line = _slice_lexed_line(line, 0, match.end(), last=False)
            remainder = _slice_lexed_line(
                line, match.end(), len(line.raw), last=True)
            if not _valid_package_tail_start(remainder):
                raise ValueError(
                    f"{relative}: invalid declaration after package separator: "
                    f"{remainder.code.strip()!r}")
            result.append(package_line)
            queue.insert(0, remainder)
        brace_depth += original.brace_delta
    return result


def _split_direct_declaration_line(
    line: LexedLine,
    brace_depth: int,
    direct_depths: set[int],
    initial_group_depth: int,
    *,
    close_type_angles: bool,
) -> list[LexedLine]:
    """Split semicolon-separated declarations only at an API-owner direct scope."""
    current_brace_depth = brace_depth
    group_depth = max(initial_group_depth, 0)
    boundaries: list[int] = []
    for index, character in enumerate(line.code):
        if character in "([":
            group_depth += 1
        elif character in ")]":
            group_depth -= 1
        elif character == "{":
            current_brace_depth += 1
            group_depth += 1
        elif character == "}":
            current_brace_depth -= 1
            group_depth -= 1
        elif (close_type_angles and character == ">" and
            (index == 0 or line.code[index - 1] != "-") and group_depth > 0):
            group_depth -= 1
        elif (close_type_angles and character == "<" and
            (index + 1 >= len(line.code) or line.code[index + 1] != ":")):
            group_depth += 1
        elif (character == ";" and group_depth == 0 and
            current_brace_depth in direct_depths):
            boundaries.append(index + 1)
        if group_depth < 0:
            # A closing brace can belong to an owner opened on an earlier line.
            group_depth = 0
    if not boundaries:
        return [line]
    result: list[LexedLine] = []
    start = 0
    for boundary in boundaries:
        if boundary > start:
            result.append(_slice_lexed_line(line, start, boundary, last=False))
        start = boundary
    if start < len(line.raw):
        result.append(_slice_lexed_line(line, start, len(line.raw), last=True))
    elif result:
        final = result[-1]
        result[-1] = LexedLine(
            final.raw,
            final.code,
            final.semantic,
            final.literal,
            final.comment,
            final.brace_delta,
            final.brace_openings,
            line.lexical_continuation,
        )
    return result or [line]


def _validate_structural_body_remainder(
    relative: str,
    declaration: str,
    owner_name: str | None,
) -> None:
    """Reject a second declaration that was not separated at a safe boundary."""
    opening = _structural_body_opening(declaration, owner_name)
    if opening is None:
        return
    line, state = _lex_line(declaration, LexicalState())
    if _lexically_open(state):
        return
    closing = _matching_brace(line.code, opening)
    if closing is None:
        return
    trailing = line.code[closing + 1:].strip()
    if trailing not in ("", ";"):
        raise ValueError(
            f"{relative}: declaration remainder has no safe structural separator: {trailing!r}")


def _matching_brace(code: str, opening: int) -> int | None:
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == "{":
            depth += 1
        elif code[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


def _body_segments(line: LexedLine, opening: int, closing: int, kind: str) -> list[tuple[str, str]]:
    code = line.code
    segments: list[tuple[int, int]] = []
    brace_depth = 0
    paren_depth = 0
    bracket_depth = 0
    start: int | None = opening + 1 if kind != "enum" else None
    for index in range(opening + 1, closing):
        character = code[index]
        direct = brace_depth == 0 and paren_depth == 0 and bracket_depth == 0
        if kind == "enum" and character == "|" and direct:
            if start is not None:
                segments.append((start, index))
            start = index
            continue
        if character == ";" and direct:
            if start is not None:
                segments.append((start, index))
            start = index + 1 if kind != "enum" else None
            continue
        if character == "{":
            brace_depth += 1
        elif character == "}":
            brace_depth -= 1
        elif character == "(":
            paren_depth += 1
        elif character == ")":
            paren_depth -= 1
        elif character == "[":
            bracket_depth += 1
        elif character == "]":
            bracket_depth -= 1
        if brace_depth < 0 or paren_depth < 0 or bracket_depth < 0:
            raise ValueError("unbalanced single-line public API body")
    if brace_depth != 0 or paren_depth != 0 or bracket_depth != 0:
        raise ValueError("unbalanced single-line public API body")
    if start is not None:
        segments.append((start, closing))
    result: list[tuple[str, str]] = []
    for first, end in segments:
        code_fragment = code[first:end].strip()
        if code_fragment:
            result.append((code_fragment, line.raw[first:end]))
    return result


def _collect_single_line_body(
    relative: str,
    package: str,
    scope: TypeScope,
    line: LexedLine,
    opening: int,
    closing: int,
    declarations: list[str],
) -> None:
    fragments = _body_segments(line, opening, closing, scope.kind)
    if not scope.effective_public:
        return
    for code, semantic in fragments:
        if scope.kind == "enum":
            if not code.startswith("|"):
                raise ValueError(f"{relative}: cannot normalize single-line enum body fragment: {code!r}")
            _append_declaration(declarations, relative, package, scope.owner, semantic,
                prefix="enum-variant ")
            continue
        head = _declaration_head(code, scope.name)
        if head is not None and head.kind in TYPE_KINDS:
            if head.visibility == "public":
                raise ValueError(f"{relative}: public nested type in a single-line body is unsupported")
            continue
        if head is not None and head.visibility == "public":
            _append_declaration(declarations, relative, package, scope.owner, semantic, scope=scope)
        elif (head is not None and head.visibility == "protected" and
            scope.externally_subclassable):
            _append_declaration(declarations, relative, package, scope.owner, semantic, scope=scope)
        elif (head is not None and scope.kind == "interface" and head.visibility is None and
            head.kind in CALLABLE_KINDS | {"type-alias", "field"}):
            _append_declaration(declarations, relative, package, scope.owner, semantic,
                prefix="interface-member ", scope=scope)
        elif head is not None:
            continue
        elif (re.search(r"\bpublic\b", code) or
            (scope.externally_subclassable and re.search(r"\bprotected\b", code))):
            raise ValueError(f"{relative}: cannot normalize visible single-line API fragment: {code!r}")
        else:
            raise ValueError(f"{relative}: cannot normalize single-line public API body fragment: {code!r}")


def _complete_scope(
    relative: str,
    package: str,
    pending: PendingScope,
    line: LexedLine,
    opening: int,
    brace_depth: int,
    declarations: list[str],
) -> TypeScope:
    header = _canonical_parts(pending.parts)
    if pending.record_public:
        declarations.append(_owner_record(relative, package, pending.parent_owner,
            _annotated_declaration(pending.annotations, header)))
    identity = (_annotated_declaration(pending.annotations, header)
        if pending.kind == "extend" else pending.name)
    segment = _owner_segment(pending.kind, identity)
    owner = f"{pending.parent_owner}>{segment}" if pending.parent_owner is not None else segment
    scope = TypeScope(pending.kind, pending.name, owner, brace_depth + 1, pending.effective_public,
        pending.externally_subclassable)
    closing = _matching_brace(line.code, opening)
    if closing is None:
        if line.code[opening + 1:].strip():
            raise ValueError(f"{relative}: nonempty type body must close on the same line or start on a new line")
        return scope
    trailing = line.code[closing + 1:].strip()
    if trailing not in ("", ";"):
        raise ValueError(f"{relative}: multiple top-level declarations on one line are unsupported")
    _collect_single_line_body(relative, package, scope, line, opening, closing, declarations)
    return scope


def _valid_owner(owner: str) -> bool:
    for segment in owner.split(">"):
        kind, encoded = segment.split("/", 1)
        try:
            decoded = unquote_to_bytes(encoded).decode("utf-8")
        except UnicodeDecodeError:
            return False
        if quote(decoded, safe="") != encoded:
            return False
        if kind == "extend":
            try:
                head = _declaration_head(decoded)
            except ValueError:
                return False
            if head is None or head.kind != "extend" or not decoded.endswith("{"):
                return False
        elif not _is_identifier_token(decoded):
            return False
    return True


def _record_declaration(record: str) -> str:
    prefix = RECORD_PREFIX.match(record)
    if prefix is None:
        return record
    declaration = record[prefix.end():]
    owner = OWNER_PREFIX.match(declaration)
    return declaration[owner.end():] if owner is not None else declaration


def _canonical_owner_identity(owner: str) -> str:
    result: list[str] = []
    for segment in owner.split(">"):
        kind, encoded = segment.split("/", 1)
        decoded = unquote_to_bytes(encoded).decode("utf-8")
        identity = (_canonical_parts([decoded]) if kind == "extend"
            else _nfc_identifier(decoded))
        result.append(_owner_segment(kind, identity))
    return ">".join(result)


def normalized_declarations() -> list[str]:
    declarations: list[str] = []
    for path in sorted((ROOT / "src").rglob("*.cj")):
        if path.name.endswith("_test.cj") or path.name.startswith("generated_"):
            continue
        relative = path.relative_to(ROOT / "src").as_posix()
        raw_lines = path.read_text(encoding="utf-8").split("\n")
        lines = _lex_source(raw_lines)
        lines = _merge_dotted_package_lines(lines)
        lines = _split_package_declaration_lines(lines, relative)
        package = _source_package(lines, relative)
        brace_depth = 0
        type_scopes: list[TypeScope] = []
        pending_scope: PendingScope | None = None
        pending_declaration: PendingDeclaration | None = None
        pending_annotations: list[str] = []
        annotation_parts: list[str] | None = None
        annotation_balance = 0
        for index, line in enumerate(lines):
            direct_depths = {0, *(scope.body_depth for scope in type_scopes)}
            initial_group_depth = annotation_balance
            if pending_declaration is not None:
                initial_group_depth = max(initial_group_depth, pending_declaration.balance)
            fragments = _split_direct_declaration_line(
                line, brace_depth, direct_depths, initial_group_depth,
                close_type_angles=(pending_declaration is not None and
                    pending_declaration.mode == "alias"))
            if len(fragments) > 1:
                lines[index:index + 1] = fragments
            line = fragments[0]
            stripped = line.code.strip()
            if pending_scope is not None:
                if line.brace_openings > 0:
                    opening = line.code.find("{")
                    header_piece = line.raw[:opening + 1]
                    if header_piece.strip():
                        pending_scope.parts.append(header_piece)
                    type_scopes.append(_complete_scope(
                        relative, package, pending_scope, line, opening, brace_depth, declarations))
                    pending_scope = None
                elif line.raw.strip():
                    pending_scope.parts.append(line.raw)
                brace_depth = _advance_scopes(type_scopes, brace_depth, line)
                continue
            if pending_declaration is not None:
                if line.raw.strip() or line.literal:
                    pending_declaration.parts.append(line.raw)
                if pending_declaration.mode == "import":
                    pending_declaration.balance += line.brace_delta
                    complete = (pending_declaration.balance <= 0 and
                        not _declaration_continues(
                            lines, index, pending_declaration.parts, "import",
                            pending_declaration.scope))
                elif pending_declaration.mode == "alias":
                    pending_declaration.balance += _type_alias_delimiter_delta(stripped)
                    if pending_declaration.balance < 0:
                        raise ValueError(f"{relative}: unbalanced public type alias")
                    if line.lexical_continuation:
                        complete = False
                    else:
                        combined = _canonical_parts(pending_declaration.parts)
                        complete = (_type_alias_has_target(combined) and
                            pending_declaration.balance == 0 and
                            not _declaration_continues(
                                lines, index, pending_declaration.parts, "alias",
                                pending_declaration.scope))
                else:
                    pending_declaration.balance += stripped.count("(") - stripped.count(")")
                    if line.lexical_continuation:
                        complete = False
                    else:
                        combined = _canonical_parts(pending_declaration.parts)
                        body_opening = (pending_declaration.mode == "signature" and
                            _structural_body_opening(combined) is not None and
                            pending_declaration.balance <= 0)
                        complete = (body_opening or stripped.endswith(";") or
                            (pending_declaration.balance <= 0 and
                                not _declaration_continues(
                                    lines, index, pending_declaration.parts,
                                    pending_declaration.mode, pending_declaration.scope)))
                if complete:
                    _append_declaration(
                        declarations, relative, package, pending_declaration.owner,
                        "\n".join(pending_declaration.parts), prefix=pending_declaration.prefix,
                        annotations=pending_declaration.annotations, scope=pending_declaration.scope)
                    pending_declaration = None
                brace_depth = _advance_scopes(type_scopes, brace_depth, line)
                continue
            if annotation_parts is not None:
                annotation_balance, annotation_end = _annotation_balance_extent(
                    line.code, annotation_balance)
                if annotation_end is None:
                    annotation_parts.append(line.raw)
                    continue
                annotation_parts.append(line.raw[:annotation_end])
                canonical_annotation = _canonical_annotation(annotation_parts)
                if _annotation_prefix_end(canonical_annotation) != len(canonical_annotation):
                    raise ValueError(f"{relative}: malformed public API annotation")
                pending_annotations.append(canonical_annotation)
                annotation_parts = None
                annotation_balance = 0
                remainder = line.raw[annotation_end:]
                if not remainder.strip():
                    continue
                line, _ = _lex_line(remainder, LexicalState())
                stripped = line.code.strip()
            if stripped.startswith("@"):
                annotation_end = _annotation_prefix_extent(line.raw)
                if annotation_end is None:
                    annotation_balance, _ = _annotation_balance_extent(line.code, 0)
                    if annotation_balance <= 0:
                        raise ValueError(f"{relative}: malformed public API annotation")
                    annotation_parts = [line.raw]
                    continue
                if annotation_end == 0:
                    raise ValueError(f"{relative}: malformed public API annotation")
                following = _next_significant(lines, index)
                if (not line.code[annotation_end:].strip() and following is not None and
                    following.code.strip().startswith("[")):
                    annotation_parts = [line.raw]
                    annotation_balance = 0
                    continue
                pending_annotations.append(_canonical_annotation([line.raw[:annotation_end]]))
                remainder = line.raw[annotation_end:]
                if not remainder.strip():
                    continue
                line, _ = _lex_line(remainder, LexicalState())
                stripped = line.code.strip()
            if not stripped:
                continue
            owner = type_scopes[-1].owner if type_scopes else None
            direct_member = not type_scopes or brace_depth == type_scopes[-1].body_depth
            scope = type_scopes[-1] if type_scopes else None
            if direct_member:
                owner_name = scope.name if scope is not None else None
                while _declaration_prefix_requires_next(line, owner_name):
                    following_index = _next_significant_index(lines, index)
                    if following_index is None:
                        raise ValueError(
                            f"{relative}: incomplete declaration prefix: {stripped!r}")
                    line = _merge_lexed_lines(
                        [line, *lines[index + 1:following_index + 1]])
                    lines[index:following_index + 1] = [line]
                    stripped = line.code.strip()
            head = _declaration_head(stripped, scope.name if scope is not None and direct_member else None)
            if (direct_member and head is not None and head.kind in CALLABLE_KINDS and
                not line.lexical_continuation):
                _validate_structural_body_remainder(
                    relative, line.raw, scope.name if scope is not None else None)
            if direct_member and head is not None and head.kind in TYPE_KINDS:
                kind = head.kind
                assert head.name is not None
                name = head.name
                modifiers = list(head.modifiers)
                explicit_visibility = head.visibility is not None
                implicit_sealed_public = (kind == "class" and not explicit_visibility and
                    "sealed" in modifiers and "abstract" in modifiers)
                declared_public = head.visibility == "public" or implicit_sealed_public
                parent_public = type_scopes[-1].effective_public if type_scopes else True
                effective_public = parent_public and declared_public
                externally_subclassable = (effective_public and kind == "class" and
                    "sealed" not in modifiers and
                    ("open" in modifiers or "abstract" in modifiers))
                opening = line.code.find("{") if line.brace_openings > 0 else None
                first_part = line.raw[:opening + 1] if opening is not None else line.raw
                pending_scope = PendingScope(
                    kind, name, owner, effective_public, externally_subclassable, effective_public,
                    [first_part] if first_part.strip() else [], list(pending_annotations))
                pending_annotations.clear()
            elif (not type_scopes and brace_depth == 0 and head is not None and
                head.kind == "extend"):
                effective_public = head.visibility not in ("private", "internal", "protected")
                opening = line.code.find("{") if line.brace_openings > 0 else None
                first_part = line.raw[:opening + 1] if opening is not None else line.raw
                pending_scope = PendingScope(
                    "extend", "", None, effective_public, False, False,
                    [first_part] if first_part.strip() else [], list(pending_annotations))
                pending_annotations.clear()
            if pending_scope is not None:
                if line.brace_openings > 0:
                    opening = line.code.find("{")
                    type_scopes.append(_complete_scope(
                        relative, package, pending_scope, line, opening, brace_depth, declarations))
                    pending_scope = None
                brace_depth = _advance_scopes(type_scopes, brace_depth, line)
                continue

            visible_context = not type_scopes or type_scopes[-1].effective_public
            if (head is not None and head.kind == "type-alias" and
                not type_scopes and brace_depth == 0 and head.visibility == "public"):
                balance = _type_alias_delimiter_delta(stripped)
                if balance < 0:
                    raise ValueError(f"{relative}: unbalanced public type alias")
                canonical = _canonical_parts([line.raw])
                if (balance > 0 or not _type_alias_has_target(canonical) or
                    (not stripped.endswith(";") and
                        _declaration_continues(
                            lines, index, [line.raw], "alias", None))):
                    pending_declaration = PendingDeclaration(
                        None, "", [line.raw], balance, "alias", None,
                        list(pending_annotations))
                else:
                    _append_declaration(declarations, relative, package, None, line.raw,
                        annotations=pending_annotations)
                pending_annotations.clear()
            elif (head is not None and head.kind == "import" and head.visibility == "public" and
                visible_context and direct_member):
                import_balance = line.brace_delta
                if (import_balance > 0 or _declaration_continues(
                    lines, index, [line.raw], "import", scope)):
                    pending_declaration = PendingDeclaration(
                        owner, "", [line.raw], import_balance, "import", scope,
                        list(pending_annotations))
                else:
                    _append_declaration(declarations, relative, package, owner, line.raw,
                        annotations=pending_annotations, scope=scope)
                pending_annotations.clear()
            elif (head is not None and head.visibility == "public" and visible_context and
                direct_member):
                balance = stripped.count("(") - stripped.count(")")
                body_opening = False
                if balance <= 0 and not line.lexical_continuation:
                    canonical = _canonical_parts([line.raw])
                    body_opening = _structural_body_opening(canonical) is not None
                if (not body_opening and not stripped.endswith(";") and
                    (balance > 0 or line.lexical_continuation or
                        _declaration_continues(
                            lines, index, [line.raw], "signature", scope))):
                    pending_declaration = PendingDeclaration(
                        owner, "", [line.raw], balance, "signature", scope,
                        list(pending_annotations))
                else:
                    _append_declaration(declarations, relative, package, owner, line.raw,
                        annotations=pending_annotations, scope=scope)
                pending_annotations.clear()
            elif (scope is not None and direct_member and scope.externally_subclassable and
                head is not None and head.visibility == "protected"):
                balance = stripped.count("(") - stripped.count(")")
                body_opening = False
                if balance <= 0 and not line.lexical_continuation:
                    canonical = _canonical_parts([line.raw])
                    body_opening = _structural_body_opening(canonical) is not None
                if (not body_opening and not stripped.endswith(";") and
                    (balance > 0 or line.lexical_continuation or
                        _declaration_continues(
                            lines, index, [line.raw], "signature", scope))):
                    pending_declaration = PendingDeclaration(
                        owner, "", [line.raw], balance, "signature", scope,
                        list(pending_annotations))
                else:
                    _append_declaration(declarations, relative, package, owner, line.raw,
                        annotations=pending_annotations, scope=scope)
                pending_annotations.clear()
            elif (scope is not None and direct_member and scope.kind == "interface" and
                scope.effective_public and head is not None and head.visibility is None and
                head.kind in CALLABLE_KINDS | {"type-alias", "field"}):
                balance = stripped.count("(") - stripped.count(")")
                if (line.brace_openings == 0 and not stripped.endswith(";") and
                    (balance > 0 or line.lexical_continuation or
                        _declaration_continues(
                            lines, index, [line.raw], "signature", scope))):
                    pending_declaration = PendingDeclaration(
                        owner, "interface-member ", [line.raw], balance, "signature", scope,
                        list(pending_annotations))
                else:
                    _append_declaration(declarations, relative, package, owner, line.raw,
                        prefix="interface-member ", annotations=pending_annotations, scope=scope)
                pending_annotations.clear()
            elif (scope is not None and direct_member and scope.kind == "enum" and
                scope.effective_public and stripped.startswith("|")):
                balance = stripped.count("(") - stripped.count(")")
                if (balance > 0 or _declaration_continues(
                    lines, index, [line.raw], "enum", scope)):
                    pending_declaration = PendingDeclaration(
                        owner, "enum-variant ", [line.raw], balance, "enum", scope,
                        list(pending_annotations))
                else:
                    _append_declaration(declarations, relative, package, owner, line.raw,
                        prefix="enum-variant ", annotations=pending_annotations, scope=scope)
                pending_annotations.clear()
            elif head is not None:
                pending_annotations.clear()
            elif pending_annotations:
                raise ValueError(f"{relative}: annotation target cannot be normalized: {stripped!r}")
            elif direct_member and visible_context and re.search(r"\bpublic\b", stripped):
                raise ValueError(f"{relative}: visible declaration cannot be normalized: {stripped!r}")
            elif (scope is not None and direct_member and scope.externally_subclassable and
                re.search(r"\bprotected\b", stripped)):
                raise ValueError(f"{relative}: protected declaration cannot be normalized: {stripped!r}")
            brace_depth = _advance_scopes(type_scopes, brace_depth, line)
        if pending_scope is not None:
            raise ValueError(f"{relative}: type or extend header has no structural body opener")
        if pending_declaration is not None:
            raise ValueError(f"{relative}: unterminated public API declaration")
        if annotation_parts is not None or pending_annotations:
            raise ValueError(f"{relative}: annotation has no declaration target")
    return sorted(declarations)


def _comparison_key(record: str) -> str:
    prefix = RECORD_PREFIX.match(record)
    if prefix is None:
        return record
    tail = record[prefix.end():]
    owner_match = OWNER_PREFIX.match(tail)
    owner_prefix = ""
    if owner_match is not None:
        owner_prefix = "owner=" + _canonical_owner_identity(owner_match.group("owner")) + ":"
    declaration = _record_declaration(record)
    canonical_declaration = _canonical_parts([declaration])
    identity = (f"package={_canonical_package_name(prefix.group('package'))}:" +
        owner_prefix + canonical_declaration)
    owner_name: str | None = None
    if owner_match is not None:
        last_owner = owner_match.group("owner").split(">")[-1]
        kind, encoded = last_owner.split("/", 1)
        if kind == "class":
            owner_name = _nfc_identifier(unquote_to_bytes(encoded).decode("utf-8"))
    try:
        head = _declaration_head(canonical_declaration, owner_name)
    except (UnicodeDecodeError, ValueError):
        return identity
    if head is None or head.kind not in ("init", "named-constructor"):
        return identity
    declaration = canonical_declaration
    line, state = _lex_line(declaration, LexicalState())
    if _lexically_open(state):
        return identity
    opening = line.code.find("(", head.keyword_end)
    if opening < 0:
        return identity
    try:
        closing = _matching_delimiter(line.code, opening, "(", ")")
        body_opening = _structural_body_opening(declaration, owner_name)
    except ValueError:
        return identity
    if closing is None or body_opening is None or body_opening <= closing:
        return identity
    tail = line.code[body_opening:].strip()
    if tail not in ("{", "{}"):
        return identity
    declaration_prefix = identity[:-len(declaration)]
    return declaration_prefix + declaration[:body_opening + 1].rstrip()


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
        declaration = record[prefix.end():]
        if declaration.startswith("owner="):
            owner = OWNER_PREFIX.match(declaration)
            if (owner is None or owner.end() == len(declaration) or
                not _valid_owner(owner.group("owner"))):
                raise ValueError(f"{source}: invalid API owner: {record!r}")
    if records != sorted(records):
        raise ValueError(f"{source}: API records are not sorted")
    if len(records) != len(set(records)):
        raise ValueError(f"{source}: duplicate raw API record (canonical collision)")
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
    for line in difflib.unified_diff(expected, current, fromfile="api/public-api-v0.10.txt", tofile="current API",
        lineterm=""):
        print(line, file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    try:
        declarations = normalized_declarations()
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
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
        print("public API differs from api/public-api-v0.10.txt", file=sys.stderr)
        _print_raw_diff(expected_records, current_records)
        return 1
    print(f"public API snapshot verified: {len(declarations)} declarations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
