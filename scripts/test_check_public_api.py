#!/usr/bin/env python3
"""End-to-end regression tests for the public API snapshot checker."""

from __future__ import annotations

import ast
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import quote


HERE = Path(__file__).resolve().parent
CHECKER = HERE / "check_public_api.py"
RELEASE_GATE = HERE / "release_gate.sh"
HEADER = "# markdown public API snapshot v0.9"


class PublicApiCheckerCliTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        (self.root / "src").mkdir()
        (self.root / "api").mkdir()
        shutil.copy2(CHECKER, self.root / "scripts" / "check_public_api.py")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_checker(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "scripts/check_public_api.py", *arguments],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )

    def write_source(self, source: str, name: str = "sample.cj") -> None:
        (self.root / "src" / name).write_text(source, encoding="utf-8")

    def update_snapshot(self) -> str:
        result = self.run_checker("--update")
        self.assertEqual(result.returncode, 0, result.stderr)
        return (self.root / "api" / "public-api-v0.9.txt").read_text(encoding="utf-8")

    def write_snapshot(self, content: str) -> None:
        (self.root / "api" / "public-api-v0.9.txt").write_bytes(content.encode("utf-8"))

    def assert_snapshot_fails(self, content: str, message: str | None = None) -> subprocess.CompletedProcess[str]:
        self.write_snapshot(content)
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        if message is not None:
            self.assertIn(message, result.stderr)
        return result

    def load_checker_module(self):
        spec = importlib.util.spec_from_file_location("check_public_api_under_test", CHECKER)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module

    def test_constructor_markers_compare_equal_and_update_stays_raw(self) -> None:
        for declaration in (
            "public init() {",
            "public unsafe init() {",
            'public init<T>(value!: String = "(") where T <: Any {',
        ):
            with self.subTest(declaration=declaration):
                self.write_source(f"package sample\npublic class Sample {{\n    {declaration}\n    }}\n}}\n")
                raw = self.update_snapshot()
                raw_record = f"sample.cj:package=sample:owner=class/Sample:{declaration}"
                self.assertIn(raw_record + "\n", raw)
                self.assertNotIn(raw_record + "}\n", raw)

                equivalent = raw.replace(raw_record + "\n", raw_record + "}\n")
                self.write_snapshot(equivalent)
                verified = self.run_checker()
                self.assertEqual(verified.returncode, 0, verified.stderr)

                updated = self.run_checker("--update")
                self.assertEqual(updated.returncode, 0, updated.stderr)
                self.assertEqual((self.root / "api" / "public-api-v0.9.txt").read_text(encoding="utf-8"), raw)

    def test_real_constructor_signature_differences_fail_with_raw_diff(self) -> None:
        declaration = 'public init<T>(value: Int64, name!: String = "x") where T <: Any {'
        self.write_source(f"package sample\npublic class Sample {{\n    {declaration}\n    }}\n}}\n")
        raw = self.update_snapshot()
        record = f"sample.cj:package=sample:owner=class/Sample:{declaration}"
        variants = [
            record.replace("public init", "public unsafe init"),
            record.replace("<T>", "<U>"),
            record.replace("where T <: Any", "where T <: Object"),
            record.replace("value: Int64", "other: Int64"),
            record.replace("value: Int64", "value: String"),
            record.replace("value: Int64, name!: String", "name!: String, value: Int64"),
            record.replace('= "x"', '= "y"'),
            record.replace(") where", "): Unit where"),
        ]
        for variant in variants:
            with self.subTest(variant=variant):
                mutated = raw.replace(record, variant)
                mutated_records = sorted(mutated[:-1].split("\n")[1:])
                result = self.assert_snapshot_fails(
                    HEADER + "\n" + "\n".join(mutated_records) + "\n", "public API differs")
                self.assertIn("-" + variant, result.stderr)
                self.assertIn("+" + record, result.stderr)

        relocated = raw.replace("sample.cj:", "other.cj:")
        self.write_snapshot(relocated)
        location_only = self.run_checker()
        self.assertEqual(location_only.returncode, 0, location_only.stderr)

    def test_non_constructor_and_non_public_markers_are_not_normalized(self) -> None:
        cases = [
            ("public func value() {", "public func value() {}", "public func value() {", "public func value() {}"),
            ("public prop value: Int64 {", "public prop value: Int64 {}",
                "public prop value: Int64 {", "public prop value: Int64 {}"),
            ("public let value = { => 1 }", "public let value = { => 2 }", "=> 1", "=> 2"),
            ("public var value = { => 1 }", "public var value = { => 2 }", "=> 1", "=> 2"),
        ]
        for current, expected, snapshot_current, snapshot_expected in cases:
            with self.subTest(current=current):
                self.write_source(f"package sample\n{current}\n")
                raw = self.update_snapshot()
                self.assert_snapshot_fails(
                    raw.replace(snapshot_current, snapshot_expected), "public API differs")

        self.write_source("package sample\npublic class Sample {}\n")
        raw = self.update_snapshot()
        for record in (
            "sample.cj:package=sample:internal init() {}",
            "sample.cj:package=sample:public protected init() {}",
        ):
            with self.subTest(record=record):
                records = sorted(raw[:-1].split("\n")[1:] + [record])
                self.assert_snapshot_fails(HEADER + "\n" + "\n".join(records) + "\n", "public API differs")

    def test_closure_defaults_actual_bodies_comments_and_whitespace_are_not_markers(self) -> None:
        closure = "public init(callback!: () -> Unit = {})"
        self.write_source(f"package sample\n{closure}\n")
        raw = self.update_snapshot()
        self.assert_snapshot_fails(raw.replace("= {})", "= {)"), "public API differs")

        body = "public init() { value = 1 }"
        self.write_source(f"package sample\n{body}\n")
        raw = self.update_snapshot()
        self.assertIn("sample.cj:package=sample:public init() {\n", raw)
        self.assertNotIn("value = 1", raw)
        self.write_source("package sample\npublic init() { value = 99 }\n")
        verified = self.run_checker()
        self.assertEqual(verified.returncode, 0, verified.stderr)

        marker = "public init() {"
        self.write_source(f"package sample\n{marker}\n")
        raw = self.update_snapshot()
        self.write_snapshot(raw.replace(marker, "public init() {} // comment"))
        self.assertEqual(self.run_checker().returncode, 0)
        self.write_snapshot(raw.replace(marker + "\n", "public init() {} \n"))
        self.assertEqual(self.run_checker().returncode, 0)

    def test_structural_bodies_are_ignored_but_defaults_and_signatures_are_bound(self) -> None:
        source = (
            "package sample\n"
            "public let defaultHandler: () -> Int64 = { => 7 }\n"
            "public func topLevel(value: Int64, callback!: () -> Int64 = { => 7 }): Int64 "
            "{ value + callback() }\n"
            "public class Box {\n"
            "    let value: Int64\n"
            "    public init(value: Int64, callback!: () -> Int64 = { => 7 }) "
            "{ this.value = value + callback() }\n"
            "    public func exposed<T>(input: T): T where T <: Any { input }\n"
            "    public prop size: Int64 { get() { value } }\n"
            "}\n"
            "public struct Measure {\n"
            "    public func exposed(value: Int64): Int64 { value + 1 }\n"
            "}\n"
            "extend Box {\n"
            "    public func extended(value: Int64): Int64 { value + 1 }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public let defaultHandler: () -> Int64 = { => 7}",
            "sample.cj:package=sample:public func topLevel(value: Int64, callback!: () -> Int64 = { => 7}): Int64 {",
            "sample.cj:package=sample:owner=class/Box:public init(value: Int64, callback!: () -> Int64 = { => 7}) {",
            "sample.cj:package=sample:owner=class/Box:public func exposed<T>(input: T): T where T <: Any {",
            "sample.cj:package=sample:owner=class/Box:public prop size: Int64 {",
            "sample.cj:package=sample:owner=struct/Measure:public func exposed(value: Int64): Int64 {",
            "sample.cj:package=sample:owner=extend/extend%20Box%20%7B:public func extended(value: Int64): Int64 {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)
        for implementation in (
            "value + callback()",
            "this.value = value + callback()",
            "{ input }",
            "get() { value }",
            "{ value + 1 }",
        ):
            self.assertNotIn(implementation, raw)

        implementation_changes = (
            ("{ value + callback() }", "{ 99 }"),
            ("{ this.value = value + callback() }", "{ this.value = 99 }"),
            ("where T <: Any { input }", "where T <: Any { panic(\"changed\") }"),
            ("{ get() { value } }", "{ get() { 99 } }"),
            ("{ value + 1 }", "{ value + 99 }"),
        )
        for old, new in implementation_changes:
            with self.subTest(implementation=(old, new)):
                self.write_source(source.replace(old, new))
                result = self.run_checker()
                self.assertEqual(result.returncode, 0, result.stderr)

        signature_changes = (
            ("defaultHandler: () -> Int64 = { => 7 }", "defaultHandler: () -> Int64 = { => 8 }"),
            ("callback!: () -> Int64 = { => 7 }", "callback!: () -> Int64 = { => 8 }"),
            ("public init(value: Int64", "public init(value: String"),
            ("exposed<T>(input: T): T", "exposed<U>(input: U): U"),
            ("where T <: Any", "where T <: Object"),
            ("public prop size: Int64", "public prop size: String"),
            ("extended(value: Int64)", "extended(value: String)"),
        )
        for old, new in signature_changes:
            with self.subTest(signature=(old, new)):
                self.write_source(source.replace(old, new, 1))
                result = self.run_checker()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("public API differs", result.stderr)

    def test_package_type_aliases_bind_target_generics_multiline_and_visibility(self) -> None:
        source = (
            "package sample\n"
            "public type Number = Int64\n"
            "public type Pair<T> = (T, T)\n"
            "public type Nested<T> =\n"
            "    Array<\n"
            "        Array<T>\n"
            "    >\n"
            "public type\n"
            "SplitAlias<T>\n"
            "=\n"
            "Array<T>\n"
            "private type Hidden = String\n"
            "internal type InternalOnly = UInt64\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertIn("sample.cj:package=sample:public type Number = Int64\n", raw)
        self.assertIn("sample.cj:package=sample:public type Pair<T> = (T, T)\n", raw)
        self.assertIn("sample.cj:package=sample:public type Nested<T> = Array<Array<T> >\n", raw)
        self.assertIn("sample.cj:package=sample:public type SplitAlias<T> = Array<T>\n", raw)
        self.assertNotIn("Hidden", raw)
        self.assertNotIn("InternalOnly", raw)

        for old, new in (
            ("Number = Int64", "Number = String"),
            ("Pair<T>", "Pair<T, U>"),
            ("Array<T>", "Array<Int64>"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                result = self.run_checker()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("public API differs", result.stderr)

        # Cangjie 1.1.3 rejects type-alias where clauses. Keep a future-syntax
        # regression so a constraint line cannot be silently dropped if the
        # language later admits it.
        future = "package sample\npublic type Future<T> = Array<T>\n    where T <: Any\n"
        self.write_source(future)
        future_raw = self.update_snapshot()
        self.assertIn("sample.cj:package=sample:public type Future<T> = Array<T> where T <: Any\n", future_raw)
        self.write_source(future.replace("Any", "Object"))
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("public API differs", result.stderr)

    def test_protected_surface_is_bound_only_for_externally_subclassable_owners(self) -> None:
        source = (
            "package sample\n"
            "public open class OpenBase {\n"
            "    protected let seed: Int64\n"
            "    protected var counter: Int64\n"
            "    protected init(seed: Int64) { this.seed = seed; this.counter = seed }\n"
            "    protected open func hook<T>(value: T): T where T <: ToString { value }\n"
            "    protected func fallbackValue<T>(value: T, fallback!: () -> T = { => value }): T "
            "where T <: ToString { fallback() }\n"
            "    protected open operator func [](index: Int64): Int64 { seed + index }\n"
            "    protected open prop amount: Int64 { get() { counter } }\n"
            "    private func privateHelper(): Int64 { 1 }\n"
            "    internal func internalHelper(): Int64 { 1 }\n"
            "}\n"
            "public abstract class AbstractBase {\n"
            "    protected init() {}\n"
            "    protected func required(value: Int64): Int64\n"
            "}\n"
            "public class FinalBase {\n"
            "    protected func finalHelper(value: Int64): Int64 { value }\n"
            "    protected let finalField: Int64 = 1\n"
            "}\n"
            "public sealed abstract class SealedBase {\n"
            "    protected func sealedHelper(value: Int64): Int64\n"
            "}\n"
            "internal open class InternalBase {\n"
            "    protected open func internalHook(value: Int64): Int64 { value }\n"
            "}\n"
            "private open class PrivateBase {\n"
            "    protected open func privateHook(value: Int64): Int64 { value }\n"
            "}\n"
            "public open class OneLineOpen { protected open func oneLine(): Int64 { 1 }; "
            "protected let oneLineField: Int64 = 1; private func hidden(): Int64 { 1 } }\n"
            "public class OneLineFinal { protected func finalOneLine(): Int64 { 1 } }\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:owner=class/OpenBase:protected let seed: Int64",
            "sample.cj:package=sample:owner=class/OpenBase:protected var counter: Int64",
            "sample.cj:package=sample:owner=class/OpenBase:protected init(seed: Int64) {",
            "sample.cj:package=sample:owner=class/OpenBase:protected open func hook<T>(value: T): T where T <: ToString {",
            "sample.cj:package=sample:owner=class/OpenBase:protected func fallbackValue<T>(value: T, "
            "fallback!: () -> T = { => value}): T where T <: ToString {",
            "sample.cj:package=sample:owner=class/OpenBase:protected open operator func [](index: Int64): Int64 {",
            "sample.cj:package=sample:owner=class/OpenBase:protected open prop amount: Int64 {",
            "sample.cj:package=sample:owner=class/AbstractBase:protected init() {",
            "sample.cj:package=sample:owner=class/AbstractBase:protected func required(value: Int64): Int64",
            "sample.cj:package=sample:owner=class/OneLineOpen:protected open func oneLine(): Int64 {",
            "sample.cj:package=sample:owner=class/OneLineOpen:protected let oneLineField: Int64 = 1",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)
        for hidden in (
            "privateHelper", "internalHelper", "finalHelper", "finalField", "sealedHelper",
            "internalHook", "privateHook", "hidden", "finalOneLine",
        ):
            self.assertNotIn(hidden, raw)

        implementation_only = (source
            .replace("this.seed = seed; this.counter = seed", "this.seed = 99; this.counter = 99")
            .replace("where T <: ToString { value }", "where T <: ToString { panic(\"changed\") }", 1)
            .replace("where T <: ToString { fallback() }", "where T <: ToString { value }")
            .replace("{ seed + index }", "{ seed + index + 99 }")
            .replace("{ get() { counter } }", "{ get() { counter + 99 } }")
            .replace("oneLine(): Int64 { 1 }", "oneLine(): Int64 { 99 }")
        )
        self.write_source(implementation_only)
        unchanged = self.run_checker()
        self.assertEqual(unchanged.returncode, 0, unchanged.stderr)

        api_changes = (
            ("protected open func hook<T>", "protected func hook<T>"),
            ("hook<T>(value: T): T", "hook<T>(value: String): T"),
            ("fallback!: () -> T = { => value }", "fallback!: () -> T = { => panic(\"changed\") }"),
            ("fallbackValue<T>", "fallbackValue<U>"),
            ("where T <: ToString", "where T <: Any"),
            ("operator func [](index: Int64): Int64", "operator func [](index: UInt64): Int64"),
            ("prop amount: Int64", "prop amount: String"),
            ("protected let seed: Int64", "protected var seed: Int64"),
        )
        for old, new in api_changes:
            with self.subTest(api_change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

        self.write_source(source.replace(
            "    protected open func hook<T>(value: T): T where T <: ToString { value }\n", ""))
        deleted = self.run_checker()
        self.assertNotEqual(deleted.returncode, 0, deleted.stdout)
        self.assertIn("public API differs", deleted.stderr)
        self.assertIn("-sample.cj:package=sample:owner=class/OpenBase:protected open func hook", deleted.stderr)

    def test_const_apis_and_implicit_public_sealed_abstract_surface_are_bound(self) -> None:
        source = (
            "package sample\n"
            "public const func topLevel<T>(value: T): T where T <: ToString { value }\n"
            "public struct ConstBox {\n"
            "    public let value: Int64\n"
            "    public const init(value: Int64) { this.value = value }\n"
            "    public const func plus(delta: Int64): Int64 { value + delta }\n"
            "    public static const func twice(value: Int64): Int64 { value * 2 }\n"
            "}\n"
            "sealed abstract class ImplicitPublicBase {\n"
            "    public static func label(): String { \"sealed\" }\n"
            "    public func value(): Int64\n"
            "    protected func packageOnly(): Int64 { 1 }\n"
            "}\n"
            "class OrdinaryDefaultClass {\n"
            "    public func hiddenByOwner(): Int64 { 1 }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public const func topLevel<T>(value: T): T where T <: ToString {",
            "sample.cj:package=sample:owner=struct/ConstBox:public const init(value: Int64) {",
            "sample.cj:package=sample:owner=struct/ConstBox:public const func plus(delta: Int64): Int64 {",
            "sample.cj:package=sample:owner=struct/ConstBox:public static const func twice(value: Int64): Int64 {",
            "sample.cj:package=sample:sealed abstract class ImplicitPublicBase {",
            "sample.cj:package=sample:owner=class/ImplicitPublicBase:public static func label(): String {",
            "sample.cj:package=sample:owner=class/ImplicitPublicBase:public func value(): Int64",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)
        for hidden in ("packageOnly", "OrdinaryDefaultClass", "hiddenByOwner"):
            self.assertNotIn(hidden, raw)

        implementation_only = (source
            .replace("where T <: ToString { value }", "where T <: ToString { panic(\"changed\") }")
            .replace("this.value = value", "this.value = value + 1")
            .replace("{ value + delta }", "{ value + delta + 99 }")
            .replace("{ value * 2 }", "{ value * 99 }")
            .replace('{ "sealed" }', '{ "changed" }'))
        self.write_source(implementation_only)
        unchanged = self.run_checker()
        self.assertEqual(unchanged.returncode, 0, unchanged.stderr)

        api_changes = (
            ("public const func topLevel", "public func topLevel"),
            ("topLevel<T>(value: T): T", "topLevel<T>(value: String): T"),
            ("where T <: ToString", "where T <: Any"),
            ("public const init(value: Int64)", "public init(value: Int64)"),
            ("plus(delta: Int64)", "plus(delta: UInt64)"),
            ("public static const func twice", "public static func twice"),
            ("sealed abstract class", "public abstract class"),
            ("public func value(): Int64", "public func value(): String"),
        )
        for old, new in api_changes:
            with self.subTest(api_change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

        self.write_source(source.replace("    public const func plus(delta: Int64): Int64 { value + delta }\n", ""))
        deleted = self.run_checker()
        self.assertNotEqual(deleted.returncode, 0, deleted.stdout)
        self.assertIn("public API differs", deleted.stderr)

    def test_package_owner_identity_ignores_source_path_and_rejects_real_duplicates(self) -> None:
        source = (
            "package sample\n"
            "public class Box {\n"
            "    public func value(input: Int64): Int64 { input }\n"
            "}\n"
        )
        self.write_source(source, "a.cj")
        raw = self.update_snapshot()
        self.assertIn(
            "a.cj:package=sample:owner=class/Box:public func value(input: Int64): Int64 {\n",
            raw,
        )

        (self.root / "src" / "a.cj").unlink()
        self.write_source(source, "b.cj")
        moved = self.run_checker()
        self.assertEqual(moved.returncode, 0, moved.stderr)

        for changed_source in (
            source.replace("package sample", "package changed"),
            source.replace("class Box", "class Crate"),
            source.replace("input: Int64", "input: String"),
        ):
            with self.subTest(changed_source=changed_source):
                self.write_source(changed_source, "b.cj")
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)
                self.assertIn("-a.cj:package=sample:", changed.stderr)
                self.assertIn("+b.cj:package=", changed.stderr)

        self.write_source(source, "b.cj")
        self.write_source(source, "a.cj")
        duplicate = self.run_checker("--update")
        self.assertNotEqual(duplicate.returncode, 0, duplicate.stdout)
        self.assertIn("canonical collision", duplicate.stderr)

        self.write_source(source.replace("package sample", "package alpha"), "a.cj")
        self.write_source(source.replace("package sample", "package beta"), "b.cj")
        distinct_packages = self.run_checker("--update")
        self.assertEqual(distinct_packages.returncode, 0, distinct_packages.stderr)
        distinct_raw = (self.root / "api" / "public-api-v0.9.txt").read_text(encoding="utf-8")
        self.assertIn("a.cj:package=alpha:owner=class/Box:", distinct_raw)
        self.assertIn("b.cj:package=beta:owner=class/Box:", distinct_raw)

    def test_modifier_order_redef_and_visible_unknown_declarations_are_fail_closed(self) -> None:
        source = (
            "package sample\n"
            "public open class Parent {\n"
            "    protected open func overridden(value: Int64): Int64 { value }\n"
            "}\n"
            "public open class Service <: Parent {\n"
            "    static public func helper(): Int64 { 1 }\n"
            "    public redef static func create(): Int64 { 2 }\n"
            "    public const func stable(): Int64 { 3 }\n"
            "    public static const VALUE: Int64 = 4\n"
            "    const protected func hook(): Int64 { 5 }\n"
            "    override protected func overridden(value: Int64): Int64 { value + 1 }\n"
            "    static protected const SECRET: Int64 = 6\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        for declaration in (
            "static public func helper(): Int64 {",
            "public redef static func create(): Int64 {",
            "public const func stable(): Int64 {",
            "public static const VALUE: Int64 = 4",
            "const protected func hook(): Int64 {",
            "override protected func overridden(value: Int64): Int64 {",
            "static protected const SECRET: Int64 = 6",
        ):
            self.assertIn(
                "sample.cj:package=sample:owner=class/Service:" + declaration + "\n", raw)

        changed_implementation = source.replace("{ 1 }", "{ 99 }").replace("{ 5 }", "{ 88 }")
        self.write_source(changed_implementation)
        self.assertEqual(self.run_checker().returncode, 0)

        for old, new in (
            ("static public func helper", "public static func helper"),
            ("public redef static func create", "public static func create"),
            ("public const func stable", "public func stable"),
            ("public static const VALUE", "public const VALUE"),
            ("const protected func hook", "protected func hook"),
            ("override protected func overridden", "protected func overridden"),
            ("static protected const SECRET", "protected const SECRET"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                result = self.run_checker()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("public API differs", result.stderr)

        self.write_source("package sample\npublic synchronized func future(): Unit {}\n")
        failed_closed = self.run_checker("--update")
        self.assertNotEqual(failed_closed.returncode, 0, failed_closed.stdout)
        self.assertIn("visible declaration cannot be normalized", failed_closed.stderr)

        self.write_source(
            "package sample\npublic open class Guard {\n"
            "    protected synchronized func future(): Unit {}\n}\n")
        protected_failed_closed = self.run_checker("--update")
        self.assertNotEqual(protected_failed_closed.returncode, 0, protected_failed_closed.stdout)
        self.assertIn("protected declaration cannot be normalized", protected_failed_closed.stderr)

    def test_same_name_constructors_and_parameter_members_are_bound(self) -> None:
        source = (
            "package sample\n"
            "public open class Owner {\n"
            "    public Owner(public let label: String, protected var count: Int64) {\n"
            "        println(label)\n"
            "    }\n"
            "}\n"
            "public class Defaults {\n"
            "    public Defaults(value!: String = ####\"one\n"
            "two \"# \"## \"### // public class Ghost {}\n"
            "three\"####) { println(value) }\n"
            "}\n"
            "public class TripleDefault {\n"
            "    public TripleDefault(value!: String = \"\"\"\n"
            "        one\n"
            "        two ) { // public class TripleGhost {}\n"
            "        three\n"
            "        \"\"\") { println(value) }\n"
            "}\n"
            "public class EscapedDefault {\n"
            "    public EscapedDefault(value!: String = \"quoted \\\" ) { still literal\") "
            "{ println(value) }\n"
            "}\n"
            "public class Inline { public Inline(public let value: Int64) {} }\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        owner_constructor = (
            "sample.cj:package=sample:owner=class/Owner:"
            "public Owner(public let label: String, protected var count: Int64) {")
        self.assertIn(owner_constructor + "\n", raw)
        self.assertIn(
            "sample.cj:package=sample:owner=class/Owner:constructor-member public let label: String\n",
            raw,
        )
        self.assertIn(
            "sample.cj:package=sample:owner=class/Owner:constructor-member protected var count: Int64\n",
            raw,
        )
        self.assertIn(
            "sample.cj:package=sample:owner=class/Inline:constructor-member public let value: Int64\n",
            raw,
        )
        defaults_record = next(line for line in raw.splitlines() if ":public Defaults(" in line)
        self.assertIn("%0A", defaults_record)
        self.assertTrue(defaults_record.endswith(" {"), defaults_record)

        self.write_source(source.replace("println(label)", "println(count + 99)").replace(
            "{ println(value) }", "{ println(\"changed\") }"))
        implementation_only = self.run_checker()
        self.assertEqual(implementation_only.returncode, 0, implementation_only.stderr)

        for old, new in (
            ("public let label: String", "public var label: String"),
            ("protected var count: Int64", "protected var count: UInt64"),
            ("public let label: String, protected var count: Int64",
                "protected var count: Int64, public let label: String"),
            ("public let label: String, ", ""),
            ("one\ntwo", "one\nchanged"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

        self.write_source(source)
        equivalent = raw
        constructor_records = [
            line for line in raw.splitlines()
            if any(f":public {name}(" in line
                for name in ("Owner", "Defaults", "TripleDefault", "EscapedDefault", "Inline"))
        ]
        self.assertEqual(len(constructor_records), 5)
        for record in constructor_records:
            self.assertTrue(record.endswith(" {"), record)
            equivalent = equivalent.replace(record + "\n", record + "}\n")
        self.write_snapshot(equivalent)
        marker_equivalent = self.run_checker()
        self.assertEqual(marker_equivalent.returncode, 0, marker_equivalent.stderr)

    def test_annotations_literals_and_comment_trivia_are_bound_structurally(self) -> None:
        source = (
            "package sample\n"
            "@When[os != \"Windows\"]\n"
            "@Deprecated[message: #\"old // /* { public class Ghost {}\"#]\n"
            "public /* type comment */ open class Box<T> // class line comment\n"
            "    where T <: Any {\n"
            "    @Observable[value: ##\"line one\n"
            "line two \" // public class GhostTwo {}\n"
            "line three\"##]\n"
            "    public func value(input!: String = ####\"one\n"
            "two \"# \"## \"### /* public class GhostFour {} */\n"
            "three\"####): String /* signature comment */ { input }\n"
            "    public prop size: Int64 /* property comment */ { get() { 1 } }\n"
            "}\n"
            "@C\n"
            "public struct CLayout { public var value: Int64 = 0 }\n"
            "@When[os == \"Windows\"]\n"
            "private func hidden(): Int64 { 0 }\n"
            "public func real(): Int64 { 42 }\n"
            "extend /* target comment */ Box<Int64> {\n"
            "    public func extended(): Int64 /* body comment */ { 1 }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertIn(
            '@When[os != "Windows"] @Deprecated[message: #"old // /* { public class Ghost {}"#] '
            "public open class Box<T> where T <: Any {",
            raw,
        )
        observable = next(line for line in raw.splitlines() if "@Observable" in line)
        self.assertIn("%0A", observable)
        self.assertIn("####\"one%0Atwo", observable)
        self.assertIn("@C public struct CLayout {", raw)
        real_record = next(line for line in raw.splitlines() if ":public func real" in line)
        self.assertNotIn("@When", real_record)

        comments_changed = (source
            .replace("type comment", "a much longer type comment")
            .replace("class line comment", "changed class line comment text")
            .replace("signature comment", "changed signature comment text")
            .replace("property comment", "changed property comment text")
            .replace("target comment", "changed target comment text")
            .replace("body comment", "changed body comment text"))
        self.write_source(comments_changed)
        comments_are_trivia = self.run_checker()
        self.assertEqual(comments_are_trivia.returncode, 0, comments_are_trivia.stderr)

        comments_removed = (source
            .replace("/* type comment */ ", "")
            .replace(" // class line comment", "")
            .replace(" /* signature comment */", "")
            .replace(" /* property comment */", "")
            .replace("/* target comment */ ", "")
            .replace(" /* body comment */", ""))
        self.write_source(comments_removed)
        removed_comments_are_trivia = self.run_checker()
        self.assertEqual(removed_comments_are_trivia.returncode, 0, removed_comments_are_trivia.stderr)

        for old, new in (
            ('os != "Windows"', 'os != "Linux"'),
            ("line two \" // public class GhostTwo {}", "changed literal bytes"),
            ("three\"####): String", "changed\"####): String"),
            ("public func real(): Int64", "public func real(): String"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_interpolation_nested_literals_and_code_comments_have_distinct_identity(self) -> None:
        source = (
            "package sample\n"
            'public let nested: String = "${["/* api-v1 public class Ghost {} */"][0]}"\n'
            'public let nestedRaw: String = "${[##"api-v1 // public class RawGhost {}"##][0]}"\n'
            'public let nestedTriple: String = "${["""\n'
            "    api-v1 /* public class TripleGhost {} */\n"
            '    """][0]}"\n'
            'public let codeComment: String = "${1 /* interpolation comment v1 */ + 2}"\n'
        )
        self.write_source(source)
        raw = self.update_snapshot()
        records = raw.splitlines()[1:]
        self.assertEqual(len(records), 4)
        nested = next(record for record in records if ":public let nested:" in record)
        nested_raw = next(record for record in records if ":public let nestedRaw:" in record)
        nested_triple = next(record for record in records if ":public let nestedTriple:" in record)
        code_comment = next(record for record in records if ":public let codeComment:" in record)
        self.assertIn("api-v1 public class Ghost", nested)
        self.assertIn("api-v1 // public class RawGhost", nested_raw)
        self.assertIn("api-v1 /* public class TripleGhost", nested_triple)
        self.assertIn("%0A", nested_triple)
        self.assertNotIn("interpolation comment", code_comment)

        self.write_source(source.replace("interpolation comment v1", "a much longer comment v2"))
        comment_change = self.run_checker()
        self.assertEqual(comment_change.returncode, 0, comment_change.stderr)

        for old, new in (
            ("api-v1 public class Ghost", "api-v2 public class Ghost"),
            ("api-v1 // public class RawGhost", "api-v2 // public class RawGhost"),
            ("api-v1 /* public class TripleGhost", "api-v2 /* public class TripleGhost"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_same_line_and_multiline_annotations_bind_their_actual_target(self) -> None:
        source = (
            "package sample\n"
            '@Deprecated[message: "one"] public func first(): Int64 { 1 }\n'
            '@When[os != "Windows"] @Deprecated[message: #"two // public class Ghost {}"#] '
            "public func second(): Int64 { 2 }\n"
            "@Deprecated[\n"
            '    message: ##"line one\n'
            "line two // public class GhostTwo {}\n"
            'line three"##] public func third(): Int64 { 3 }\n'
            '@When[os == "Windows"] private func hidden(): Int64 { 0 }\n'
            "public func real(): Int64 { 4 }\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertEqual(sum("public func first" in line for line in raw.splitlines()), 1)
        self.assertEqual(sum("public func second" in line for line in raw.splitlines()), 1)
        self.assertEqual(sum("public func third" in line for line in raw.splitlines()), 1)
        self.assertIn('@Deprecated[message: "one"] public func first(): Int64 {', raw)
        self.assertIn(
            '@When[os != "Windows"] @Deprecated[message: #"two // public class Ghost {}"#] '
            "public func second(): Int64 {",
            raw,
        )
        third = next(line for line in raw.splitlines() if "public func third" in line)
        self.assertIn("@Deprecated[message: ##\"line one%0A", third)
        self.assertIn("line three\"##] public func third(): Int64 {", third)
        real = next(line for line in raw.splitlines() if ":public func real" in line)
        self.assertNotIn("@When", real)
        self.assertNotIn("hidden", raw)

        self.write_source(source.replace("{ 1 }", "{ 99 }").replace("{ 3 }", "{ 88 }"))
        implementation_only = self.run_checker()
        self.assertEqual(implementation_only.returncode, 0, implementation_only.stderr)

        for old, new in (
            ('message: "one"', 'message: "changed"'),
            ('os != "Windows"', 'os != "Linux"'),
            ("line two // public class GhostTwo {}", "changed annotation literal"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_constructor_parameter_splitting_distinguishes_comparisons_and_generics(self) -> None:
        source = (
            "package sample\n"
            "public class CompareDefault {\n"
            "    public CompareDefault(\n"
            "        enabled!: Bool = 1 < 2,\n"
            "        callback!: () -> Bool = { => 3 < 4 }\n"
            "    ) { println(enabled) }\n"
            "}\n"
            "public class GenericDefault {\n"
            "    public GenericDefault(\n"
            "        values!: HashMap<String, Array<Int64>> = HashMap<String, Array<Int64>>()\n"
            "    ) { println(values.size) }\n"
            "}\n"
            "public open class VisibleMembers {\n"
            "    public VisibleMembers(public let name: String, protected var count: Int64) {}\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        compare = next(line for line in raw.splitlines() if ":public CompareDefault(" in line)
        generic = next(line for line in raw.splitlines() if ":public GenericDefault(" in line)
        self.assertIn("enabled!: Bool = 1<2, callback!: () -> Bool = { => 3<4}", compare)
        self.assertIn(
            "HashMap<String, Array<Int64> > = HashMap<String, Array<Int64> >()", generic)
        self.assertIn(
            "owner=class/VisibleMembers:constructor-member public let name: String", raw)
        self.assertIn(
            "owner=class/VisibleMembers:constructor-member protected var count: Int64", raw)

        self.write_source(source.replace("println(enabled)", "println(false)").replace(
            "println(values.size)", "println(99)"))
        implementation_only = self.run_checker()
        self.assertEqual(implementation_only.returncode, 0, implementation_only.stderr)

        for old, new in (
            ("1 < 2", "1 < 3"),
            ("3 < 4", "3 < 5"),
            ("HashMap<String, Array<Int64>>", "HashMap<String, Array<UInt64>>"),
            ("HashMap<String, Array<Int64>>()", "HashMap<String, Array<UInt64>>()"),
            ("public let name: String", "public var name: String"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_same_line_declarations_split_only_at_direct_structural_boundaries(self) -> None:
        source = (
            "package sample\n"
            "public import std.collection.{ArrayList, HashMap}; public type Number = Int64\n"
            "public type Numbers =\n"
            "    Array<\n"
            "        Int64>; public func afterAlias(): Int64 { 8 }\n"
            "private func hidden(): Unit {}; public func leaked(): Unit {}\n"
            "public func first(): Int64 { let inner = 1; inner }; "
            "public func second(): Int64 { 2 }\n"
            "@Deprecated[message: \"old\"] public func annotated(): Int64 { 3 }; "
            "public func afterAnnotation(): Int64 { 4 }\n"
            "@Deprecated[\n"
            "    message: \"multi\"\n"
            "] public func multiAnnotated(): Int64 { 9 }; "
            "public func afterMultiAnnotation(): Int64 { 10 }\n"
            "public let closure: () -> Int64 = { => let value = 1; value + 1 }; "
            "public func afterClosure(): Int64 { closure() }\n"
            "public let nested: String = \"${[\"; public func Ghost(): Unit {}\"][0]}\"; "
            "public func afterString(): Int64 { 5 }\n"
            "public let raw: String = ##\"one; public func RawGhost(): Unit {}\n"
            "two \\\" /* comment */ { }\n"
            "three\"##; /* separator comment */ public func afterRaw(): Int64 { 11 }\n"
            "public class Empty {}; public func afterType(): Int64 { 6 }\n"
            "public class Box {\n"
            "    public init() {}\n"
            "    private func hiddenMember(): Unit {}; "
            "public func leakedMember(): Int64 { 7 }\n"
            "    public func memberFirst(): Int64 { let inner = 1; inner }; "
            "public func memberSecond(): Int64 { 2 }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public import std.collection.{ArrayList, HashMap};",
            "sample.cj:package=sample:public type Number = Int64",
            "sample.cj:package=sample:public type Numbers = Array<Int64>;",
            "sample.cj:package=sample:public func afterAlias(): Int64 {",
            "sample.cj:package=sample:public func leaked(): Unit {",
            "sample.cj:package=sample:public func first(): Int64 {",
            "sample.cj:package=sample:public func second(): Int64 {",
            "sample.cj:package=sample:@Deprecated[message: \"old\"] public func annotated(): Int64 {",
            "sample.cj:package=sample:public func afterAnnotation(): Int64 {",
            "sample.cj:package=sample:@Deprecated[message: \"multi\"] "
                "public func multiAnnotated(): Int64 {",
            "sample.cj:package=sample:public func afterMultiAnnotation(): Int64 {",
            "sample.cj:package=sample:public let closure: () -> Int64 = { => let value = 1; value + 1};",
            "sample.cj:package=sample:public func afterClosure(): Int64 {",
            "sample.cj:package=sample:public let nested: String = "
                "\"${[\"; public func Ghost(): Unit {}\"][0]}\";",
            "sample.cj:package=sample:public func afterString(): Int64 {",
            "sample.cj:package=sample:public func afterRaw(): Int64 {",
            "sample.cj:package=sample:public class Empty {",
            "sample.cj:package=sample:public func afterType(): Int64 {",
            "sample.cj:package=sample:owner=class/Box:public func leakedMember(): Int64 {",
            "sample.cj:package=sample:owner=class/Box:public func memberFirst(): Int64 {",
            "sample.cj:package=sample:owner=class/Box:public func memberSecond(): Int64 {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)
        self.assertNotIn("hidden(): Unit", raw)
        self.assertNotIn("hiddenMember", raw)
        self.assertNotIn("owner=class/Ghost", raw)
        self.assertNotIn("owner=class/RawGhost", raw)
        self.assertNotIn("let inner = 1", raw)
        raw_literal = next(record for record in raw.splitlines() if ":public let raw:" in record)
        self.assertIn("%0A", raw_literal)
        self.assertTrue(raw_literal.endswith(";"), raw_literal)

        for old, new in (
            ("hidden(): Unit {}", "hidden(value: Int64): Unit { let local = value; }"),
            ("hiddenMember(): Unit {}", "hiddenMember(value: Int64): Unit { let local = value; }"),
            ("first(): Int64 { let inner = 1; inner }", "first(): Int64 { 99 }"),
            ("leakedMember(): Int64 { 7 }", "leakedMember(): Int64 { 99 }"),
            ("separator comment", "a much longer separator comment"),
        ):
            with self.subTest(non_api_change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                unchanged = self.run_checker()
                self.assertEqual(unchanged.returncode, 0, unchanged.stderr)

        for old, new in (
            ("public func leaked(): Unit {}", ""),
            ("public func leakedMember(): Int64 { 7 }", ""),
            ("public func second(): Int64", "public func second(value: Int64): Int64"),
            ("public func afterRaw(): Int64", "public func afterRaw(): String"),
            ("public type Number = Int64", "public type Number = String"),
        ):
            with self.subTest(api_change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

        self.write_source(
            "package sample\n"
            "private func hidden(): Unit {} public func leaked(): Unit {}\n"
        )
        unsafe_remainder = self.run_checker("--update")
        self.assertNotEqual(unsafe_remainder.returncode, 0, unsafe_remainder.stdout)
        self.assertIn("no safe structural separator", unsafe_remainder.stderr)

    def test_declaration_continuation_is_structural_and_indentation_is_trivia(self) -> None:
        source = (
            "package sample\n"
            "public type Number = Int64\n"
            "        private func hidden(): Unit {}\n"
            "            public func afterAlias(): Int64 { 1 }\n"
            "public let first: Int64 = 1\n"
            "                public let second: Int64 = 2\n"
            "public import std.collection.{\n"
            "    ArrayList,\n"
            "    HashMap\n"
            "}\n"
            "@Deprecated[\n"
            "    message: \"old\"\n"
            "]\n"
            "public func annotated<T>(\n"
            "    value: T,\n"
            "    callback!: () -> T =\n"
            "        { => value }\n"
            ")\n"
            "    : T\n"
            "    where T <: Any\n"
            "{\n"
            "    callback()\n"
            "}\n"
            "public type Nested<T> =\n"
            "    Array<\n"
            "        T\n"
            "    >\n"
            "public class Box {\n"
            "    public prop size:\n"
            "        Int64\n"
            "    {\n"
            "        get() { 1 }\n"
            "    }\n"
            "}\n"
            "public enum Result<T> {\n"
            "    | Value(\n"
            "        T,\n"
            "        Array<T>\n"
            "    )\n"
            "    | Empty\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public type Number = Int64",
            "sample.cj:package=sample:public func afterAlias(): Int64 {",
            "sample.cj:package=sample:public let first: Int64 = 1",
            "sample.cj:package=sample:public let second: Int64 = 2",
            "sample.cj:package=sample:public import std.collection.{ArrayList, HashMap}",
            "sample.cj:package=sample:@Deprecated[message: \"old\"] "
                "public func annotated<T>(value: T, callback!: () -> T = { => value}): T where T <: Any {",
            "sample.cj:package=sample:public type Nested<T> = Array<T>",
            "sample.cj:package=sample:owner=class/Box:public prop size: Int64 {",
            "sample.cj:package=sample:owner=enum/Result:enum-variant | Value(T, Array<T>)",
            "sample.cj:package=sample:owner=enum/Result:enum-variant | Empty",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)
        self.assertNotIn("hidden", raw)

        formatting_only = (source
            .replace("            public func afterAlias", " public func afterAlias")
            .replace("                public let second", "  public let second")
            .replace("    where T <: Any\n{", "where T <: Any {"))
        self.write_source(formatting_only)
        formatted = self.run_checker()
        self.assertEqual(formatted.returncode, 0, formatted.stderr)

        self.write_source(source.replace("hidden(): Unit {}", "hidden(value: Int64): Unit { }"))
        private_change = self.run_checker()
        self.assertEqual(private_change.returncode, 0, private_change.stderr)

        for old, new in (
            ("public func afterAlias(): Int64 { 1 }", ""),
            ("public let second: Int64 = 2", "public let second: String = \"two\""),
            ("where T <: Any", "where T <: Object"),
            ("public prop size:", "public prop length:"),
            ("Array<T>", "Array<Int64>"),
        ):
            with self.subTest(api_change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_package_prefix_can_share_a_line_with_a_public_declaration(self) -> None:
        source = (
            "/* package comment.fake */\n"
            "let fake = \"package literal.fake\"\n"
            "package sample; public let exposed: Int64 = 1\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertEqual(
            raw,
            HEADER + "\nsample.cj:package=sample:public let exposed: Int64 = 1\n",
        )

        self.write_source(source.replace("package sample;", "package sample /* trivia */ ;"))
        trivia = self.run_checker()
        self.assertEqual(trivia.returncode, 0, trivia.stderr)

        self.write_source(source.replace("exposed: Int64", "exposed: String"))
        changed = self.run_checker()
        self.assertNotEqual(changed.returncode, 0, changed.stdout)
        self.assertIn("public API differs", changed.stderr)

        for invalid, message in (
            ("public let exposed: Int64 = 1\n", "exactly one canonical package"),
            ("package first; package second; public let exposed: Int64 = 1\n",
                "exactly one canonical package"),
            ("package sample; totally invalid\n", "invalid declaration after package"),
            ("package sample; \"literal tail\"\n", "invalid declaration after package"),
        ):
            with self.subTest(invalid=invalid):
                self.write_source(invalid)
                rejected = self.run_checker("--update")
                self.assertNotEqual(rejected.returncode, 0, rejected.stdout)
                self.assertIn(message, rejected.stderr)

    def test_multiline_public_import_binds_the_complete_path(self) -> None:
        source = (
            "package sample\n"
            "public import std.collection.\n"
            "    ArrayList\n"
            "public import std.collection\n"
            "    .HashMap\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertIn(
            "sample.cj:package=sample:public import std.collection.ArrayList\n", raw)
        self.assertIn(
            "sample.cj:package=sample:public import std.collection.HashMap\n", raw)

        self.write_source(
            "package sample\n"
            "public import std.collection.ArrayList\n"
            "public import std.collection.HashMap\n"
        )
        formatting = self.run_checker()
        self.assertEqual(formatting.returncode, 0, formatting.stderr)

        for changed_source in (
            source.replace("ArrayList", "LinkedList", 1),
            source.replace("public import std.collection\n    .HashMap\n", ""),
        ):
            with self.subTest(changed_source=changed_source):
                self.write_source(changed_source)
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_import_path_and_alias_continuations_are_complete(self) -> None:
        source = (
            "package sample\n"
            "public import\n"
            "    std.collection.ArrayList\n"
            "public import std.collection.HashMap\n"
            "    as Maps\n"
            "public func sibling(): Unit {}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public import std.collection.ArrayList",
            "sample.cj:package=sample:public import std.collection.HashMap as Maps",
            "sample.cj:package=sample:public func sibling(): Unit {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)

        self.write_source(
            "package sample\n"
            "public import std.collection.ArrayList\n"
            "public import std.collection.HashMap as Maps\n"
            "public func sibling(): Unit {}\n"
        )
        one_line = self.run_checker()
        self.assertEqual(one_line.returncode, 0, one_line.stderr)

        for old, new in (
            ("std.collection.ArrayList", "std.collection.LinkedList"),
            ("as Maps", "as Lookup"),
            ("    as Maps\n", ""),
            ("public func sibling(): Unit {}\n", ""),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_wildcard_import_terminates_without_weakening_multiply_continuation(self) -> None:
        source = (
            "package sample\n"
            "public import std.collection.*\n"
            "public let product: Int64 = 2 *\n"
            "    3\n"
            "public func exported(): Int64 { product }\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public import std.collection.*",
            "sample.cj:package=sample:public let product: Int64 = 2 * 3",
            "sample.cj:package=sample:public func exported(): Int64 {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)

        self.write_source(source.replace(
            "public import std.collection.*",
            "public import std.collection.\n    *",
            1,
        ))
        formatting = self.run_checker()
        self.assertEqual(formatting.returncode, 0, formatting.stderr)

        for changed_source in (
            source.replace("std.collection.*", "std.core.*", 1),
            source.replace("public import std.collection.*\n", "", 1),
            source.replace("public func exported(): Int64 { product }\n", "", 1),
        ):
            with self.subTest(changed_source=changed_source):
                self.write_source(changed_source)
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_code_identity_is_token_canonical_and_preserves_operator_boundaries(self) -> None:
        compact = (
            "package sample\n"
            "public import std.collection.{ArrayList as Lists, HashMap}\n"
            "public type Values<T> = Array<T>\n"
            "public func exported(value: Int64): Int64 { value }\n"
            "public let shift: Int64 = 8 >> 1\n"
            "public let threshold: Bool = 8 >= 1\n"
        )
        self.write_source(compact)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public import std.collection.{ArrayList as Lists, HashMap}",
            "sample.cj:package=sample:public type Values<T> = Array<T>",
            "sample.cj:package=sample:public func exported(value: Int64): Int64 {",
            "sample.cj:package=sample:public let shift: Int64 = 8 >> 1",
            "sample.cj:package=sample:public let threshold: Bool = 8 >= 1",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)

        spaced = (
            "package sample\n"
            "public import std . collection . { ArrayList as Lists , HashMap }\n"
            "public type Values < T > = Array < T >\n"
            "public func exported ( value : Int64 ) : Int64 { value }\n"
            "public let shift : Int64 = 8 >> 1\n"
            "public let threshold : Bool = 8 >= 1\n"
        )
        self.write_source(spaced)
        formatting = self.run_checker()
        self.assertEqual(formatting.returncode, 0, formatting.stderr)

        comments = (spaced
            .replace("public import", "public/* visibility */ import", 1)
            .replace("std . collection", "std/* left */ . /* right */collection", 1)
            .replace("exported (", "exported/* call */(", 1)
            .replace("Values <", "Values/* generic */<", 1))
        self.write_source(comments)
        comment_trivia = self.run_checker()
        self.assertEqual(comment_trivia.returncode, 0, comment_trivia.stderr)

        for old, new in (
            ("Lists", "Sequence"),
            ("HashMap", "HashSet"),
            ("value: Int64", "value: String"),
            ("Values<T>", "Values<U>"),
            ("8 >> 1", "8 > > 1"),
            ("8 >= 1", "8 > = 1"),
            ("8 >= 1", "8 >/* boundary */= 1"),
            ("exported", "ex ported"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(compact.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)

    def test_cangjie_multichar_operators_use_longest_match_and_complete_rhs(self) -> None:
        # This exact source is compiled by the Round 19 SDK 1.1.3 probe.  The
        # closures are the grammar-valid contexts for &&=/||= and if-let is the
        # grammar-valid context for <-.
        source = (
            "package sample\n"
            "func double(value: Int64): Int64 { value * 2 }\n"
            "func increment(value: Int64): Int64 { value + 1 }\n"
            "public let mapped: Int64 = 1 |>\n"
            "    double\n"
            "public let composed: (Int64) -> Int64 = double ~>\n"
            "    increment\n"
            "public let values = 1 ..=\n"
            "    3\n"
            "public let updateAnd: () -> Bool = { =>\n"
            "    var value = true\n"
            "    value &&=\n"
            "        false\n"
            "    value\n"
            "}\n"
            "public let updateOr: () -> Bool = { =>\n"
            "    var value = false\n"
            "    value ||=\n"
            "        true\n"
            "    value\n"
            "}\n"
            "public let matched: Int64 = if (let Some(value) <-\n"
            "    Some(7)) { value } else { 0 }\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        records = raw.removeprefix(HEADER + "\n").strip().split("\n")
        self.assertEqual(len(records), 6)
        for fragment in (
            "public let mapped: Int64 = 1 |> double",
            "public let composed: (Int64) -> Int64 = double ~> increment",
            "public let values = 1 ..= 3",
            "value &&= false",
            "value ||= true",
            "Some(value) <- Some(7)",
        ):
            self.assertIn(fragment, raw)

        one_line = (source
            .replace("1 |>\n    double", "1 |> double")
            .replace("double ~>\n    increment", "double ~> increment")
            .replace("1 ..=\n    3", "1 ..= 3")
            .replace("value &&=\n        false", "value &&= false")
            .replace("value ||=\n        true", "value ||= true")
            .replace("Some(value) <-\n    Some(7)", "Some(value) <- Some(7)"))
        self.write_source(one_line)
        equivalent = self.run_checker()
        self.assertEqual(equivalent.returncode, 0, equivalent.stderr)

        for old, new in (
            ("1 |>\n    double", "1 |>\n    increment"),
            ("double ~>\n    increment", "double ~>\n    double"),
            ("1 ..=\n    3", "1 ..=\n    4"),
            ("value &&=\n        false", "value &&=\n        true"),
            ("value ||=\n        true", "value ||=\n        false"),
            ("Some(value) <-\n    Some(7)", "Some(value) <-\n    Some(8)"),
            ("1 |>\n", "1 | >\n"),
            ("1 ..=\n", "1 . .=\n"),
            ("value &&=\n", "value & &=\n"),
            ("value ||=\n", "value | |=\n"),
            ("Some(value) <-\n", "Some(value) < -\n"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)

        checker = self.load_checker_module()
        for compact, separated in (
            ("left...right", "left. ..right"),
            ("left!in right", "left! in right"),
            ("left@!right", "left@ !right"),
            ("left<-right", "left< -right"),
        ):
            with self.subTest(lexeme=(compact, separated)):
                self.assertNotEqual(
                    checker._canonical_parts([compact]),
                    checker._canonical_parts([separated]),
                )

    def test_identifier_identity_is_nfc_but_literal_bytes_are_not(self) -> None:
        composed = (
            "package pàckage.sample\n"
            "public class Càse {\n"
            "    public Càse() {}\n"
            "    public func vàlue(): Int64 { 1 }\n"
            "}\n"
            "public class `clàss` {\n"
            "    public func `vàlue`(): Int64 { 2 }\n"
            "}\n"
            "public let literal: String = \"à\"\n"
            "public let rawLiteral: String = #\"à\"#\n"
            "public let interpolated: String = \"à ${Càse().vàlue()}\"\n"
        )
        self.write_source(composed)
        raw = self.update_snapshot()
        self.assertIn("package=pàckage.sample:public class Càse {", raw)
        self.assertIn("owner=class/C%C3%A0se:public Càse() {", raw)
        self.assertIn("public func vàlue(): Int64 {", raw)
        self.assertIn("owner=class/%60cl%C3%A0ss%60:public func `vàlue`(): Int64 {", raw)

        decomposed = (composed
            .replace("pàckage", "pa\u0300ckage")
            .replace("Càse", "Ca\u0300se")
            .replace("vàlue", "va\u0300lue")
            .replace("clàss", "cla\u0300ss"))
        self.write_source(decomposed)
        equivalent = self.run_checker()
        self.assertEqual(equivalent.returncode, 0, equivalent.stderr)

        for changed_source in (
            composed.replace("vàlue", "válue"),
            decomposed.replace('literal: String = "à"', 'literal: String = "a\u0300"'),
            decomposed.replace('rawLiteral: String = #"à"#', 'rawLiteral: String = #"a\u0300"#'),
            decomposed.replace('interpolated: String = "à ${', 'interpolated: String = "a\u0300 ${'),
        ):
            with self.subTest(changed_source=changed_source):
                self.write_source(changed_source)
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)

    def test_numeric_tokens_separate_member_and_range_dots(self) -> None:
        # Both compact and spaced member access forms in this fixture compile
        # with the official 1.1.3 SDK.
        source = (
            "package sample\n"
            "public let text: String = 1.toString()\n"
            "public let fraction: Float64 = 1.0\n"
            "public let exponent: Float64 = 1.0e-2\n"
            "public let hexadecimal: Int64 = 0x7fi64\n"
            "public let binary: UInt8 = 0b1010u8\n"
            "public let suffixed: Float32 = 1.25f32\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertIn("public let text: String = 1 .toString()", raw)
        for number in ("1.0", "1.0e-2", "0x7fi64", "0b1010u8", "1.25f32"):
            self.assertIn(number, raw)

        self.write_source(source.replace("1.toString()", "1 . toString()"))
        spaced_member = self.run_checker()
        self.assertEqual(spaced_member.returncode, 0, spaced_member.stderr)

        for old, new in (
            ("toString", "hashCode"),
            ("1.toString", "2.toString"),
            ("1.0", "2.0"),
            ("1.0e-2", "1.0e-3"),
            ("0x7fi64", "0x7ei64"),
            ("0b1010u8", "0b1011u8"),
            ("1.25f32", "1.5f32"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)

        checker = self.load_checker_module()
        for compact, separated in (
            ("1..2", "1 . .2"),
            ("1...", "1 . .."),
            ("1.0", "1 . 0"),
            ("1e2", "1 e2"),
            ("0x7fi64", "0x7f i64"),
            ("0b1010u8", "0b1010 u8"),
            ("1.25f32", "1.25 f32"),
        ):
            with self.subTest(numeric_boundary=(compact, separated)):
                self.assertNotEqual(
                    checker._canonical_parts([compact]),
                    checker._canonical_parts([separated]),
                )

    def test_unicode_and_escaped_identifiers_bind_package_owner_and_members(self) -> None:
        source = (
            "package 样例.子包\n"
            "public class 类型 {\n"
            "    public 类型() {}\n"
            "    public func 值(): Int64 { 1 }\n"
            "}\n"
            "public struct 数据 {\n"
            "    public func 大小(): Int64 { 1 }\n"
            "}\n"
            "public interface 接口 {\n"
            "    func 读取(): Int64\n"
            "}\n"
            "public enum 结果 {\n"
            "    | 成功(Int64)\n"
            "    | 失败\n"
            "}\n"
            "public class `class` {\n"
            "    public func value(): Int64 { 1 }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        package = "sample.cj:package=样例.子包:"
        expected = (
            package + "public class 类型 {",
            package + "owner=class/" + quote("类型", safe="") + ":public 类型() {",
            package + "owner=class/" + quote("类型", safe="") + ":public func 值(): Int64 {",
            package + "public struct 数据 {",
            package + "owner=struct/" + quote("数据", safe="") + ":public func 大小(): Int64 {",
            package + "public interface 接口 {",
            package + "owner=interface/" + quote("接口", safe="") +
                ":interface-member func 读取(): Int64",
            package + "public enum 结果 {",
            package + "owner=enum/" + quote("结果", safe="") + ":enum-variant | 成功(Int64)",
            package + "owner=enum/" + quote("结果", safe="") + ":enum-variant | 失败",
            package + "public class `class` {",
            package + "owner=class/" + quote("`class`", safe="") +
                ":public func value(): Int64 {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)

        for old, new in (
            ("子包", "其他"),
            ("类型", "类型二"),
            ("值", "新值"),
            ("数据", "记录"),
            ("读取", "写入"),
            ("成功", "完成"),
            ("`class`", "`struct`"),
        ):
            with self.subTest(change=(old, new)):
                replacement = source.replace(old, new) if old in ("类型", "`class`") else source.replace(old, new, 1)
                self.write_source(replacement)
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)

        for invalid, message in (
            ("package sample\npublic class `bad-name` {}\n", "invalid escaped identifier"),
            ("package sample\npublic class `class {}\n", "unterminated escaped identifier"),
            ("package sample.`class`\npublic class Visible {}\n", "canonical package"),
        ):
            with self.subTest(invalid=invalid):
                self.write_source(invalid)
                rejected = self.run_checker("--update")
                self.assertNotEqual(rejected.returncode, 0, rejected.stdout)
                self.assertIn(message, rejected.stderr)

    def test_annotation_argument_group_can_start_on_the_following_line(self) -> None:
        source = (
            "package sample\n"
            "@Deprecated\n"
            "[\n"
            "    message: \"old\"\n"
            "]\n"
            "public func annotated(value: Int64): Int64 { value }\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertIn(
            "sample.cj:package=sample:@Deprecated[message: \"old\"] "
            "public func annotated(value: Int64): Int64 {\n",
            raw,
        )

        for old, new in (
            ('message: "old"', 'message: "new"'),
            ("value: Int64", "value: String"),
            ("public func annotated", "private func annotated"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)

    def test_token_separated_declaration_prefixes_are_completed_structurally(self) -> None:
        source = (
            "package sample\n"
            "public\n"
            "func splitFunction(): Unit {}\n"
            "public open\n"
            "class OpenBox {}\n"
            "public class\n"
            "NamedBox {}\n"
            "public class ConstructorBox {\n"
            "    public ConstructorBox\n"
            "    (\n"
            "        value: Int64\n"
            "    ) { let ignored = value }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:public func splitFunction(): Unit {",
            "sample.cj:package=sample:public open class OpenBox {",
            "sample.cj:package=sample:public class NamedBox {",
            "sample.cj:package=sample:public class ConstructorBox {",
            "sample.cj:package=sample:owner=class/ConstructorBox:"
                "public ConstructorBox(value: Int64) {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)

        joined = (source
            .replace("public\nfunc", "public func")
            .replace("public open\nclass", "public open class")
            .replace("public class\nNamedBox", "public class NamedBox")
            .replace("public ConstructorBox\n    (", "public ConstructorBox("))
        self.write_source(joined)
        formatting = self.run_checker()
        self.assertEqual(formatting.returncode, 0, formatting.stderr)

        for old, new in (
            ("splitFunction(): Unit", "splitFunction(): String"),
            ("class OpenBox", "class RenamedOpenBox"),
            ("value: Int64", "value: String"),
            ("public ConstructorBox", "private ConstructorBox"),
        ):
            with self.subTest(change=(old, new)):
                self.write_source(source.replace(old, new, 1))
                changed = self.run_checker()
                self.assertNotEqual(changed.returncode, 0, changed.stdout)
                self.assertIn("public API differs", changed.stderr)

    def test_dotted_package_declaration_is_canonical_across_line_breaks(self) -> None:
        source = (
            "package sample.\n"
            "    nested\n"
            "public let exposed: Int64 = 1\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertEqual(
            raw,
            HEADER + "\nsample.cj:package=sample.nested:public let exposed: Int64 = 1\n",
        )

        self.write_source(
            "package sample.nested\n"
            "public let exposed: Int64 = 1\n"
        )
        formatting = self.run_checker()
        self.assertEqual(formatting.returncode, 0, formatting.stderr)

        self.write_source(source.replace("nested", "changed", 1))
        changed = self.run_checker()
        self.assertNotEqual(changed.returncode, 0, changed.stdout)
        self.assertIn("public API differs", changed.stderr)

    def test_snapshot_structure_is_fail_closed(self) -> None:
        self.write_source("package sample\npublic class Sample {}\npublic init() {\n")
        raw = self.update_snapshot()
        lines = raw[:-1].split("\n")
        records = lines[1:]

        malformed = [
            ("# wrong header\n" + "\n".join(records) + "\n", "header"),
            (raw + HEADER + "\n", "exactly once"),
            (raw[:-1], "exactly one newline"),
            (raw + "\n", "exactly one newline"),
            (HEADER + "\n" + "\n".join(reversed(records)) + "\n", "not sorted"),
            (HEADER + "\n" + "\n".join(sorted(records + [records[0]])) + "\n", "duplicate raw"),
            (HEADER + "\ngarbage\n", "invalid API record"),
            (HEADER + "\ndir\\sample.cj:package=sample:public init() {}\n", "invalid API record"),
            (HEADER + "\n.cj:package=sample:public init() {}\n", "invalid API record"),
        ]
        for content, message in malformed:
            with self.subTest(message=message):
                self.assert_snapshot_fails(content, message)

        collision = sorted([
            "sample.cj:package=sample:public init() {",
            "sample.cj:package=sample:public init() {}",
        ])
        self.assert_snapshot_fails(HEADER + "\n" + "\n".join(collision) + "\n", "canonical collision")

    def test_current_api_collision_fails_before_update(self) -> None:
        self.write_source("package sample\npublic init() {}\npublic init() {\n")
        result = self.run_checker("--update")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("canonical collision", result.stderr)
        self.assertFalse((self.root / "api" / "public-api-v0.9.txt").exists())

    def test_implicit_public_interface_members_are_snapshotted(self) -> None:
        self.write_source(
            "package sample\n"
            "public interface ParserSpi {\n"
            "    prop triggerBytes: Array<Byte>\n"
            "    func parse(\n"
            "        input: String,\n"
            "        offset: Int64\n"
            "    ): Bool\n"
            "}\n"
        )
        raw = self.update_snapshot()
        self.assertIn(
            "sample.cj:package=sample:owner=interface/ParserSpi:interface-member prop triggerBytes: Array<Byte>\n",
            raw,
        )
        self.assertIn(
            "sample.cj:package=sample:owner=interface/ParserSpi:interface-member func parse(input: String, offset: Int64): Bool\n",
            raw,
        )

        changed = raw.replace("triggerBytes: Array<Byte>", "triggerBytes: Array<Rune>")
        self.assert_snapshot_fails(changed, "public API differs")

    def test_static_unsafe_function_is_snapshotted(self) -> None:
        declaration = "public static unsafe func trusted(): String {"
        self.write_source(f"package sample\npublic class Sample {{\n    {declaration}\n    }}\n}}\n")
        raw = self.update_snapshot()
        record = f"sample.cj:package=sample:owner=class/Sample:{declaration}"
        self.assertIn(record + "\n", raw)
        self.assert_snapshot_fails(raw.replace(record, record.replace(" unsafe", "")), "public API differs")

    def test_members_are_bound_to_owning_type_and_cannot_be_deleted_silently(self) -> None:
        cases = [
            (
                "interface",
                "public interface First {\n    prop value: Int64\n}\n"
                "public interface Second {\n    prop value: Int64\n}\n",
                "owner=interface/First:interface-member prop value: Int64",
                "owner=interface/Second:interface-member prop value: Int64",
                "    prop value: Int64\n",
            ),
            (
                "class",
                "public class First {\n    public func value(): Int64 { 1 }\n}\n"
                "public class Second {\n    public func value(): Int64 { 1 }\n}\n",
                "owner=class/First:public func value(): Int64 {",
                "owner=class/Second:public func value(): Int64 {",
                "    public func value(): Int64",
            ),
            (
                "enum",
                "public enum First {\n    | Value\n}\n"
                "public enum Second {\n    | Value\n}\n",
                "owner=enum/First:enum-variant | Value",
                "owner=enum/Second:enum-variant | Value",
                "    | Value\n",
            ),
        ]
        for kind, source, first_record, second_record, member_marker in cases:
            with self.subTest(kind=kind):
                self.write_source("package sample\n" + source)
                raw = self.update_snapshot()
                self.assertIn("sample.cj:package=sample:" + first_record + "\n", raw)
                self.assertIn("sample.cj:package=sample:" + second_record + "\n", raw)

                first_start = source.index("public " + kind + " First")
                second_start = source.index("public " + kind + " Second")
                first_member = source.index(member_marker, first_start, second_start)
                second_member = source.index(member_marker, second_start)
                marker_length = len(member_marker)
                if kind == "class":
                    first_end = source.index("\n", first_member) + 1
                    second_end = source.index("\n", second_member) + 1
                else:
                    first_end = first_member + marker_length
                    second_end = second_member + marker_length
                for (start, end), removed_record in zip(
                    ((first_member, first_end), (second_member, second_end)),
                    (first_record, second_record),
                ):
                    self.write_source("package sample\n" + source[:start] + source[end:])
                    changed = self.run_checker()
                    self.assertNotEqual(changed.returncode, 0, changed.stdout)
                    self.assertIn("public API differs", changed.stderr)
                    self.assertIn("-sample.cj:package=sample:" + removed_record, changed.stderr)

    def test_nested_owner_chain_is_stable(self) -> None:
        self.write_source(
            "package sample\n"
            "public class Outer {\n"
            "    public class Inner {\n"
            "        public prop value: Int64 { 1 }\n"
            "    }\n"
            "}\n"
        )
        raw = self.update_snapshot()
        self.assertIn(
            "sample.cj:package=sample:owner=class/Outer>class/Inner:public prop value: Int64 {\n",
            raw,
        )

    def test_multiline_type_body_and_literal_braces_preserve_owner(self) -> None:
        self.write_source(
            "package sample\n"
            "public open class Sample\n"
            "{\n"
            "    public let text = \"} not a scope\"\n"
            "    /* { neither is this } */\n"
            "    public func value(): Int64 { 1 }\n"
            "}\n"
        )
        raw = self.update_snapshot()
        self.assertIn(
            'sample.cj:package=sample:owner=class/Sample:public let text = "} not a scope"\n',
            raw,
        )
        self.assertIn(
            "sample.cj:package=sample:owner=class/Sample:public func value(): Int64 {\n",
            raw,
        )

    def test_fake_declarations_in_comments_and_literals_are_ignored(self) -> None:
        self.write_source(
            "package sample\n"
            "/*\n"
            "public class CommentGhost {\n"
            "    public func ghost(): Unit {}\n"
            "}\n"
            "*/\n"
            "let fake = \"public class StringGhost { public func ghost(): Unit {} }\"\n"
            "public class Real {\n"
            "    public let description = \"public func notADeclaration(): Unit {}\"\n"
            "}\n"
        )
        raw = self.update_snapshot()
        self.assertNotIn("CommentGhost", raw)
        self.assertNotIn("StringGhost", raw)
        self.assertNotIn("notADeclaration(): Unit", raw.split("description =", 1)[0])
        self.assertIn(
            'sample.cj:package=sample:owner=class/Real:public let description = "public func notADeclaration(): Unit {}"\n',
            raw,
        )

    def test_cangjie_hash_raw_strings_mask_until_the_matching_delimiter(self) -> None:
        self.write_source(
            'package sample\n'
            'let rawOne = #"embedded " quote, \\ backslash, /* block */, { brace }\n'
            'public class GhostOne { public func ghost(): Unit {} }\n'
            '"#\n'
            'let rawTwo = ##"first line with " quotes and the shorter "# delimiter\n'
            'public class GhostTwo { public func ghost(): Unit {} }\n'
            'second line with //, /* */, { and }\n'
            '"##\n'
            'let rawFour = ####"public class GhostFour { public func ghost(): Unit {} }"####\n'
            '\n'
            'public class Real {}\n'
            '\n'
            'main() {}\n'
        )
        raw = self.update_snapshot()
        self.assertEqual(
            raw,
            HEADER + "\nsample.cj:package=sample:public class Real {\n",
        )

    def test_nonempty_single_line_type_and_extend_bodies_are_snapshotted(self) -> None:
        source = (
            "package sample\n"
            "public class Box {}\n"
            "public class OneLineClass { public func exposed(): Int64 { 1 }; "
            "private func hidden(): Int64 { 2 } }\n"
            "public struct OneLineStruct { public func exposed(): Int64 { 1 }; "
            "private func hidden(): Int64 { 2 } }\n"
            "public interface OneLineInterface { prop size: Int64; }\n"
            "public enum OneLineEnum { | Value(Int64) | Empty }\n"
            "extend Box { public func extended(): Int64 { 1 }; "
            "private func hidden(): Int64 { 2 } }\n"
            "\n"
            "main() {}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        expected = (
            "sample.cj:package=sample:owner=class/OneLineClass:public func exposed(): Int64 {",
            "sample.cj:package=sample:owner=struct/OneLineStruct:public func exposed(): Int64 {",
            "sample.cj:package=sample:owner=interface/OneLineInterface:interface-member prop size: Int64",
            "sample.cj:package=sample:owner=enum/OneLineEnum:enum-variant | Value(Int64)",
            "sample.cj:package=sample:owner=enum/OneLineEnum:enum-variant | Empty",
            "sample.cj:package=sample:owner=extend/" + quote("extend Box {", safe="") +
                ":public func extended(): Int64 {",
        )
        for record in expected:
            self.assertIn(record + "\n", raw)
        self.assertNotIn("hidden", raw)
        for record in raw.splitlines():
            if record.startswith("sample.cj:package=sample:public class OneLineClass"):
                self.assertEqual(record, "sample.cj:package=sample:public class OneLineClass {")

        self.write_source(source.replace("hidden(): Int64 { 2 }", "hidden(): Int64 { 99 }"))
        private_change = self.run_checker()
        self.assertEqual(private_change.returncode, 0, private_change.stderr)

        self.write_source(source.replace("exposed(): Int64", "renamed(): Int64", 1))
        public_change = self.run_checker()
        self.assertNotEqual(public_change.returncode, 0, public_change.stdout)
        self.assertIn("public API differs", public_change.stderr)
        self.assertIn("renamed", public_change.stderr)

    def test_nonempty_body_split_across_lines_fails_closed(self) -> None:
        self.write_source(
            "package sample\n"
            "public class Sample { public func value(): Int64 {\n"
            "    1\n"
            "}\n"
            "}\n"
        )
        result = self.run_checker("--update")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("nonempty type body", result.stderr)
        self.assertFalse((self.root / "api" / "public-api-v0.9.txt").exists())

    def test_private_and_internal_owners_hide_nested_public_declarations(self) -> None:
        self.write_source(
            "package sample\n"
            "private class Hidden {\n"
            "    public func leaked(): Unit {}\n"
            "    public class Nested {\n"
            "        public func alsoLeaked(): Unit {}\n"
            "    }\n"
            "}\n"
            "internal interface InternalSpi {\n"
            "    prop leaked: Int64\n"
            "}\n"
            "private extend Hidden {\n"
            "    public func extensionLeak(): Unit {}\n"
            "}\n"
            "public class Visible {\n"
            "    public func kept(): Unit {}\n"
            "}\n"
        )
        raw = self.update_snapshot()
        for hidden in ("Hidden", "Nested", "leaked", "alsoLeaked", "InternalSpi", "extensionLeak"):
            self.assertNotIn(hidden, raw)
        self.assertIn("sample.cj:package=sample:public class Visible {\n", raw)
        self.assertIn("sample.cj:package=sample:owner=class/Visible:public func kept(): Unit {\n", raw)

    def test_multiline_type_headers_are_complete_api_identity(self) -> None:
        declarations = []
        for kind, name in (
            ("class", "ClassBox"),
            ("struct", "StructBox"),
            ("interface", "InterfaceBox"),
            ("enum", "EnumBox"),
        ):
            declarations.append(
                f"public {kind} {name}<T>\n"
                f"    <: Base{name}<T>\n"
                "    where T <: OriginalBound\n"
                "{\n"
                "}\n"
            )
        source = "package sample\n" + "".join(declarations)
        self.write_source(source)
        raw = self.update_snapshot()
        for kind, name in (
            ("class", "ClassBox"),
            ("struct", "StructBox"),
            ("interface", "InterfaceBox"),
            ("enum", "EnumBox"),
        ):
            self.assertIn(
                f"sample.cj:package=sample:public {kind} {name}<T> <: Base{name}<T> where T <: OriginalBound {{\n",
                raw,
            )

        self.write_source(source.replace("OriginalBound", "ChangedBound", 1))
        changed = self.run_checker()
        self.assertNotEqual(changed.returncode, 0, changed.stdout)
        self.assertIn("public API differs", changed.stderr)
        self.assertIn("ChangedBound", changed.stderr)

    def test_extend_owner_binds_complete_multiline_header(self) -> None:
        first_header = "extend Box<T> where T <: FirstBound {"
        second_header = "extend Box<T> where T <: SecondBound {"
        source = (
            "package sample\n"
            "extend Box<T>\n"
            "    where T <: FirstBound\n"
            "{\n"
            "    public func value(): Int64 { 1 }\n"
            "}\n"
            "extend Box<T>\n"
            "    where T <: SecondBound\n"
            "{\n"
            "    public func value(): Int64 { 1 }\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        for header in (first_header, second_header):
            self.assertIn(
                "sample.cj:package=sample:owner=extend/" + quote(header, safe="") +
                ":public func value(): Int64 {\n",
                raw,
            )

        self.write_source(source.replace("FirstBound", "ChangedBound", 1))
        changed = self.run_checker()
        self.assertNotEqual(changed.returncode, 0, changed.stdout)
        self.assertIn("public API differs", changed.stderr)
        self.assertIn(quote("ChangedBound", safe=""), changed.stderr)

    def test_multiline_interface_member_and_enum_payload_are_complete(self) -> None:
        source = (
            "package sample\n"
            "public interface Parser<T> {\n"
            "    func parse(\n"
            "        input: T,\n"
            "        flags: Array<String>\n"
            "    ): Result<T>\n"
            "    where T <: ParseInput\n"
            "}\n"
            "public enum Result<T> {\n"
            "    | Value(\n"
            "        T,\n"
            "        Array<String>\n"
            "    )\n"
            "}\n"
        )
        self.write_source(source)
        raw = self.update_snapshot()
        self.assertIn(
            "sample.cj:package=sample:owner=interface/Parser:interface-member func parse(input: T, "
            "flags: Array<String>): Result<T> where T <: ParseInput\n",
            raw,
        )
        self.assertIn(
            "sample.cj:package=sample:owner=enum/Result:enum-variant | Value(T, Array<String>)\n",
            raw,
        )

        self.write_source(source.replace("ParseInput", "ChangedInput", 1))
        changed_member = self.run_checker()
        self.assertNotEqual(changed_member.returncode, 0, changed_member.stdout)
        self.assertIn("ChangedInput", changed_member.stderr)
        self.write_source(source.replace("Array<String>\n    )", "Array<Int64>\n    )", 1))
        changed_variant = self.run_checker()
        self.assertNotEqual(changed_variant.returncode, 0, changed_variant.stdout)
        self.assertIn("Array<Int64>", changed_variant.stderr)

    def test_invalid_owner_record_fails_closed(self) -> None:
        self.write_source("package sample\npublic class Sample {}\n")
        raw = self.update_snapshot()
        for invalid in (
            "sample.cj:package=sample:owner=class/:public func bad() {}",
            "sample.cj:package=sample:owner=class/Sample:",
        ):
            with self.subTest(invalid=invalid):
                records = sorted(raw[:-1].split("\n")[1:] + [invalid])
                self.assert_snapshot_fails(HEADER + "\n" + "\n".join(records) + "\n", "invalid API owner")

    def test_main_collects_once(self) -> None:
        tree = ast.parse(CHECKER.read_text(encoding="utf-8"))
        main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        calls = [
            node for node in ast.walk(main)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and
            node.func.id == "normalized_declarations"
        ]
        self.assertEqual(len(calls), 1)

    def test_release_gate_executes_checker_tests_first_and_fails_fast(self) -> None:
        gate_root = self.root / "gate"
        scripts = gate_root / "scripts"
        bin_directory = gate_root / "bin"
        scripts.mkdir(parents=True)
        bin_directory.mkdir()
        (gate_root / "tools" / "markdown").mkdir(parents=True)
        (gate_root / "examples" / "quickstart").mkdir(parents=True)
        (gate_root / "examples" / "cookbook").mkdir(parents=True)
        (gate_root / "benchmarks" / "driver").mkdir(parents=True)
        shutil.copy2(RELEASE_GATE, scripts / "release_gate.sh")

        self.write_shell_stub(scripts / "check_format.sh", "format")
        self.write_python_stub(scripts / "check_docs.py", "docs")
        self.write_python_stub(scripts / "test_build_native_scanner.py", "native-build-test")
        self.write_python_stub(scripts / "build_native_scanner.py", "native-build")
        self.write_python_stub(scripts / "fuzz_native_scanner.py", "native-fuzz")
        self.write_python_stub(scripts / "test_check_public_api.py", "checker-test", "CHECKER_TEST_EXIT")
        self.write_python_stub(scripts / "check_public_api.py", "checker", "CHECKER_EXIT")
        self.write_python_stub(scripts / "release_evidence.py", "release-evidence")
        (scripts / "release_evidence_bundle.py").write_text(
            "import pathlib, sys\n"
            "arguments = sys.argv[1:]\n"
            "output = pathlib.Path(arguments[arguments.index('--output') + 1])\n"
            "if 'init' in arguments:\n"
            "    (output / 'logs').mkdir(parents=True, exist_ok=True)\n"
            "if 'finalize' in arguments:\n"
            "    (output / 'manifest.json').write_text('{}\\n', encoding='utf-8')\n",
            encoding="utf-8",
        )
        self.write_python_stub(
            scripts / "test_release_evidence_bundle.py", "release-evidence-bundle-test"
        )
        self.write_python_stub(scripts / "test_release_evidence.py", "release-evidence-test")
        self.write_python_stub(
            scripts / "test_build_benchmark_driver.py", "benchmark-driver-build-test"
        )
        self.write_python_stub(
            scripts / "build_benchmark_driver.py", "benchmark-driver-build"
        )
        self.write_python_stub(scripts / "test_benchmark_input_profiles.py", "benchmark-input-profiles")
        self.write_shell_stub(scripts / "cli_smoke.sh", "cli-smoke")
        self.write_shell_stub(scripts / "setup_differential_tools.sh", "differential-tools")
        self.write_python_stub(scripts / "differential_test.py", "differential")
        self.write_python_stub(gate_root / "benchmarks" / "measure.py", "measure")
        self.write_cjpm_stub(bin_directory / "cjpm")

        failed_tests, failed_tests_log = self.run_release_gate(gate_root, checker_test_exit=7, checker_exit=0)
        self.assertEqual(failed_tests.returncode, 7)
        self.assertEqual(failed_tests_log, ["format", "docs", "native-build-test", "checker-test"])
        self.assertNotIn("checker", failed_tests_log)
        self.assertFalse(any(entry.startswith("cjpm:") for entry in failed_tests_log))

        failed_checker, failed_checker_log = self.run_release_gate(gate_root, checker_test_exit=0, checker_exit=9)
        self.assertEqual(failed_checker.returncode, 9)
        self.assertEqual(failed_checker_log, ["format", "docs", "native-build-test", "checker-test", "checker"])
        self.assertFalse(any(entry.startswith("cjpm:") for entry in failed_checker_log))

        success, success_log = self.run_release_gate(gate_root, checker_test_exit=0, checker_exit=0)
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertEqual(success_log[:5], ["format", "docs", "native-build-test", "checker-test", "checker"])
        self.assertTrue(success_log[5].startswith("cjpm:check"))

    def write_shell_stub(self, path: Path, label: str) -> None:
        path.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            f"printf '%s\\n' '{label}' >> \"$GATE_LOG\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def write_python_stub(self, path: Path, label: str, exit_variable: str | None = None) -> None:
        exit_expression = f'int(os.environ.get("{exit_variable}", "0"))' if exit_variable is not None else "0"
        path.write_text(
            "import os\n"
            "from pathlib import Path\n"
            f'with Path(os.environ["GATE_LOG"]).open("a", encoding="utf-8") as stream:\n'
            f'    stream.write("{label}\\n")\n'
            f"raise SystemExit({exit_expression})\n",
            encoding="utf-8",
        )

    def write_cjpm_stub(self, path: Path) -> None:
        path.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "printf 'cjpm:%s\\n' \"$*\" >> \"$GATE_LOG\"\n",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def run_release_gate(
        self,
        gate_root: Path,
        *,
        checker_test_exit: int,
        checker_exit: int,
    ) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        log = gate_root / "calls.log"
        log.unlink(missing_ok=True)
        environment = os.environ.copy()
        environment["PATH"] = str(gate_root / "bin") + os.pathsep + environment["PATH"]
        environment["GATE_LOG"] = str(log)
        environment["CHECKER_TEST_EXIT"] = str(checker_test_exit)
        environment["CHECKER_EXIT"] = str(checker_exit)
        result = subprocess.run(
            ["bash", "scripts/release_gate.sh"],
            cwd=gate_root,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
        return result, calls


if __name__ == "__main__":
    unittest.main(verbosity=2)
