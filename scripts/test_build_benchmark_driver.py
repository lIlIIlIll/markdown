#!/usr/bin/env python3
"""Regression tests for the canonical benchmark driver build."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import build_benchmark_driver


def add_tar_file(bundle: tarfile.TarFile, name: str, content: bytes,
        mode: int = 0o644) -> None:
    member = tarfile.TarInfo(name)
    member.size = len(content)
    member.mode = mode
    bundle.addfile(member, io.BytesIO(content))


def add_tar_symlink(bundle: tarfile.TarFile, name: str, target: str) -> None:
    member = tarfile.TarInfo(name)
    member.type = tarfile.SYMTYPE
    member.linkname = target
    member.mode = 0o777
    bundle.addfile(member)


def fake_sdk_archive(path: Path) -> str:
    with tarfile.open(path, "w:gz") as bundle:
        add_tar_file(bundle, "cangjie/envsetup.sh", b"#!/bin/sh\n", 0o755)
        add_tar_file(bundle, "cangjie/bin/cjc",
            b"#!/bin/sh\necho 'Target: x86_64-unknown-linux-gnu'\n", 0o755)
        add_tar_file(bundle, "cangjie/tools/bin/cjpm",
            b"#!/bin/sh\necho 'cjpm test'\n", 0o755)
    return hashlib.sha256(path.read_bytes()).hexdigest()


class BenchmarkDriverBuildTest(unittest.TestCase):
    def test_removed_build_mode_is_rejected(self) -> None:
        result = subprocess.run(
            [sys.executable, str(Path(build_benchmark_driver.__file__)), "--mode", "compatibility"],
            capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("unrecognized arguments", result.stderr)

    def test_identity_schema_matches_same_language_gate(self) -> None:
        import compare_markdown4cj

        self.assertEqual(build_benchmark_driver.IDENTITY_SCHEMA_VERSION,
            compare_markdown4cj.BUILD_IDENTITY_SCHEMA_VERSION)

    def write_native_identity_fixture(self, native: Path) -> tuple[Path, Path, Path]:
        native.mkdir(parents=True)
        tools = native.parent / "native-tools"
        tools.mkdir()
        compiler = tools / "clang"
        archiver = tools / "ar"
        compiler.write_text("#!/bin/sh\necho 'stable tools'\n", encoding="utf-8")
        archiver.write_text("#!/bin/sh\necho 'stable tools'\n", encoding="utf-8")
        compiler.chmod(0o755)
        archiver.chmod(0o755)
        obj = native / "markdown_scanner.o"
        archive = native / "libmarkdown_scanner.a"
        manifest_path = native / "markdown_scanner.cache.json"
        obj.write_bytes(b"native-object")
        archive.write_bytes(b"native-archive")
        compiler_identity = build_benchmark_driver.binary_identity(compiler)
        compiler_identity["version"] = {"command": [str(compiler), "--version"],
            "exitCode": 0, "stdout": "stable tools\n", "stderr": ""}
        archiver_identity = build_benchmark_driver.binary_identity(archiver)
        archiver_identity["version"] = {"command": [str(archiver), "--version"],
            "exitCode": 0, "stdout": "stable tools\n", "stderr": ""}
        variables = {
            "HOME": str((native / ".native-build-home").resolve()),
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": os.pathsep.join((str(tools.resolve()), "/usr/bin", "/bin")),
            "SOURCE_DATE_EPOCH": "0",
            "TMPDIR": str((native / ".native-build-tmp").resolve()),
            "TZ": "UTC",
        }
        manifest = {
            "schemaVersion": build_benchmark_driver.NATIVE_CACHE_SCHEMA_VERSION,
            "sourceSha256": build_benchmark_driver.sha256(
                build_benchmark_driver.ROOT / "native/markdown_scanner.c"),
            "headerSha256": build_benchmark_driver.sha256(
                build_benchmark_driver.ROOT / "native/markdown_scanner.h"),
            "target": "x86_64-unknown-linux-gnu",
            "platformBranch": "gnu-like",
            "compiler": compiler_identity,
            "archiver": archiver_identity,
            "compileCommand": [str(compiler), "-o", str(obj)],
            "archiveCommand": [str(archiver), "rcs", str(archive), str(obj)],
            "buildEnvironment": {
                "schemaVersion": build_benchmark_driver.NATIVE_ENVIRONMENT_SCHEMA_VERSION,
                "allowlist": sorted(
                    build_benchmark_driver.NATIVE_BUILD_ENVIRONMENT_KEYS),
                "variables": variables,
                "sha256": build_benchmark_driver.canonical_json_sha256(variables),
            },
            "object": build_benchmark_driver.binary_identity(obj),
            "archive": build_benchmark_driver.binary_identity(archive),
        }
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return obj, archive, manifest_path



    def test_trimpath_manifest_is_root_specific_and_preserves_other_options(self) -> None:
        source = '[package]\n  compile-option = "-O2 --lto thin --obf-seed 0"\n'
        actual = build_benchmark_driver.trimpath_manifest(source,
            Path("/tmp/fresh-product-a"))
        self.assertIn(
            'compile-option = "-O2 --lto thin --obf-seed 0 --trimpath /tmp/fresh-product-a"',
            actual)
        with self.assertRaisesRegex(ValueError, "already contains --trimpath"):
            build_benchmark_driver.trimpath_manifest(actual,
                Path("/tmp/fresh-product-b"))

    def test_cangjie_trimpath_makes_two_fresh_roots_byte_reproducible(self) -> None:
        cjc = shutil.which("cjc")
        if cjc is None:
            self.fail("cjc is required for the canonical trimpath probe")
        with tempfile.TemporaryDirectory() as temporary:
            binaries = []
            for suffix in ("a", "b"):
                root = Path(temporary) / f"fresh-{suffix}"
                root.mkdir()
                source = root / "main.cj"
                output = root / "main"
                source.write_text("main(): Int64 { return 0 }\n", encoding="utf-8")
                result = subprocess.run([cjc, "-O2", "--lto=thin", "--obf-seed", "0", "--trimpath",
                    str(root), str(source), "-o", str(output)], text=True,
                    capture_output=True, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                binaries.append(output.read_bytes())
            self.assertEqual(binaries[0], binaries[1])

    def test_build_identity_binds_the_actual_sdk_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "sdk.tar.gz"
            sdk_sha = fake_sdk_archive(archive)
            args = SimpleNamespace(sdk_archive=archive, sdk_sha256=sdk_sha,
                sdk_url="https://example.invalid/sdk.tar.gz",
                sdk_extract_dir=Path(temporary) / "extracted",
                target="x86_64-unknown-linux-gnu")
            sdk = build_benchmark_driver.prepare_sdk(args)
            link_root = Path(temporary) / "link-inputs"
            (link_root / "sysroot/lib").mkdir(parents=True)
            startup = link_root / "sysroot/lib/startup.o"
            startup.write_bytes(b"\x7fELFtest-startup-object")
            startup.chmod(0o644)
            cpp = link_root / "sysroot" / build_benchmark_driver.link_inputs.SDK_CPP_ROOT
            cpp.mkdir(parents=True)
            for name in build_benchmark_driver.link_inputs.SDK_CPP_LIBRARIES:
                (cpp / name).write_bytes(b"\x7fELFtest-" + name.encode())
                (cpp / name).chmod(0o644)
            link_files = build_benchmark_driver.link_inputs.inventory(link_root / "sysroot")
            link_identity = {"schemaVersion": 1, "target": args.target, "files": link_files,
                "libraryDirectories": sorted({str(Path(value).parent) for value in link_files}),
                "treeSha256": build_benchmark_driver.link_inputs.canonical_digest(link_files)}
            launcher = Path(temporary) / "linker"
            build_benchmark_driver.link_inputs.install_cpp_runtime(
                link_root / "sysroot", link_identity, sdk.root)
            sdk = replace(sdk, link_inputs={"root": str(link_root), "launcher": str(launcher),
                "identity": link_identity,
                "compilerOptions": build_benchmark_driver.link_inputs.option_arguments(
                    link_root / "sysroot", link_identity, launcher)})
            recorded_environment = dict(sdk.environment)
            driver = {"build": {"command": [str(sdk.cjpm), "build"],
                "environment": recorded_environment},
                "sourceProductTreeSha256":
                    build_benchmark_driver.benchmark_product_tree_sha256(
                        build_benchmark_driver.ROOT),
                "binary": {"sha256": "1" * 64}}
            cli = {"build": {"command": [str(sdk.cjpm), "build"],
                "environment": recorded_environment},
                "sourceProductTreeSha256":
                    build_benchmark_driver.benchmark_product_tree_sha256(
                        build_benchmark_driver.ROOT),
                "binary": {"sha256": "2" * 64}}
            with patch.object(build_benchmark_driver, "native_identity",
                    return_value={"archive": {"sha256": "3" * 64}}):
                identity = build_benchmark_driver.build_identity(args, driver, cli, sdk)
            self.assertEqual(identity["sdk"]["archiveSha256"], sdk_sha)
            self.assertEqual(identity["sdk"]["archiveBytes"], archive.stat().st_size)
            self.assertEqual(identity["linkInputs"], sdk.link_inputs)
            self.assertIn("benchmarks/link_inputs.py", identity["sourceIdentity"]["files"])
            self.assertEqual(identity["builds"]["markdownDriver"], driver)
            self.assertEqual(identity["tools"]["cjpm"]["path"], str(sdk.cjpm))
            self.assertEqual(identity["tools"]["cjpm"]["sha256"],
                hashlib.sha256(sdk.cjpm.read_bytes()).hexdigest())
            self.assertIn("scripts/build_benchmark_driver.py",
                identity["sourceIdentity"]["files"])
            self.assertEqual(identity["sdk"]["environment"],
                build_benchmark_driver.build_environment_attestation(sdk.environment))

    def test_sdk_child_environment_does_not_inherit_ambient_controls(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "cangjie"
            root.mkdir()
            contaminated = {
                "PATH": "/host/tools",
                "LD_LIBRARY_PATH": "/host/runtime",
                "LD_PRELOAD": "/host/instrumentation.so",
                "LIBRARY_PATH": "/host/linker",
                "cjHeapSize": "64MB",
                "cjGCInterval": "1ms",
                "LANG": "tr_TR.UTF-8",
            }
            with patch.dict(os.environ, contaminated, clear=True):
                environment = build_benchmark_driver.sdk_environment(root,
                    "x86_64-unknown-linux-gnu")
            self.assertEqual(environment,
                build_benchmark_driver.canonical_build_environment(root,
                    "x86_64-unknown-linux-gnu"))
            self.assertTrue(Path(environment["HOME"]).is_dir())
            self.assertTrue(Path(environment["TMPDIR"]).is_dir())
            for name in ("LD_PRELOAD", "LIBRARY_PATH", "cjHeapSize", "cjGCInterval"):
                self.assertNotIn(name, environment)

    def test_build_child_rejects_an_environment_outside_the_allowlist(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "cangjie"
            root.mkdir()
            environment = build_benchmark_driver.sdk_environment(root,
                "x86_64-unknown-linux-gnu")
            environment["LD_PRELOAD"] = "/tmp/instrumentation.so"
            with self.assertRaisesRegex(ValueError, "unexpected: LD_PRELOAD"):
                build_benchmark_driver.command_record(
                    ["/bin/true"], root, check=True, environment=environment)

    def test_canonical_measurement_rejects_ambient_performance_controls(self) -> None:
        for name in ("LD_PRELOAD", "LIBRARY_PATH", "MARKDOWN_NATIVE_CFLAGS",
                "TARGET", "cjHeapSize", "cjGCInterval"):
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, name):
                build_benchmark_driver.reject_ambient_benchmark_environment(
                    {name: "polluted"})

    def test_build_identity_rejects_an_unverified_sdk_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "sdk.tar.gz"
            archive.write_bytes(b"not the declared archive")
            args = SimpleNamespace(sdk_archive=archive, sdk_sha256="0" * 64,
                sdk_url="https://example.invalid/sdk.tar.gz",
                sdk_extract_dir=Path(temporary) / "extracted",
                target="x86_64-unknown-linux-gnu")
            with self.assertRaisesRegex(RuntimeError, "SDK archive digest"):
                build_benchmark_driver.prepare_sdk(args)
            self.assertFalse(args.sdk_extract_dir.exists())

    def test_native_identity_binds_manifest_to_real_object_and_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            native = Path(temporary) / "native"
            obj, archive, manifest = self.write_native_identity_fixture(native)
            with patch.object(build_benchmark_driver, "NATIVE", native), \
                    patch.object(build_benchmark_driver, "NATIVE_MANIFEST", manifest):
                identity = build_benchmark_driver.native_identity(
                    "x86_64-unknown-linux-gnu")
            self.assertEqual(identity["object"],
                build_benchmark_driver.binary_identity(obj))
            self.assertEqual(identity["archive"],
                build_benchmark_driver.binary_identity(archive))
            self.assertEqual(identity["cacheManifestSha256"],
                build_benchmark_driver.canonical_json_sha256(identity["cacheManifest"]))

    def test_native_identity_rejects_tampered_object_and_archive(self) -> None:
        for output_name, expected_message in (
                ("markdown_scanner.o", "object digest"),
                ("libmarkdown_scanner.a", "archive digest")):
            with self.subTest(output=output_name), tempfile.TemporaryDirectory() as temporary:
                native = Path(temporary) / "native"
                _, _, manifest = self.write_native_identity_fixture(native)
                (native / output_name).write_bytes(b"tampered")
                with patch.object(build_benchmark_driver, "NATIVE", native), \
                        patch.object(build_benchmark_driver, "NATIVE_MANIFEST", manifest), \
                        self.assertRaisesRegex(RuntimeError, expected_message):
                    build_benchmark_driver.native_identity(
                        "x86_64-unknown-linux-gnu")

    def test_native_identity_rejects_a_polluted_build_environment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            native = Path(temporary) / "native"
            _, _, manifest_path = self.write_native_identity_fixture(native)
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            variables = manifest["buildEnvironment"]["variables"]
            variables["COMSPEC"] = "/tmp/ambient-command-shell"
            manifest["buildEnvironment"]["sha256"] = \
                build_benchmark_driver.canonical_json_sha256(variables)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with patch.object(build_benchmark_driver, "NATIVE", native), \
                    patch.object(build_benchmark_driver, "NATIVE_MANIFEST", manifest_path), \
                    self.assertRaisesRegex(RuntimeError, "environment is not canonical"):
                build_benchmark_driver.native_identity(
                    "x86_64-unknown-linux-gnu")

    def test_native_identity_rejects_same_version_tool_binary_tampering(self) -> None:
        for field in ("compiler", "archiver"):
            with self.subTest(tool=field), tempfile.TemporaryDirectory() as temporary:
                native = Path(temporary) / "native"
                _, _, manifest_path = self.write_native_identity_fixture(native)
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                tool = Path(manifest[field]["path"])
                original_version = manifest[field]["version"]
                tool.write_text(
                    "#!/bin/sh\n# changed wrapper\necho 'stable tools'\n",
                    encoding="utf-8")
                tool.chmod(0o755)
                self.assertEqual(manifest[field]["version"], original_version)
                with patch.object(build_benchmark_driver, "NATIVE", native), \
                        patch.object(build_benchmark_driver, "NATIVE_MANIFEST", manifest_path), \
                        self.assertRaisesRegex(RuntimeError,
                            rf"{field} binary digest changed"):
                    build_benchmark_driver.native_identity(
                        "x86_64-unknown-linux-gnu")

    def test_active_path_sdk_cannot_be_attested_as_the_pinned_sdk(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "sdk.tar.gz"
            args = SimpleNamespace(sdk_archive=archive,
                sdk_sha256=fake_sdk_archive(archive),
                sdk_url="https://example.invalid/sdk.tar.gz",
                sdk_extract_dir=root / "extracted",
                target="x86_64-unknown-linux-gnu")
            wrong = root / "daily" / "bin" / "cjpm"
            wrong.parent.mkdir(parents=True)
            wrong.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            wrong.chmod(0o755)
            with patch.dict(os.environ, {"PATH": str(wrong.parent)}):
                sdk = build_benchmark_driver.prepare_sdk(args)
            self.assertNotEqual(sdk.cjpm, wrong.resolve())
            driver = {"build": {"command": [str(wrong), "build"]}}
            cli = {"build": {"command": [str(sdk.cjpm), "build"],
                "environment": dict(sdk.environment)}}
            with self.assertRaisesRegex(RuntimeError, "markdownDriver was not built"):
                build_benchmark_driver.build_identity(args, driver, cli, sdk)

    def test_product_build_invokes_the_extracted_cjpm_by_absolute_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "sdk.tar.gz"
            args = SimpleNamespace(sdk_archive=archive,
                sdk_sha256=fake_sdk_archive(archive),
                sdk_extract_dir=root / "extracted",
                target="x86_64-unknown-linux-gnu")
            sdk = build_benchmark_driver.prepare_sdk(args)
            observed: list[list[str]] = []

            def record(arguments: list[str], _cwd: Path, *, check: bool,
                    environment: dict[str, str] | None = None) -> dict[str, object]:
                observed.append(arguments)
                self.assertTrue(check)
                self.assertEqual(environment["CANGJIE_HOME"], str(sdk.root))
                return {"command": arguments, "cwd": "/tmp", "exitCode": 0,
                    "stdout": "", "stderr": ""}

            with patch.object(build_benchmark_driver, "command_record", side_effect=record), \
                    patch.object(build_benchmark_driver, "binary_identity",
                        return_value={"path": "/tmp/main", "bytes": 1,
                            "sha256": "1" * 64}):
                build_benchmark_driver.build_canonical(sdk)
                build_benchmark_driver.build_cli(sdk)
            self.assertEqual(observed, [
                [str(sdk.cjpm), "build", "-j", "1"],
                [str(sdk.cjpm), "build", "-j", "1"],
            ])

    def test_product_build_workspace_excludes_existing_package_targets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            native = Path(temporary) / "native"
            self.write_native_identity_fixture(native)
            with patch.object(build_benchmark_driver, "NATIVE", native):
                workspace = build_benchmark_driver.prepare_build_workspace(
                    Path(temporary) / "markdown")
            self.assertTrue((workspace / "src/engine/parser.cj").is_file())
            self.assertEqual((workspace / "target/native/libmarkdown_scanner.a").read_bytes(),
                b"native-archive")
            self.assertFalse((workspace / "benchmarks/driver/target").exists())
            self.assertFalse((workspace / "tools/markdown/target").exists())

    def test_sdk_extraction_rejects_path_traversal_and_removes_partial_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "sdk.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                add_tar_file(bundle, "../escaped", b"owned")
            destination = root / "fresh"
            with self.assertRaises((tarfile.TarError, RuntimeError)):
                build_benchmark_driver.extract_sdk_archive(archive, destination,
                    "x86_64-unknown-linux-gnu")
            self.assertFalse((root / "escaped").exists())
            self.assertFalse(destination.exists())

    def test_sdk_extraction_accepts_archive_internal_relative_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "sdk.tar.gz"
            with tarfile.open(archive, "w:gz") as bundle:
                add_tar_file(bundle, "cangjie/envsetup.sh", b"#!/bin/sh\n", 0o755)
                add_tar_file(bundle, "cangjie/bin/cjc", b"#!/bin/sh\n", 0o755)
                add_tar_file(bundle, "cangjie/tools/bin/cjpm", b"#!/bin/sh\n", 0o755)
                add_tar_file(bundle,
                    "cangjie/runtime/lib/linux_x86_64_cjnative/libboundscheck.so",
                    b"runtime-library")
                add_tar_symlink(bundle,
                    "cangjie/third_party/llvm/lib/libboundscheck.so",
                    "../../../runtime/lib/linux_x86_64_cjnative/libboundscheck.so")
            destination = root / "fresh"
            sdk = build_benchmark_driver.extract_sdk_archive(archive, destination,
                "x86_64-unknown-linux-gnu")
            link = sdk.root / "third_party/llvm/lib/libboundscheck.so"
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.resolve().read_bytes(), b"runtime-library")
            link.resolve().relative_to(destination)

    def test_sdk_extraction_rejects_external_and_prefix_symlinks(self) -> None:
        for prefix_member in (False, True):
            with self.subTest(prefix_member=prefix_member), \
                    tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "sdk.tar.gz"
                with tarfile.open(archive, "w:gz") as bundle:
                    add_tar_file(bundle, "cangjie/envsetup.sh", b"#!/bin/sh\n", 0o755)
                    add_tar_file(bundle, "cangjie/bin/cjc", b"#!/bin/sh\n", 0o755)
                    add_tar_file(bundle, "cangjie/tools/bin/cjpm", b"#!/bin/sh\n", 0o755)
                    if prefix_member:
                        add_tar_file(bundle, "cangjie/target", b"target")
                        add_tar_symlink(bundle, "cangjie/link", "target")
                        add_tar_file(bundle, "cangjie/link/child", b"escape")
                    else:
                        add_tar_symlink(bundle, "cangjie/link", "../../outside")
                destination = root / "fresh"
                with self.assertRaisesRegex(RuntimeError,
                        "outside the archive|traverses a symlink"):
                    build_benchmark_driver.extract_sdk_archive(archive, destination,
                        "x86_64-unknown-linux-gnu")
                self.assertFalse(destination.exists())

    def test_sdk_extraction_refuses_a_preexisting_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "sdk.tar.gz"
            fake_sdk_archive(archive)
            destination = root / "dirty"
            destination.mkdir()
            marker = destination / "marker"
            marker.write_text("keep", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "must not exist"):
                build_benchmark_driver.extract_sdk_archive(archive, destination,
                    "x86_64-unknown-linux-gnu")
            self.assertEqual(marker.read_text(encoding="utf-8"), "keep")


if __name__ == "__main__":
    unittest.main(verbosity=2)
