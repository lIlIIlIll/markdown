#!/usr/bin/env bash
set -euo pipefail

tools_root="${MARKDOWN_DIFFERENTIAL_ROOT:-/tmp}"
cmark_dir="$tools_root/markdown-cmark-0.31.1"
cmark_gfm_dir="$tools_root/markdown-cmark-gfm-0.29.0.gfm.13"
commonmark_js_dir="$tools_root/markdown-commonmark-js"

clone_commit() {
    local repository="$1"
    local commit="$2"
    local destination="$3"
    if test -d "$destination/.git" && test "$(git -C "$destination" rev-parse HEAD)" = "$commit"; then
        return
    fi
    if test -e "$destination"; then
        printf 'refusing to replace non-matching differential tool path: %s\n' "$destination" >&2
        exit 2
    fi
    git init --quiet "$destination"
    git -C "$destination" remote add origin "$repository"
    git -C "$destination" fetch --quiet --depth 1 origin "$commit"
    git -C "$destination" checkout --quiet --detach FETCH_HEAD
    test "$(git -C "$destination" rev-parse HEAD)" = "$commit"
}

clone_commit https://github.com/commonmark/cmark.git \
    bb3678d7a73cb02d35c8876ecd097072636200a8 "$cmark_dir"
if ! test -x "$cmark_dir/build/src/cmark"; then
    cmake -S "$cmark_dir" -B "$cmark_dir/build" -DCMAKE_BUILD_TYPE=Release -DCMARK_TESTS=OFF
    cmake --build "$cmark_dir/build" --parallel 2
fi

clone_commit https://github.com/github/cmark-gfm.git \
    587a12bb54d95ac37241377e6ddc93ea0e45439b "$cmark_gfm_dir"
if ! test -x "$cmark_gfm_dir/build/src/cmark-gfm"; then
    cmake -S "$cmark_gfm_dir" -B "$cmark_gfm_dir/build" -DCMAKE_BUILD_TYPE=Release \
        -DCMARK_TESTS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    cmake --build "$cmark_gfm_dir/build" --parallel 2
fi

clone_commit https://github.com/commonmark/commonmark.js.git \
    cb2c2303d3550ec6ef28ceb2841f148e8761eebf "$commonmark_js_dir"
if ! test -d "$commonmark_js_dir/node_modules"; then
    npm --prefix "$commonmark_js_dir" install --ignore-scripts --omit=dev --no-package-lock --no-audit --no-fund \
        --save=false entities@3.0.1 mdurl@1.0.1 minimist@1.2.8
fi
test -f "$commonmark_js_dir/lib/index.js"

printf 'differential tools ready\n'
