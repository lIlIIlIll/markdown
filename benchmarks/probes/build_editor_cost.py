#!/usr/bin/env python3
"""Build an isolated, instrumented editor/CST experiment without SDK changes.

The candidate switch lives only in the copied source. Production parser and
public API files are never modified by this script.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "benchmarks"))
from benchmark_identity import benchmark_product_tree_sha256


def replace(text: str, old: str, new: str, count: int = 1) -> str:
    if text.count(old) != count:
        raise ValueError(f"instrumentation boundary changed: {old[:60]}")
    return text.replace(old, new)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, help="Clean source checkout using the current domain package layout")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    baseline = args.baseline.resolve() if args.baseline else ROOT
    product_tree = benchmark_product_tree_sha256(baseline)
    instrumenter_hash = sha(Path(__file__))
    source = output / "src"
    source.mkdir()
    originals = {}
    for path in sorted((baseline / "src").rglob("*.cj")):
        if not path.name.endswith("_test.cj"):
            relative = path.relative_to(baseline / "src")
            destination = source / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            originals[path.relative_to(baseline).as_posix()] = sha(path)
    manifest = (baseline / "cjpm.toml").read_text().replace('output-type = "static"', 'output-type = "executable"')
    (output / "cjpm.toml").write_text(manifest)
    probe = ROOT / "benchmarks/probes/editor_cost.cj"
    probe_hash = sha(probe)
    shutil.copy2(probe, source / "editor_cost_probe.cj")
    variable_probe = ROOT / "benchmarks/probes/variable_edit.cj"
    variable_probe_hash = sha(variable_probe)
    shutil.copy2(variable_probe, source / "variable_edit_probe.cj")
    cache_probe = ROOT / "benchmarks/probes/cache_restore.cj"
    cache_probe_hash = sha(cache_probe)
    shutil.copy2(cache_probe, source / "cache_restore_probe.cj")

    # Instrumentation state is a module-private leaf package, independent of the AST.
    controller = source / "editor_cost_probe.cj"
    controller_text = controller.read_text()
    import re
    counters = re.findall(r"^var probe\w+[^\n]*", controller_text, flags=re.M)
    controller_text = re.sub(r"^var probe\w+[^\n]*\n", "", controller_text, flags=re.M)
    helpers = []
    for name in ("probeTextBoundaries", "probeTextByte", "probeTextBitmap"):
        match = re.search(r"^func " + name + r"\([\s\S]*?^}\n", controller_text, flags=re.M)
        if match is None:
            raise ValueError(f"missing editor instrumentation helper: {name}")
        helpers.append(match.group().replace("func ", "protected func ", 1))
        controller_text = controller_text[:match.start()] + controller_text[match.end():]
    state = source / "probe"
    state.mkdir()
    (state / "state.cj").write_text("protected package markdown.probe\n\n" +
        "\n".join("protected " + line for line in counters) + "\n")
    (source / "editor" / "probe_helpers.cj").write_text("package markdown.editor\n\n" +
        "import markdown.core.*\nimport std.collection.*\nimport std.sort.sort\n\n" + "\n".join(helpers))
    for name in ("editor_cost_probe.cj", "variable_edit_probe.cj", "cache_restore_probe.cj"):
        target = source / name
        text = controller_text if name == "editor_cost_probe.cj" else target.read_text()
        text = text.replace("package markdown\n", "package markdown\n\nimport markdown.probe.*\n", 1)
        if name == "cache_restore_probe.cj":
            text = text.replace("package markdown\n", "package markdown\nimport markdown.editor.probeTextByte\n", 1)
        target.write_text(text)
    for relative, names in {
        "core/arena.cj": "probeAstRecords",
        "core/limits.cj": "probeChargedScans",
        "artifact/binary_artifact.cj": "probeSharedDigests",
        "editor/editor.cj": "{probeSyntaxTokens, probeSyntaxNodes, probeCstBytes, probeMapVisits, probeCoalesceCst, probeBitmapCst}",
    }.items():
        target = source / relative
        text = target.read_text()
        at = text.index("\n") + 1
        target.write_text(text[:at] + "\nimport markdown.probe." + names + "\n" + text[at:])

    path = source / "core" / "arena.cj"
    text = replace(path.read_text(), "        localIdentityValue = UInt32(localIdentity)",
        "        probeAstRecords++\n        localIdentityValue = UInt32(localIdentity)")
    path.write_text(text)
    path = source / "core" / "limits.cj"
    text = replace(path.read_text(), "        remainingScanSteps -= steps",
        "        probeChargedScans += steps\n        remainingScanSteps -= steps")
    path.write_text(text)
    path = source / "artifact" / "binary_artifact.cj"
    text = path.read_text()
    text = replace(text, "binaryWriteString(out, Sha256.digestBytes(originalBytes))",
        "binaryWriteString(out, if (probeSharedDigests) { snapshot.sourceDigest } else { Sha256.digestBytes(originalBytes) })")
    text = replace(text, "binaryWriteString(out, Sha256.digest(snapshot.result.source.text()))",
        "binaryWriteString(out, if (probeSharedDigests) { snapshot.sourceDigest } else { Sha256.digest(snapshot.result.source.text()) })")
    text = replace(text, "        binaryWriteString(out, Sha256.digest(snapshot.syntaxTree.losslessText()))", """        let cstText = snapshot.syntaxTree.losslessText()
        if (probeSharedDigests && cstText != snapshot.result.source.text()) {
            throw MarkdownException(MarkdownErrorCode.InvalidArtifact, "snapshot CST does not match source", phase: "artifact_encode")
        }
        binaryWriteString(out, if (probeSharedDigests) { snapshot.sourceDigest } else { Sha256.digest(cstText) })""")
    text = replace(text, "            let sourceBytes = source.toArray()", """            let sourceBytes = source.toArray()
            let verifiedSourceDigest = if (probeSharedDigests) { Sha256.digestBytes(sourceBytes) } else { "" }""")
    text = replace(text, "if (originalBytesDigest != Sha256.digestBytes(sourceBytes))",
        "if (originalBytesDigest != (if (probeSharedDigests) { verifiedSourceDigest } else { Sha256.digestBytes(sourceBytes) }))")
    text = replace(text, "if (decodedTextDigest != Sha256.digest(source))",
        "if (decodedTextDigest != (if (probeSharedDigests) { verifiedSourceDigest } else { Sha256.digest(source) }))")
    text = replace(text, "            if (cstDigest != Sha256.digest(snapshot.syntaxTree.losslessText())) {", """            let cstText = snapshot.syntaxTree.losslessText()
            if (probeSharedDigests && cstText != snapshot.result.source.text()) {
                return BinaryArtifactLoadResult.CacheMiss("CST digest")
            }
            if (cstDigest != (if (probeSharedDigests) { snapshot.sourceDigest } else { Sha256.digest(cstText) })) {""")
    path.write_text(text)
    path = source / "editor" / "editor.cj"
    text = path.read_text()
    token_start = text.index("public class SyntaxToken {")
    token_end = text.index("\n}\n", token_start)
    section = replace(text[token_start:token_end], "        this.kind = kind", "        probeSyntaxTokens++\n        this.kind = kind")
    text = text[:token_start] + section + text[token_end:]
    node_start = text.index("public class SyntaxNode {")
    node_end = text.index("\n}\n", node_start)
    section = replace(text[node_start:node_end], "        this.kind = kind", "        probeSyntaxNodes++\n        this.kind = kind", 2)
    text = text[:node_start] + section + text[node_end:]
    text = replace(text, "        let value = source.text()\n        let tokens = ArrayList<SyntaxToken>()", """        let value = source.text()
        let boundaries: Array<Int64> = if (probeCoalesceCst && !probeBitmapCst) { probeTextBoundaries(source, document) } else { [] }
        let boundaryBits: Array<Bool> = if (probeBitmapCst) { probeTextBitmap(source, document) } else { [] }
        var boundaryIndex: Int64 = 0
        let tokens = ArrayList<SyntaxToken>()""")
    text = replace(text, "            let start = index\n            let kind: SyntaxKind", """            let start = index
            while (boundaryIndex < boundaries.size && boundaries[boundaryIndex] <= index) { boundaryIndex++ }
            let kind: SyntaxKind""")
    text = replace(text, """                index = editorNextRune(value, index)
                kind = classifySyntaxByte(value[start], lineStart)
                lineStart = false""", """                index = editorNextRune(value, index)
                kind = classifySyntaxByte(value[start], lineStart)
                if (probeCoalesceCst) {
                    if (let SyntaxKind.Text <- kind) {
                        if (probeBitmapCst) {
                            while (index < value.size && !boundaryBits[index] && probeTextByte(value[index])) {
                                index = editorNextRune(value, index)
                            }
                        } else {
                            let limit = boundaries[boundaryIndex]
                            while (index < limit && probeTextByte(value[index])) { index = editorNextRune(value, index) }
                        }
                    }
                }
                lineStart = false""")
    text = replace(text, "            tokens.add(\n                SyntaxToken(kind, value[start..index],", "            probeCstBytes += index - start\n            tokens.add(\n                SyntaxToken(kind, value[start..index],")
    text = replace(text, "                    while (tokenIndex < end) {\n                        if (length < ownerLengths[tokenIndex])", "                    while (tokenIndex < end) {\n                        probeMapVisits++\n                        if (length < ownerLengths[tokenIndex])")
    text = replace(text, "    private init(source: SourceBuffer, root: SyntaxNode, tokenArena: Array<SyntaxToken>, document: ?Document)",
        "    protected init(source: SourceBuffer, root: SyntaxNode, tokenArena: Array<SyntaxToken>, document: ?Document)")
    text, changed = re.subn(r"^(?:private|internal|protected) func syntaxRootForDocument\(",
        "protected func syntaxRootForDocument(", text, flags=re.M)
    if changed != 1:
        raise ValueError("syntax root instrumentation boundary changed")
    text = replace(text, "        sourceDigest = Sha256.digestBytes(result.source.text().toArray())\n    }", """        sourceDigest = Sha256.digestBytes(result.source.text().toArray())
    }

    protected init(engine: MarkdownEngine, version: Int64, result: ParseResult, restoredSyntax!: SyntaxTree) {
        restoredSyntax.requireDocument(result.document)
        this.engine = engine
        this.version = version
        this.result = result
        syntaxTree = restoredSyntax
        syntaxMap = SyntaxToAstMap(restoredSyntax, result.document)
        sourceDigest = Sha256.digestBytes(result.source.text().toArray())
    }""")
    path.write_text(text)
    tool = shutil.which("cjpm")
    if tool is None:
        parser.error("activate the official STS 1.2.0 SDK first")
    compiler = shutil.which("cjc")
    version = subprocess.check_output([compiler, "--version"], text=True)
    if "1.2.0" not in version:
        parser.error("official STS 1.2.0 is required")
    environment = os.environ | {"TMPDIR": str(output), "TMP": str(output), "TEMP": str(output)}
    with (output / "build.log").open("w") as log:
        result = subprocess.run([tool, "build"], cwd=output, env=environment, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise ValueError("instrumented build failed; inspect build.log")
    if benchmark_product_tree_sha256(baseline) != product_tree or sha(Path(__file__)) != instrumenter_hash or sha(probe) != probe_hash or sha(variable_probe) != variable_probe_hash or sha(cache_probe) != cache_probe_hash:
        raise ValueError("production source or instrumentation changed during the build")
    metadata = {"schema": "markdown.editor-cost-build/1", "productionTreeSha256": product_tree,
        "probeSourceSha256": probe_hash, "instrumenterSha256": instrumenter_hash, "originalFiles": originals,
        "variableEditProbeSha256": variable_probe_hash,
        "cacheRestoreProbeSha256": cache_probe_hash,
        "sdk": version.strip(), "cjcSha256": sha(Path(compiler).resolve()), "cjpmSha256": sha(Path(tool).resolve()),
        "instrumentedFiles": {str(path.relative_to(output)): sha(path) for path in sorted(source.rglob("*.cj"))},
        "manifestSha256": sha(output / "cjpm.toml"), "executableSha256": sha(output / "target/release/bin/main"),
        "scope": "private constructor/charged-work counters and runtime CST candidate; no SDK or production edits"}
    (output / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print("PASS isolated editor cost build", flush=True)


if __name__ == "__main__":
    main()
