# Input, cancellation, and budgets

`MarkdownEngine` accepts String, UTF-8 bytes, `InputStream`, and buffered sessions. `BufferedInputSession` is the explicit name for the execution model: it retains every chunk and produces semantics only at `finish()`. `ChunkedParseSession` remains as the compatibility API with the same contract. Neither API is an incremental parser and neither lowers peak input memory.

## Input execution profiles

| API | Per-parse conversion/copy | Native line scanner |
| --- | --- | --- |
| `parse(String)` | none | no; scans the immutable String in Cangjie |
| `parse(Array<Byte>)` | defensive copy and UTF-8 decode | only with an explicitly injected accelerator |
| `parse(OwnedUtf8Input)` | unsafe caller guarantees valid UTF-8 and transfers unique ownership; benchmark clones once per iteration to create a fresh transferable value, while parsing does not copy or revalidate it | only with an explicitly injected accelerator |
| `parse(InputStream)` | fully buffers then decodes before parsing | only after buffering and only with an explicitly injected accelerator |

The root package has no foreign declaration and no link option. To opt in:

```sh
CC=clang AR=ar python3 scripts/build_native_scanner.py --enable --out-dir target/native
```

The executable consumer adds the target-appropriate archive to its linker and
constructs `MarkdownEngine.builder().build().acceleratedBy(NativeLineScanner())`
after importing `markdown.native.NativeLineScanner`. `nativeScannerEnabled(false)`
can still disable an injected accelerator for parity measurements.
`EngineCapabilities` reports actual availability and effective enablement;
`acceleratedEngine.executionModels()` reports implementation identity and the buffered
execution contracts. The build helper accepts `--target`; it emits `.a`
with Clang/`ar` for Unix and MinGW targets, or `.lib` with `cl`/`lib` for an
MSVC target. Pure builds never invoke the helper toolchain.

| Target family | Build tools | Produced linker asset |
| --- | --- | --- |
| Linux, macOS, Android, HarmonyOS and other Clang targets | target toolchain `CC` and `AR`; pass the target triple through `--target` | `libmarkdown_scanner.a` |
| MinGW | MinGW `CC` and `AR`; pass a `*-windows-gnu` target | `libmarkdown_scanner.a` |
| Windows MSVC | `CC=cl`, `AR=lib`; pass a `*-windows-msvc` target | `markdown_scanner.lib` |

The final executable, not the core package, supplies the matching archive in
its target-specific linker options. Cross-target command generation is covered
by repository tests; release qualification on each platform still requires its
real Cangjie SDK and linker matrix.

`SourcePositionMap` builds line indexes and per-line UTF-16/display checkpoints
once, then uses binary search plus at most one short checkpoint scan per query.
Its display columns are deliberately not terminal cell widths:
`DisplayWidthPolicy.UnicodeScalar` counts every Unicode scalar as one column;
the default `UnicodeScalarWithTabStops` additionally expands tabs. CJK wide
characters, combining marks and ZWJ emoji therefore retain explicit scalar
semantics rather than pretending to implement terminal-width rules.

`ParseLimits.safe()` bounds input, line, depth, nodes, references, table columns, URL, literal, output, capture, and lookahead. `trusted()` raises sizes but never disables overflow/capacity/acyclic/stack/output protections. `OperationBudget` separately bounds scans, delimiters, callbacks, transforms, rendered nodes, and bytes. The host owns wall-clock deadlines via `CancellationToken`.

`SourceBuffer.sourceSlice` and `LiteralStorage.Copy`/`Slice` make ownership
explicit. Plain Text nodes and exact LF code/HTML literals default to
`SourceSlice`; normalized/decoded values use `Copy`. Strict byte decoding no
longer allocates an identity offset table. `detach()` recursively converts
Text/CodeBlock/HtmlBlock slices to owned text. `SourcePositionMap` exposes
byte, UTF-16, and visual positions without modifying source. The normal `parse`
entry throws on hard failure and therefore returns no AST. `tryParse` (and the
compatibility name `parsePartial`) returns a failure result with an empty
Document, `isComplete=false`, `stoppedAt`, `unfinishedPhase`, and structured
errors; it does not return a completed prefix. Partial results are rejected by
artifact creation. `BufferedAsyncHtmlOutputSession` pre-renders the complete
HTML value and only makes sink delivery resumable; the compatibility name
`AsyncHtmlRenderSession` has identical buffered semantics.
