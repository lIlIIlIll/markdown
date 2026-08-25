# Concurrency and observability

`MarkdownEngine`, renderer configuration, and `Document` are immutable and may
be shared for concurrent parse/render/read-only work. Every parse and chunked
session owns independent mutable state; one chunked session is not safe for
concurrent calls. There is no mutable global extension registry. Host-code
extensions declare `shareable`; a host must not concurrently reuse a
non-shareable callback instance. `AnnotationStore` is explicitly owner-thread
confined (`threadSafe == false`) and must be externally synchronized if shared.

Metrics are local and opt-in through `parseObserved` and `renderObserved`.
Timing is additionally opt-in with `StatisticsOptions(timing: true)` so the
default hot path does not read a clock. Statistics include byte/line/node/depth,
reference, callback, scan, rendered-node, output-byte, diagnostic, profile and
fingerprint values. They never include document text, destinations, image URLs,
code literals, front matter, thread IDs, absolute paths, or remote telemetry.
