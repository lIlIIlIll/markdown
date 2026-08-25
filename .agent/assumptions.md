# PRD 歧义、解释与待决事项

本文件记录对 `docs/prd/markdown-library.md` 的解释。任何会改变功能、版本范围、安全默认或验收门槛的选择都必须先写在这里；实现者不得在代码中静默补全 PRD。

状态约定：

- `adopted`：仅用于形成当前计划的可逆解释，已有足够 PRD 依据。
- `decision_required`：实施到相关切片前必须由产品/维护者确认。
- `resolved`：已获得明确决策；应同时记录决定、日期和影响的 requirement IDs。

## A-001：何时可以说“完成”

- 状态：`adopted`
- 涉及：全部 requirements
- 解释：`requirements.yaml` 同时记录 1.0、1.1、2.0+ 和跨版本约束。可以单独说“1.0 GA scope 已通过”，前提是所有适用于 1.0 的条目均为 `pass`；但只要账本中任何条目不是 `pass`，不得说“整个 PRD/项目已完成”。
- 理由：同时满足 PRD 的分期路线与用户给出的“只有全部为 pass 才能声明完成”。

## A-002：必须、应该、可以如何入账

- 状态：`adopted`
- 涉及：`level` 字段
- 解释：`必须` 记为 `must`，`应该` 记为 `should`。`should` 不能因为实现困难直接标 `pass`；若要推迟，需明确批准并修改目标版本或 PRD。纯示例和未被选择的 `可以` 不当作强制交付；一旦 `可以` 被公开 API、冻结决策或路线目标采用，则入账并必须验收。

## A-003：PRD API 代码块不是最终仓颉语法

- 状态：`adopted`
- 涉及：`MD-DIA-*`、`MD-SYN-*`、`MD-RDSL-*`、`MD-API-*`
- 解释：PRD 明确将多个代码块称为 API/语义草案。计划冻结其语义能力与安全边界，不把示例拼写当作不可修改的最终签名。M0 的可编译 API review 决定最终仓颉语法，并回填账本证据。

## A-004：重复要求只保留一个状态

- 状态：`adopted`
- 涉及：PRD §7、§50-52、§54-55
- 解释：目标、里程碑、GA checklist、成功指标和冻结决策中重复出现的同一行为合并到一个 requirement；`source` 列出全部来源。里程碑退出条件在 `implementation-plan.md` 聚合，不创建会漂移的第二份状态。

## A-005：P0 架构预留不等于 P1 能力已实现

- 状态：`adopted`
- 涉及：`MD-CST-*`、`MD-HTML-006`、`MD-EVT-001`、`MD-EDIT-*`
- 解释：1.0 必须保留 Syntax Representation、source-map hook、snapshot 等依赖边界，但完整 CST、Rendered Source Map、Event API、Snapshot API 分别按 PRD 的 P1 目标验收。仅有占位接口不能把这些条目标为 `pass`。

## A-006：CLI 列表与 P1 功能存在版本交叉

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-CLI-001`、`MD-LINT-*`、`MD-EXP-001`、`MD-FMT-004`
- 歧义：PRD §41 将 `explain`、format `range`、check `lint` 列为 CLI 能力，但 §26.6、§34、§35 将底层能力放在 P1。
- 决定：最终产品必须实现全部列出的 CLI 命令；版本化 capability 决定某个发行版本是否可用。1.0 若早于 P1 能力发布，只能保留命令发现面并明确返回 unsupported/capability=false；完成整个 PRD 时 explain、range 和 lint 必须真实可用。

## A-007：ANSI/TUI renderer 的 1.0 边界

- 状态：`adopted`
- 涉及：`MD-RDSL-001`、`MD-TEXT-001`
- 解释：P0 Renderer DSL 能声明 ANSI/TUI backend capability，1.0 用 PlainTextRenderer 和第三方 renderer 支持终端场景；官方 ANSI/TUI renderer 属于 P1。Plain Text 默认不得输出 ANSI。

## A-008：`gfm-modern-v1` 的差异基线

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-PRO-001`、`MD-TST-001`、`MD-DOC-001`
- 歧义：PRD 固定扩展集合，但没有给出每个扩展叠加到 CommonMark 0.31.2 后全部边界行为的权威 fixture。
- 决定：`gfm-modern-v1` 以 CommonMark 0.31.2 parser 语义叠加 Tables、Task
  Lists、Strikethrough、Extended Autolinks 和 Tag Filter；项目自有组合快照位于
  `src/profile_snapshot_test.cj`。正式 GFM 0.29 仍使用独立 profile 和官方 fixture，
  modern-v1 不继承“精确 GFM 0.29”标签。

## A-009：官方测试数据的获取和归属

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-TST-001`、`MD-REL-001`
- 决定：CommonMark 使用官方 `commonmark/commonmark-spec` tag `0.31.2`、commit `9103e341a973013013bb1a80e13567007c5cef6f`；GFM 使用官方 `github/cmark-gfm` tag `0.29.0.gfm.0`、peeled commit `b8eb2e00de094999f978e9cb02b1a78d810812d3`。规范文本、官方 extractor/normalizer 和许可证固定在 `tests/spec/`，生成器不维护 skip/allowlist。

## A-010：Tier 1 平台清单未定义

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-DET-001`、`MD-QUAL-001`
- 歧义：PRD 要求 Tier 1 跨平台一致，但没有列出 OS、架构和 SDK 版本。
- 决定：首个 1.0 候选的 Tier 1 证据平台冻结为 Linux x86_64、Cangjie
  `1.1.0-alpha.20260817040003 (cjnative)`；其他 OS/架构在加入 Tier 1 前属于
  未承诺平台。跨平台确定性仍通过重复运行 digest/API snapshot 检查，不把单平台
  结果描述为多平台验证。
- 理由：PRD 未列出平台集合；采用当前可真实执行的最小 Tier 1 集合比虚构未运行
  的矩阵更保守。

## A-011：性能 reference host 未定义

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-PERF-001-003`
- 歧义：PRD 规定“固定 reference host 和 release build”及数值门槛，但没有机器、CPU 绑定、SDK、参考实现版本、预热/采样和统计协议。
- 决定：本候选版本 reference host 冻结为 Linux x86_64、Intel Core i7-8700
  6C/12T、Cangjie `1.1.0-alpha.20260817040003`、`-O2`、clang 15.0.7；参考实现
  固定为 cmark 0.31.1 commit `bb3678d7...` 与 cmark-gfm 0.29.0.gfm.13 commit
  `587a12bb...`。每个有效点至少 7 个进程内样本，发布原始 wall/RSS 数据和语料
  SHA-256。当前未固定 CPU 频率，因此噪声超过门槛的结果只能失败或重测，不能放宽。

## A-023：项目许可证

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-REL-001`、`MD-DOC-001`
- 歧义：PRD 要求发布物包含 license，但未指定许可证。
- 决定：采用 MIT License，版权主体写为 `markdown contributors`；第三方规范
  fixture 继续保留各自上游许可证，不重许可。
- 理由：MIT 是简洁、宽松且不改变上游测试数据归属的最小发布选择。

## A-012：`≈` 的 AST 语义等价规则未定义

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-FMT-001-002`
- 歧义：PRD 使用 `parse(render(ast)) ≈ ast`，未列出可忽略字段。
- 决定：semantic equality 比较 node kind、语义字段、children 顺序、reference resolution、task/table 状态和 custom typed payload；忽略 NodeId、SourceSpan、raw delimiter/trivia、NodeOrigin 和 diagnostics。若两个节点都声明 normalized value，则 normalized value 也必须相等。

## A-013：Safe 模式的远程图片默认值未明确

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-HTML-002-003`
- 歧义：PRD 要求 `allowRemoteImages` 可配置并强调隐私风险，但未直接给默认值。
- 决定：采用最保守安全默认，`allowRemoteImages=false`、`allowDataImages=false`；调用者必须显式开启并配置 MIME allowlist。该策略进入 RendererFingerprint、文档与测试。

## A-014：`ParseLimits.trusted()` 的具体数值未定义

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-LIM-001-002`
- 决定：`trusted()` 的可调规模上限初始为 `safe()` 的 8 倍；整数溢出、容器容量、AST 无环、调用栈和输出长度检查仍不可关闭。显式自定义 limits 必须全部为正数。

## A-015：SourceSpan 父子包含的例外

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-POS-001`、`MD-AST-006`
- 歧义：用户给出的账本示例要求嵌套节点范围包含于父范围，PRD 要求 span 合法，但 synthetic/transformed node 可能没有直接源范围。
- 决定：parsed nodes 必须有合法 span 且子 span 被父 span 包含；synthetic/transformed nodes 可以无 span，但必须有对应 NodeOrigin。derived span 必须覆盖全部 sourceNodeIds 的范围，不能伪造零长度位置。

## A-016：建议模块名与强制依赖边界

- 状态：`adopted`
- 涉及：`MD-PKG-001`、`MD-ARCH-002`
- 解释：PRD §40 的具体目录和逻辑模块称为“建议”，因此名称可在有记录的架构决策下调整；AST/CommonMark/CLI/TestKit/extension/unsafe HTML 的依赖禁止项是强制验收边界。

## A-017：核心“仅标准库”范围

- 状态：`adopted`
- 涉及：`MD-SEC-001`、`MD-PKG-001`、`MD-PERF-001`
- 解释：生产库和发布时链接图只允许仓颉标准库；testkit、fixtures、benchmark harness 可以调用 cmark/cmark-gfm/commonmark.js，但这些不得进入生产依赖闭包。CLI 是否可有额外纯仓颉依赖需在 M0 的 package policy 中明确。

## A-018：“明显二次增长”的量化门槛

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：`MD-SEC-002`、`MD-PERF-002`
- 歧义：PRD 给出 1-16 MiB 不得明显二次增长，但没有拟合方法和容忍噪声。
- 决定：固定 1、2、4、8、16 MiB 输入，每个点至少 7 个有效样本，以中位数做 log-log 线性拟合；斜率大于 1.35 或任一相邻翻倍的耗时比大于 3.0 判定失败。原始样本、环境和拟合脚本必须发布。

## A-019：Default diagnostic 与 ordinary Markdown tolerance

- 状态：`adopted`
- 涉及：`MD-PAR-008`、`MD-ERR-003`
- 解释：未闭合普通 Markdown 默认不产生 hard error；是否产生 warning/info diagnostic 由 versioned profile/extension contract 冻结。任何 diagnostic 差异会进入确定性和 profile snapshot。

## A-020：当前仓库基线

- 状态：`resolved`
- 决策日期：2026-08-17
- 涉及：当前进度
- 事实：实施前 HEAD 为 `71b95a518e701d16f02dbb9c5282c476b4ea5613`，GitButler
  common base/merge-base 为 `0133d479d2e8c8f03076233fd630bd3924d64db5`，workspace
  为 `gitbutler/workspace`，初始 dirty 路径只有 `.agent/` 与 `docs/`。
- 影响：未初始化或改写仓库；本轮所有新增实现保持 uncommitted，未把初始
  `.agent/`/`docs/` 简单归因于本轮，也未执行 reset/clean/stash/checkout/rebase/commit/push。

## A-021：PRD 排版异常不改变语义

- 状态：`adopted`
- 涉及：PRD §16.5、§44.5-6、§53.2-3 等
- 解释：若项目符号误写为正文中的 `-危险 URI`、`-版本`、`-跨 snapshot` 或类似排版残片，按上下文视为同级列表项；若该解释会影响行为合同，则升级为 `decision_required`。

## A-022：产品名、发行模块名与公开根命名空间

- 状态：`resolved`
- 决策日期：2026-08-25（统一修订）
- 涉及：`MD-GOV-001`、`MD-PKG-001`
- 决定：仓库、产品、发布包、公开根命名空间和 CLI 命令统一使用 `markdown`；CLI 工程位于 `tools/markdown`，其内部 cjpm 包名 `markdown_cli` 仅用于避免与根依赖同名，不是对外产品名。
- 历史处理：README、PRD、报告、原始报告字段、需求账本、进度和验收记录中的本项目旧称一并改为 `markdown`；第三方项目 `markdown4cj` 的正式名称保持不变。
- 影响：根 manifest 使用 `name = "markdown"`，用户通过 `import markdown.*` 使用公开 API；文档和证据不得再引入旧产品别名。

## A-023：私密漏洞报告渠道不能由实现 Agent 虚构

- 状态：`blocked_external`
- 决策日期：2026-08-18
- 涉及：`MD-SEC-005`、`MD-REL-001`、`MD-QUAL-001`
- 歧义：PRD 强制要求私密漏洞报告渠道，但仓库没有安全邮箱、托管平台 security advisory URL 或维护者提供的其他私密端点。
- 决定：发布响应流程和所需报告内容继续写入 `SECURITY.md`，但不把“repository security contact”占位文字当作可用渠道，也不虚构邮箱或外部服务。
- 影响：在维护者配置并验证真实渠道前，相关要求保持 `blocked`，项目不得声明 1.0 GA。

## A-024：`cjpm bundle` 的字节级可复现性

- 状态：`observed_non_normative`
- 决策日期：2026-08-18
- 涉及：发布验证记录
- 事实：相同源码连续两次 `cjpm bundle` 均成功，但 SHA-256 分别为 `54b6742342c9494eed9d824556b0e2ee2a62277c950a79a888c276d4c8644383` 和 `8eca4e127e1741b6347dafcca38b8b9a841db10dd9363cff23f06df0cc2380bf`；归档目录项记录了当前时间和本机 owner。
- 决定：PRD 没有字节级 reproducible-build 规范，因此不额外创建或弱化需求；验收报告仍公开记录该偏差。若发布系统要求可复现归档，需要在 cjpm 外增加规范化打包步骤或由工具链提供时间/owner 固定选项。

## A-025：病态 delimiter 的复杂度判定

- 状态：`resolved`
- 决策日期：2026-08-18
- 涉及：`MD-SEC-002`、`MD-PERF-002`
- 歧义：PRD 禁止简单重复模式触发“明显二次复杂度”，但没有为病态 delimiter 单独规定尺度、拟合方法或相邻翻倍门槛。
- 决定：固定 64、128、256、512 KiB 的未闭合链接、代码和 delimiter 组合输入，每点预热后取 5 个独立进程样本中位数，以 log-log slope `≤1.35` 为规范门槛；同时发布相邻倍增比作为诊断数据，但不因单个进程启动或分配阈值跳变单独否决。普通 1–16 MiB 输入仍按 A-018 同时执行 slope 与相邻倍增门槛。
- 证据：修复前直接尺度测试 slope `1.986`；最终 release-gate 固定 CPU 矩阵 slope `1.325`，不再呈明显二次增长并满足 `≤1.35` 门槛。

## A-026：`@FastNative` 扫描器的发布边界

- 状态：`resolved`（2026-08-22 修订）
- 决策日期：2026-08-19
- 涉及：`MD-PERF-002`、`MD-PKG-001`、`MD-DOC-001`
- 歧义：PRD 允许用 `@FastNative` 提升 foreign 函数性能，但要求函数不长时间运行、不阻塞且不调用仓颉方法；仓库同时需要保留可复核的 native scanner 入口。
- 决定：2026-08-19 的实现曾仅为 `MD_Markdown_ScanLines` 添加 `@FastNative`；后续审计确认，尽管其 C 实现只读输入、写 packed records、无锁无 I/O 且无 Cangjie 回调，整输入扫描的总执行时间随输入变化，无法证明短时且有界，因此在 2026-08-22 删除 annotation。native scanner 与 static archive 发布边界仍保留；仓库内 CLI、benchmark driver 和 quickstart 显式链接 `target/native/libmarkdown_scanner.a`，README/迁移文档公开该依赖。
- 理由：删除 annotation 满足运行时调用约束，不改变 foreign signature、packed record ABI 或发布依赖，也不代表 `MD-PERF-002` 已完成；parser、GC 和对象分配路径仍不得标记 `@FastNative`。
- 影响 requirements：`MD-PERF-002`、`MD-PKG-001`、`MD-DOC-001`。

## A-027：UInt64 repair 与 reference evidence 边界

- 状态：`resolved`（2026-08-23）
- 决定：P1 的 committed scanner declaration 保持 `CPointer<UInt64>`，native header/packed records、archive consumer 和 typed probe 均按 UInt64、无 cast 验证；工作树 UInt32 overlay 不属于本轮提交。reference tools 只来自 `/tmp/markdown-reference-tools-runtime-20260823-n3y44FGb` 的 `SUCCESS_SEALED` evidence，失败 roots 零复用。
- 证据：benchmark dependency H `db4392e2` 固化 paired seven-sample ordering 与 owned-input driver。H 之前的 raw `48dbad...` 及 `6.449555x`/`5.695987x` 仅为 historical pre-dependency measurement，不是 final acceptance evidence，且不得用于 trend/projection。
- 结论：历史 UInt32 `4.089529x`/`3.396847x` 只保留为 historical/superseded。包含 H 的 mode-exact final committed archive 已 fresh 通过 typed UInt64 no-cast ABI、F2/F3 与 differential；formal raw `9acd3c7b...3f950d0` 得到 CommonMark `6.234490x`、GFM `4.845909x`，故 `MD-PERF-002` 继续 `blocked`。
- 影响 requirements：`MD-PERF-002`、`MD-PKG-001`、`MD-REL-001`。

## A-028：schema-v1 artifact 与 literal limit 的保守边界

- 状态：`resolved`
- 决策日期：2026-08-25
- 涉及：`MD-LIM-002`、`MD-ART-001`、`MD-DIA-003`、`MD-HTML-006`
- 歧义：`maximumLiteralBytes` 可以解释为整个文档所有文本之和，也可以解释为单个语义 literal 在跨行/合并构造中的累计值；artifact schema v1 没有保存原始 bytes 与 decoded→original mapping。
- 决定：`maximumLiteralBytes` 限制每个最终语义 literal 的累计字节数，多行 fenced/HTML/extension 和 Text coalescing 均在构造时检查；文档总资源仍由 `maximumInputBytes`、`maximumAstNodes` 和 operation budget 共同限制。artifact 采用方案 B，仅允许 `SourceBuffer` 的原始/解码 offset mapping 为 identity；`ReplaceInvalid` 结果直接拒绝缓存，不猜测或丢弃映射。
- 理由：该解释保留现有公开 limit 形状，不引入事后全树遍历；schema v1 无法安全表达原始字节身份，拒绝比错误命中更兼容且 fail closed。
- 后续：若 schema v2 支持非 identity 输入，必须同时保存 input kind、UTF-8 policy、original bytes digest、decoded digest 和 offset mapping identity，并增加 mutation/fuzz 证据。

## A-029：native scanner 开关与 benchmark 兼容名称

- 状态：`resolved`
- 决策日期：2026-08-25
- 涉及：`MD-CAP-001`、`MD-PERF-001`、`MD-PKG-001`
- 歧义：既有 `commonmark-parse` 已用于历史报告和外部脚本，但实际调用 owned-byte API；运行时关闭 native scanner 是否等同于移除 native 构建依赖也容易混淆。
- 决定：保留 `commonmark-parse` 作为 `commonmark-parse-owned` 的兼容 alias，并新增 String/Array/Owned/Stream 四个明确 profile。builder 开关只控制解析执行路径；capability 同时报告 available、enabled 和 String 路径是否使用 native。当前静态 archive 仍是包链接依赖，不把“禁用执行”描述为“纯仓颉发布物”。
- 理由：避免历史 harness 静默换入口，同时让默认 README API 与最优 owned-byte API 的成本可分别测量；不对尚未实现的跨平台无 native 打包作虚假声明。
- 后续：真正移除 native 链接依赖需要独立 package/build feature 或可选 accelerator 模块，并在目标平台矩阵证明。

## A-030：VisualPosition 的显示宽度边界

- 状态：`resolved`
- 决策日期：2026-08-25
- 涉及：`MD-POS-002`、`MD-POS-003`
- 歧义：既有 `visualPosition` 名称可能被理解为终端 cell、grapheme cluster 或 Unicode scalar 列；PRD 只明确要求 tab stop，未要求 wcwidth/grapheme 算法。
- 决定：保持既有默认语义为 Unicode scalar 列并按固定 tab stop 展开，新增 `DisplayWidthPolicy.UnicodeScalar` 允许关闭 tab 展开；capability 和文档使用 `visual-scalar`/`visual-scalar-with-tab-stops` 明示含义。CJK、combining mark、variation selector 和 ZWJ emoji 不声称使用真实终端显示宽度。
- 理由：保持旧构造器和行为兼容，同时消除名称隐含的过度承诺；若未来加入 terminal-cell/grapheme policy，应作为新的显式策略和测试矩阵。
- 影响 requirements：`MD-POS-002`、`MD-POS-003`。

## A-031：incremental capability 的范围

- 状态：`resolved`
- 决策日期：2026-08-25
- 涉及：`MD-EDIT-001`、`MD-CAP-001`、`MD-DOC-001`
- 歧义：布尔 `incrementalSupport=true` 可能被误读为任意编辑都局部重解析，但当前实现只优化单个等字节长度、无 reference/extension 依赖的顶层 paragraph/heading 纯文本编辑。
- 决定：保留布尔值表示存在真实增量路径，同时新增并文档化 `incrementalMode="block-local-with-full-fallback"`；所有不满足约束的编辑明确回退全文解析并返回 `wasIncremental=false`。不得称为完整 incremental parser。
- 理由：不破坏已有 capability 消费者，同时让范围可机器读取并与实际执行模型一致。
- 影响 requirements：`MD-EDIT-001`、`MD-CAP-001`、`MD-DOC-001`。

## A-032：extension semanticVersion 与 implementationVersion 的语义

- 状态：`resolved`
- 决策日期：2026-08-25
- 涉及：`MD-DIA-004`、`MD-COMP-001`
- 歧义：manifest 同时暴露 semanticVersion 和 implementationVersion；旧实现把前者的 `-`/`+` 后内容截断并接受不完整版本，但 PRD 明确声明项目采用 SemVer。
- 决定：`semanticVersion` 和 `ExtensionDependency.minimumSemanticVersion` 必须是完整 SemVer，按 prerelease precedence 比较并忽略 build metadata；`implementationVersion` 保持不透明构建身份，仅参与 fingerprint，不进行大小比较。方言自身的 version 仍是 versioned identity，不在本切片静默改成 dependency constraint。
- 理由：这修复 `1.0.0-alpha >= 1.0.0` 的错误，同时避免把任意构建标签错误解释为 SemVer。
- 影响 requirements：`MD-DIA-004`、`MD-COMP-001`。

## A-033：可选 native、buffered 命名与包表面兼容策略

- 状态：`resolved`
- 决策日期：2026-08-25
- 涉及：`MD-IN-003-004`、`MD-SINK-001`、`MD-CAP-001`、`MD-PKG-001`、`MD-TST-004`
- 歧义：要求既可解释为删除现有根包 API 并实现真正增量 parser，也可解释为校准执行合同并提供可逐步采用的窄入口；直接删除已公开符号会违反现有兼容约束。
- 决定：采用成本更低且可验证的 buffered 路线，新增 `BufferedInputSession`、`BufferedAsyncHtmlOutputSession` 和 `tryParse`，保留旧名称并明确它们不提前产生语义、不降低峰值内存。根 `markdown` 继续作为兼容 umbrella；新增 `markdown.core/render/extensions/editor/artifact/document/testkit` 精选子包。0.8 pre-GA 审计确认 `NodeIdAllocator` 和 `Sha256` 仅为内部构造/fingerprint helper，收回为 internal；其余既有行为型 API 不在本切片删除。native foreign 声明隔离到 `markdown.native`，byte/owned/stream 仅经显式 `acceleratedBy` 包装器启用；默认 build 不执行 C toolchain、不携带 linker option。
- 理由：保留已有消费者的源码/布局兼容，同时让新消费者只导入所需能力；一个共享 parser 避免维护两套语义实现。非 Unix 支持以 target-aware `CC`/`AR` 或 `cl`/`lib` 构建及 consumer linker 资产为边界，真实平台发布资格仍须在相应 SDK runner 验证。
- 影响 requirements：上述条目的 notes 引用本假设；不得把 buffered adapter 宣称为真正 incremental execution，也不得把跨 target 命令测试宣称为实机平台验证。

## 决策记录模板

```text
### A-XXX：标题

- 状态：resolved
- 决策日期：YYYY-MM-DD
- 决策人：
- 决定：
- 理由：
- 影响 requirements：
- 需要更新的代码/测试/文档：
```
