# Migration guide

## 0.8 to 0.9 (pre-GA breaking reset)

0.9 deliberately resets the pre-GA compatibility surface so the parser can
move to a document-owned arena without carrying the 0.8 object graph as a
runtime adapter. Consumers must rebuild against the 0.9 API snapshot; binary
artifacts and cached fingerprints from 0.8 are not compatible.

The final pre-GA CodeCheck qualification also renames the public
`NodeKind.Document` and `SyntaxKind.Document` variants to
`NodeKind.DocumentNode` and `SyntaxKind.DocumentNode`. This avoids the Cangjie
enum-sugar collision with the public `Document` type. Match expressions and
extension or editor code that inspect the root node must use the new variant
names; the document object type and its behavior are unchanged.

Extension authors must implement `InlineParserSpi.triggerBytes`. The returned
byte list is the complete set of UTF-8 leading bytes that may start the rule.
It must be non-empty and contain no duplicates. The compiler rejects invalid
declarations, and the parser does not invoke the SPI at other byte positions.
Syntax DSL rules derive the same dispatch information from their opener.

The following 0.9 contracts are staged in dependency order and are not
available merely because the package version changed:

1. `Document` owns the node/child arenas and public nodes become stable value
   views; parsed origin is derived from the stored span.
2. artifact schema 2 binds the arena layout and original input identity;
   schema 1 artifacts are rejected rather than adapted.
3. fused HTML is selected only through an explicit execution policy. A
   required fused path fails closed when processors or extensions need a full
   AST; it never silently drops capabilities.

The source Event API now uses `MarkdownSourceEvent` values that cannot retain
`Document` or `NodeRef`. `ResolvedEventMode` performs two source passes and
emits final reference semantics from transient parser blocks;
`RawBlockEventSession` incrementally emits only blocks proven closed and marks
its events as non-final. The removed 0.8 AST-walk event adapter is not restored,
so consumers must migrate to `parseEvents`, `emitEvents`, or
`newRawBlockEventSession` instead of expecting AST objects in event values.

Until each staged contract has implementation and test evidence, its
requirement remains non-pass in `.agent/requirements.yaml`.

Depend on module `markdown` even though the product/repository is `markdown`. Replace string-to-HTML helpers with `MarkdownEngine → ParseResult.document → renderer`. Choose an explicit versioned profile and HTML policy. Treat spans as UTF-8 bytes and convert through `SourceBuffer` for UTF-16 clients. Code extensions require a manifest, finite rules, renderer coverage, and TCK evidence.

The package uses one native line-scanning helper. Repository consumers get
`libmarkdown_scanner` from the root pre-build hook; standalone consumers must
ship and link that archive beside the Cangjie package. The whole-input helper
does not perform I/O, lock, or call Cangjie methods, but it is not annotated
`@FastNative` because its input-dependent execution time cannot be proven short
and bounded.

The committed FFI declaration and native packed-record storage use UInt64.
The parser consumes the valid prefix returned by `scanLineRecords` without
trimming the accelerator-owned capacity array. Existing accelerators remain
source-compatible because the interface default adapts `scanLines`; custom
implementations may override the new method after validating their returned
count is within both the array size and requested capacity.
Earlier UInt32 benchmark data is historical and superseded; it is not evidence
for the current candidate. Benchmark dependency H keeps this ABI unchanged and
requires a fresh committed-archive no-cast validation; pre-H raw data cannot
satisfy that gate. The committed-H archive now passes the typed UInt64 no-cast
probe and the complete correctness/package gates; its fresh final CommonMark
`6.234490x` and GFM `4.845909x` ratios still fail the `2.5x` limits.
`MD-PERF-002` therefore remains blocked.
