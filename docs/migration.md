# Migration guide

Depend on module `markdown` even though the product/repository is `markdown`. Replace string-to-HTML helpers with `MarkdownEngine → ParseResult.document → renderer`. Choose an explicit versioned profile and HTML policy. Treat spans as UTF-8 bytes and convert through `SourceBuffer` for UTF-16 clients. Code extensions require a manifest, finite rules, renderer coverage, and TCK evidence.

The package uses one native line-scanning helper. Repository consumers get
`libmarkdown_scanner` from the root pre-build hook; standalone consumers must
ship and link that archive beside the Cangjie package. The whole-input helper
does not perform I/O, lock, or call Cangjie methods, but it is not annotated
`@FastNative` because its input-dependent execution time cannot be proven short
and bounded.

The committed FFI declaration and native packed-record storage use UInt64.
Earlier UInt32 benchmark data is historical and superseded; it is not evidence
for the current candidate. Benchmark dependency H keeps this ABI unchanged and
requires a fresh committed-archive no-cast validation; pre-H raw data cannot
satisfy that gate. The committed-H archive now passes the typed UInt64 no-cast
probe and the complete correctness/package gates; its fresh final CommonMark
`6.234490x` and GFM `4.845909x` ratios still fail the `2.5x` limits.
`MD-PERF-002` therefore remains blocked.
