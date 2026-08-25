# Release benchmark report

Status: **FAIL**

- CommonMark parse-only geometric mean ratio vs cmark: `6.98x` (limit `2.5x`).
- GFM parse+HTML geometric mean ratio vs cmark-gfm: `5.99x` (limit `2.5x`).
- Ordinary representative ratios: CommonMark `3.51x`, GFM `2.71x` (limit `5x`).
- 1–16 MiB log-log slope: `0.924` (limit `1.35`).
- Maximum adjacent doubling ratio: `1.956` (limit `3.0`).
- Pathological delimiter 64–512 KiB log-log slope: `0.963` (limit `1.35`).
- Pathological delimiter maximum adjacent doubling ratio: `3.528` (informational; process startup and allocator thresholds make a single doubling noisy).
- 10 MiB extra peak RSS: `80120 KiB` (limit `81920 KiB`).

- SourceMap time overhead vs parse+HTML: `112.2%`.
- CST/snapshot time overhead vs parse-only: `1039.0%`.

Raw samples, corpus digests, tool commits, CPU pin, and environment are in `benchmark-raw.json`.
