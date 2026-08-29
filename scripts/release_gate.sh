#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

scripts/check_format.sh
python3 scripts/check_docs.py
python3 scripts/test_build_native_scanner.py
python3 scripts/test_check_public_api.py
python3 scripts/check_public_api.py
cjpm check
python3 scripts/release_evidence.py
python3 scripts/test_release_evidence.py
cjpm build
CC="${CC:-clang}" AR="${AR:-ar}" python3 scripts/build_native_scanner.py --enable
(cd benchmarks/driver && cjpm build)
python3 scripts/fuzz_native_scanner.py --runs 10000
python3 scripts/test_benchmark_input_profiles.py
cjpm test --no-color --no-progress --report-path /tmp/markdown-release-tests --report-format xml

(cd tools/markdown && cjpm build)
scripts/cli_smoke.sh
(cd examples/quickstart && cjpm build && cjpm run --skip-build)
(cd examples/cookbook && cjpm build && cjpm run --skip-build)

export MARKDOWN_DIFFERENTIAL_ROOT="$repo_root/target/differential-tools"
scripts/setup_differential_tools.sh
python3 scripts/differential_test.py
cjpm bench --filter MarkdownReleaseBenchmarks --no-color \
    --report-path /tmp/markdown-release-bench --report-format csv
cjpm bundle
python3 scripts/release_evidence.py --evidence-ready

printf 'release gate: pass\n'
