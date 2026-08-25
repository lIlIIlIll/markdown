#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
format_tmp="$(mktemp -d)"
trap 'rm -rf "$format_tmp"' EXIT

cjfmt -d "$repo_root/src" -o "$format_tmp"
for source_file in "$repo_root"/src/*.cj; do
    diff -q "$source_file" "$format_tmp/src/$(basename "$source_file")"
done

check_one() {
    local source_file="$1"
    local output_file="$format_tmp/$(basename "$(dirname "$(dirname "$source_file")")")-$(basename "$source_file")"
    cjfmt -f "$source_file" -o "$output_file"
    diff -q "$source_file" "$output_file"
}

check_one "$repo_root/tools/markdown/src/main.cj"
check_one "$repo_root/examples/quickstart/src/main.cj"
check_one "$repo_root/benchmarks/driver/src/main.cj"

printf 'cjfmt check: pass\n'
