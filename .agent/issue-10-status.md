# Issue 10 implementation status

The scope remains MD-00..08 and all original acceptance IDs in issue #10. This is
an implementation ledger, not a release claim. No core PR or release is authorized
for automatic merge or publication.

| Task | Implementation and evidence | State |
| --- | --- | --- |
| Prerequisite baseline | PR #11 merged as `8b5227b`; official STS 1.2.0; final push/PR checks PASS; exact retained CI artifact rebuilt offline in Arch and Ubuntu | PASS |
| Required checks | Replaced the three obsolete SDK contexts with the two passing STS 1.2.0 contexts; all other protection values verified equal | PASS |
| MD-00.3 / EDT-T01 identity | NodeId lineage plus nonrecycled serial, distinct immutable revisions, bounded shared-arena reservations, distributed identity hashes, persistent-fork allocation and stale CST/NodeRef/fix rejection | Correctness/resource regression PASS in 1566-case run; final performance cost not yet qualified |
| MD-00.4 / MD-00.5 / ARC-T02 | Success-only ParseResult, explicit ParseOutcome, removed aliases and content-hash StableNodeId; consumers migrated | PASS in the 1517-case full run |
| MD-00.7 / ART-T01 | 0.10 API boundary, SPI 3, plan 5, artifact schema 3; no old reader; explicit unsupported-version error | Current preparation checkpoint: 1611/1611 full tests and 70 API/evidence Python tests PASS |
| MD-00.1/.2, MD-01 batch | Typed footnote payloads, reachable-definition binding, first-definition/numbering/unique-anchor/backlink decisions, shared HTML/Text/Markdown output, exact source and snapshot/config identity; DocumentBindingTests | Batch and public append implemented; complete output-resource qualification pending |
| MD-03 batch | Heading-only typed suffix, explicit-ID reservation, shared anchor allocator, authoritative heading/fragment queries, structured TOC, source/Markdown/snapshot preservation; HeadingBindingTests | Batch and public append implemented; edit dependency qualification pending |
| MD-02 / EXT-T03 | Definition Lists 2.0 with typed List/Entry/Term/Definition, ordinary block bodies, source markers, full binding validation and shared HTML/Text/Markdown/snapshot/append/output traversal | Implemented; 1564-case full run and consumer gates PASS |
| MD-00.8 / MD-06.1..6 | Shared block/inline parser, pre-binding transforms, final binder and read-only analysis; actual feed-time closed AST fragments, atomic identity/version updates and replica, terminal failure, cumulative limits | Public append and shared lifecycle implemented; final resource/performance qualification pending |
| MD-06.7 | Real resumable HTML cursor over shared renderer rules; UTF-8 prefix acknowledgement, lazy tables/footnotes/escaping, terminal failure and cumulative output budgets; old buffered implementation removed | Implemented and correctness verified; final release performance/RSS qualification pending |
| MD-06.8 | Public append scaling tests for long loose lists, deferred-reference paragraphs, unclosed fences and many closed blocks; real scan/node-construction/patch counters | Correctness and work growth PASS; latency, peak RSS and release performance qualification pending |
| MD-04 / EXT-T05..06 | Versioned official capability matrix, exact enable/disable/profile output, literal Front Matter boundaries and bounded deterministic smart punctuation | Correctness verified; final release gates pending |
| MD-00.6 | Actual AST transform → binding → read-only analysis, shared batch/append pipeline, early whole-document execution gates and meaningful capability validation | Implemented; 1585-case run, consumers and API/evidence gates PASS |
| MD-05 | Math 2.0, Code Groups 1.0 and explicit typed preparation with revision/source/config binding, validation, Ready-only cache and shared resumable rendering | Shared preparation/model/UI correctness PASS; installable real optional backends and end-to-end resource qualification pending |
| MD-05.7 / code-group portion of RND-T02 | Group/Item with ordinary fenced children, titles, line ranges and exact copy text; optional localized tabs/copy and static fallback | 1600-case Cangjie run, all normal consumers and actual Chrome clipboard/keyboard/AX checks PASS |
| MD-07..08 | Existing editor/artifact phase baseline and real process/backend capability probes retained privately; no optimization verdict yet | Pending |
| DONE-02..06 | Complete task-to-test ledger, new performance qualification, docs/consumer gates and core hosted evidence | Pending |

The prior 0.9 raw reports remain historical measurements of their recorded
commits. They do not qualify the changed 0.10 product. No measurements are rebound
to a new commit by editing report identities.

The 1517-case run product tree digest is `9c27f722877fc46d2aff564065b36cc788866c730470f6a8f0f08e29f9aaeafc` (work tree and disk-backed test tree verified equal). API snapshot: 1434 declarations.

The subsequent semantic-binding full run passed 1534/1534 with STS 1.2.0, zero
skips/errors/failures. It adds ordinary reference definitions inside footnote
containers, excludes code from definition discovery, checks typed-payload source
ownership, bounds definition bytes and unmatched inline lookahead, and preserves
GFM table inline semantics with exact escaped-label offsets. API snapshot: 1508
declarations. These results do not qualify the pending append, editor, rich-backend
or end-to-end performance goals.

Additional foundation validation: both examples built and ran; CLI build/smoke and canonical benchmark-driver build PASS. Format, docs, public API and release-evidence consistency checks PASS. The complete 0.10 release/performance gate remains pending. Main post-merge CI run `39089161613` is PASS.

The final formatted binding product tree digest is `6873bd666d7b6cb0a4d7eb50fd233a65d09f3056f9b33b502948aba516c24cd2` (workspace and disk test tree verified equal). The exact tree passed all 1534 tests, both example builds/runs, CLI build/smoke and benchmark-driver build. API checker, evidence logic and bundle tests: 70/70 PASS. Docs/API/evidence consistency checks PASS. Complete release/performance gates and hosted core CI remain pending.

The append checkpoint uses official STS 1.2.0 and formatted product tree
`7376a44fc342a9e022355e008a3b52fd291c778dfdf3b9cab6e10bb63bb99cf5` (workspace and disk-backed test tree verified equal).
Full tests: 1548/1548 PASS, zero skips/errors/failures. The public session runs all
652 CommonMark and 671 GFM cases through six chunk patterns (7938 equivalence
checks), including reproducible random widths; final semantic AST digest,
HTML/Text/Markdown, source maps, reference definitions, diagnostics and snapshot
round trips match batch. Invalid-byte replacement fuzz covers 256 inputs through
three partitions; strict failures are terminal. Processor deletion exercises
Replace/Remove against the old version. Pending/input/node-work/patch/batch quotas,
wrong ordering/cross-session rejection and source-coordinate regressions PASS.

Normal check/build, both example builds/runs, CLI build/smoke and benchmark-driver
build PASS on that tree. Public API: 1559 declarations. The source-event loose-list
scheduler changed from quadratic prefix replay to geometric retry; the public
append tests assert linear scan/construction growth. These counters are not heap
allocation or RSS measurements. Full resumable HTML traversal (MD-06.7), the new
definition-list model, rich backends, edit/cache work and final release gates are
still pending. Historical benchmark reports remain bound to their original source.

The resumable-output checkpoint uses official STS 1.2.0 and formatted product
tree `94adfef5e05b4a5a61b9cb7652469fa957259859f06a07dbae0211d718694d27`
(workspace and disk-backed test tree verified equal). Full tests: 1554/1554 PASS,
zero skips/errors/failures. All 1323 pinned standard inputs run through three
HTML policies and three output widths (11907 output checks), with rejected,
partial and fully acknowledged pauses. Output bytes and rendered-node counters
match synchronous rendering; the existing 7938 append checks remain enabled.
Additional cases cover host callback timing, UTF-8 acknowledgement validation,
sink exceptions/failures, empty output, cancellation before/during/after a pause,
long flat documents and a single long escaped literal. No full HTML is built by
the session constructor; repeated refusal does not advance traversal or budgets.

Normal check/build, both example builds/runs, CLI build/smoke and benchmark-driver
build PASS. Format/docs/API/evidence checks and 70 API/evidence Python tests PASS.
Public API: 1561 declarations. The old buffered output class is removed and
Pause now carries the accepted UTF-8 prefix byte count. Buffered byte counters
exclude the AST, source and host port allocations. These correctness results do
not qualify peak RSS, frozen performance gates or the remaining issue scope.

The definition-list checkpoint uses official STS 1.2.0 and formatted product tree
`ad689322d84c832de70f8e1e82ca647ec4f3ec29a2b16429f56560171a6b85a0`
(workspace and disk-backed test tree verified equal). Full tests: 1564/1564 PASS,
zero skips/errors/failures. DefinitionListTests cover exact grouped HTML/Text and
canonical Markdown, multiple terms/definitions, empty definitions, ordinary
paragraph/list/quote/fence bodies, nesting, Unicode/CRLF and invalid-byte source
mapping, lossless CST, footnote/heading/link binding, snapshot equivalence,
single-byte/mixed/whole append and resumable output. Disabled/default profiles,
orphan markers, setext ambiguity, unsupported execution paths, malformed typed
payloads, grammar flags, declared resource costs, limits and cancellation are
checked explicitly. Canonical quote/list/task continuations keep their ownership;
four additional container fixtures check HTML round trips and idempotence.

Nested literal closures no longer trigger repeated whole definition-list prefix
retries. Public scaling cases check scan/construction growth at 16/32/64 entries
against batch output, including indented bodies. These are actual work counters,
not latency or RSS evidence. Normal check/build, both example builds/runs, CLI
build/smoke and benchmark-driver build PASS. Format/docs/API/evidence checks and
70 API/evidence Python tests PASS; public API: 1573 declarations. Full lifecycle,
remaining extension/rich-backend, editor/artifact and frozen release/performance
qualification remain pending. No core push or PR is authorized.

The identity-resource checkpoint uses official STS 1.2.0 and formatted product
tree `bcd0999fe4d6daf2c6669c24f30bb1fe046df097a229c1f6b89eb2a1a749ac41`
(workspace and disk-backed test tree verified equal). Full tests: 1566/1566 PASS,
zero skips/errors/failures; format and unchanged 1573-declaration API PASS.
In the actual internal probe, 1024 three-node arenas previously advanced their
shared lineage to serial 4190211; the same fixture now ends at 3072. Independent
batch arenas keep chunk reservations, while shared fragment/resolver/fork arenas
grow bounded reservations geometrically. Rollback never recycles identities and
the finite 32-bit exhaustion remains explicit. Distribution and lookup regressions
cover sparse serials and distinct lineage/serial pairs; the actual SDK HashMap
probe preserves checksums before/after. Exploratory process timings are not the
frozen performance gate or evidence of end-to-end throughput/RSS qualification.

The official-extension checkpoint uses official STS 1.2.0 and formatted product
tree `194f6e67bb1322678dfde0a1edcac4f238a0032084d208e34f786655a481c1f2`
(workspace and disk-backed test tree verified equal). Full tests: 1573/1573 PASS,
zero skips/errors/failures. The actual old smart-punctuation implementation failed
the new automatic-link, unchanged-identity and scan-budget regressions; all now
pass. Smart Punctuation 2.0 preserves automatic URI labels, code/raw HTML/literal
payloads, destinations and titles; it uses longest matches within semantic Text,
preserves raw source, keeps unchanged revisions and checks cumulative work/cancel.
Entities/escapes are decoded before this transform; no quote engine is claimed.

The matrix checks six optional extensions under both supported profiles with
exact HTML, versions, lossless source, enable/disable and builder immutability.
Duplicate registrations and the declared unsupported GFM 0.29 combinations are
explicitly rejected, rather than expanding profile declarations to fit the test.
Front Matter additionally covers CRLF/BOM ranges, normalized literal content,
ordinary body separators, canonical output and single-byte/mixed/whole append.
The combined punctuation/footnote/heading/definition/math/front-matter fixture
checks batch/append, source maps, diagnostics, canonical output and snapshots.
The API remains at 1573 declarations. Frozen performance, full lifecycle, real
rich backends, edit/cache work, final consumers and hosted core gates are pending.

The lifecycle checkpoint uses official STS 1.2.0 and formatted product tree
`4caf6ae2e200c241d9b7d841aed63cdb1e1ff52e5c3d7e92bd4f4c6cd429d85a`
(workspace and disk-backed test tree verified equal). Full tests: 1585/1585 PASS,
zero skips/errors/failures. ExtensionAstTransform executes before binding and
ExtensionDocumentAnalysis reads final bindings to return diagnostics. Both receive
the actual source/limits/budget/cancellation. Old DocumentPostprocess/processor
interfaces, registration and the obsolete execution-model field are removed.
SPI is 3, parser plan is 4; the binary layout remains schema 3 and configuration
identity changes invalidate prior caches. No compatibility wrapper is introduced.

Lifecycle tests verify transform/bind/analysis ordering, exactly-once final append
execution, analysis-only edit fallback, callback-free events/fused rejection and
PreferFused fallback. Callback resource errors retain their categories; invalid
source/profile ownership and host failures carry stage identity. Diagnostic main,
related and fix spans are validated, including Chinese/emoji scalar boundaries and
invalid-byte replacement mapping; attribution, literal budgets and defensive
related-span copying are checked. AST validation and TreeRewriter share operation
budgets/cancellation, and construction uses the configured node bound.

Typed grammar flags and generic renderer overrides fail explicitly; footnote and
heading matches charge configured resource costs. Heading suffixes obey global
lookahead/capture limits. Existing full append/output and standard corpus checks
remain enabled. All nine normal consumer steps PASS; the cookbook's actual
post-binding analysis emits `heading=analyzed`. CLI validation reads the engine's
current SPI and tests default/3 success plus obsolete 1/2 rejection. Format, docs,
public API (1578 declarations), evidence consistency, 70 API/evidence Python tests
and privacy checks PASS. Real rich backends, measured edit/cache decisions and
frozen release/performance/hosted core evidence remain pending. Core stays local.

The Math 2.0 checkpoint uses official STS 1.2.0 and product tree
`21b6fd28f1150949f5c8a3fd032d489876d1916ca94b491fd9145e4406d029b5`
(workspace and disk-backed test tree verified equal). Full tests: 1590/1590 PASS,
zero skips/errors/failures. API: 1593 declarations. MathPayload separates TeX,
inline/display mode, exact delimiter ranges and immutable MathSourcePart records
from any backend output. The actual first full run found a four-column opener
incorrectly taking indented code; the actual container probe found partial tab
expansion could not be validated as a contiguous raw string. Both regressions now
pass. Prefix layout preserves the physical tab span and normalized spaces without
changing the shared parser's line storage. Validation compares bounded source
bytes without materializing a second full normalized expression.

Cases cover quote/list, multiple tabs, empty/multiline formulas, CRLF/BOM, Chinese
and emoji, invalid-byte replacement, canonical/lossless Markdown, source maps,
snapshot identity, single-byte/mixed/whole append and resumable output including
image alternatives. Fixed grammar options and renderer overrides reject explicitly;
limits, cumulative scan and cancellation are exercised. All nine normal consumer
steps PASS; cookbook imports the public MathPayload and emits
`expression=x + y, source=x + y`. Format/docs/API/evidence consistency and 70
API/evidence Python tests PASS. This checkpoint is not real formula typesetting,
code groups, rich-output preparation, frozen performance or hosted core proof.

The Code Groups 1.0 checkpoint uses official STS 1.2.0 and product tree
`1a3208158bbeaf5ed219591eb64f31d3717372810beab0152b245642c5feda17`
(workspace and disk-backed test tree verified equal). Full tests: 1600/1600 PASS,
zero skips/errors/failures; API: 1620 declarations. The group owns typed Item nodes
with ordinary fenced-code children, fixed title/range grammar and source-derived
copyText preserving BOM/CR/LF/CRLF after container normalization. Default HTML is
complete static figure/figcaption/pre/code with visible mark elements. Canonical
Markdown keeps metadata and selects a safe fence. Combined footnote, heading, math
and definition-list cases, snapshots, source maps, bytewise append, invalid UTF-8,
resource bounds, cancellation, resumable output and actual nested-closer scaling
PASS. Invalid info/body stays visible with diagnostics; code is never executed.

Optional CodeGroupHtmlOptions emits bounded UTF-8 hex data and localized labels
without loading JavaScript. The independent script progressively creates linked
tabs/panels, keyboard navigation and click-only Clipboard API controls. Disabled
copy is visibly explained; missing JS leaves every block visible. Browser checks
use actual cookbook HTML, not handwritten output: Node 24.22.0, Puppeteer 25.14.0,
Chrome 155.0.8059.84. Real clipboard round trips preserve leading BOM, CRLF, Chinese
and emoji; empty-block copy also succeeds. Four AX tabs, duplicate fragments,
ID collisions, repeated initialization, arrow/Home/End keys, localized failure,
copy-limit fallback, no-script output, light/mobile-dark layouts and zero unexpected
page requests PASS. Both screenshots were visually inspected. Browser execution
is a separate trusted fixture test and does not claim an OS sandbox or other-OS proof.

The generated fixture SHA is
`069877d52a872a34339e232f1dca1fd56329b03b1f60ff7acab4778c8ba7a541`;
final script/CSS hashes are
`aa73761fb9873081f4ac323b4f3a42dfe8dcbaf9ca16d0216f93ce47fc3e820f` /
`d65aec4f30581756675bc21a79d9704aaa75a2fd84e407fd0718c758641b4875`.
The first browser timeout was diagnosed as missing sanitized-write permission in
the independent test context, not silently turned into a mock success. Granting
the required scoped permission allowed actual clipboard writes; denied writes
remain an explicit tested failure state. A Cangjie declaration-order compile
error in the shared default was fixed using the repository's class-static pattern.

All nine normal consumer steps, 70 API/evidence Python tests and format/docs/API/
evidence/privacy checks PASS. Parser plan 5 now uses one constant across canonical
descriptors, engine fingerprints and parse artifacts; binary layout stays 3. Rich
literal containers collect references through real block boundaries. All structured
payload renderers require completed binding. Real KaTeX/Mermaid/Shiki preparation,
process cleanup qualification, measured editor/cache decisions, frozen performance
and hosted core gates remain pending. No core push, PR, merge or release is authorized.

The final canonical regression was run against the actual prior implementation:
changed typed titles/ranges were replaced by the old info string, and deleting
the first unnamed block left an ordinal caption inconsistent with reparse. The
same case now passes. Canonical headers consume typed metadata with quote,
backslash and backtick protection; raw info remains source-only. Unnamed blocks
use the stable `text` label. Controls and unrepresentable metadata fail binding.
The final 1600-case tree above also passed all nine normal consumer steps and 70
API/evidence Python tests. The newly generated cookbook fixture matches the hash
recorded above, and the actual browser gate was rerun. Its runner hash is
`b204f782ff7cb53c0396b0ce2c7a7766b0941f6d13aa154d8213812998117c00`.

## Shared rich preparation checkpoint

Official STS 1.2.0, formatted product tree
`cfb10b735a826eab269e6623c17fa279165677e7289d1a0a0b1340c107120ae0`
matches the actual disk-backed test tree. Full suite: 1611/1611, zero skips,
errors or failures. Public API: 1705 declarations. Nine normal consumer steps,
70 API/evidence Python tests, format/docs/API/evidence and privacy checks PASS.
The cookbook actually reports `math preparation=missing` and retains full TeX.

MD-05.1/.4/.5/.6/.8 now have a shared typed boundary: immutable MathML trees,
UTF-8 color/font tokens and RGB/RGBA PNG containers; fixed tag/attribute/value
validation, token order/scalar boundaries, PNG bounds/chunks/CRC/end, explicit
disabled/missing/unsupported/timeout/failure/limit states and strict opt-in.
No third-party HTML/SVG is promoted to TrustedHtml. PNG display additionally
requires an explicit PNG data-image policy; otherwise full source is rendered.
Prepared entries reject another Document revision before output. Text/Markdown
and source AST remain unchanged. Derived MathML/PNG maps are marked generated
with coarse provenance; expression source parts remain available separately.
HTML fingerprint is 5; no prepared data is persisted in parser artifacts.

RichContentTests exercise default/missing behavior, hostile structured outputs,
Unicode/ranges, raw CRLF code-group copy, explicit image policy, source/config/
actual-theme cache keys, non-cached failures, current stricter limits, total
output/cache capacity, stale identities, cancellation and resumed byte equality.
The boundary fixtures are explicitly not real-engine qualification. The real
KaTeX/Mermaid/Shiki adapter remains pending.

A real first run crashed all nine new cases while the prior 1600 passed. A
standalone std-only probe isolates STS 1.2.0: direct tuple destructuring of
ArrayList.remove returns a corrupt reference at -O2; -O0 and a named popped
frame at -O2 pass. The preparation and validator use the existing repository's
named-frame pattern. No SDK or optimization flag changed. Two compile-only test
type errors and two incorrect output expectations were also corrected; retained
logs distinguish those from the actual runtime failure.

Separate Linux supervision probes cover exact 256 KiB simultaneous binary pipes,
worker crash, detached descendants retaining pipes and ignoring TERM, timeout,
output-limit cancellation and launcher death. Actual Chrome 155.0.8059.84 creates
nine descendants; Node crash and cancellation both terminate and reap all nine.
The STS 1.2.0 bridge passes concurrent pipe/timeout/limit checks. This establishes
a viable Linux optional-adapter mechanism, not a production backend or an OS
sandbox. Frozen performance, editor/cache decisions and hosted core gates remain
pending. Core changes remain local; no push, PR or release is authorized.
