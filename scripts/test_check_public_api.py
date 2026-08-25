#!/usr/bin/env python3
"""End-to-end regression tests for the public API snapshot checker."""

from __future__ import annotations

import ast
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
CHECKER = HERE / "check_public_api.py"
RELEASE_GATE = HERE / "release_gate.sh"
HEADER = "# markdown public API snapshot v1"


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
        return (self.root / "api" / "public-api-v1.txt").read_text(encoding="utf-8")

    def write_snapshot(self, content: str) -> None:
        (self.root / "api" / "public-api-v1.txt").write_bytes(content.encode("utf-8"))

    def assert_snapshot_fails(self, content: str, message: str | None = None) -> subprocess.CompletedProcess[str]:
        self.write_snapshot(content)
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        if message is not None:
            self.assertIn(message, result.stderr)
        return result

    def test_constructor_markers_compare_equal_and_update_stays_raw(self) -> None:
        for declaration in (
            "public init() {",
            "public unsafe init() {",
            'public init<T>(value!: String = "(") where T <: Any {',
        ):
            with self.subTest(declaration=declaration):
                self.write_source(f"package sample\npublic class Sample {{\n    {declaration}\n    }}\n}}\n")
                raw = self.update_snapshot()
                raw_record = f"sample.cj:{declaration}"
                self.assertIn(raw_record + "\n", raw)
                self.assertNotIn(raw_record + "}\n", raw)

                equivalent = raw.replace(raw_record + "\n", raw_record + "}\n")
                self.write_snapshot(equivalent)
                verified = self.run_checker()
                self.assertEqual(verified.returncode, 0, verified.stderr)

                updated = self.run_checker("--update")
                self.assertEqual(updated.returncode, 0, updated.stderr)
                self.assertEqual((self.root / "api" / "public-api-v1.txt").read_text(encoding="utf-8"), raw)

    def test_real_constructor_signature_and_file_differences_fail_with_raw_diff(self) -> None:
        declaration = 'public init<T>(value: Int64, name!: String = "x") where T <: Any {'
        self.write_source(f"package sample\npublic class Sample {{\n    {declaration}\n    }}\n}}\n")
        raw = self.update_snapshot()
        record = f"sample.cj:{declaration}"
        variants = [
            record.replace("public init", "public unsafe init"),
            record.replace("<T>", "<U>"),
            record.replace("where T <: Any", "where T <: Object"),
            record.replace("value: Int64", "other: Int64"),
            record.replace("value: Int64", "value: String"),
            record.replace("value: Int64, name!: String", "name!: String, value: Int64"),
            record.replace('= "x"', '= "y"'),
            record.replace(") where", "): Unit where"),
            record.replace("sample.cj:", "other.cj:"),
        ]
        for variant in variants:
            with self.subTest(variant=variant):
                mutated = raw.replace(record, variant)
                mutated_records = sorted(mutated[:-1].split("\n")[1:])
                result = self.assert_snapshot_fails(
                    HEADER + "\n" + "\n".join(mutated_records) + "\n", "public API differs")
                self.assertIn("-" + variant, result.stderr)
                self.assertIn("+" + record, result.stderr)

    def test_non_constructor_and_non_public_markers_are_not_normalized(self) -> None:
        cases = [
            ("public func value() {", "public func value() {}"),
            ("public prop value: Int64 {", "public prop value: Int64 {}"),
            ("public let value = {", "public let value = {}"),
            ("public var value = {", "public var value = {}"),
        ]
        for current, expected in cases:
            with self.subTest(current=current):
                self.write_source(f"package sample\n{current}\n")
                raw = self.update_snapshot()
                self.assert_snapshot_fails(raw.replace(current, expected), "public API differs")

        self.write_source("package sample\npublic class Sample {}\n")
        raw = self.update_snapshot()
        for record in (
            "sample.cj:internal init() {}",
            "sample.cj:public protected init() {}",
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
        self.assert_snapshot_fails(raw.replace(body, "public init() {}"), "public API differs")

        marker = "public init() {"
        self.write_source(f"package sample\n{marker}\n")
        raw = self.update_snapshot()
        self.assert_snapshot_fails(raw.replace(marker, "public init() {} // comment"), "public API differs")
        self.assert_snapshot_fails(raw.replace(marker + "\n", "public init() {} \n"), "public API differs")

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
            (HEADER + "\ndir/sample.cj:public init() {}\n", "invalid API record"),
            (HEADER + "\n.cj:public init() {}\n", "invalid API record"),
        ]
        for content, message in malformed:
            with self.subTest(message=message):
                self.assert_snapshot_fails(content, message)

        collision = sorted(["sample.cj:public init() {", "sample.cj:public init() {}"])
        self.assert_snapshot_fails(HEADER + "\n" + "\n".join(collision) + "\n", "canonical collision")

    def test_current_api_collision_fails_before_update(self) -> None:
        self.write_source("package sample\npublic init() {}\npublic init() {\n")
        result = self.run_checker("--update")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("canonical collision", result.stderr)
        self.assertFalse((self.root / "api" / "public-api-v1.txt").exists())

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
        (gate_root / "benchmarks").mkdir()
        shutil.copy2(RELEASE_GATE, scripts / "release_gate.sh")

        self.write_shell_stub(scripts / "check_format.sh", "format")
        self.write_python_stub(scripts / "test_check_public_api.py", "checker-test", "CHECKER_TEST_EXIT")
        self.write_python_stub(scripts / "check_public_api.py", "checker", "CHECKER_EXIT")
        self.write_shell_stub(scripts / "cli_smoke.sh", "cli-smoke")
        self.write_python_stub(scripts / "differential_test.py", "differential")
        self.write_python_stub(gate_root / "benchmarks" / "measure.py", "measure")
        self.write_cjpm_stub(bin_directory / "cjpm")

        failed_tests, failed_tests_log = self.run_release_gate(gate_root, checker_test_exit=7, checker_exit=0)
        self.assertEqual(failed_tests.returncode, 7)
        self.assertEqual(failed_tests_log, ["format", "checker-test"])
        self.assertNotIn("checker", failed_tests_log)
        self.assertFalse(any(entry.startswith("cjpm:") for entry in failed_tests_log))

        failed_checker, failed_checker_log = self.run_release_gate(gate_root, checker_test_exit=0, checker_exit=9)
        self.assertEqual(failed_checker.returncode, 9)
        self.assertEqual(failed_checker_log, ["format", "checker-test", "checker"])
        self.assertFalse(any(entry.startswith("cjpm:") for entry in failed_checker_log))

        success, success_log = self.run_release_gate(gate_root, checker_test_exit=0, checker_exit=0)
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertEqual(success_log[:3], ["format", "checker-test", "checker"])
        self.assertTrue(success_log[3].startswith("cjpm:check"))

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
