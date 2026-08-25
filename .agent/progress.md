# markdown 当前进度

更新时间：2026-08-25
当前阶段：P0 correctness 与 P1 hardening 已完成并通过全量测试；0.8.0 与 release evidence 基础设施已落地，canonical benchmark 已绑定当前产品提交，但性能仍未达 GA
整体结论：**INCOMPLETE**。正确性、规范、构建、打包和私密安全报告门槛已通过，但需求账本仍有 3 个 `blocked` 项。

## 需求概览

| 状态 | 数量 |
| --- | ---: |
| 总数 | 125 |
| `pass` | 122 |
| `implemented_unverified` | 0 |
| `pending` | 0 |
| `blocked` | 3 |

`requirements.yaml` 是唯一状态账本；本文件只用于会话恢复。

## 2026-08-25 P0 correctness/resource contract hardening

- `maximumAstNodes` 已前移到 parser-owned `NodeIdAllocator.next()`，内建节点与 Parser SPI 的 `nextNodeId()` 共用同一计数器；极低上限在下一节点分配前抛出 `ast_nodes`。
- `BoundedLiteralBuilder` 与统一 literal guard 在 fenced code、HTML block、indented code、inline code/HTML、Text 合并和 extension literal 构造期间检查 `maximumLiteralBytes`，多行内容不能再靠单行上限绕过。
- dialect、renderer、engine 与 binary AST digest 改用类型化长度前缀 canonical fields；分隔符、Unicode、空字段和字段切分不再形成相同 preimage，manifest 的无序集合先排序，语义相关 rule 顺序仍进入 fingerprint。
- HTML SourceMap 改为 renderer 写出时同步记录 generated/source-derived range；`sourceSpanAt()` 与 `nodeIdAt()` 对已排序 ranges 二分查询，`p`/`em` 标签名碰撞回归通过。
- schema-v1 artifact 采用保守方案：仅接受 identity-preserving source mapping；`ReplaceInvalid` 结果在 encode 前以 `InvalidArtifact` 拒绝，binary artifact 同样 fail closed。
- 最终验证：format、`cjpm check`、release build、8 个 API checker tests、1155 declaration API snapshot 均 exit 0；完整 socket-enabled suite `1413/1413` pass。
- 本切片没有重新运行 benchmark；后续发布治理已把版本重置为 `0.8.0`，新增托管 CI 和单一 `release-evidence.json`，并把现有 raw 标记为 `stale-unbound`。当前整体状态保持 **INCOMPLETE**。

## 2026-08-25 P1 indexed source positions

- `SourcePositionMap` 现在一次构建 `SourceIndex`：行起点通过二分定位，UTF-16 与 visual scalar 查询从每行最近的 bounded checkpoint 开始短扫，不再每次从文档开头扫描。
- ReplaceInvalid 的 original→decoded 定位改为 lower-bound 二分并保持重复映射取首项的既有语义；CRLF 中间 offset 仍按下一行 column 0/1 的旧契约返回。
- 保留 `SourcePositionMap(source, tabStop: ...)` 构造器和默认 tab 展开行为；新增显式 `DisplayWidthPolicy`。文档不把 scalar column 误称为 CJK/emoji/grapheme 的终端 cell 宽度。
- 验证：`scripts/check_format.sh` exit 0；API snapshot 1164 declarations，SHA-256 `448d318d...b10`；socket-enabled full `cjpm test` exit 0，1415/1415 passed，其中索引回归覆盖 CRLF、emoji、replacement、tab policy 和 200-byte checkpoint 边界。
- 当前 canonical benchmark 仍是 `stale-unbound`，未用本地功能测试替代远端 release benchmark；整体状态保持 **INCOMPLETE**。

## 2026-08-25 P1 shared CST arena and indexes

- `SyntaxTree` 只保存一份 token arena；每个嵌套 `SyntaxNode.tokens` 变为共享 backing 的 `ImmutableArray` range view，不再为每个 AST 节点收集并防御性复制同一批 token 引用。公开构造器和 `toArray()` 仍执行防御性复制。
- `SyntaxToAstMap` 构造时建立 NodeId→syntax、NodeId→semantic 与 TokenIndex→smallest semantic node 索引；`SyntaxTree.tokenAt(byteOffset)` 用二分查找，替代每次全 token/AST 遍历。
- capability 使用 `incrementalMode="block-local-with-full-fallback"`；文档明确 chunk/stream 是 buffered adapter，unsupported edit 仍全文重解析，不宣称完整 incremental parser。
- 验证：format、build 通过；最终 socket-enabled full suite exit 0，1416/1416 passed，包括共享 range、防御性复制、byte token lookup、smallest semantic owner 和 capability 回归；benchmark smoke 3/3。API snapshot 为 1165 declarations、SHA-256 `b6b105c0...9479`；canonical CST overhead 仍待远端 release benchmark。

## 2026-08-25 P1 SemVer dependency correctness

- extension semantic version 和 dependency minimum 不再只取前三段数字并截断 `-`/`+`；完整实现 SemVer prerelease precedence，build metadata 不影响排序。
- dialect compile 阶段拒绝不完整版本、数字前导零、空/非法 identifier 和 Int64 overflow；implementationVersion 保持不透明构建身份。仓库内有效 manifest 已迁移到完整 `x.y.z`。
- 第一次 full suite 真实发现 1 个 capability 断言和 1 个 Parser SPI fixture 尚用旧版本字符串，结果为 1415 passed/1 failed/1 error；修复迁移而未降低断言后，最终 socket-enabled full suite exit 0，1417/1417 passed。
- 最终门禁：`scripts/check_format.sh`、`cjpm check`、`python3 scripts/release_evidence.py`、release-evidence tests 3/3、API checker tests 8/8 和 1165-declaration snapshot 均 exit 0；公开 API 未新增。`python3 scripts/release_evidence.py --release-ready` 按预期 exit 1，明确拒绝 draft、dirty/unbound source、stale benchmark 和 unbound benchmark SDK。canonical benchmark 仍未绑定当前源码，整体状态保持 **INCOMPLETE**。

## 2026-08-25 Safe renderer URI/target hardening

- data-image allowlist 不再使用 MIME 前缀匹配；只比较首个 `;` 参数前的完整 media type，大小写无关，因此允许 `image/png` 不会误放行 `image/pngx`，带合法参数的 `image/PNG;charset=...` 仍可通过。
- Safe policy 下，HTTP(S) 外链配置 `_blank` target 时强制补齐 `noopener noreferrer`；已有大小写不同的 rel token 按 ASCII whitespace token 识别并去重。SpecCompatible 不自动添加 Safe-only rel。
- 定向用例 exit 0；socket-enabled 全量 `cjpm test` exit 0，1418/1418 passed，0 skipped/error/failed。format、`cjpm check`、真实仓库命令 `cjpm build`、API checker 8/8 和 1165-declaration snapshot 均 exit 0。曾误用 `cjpm build --build-type release`，cjpm 在编译前因无效自定义参数 exit 1；该结果未计为 build 证据，随后已按 `scripts/release_gate.sh` 的实际命令重跑成功。该切片不改变 public API，也不改写 canonical benchmark；整体状态仍为 **INCOMPLETE**。

## 2026-08-25 arbitrary-byte UTF-8/chunk differential fuzz

- 新增 seed `20260825` 的 256 个任意 byte 输入（最长 191 bytes），同时验证 Strict/ReplaceInvalid、all-at-once/变长 chunk partition、decoded source、原始 byte length、diagnostics、HTML 与 AST invariants。
- 首次定向运行在 case 16 `[160,138,230,223,75,254,49,189,92,141,27,232,64,79,169,36]` 真实触发 GFM email local-part 的非法 UTF-8 slice；修复后复跑又触发 HTML block ASCII lowercase 逐 byte 构造非法 String。两处均修复为 byte-safe 实现，未吞异常或弱化测试。
- 最终定向测试 exit 0；socket-enabled 全量 `cjpm test` exit 0，1419/1419 passed，0 skipped/error/failed；format、`cjpm check`、`cjpm build`、API checker 8/8、1165-declaration snapshot 和 benchmark smoke 3/3 均通过。fuzz summary 保持 deterministic property smoke 定位，不声称 coverage-guided/native fuzz 已完成，benchmark smoke 也不替代 canonical 远端 release benchmark。

2026-08-23 UInt64 repair：benchmark dependency H `db4392e2` 已把 paired
seven-sample protocol 与 owned-input driver 纳入 committed stack。H 之前的
raw `48dbad...` 及 `6.449555x`/`5.695987x` 只作 historical
pre-dependency measurement，不是 final acceptance evidence，不参与
trend/projection。历史 UInt32 `4.089529x`/`3.396847x` 也仅为
historical/superseded。包含 H 的 preliminary committed archive 已 fresh 通过
typed UInt64 no-cast ABI、API 1155、tests 1410/1410、CLI、differential
25/24/1/0、benchmark smoke 3/3、quickstart 与 bundle。Formal raw SHA-256
`9acd3c7b7e2077462daeff0032f8a43e4d507fab3fe21dda244a663bc3f950d0`
测得 CommonMark `6.234490x`、GFM `4.845909x`；保持 **INCOMPLETE**、
`MD-PERF-002=blocked`。

2026-08-24 同语言补充证据：固定 `markdown4cj` `f43cfb3a`，仅抽取平台无关
`src/core/**`，用当前 SDK 和 `commonmark4cj` `41499e6d` 构建；未使用
DevEco、OHOS UI 或 components。CPU 2、`-O2`、11 个 256 KiB 语料、每侧
7 个交替样本的 parse-only 对比中，`markdown` 几何平均快 `10.996x`，
最小单项 `4.150x`，最大峰值 RSS 比值 `0.664x`；共享 HTML 行为 `12/12`。
该结果证明同语言 parse-only 优势，不替代 `MD-PERF-002` 的 cmark/cmark-gfm
GA 门槛。

## 已完成主链路

- CommonMark 0.31.2 与 GFM 0.29 官方语料分别 652/652、671/671。
- String/bytes/stream/chunked 输入、不可变 AST、byte/UTF-16/visual 位置、SourceSlice、partial-result 隔离。
- Spec/GFM/Safe HTML、Plain Text、Canonical Markdown、Sink、sanitizer 和暂停/恢复 adapter。
- Dialect/Syntax/Renderer DSL、typed 参数、bounded Parser SPI、SHA-256 fingerprints、TCK。
- Walker/Visitor/Query/Rewriter、transform、annotation、events、CST/token map、snapshot、range/preserving edit、lint/fix/explain、source map、artifact。
- CLI、consumer quickstart、API snapshot、差分测试、安全/fuzz corpus、benchmark harness、完整 cjpm bundle。

## 当前非通过项

- `MD-SEC-005` — `pass` — 2026-08-24 GitHub official API returned `{"enabled":true}`; SECURITY.md and docs/security.md link the private advisory form.
- `MD-PERF-002` — `blocked` — On the fixed 2026-08-25 Server rerun, commit `0275f27a` measured CommonMark 5.842x and GFM 4.982x versus the 2.5x GA limits. Ordinary, scaling, pathological scaling and RSS gates pass; only the two ratio gates fail.
- `MD-REL-001` — `blocked` — The package, CLI, documentation, reports, example, bundle, and private reporting channel exist, but mandatory MD-PERF-002 prevents a 1.0 GA declaration.
- `MD-QUAL-001` — `blocked` — Correctness, package, and private security reporting gates pass, but the mandatory performance success metric does not.

## 最后验证

| 命令 | Exit | 结果 |
| --- | ---: | --- |
| `scripts/check_format.sh` | 0 | all Cangjie source matches cjfmt |
| `cjlint -f src` | 0 | 0 errors; 476 advisory diagnostics |
| `cjpm check` | 0 | dependency graph valid |
| `cjpm build` | 0 | root static library, `-O2` |
| `cjpm test` (2026-08-25 P0 final socket-enabled rerun) | 0 | 1413 passed, 0 skipped/error/failed |
| CommonMark/GFM cases inside full suite | 0 | 652/652 and 671/671 |
| `cd tools/markdown && cjpm build`; `scripts/cli_smoke.sh` | 0 | CLI build and exit 0/2/3/4/5/6/7 smoke; explicit native archive link |
| `cd examples/quickstart && cjpm build && cjpm run` | 0 | public consumer example built and ran; explicit native archive link |
| `python3 scripts/check_public_api.py` | 0 | 1155 public declarations match snapshot |
| `python3 scripts/differential_test.py` | 0 | 25 comparisons: 24 exact, 1 classified, 0 unexpected |
| `cjpm bench --filter MarkdownReleaseBenchmarks ...` | 0 | 3/3 benchmark smoke cases; socket permission required |
| `python3 benchmarks/measure.py` (remote Server, CPU 24, harness module-path override) | 1 | 12-corpus GA FAIL: CommonMark 4.084x, GFM 3.229x; ordinary CommonMark 3.875x; slope 0.989, pathological slope 1.237, RSS 68288 KiB pass |
| `python3 benchmarks/measure.py` (2026-08-20 current candidate, remote Server CPU 24) | 1 | 12-corpus GA FAIL: CommonMark 5.261x, GFM 4.129x; slope 0.852, pathological slope 0.792, RSS 59464 KiB pass; only ratio gates fail |
| `python3 benchmarks/measure.py` (2026-08-21 retained candidate, remote Server CPU 24) | 1 | 12-corpus GA FAIL: CommonMark 4.469x, GFM 4.028x; slope 0.851, maximum adjacent 2.007, pathological slope 0.799, RSS 58820 KiB pass; only ratio gates fail; raw SHA-256 aaac470...0e03 |
| `scripts/release_gate.sh` | 1 | fail-closed at performance after format/API/check/build/1410 tests/CLI/example/differential/benchmark smoke passed |
| `cjpm bundle --skip-test` after the full 1410-test gate | 0 | target/markdown-1.0.0.cjp; 343528 bytes; SHA-256 aab2e233b88b495c0221eb36e673c0d6a19184721b1776620525283098882529 |


## 工作区安全

- 本轮性能实现前快照：workspace HEAD `16face7d87a175f9c0a1e23cb99381dab1ca5331`；`perf-cffi-scan` branch ref `47ffe482342d6ec785d2478faa4c1702e5ad228e`；merge-base `b96e8f9e6eb2be386b4801ce86f24bb0c7207421`；dirty paths none。
- 本轮最终快照：GitButler `zz [uncommitted]` 无变更；`perf-cffi-scan` 已推送并与 `origin/perf-cffi-scan` 对齐，merge-base 为 `b96e8f9e6eb2be386b4801ce86f24bb0c7207421`；精确 refs 以最终 `but status`/远端核对为准。
- 本轮新增并推送 GitButler commits `knw`（`InlinePiece` 值结构优化）和 `noq`（链表结构体实验回退记录）；此前的 `mlx`/`uxv` 也保持在远端。生成的 `build-script-cache` 已按精确路径清理。
- 未执行 reset、clean、stash、checkout、rebase、merge、amend 或 PR 操作；未发现并发漂移。

## 恢复顺序

1. 从 `requirements.yaml` 读取 3 个 blocked 项，不从本摘要猜测。
2. 对 `MD-PERF-002` 继续执行 measure → profile → allocation/lifetime 优化 → 全量正确性 → 重测；不得放宽阈值。
3. 性能项通过后重跑全部 gate，并将 `MD-REL-001`、`MD-QUAL-001` 改为 pass。
5. 只在 125/125 `pass` 时声明 COMPLETE。

## 2026-08-19 性能复核（本轮）

- 固定环境：授权 SSH `Server`、CPU 24、Linux 5.15、Xeon Gold 6248R、Cangjie SDK `/home/chenqian/fastjson-bench-sdk-20260803/cangjie`（`1.1.0-alpha.20260803040049`）、`-O2`、`cjHeapSize=2GB`。该 SDK 与 2026-08-18 的远端快照不同，因此只做同一 SDK 内的配对比较，不把绝对比率跨 SDK 直接合并。
- PMU 仍不可用：服务器 `perf_event_paranoid=4`，`perf stat` 明确拒绝；没有伪造 cycles/instructions 证据。分析使用固定 CPU、12 轮交替测量、RSS 和完整 release harness。
- 保留的候选位于 `src/parser.cj`：解析会话为有效 reference definition 建立 `HashMap<String, ReferenceDefinition>`；reference lookup 和 delimiter 中的 reference 判断均复用 O(1) 索引；ASCII 小写且无空白/非 ASCII 标签走无分配规范化快路径。重复标签仍只索引首个 effective definition。
- 候选源码归档 SHA-256：`1162a0350b22efbeb969279ad89d2b4898b3a8612cbcb5aedbdf26abfd072845`（cjfmt 后最终工作树）；交替 A/B JSON SHA-256：`4df43fc1dba76d6189bd690252e65fbd08b0aea05110501bb75734a1331682f8`。12 轮、CPU 24 的 1 MiB 语料结果：CommonMark ordinary `1.162x`、many-references `1.268x`、large-table `1.035x`、pathological `1.010x`、CJK `1.016x`；GFM ordinary `1.032x`、many-references `1.157x`、large-table `0.996x`、pathological `1.017x`、CJK `1.002x`（candidate speedup）。所有 stdout checksums 相同。
- 第三候选全量 `cjpm test` exit 0：1410 passed、0 skipped、0 failed、0 errors。完整 release harness exit 1：CommonMark `6.137x`、GFM `5.459x`、普通扩展性 slope `0.877`、最大相邻增长 `1.968`、病理 slope `1.402`、最大相邻 `3.984`、10 MiB extra RSS `80600 KiB`。原始报告 SHA-256：`6d424f69062c7caca03926277bffcd2b8ba81d8082df4631df1d1124040833e9`。
- 同一 SDK/CPU 的配对 baseline release exit 1：CommonMark `6.945x`、GFM `5.670x`、slope `0.935`、病理 slope `1.377`、extra RSS `79844 KiB`；因此候选对 CommonMark 约改善 11.6%，GFM 约改善 3.7%，但仍未达到 2.5x GA 门槛。
- 直接 UTF-8 rune decoder 候选已拒绝：ordinary 慢 `4.7%`、CJK 慢 `5.1%`；第四个“无有效引用布尔快路径”候选因 ordinary 慢 `4–13%` 而拒绝。未把跨 profile 回退或噪声收益提交为优化。
- 2026-08-19 当时 `src/native_scanner.cj` 的 foreign scanner 带有 `@FastNative`，且 C 实现无锁、无 I/O、无 Cangjie 回调；2026-08-22 后续审计因整输入扫描的总调用时长无法证明短时且有界而删除该 annotation。parser/GC 长路径始终未标记 `@FastNative`。
- 2026-08-20 的后续性能记录仍把 packed native scanner 描述为 bounded `@FastNative` foreign 扫描；该表述只反映当时实现，2026-08-22 审计后 annotation 已删除，native static archive 发布依赖不变。

### 增量候选回退记录

- 2026-08-19 在同一固定 SDK、Server CPU 24、1 MiB 语料和 12 轮交替协议下验证了两个 parser 微优化：将 `mayContainExtendedAutolink` 的三个 `String.contains` 合并为单字节扫描，以及把 `lastUnescapedClosingBracket` 延迟到遇到 `[`/`![` 时执行。
- 两个候选的 stdout checksum 均与 baseline 一致，但相对 `e9f8421` baseline 的配对结果为 CommonMark `0.961x`、GFM `0.949x`（即分别慢约 4.0%、5.1%）；原始 JSON SHA-256 为 `faf091028e91ee8dd20e10364856fc2ad94c56e814703dcb9bc5e2d1aed2c7e8`。
- 结论：两项均已回退，未污染发布候选；这说明 Cangjie `String.contains` 和预扫描的实现成本不能仅凭源码直觉替换，后续应先取得可重复 allocation/profile 证据再改动。

## 2026-08-19 InlinePiece 分配优化复核

- 在 `src/parser.cj` 将只承载行内片段值的 `InlinePiece` 从 class 改为 struct；链表节点 `InlinePieceLink` 仍为 class，并把 delimiter 消费后的值显式写回节点。这样保留原有 delimiter 链表和 AST 语义，只移除每个普通片段的一次独立对象分配。
- 远端候选归档 SHA-256：`f4e0a5c34b4a35c6cb07bc278a3cb3c8904365676145f8b426118cea45c99992`。固定 Server CPU 24、同一 Cangjie SDK、1 MiB CommonMark/GFM 语料和 12 轮交替 A/B 的配对 JSON SHA-256：`da1f7157c34ae124d71e1d4354fadca6545a3b0cb92f6be392f1c2217d5d5296`；所有 checksum 相同。CommonMark 中位耗时由 `0.4761775515` 降至 `0.470497035`（约 `1.207%`），GFM 由 `1.3829321625` 降至 `1.3663628375`（约 `1.213%`）；配对 ratio 分别为 `0.9973` 和 `0.9885`，收益较小，仍需完整 release 门槛复核。
- 本地 `perf record -F 199 -g --call-graph dwarf`（1 MiB、20 轮，exit 0）重复观察到 `String.fromUtf8`/验证、C 行扫描器、Maple GC tracing/forwarding 和引用数组复制热点；远端 PMU 仍因 `perf_event_paranoid=4` 不可用，因此没有 cycles/instructions 声明。
- `SourceBuffer.matches` 手写字节比较、`ArrayList` 容量预估、packed reference 标志/`memchr` 预扫描和特殊字符 gate 均在 A/B 或全量测试中回退或无法证明跨语料收益，已恢复，不纳入发布候选。packed 标志实验还曾触发范围错误，修正后虽恢复 `1410/1410`，仍因性能回退而丢弃。
- 随后尝试把 `InlinePieceLink` 也改为带数组索引的 struct，以消除 delimiter 链表 class 分配；该版本本地全量测试同样为 `1410/1410`，但固定 CPU、每次 100 次解析的 6 轮交替测量中位配对 ratio 为 `1.0434`、candidate speedup `0.9897`，与短样本的跨语料波动不一致，已回退。当前发布候选仍只保留 `InlinePiece` struct，避免把未经远端复核的链表重写带入。
- 当前候选已完成本地格式、`cjpm check`、根包和 benchmark driver 构建、全量 `cjpm test`（`1410/1410`）；尝试启动同一候选的远端完整 release harness 时 SSH 被服务器主动关闭，未取得新的 raw report，不能把本地或配对结果替代 release 门槛。`MD-PERF-002` 继续 `blocked`。

## 2026-08-19 当前候选完整 release benchmark

- 纠正 SSH 别名后，使用 `Server`（SSH 配置端口 1105）重新执行完整 harness；固定 CPU 24、Xeon Gold 6248R、Linux 5.15、Cangjie `1.1.0-alpha.20260803040049`、`-O2`、`cjHeapSize=2GB`、cmark 0.31.1、cmark-gfm 0.29.0.gfm.13，7 samples × 3 iterations。
- 当前分支归档 SHA-256：`dc5f5dc6f12d5567e26efb028bf3d4e87cd0cb3aa5bcac598bccb98a0a33754b`；远端 driver SHA-256：`f1e0431ed96ebe9eaab640787d2921ece2765c5c538c1d2fe3814077a330443f`；raw report SHA-256：`f88ec9fa944411df4aaa560d1e9dd9fd51d240704ca3543c188c316023204ae1`，已同步到 `docs/reports/benchmark-raw.json`。
- harness exit `1`，但远端进程完整结束并写出 report。CommonMark 几何平均 `6.980369x`、GFM 几何平均 `5.989632x`，两项均超过 `2.5x`；普通代表项 CommonMark `3.512038x`、GFM `2.709449x` 均通过 `5x` 限制。
- 扩展性 slope `0.923963`、最大相邻增长 `1.955930`、病理 slope `0.962821`、10 MiB extra RSS `80120 KiB` 均通过；SourceMap 时间开销 `112.16%`、CST 时间开销 `1038.97%` 已记录。gates 只有 CommonMark/GFM ratio 为 false，未修改阈值。`MD-PERF-002` 仍为 `blocked`。

## 2026-08-18 性能复核（历史记录）

- 基线：`perf-cffi-scan` 的 `uwv`（zero-copy `OwnedUtf8Input` + 单次 packed-record scanner）；远端 `Server`、固定 CPU 24、1 MiB 固定 CommonMark/GFM 语料、交替配对测量。
- `perf record -F 99 -g --call-graph fp` 可用；PMU `perf stat` 计数器相对误差过大，未作为证据。可重复热点是 Maple GC 的 tracing/forwarding、`memset`、`collectReferences`、字符串验证和后续对象分配；native scanner 本身占比较小。
- 已验证但未保留：新增 `[`/reference-open packed flag（收益落在 A/A 噪声内）、`hasCoreInlineSpecial` gate、native malloc record（CommonMark 约慢 4%）、`UInt32` packed record（CommonMark 单独变快但 GFM 回退）、`bytes/12` 容量估计（CommonMark 约快但 GFM 约慢 4.6%）。所有实验结束后源文件恢复为 `uwv`，没有把跨 profile 回退提交为优化。
- CommonMark `UInt32`/容量候选曾出现约 15–20% 的配对优势，但 GFM 对照无法证明无回退；因此 `MD-PERF-002` 继续 `blocked`，不放宽 GA 阈值。
- 历史基线源码验证：`scripts/check_format.sh` exit 0；根包 `cjpm build` exit 0；`benchmarks/driver` `cjpm build` exit 0；全量 `cjpm test --no-color --no-progress --report-path /tmp/markdown-final-tests --report-format xml` exit 0，1410 passed、0 skipped、0 failed、0 errors。
- 完整 release benchmark：远端 Linux 5.15 / Xeon Gold 6248R / glibc 2.35 / CPU 24 / Cangjie `-O2` / heap 2GB；7 samples、3 iterations、12 个 256 KiB corpus，exit 1（仅两个比率门槛失败）。Raw report 已写入 `docs/reports/benchmark-raw.json`。
- 本轮 Git 状态：上一轮性能证据提交 `f13b8a3` 已推送；本次远端 release 报告、需求账本和验收记录已纳入后续 GitButler 提交，提交后推送到 `origin/perf-cffi-scan` 并确认工作区 clean。

## 2026-08-20 parser、分配与 renderer 优化复核

- 2026-08-20 当时保留了 `OwnedUtf8Input` 零复制输入、packed native line scanner、带 `@FastNative` annotation 的 foreign 扫描、`StringTextSink.appendTrusted`、手写 extended-autolink precheck 和 64 KiB renderer 初始容量；该 annotation 后于 2026-08-22 因整输入调用时长无法证明短时且有界而删除。当前 full release 的上一个接受基线为 CommonMark `5.279783x`、GFM `5.060454x`。
- `src/parser.cj` 的 GFM table 实现改为 cmark-gfm 风格游标扫描：探测阶段只计数和校验 byte range，行解析使用紧凑 `TableCellSlice`，仅在 cell 真正包含 `\|` 时分配反转义 builder。固定 CPU 24 两轮隔离 A/B 中，`large-table/GFM` 分别从 `0.750236s` 降至 `0.536904s`（`0.7156x`）和从 `0.742868s` 降至 `0.555905s`（`0.7483x`）；raw JSON SHA-256 分别为 `2f48dd83f1d9457482e784e09263f84a94ff45fc94bf46a666078ab79a3f9074`、`02dea39895e3242f2d5adb3d7aaf550cb1a31d7dbae8a3a0857a6301aa41045b`。
- `src/ast.cj` 增加仅内部可见的 `OwnedArray<T>`；公开 `ImmutableArray` 和所有公开 AST 构造器仍执行 defensive clone，parser 对自己刚生成且无外部别名的 Paragraph/Heading/Table/inline-container children 才走 owned 构造路径。两轮隔离 A/B 的 GFM 八语料几何均值为 `0.9549x`、`0.9623x`，many-reference/GFM 稳定约 `0.88x`，large-table/GFM 稳定 `0.898x`/`0.911x`；raw JSON SHA-256 分别为 `9d662877cced8dea225901a78261a8b0d08ac4c7c87b6755574c72bd31f0d3c1`、`f0c371d9c6075b522f678c6fe6f2301c0ad876e5786fa663f08f082c9acb7420`。
- 完整测试命令 `cjpm test --no-color --no-progress --report-path /tmp/markdown-owned-children-tests --report-format xml` exit `0`：`1411/1411` passed，0 skipped/error/failed；format 和 `cjpm check` 均 exit `0`。
- Server CPU 24 的 DWARF `perf record -F 997 -g --call-graph dwarf` 对 256 KiB pathological GFM、100 次渲染捕获 4888 samples、0 lost：GC phase transition `19.48%`、memset/allocation `9.91%`、parseInline `4.22%`、resolveDelimiterPieces `4.05%`、writeHtmlEnter `3.33%`、inlineSpecial `2.74%`、StringBuilder.append `2.11%`。perf data SHA-256 `e3138c7983301e5618b379c6c102d54aa37ccf43a952162937aaeb49fe18f481`，text report SHA-256 `3ff995dec06b0636a3e3443420ca25d50ad381b7091b363402ff3452ff7f2fe6`。
- 按 cmark opener 链表改写 delimiter stack 的候选在目标 pathological 语料为 CommonMark `1.0285x`、GFM `1.0061x`，已回退；连续 Text run 一次性 coalesce 候选使 pathological GFM `1.0419x`，也已回退。没有把仅理论上减少分配、实测却回退的改动留在发布候选。
- 当前正式 raw report 为 `docs/reports/benchmark-raw.json`，SHA-256 `9ac920aaaa4111027322be068691954a999d56350e8ccb1fc31b80a963ef8573`。固定 Server CPU 24、同一 SDK、7 samples × 3 iterations 的 harness exit `1`：CommonMark `5.261142x`、GFM `4.128814x`，slope `0.852194`、最大相邻 `1.989656`、pathological slope `0.792435`、extra RSS `59464 KiB`。除 CommonMark/GFM `2.5x` ratio 外所有门槛通过；`MD-PERF-002` 继续 `blocked`，未放宽阈值。

## 2026-08-21 retained candidate 与后续分配实验

- 当前保留源码的 parser SHA-256 为 `3f2c21e0b3f7a91632dd4b89eed177ed71d53b7f65778e0df40e1897520d273c`，远端 release driver SHA-256 为 `c60b5f0be5e4d0ed9b8c061571aa260cf27d517980efe1711128dc946d2e9c32`。保留改动包括精确 `Array<LineRecord>`、28-bit offset 的 `UInt32` packed native records，以及 `decodeLinkValue` 对反斜杠和实体标记使用单次 byte probe，避免进入 `String.contains` 的重复验证路径。
- `decodeLinkValue` 的两轮固定 CPU 24、1 MiB、12 轮交替 A/B 中，many-reference CommonMark candidate/baseline 为 `0.95573`、`0.95372`，GFM 为 `0.94976`、`0.97041`；JSON SHA-256 分别为 `4fd8481b58c40ed52004adff86b9c3f4865fbc916619ccccfc13a5ff0f6d7885`、`ae3ed410876e8527a2f25797a3c7269861baa6a5011e37f93aea70c287c04f7e`，两轮 checksum 均一致，因此保留。
- 本地 `scripts/check_format.sh` 和 `cjpm check` exit `0`。第一次沙箱内 `cjpm test` 在创建 `std.unittest` 协调 socket 前失败（0 个测试执行）；以 socket 权限原命令重跑 exit `0`，`1411/1411` passed，0 skipped/error/failed。
- 固定 Server CPU 24、同一 pinned SDK、7 samples × 3 iterations 的完整 release harness exit `1`；raw report SHA-256 `aaac470be4aa98df3f70f4e070c11db84de0fb214526df62b5939af4e5fe0e03`，已同步到 `docs/reports/benchmark-raw.json`。CommonMark `4.469416x`、GFM `4.028095x`；slope `0.851007`、最大相邻 `2.006987`、pathological slope `0.798977`、最大相邻 `2.376026`、extra RSS `58820 KiB` 均通过。SourceMap 开销 `35.50%`、CST 开销 `1033.83%` 已记录；仍只有两个 `2.5x` ratio gate 失败。
- 逐语料剩余高比值集中在 CJK（CommonMark `7.950x`、GFM `8.136x`）、README（`6.566x`/`6.058x`）、emoji（`6.012x`/`6.312x`）、reference（`5.898x`/`4.787x`）和 CommonMark table（`5.577x`）。远端 DWARF profile 仍以 GC phase（约 `18%`）、memset/allocation（约 `9%`）、parseInline、StringBuilder 和 URI/render 路径为主，scanner 已非主要瓶颈。
- 精确行数双遍扫描、reference-definition 预筛选、GFM autolink 预扫描、单遍 lazy GFM materialization 和小容量 `ArrayList` 五组候选均经固定 CPU、1 MiB、12 轮交替 A/B 拒绝；其总体 candidate/baseline 分别为 `1.02966`、`1.00402`、复测 `1.00693`、复测 `1.00936`、缩减后 `1.01638`。对应 raw SHA-256 为 `a8be88d8c1d75532ce6a34c16873d1d26571e02bca5859a1cdfd6a27be3e6a6e`、`023f2c729f8ee8fcf94c5f769b885a5f059ed69a51eaa8d38c6e73093806c4b2`、`cbc13e45ee2b5e9de7f9e45f450854504f2feb2285fc6d815a9178f93d6c5692`、`b2052c0bb747315d9cee99dbaf073bd23cb673fa55b3fac1330aace674dffc3a`、`d1026a6199478bb6c222bd07401057f11e105568e24cc23c197b43b1890102e1`。所有候选均已回滚，稳定 parser hash 恢复为 `3f2c21...273c`。

## 2026-08-21 renderer 输出与 reference link 优化

- benchmark harness 改为逐语料交替配对，奇数样本反转执行顺序；`comparisonProtocol.ordering` 写入 raw report，避免先跑完 markdown 再跑 reference 造成的系统漂移。当前 `benchmarks/measure.py` SHA-256 为 `7c35b1ac8b4ed9eca35308435168df614e6117d2b597999e3e30bc8e613bbbb4`。
- Server CPU 24 的 `perf record -F 999 -g` 在 1 MiB CJK CommonMark 上采集约 4K samples、0 lost：GC phase transition `17.82%`、`memset`/allocation `11.89%`、`parseInline` `9.09%`、`storedText` `2.75%`、native scanner `2.01%`。1 MiB GFM large-code 优化前约 6K samples、0 lost：`escapeText` `25.93%`、GC `23.32%`、`StringBuilder.append` `19.13%`、String 构造 `8.14%`、`memmove` `6.69%`。
- `src/renderer.cj` 保留三层优化：转义时按连续普通区间 append；`CodeBlock.literal` 只物化一次并把开标签、正文、闭标签分段写入；内置 `StringTextSink` 直接接收 code escape 区间，避免完整 escaped 临时 String。escape-run 的 12 轮 A/B raw SHA-256 为 `08e96983412b52070ed2b221d81951414a3e2e044edf1b46985cd05802ba9082`，GFM geomean `0.966956`。
- 所有 link 直接分段输出虽然 many-references 稳定快约 `35%`，但 inline CJK link 稳定回退 `13%`–`15%`；最终仅 `FullReference`、`CollapsedReference`、`ShortcutReference` 走单次 budget/cancellation + 直接 sink append，Inline/Autolink 保持单 tag String。两轮 12-round A/B raw SHA-256 为 `af77c823e59cc45c6d0e93099b55873a31892f0e9fd0cb25d8a812ccd15fe77b`、`80434e26f0b3dbc50bcb1c9d057fdf3816f6f90e5d59f94375e8690597e35a40`，GFM geomean `0.979599`、`0.957051`；所有 checksum 一致。
- 当前 parser SHA-256 `c1854a356d2e2ece4d958a8925d2b469585c1288f3045df63d4ce3f5ba114f14`，renderer SHA-256 `cc0e4fe45cc4544c7cade20d5fda744a95446cab8aebd2e74d4b32fc1a8fb26c`。`scripts/check_format.sh`、`cjpm check` exit `0`；socket-enabled 全量 `cjpm test` exit `0`，`1411/1411` passed。
- 当前完整 release harness 采用 Server CPU 24、固定 SDK、7 samples × 3 iterations、逐语料交替配对，exit `1`；raw report SHA-256 `1a6bc43d80376a1f9c47173006c338ebbe9ff9c43bd76f62e9055a0aff08c011`。CommonMark `4.329382x`、GFM `3.276393x`；slope `0.961197`、最大相邻 `2.399741`、pathological slope `0.866012`、最大相邻 `2.281035`、extra RSS `59632 KiB` 均通过，仍只有两个 `2.5x` ratio gate 失败。
- 已拒绝并回滚：按 depth 复用无 delimiter Node buffer（总体 `1.005402`）、Unicode byte-run scan（`1.008051`）、1 MiB renderer 预分配（GFM 复测 `1.000908`）、所有 link 直接输出（CJK 回退）、逐行 `withRawData`（总体 `0.999252`、CommonMark `1.005194`）。未将不可复现或跨 profile 回退纳入当前源码。

## 2026-08-21 S0 reference URI attribute cache stop/go

- S0 候选只在单次 `renderTo` 内为 reference link 缓存最终 URI attribute，最多 256 项；候选 renderer SHA-256 `1503e4e33df42d037190c6abe54cd337ea01b2a879c5ef1b84425e5c7ff1127c`，远端 candidate driver SHA-256 `70e51613b2d7bf4689d215e4f131e32a5afc8cdbb1394b6c7cc1239c0967c924`，baseline driver SHA-256 `d4e7fa6f6cf53d72b6a59ad66daff43457df8da1580e97764d543d899e04ff18`。
- 固定 Server CPU 24、固定 SDK、1 MiB、11 个正式语料、12 轮交替配对并在第二次反转首轮顺序；另运行 unique-link guard。raw JSON `/tmp/markdown_pair_link_attribute_cache_run1.json` SHA-256 `8dd1a38961bd3deff4dfbfe103bb5fe6620ea7239355afb6b6b3087cc7d6055d`，第二次 `/tmp/markdown_pair_link_attribute_cache_run2.json` SHA-256 `1a45f6e495962ab4bb10c1695b6bddd4e76a22c69e46fd8aedde905e531ed18c`；所有逐样本 checksum 相等。
- 第一次/第二次 many-reference GFM candidate/baseline 分别为 `0.974967`/`0.973003`，均未达到 `<=0.95`；11-corpus GFM geomean 分别为 `1.012694`/`0.999817`，均未达到 `<=0.98`。CJK、readme、unique-link guard 没有连续两次超过 `1.03`，但核心门槛失败；两次最大 candidate-baseline peak RSS 差分别为 `+11168 KiB`、`+31180 KiB`。
- 按冻结 stop/go 完整回退 S0 cache/helper/参数传播及 3 个专用测试，保留 cache 前 direct reference/code/plain-run renderer 优化；本地与远端临时 worktree 的 renderer SHA-256 均精确恢复为 `cc0e4fe45cc4544c7cade20d5fda744a95446cab8aebd2e74d4b32fc1a8fb26c`。候选/baseline 二进制和 raw 只保留在 `/tmp` 供复核。因此未运行正式 release benchmark，也未改写 `docs/reports/benchmark-raw.json` 或 `benchmark.md`。
- 回退后 `scripts/check_format.sh` exit `0`，`cjpm check` exit `0`；沙箱内第一次 `cjpm test` 因 unittest 控制 socket 权限在 0 tests 前失败，socket-enabled 原命令重跑 exit `0`，`1411/1411` passed。`python3 scripts/test_check_public_api.py` 为 `8/8`，`python3 scripts/check_public_api.py` 验证 `1155` declarations。`MD-PERF-002` 保持 `blocked`，最新正式证据仍为 CommonMark `4.329382x`、GFM `3.276393x`。
- 最终 diff 审计发现当前 `docs/reports/benchmark-raw.json` 是本轮前已存在的本地 CPU 2 / Arch 报告（SHA-256 `adecf410140ed0bfc65528473fadd7cba6b2c458a438b88dfa021bafa6b05f8b`，CommonMark `4.579341x`、GFM `3.968396x`），不是授权 Server CPU 24 证据；本轮未修改该文件，也不以它替代最近已验证的 Server raw。该并发/既有漂移需在下一次正式 Server benchmark 成功生成报告时统一校正。

## 2026-08-25 产品名统一

- 仓库、产品、根 cjpm 包、公开命名空间和 CLI 命令统一为 `markdown`；CLI 工程目录由旧路径迁移到 `tools/markdown`。内部包名 `markdown_cli` 只用于区分 CLI 工程与根依赖，不作为产品名展示。
- README、PRD、CLI 文档、changelog、脚本、benchmark runner、历史报告、raw JSON 字段、需求账本和验收记录同步改名；第三方对比库 `markdown4cj` 保持其正式名称。排除生成目录后的旧产品名扫描为 0。
- CLI 验证再次生成的 `tools/markdown/build-script-cache` 已删除，根 `.gitignore` 新增 `**/build-script-cache/`，后续子工程构建不会再把本机预构建脚本缓存带入源码归档或工作区差异。
- 改名不改变任何 benchmark 样本或 ratio。标签规范化后当前文件摘要为：`benchmark-raw.json` `a107300090f599152ffd8e9020465666ed1b3b91c7e2fccd783ddcfc29d897d9`，`benchmark.md` `a8387ff89585a32eb445cb82e02e7732226875c141f4d8bd10c8db5a6f48e590`，同语言 raw `6d67ac4a9db3d6a64aaebfeb56d498658a3a248ecbf2787aa87889a03ac882a7`，同语言报告 `a6faf8d59555294552ce8ec603c072b858b447730ede6978d62bb389d1fe78ef`。
- 验证：Python 脚本编译、125 项 YAML、3 份 JSON、`scripts/check_format.sh`、`cjpm check`、CLI release build、CLI smoke、API checker 8/8、1155 声明快照及 socket-enabled `cjpm test` 1410/1410 全部通过。第一次沙箱内全量测试在执行 0 个用例前因 `std.unittest` socket 权限失败，随后以相同命令在允许 socket 的环境通过。

## 2026-08-25 P0 correctness 与 release evidence

- 构造路径统一执行 `maximumAstNodes`；代码块、HTML、inline 与扩展 literal 在累计/合并时执行 `maximumLiteralBytes`、operation budget 和 cancellation，未恢复解析后的全树遍历。
- fingerprint 改为类型标记加 UTF-8 字节长度前缀编码；SourceMap 改为 renderer 写出时记录 generated/source ranges 并使用二分查询；artifact schema v1 对非 identity mapping fail closed。
- 新增低节点数、多行 fenced code/HTML、Parser SPI 批量节点、delimiter/Unicode/empty/order fingerprint、标签名碰撞及 invalid UTF-8 artifact 回归。全量 socket-enabled 测试为 1413/1413。
- `cjpm` 实测拒绝 `1.0.0-rc.1` prerelease 字符串，因此包版本从 `1.0.0` 调整为可构建的 pre-GA `0.8.0`，文档不再冻结完整 1.x 表面。新增 `release-evidence.json`、生成/校验脚本、fail-closed release gate 和 Linux LTS/current SDK 托管 CI 定义。
- README、canonical benchmark report 与 acceptance report 的当前数字都投影自 `release-evidence.json`。现有 raw SHA-256 `a1073000...d897d9` 对应 6.980369x/5.989632x，但未记录受测 source commit 和 SDK，且早于本轮 P0 改动，因此明确标记 `stale-unbound`，不能作为当前候选发布证据。
- 仓库 `.gitignore` 显式反忽略根目录 `release-evidence.json`，覆盖开发机全局 `*.json` 规则，保证该 canonical 证据文件不会在提交时静默遗漏。
- 最终验证：format、API snapshot 1155、API checker 8/8、release-evidence tests 3/3、`cjpm check`、root/CLI/quickstart build、quickstart run、socket-enabled full suite 1413/1413 均 exit 0；`cjpm bundle --skip-test` 生成 `target/markdown-0.8.0.cjp`（SHA-256 `8782dcc1...cfd527`）。`--release-ready` 按预期 exit 1，明确列出 draft、source unbound、benchmark stale 和 SDK unbound。

## 2026-08-25 P1 input profiles 与 scanner capability

- `MarkdownEngineBuilder.nativeScannerEnabled(false)` 可强制 byte-backed 输入走纯仓颉 line scanner；默认行为保持不变。`EngineCapabilities` 新增 available/enabled/String-path 三个显式字段。
- benchmark driver 新增 `commonmark-parse-string`、`-bytes`、`-owned`、`-stream`；历史 `commonmark-parse` 明确保留为 owned alias。`measure.py` 的新 raw schema 会分别记录每轮 copy/decode、process preparation 和 native scanner 使用情况。
- 四种 driver mode 已实际执行并产生相同 checksum；Python contract tests 2/2、API checker 8/8、API snapshot 1159、定向 input/capability 8/8 以及 socket-enabled full suite 1414/1414 全部通过。
- 该 P1 切片当时仍静态链接 scanner archive；随后 S20 已把默认包改为纯仓颉、将 foreign/linker 边界移入显式 accelerator，并增加 target-aware `.a`/`.lib` 构建。真实非 Linux SDK/linker 资格仍须平台 runner 验证。

## 2026-08-25 optional native、buffered execution、package surface 与 native fuzz

- 根 `cjpm.toml`、CLI 和 quickstart 已移除 native link option；foreign 声明只存在于 `markdown.native`。默认 engine 走纯仓颉 scanner，byte/owned/stream 只有通过 `acceleratedBy(NativeLineScanner())` 才启用 C scanner。以不存在的 `CC`/`AR` 在全新 `/tmp` target 执行默认 `cjpm build` exit 0，证明纯构建不调用 C toolchain。
- `scripts/build_native_scanner.py` 默认 no-op，显式 `--enable` 后按 target 生成 Unix/MinGW `.a` 或 MSVC `.lib`，工具链完全由 `CC`/`AR` 提供；4/4 command-contract tests 通过。Linux 上实际 archive、显式链接的 benchmark driver、无 native 的 quickstart 和 CLI 均构建通过。非 Linux 实机 SDK/linker 资格未在本机伪造。
- `BufferedInputSession`、`BufferedAsyncHtmlOutputSession`、`tryParse` 与 `ExecutionModelCapabilities` 明确 stream/chunk/async 都是 buffered adapter：finish 前不产生语义、async 仅表示 sink backpressure、failure result 不含 completed prefix。旧名称保留兼容行为。
- 新增 `markdown.core/render/extensions/editor/artifact/document/testkit` 精选子包；根 `markdown` 保留 umbrella 兼容。公开表面审计将内部 `NodeIdAllocator`、`Sha256` 收回为 internal，API snapshot 最终为 1192 declarations。quickstart 仅导入精选 public packages 并运行成功。
- 新增 scanner libFuzzer、ASan/UBSan deterministic harness、4 个稳定 seed 和版本化历史 crash corpus。`scripts/fuzz_native_scanner.py --runs 10000` exit 0；mutation 在临时 corpus 中进行，ASan/UBSan clean。Cangjie 历史 crash regression 纳入全量测试。
- 最终验证：format exit 0；`cjpm check` exit 0；API checker tests 8/8；API snapshot 1192；build-helper tests 4/4；benchmark input-profile tests 2/2；pure/native/driver/quickstart/CLI build 与 CLI smoke 全部 exit 0；full `cjpm test` exit 0，1423/1423 passed，0 skipped/error/failed。
- 账本仍为 125 total、122 pass、3 blocked。该切片未重跑或覆盖 canonical 远端 release benchmark；`MD-PERF-002` 及其连带的 `MD-REL-001`、`MD-QUAL-001` 保持 blocked，整体仍为 INCOMPLETE。

## 2026-08-25 commit-bound canonical release benchmark

- 受测产品来自提交 `0275f27a1d8fea38262127b245ca5e4c81c9b3a8` 的最小源码归档（SHA-256 `cfad40e29f83d0d34b1327935c2c15af75cf033496aba0b85551ea437f459428`）；远端 release driver SHA-256 为 `7c83262fd4fd1f6506255100688ed3f1c0379eff0be529c5840afb6e89fb3a5c`。归档明确排除 `target`、`build-script-cache`、`.agents`、`.codex` 和本机构建产物。
- 发现 CommonMark/GFM `spec.txt` 被开发机全局 `*.txt` 忽略规则静默排除；仓库 `.gitignore` 已反忽略两份冻结语料，远端用 release-evidence 中的 SHA-256 逐一验证。第一次有效采样后又发现 Python schema 误写 JSON 布尔字面量；改为 Python `True`/`False` 并增加 AST 回归，3/3 通过。失败运行均未覆盖 canonical raw。
- 最终固定 Server CPU 24、Cangjie `1.1.0-alpha.20260803040049`、12 个 256 KiB 语料、每进程 3 iterations、每侧 warmup + 7 个交替配对样本。命令 exit `1`：CommonMark `5.842342x`、GFM `4.982426x`，只失败两个 `2.5x` ratio gate；ordinary `4.019176x`/`2.704565x`、slope `0.861705`、最大相邻 `2.076031`、pathological slope `0.914978`、extra RSS `69700 KiB` 均通过。
- SourceMap 开销 `2.31%`，CST/snapshot 开销 `1040.41%`。1 MiB 输入 profile 中位耗时：String `0.211546s`、Array `0.221442s`、Owned `0.213213s`、InputStream `0.235104s`；各入口的复制、转换和 native scanner 语义已写入 raw。
- canonical raw SHA-256 为 `1b025514500df45128e92a5fb72c77897773222e72f98e95c72db1ee89e23f57`。raw 同时绑定 harness `e35120dc...131a26`、markdown driver `7c83262f...3a5c`、cmark driver `385d4f18...a95e` 和 cmark-gfm driver `6f8ad2cf...e0b4`。README、benchmark report、账本和 acceptance report 已由 `release-evidence.json` 同步；整体仍为 **INCOMPLETE**。
