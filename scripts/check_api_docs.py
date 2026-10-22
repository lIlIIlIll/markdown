#!/usr/bin/env python3
"""Reject incomplete or undocumented cjdoc output before publishing it."""

from __future__ import annotations

import argparse
from collections import defaultdict
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

import check_public_api as public_api

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.7.3"
MARKER = ".markdown-api-docs.json"


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name}: expected a JSON object")
    return value


def canonical_header(value: str) -> str:
    # Reuse the snapshot's lexer so strings, defaults and generic brackets retain
    # their identity. Only a declaration's structural body opener is omitted.
    return public_api._canonical_parts([value]).removesuffix(" {}").removesuffix(" {").strip()


def external_declarations(document: dict) -> list[dict]:
    declarations = document["declarations"]
    by_id = {item["id"]: item for item in declarations}
    if len(by_id) != len(declarations):
        raise ValueError("duplicate declaration identity in Doc IR")
    memo: dict[str, bool] = {}

    def visible(item: dict, ancestors: frozenset[str] = frozenset()) -> bool:
        identity = item["id"]
        if identity in ancestors:
            raise ValueError("cyclic declaration ownership in Doc IR")
        if identity in memo:
            return memo[identity]
        if item["kind"] == "extend":
            targets = [relationship.get("targetSymbolId")
                       for relationship in item.get("symbolRelationships", [])
                       if relationship["kind"] == "extensionTarget"]
            if len(targets) != 1 or targets[0] not in by_id:
                raise ValueError(f"unresolved extension target: {item['qualifiedName']}")
            result = visible(by_id[targets[0]], ancestors | {identity})
        else:
            owner = item.get("ownerId")
            if owner and owner not in by_id:
                raise ValueError(f"missing owner: {item['qualifiedName']}")
            result = item["visibility"] in ("public", "protected") and (
                not owner or visible(by_id[owner], ancestors | {identity}))
        memo[identity] = result
        return result

    return [item for item in declarations if visible(item)]


def snapshot_mapping(document: dict, visible: list[dict], snapshot: Path) -> dict[str, str]:
    """Map every retained API record to exactly one visible source declaration."""
    records, _ = public_api._validated_records(snapshot.read_text(encoding="utf-8"), "API snapshot")
    if not records:
        raise ValueError("API snapshot has no declarations")
    declarations = {item["id"]: item for item in document["declarations"]}

    def owners(item: dict) -> str:
        if not item.get("ownerId"):
            return ""
        owner = declarations[item["ownerId"]]
        identity = (canonical_header(owner["headerSpelling"]) if owner["kind"] == "extend"
                    else owner["name"])
        return owners(owner) + ">" + owner["kind"] + "/" + identity

    index: dict[tuple[str, ...], list[str]] = defaultdict(list)
    for item in visible:
        if item.get("sourceApiSignature", {}).get("state") != "available":
            raise ValueError(f"unavailable source signature: {item['qualifiedName']}")
        source = item["source"]["path"]
        index[(source.removeprefix("src/"), item["packageName"], owners(item),
               canonical_header(item["headerSpelling"]))].append(item["id"])
    result = {}
    failures = []
    for record in records:
        prefix = public_api.RECORD_PREFIX.match(record)
        assert prefix is not None  # validated by the snapshot parser above
        tail = record[prefix.end():]
        owner_match = public_api.OWNER_PREFIX.match(tail)
        owner = ""
        if owner_match:
            for segment in owner_match["owner"].split(">"):
                kind, name = segment.split("/", 1)
                owner += ">" + kind + "/" + canonical_header(unquote(name))
            tail = tail[owner_match.end():]
        header = canonical_header(tail.removeprefix("enum-variant ").removeprefix("interface-member "))
        matches = index[(prefix["path"], prefix["package"], owner, header)]
        if len(matches) != 1:
            failures.append(f"{len(matches)} visible matches for {record}")
        else:
            result[record] = matches[0]
    if failures:
        raise ValueError("API snapshot mapping failed:\n" + "\n".join(failures))
    return result


def meaningful(value: str | None, name: str = "", type_name: str = "") -> bool:
    def compact(text: str) -> str:
        return re.sub(r"[\s`。．.:：]+", "", text).casefold()
    text = compact(value or "")
    if not text:
        return False
    name = compact(name)
    type_name = compact(type_name)
    placeholders = {"todo", "tbd", "待补充", "待完善", name, "参数" + name,
                    "parameter" + name, "返回" + type_name, "returns" + type_name,
                    "return" + type_name}
    return text not in placeholders


def check_documentation(document: dict, visible: list[dict], quality: dict) -> dict[str, int]:
    if not visible:
        raise ValueError("external API has a zero declaration denominator")
    failures = []
    parameters = 0
    returns = 0
    for item in visible:
        name = item["qualifiedName"]
        doc = item.get("documentation") or {}
        if not meaningful(doc.get("summary"), item["name"]):
            failures.append(f"missing meaningful summary: {name}")
        for parameter in item.get("parameters", []):
            if parameter["name"].startswith("_"):
                continue
            parameters += 1
            if not meaningful(parameter.get("documentation"), parameter["name"]):
                failures.append(f"missing meaningful parameter: {name}({parameter['name']})")
        tags = doc.get("tags", [])
        return_type = item.get("returnType")
        # Fields have returnType in cjdoc's model but describe a value, not a
        # call result. All current public properties are readable.
        if item["kind"] in ("function", "property") and return_type and return_type["spelling"] != "Unit":
            returns += 1
            return_docs = [tag.get("description") for tag in tags if tag["name"] == "return"]
            if len(return_docs) != 1 or not meaningful(return_docs[0], type_name=return_type["spelling"]):
                failures.append(f"missing meaningful return description: {name}")
        for tag in tags:
            if tag["name"] == "see" and (
                    tag.get("referenceState") != "resolved" or not tag.get("targetSymbolId")):
                failures.append(f"unresolved explicit @see: {name} -> {tag.get('subject', '')}")
    if quality.get("schemaVersion") != "cjdoc.documentation-quality/1" or quality.get("audience") != "external":
        failures.append("unexpected documentation quality schema/audience")
    for metric, expected in (("symbols", len(visible)), ("parameters", parameters)):
        count = quality.get(metric, {})
        if count.get("total") != expected or expected <= 0:
            failures.append(f"invalid {metric} denominator: expected {expected}, got {count.get('total')}")
        if count.get("meaningful") != expected or count.get("percent") != 100:
            failures.append(f"{metric} meaningful coverage must be 100% ({count.get('meaningful')}/{expected})")
    for finding in quality.get("findings", []):
        failures.append(f"documentation quality finding: {finding.get('code')} {finding.get('symbolId')}")
    if failures:
        raise ValueError("documentation contract failed:\n" + "\n".join(failures))
    return {"symbols": len(visible), "parameters": parameters, "returns": returns}


class PageLinks(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attributes: list[tuple[str, str | None]]) -> None:
        for key, value in attributes:
            if not value:
                continue
            if key == "id" or (tag == "a" and key == "name"):
                self.ids.add(value)
            if key in ("href", "src"):
                self.links.append(value)


def check_site(site: Path, visible_ids: set[str]) -> int:
    site = site.resolve()
    if not (site / "index.html").is_file():
        raise ValueError("generated HTML index is missing")
    index = read_json(site / "navigation-index.json")
    if index.get("schemaVersion") != "cjdoc.navigation-index/1" or index.get("project", {}).get("audience") != "external":
        raise ValueError("unexpected navigation index schema/audience")
    indexed_ids = [page["symbolId"] for page in index["pages"] if page.get("symbolId")]
    if len(indexed_ids) != len(set(indexed_ids)) or set(indexed_ids) != visible_ids:
        missing = visible_ids - set(indexed_ids)
        extra = set(indexed_ids) - visible_ids
        raise ValueError(f"navigation declaration inventory differs: {len(missing)} missing, {len(extra)} extra")
    pages: dict[Path, PageLinks] = {}
    for path in site.rglob("*.html"):
        page = PageLinks()
        page.feed(path.read_text(encoding="utf-8"))
        pages[path] = page
    links = [(site / "index.html", page["href"]) for page in index["pages"]]
    links.extend((path, link) for path, page in pages.items() for link in page.links)
    failures = []
    for origin, href in links:
        target = urlsplit(href)
        if target.scheme or target.netloc:
            if target.scheme not in ("http", "https", "mailto", "data"):
                failures.append(f"unexpected URL scheme: {href}")
            continue
        if target.path.startswith("/"):
            failures.append(f"site link must support /markdown/ subpath: {href}")
            continue
        destination = (origin.parent / unquote(target.path)).resolve() if target.path else origin
        if not destination.is_relative_to(site):
            failures.append(f"link escapes site: {href}")
        elif not destination.is_file():
            failures.append(f"broken site link: {origin.relative_to(site)} -> {href}")
        elif target.fragment and destination in pages and unquote(target.fragment) not in pages[destination].ids:
            failures.append(f"broken site anchor: {origin.relative_to(site)} -> {href}")
    if failures:
        raise ValueError("site links failed:\n" + "\n".join(sorted(set(failures))))
    return len(pages)


def validate_contract(output: Path, snapshot: Path, *, require_examples: bool = False) -> dict[str, int]:
    """Check the source/annotation proof before spending time rendering HTML."""
    document = read_json(output / "docs.json")
    if document.get("schemaVersion") != "cjdoc.doc-ir/16" or document.get("generator", {}).get("version") != VERSION:
        raise ValueError("Doc IR must be produced by the pinned cjdoc 0.7.3 release")
    if document.get("status") != "complete" or document.get("apiCollectionState") != "resolved":
        raise ValueError("Doc IR is partial/unavailable; complete resolved API collection is required")
    if document.get("configuration", {}).get("audience") != "external":
        raise ValueError("Doc IR audience must be external")
    diagnostics = document.get("diagnostics", [])
    # The optional highlighter may exhaust its budget while preserving code
    # text. Every other warning remains actionable rather than being silently
    # converted into a successful publication.
    bad = [d for d in diagnostics if d.get("code") != "CJDOC3028"
           and d.get("severity") in ("error", "warning")]
    if bad:
        raise ValueError("cjdoc failed: " + "; ".join(f"{d['code']}: {d['message']}" for d in bad))
    visible = external_declarations(document)
    mapped = snapshot_mapping(document, visible, snapshot)
    counts = check_documentation(document, visible, read_json(output / "coverage" / "quality.json"))
    coverage = read_json(output / "coverage" / "coverage.json")
    if coverage.get("schemaVersion") != "cjdoc.documentation-coverage/2" or coverage.get("audience") != "external":
        raise ValueError("unexpected coverage schema/audience")
    metric = coverage.get("metrics", {}).get("symbols", {})
    if metric.get("total") != len(visible) or metric.get("documented") != len(visible):
        raise ValueError("presence coverage declaration inventory differs from Doc IR")
    counts["snapshot"] = len(mapped)
    if require_examples:
        marker = read_json(output / MARKER)
        if marker.get("examplesChecked") is not True:
            raise ValueError("publication requires compiled/checked examples; omit --skip-examples")
    check_private_paths(output)
    return counts


def check_private_paths(output: Path) -> None:
    for path in output.rglob("*"):
        if path.is_file() and path.suffix in (".json", ".html", ".js", ".css", ".txt"):
            if re.search(r"(?:/home/|/Users/|[A-Za-z]:[\\/]Users[\\/])", path.read_text(encoding="utf-8")):
                raise ValueError(f"private local environment path in output: {path.relative_to(output)}")


def validate(output: Path, snapshot: Path, *, require_examples: bool = False) -> dict[str, int]:
    counts = validate_contract(output, snapshot, require_examples=require_examples)
    visible = external_declarations(read_json(output / "docs.json"))
    counts["pages"] = check_site(output / "html", {item["id"] for item in visible})
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "target" / "api-docs")
    parser.add_argument("--snapshot", type=Path, default=ROOT / "api" / "public-api.txt")
    parser.add_argument("--require-examples", action="store_true")
    parser.add_argument("--contract-only", action="store_true", help="validate JSON/coverage before HTML rendering")
    args = parser.parse_args()
    try:
        validator = validate_contract if args.contract_only else validate
        counts = validator(args.output, args.snapshot, require_examples=args.require_examples)
    except (OSError, ValueError, KeyError, TypeError, RecursionError) as error:
        print(f"API docs check failed: {error}", file=sys.stderr)
        return 1
    print("API docs verified: " + ", ".join(f"{value} {name}" for name, value in counts.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
