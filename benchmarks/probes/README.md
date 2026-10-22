# Editor/cache feasibility probes

These tools reproduce the alternatives in the
[editor/cache decision report](../../docs/reports/editor-cache-cost.md). They are
separate experiments, outside the library and normal consumers. The AST/token
wire handles only the primitive fixture and omits general Markdown grammar
certification. It is an optimistic cost bound, unsuitable as a production reader.

Activate official STS 1.2.0. Use a new disk-backed directory for every build and
measurement, and set `TMPDIR`, `TMP`, and `TEMP` to that task directory. Linux
measurements require `/proc` and `taskset`; choose a CPU from the process's allowed
affinity set. Existing output directories are rejected.

The current tools use the 0.9.2 domain package layout. Historical reports remain
bound to their recorded source; replay them with the tools from that revision.
The current feature, append and public-encode reports use schema 2 and bind all
domain archives and compiler metadata, including the shared identity helper.

Build a copied-source experiment from a source checkout with the current layout:

```sh
python3 benchmarks/probes/build_editor_cost.py \
  --baseline <source-with-current-domain-layout> --output "$TMPDIR/editor-probe"
python3 benchmarks/probes/measure_editor_cost.py \
  --build "$TMPDIR/editor-probe" --output "$TMPDIR/editor-matrix" \
  --cpu <allowed-cpu>
```

The builder checks exact instrumentation boundaries and preserves original and
modified file hashes, SDK/compiler identity, and executable hash in `build.json`.
It never edits production or SDK sources. Source changes can invalidate a patch
boundary; use the retained source instead of changing a historical identity.

The candidate modes are `sorted` (ordered Text boundaries), `bitmap` (byte
boundary bitmap), and `local` (restricted variable-length paragraph/heading edits).
To measure the variable candidate, select `--candidates local --phases
variable-edit`. `--repeat-from <prior-result.json>` fixes batch repetitions before
measurement to `ceil(500ms / prior baseline median)`, capped at 1024. Without it,
each process times one operation. Seven retained pairs and an excluded warmup
are mandatory. Reversing cases and alternating A/B are part of the harness.

Compare actual source reparse, restricted AST restore, and AST+token restore:

```sh
python3 benchmarks/probes/measure_cache_cost.py \
  --build "$TMPDIR/editor-probe" --output "$TMPDIR/cache-matrix" \
  --cpu <allowed-cpu> --candidates ast direct
```

Use `--candidates shared` in a separate output directory for the complete-check
source-digest experiment. The harness requires byte-identical source/shared
wire files before timing. Encode/write, byte-array decode and warm-filesystem
read/decode remain separate. Writes close without `fsync`; no cold-storage cost
is inferred. Calibration fixes batch size from three baseline pilots before A/A
and A/B samples. Counters count constructors and charged work, not heap allocation.

`public_encode_cost.cj` and `measure_public_encode.py` independently measure two
uninstrumented library builds through public APIs:

```sh
python3 benchmarks/probes/measure_public_encode.py \
  --before-library <baseline-library-directory> \
  --after-library <candidate-library-directory> \
  --output "$TMPDIR/public-encode" --cpu <allowed-cpu>
```

`prepare_cache_wire_proof.py --output "$TMPDIR/wire-input.bin"` extracts all
1323 pinned standard inputs plus 48 semantic fixtures without changing the
corpora. Compile `cache_wire_consumer.cj` against each library with `cjc -O2
--obf-seed 0 --import-path <library> -L <library> -lmarkdown`. Create separate
output directories and run each consumer with `<wire-input.bin> <output-directory>`.
Compare all 1371 numbered `.bin` files byte by byte. The consumer also reads and
re-encodes each artifact and checks its semantic output. This is functional wire
proof; source-to-binary offline replay is a separate qualification.

The exporter validates the six immutable measured JSON digests and every retained
sample/input hash before exporting all numeric rows. CPU numbers are omitted
from the public projection; identities and timings are unchanged:

```sh
python3 benchmarks/probes/summarize_editor_cache.py \
  --evidence-root <retained-measurement-root> --output "$TMPDIR/editor-cache-report"
```

Do not replace different historical reports, relax the noise rule after seeing
results, rerun only to force a pass, or relabel these measurements as frozen
release evidence. A new experiment gets new source/build/harness identities.
