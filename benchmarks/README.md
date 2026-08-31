# Benchmark harness

Run the release benchmark smoke suite with the pinned Cangjie environment:

```sh
/home/elliot/.codex/scripts/codex_cangjie_env cjpm bench --no-color \
  --report-path /tmp/markdown-bench --report-format csv
```

The suite covers CommonMark parse-only, GFM parse plus HTML, CJK/emoji,
tables, tasks, references, code blocks, nested containers, long repeated input,
and extension-shaped delimiter content. `measure.py` measures the `-O2`
process-stable driver and pinned `/tmp/markdown-cmark*-reference-driver`
binaries against corpora generated deterministically by `generate_corpus.py`;
these are test-only tools and are never linked by the library.

Release evidence must record the host, SDK, build mode, corpus digest, raw
samples, geometric mean, peak RSS, and 1–16 MiB scaling. A smoke run proves the
harness works; it does not by itself prove the GA ratios.

The current candidate report is `docs/reports/benchmark.md`; raw samples are
in `docs/reports/benchmark-raw.json`. The measurement script exits non-zero
whenever any GA gate fails.

## Same-language comparison

`compare_markdown4cj.py` pins public
[`markdown4cj`](https://gitcode.com/Cangjie-TPC/markdown4cj/tree/develop) commit
`f43cfb3ae1cd3092d9a8a94332c64815fc4572f9` and `commonmark4cj` commit
`41499e6d6e50efac71db3bba64d5300d251d9c90`. It extracts only the
platform-neutral `markdown4cj` parser core, applies a fail-closed current-SDK
collection-API adapter, and excludes OHOS UI, DevEco, prism4cj, and formula-ffi.

Download the pinned official SDK archive to `/tmp/cangjie-sdk.tar.gz`. The
build helper verifies the digest before any Cangjie build, safely extracts it
into a fresh non-existing directory, and invokes the extracted `cjpm` by its
absolute path for the product driver, CLI, and comparator adapter. Product
builds use a fresh source workspace and never reuse package `target` caches.
An active daily SDK on `PATH` is not used. Run these commands from the
repository root:

```sh
unset LD_PRELOAD LD_LIBRARY_PATH LIBRARY_PATH
unset MARKDOWN_NATIVE_ARFLAGS MARKDOWN_NATIVE_CFLAGS TARGET
unset cjHeapSize cjGCInterval
CC=clang AR=ar python3 scripts/build_native_scanner.py \
  --enable --target x86_64-unknown-linux-gnu
python3 scripts/build_benchmark_driver.py \
  --mode canonical \
  --build-cli \
  --identity-output target/same-language-benchmark/build-identity.json \
  --sdk-url 'https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.1.3.tar.gz&objectKey=6a19349d21f5a8178d6fd22b' \
  --sdk-sha256 2b68905afc466e665ae181595c63f96c18d75fd2c1fb6c6f0cb64e179c28d61a \
  --sdk-archive /tmp/cangjie-sdk.tar.gz \
  --sdk-extract-dir /tmp/fresh-cangjie-sdk-verified \
  --target x86_64-unknown-linux-gnu
python3 benchmarks/compare_markdown4cj.py \
  --tools-root /tmp/markdown-same-language-tools \
  --workspace /tmp/fresh-markdown4cj-adapter \
  --binary-root target/same-language-benchmark/binaries \
  --build-identity target/same-language-benchmark/build-identity.json \
  --output /tmp/markdown4cj-comparison.json \
  --markdown-report /tmp/markdown4cj-comparison.md
```

The canonical command rejects non-empty loader, compiler-search, allocator,
heap, or GC variables from the parent process. The build helper passes an exact
allowlist to `cjc` and `cjpm`: the extracted SDK paths, a private `HOME` and
`TMPDIR`, `C.UTF-8`, and `TZ=UTC`. It does not inherit the host `PATH` or library
search paths.

The destinations passed to `--sdk-extract-dir`, `--workspace`, and
`--binary-root` must not exist. The SDK extraction remains available until comparison finishes so the
adapter uses the same attested toolchain. Comparator source is exported from
the fixed commits' Git objects into the fresh adapter; uncommitted checkout
content cannot enter the build.

The timed comparison is parse-only. Before timing, the harness renders every
timed corpus through both implementations and requires exact CommonMark
spec-HTML byte length and SHA-256 equality. It also requires 12 shared public
CLI behavior cases, 11 deterministic 256 KiB corpora, `-O2`, a pinned CPU, one
warmup and seven alternating samples per side, at least 20% geomean speedup, no
per-corpus regression beyond 10%, and peak RSS no more than 120% of the
comparator. See
`docs/reports/markdown4cj-comparison.md` for the current result.

Both measured processes use `cjHeapSize=2GB` and `cjGCInterval=500ms`. The raw
report records every variable passed to each process and its digest. The only
permitted difference is `LD_LIBRARY_PATH`: the `markdown4cj` process adds the
retained binary root's `libraries/commonmark4cj` directory. The verifier derives both process
environments from the SDK and adapter identities and rejects extra variables,
changed locale values, or an unrecorded loader-path difference.

Schema v5 binds the SDK archive, fresh extraction, absolute compiler/package
manager commands and binary digests, target triple, native scanner manifest and
commands, build flags, source inputs, product binaries, comparator adapter,
semantic digests, raw samples, and independently derived statistics. Native
compiler and archiver identity includes the resolved executable path, executable
bytes and SHA-256, and the complete version command/output. Those subprocesses
receive a minimal explicit environment rather than ambient `os.environ`; the
manifest records that complete environment and its digest. The benchmark process
environment attestation separately binds `PATH`, `LD_LIBRARY_PATH`, `HOME`,
`TMPDIR`, locale, timezone, heap, and GC settings. The verifier rejects schema v4
reports and older build identities instead of upgrading them without a new
measurement.

Fresh product, CLI, comparator, and comparator-dependency manifests add a
build-root-specific `--trimpath`. The identity records both the canonical
manifest and effective trimmed manifest. This removes absolute temporary source
roots from Cangjie outputs; the gate includes a real two-root compiler probe and
the verifier requires byte-identical fresh outputs.

Comparator provenance is independently reconstructed from explicit local Git
inputs. The verifier resolves the fixed `markdown4cj` and `commonmark4cj`
commits and trees, reads all selected blobs, recomputes the core and full
dependency source manifests, reapplies the ordered migrations, and derives the
adapter driver and path-stable manifest. It does not accept reported preflight
booleans as evidence. A checkout, bare object store, or Git bundle can provide
the objects; missing objects fail closed.

The measurement copies the exact product driver, CLI, comparator driver, and
adapter-owned recursive ELF `PT_DYNAMIC`/`DT_NEEDED` closure into the dedicated
`--binary-root`. The pinned adapter currently needs only
`libraries/commonmark4cj/libcommonmark4cj.commonmark.so`; the generated base,
table, and strikethrough DSOs are not retained because the measured executable
does not link them. Reports bind each retained DSO's canonical relative path,
length, SHA-256, and mode. The comparator `LD_LIBRARY_PATH` points at that
retained directory, so timing loads the recorded bytes rather than the temporary
build output. It rejects comparator `DT_RPATH`/`DT_RUNPATH`, so an embedded search
path cannot precede or bypass the retained root. Offline verification reparses
the loader-authoritative program headers (not optional section metadata) and
checks them against the retained, adapter-build, and build-output identities. Missing,
extra, swapped, symlinked, path-escaping, mode-changed, or modified artifacts
fail closed. Verification then rebuilds the native scanner, product driver,
CLI, comparator adapter, and adapter-owned DSO closure in fresh directories
from the retained product/comparator Git objects, retained SDK archive, retained
native compiler/archiver executables, retained Clang resource archive, and the
native tools' retained ELF loader plus recursive DSO closure. Rebuild commands
invoke those tools only through the retained loader and library root. Every
rebuilt byte must equal the retained measured byte;
synchronized edits to both a binary and its report digest therefore fail.

Repository provenance is derived from Git objects, not trusted report strings.
The verifier resolves the declared ref to its commit and tree, reads the declared
commit's product and harness blobs, recomputes their digests, and binds both build
identities to that snapshot. `--require-current-product` additionally requires the
declared commit and tree to equal the retained product source's `HEAD`; a checkout
must also be clean. Missing Git objects, historical ancestor substitution, ambient
`GIT_*` redirection, or a missing product source fail closed.

Verify the committed raw samples, all derived statistics, the generated report,
the product tree, the corpus, and the harness with:

```sh
git bundle create /tmp/markdown-product.bundle HEAD
python3 benchmarks/compare_markdown4cj.py \
  --source /tmp/markdown-same-language-tools/markdown4cj \
  --commonmark4cj-source /tmp/markdown-same-language-tools/commonmark4cj \
  --product-source /tmp/markdown-product.bundle \
  --binary-root target/same-language-benchmark/binaries \
  --sdk-archive target/same-language-benchmark/toolchain/cangjie-sdk-linux-x64-1.1.3.tar.gz \
  --verify-report docs/reports/markdown4cj-comparison-raw.json \
  --markdown-report docs/reports/markdown4cj-comparison.md \
  --require-current-product
```

GitHub Actions runs that verification and a fresh paired measurement in
`Same-language benchmark (current-1.1.3)`. The check is required before a pull
request can merge into `main`; its raw samples, generated report, retained product
Git bundle, minimal bundles for both pinned comparator commits, retained SDK
archive, native tool/resource inputs, measured executables, and runtime DSO closure are uploaded even when
the job fails. Verification can therefore run from relocated evidence without
consulting the verifier checkout's `.git` directory or the network. Directory
Git inputs must be the exact worktree or bare-repository root; nested paths,
symlinked roots, and external `.git` indirection fail closed.
