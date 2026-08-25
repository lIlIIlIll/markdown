# markdown CLI

Commands are `render`, `parse`, `format`, `check`, `explain`, and `dialect`.
Profiles are selected with `--profile`; render targets use `--to`.
`format --range start:end` uses UTF-8 byte offsets. `--max-input-bytes N`
applies a real parser limit and is useful for constrained hosts.

Exit codes are stable machine contracts:

| Code | Meaning |
| ---: | --- |
| 0 | Success |
| 1 | Input or parse failure |
| 2 | Invalid arguments |
| 3 | `format --check` found a difference |
| 4 | Security/lint rejection |
| 5 | Extension or dialect failure |
| 6 | Cancellation or budget exhaustion |
| 7 | Internal invariant failure |

`--fault-inject internal` is an explicit test-only fault-injection switch used
by the release smoke suite to verify exit 7, which valid user input must never
produce. It throws through the same structured internal-error mapping and does
not alter parser or renderer behavior.
