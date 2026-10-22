# Benchmark harness

The [editor/cache decision report](../docs/reports/editor-cache-cost.md) records
the measured alternatives and their adoption decisions. Reproduction tools and
their restricted scope are documented in [probes/README.md](probes/README.md).

The [feature cost report](../docs/reports/feature-cost.md) separates explicit
extension switches, source-reparse cache paths, actual backend startup, Ready
cache hits, and prepared rendering. `measure_features.py` consumes an explicitly
installed runtime; it does not prepare or download one. Its 20ms process-tree RSS
samples include setup and shared pages and are separate from Cangjie VmHWM.

The separate [append/output workload report](../docs/reports/append-cost.md)
records per-feed latency, first closed block, finish, charged work and a Linux
RSS checkpoint. Run `measure_append.py` against an explicitly built library and
retain its complete output directory. `summarize_append.py` verifies every raw
sample digest and exports the report without local paths or CPU numbering.
This workload report does not replace the frozen release gates below.

Activate the official Cangjie STS 1.2.0 SDK, then run the release benchmark smoke suite:

```sh
cjpm bench --no-color \
  --report-path target/benchmark-smoke --report-format csv
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

Create a private, disk-backed task directory and download the pinned official
SDK archive there. The examples below use `$TMPDIR`; set `TMP` and `TEMP` to
the same directory. The
build helper verifies the digest before any Cangjie build, safely extracts it
into a fresh non-existing directory, and invokes the extracted `cjpm` by its
absolute path for the product driver, CLI, and comparator adapter. Product
builds use a fresh source workspace and never reuse package `target` caches.
An active daily SDK on `PATH` is not used. Run these commands from the
repository root:

```sh
umask 077
mkdir -p "$HOME/.cache/agent-tmp"
export TMPDIR="$(mktemp -d -p "$HOME/.cache/agent-tmp" markdown-benchmark.XXXXXXXX)"
export TMP="$TMPDIR" TEMP="$TMPDIR"
curl --fail --location --retry 3 \
  'https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.2.0.tar.gz&objectKey=6ab1e26eece1f87ff5befa73' \
  --output "$TMPDIR/cangjie-sdk.tar.gz"
unset LD_PRELOAD LD_LIBRARY_PATH LIBRARY_PATH
unset MARKDOWN_NATIVE_ARFLAGS MARKDOWN_NATIVE_CFLAGS TARGET
unset cjHeapSize cjGCInterval
CC=clang AR=ar python3 scripts/build_native_scanner.py \
  --enable --target x86_64-unknown-linux-gnu
python3 scripts/build_benchmark_driver.py \
  --build-cli \
  --identity-output target/same-language-benchmark/build-identity.json \
  --sdk-url 'https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.2.0.tar.gz&objectKey=6ab1e26eece1f87ff5befa73' \
  --sdk-sha256 8c5fd944cd9cc51ee63d4a240e3ecc4f540345dae1468e8b47c927ecf2ba998f \
  --sdk-archive "$TMPDIR/cangjie-sdk.tar.gz" \
  --sdk-extract-dir "$TMPDIR/fresh-cangjie-sdk-verified" \
  --target x86_64-unknown-linux-gnu
python3 benchmarks/compare_markdown4cj.py \
  --tools-root "$TMPDIR/markdown-same-language-tools" \
  --workspace "$TMPDIR/fresh-markdown4cj-adapter" \
  --binary-root target/same-language-benchmark/binaries \
  --build-identity target/same-language-benchmark/build-identity.json \
  --output "$TMPDIR/markdown4cj-comparison.json" \
  --markdown-report "$TMPDIR/markdown4cj-comparison.md"
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

Both measured processes use `cjHeapSize=2GB`, `cjGCInterval=500ms`, and the same
execution environment. The comparator dependency is statically linked into the
adapter, so it needs no extra `LD_LIBRARY_PATH`. The verifier derives both process
environments from the SDK identity and rejects any per-side difference, extra
variable, or changed locale value.

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

Fresh product, CLI, comparator, and comparator-dependency manifests use a
build-root-specific `--trimpath`, fixed `--obf-seed 0`, and one `cjpm` build job.
The comparator's pinned dependency manifest is normalized to a non-incremental
static build. The identity records both canonical and effective manifests. These
settings remove temporary source roots and nondeterministic dynamic-library
layout; the gate includes real independent rebuilds and requires byte-identical
fresh outputs.

Comparator provenance is independently reconstructed from explicit local Git
inputs. The verifier resolves the fixed `markdown4cj` and `commonmark4cj`
commits and trees, reads all selected blobs, recomputes the core and full
dependency source manifests, reapplies the ordered migrations, and derives the
adapter driver and path-stable manifest. It does not accept reported preflight
booleans as evidence. A checkout, bare object store, or Git bundle can provide
the objects; missing objects fail closed.

The measurement copies the exact product driver, CLI, and statically linked
comparator driver into the dedicated `--binary-root`. The report requires an
empty comparator-owned runtime-library closure; an injected DSO, search-path
difference, extra artifact, symlink, or path escape fails closed. Offline
verification reparses loader-authoritative program headers rather than optional
section metadata, then rebuilds the native scanner, product driver, CLI, and
comparator adapter in fresh directories
from the retained product/comparator Git objects, retained SDK archive, retained
native compiler/archiver executables, retained Clang resource archive, and the
native tools' retained ELF loader plus recursive DSO closure. Rebuild commands
invoke those tools only through the retained loader and library root. Every
rebuilt executable byte must equal the retained measured byte;
synchronized edits to both a binary and its report digest therefore fail.

Repository provenance is derived from Git objects, not trusted report strings.
The report records the measured commit as an immutable full object ID. The verifier
resolves that ID to its commit and tree, reads every product and harness blob,
recomputes their digests, and binds both build identities to that snapshot.
`--require-current-product` additionally compares all product/build inputs and
harness blobs with the retained product source's `HEAD`; a checkout must also be
clean. A later commit that only retains reports remains verifiable. Changes to
product or harness inputs, missing Git objects, ambient `GIT_*` redirection, or a
missing product source fail closed.

Verify the committed raw samples, all derived statistics, the generated report,
the product tree, the corpus, and the harness with:

```sh
git bundle create /tmp/markdown-product.bundle HEAD
python3 benchmarks/compare_markdown4cj.py \
  --source /tmp/markdown-same-language-tools/markdown4cj \
  --commonmark4cj-source /tmp/markdown-same-language-tools/commonmark4cj \
  --product-source /tmp/markdown-product.bundle \
  --binary-root target/same-language-benchmark/binaries \
  --sdk-archive target/same-language-benchmark/toolchain/cangjie-sdk-linux-x64-1.2.0.tar.gz \
  --verify-report docs/reports/markdown4cj-comparison-raw.json \
  --markdown-report docs/reports/markdown4cj-comparison.md \
  --require-current-product
```

GitHub Actions runs that verification and a fresh paired measurement in
`Same-language benchmark (sts-1.2.0)`. The check is required before a pull
request can merge into `main`; its raw samples, generated report, retained product
Git bundle, minimal bundles for both pinned comparator commits, retained SDK
archive, native tool/resource inputs, measured executables, and empty comparator runtime-closure identity are uploaded even when
the job fails. The artifact contains `same-language-benchmark.tar` to preserve
executable permissions. Verification can therefore run from relocated evidence without
consulting the verifier checkout's `.git` directory or the network. Directory
Git inputs must be the exact worktree or bare-repository root; nested paths,
symlinked roots, and external `.git` indirection fail closed.

The committed report uses its own measured inputs. `.github/benchmark-evidence.json`
pins the CI run, artifact ID, archive digest and raw-report digest. A `main` push
downloads that artifact and verifies the committed report against those retained
binaries and the current product and harness. It never substitutes the new
runner's binaries for the committed measurement. Missing, expired or mismatched
artifacts fail verification. Retain the downloaded archive for offline checks:

```sh
python3 scripts/verify_committed_benchmark.py \
  --artifact-archive <evidence.zip> --work-dir "$TMPDIR/committed-evidence"
```

This performs the same complete source-to-binary rebuild. The work directory
must not already exist. The CI archive is retained for 90 days; keep an offline
copy before it expires.

Schema v6 also retains the system startup objects and link-library closure under
`binaries/toolchain/cangjie-link-inputs`. The attested builder captures these
inputs once, resolves linker-script references, and records every file's bytes,
mode and digest. Rebuilds validate this set and regenerate a launcher for the
official SDK's LLD. Both the compiler's sysroot and the linker's library search
use the retained set. They do not substitute the verifier host's linker or GCC
startup objects. Compiler and package-manager jobs are both fixed at one; a
single `cjpm` job alone does not fix the compiler's default parallel code generation.
LLVM linker and thin-LTO worker counts are also fixed at one. The retained set
includes the SDK tools' external C++ runtime libraries. Controlled build and
execution environments load validated copies from a sibling of the extracted
SDK, preserving the official SDK files.

Schema v5 reports lack these inputs and must be measured again. The input
identity rejects symlinks, extra or missing files, path traversal, unsupported
linker-script directives, unresolved references, and retention-limit violations.
