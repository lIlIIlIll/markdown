#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_log="$repo_root/target/release-evidence/logs/build.log"
if ! test -f "$build_log" || ! grep -q 'llc.*exit code 139' "$build_log"; then
    exit 0
fi

output="$repo_root/target/compiler-diagnostics"
work="$(mktemp -d "${TMPDIR:-/tmp}/markdown-backend-diagnostic.XXXXXX")"
mkdir -p "$output/ir" "$work/source"
trap 'rm -rf "$work"' EXIT
ulimit -c 0

{
    cjc -v
    uname -sr
    getconf GNU_LIBC_VERSION
    printf 'Compiler stack limit (KiB): '
    ulimit -s
    git -C "$repo_root" rev-parse HEAD
} > "$output/environment.txt" 2>&1
git -C "$repo_root" archive HEAD | tar -x -C "$work/source"
python3 - "$work/source/cjpm.toml" "$output/ir" <<'PY'
from pathlib import Path
import json
import re
import sys

manifest = Path(sys.argv[1])
text = manifest.read_text()
pattern = r'(?m)^(\s*compile-option\s*=\s*)"([^"]*)"\s*$'
matches = list(re.finditer(pattern, text))
if len(matches) != 1:
    raise SystemExit("expected one root compile-option")
replacement = matches[0][1] + json.dumps(matches[0][2] + " --save-temps " + sys.argv[2])
manifest.write_text(re.sub(pattern, lambda _: replacement, text))
PY

set +e
(cd "$work/source" && cjpm build -V) > "$output/build.log" 2>&1
build_status=$?
set -e
printf '%s\n' "$build_status" > "$output/build-exit.txt"

ir="$(find "$output/ir" -type f -name markdown.opt.bc -print -quit)"
if test -z "$ir"; then
    printf 'Compiler did not retain markdown.opt.bc\n' > "$output/llc.log"
    exit 0
fi
llc="$CANGJIE_HOME/third_party/llvm/bin/llc"
export LD_LIBRARY_PATH="$(dirname "$llc")/../lib:${LD_LIBRARY_PATH:-}"
command=("$llc" "$ir" --cangjie-pipeline -disable-debug-info-print
    --relocation-model=pic --frame-pointer=non-leaf --stack-trace-format=default
    -mcpu=generic -mattr=-avx --cj-safepoint-outline=false -O2 --filetype=obj
    -o "$output/markdown.o")
set +e
if command -v gdb >/dev/null 2>&1; then
    timeout --kill-after=5s 120s gdb --batch -ex 'set pagination off' -ex run \
        -ex 'thread apply all bt 30' --args "${command[@]}" > "$output/llc.log" 2>&1
else
    timeout --kill-after=5s 120s "${command[@]}" > "$output/llc.log" 2>&1
fi
printf '%s\n' "$?" > "$output/llc-exit.txt"
set -e
