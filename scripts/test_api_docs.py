#!/usr/bin/env python3
"""Regression cases for false-positive documentation publication gates."""

from __future__ import annotations

import argparse
from contextlib import nullcontext, redirect_stderr, redirect_stdout
from copy import deepcopy
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

import check_api_docs as checker
import generate_api_docs as generator


def declaration(identity: str, kind: str, header: str, *, owner: str | None = None) -> dict:
    name = "Sample" if kind == "class" else "parse"
    return {"id": identity, "name": name, "kind": kind, "qualifiedName": "probe." + name,
            "packageName": "probe", "ownerId": owner, "visibility": "public",
            "source": {"path": "src/probe.cj"}, "sourceApiSignature": {"state": "available"},
            "headerSpelling": header, "parameters": [], "returnType": None,
            "documentation": {"summary": "保存解析结果与输入之间的关联。", "tags": []}}


def fixture(output: Path) -> tuple[dict, Path]:
    output.mkdir()
    sample = declaration("sample", "class", "public class Sample")
    parse = declaration("parse", "function", "public func parse(source: String): String")
    parse["parameters"] = [{"name": "source", "documentation": "待解析的 UTF-8 文本。"}]
    parse["returnType"] = {"spelling": "String"}
    parse["documentation"]["tags"] = [{"name": "return", "description": "转义后的安全 HTML 文本。"}]
    document = {"schemaVersion": "cjdoc.doc-ir/16", "generator": {"version": "0.7.3"},
                "status": "complete", "apiCollectionState": "resolved",
                "configuration": {"audience": "external"}, "declarations": [sample, parse], "diagnostics": []}
    snapshot = output.parent / "api.txt"
    snapshot.write_text("# markdown public API snapshot\n"
                        "probe.cj:package=probe:public class Sample {\n"
                        "probe.cj:package=probe:public func parse(source: String): String {\n", encoding="utf-8")
    write_json(output / "docs.json", document)
    write_json(output / "coverage" / "quality.json", {
        "schemaVersion": "cjdoc.documentation-quality/1", "audience": "external",
        "symbols": {"total": 2, "meaningful": 2, "percent": 100},
        "parameters": {"total": 1, "meaningful": 1, "percent": 100}, "findings": []})
    write_json(output / "coverage" / "coverage.json", {
        "schemaVersion": "cjdoc.documentation-coverage/2", "audience": "external",
        "metrics": {"symbols": {"total": 2, "documented": 2, "percent": 100}}})
    write_json(output / "html" / "navigation-index.json", {
        "schemaVersion": "cjdoc.navigation-index/1", "project": {"audience": "external"},
        "pages": [{"href": "Sample.html", "symbolId": "sample"}, {"href": "parse.html", "symbolId": "parse"}]})
    (output / "html" / "index.html").write_text('<a href="parse.html#contract">parse</a>', encoding="utf-8")
    (output / "html" / "Sample.html").write_text('<a href="index.html">index</a>', encoding="utf-8")
    (output / "html" / "parse.html").write_text('<main id="contract">contract</main>', encoding="utf-8")
    write_json(output / checker.MARKER, {"generator": "markdown-api-docs/1", "examplesChecked": True})
    return document, snapshot


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


class PublicationGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name) / "site"
        self.document, self.snapshot = fixture(self.output)

    def update_document(self) -> None:
        write_json(self.output / "docs.json", self.document)

    def test_complete_site_has_exact_inventory(self) -> None:
        result = checker.validate(self.output, self.snapshot, require_examples=True)
        self.assertEqual(result, {"symbols": 2, "parameters": 1, "returns": 1, "snapshot": 2, "pages": 3})

    def test_contract_can_be_checked_without_html(self) -> None:
        shutil.rmtree(self.output / "html")
        self.assertEqual(checker.validate_contract(self.output, self.snapshot, require_examples=True)["snapshot"], 2)
        with self.assertRaisesRegex(ValueError, "HTML index is missing"):
            checker.validate(self.output, self.snapshot)

    def test_empty_hundred_percent_is_not_documentation(self) -> None:
        with self.assertRaisesRegex(ValueError, "zero declaration denominator"):
            checker.check_documentation({}, [], {"symbols": {"total": 0, "meaningful": 0, "percent": 100}})

    def test_resource_fallback_rejected_even_with_success_status(self) -> None:
        self.document["diagnostics"] = [{"code": "CJDOC3027", "severity": "warning", "message": "fallback"}]
        self.update_document()
        with self.assertRaisesRegex(ValueError, "CJDOC3027"):
            checker.validate(self.output, self.snapshot)

    def test_source_semantic_uncertainty_does_not_imply_missing_api(self) -> None:
        # Source mode is expected to lack canonical type resolution. Root API
        # collection completeness and raw source signatures are separate proof.
        self.document["declarations"][1]["semantic"] = {"state": "partial"}
        self.update_document()
        checker.validate(self.output, self.snapshot)
        self.document["apiCollectionState"] = "partial"
        self.update_document()
        with self.assertRaisesRegex(ValueError, "partial/unavailable"):
            checker.validate(self.output, self.snapshot)

    def test_missing_snapshot_declaration_is_not_masked_by_coverage(self) -> None:
        self.document["declarations"].pop()
        self.update_document()
        with self.assertRaisesRegex(ValueError, "0 visible matches.*parse"):
            checker.validate(self.output, self.snapshot)

    def test_default_and_overload_identity_are_checked(self) -> None:
        self.document["declarations"][1]["headerSpelling"] = 'public func parse(source: String = "default"): String'
        self.update_document()
        with self.assertRaisesRegex(ValueError, "0 visible matches.*parse"):
            checker.validate(self.output, self.snapshot)

    def test_missing_navigation_symbol_is_rejected(self) -> None:
        nav = checker.read_json(self.output / "html" / "navigation-index.json")
        nav["pages"].pop()
        write_json(self.output / "html" / "navigation-index.json", nav)
        with self.assertRaisesRegex(ValueError, "navigation declaration inventory differs"):
            checker.validate(self.output, self.snapshot)

    def test_broken_href_and_anchor_are_rejected(self) -> None:
        for href in ("missing.html", "parse.html#absent", "/parse.html", "../outside.html"):
            with self.subTest(href=href):
                (self.output / "html" / "index.html").write_text(f'<a href="{href}">link</a>', encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "site links failed"):
                    checker.validate(self.output, self.snapshot)

    def test_meaningful_parameters_and_returns_required_independently(self) -> None:
        original = deepcopy(self.document)
        self.document["declarations"][1]["parameters"][0]["documentation"] = "参数 source。"
        self.update_document()
        with self.assertRaisesRegex(ValueError, "meaningful parameter"):
            checker.validate(self.output, self.snapshot)
        self.document = original
        self.document["declarations"][1]["documentation"]["tags"][0]["description"] = "返回 String。"
        self.update_document()
        with self.assertRaisesRegex(ValueError, "meaningful return"):
            checker.validate(self.output, self.snapshot)

    def test_fields_describe_values_without_return_tag(self) -> None:
        item = declaration("field", "variable", "public let size: Int64")
        item["returnType"] = {"spelling": "Int64"}
        quality = {"schemaVersion": "cjdoc.documentation-quality/1", "audience": "external",
                   "symbols": {"total": 2, "meaningful": 2, "percent": 100},
                   "parameters": {"total": 1, "meaningful": 1, "percent": 100}, "findings": []}
        checker.check_documentation({}, [self.document["declarations"][1], item], quality)

    def test_internal_extend_exposes_public_members_of_visible_target(self) -> None:
        target = self.document["declarations"][0]
        extension = declaration("extend", "extend", "extend Sample")
        extension["visibility"] = "internal"
        extension["symbolRelationships"] = [{"kind": "extensionTarget", "targetSymbolId": target["id"]}]
        member = deepcopy(self.document["declarations"][1])
        member["ownerId"] = extension["id"]
        document = {"declarations": [target, extension, member]}
        self.assertEqual(len(checker.external_declarations(document)), 3)
        self.snapshot.write_text("# markdown public API snapshot\n"
                                 "probe.cj:package=probe:owner=extend/extend%20Sample%20%7B:"
                                 "public func parse(source: String): String {\n", encoding="utf-8")
        mapping = checker.snapshot_mapping(document, checker.external_declarations(document), self.snapshot)
        self.assertEqual(list(mapping.values()), ["parse"])
        target["visibility"] = "internal"
        self.assertEqual(checker.external_declarations(document), [])

    def test_explicit_unresolved_see_is_rejected(self) -> None:
        self.document["declarations"][1]["documentation"]["tags"].append(
            {"name": "see", "subject": "Missing", "referenceState": "unresolved", "targetSymbolId": None})
        self.update_document()
        with self.assertRaisesRegex(ValueError, "unresolved explicit @see"):
            checker.validate(self.output, self.snapshot)

    def test_preview_cannot_be_published(self) -> None:
        write_json(self.output / checker.MARKER, {"examplesChecked": False})
        with self.assertRaisesRegex(ValueError, "requires compiled/checked examples"):
            checker.validate(self.output, self.snapshot, require_examples=True)


class GeneratorSafetyTests(unittest.TestCase):
    def test_unowned_directory_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / "unrelated"
            output.mkdir()
            (output / "keep.txt").write_text("keep", encoding="utf-8")
            transaction = parent / "transaction"
            transaction.mkdir()
            staged = transaction / "site"
            staged.mkdir()
            with self.assertRaisesRegex(ValueError, "not owned"):
                generator.publish_directory(staged, output, transaction)
            self.assertEqual((output / "keep.txt").read_text(), "keep")

    @unittest.skipUnless(os.environ.get("CJDOC_TEST_BINARY"), "set CJDOC_TEST_BINARY to the pinned release executable")
    def test_release_binary_generates_data_then_versioned_html(self) -> None:
        # Exercise the real release CLI, not a mock command consumer: v0.7.3
        # rejects --doc-version unless the same invocation requests HTML.
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            project = parent / "project"
            (project / "src").mkdir(parents=True)
            (project / "api").mkdir()
            (project / "cjdoc.toml").write_text(
                (checker.ROOT / "cjdoc.toml").read_text(encoding="utf-8"), encoding="utf-8")
            (project / "cjpm.toml").write_text(
                '[package]\nname = "probe"\nversion = "0.0.1"\n'
                'cjc-version = "1.2.0"\noutput-type = "static"\n', encoding="utf-8")
            (project / "src" / "probe.cj").write_text(
                'package probe\n\n/** 保存输入文本的处理状态。 */\npublic class Sample {}\n\n'
                '/** 原样返回输入文本。\n * @param source 待返回的完整文本。\n'
                ' * @return 与输入内容相同的文本。\n */\n'
                'public func parse(source: String): String { source }\n', encoding="utf-8")
            (project / "api" / "public-api.txt").write_text(
                '# markdown public API snapshot\n'
                'probe.cj:package=probe:public class Sample {}\n'
                'probe.cj:package=probe:public func parse(source: String): String {\n', encoding="utf-8")
            output = parent / "documentation"
            args = argparse.Namespace(output=output, cjdoc=Path(os.environ["CJDOC_TEST_BINARY"]),
                                      revision=None, skip_examples=False)
            with (mock.patch.object(generator, "ROOT", project),
                  mock.patch.object(generator, "source_revision", return_value=None)):
                counts = generator.generate(args)
            self.assertEqual(counts["snapshot"], 2)
            self.assertTrue((output / "html" / "index.html").is_file())
            self.assertIn("0.0.1", (output / "html" / "version.json").read_text(encoding="utf-8"))
            self.assertTrue(checker.read_json(output / checker.MARKER)["examplesChecked"])

    def test_annotation_failure_retains_evidence_and_skips_render(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / "published"
            output.mkdir()
            (output / "keep.html").write_text("previous successful output", encoding="utf-8")
            write_json(output / checker.MARKER, {"generator": "markdown-api-docs/1"})
            calls = []

            def generated(command, *, environment, log):
                calls.append(command)
                staged = Path(command[command.index("--output") + 1])
                fixture(staged)
                shutil.rmtree(staged / "html")
                log.write_text("generated JSON and coverage\n", encoding="utf-8")

            args = argparse.Namespace(output=output, cjdoc=Path("offline-cjdoc"), revision=None, skip_examples=False)
            with (mock.patch.object(generator, "source_revision", return_value=None),
                  mock.patch.object(generator, "work_directory", return_value=nullcontext(parent)),
                  mock.patch.object(generator, "checked_binary", return_value=Path("offline-cjdoc")),
                  mock.patch.object(generator.subprocess, "check_output", return_value="btrfs\n"),
                  mock.patch.object(generator, "run_logged", side_effect=generated),
                  mock.patch.object(generator, "validate_contract", side_effect=ValueError("missing meaningful summary")),
                  redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO())):
                with self.assertRaisesRegex(ValueError, "missing meaningful summary"):
                    generator.generate(args)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][1], "generate")
            self.assertNotIn("html", calls[0])
            self.assertEqual(calls[0].count("--check-examples"), 1)
            self.assertEqual((output / "keep.html").read_text(), "previous successful output")
            evidence = list(parent.glob(".api-docs-*"))
            self.assertEqual(len(evidence), 1)
            self.assertTrue((evidence[0] / "site" / "docs.json").is_file())
            self.assertTrue((evidence[0] / "site" / "coverage" / "quality.json").is_file())
            self.assertTrue((evidence[0] / "generate.log").is_file())
            self.assertIn("Stage: documentation contract", (evidence[0] / "failure.txt").read_text())

    def test_success_renders_same_ir_without_rechecking_examples(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            output = parent / "published"
            calls = []

            def generated(command, *, environment, log):
                calls.append(command)
                destination = Path(command[command.index("--output") + 1])
                if command[1] == "generate":
                    fixture(destination)
                    shutil.rmtree(destination / "html")
                else:
                    self.assertEqual(command[1], "render")
                    self.assertEqual(Path(command[command.index("--input") + 1]),
                                     Path(calls[0][calls[0].index("--output") + 1]) / "docs.json")
                    (destination / "html").mkdir(parents=True)
                    (destination / "html" / "index.html").write_text("rendered", encoding="utf-8")
                log.write_text("completed\n", encoding="utf-8")

            args = argparse.Namespace(output=output, cjdoc=Path("offline-cjdoc"), revision=None, skip_examples=False)
            with (mock.patch.object(generator, "source_revision", return_value=None),
                  mock.patch.object(generator, "work_directory", return_value=nullcontext(parent)),
                  mock.patch.object(generator, "checked_binary", return_value=Path("offline-cjdoc")),
                  mock.patch.object(generator.subprocess, "check_output", return_value="btrfs\n"),
                  mock.patch.object(generator, "run_logged", side_effect=generated),
                  mock.patch.object(generator, "validate_contract", return_value={"symbols": 2}),
                  mock.patch.object(generator, "validate", return_value={"symbols": 2, "pages": 3}),
                  redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO())):
                self.assertEqual(generator.generate(args), {"symbols": 2, "pages": 3})
            self.assertEqual([command[1] for command in calls], ["generate", "render"])
            self.assertEqual(sum(command.count("--check-examples") for command in calls), 1)
            self.assertEqual((output / "html" / "index.html").read_text(), "rendered")
            self.assertTrue((output / "docs.json").is_file())
            self.assertEqual(list(parent.glob(".api-docs-*")), [])

    def test_binary_override_still_checks_release_checksum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "cjdoc"
            path.write_bytes(b"not the release executable")
            with mock.patch.object(generator.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "SHA-256 differs"):
                    generator.checked_binary(path, {})
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
