#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cli="$repo_root/tools/markdown/target/release/bin/main"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

printf '# CLI\n\n<script>x</script>\n' > "$tmp_dir/input.md"
"$cli" render --to safe-html < "$tmp_dir/input.md" > "$tmp_dir/rendered.html"
grep -F '<h1>CLI</h1>' "$tmp_dir/rendered.html" >/dev/null
grep -F '&lt;script&gt;x&lt;/script&gt;' "$tmp_dir/rendered.html" >/dev/null

"$cli" parse < "$tmp_dir/input.md" > "$tmp_dir/ast.json"
grep -F '"debug":true' "$tmp_dir/ast.json" >/dev/null

set +e
printf '# H' | "$cli" format --check >/dev/null
format_status=$?
printf '[x](javascript:alert)' | "$cli" check >/dev/null
security_status=$?
printf 'cancel' | "$cli" render --cancel-before-start >/dev/null 2>&1
cancel_status=$?
"$cli" dialect validate --spi-version 999 >/dev/null 2>&1
dialect_status=$?
printf 'too large' | "$cli" parse --max-input-bytes 1 >/dev/null 2>&1
input_status=$?
"$cli" parse --fault-inject internal </dev/null >/dev/null 2>&1
internal_status=$?
"$cli" unknown >/dev/null 2>&1
argument_status=$?
set -e

test "$format_status" -eq 3
test "$security_status" -eq 4
test "$cancel_status" -eq 6
test "$dialect_status" -eq 5
test "$input_status" -eq 1
test "$internal_status" -eq 7
test "$argument_status" -eq 2

test "$(printf '#  x' | "$cli" format --range 0:4)" = '# x'

"$cli" dialect fingerprint > "$tmp_dir/fingerprint"
test "$(wc -c < "$tmp_dir/fingerprint")" -eq 65

printf 'cli smoke: pass\n'
