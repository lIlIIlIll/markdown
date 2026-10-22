#!/usr/bin/env python3
"""Compile external consumers against the built domain packages and their boundaries."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "target" / "release" / "markdown"

CONSUMER = """package outside_consumer
import markdown.core.{DisplayWidthPolicy, SourcePositionMap}
import markdown.engine.MarkdownEngine
import markdown.editor.{DocumentSnapshot, MarkdownLinter}
import markdown.artifact.{ArtifactLoadResult, MarkdownParseArtifact}

public func useDomains(): Int64 {
    let engine = MarkdownEngine.builder().build()
    let snapshot = DocumentSnapshot.parse(engine, "# title")
    let positions = SourcePositionMap(snapshot.result.source, tabStop: 4,
        displayWidthPolicy: DisplayWidthPolicy.UnicodeScalarWithTabStops)
    let diagnostics = MarkdownLinter(engine).lint(snapshot)
    let artifact = MarkdownParseArtifact.create(engine, snapshot.result)
    let nodes = match (artifact.load(engine, "# title")) {
        case ArtifactLoadResult.Hit(document) => document.nodeCount
        case _ => 0
    }
    let document = snapshot.result.document.detach()
    let renderer = engine.htmlRenderer()
    let output = renderer.renderWithSourceMap(document)
    let observed = renderer.renderObserved(document)
    return nodes + output.sourceMap.size + diagnostics.size +
        observed.statistics.outputBytes + positions.sourcePosition(0).line
}
"""


class DomainPackageConsumerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compiler = shutil.which("cjc")
        if cls.compiler is None or not (MODULES / "markdown.engine.cjo").is_file():
            raise RuntimeError("activate STS 1.2.0 and run cjpm build before this check")
        cls.temporary = tempfile.TemporaryDirectory(prefix="markdown-domain-consumer-")
        cls.directory = Path(cls.temporary.name)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def compile(self, source: str) -> subprocess.CompletedProcess[str]:
        path = self.directory / "consumer.cj"
        path.write_text(source, encoding="utf-8")
        return subprocess.run(
            [self.compiler, str(path), "--output-type", "staticlib", "--import-path", str(MODULES),
                "-o", str(self.directory / "consumer.a")],
            capture_output=True, text=True, check=False)

    def test_domain_operations_and_same_package_extensions_are_exported(self) -> None:
        result = self.compile(CONSUMER)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_root_facade_and_internal_arena_are_not_exported(self) -> None:
        for package, name in (("markdown", "Markdown"), ("markdown", "Document"),
                ("markdown.core", "AstArenaBuilder"), ("markdown.engine", "AcceleratedMarkdownEngine")):
            with self.subTest(package=package, name=name):
                result = self.compile(f"package outside_consumer\nimport {package}.{name}\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)

    def test_engine_does_not_retain_removed_service_and_configuration_entries(self) -> None:
        for expression, name in (
                ('MarkdownEngine.builder().build().parseSnapshot("text")', "parseSnapshot"),
                ('MarkdownEngine.builder().build().createArtifact(MarkdownEngine.builder().build().parse("text"))',
                    "createArtifact"),
                ("MarkdownEngine.builder().nativeScannerEnabled(false)", "nativeScannerEnabled"),
                ("MarkdownEngineBuilder()", "MarkdownEngineBuilder")):
            with self.subTest(name=name):
                result = self.compile("package outside_consumer\n"
                    "import markdown.engine.{MarkdownEngine, MarkdownEngineBuilder}\n"
                    f"public func removed(): Unit {{ let _ = {expression} }}\n")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)


if __name__ == "__main__":
    unittest.main()
