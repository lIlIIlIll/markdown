#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

evidence_dir="$repo_root/target/release-evidence"
evidence_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/markdown-release-evidence.XXXXXX")"
python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" init

finalize_evidence() {
    status=$?
    trap - EXIT
    python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" \
        finalize --gate-exit "$status" || true
    python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" \
        publish --destination "$evidence_dir" || true
    exit "$status"
}
trap finalize_evidence EXIT

run_step() {
    name="$1"
    shift
    log="logs/${name}.log"
    set +e
    "$@" 2>&1 | tee "$evidence_work_dir/$log"
    status=${PIPESTATUS[0]}
    set -e
    python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" record \
        --name "$name" --working-directory "$PWD" --exit-code "$status" --log "$log" -- "$@"
    return "$status"
}

run_step format scripts/check_format.sh
run_step docs python3 scripts/check_docs.py
run_step native-build-tests python3 scripts/test_build_native_scanner.py
run_step api-checker-tests python3 scripts/test_check_public_api.py
run_step api python3 scripts/check_public_api.py
run_step static-check cjpm check
run_step release-evidence-consistency python3 scripts/release_evidence.py
run_step release-evidence-tests python3 scripts/test_release_evidence.py
run_step benchmark-driver-tests python3 scripts/test_build_benchmark_driver.py
run_step build cjpm build
run_step native-build env CC="${CC:-clang}" AR="${AR:-ar}" \
    python3 scripts/build_native_scanner.py --enable
run_step benchmark-driver python3 scripts/build_benchmark_driver.py \
    --mode "${MARKDOWN_BENCHMARK_DRIVER_MODE:-canonical}"
run_step native-fuzz python3 scripts/fuzz_native_scanner.py --runs 10000
run_step benchmark-profile-tests python3 scripts/test_benchmark_input_profiles.py
run_step tests cjpm test --no-color --no-progress \
    --report-path "$repo_root/target/release-tests" --report-format xml

run_step cli-build bash -c 'cd tools/markdown && cjpm build'
run_step cli-smoke scripts/cli_smoke.sh
run_step quickstart bash -c 'cd examples/quickstart && cjpm build && cjpm run --skip-build'
run_step cookbook bash -c 'cd examples/cookbook && cjpm build && cjpm run --skip-build'

export MARKDOWN_DIFFERENTIAL_ROOT="$repo_root/target/differential-tools"
run_step differential-setup scripts/setup_differential_tools.sh
run_step differential python3 scripts/differential_test.py
run_step benchmark-smoke cjpm bench --filter MarkdownReleaseBenchmarks --no-color \
    --report-path "$repo_root/target/release-bench" --report-format csv
run_step evidence-snapshot python3 scripts/release_evidence_bundle.py \
    --output "$evidence_work_dir" snapshot
run_step bundle cjpm bundle --skip-test --skip-lint
python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" finalize --gate-exit 0
python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" \
    publish --destination "$evidence_dir"
run_step release-evidence-ready python3 scripts/release_evidence.py --evidence-ready \
    --execution-manifest "$evidence_dir/manifest.json"
python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" finalize --gate-exit 0
python3 scripts/release_evidence_bundle.py --output "$evidence_work_dir" \
    publish --destination "$evidence_dir"
python3 scripts/release_evidence_bundle.py --output "$evidence_dir" verify
trap - EXIT

printf 'release gate: pass\n'
