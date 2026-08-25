#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

scripts/check_format.sh
python3 scripts/test_check_public_api.py
python3 scripts/check_public_api.py
cjpm check
cjpm build
cjpm test --no-color --no-progress --report-path /tmp/markdown-release-tests --report-format xml

(cd tools/markdown && cjpm build)
scripts/cli_smoke.sh
(cd examples/quickstart && cjpm build && cjpm run)

python3 scripts/differential_test.py
cjpm bench --filter MarkdownReleaseBenchmarks --no-color \
    --report-path /tmp/markdown-release-bench --report-format csv
python3 benchmarks/measure.py
cjpm bundle

printf 'release gate: pass\n'
