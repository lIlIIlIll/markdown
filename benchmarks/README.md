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

Prepare the current SDK, build the two product drivers, and let the harness
create exact comparator checkouts:

```sh
cangjie_env
CC=clang AR=ar python3 scripts/build_native_scanner.py --enable
python3 scripts/build_benchmark_driver.py --mode canonical
(cd tools/markdown && cjpm build)
python3 benchmarks/compare_markdown4cj.py \
  --tools-root /tmp/markdown-same-language-tools \
  --workspace /tmp/fresh-markdown4cj-adapter \
  --output /tmp/markdown4cj-comparison.json \
  --markdown-report /tmp/markdown4cj-comparison.md
```

The destination passed to `--workspace` must not exist. The harness refuses to
replace a comparator checkout whose commit or working tree differs from the
pinned identity.

The comparison is intentionally parse-only: `markdown4cj` renders HarmonyOS
`NodeView`, not an HTML string equivalent to this repository's renderer. A
valid result requires 12 shared CommonMark HTML behavior cases, 11 deterministic
256 KiB corpora, `-O2`, a pinned CPU, one warmup and seven alternating samples
per side, at least 20% geomean speedup, no per-corpus regression beyond 10%, and
peak RSS no more than 120% of the comparator. See
`docs/reports/markdown4cj-comparison.md` for the current result.

Verify the committed raw samples, all derived statistics, the generated report,
the product tree, the corpus, and the harness with:

```sh
python3 benchmarks/compare_markdown4cj.py \
  --verify-report docs/reports/markdown4cj-comparison-raw.json \
  --markdown-report docs/reports/markdown4cj-comparison.md \
  --require-current-product
```

GitHub Actions runs that verification and a fresh paired measurement in
`Same-language benchmark (current-1.1.3)`. The check is required before a pull
request can merge into `main`; its raw samples and generated report are uploaded
even when the job fails.
