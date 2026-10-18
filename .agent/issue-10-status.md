# Issue 10 implementation status

The scope remains MD-00..08 and all original acceptance IDs in issue #10. This is
an implementation ledger, not a release claim. No core PR or release is authorized
for automatic merge or publication.

| Task | Implementation and evidence | State |
| --- | --- | --- |
| Prerequisite baseline | PR #11 merged as `8b5227b`; official STS 1.2.0; final push/PR checks PASS; exact retained CI artifact rebuilt offline in Arch and Ubuntu | PASS |
| Required checks | Replaced the three obsolete SDK contexts with the two passing STS 1.2.0 contexts; all other protection values verified equal | PASS |
| MD-00.3 / EDT-T01 identity | NodeId lineage plus nonrecycled serial, distinct immutable revisions, persistent-fork allocation, stale CST/NodeRef/fix rejection; 1517/1517 full tests PASS with STS 1.2.0 after result/schema migration | In progress: performance cost not yet qualified |
| MD-00.4 / MD-00.5 / ARC-T02 | Success-only ParseResult, explicit ParseOutcome, removed aliases and content-hash StableNodeId; consumers migrated | PASS in the 1517-case full run |
| MD-00.7 / ART-T01 | 0.10 API boundary, SPI 2, plan/schema 3; no old reader; explicit unsupported-version error | PASS in the 1517-case full run; API checker 47, evidence bundle 5 and evidence logic 18 tests PASS |
| MD-00.1/.2, MD-01 batch | Typed footnote payloads, reachable-definition binding, first-definition/numbering/unique-anchor/backlink decisions, shared HTML/Text/Markdown output, exact source and snapshot/config identity; DocumentBindingTests | Batch implemented; true append and complete output-resource qualification pending |
| MD-03 batch | Heading-only typed suffix, explicit-ID reservation, shared anchor allocator, authoritative heading/fragment queries, structured TOC, source/Markdown/snapshot preservation; HeadingBindingTests | Batch implemented; edit dependency and append qualification pending |
| MD-00.6/.8, MD-02, MD-04..06 | Lifecycle cleanup, structured definition lists, complete extension acceptance, true append and resumable output, real optional rich rendering | In progress |
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
