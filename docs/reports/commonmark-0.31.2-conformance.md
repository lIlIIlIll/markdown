# CommonMark 0.31.2 Conformance Report

- Specification source: `commonmark/commonmark-spec`
- Tag: `0.31.2`
- Commit: `9103e341a973013013bb1a80e13567007c5cef6f`
- Vendored fixture: `tests/spec/commonmark-0.31.2/spec.txt`
- Generated suite: `src/generated_commonmark_spec_test.cj`
- Profile: `commonmark-0.31.2`
- Comparison: exact HTML

## Result

| Total | Passed | Failed | Error | Skipped |
| ---: | ---: | ---: | ---: | ---: |
| 652 | 652 | 0 | 0 | 0 |

Validation command:

```text
/home/elliot/.codex/scripts/codex_cangjie_env cjpm test --skip-build --filter CommonMark0312ConformanceTest --no-color --no-progress --report-path /tmp/markdown-commonmark-report --report-format xml
```

The conformance cases and final unfiltered package run exited 0 on 2026-08-18; the latter passed all 1410 tests with no skips.
