#!/usr/bin/env python3
"""Contract tests for the retained system link-input closure."""

from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import link_inputs


class LinkInputsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="markdown-link-inputs-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.sysroot = self.root / "sysroot"
        (self.sysroot / "lib").mkdir(parents=True)
        (self.sysroot / "lib/libc.so.6").write_bytes(b"\x7fELFfixture")
        (self.sysroot / "lib/libc.so").write_bytes(
            b"/* fixture */ OUTPUT_FORMAT(elf64-x86-64) GROUP(/lib/libc.so.6)")
        for path in self.sysroot.rglob("*"):
            if path.is_file(): path.chmod(0o644)
        files = link_inputs.inventory(self.sysroot)
        self.identity = {"schemaVersion": 1, "target": "x86_64-unknown-linux-gnu",
            "files": files, "treeSha256": link_inputs.canonical_digest(files),
            "libraryDirectories": ["lib"]}

    def test_complete_closure_is_accepted(self):
        self.assertEqual(link_inputs.validate_inputs(self.sysroot, self.identity), self.identity)

    def test_modified_missing_and_extra_inputs_fail(self):
        original = (self.sysroot / "lib/libc.so.6").read_bytes()
        (self.sysroot / "lib/libc.so.6").write_bytes(b"\x7fELFchanged")
        with self.assertRaises(ValueError):
            link_inputs.validate_inputs(self.sysroot, self.identity)
        (self.sysroot / "lib/libc.so.6").write_bytes(original)
        (self.sysroot / "lib/extra.o").write_bytes(b"\x7fELFextra")
        with self.assertRaises(ValueError):
            link_inputs.validate_inputs(self.sysroot, self.identity)
        (self.sysroot / "lib/extra.o").unlink()
        (self.sysroot / "lib/libc.so.6").unlink()
        with self.assertRaises(ValueError):
            link_inputs.validate_inputs(self.sysroot, self.identity)

    def test_symlink_root_and_members_fail(self):
        alias = self.root / "alias"
        alias.symlink_to(self.sysroot)
        with self.assertRaises(ValueError): link_inputs.inventory(alias)
        (self.sysroot / "lib/alias.so").symlink_to("libc.so.6")
        with self.assertRaises(ValueError): link_inputs.inventory(self.sysroot)

    def test_script_rejects_traversal_includes_and_other_directives(self):
        for script in (b"GROUP(/lib/../../outside)", b"INCLUDE /lib/input",
                b"OUTPUT(/lib/file)", b"SEARCH_DIR(/lib)", b"GROUP(/lib/input", b"GROUP(/lib/input))"):
            with self.subTest(script=script), self.assertRaises(ValueError):
                link_inputs.script_references(script)
        self.assertEqual(link_inputs.script_references(
            b"GROUP(/lib/libc.so.6 AS_NEEDED(-lm))"), ["/lib/libc.so.6", "-lm"])

    def test_unretained_script_reference_is_rejected_even_with_updated_digest(self):
        (self.sysroot / "lib/libc.so").write_bytes(b"INPUT(/lib/unretained.so)")
        files = link_inputs.inventory(self.sysroot)
        self.identity.update(files=files, treeSha256=link_inputs.canonical_digest(files))
        with self.assertRaisesRegex(ValueError, "unretained input"):
            link_inputs.validate_inputs(self.sysroot, self.identity)

    def test_retention_limits_fail_closed(self):
        with patch.object(link_inputs, "MAX_FILES", 1), self.assertRaises(ValueError):
            link_inputs.inventory(self.sysroot)
        with patch.object(link_inputs, "MAX_BYTES", 2), self.assertRaises(ValueError):
            link_inputs.inventory(self.sysroot)

    def test_options_pin_compiler_jobs_driver_and_linker_sysroots(self):
        sdk = self.root / "sdk"
        (sdk / "third_party/llvm/bin").mkdir(parents=True)
        (sdk / "third_party/llvm/bin/lld").write_bytes(b"fixed-sdk-linker")
        launcher = self.root / "commands"
        options = link_inputs.compiler_options(self.sysroot, self.identity, sdk, launcher)
        self.assertIn("-j1", options)
        self.assertEqual(options[options.index("--sysroot") + 1], str(self.sysroot))
        self.assertIn("--link-option=--sysroot=" + str(self.sysroot), options)
        self.assertIn("--link-option=-L" + str(self.sysroot / "lib"), options)
        command = (launcher / "ld").read_text()
        self.assertIn(str(sdk / "third_party/llvm/bin/lld"), command)
        self.assertIn('-flavor gnu "$@"', command)
        self.assertNotIn("/usr/bin/ld", command)
        self.assertIn("--link-option=--threads=1", options)
        self.assertIn("--link-option=--thinlto-jobs=1", options)

    def test_sdk_cpp_runtime_is_installed_without_changing_sdk_files(self):
        source = self.sysroot.joinpath(*link_inputs.SDK_CPP_ROOT.parts)
        source.mkdir(parents=True)
        for name in link_inputs.SDK_CPP_LIBRARIES:
            (source / name).write_bytes(b"\x7fELFfixture-" + name.encode())
            (source / name).chmod(0o644)
        files = link_inputs.inventory(self.sysroot)
        self.identity.update(files=files, treeSha256=link_inputs.canonical_digest(files),
            libraryDirectories=sorted({str(Path(value).parent) for value in files}))
        sdk = self.root / "extracted/cangjie"
        (sdk / "bin").mkdir(parents=True)
        (sdk / "bin/cjc").write_bytes(b"unmodified-sdk")
        destination = link_inputs.install_cpp_runtime(self.sysroot, self.identity, sdk)
        self.assertEqual((sdk / "bin/cjc").read_bytes(), b"unmodified-sdk")
        self.assertFalse(destination.is_relative_to(sdk))
        link_inputs.validate_cpp_runtime(destination, self.identity)
        (destination / "libstdc++.so.6").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "bytes or mode differ"):
            link_inputs.validate_cpp_runtime(destination, self.identity)

    def test_missing_sdk_cpp_runtime_cannot_fall_back_to_the_host(self):
        sdk = self.root / "extracted/cangjie"
        sdk.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, r"C\+\+ runtime library is missing"):
            link_inputs.install_cpp_runtime(self.sysroot, self.identity, sdk)
        self.assertFalse((sdk.parent / "cpp-runtime").exists())


if __name__ == "__main__":
    unittest.main()
