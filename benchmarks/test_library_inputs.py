"""Regressions for domain libraries that were previously outside the root archive identity."""

from pathlib import Path
import tempfile
import unittest

from library_inputs import library_digest, library_inputs, library_link_arguments


class DomainLibraryInputsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="markdown-library-inputs-")
        self.root = Path(self.temporary.name)
        for name in ("libmarkdown.a", "libmarkdown.core.a", "libmarkdown.engine.a",
                "markdown.cjo", "markdown.core.cjo", "markdown.engine.cjo"):
            (self.root / name).write_bytes(name.encode())

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_engine_change_is_bound_even_when_root_archive_is_unchanged(self) -> None:
        before = library_digest(self.root)
        root = (self.root / "libmarkdown.a").read_bytes()
        (self.root / "libmarkdown.engine.a").write_bytes(b"changed engine")
        self.assertEqual((self.root / "libmarkdown.a").read_bytes(), root)
        self.assertNotEqual(library_digest(self.root), before)

    def test_new_domain_and_compiler_metadata_are_both_bound(self) -> None:
        before = library_digest(self.root)
        (self.root / "libmarkdown.editor.a").write_bytes(b"editor")
        self.assertNotEqual(library_digest(self.root), before)
        self.assertIn("-lmarkdown.editor", library_link_arguments(self.root))
        before = library_digest(self.root)
        (self.root / "markdown.core.cjo").write_bytes(b"changed public metadata")
        self.assertNotEqual(library_digest(self.root), before)
        self.assertIn("markdown.core.cjo", library_inputs(self.root))

    def test_root_only_library_is_rejected(self) -> None:
        (self.root / "libmarkdown.core.a").unlink()
        with self.assertRaisesRegex(ValueError, "domain packages"):
            library_inputs(self.root)


if __name__ == "__main__":
    unittest.main()
