# markdown 实施计划

## 0. 2026-08-18 最终实施校准

本计划的 S0-S11 主链路已有可运行实现，最终全量测试为 1410/1410，
CommonMark/GFM 官方语料为 652/652 与 671/671；随后执行
`cjpm bundle --skip-test` 通过并生成当前包，避免无意义地重复同一轮测试。
当前仍不能声明 GA：`requirements.yaml` 有 3 个 `blocked` 项；私密安全
报告渠道已启用并验证，但 `benchmarks/measure.py` 的性能 GA gate 真实失败，
并连带阻塞 release 与 quality gate。

本轮性能切片已按 profile 证据完成：`LineRecord`/list marker 改为值类型、
共享空 immutable array、普通 inline 跳过 delimiter 链、段落只计算一次续行
状态、块规则按首字节分派、内置 profile 跳过空扩展规则、引用预扫描减少无关
规则调用。全部改动保持公开 API snapshot 1155 项不变，并通过 1410 项回归；
最终固定矩阵仍未达到 PRD 数值，因此该切片不能转为 `pass`。

后续依赖顺序冻结为：

```text
allocation profile and performance convergence
→ full correctness/performance/package gate rerun
→ final 125/125 audit
```

每个后续切片仍必须同时修改行为、负例/正例测试、文档和需求账本；性能
切片不得通过更换阈值、缩小 reference 集或跳过原始样本来转为 `pass`。

## 1. 计划边界

本计划依据 `docs/prd/markdown-library.md` PRD 2.0 制定。需求状态、实现位置、测试和证据只在 `requirements.yaml` 中维护；本文件只描述架构、依赖顺序与实施切片，不拥有独立的完成状态。

目标分三层：

- `1.0`：P0/GA，按 M0-M6 交付。
- `1.1`：P1 编辑器、lossless、lint/transform 等能力，按 M7 交付。
- `2.0+`：真正增量解析、外部数据方言、隔离插件和文档图等长期能力。

可以报告某一里程碑的验收结果，但只要 `requirements.yaml` 中仍有非 `pass` 条目，就不得宣称整个 PRD 已完成。

## 2. 架构

### 2.1 运行时主链路

```text
SourceInput
  → SourceBuffer / SourcePositionMap
  → Versioned MarkdownDialect
  → DialectCompiler
  → immutable CompiledMarkdownDialect
  → bounded ParseSession
  → reference collection
  → explicit-frame block parse
  → inline parse
  → extension postprocess
  → AST invariant validation
  → immutable Document
  → TreeRewriter / Transform Pipeline
  → explicit Renderer policy
  → bounded TextSink
```

长期编辑器链路在同一 Source/AST 边界上增加：

```text
DocumentSnapshot
  → lossless CST + SyntaxToAstMap
  → Semantic AST
  → lint / transform / fix
  → PreservingFormatter / RangeFormatter
  → TextEdits + Rendered SourceMap
```

### 2.2 逻辑模块与职责

| 模块 | 职责 | 允许依赖 |
| --- | --- | --- |
| `markdown_core` | source、position、AST、diagnostic、limits、budget、cancellation、SPI contracts | 仓颉标准库 |
| `markdown_commonmark` | CommonMark block/inline/reference parser、精确 profile | `markdown_core` |
| `markdown_gfm` | GFM 扩展与两个 GFM profiles | `markdown_core`、`markdown_commonmark` 的公开扩展点 |
| `markdown_dsl` | dialect/syntax/renderer DSL、compiler、fingerprint | `markdown_core` |
| `markdown_transform` | Walker、Visitor、TreeRewriter；P1 Transform DSL/pipeline | `markdown_core` |
| `markdown_html` | Spec/GFM/Safe HTML、structured builder、URI policy、Sink | `markdown_core`、公开 renderer SPI |
| `markdown_format` | Plain Text、Canonical Markdown；P1 preserving/range | `markdown_core`、公开 renderer/format SPI |
| `markdown_lint` | P1 lint、Fix-It、Explain | `markdown_core`、公开 syntax/AST API |
| `markdown` | 稳定 public façade 和便利 API | 上述生产模块的公开 API |
| `markdown_cli` | `markdown` 命令行 | `markdown`；不得被库反向依赖 |
| `markdown_testkit` | conformance、TCK、fuzz/differential helpers | 生产模块；不得被生产模块依赖 |

硬边界：AST 不依赖 renderer，CommonMark 不依赖 GFM，parser 不依赖 CLI，生产代码不依赖 TestKit，unsafe HTML 位于独立命名空间。任何跨边界请求先更新架构决策和 `assumptions.md`，不得在实现中悄悄形成反向依赖。

### 2.3 核心契约

- 规范位置只有 UTF-8 byte offset；UTF-16 和 visual position 都是派生视图。
- AST 不可变、无环、可并发只读；NodeId 仅保证 Document 内唯一和确定。
- raw、semantic、normalized/comparison 值分开保存和使用。
- profile、dialect、engine、renderer 的版本/指纹职责分层。
- parser、transform、renderer 共享 cancellation、operation budget、limits 和结构化错误模型。
- Safe HTML 通过结构化 builder 和独立 Link/Image URI policy 实现；`TrustedHtml` 是显式 unsafe capability。
- 所有可能受输入规模影响的分配在分配前检查上限。
- 默认 hard error 不产生完整 AST；扩展和 Sink 失败不被吞掉。

## 3. 依赖顺序

```text
S0 契约与证据基础
 └─ S1 Source / Position / Error / Limits / AST schema
     ├─ S2 CommonMark parser + Spec HTML
     │   ├─ S3 Chunked / Cancellation / Sink / Resource hardening
     │   └─ S4 GFM exact + modern profiles
     ├─ S5 Dialect / Syntax / Renderer DSL + Extension SPI/TCK
     └─ S6 AST operations / transforms foundation
         └─ S7 Safe HTML / Text / Canonical Markdown
             └─ S8 Public façade / Capability / CLI
                 └─ S9 Conformance / Fuzz / Perf / Docs / Release
                     └─ S10 P1 lossless/editor toolchain
                         └─ S11 P2 incremental and ecosystem features
```

并行限制：只有接口已经在下层切片冻结、文件所有权不重叠、同一验收证据不由实现者自证时，才拆并行工作。测试与其验证的行为放在同一切片，不留到最后补齐。

## 4. 实施切片

### S0：契约冻结与可复核证据基础（M0）

范围：`MD-GOV-*`、`MD-ARCH-*`、`MD-PRO-*`、`MD-DIA-003`、`MD-VAL-*`、`MD-ERR-*`、`MD-COMP-*`。

交付：

- 冻结 profile IDs、public AST schema、SourceSpan、值模型、error/diagnostic codes。
- 冻结 dialect descriptor、fingerprint canonical serialization、SPI/DSL/plan versions。
- 固定仓颉 SDK、Tier 1 平台清单、官方 fixture 版本与归属、reference host 与 benchmark protocol。
- 建立 conformance、unit、metamorphic、fuzz、benchmark 和 API snapshot harness。

退出门槛：核心语义均有书面契约；测试 harness 能在空实现上给出预期失败；不得以临时公开 AST 进入大规模 parser 实现。

### S1：Source、位置、资源与 AST 基础（M0/M1）

范围：`MD-IN-*`（除完整 chunk session）、`MD-POS-*`、`MD-AST-*`、`MD-LIM-*`、`MD-CAN-*`、`MD-BUD-001`、`MD-CON-001`。

交付：

- String/bytes/stream、UTF-8 policies、newline/BOM、immutable SourceBuffer/SourceSlice、detach。
- UTF-8 span、UTF-16 mapper、position types。
- immutable AST、NodeId、Custom Node、invariant validator。
- ParseLimits、OperationBudget、CancellationToken 和共享 error context。

退出门槛：多字节、CRLF、非法 UTF-8、边界 limit、深度输入和并发只读测试通过；所有超限在大分配前失败。

### S2：CommonMark Core 与 Spec HTML（M1）

范围：`MD-PAR-*`、`MD-PRO-001` 的 CommonMark 部分、`MD-HTML-001` 的 SpecCompatible 部分、`MD-TST-001` 的 CommonMark 部分。

交付：block parser、reference collection/resolution、inline parser、容错、raw HTML nodes、Spec HTML renderer。

实施次序：

1. line/block state machine 与 container 显式栈；
2. reference definition table；
3. delimiter/entity/link inline engine；
4. AST validation；
5. exact Spec HTML；
6. 官方示例逐组收敛。

退出门槛：CommonMark 0.31.2 官方测试 100%，无长期 skip，无已知 crash。

### S3：分块、取消、预算与 Sink（M1）

范围：`MD-IN-004`、`MD-CAN-*`、`MD-BUD-001`、`MD-SINK-001`、`MD-SEC-002-003`、`MD-TST-003`。

交付：chunked session、跨 chunk decoder/state、取消检查点、扫描/回调/输出预算、同步 Sink。

退出门槛：all-at-once 与 1-byte/random/边界 chunks 全等；取消后无扩展调用和 Sink 写入；Sink 失败原样传播；病态输入不栈溢出。

### S4：GFM profiles 与官方 P0 扩展（M2）

范围：`MD-PRO-001` 的 GFM 部分、`MD-PAR-002-005` 的 GFM 行为、`MD-EXT-006` 的 1.0 部分、`MD-TST-001` 的 GFM 部分。

交付：Table、Task List、Strikethrough、Extended Autolink、Tag Filter、`gfm-0.29`、`gfm-modern-v1`。

退出门槛：GFM 0.29-gfm 官方测试 100%；modern-v1 与正式 GFM 的差异文档完成；两个 profile 独立快照和差分测试通过。

### S5：DSL、编译计划与扩展生态（M3）

范围：`MD-DIA-*`、`MD-SYN-*`、`MD-RDSL-*`、`MD-EXT-001-005`、`MD-CAP-001`。

交付：Dialect/Syntax/Renderer DSL、immutable plan、规则验证/排序、fingerprint、manifest、capability matrix、Parser SPI、Extension TCK。

退出门槛：所有冲突/无界/版本/renderer coverage 负例在 build 阶段失败；fingerprint determinism 100%；官方扩展 TCK 100%。

### S6：AST 操作与变换基础（M5）

范围：`MD-OPS-001-002`；为 `MD-TRN-001`、`MD-OPS-003` 保留接口边界。

交付：非递归 Walker、typed Visitor、查询、immutable TreeRewriter、结构共享和变换后 invariant validation。

退出门槛：所有 rewrite 操作、深树遍历、结构共享和错误 AST 测试通过；P1 pipeline 不被 1.0 façade 误报。

### S7：安全 Renderer、Text 与 Canonical Markdown（M4）

范围：`MD-HTML-*` 的 P0 项、`MD-TEXT-001`、`MD-FMT-001-002`、`MD-SEC-003-004`、`MD-TST-004` 的 Safe HTML 部分。

交付：Safe/GFM HTML、structured builder、Link/Image policy、Plain Text、Canonical Markdown、streaming Sink integration。

退出门槛：安全 corpus 全过；普通 String 无法注入；危险 URI 默认拒绝；formatter 幂等与语义保持 100%；无无界 renderer buffer。

### S8：Public façade、Capability 与 CLI（M5）

范围：`MD-API-*`、`MD-PKG-001`、`MD-CLI-*`、`MD-CAP-001`、`MD-OBS-001`。

交付：`markdown` façade、便利 API、`markdown` 命令、structured exit codes、本地 opt-in stats。

退出门槛：public API review 完成；CLI 每种 exit code 有端到端测试；未交付 P1/P2 能力明确报告 unsupported/capability=false。

### S9：发布加固（M6）

范围：`MD-TST-*`、`MD-PERF-*`、`MD-DET-001`、`MD-DOC-*`、`MD-SEC-005`、`MD-REL-001`、`MD-QUAL-001`。

交付：官方/差分/病态/fuzz/API compatibility 测试，固定主机 release benchmark，文档、示例、报告与包元数据。

退出门槛：所有 target=`1.0` 的验收证据齐全；`requirements.yaml` 对这些条目逐项为 `pass`；独立验收人重新运行发布 gate。若 P1/P2 尚未完成，只能声明“1.0 GA scope passed”，不能声明整个 PRD 完成。

### S10：1.1 lossless 与编辑器工具链（M7）

范围：`MD-CST-*`、`MD-TRN-001`、`MD-OPS-003`、`MD-ANN-001`、`MD-HTML-005-006`、`MD-FMT-003-004`、`MD-EVT-001`、`MD-LINT-*`、`MD-EXP-001`、`MD-EDIT-001`、`MD-ART-001`，以及 P1 官方扩展和异步 Sink adapter。

依赖次序：lossless representation → AST/CST map → snapshot/edit validation → preserving/range format → lint/fix/explain → source map/event/artifact → P1 official extensions。

退出门槛：lossless round-trip、最小差异、stale fix 防护、artifact cache miss、source-map 和 snapshot 行为全有测试；不得把全文重解析描述为局部增量。

### S11：2.0+ 增量与生态能力

范围：`MD-EDIT-002`、`MD-FUT-*`。

依赖次序：stable syntax identity → invalidation graph → incremental diagnostics/source map → StableNodeId → external data dialect → plugin isolation → multi-document/document graph → binary format/paging。

退出门槛：每项能力有独立版本化契约、capability flag、资源/安全模型和跨 snapshot 测试。当前这些条目已通过；后续修改必须保持对应回归。

### S12：P0 correctness/resource contract hardening（2026-08-25）

范围：`MD-LIM-002`、`MD-DIA-003`、`MD-HTML-006`、`MD-ART-001`。

依赖次序：构造时 node/literal limits → canonical fingerprint fields → renderer write-time SourceMap → artifact identity restriction → targeted attacks → full suite/API gate。

交付：bounded parser allocator、`BoundedLiteralBuilder`、长度前缀 descriptor、write-time range recorder、binary-search SourceMap queries，以及 schema-v1 identity-mapping cache restriction。

退出门槛：低节点数、多行 code/HTML、Parser SPI、delimiter/Unicode/empty/order fingerprints、tag-name collision 和 invalid UTF-8 artifact 回归全过；format/check/build/API/full suite 全过。该切片已达到退出门槛。

### S13：release evidence and version reset（基础设施已实施，证据待刷新）

范围：版本改为 0.x 或 RC、缩减 RC 阶段的 1.x 冻结承诺、托管 CI、规范语料可复现获取，以及单一 `release-evidence.json`。

依赖次序：冻结 evidence schema → 选择 RC/version policy → 生成 commit/SDK/target/flags/corpus/reference/raw/conformance/API digests → 由该文件生成 README/report/acceptance 投影 → 托管 CI 多 SDK/平台验证。

退出门槛：仓库内只有一个 canonical current result；README、benchmark report、raw digest、账本和 acceptance report 可由同一 evidence 文件复核，且不再把 pre-GA 状态与 `1.0.0` 完整冻结承诺并列。版本、生成器、fail-closed gate 和 Linux 双 SDK CI 已落地；2026-08-25 raw 已绑定 source commit、SDK、源码归档、harness 和三个 driver，但两个 `2.5x` ratio gate 仍失败且 evidence tree 尚未提交，因此本切片仍未达到发布退出门槛。完成前不得发布 GA。

### S14：input profiles and native scanner execution capability（2026-08-25）

范围：P1 默认 String 与 owned-byte benchmark 偏差、native scanner on/off capability，以及输入 API 成本归因。

交付：engine 级 native scanner 开关；available/enabled/String-path capability；String、Array、Owned、InputStream 四个可执行 benchmark mode；future raw report 的复制、转换和 scanner metadata；兼容 alias 文档。

退出门槛：四种 mode 对同一输入产生相同 checksum；native on/off 公共解析语义相同；API snapshot、format/check/build 和全量测试通过。该执行层切片已达到退出门槛，但静态 native archive 的完全可选打包与跨平台产物仍属于后续 build-system 工作。

### S15：indexed source positions（2026-08-25）

范围：`MD-POS-001-003` 的高频编辑器查询成本与 visual-column 语义校准。

交付：`SourcePositionMap` 持有共享 `SourceIndex`；line starts 二分定位；长行按 bounded checkpoints 计算 UTF-16 与 visual scalar 列；ReplaceInvalid decoded/original mapping 二分定位；显式 `DisplayWidthPolicy`，且保留旧构造器行为。

退出门槛：CRLF、emoji、非法 UTF-8 replacement、tab policy 和跨 checkpoint 长行与原 `SourceBuffer` 语义一致；API snapshot、format、build 和全量测试通过。该切片已达到退出门槛；终端 cell/grapheme width 不在此切片范围，见 A-030。

### S16：shared CST token arena and query indexes（2026-08-25）

范围：`MD-CST-001-002` 的嵌套 token 重复存储与 AST/CST/token 反查成本，并校准局部增量 capability 的命名。

交付：一个 `SyntaxTree` token arena；`SyntaxNode.tokens` 作为共享 backing 的不可变 range view；NodeId→SyntaxNode、NodeId→MarkdownNode、TokenIndex→smallest semantic node 索引；byte offset→token 二分；`incrementalMode=block-local-with-full-fallback`。

退出门槛：lossless bytes、token categories、双向映射、defensive-copy API、byte lookup、formatter/lint/snapshot 全量回归通过；旧 `SyntaxNode` 构造器与 `tokens` 公开类型保持兼容。该切片已达到退出门槛；CST overhead 的 canonical 数字必须在下一次绑定当前 commit 的远端 release benchmark 中刷新。

### S17：SemVer dependency correctness（2026-08-25）

范围：`MD-DIA-004`、`MD-COMP-001` 的 extension manifest 与 dependency minimum 版本语义。

交付：完整 `major.minor.patch` 解析；prerelease identifier precedence；build metadata 非排序语义；leading zero、空 identifier、非法字符和 Int64 overflow fail closed；仓库示例/fixture 迁移到完整 semantic version。

退出门槛：release/prerelease、numeric/text prerelease、build metadata、无效/不完整/溢出版本均有回归；现有 DSL、SPI、fingerprint、capability 与外部 descriptor 全量测试通过。该切片已达到退出门槛；implementationVersion 继续作为不透明 fingerprint identity。

### S18：Safe renderer URI/target hardening（2026-08-25）

范围：`MD-HTML-002-003` 的 data-image allowlist 与外部链接 target 安全细节。

交付：data URI 只按首个参数前的完整 media type 做大小写无关等值匹配；Safe policy 的外部 `_blank` 链接强制包含 `noopener noreferrer`，并按 ASCII whitespace token 去重；compatibility policy 不静默改变输出。

退出门槛：合法 MIME 参数、前缀碰撞、大小写、已有 rel token 和 SpecCompatible 对照回归通过；format、check、API snapshot 和全量测试通过。

### S19：arbitrary-byte UTF-8/chunk differential fuzz（2026-08-25）

范围：`MD-IN-002`、`MD-TST-004` 的任意 bytes、Strict/ReplaceInvalid 和 chunk partition 风险。

交付：256-case 任意字节 deterministic corpus；all-at-once/chunked 成败、decoded text、original byte length、diagnostics、HTML 与 AST invariants 差分；修复 GFM email punctuation 和 HTML-block ASCII lowercase 的 UTF-8 byte-boundary 崩溃。

退出门槛：固定 seed 的任意 bytes corpus 在 Strict/ReplaceInvalid 双模式无未处理异常，chunk partition 语义一致，全量测试通过；持续明确该套件是 deterministic property smoke，不冒充 coverage-guided native fuzz。

### S20：optional native、buffered execution 与 public surface（2026-08-25）

范围：`MD-IN-003-004`、`MD-SINK-001`、`MD-CAP-001`、`MD-PKG-001`、`MD-TST-004`。

交付：默认纯仓颉核心；显式 `markdown.native` accelerator 包装器；Unix/MinGW/MSVC target-aware archive 构建；明确 buffered stream/chunk/async/tryParse 合同；按 core/render/extensions/editor/artifact/document/testkit 收窄的公开子包；coverage-guided libFuzzer、ASan/UBSan scanner harness 与历史 crash corpus。

退出门槛：缺失 C toolchain 的默认构建通过；显式 native archive 和 benchmark consumer 可链接；跨 target 命令合同测试通过；全量测试、API snapshot、format、consumer example 和 10,000-run sanitizer fuzz 均通过。非 Linux 平台的真实 SDK/linker release matrix 仍由对应托管 runner 资格验证，不把命令合同测试冒充平台实机构建。

## 5. 每个切片的统一工作流

1. 在 `requirements.yaml` 选择本切片条目，确认全部 acceptance 可测试。
2. 若 PRD 含歧义，先更新 `assumptions.md` 并等待必要决策；不在代码中静默选择。
3. 先提交失败测试或可复核 fixture，再实现最小闭环。
4. 实现存在但尚未完成所有验证时，只能标为 `implemented_unverified`。
5. 运行单元、集成、规范、负例和适用的性能/跨平台 gate。
6. 在账本填入精确实现位置、测试命令/用例和不可变报告或日志路径。
7. 独立复核全部 acceptance 后才改为 `pass`。
8. 同步 `progress.md`；`acceptance-report.md` 只从账本生成验收投影。

## 6. 证据最低标准

- `implementation`：仓库相对路径和符号，必要时附 commit/change ID。
- `tests`：测试文件、case/fixture ID、实际运行命令和退出码。
- `evidence`：报告、原始日志、快照、benchmark 样本或发布产物的路径/摘要；不能只写“已验证”。
- conformance：固定规范版本、总例数、通过数、失败数、skip 数。
- 性能：reference host、CPU 绑定/环境、release build、参考实现版本、原始样本和统计方法。
- 安全/复杂度：最小输入、大小序列、预算/取消行为和 regression corpus。
- 跨平台：平台/SDK 矩阵与逐项 digest；只在 Tier 1 清单全部覆盖后通过。

## 7. 变更控制

- PRD 变更先更新 `requirements.yaml` 的 source/acceptance，再调整本计划。
- 已发布 profile、AST、diagnostic、SPI 或 artifact 的语义变更必须走兼容性评审。
- `blocked` 不是完成态；必须记录阻塞证据、责任人/外部依赖和解除条件。
- `acceptance-report.md` 与账本不一致时，以账本为准并重新生成报告。
