# GFM 0.29-gfm Conformance Report

- Specification source: `github/cmark-gfm`
- Tag: `0.29.0.gfm.0`
- Peeled commit: `b8eb2e00de094999f978e9cb02b1a78d810812d3`
- Vendored fixture: `tests/spec/gfm-0.29/spec.txt`
- Generated suite: `src/generated_gfm_spec_test.cj`
- Profile: `gfm-0.29` for extension sections; pinned 0.29 base profile for base sections
- Comparison: exact HTML, including tagfilter where specified

## Result

| Total | Passed | Failed | Error | Skipped |
| ---: | ---: | ---: | ---: | ---: |
| 671 | 671 | 0 | 0 | 0 |

Validation command:

```text
/home/elliot/.codex/scripts/codex_cangjie_env cjpm test --skip-build --filter Gfm029ConformanceTest --no-color --no-progress --report-path /tmp/markdown-commonmark-report --report-format xml
```

The conformance cases and final unfiltered package run exited 0 on 2026-08-18; the latter passed all 1410 tests with no skips.
