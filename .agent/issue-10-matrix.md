# Issue #10 验收矩阵

范围为 MD-00..08 和原始验收 ID，不删除或缩小需求。PASS 仅描述下面实际运行的维度；
核心分支已交付 [PR #12](https://github.com/lIlIIlIll/markdown/pull/12)，issue 未关闭。发布边界为 breaking pre-GA `0.10.0`，STS `1.2.0`。

## 证据标记

- **F1**：兼容清理修订 `88db33b`，生产 tree
  `6c777aa402a9de37ca65bfc86b1fabcc5af9420678dfc78d9e31a40b1e6f1ce1`，官方 STS 1.2.0 Linux；
  完整 1621/1621、零 skipped/errors/failures，API 1706，格式/文档/70 项 Python 检查 PASS。
  后续测量修订 `b930377` 的生产 tree 相同。具体 checkpoint 见[实施记录](issue-10-status.md)。
- **S1**：[append 成本](../docs/reports/append-cost.md)：336 个进程，七轮保留样本；
  每 feed/首块/收尾/实际收费/patch/RSS 与批量 oracle，PASS；不宣称常量内存。
- **E1**：[editor/cache 取舍](../docs/reports/editor-cache-cost.md)：3168 个进程，A/A、交替
  A/B、实际受限变长编辑与两种恢复原型、1371 份公开 wire 字节证明；未放宽采用门槛。
- **C1**：[功能成本](../docs/reports/feature-cost.md)：1056 feature + 48 actual rich/fallback
  进程，扩展密集、重复脚注、碰撞标题、热 byte-array/应用冷启动 warm-FS、真实后端/缓存，PASS。
- **N1**：Node 后端修订 `db67810` 的真实 STS/Chrome/clipboard/离线 runtime gate PASS；
  固定 runtime `66482adc432167538bbcccac7a431bcbf9d6d93653981333609ef0ede5d0ba39`。
  当前正式库的全套本地实际 browser/clipboard/timeout/cancel、七种 fixture 和实际 Chrome 清理
  gate 也 PASS，HTML SHA-256 为 `cb42c140c0fb6877dea3b3c7345a6212c92e7dbc86e711875f007697f72e70ad`。
  PR #12 的 Linux 能力分类修复使用新离线 runtime
  `9d7f66290e664254501b6a293fe6eb9218c79b1f86a7779f94acb297669dd5a4`：4 项能力回归、
  7 类生命周期、2 类实际 Chrome 清理及 browser/clipboard 全部 PASS；不重绑 C1 成本样本。
  C1 校验实际成本；基础包不依赖 Node，不宣称 OS sandbox。
- **P1**：修订 `b930377c2ea52f4afbd5e4c93a354bda41809c82` 的全新 attested 构建：C 比值
  2.2662144957 / 1.7966549619，增长/病理/RSS gate 全 PASS；同语言 12/12、几何平均
  13.880235098、最大 RSS 比 0.525891473，所有冻结门槛 PASS。Arch 和 Ubuntu 断网新目录
  从保留源码/官方 SDK/native/link 闭包重建三项产物，逐字节验证 PASS。新测量没有重绑旧数字。
- **G1**：干净预检提交 `e31221204753a20b229dd9875cec64afb9aec207` 的 26 步全部 PASS，
  包括完整测试/语料、native ASan+UBSan fuzz10000、CLI、两个示例、差分25/24/1/0、
  benchmark smoke3/3 和候选打包。真实 manifest SHA-256 为
  `4d6fbf6f9edc44a4b6a16bcf9578c784b903614fb0d2f0e169ca55f4ead424d2`，treeState=clean。
  在写入 readiness 前，就绪校验器已用该 manifest 验证拟议状态、JUnit/API/校验和，
  返回零错误。最终原始 release gate 的执行 commit、步骤和候选 hash 以独立 evidence
  中的 `target/release-evidence/manifest.json` 为准。Hosted core CI 记录见 H1。

- **H1**：[hosted 证据记录](issue-10-hosted-evidence.md)：核心 head `d383eac` 的 push
  `39185741396` 与 PR `39185745072` 全部成功，实际 27 步 manifest/JUnit/校验和已复验。
  canonical 采用稳定分支提交的 push artifact `12158042400`，同语言 12/12、geomean
  `10.330166028`、最大 RSS 比 `0.555294453`，Arch/Ubuntu 断网字节重建均 PASS。
  最终 head 的实时检查见 PR #12；静态证据不预先宣称新 metadata 提交已通过 CI。


所有功能行的 PASS 指 F1 的实际公开行为回归；成本行明确引用各自测量修订，不将其冒充
P1 或 G1。完整原始日志、执行文件和失败诊断在独立 evidence 中保留，公开报告去除本机路径。

## MD-00 新模型

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-00.1 | [typed payload](../src/binding.cj)、[公式来源](../src/math.cj)、[代码组](../src/code_groups.cj) 分离原文/语义/派生产物 | F1：DocumentBindingTests、StructuredMathTests、CodeGroupTests PASS | 无 |
| MD-00.2 | [共享绑定器](../src/binding.cj)、[标题目标](../src/headings.cj)、[解析管线](../src/parse_pipeline.cj) | F1：DocumentBindingTests、HeadingBindingTests、ExtensionLifecycleTests PASS | 无 |
| MD-00.3 | [lineage/serial](../src/node_identity.cj)、不可变 revision、归属检查 | F1：[NodeIdentityTests](../src/node_identity_test.cj)、EditorSemanticAcceptanceTest PASS；P1 成本 gate PASS | 无 |
| MD-00.4 | [ParseOutcome](../src/parser.cj)、成功专用 ParseResult、临时 AppendDraft | F1：core/input/append failure tests PASS | 无 |
| MD-00.5 | 删除 ast/parsePartial/StableNodeId/processor/buffered-output/profile aliases/旧 scanner adapters；保留单条准确命名的完整输入便利路径 | F1：NodeIdentityTests、InputBehaviorTest PASS；[迁移清单](../docs/migration-0.10.md) | 无 |
| MD-00.6 | transform → bind → analysis → prepare → render，整文能力早期拒绝或明确延后 | F1：[ExtensionLifecycleTests](../src/extension_stages_test.cj) PASS | 无 |
| MD-00.7 | SPI 3、plan 6、artifact/wire 3、renderer fingerprint 5；旧格式拒绝，无自动迁移 | F1：artifact/binary/identity tests、1706 声明检查 PASS | 无 |
| MD-00.8 | 真实后置脚注/标题样例贯穿 batch/append/绑定/多输出/source/snapshot | F1：binding、append、组合语义 tests PASS | 无 |

## MD-01 脚注

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-01.1 | typed label/source、首定义优先、文档作用域 | F1：DocumentBindingTests 的重复/未定义/来源断言 PASS | 无 |
| MD-01.2 | 正文首次有效引用编号，后续 reachable 定义队列；未引用定义保留 AST | F1：postDefinedFootnotes、nestedReachableFootnotesAndCycles PASS | 无 |
| MD-01.3 | 共享普通 block parser，四列续段、列表/引用/代码 | F1：DocumentBindingTests、DefinitionListTests PASS | 无 |
| MD-01.4 | 独立引用锚点、完整脚注区、多回链/可访问名称、scope | F1：精确 HTML 和 href/target/source 断言 PASS | 无 |
| MD-01.5 | MD4001/2/3、可见原文、显式 strict、代码隔离 | F1：undefinedDuplicateUnusedAndCodeSyntax、关闭标准 caret links PASS | 无 |
| MD-01.6 | HTML/Text/Markdown/SourceMap/lint/rewrite/artifact 消费统一语义；依赖编辑完整回退 | F1：binding/artifact/editor semantics PASS | 无 |
| MD-01.7 | 统一引用/锚点/回链工作量与来源上限 | F1：referenceAndGeneratedAnchorWorkShareTheConfiguredBudget PASS；C1 512 引用成本 | 无 |

## MD-02 定义列表

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-02.1 | [定义列表 2.0](../docs/definition-lists.md) 固定邻接/空行/两列续段/终止 | F1：DefinitionListTests PASS | 无 |
| MD-02.2 | List/Entry/Term/Definition roles，dl/dt/dd 层级 | F1：groupsMultipleTermsAndDefinitionsWithExactHtmlTextAndMarkdown PASS | 无 |
| MD-02.3 | 正常块 children 与精确来源；不二次切源码 | F1：bodyUsesNormalBlocksAndKeepsContainerUnicodeAndCrLfPositions PASS | 无 |
| MD-02.4 | setext、冒号、代码、引用/列表、孤立 marker 明确 | F1：orphanMarkersSetextCodeAndDisabledProfilesRemainOrdinaryMarkdown PASS | 无 |
| MD-02.5 | 全部输出/CST/snapshot/append 与资源边界 | F1：DefinitionListTests、formatter/组合语义 PASS | 无 |

## MD-03 标题与目录

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-03.1 | 标题专用 HeadingIdPayload 与 HeadingBinding，原始 suffix span | F1：suffixIsHeadingOnlyAndSetextContainerMetadataKeepsExactSource PASS | 无 |
| MD-03.2 | hN id、TOC/query/fragment 共用 bindings | F1：scopedFragmentLinksQueriesLintAndSnapshotConsumeTheSameTargets PASS | 无 |
| MD-03.3 | 显式 ID 预留、诊断与后缀、Unicode/空标题、共享脚注分配器 | F1：HeadingBindingTests PASS；C1 256 个碰撞标题 | 无 |
| MD-03.4 | 结构化 TOC、层级范围、跳级嵌套 | F1：unicodeEmptyAndRepeatedHeadingsHaveDeterministicStructuredToc PASS | 无 |
| MD-03.5 | 新 slug 算法及单一目标，无旧自动锚点双写；保留来源/Markdown | F1：HeadingBindingTests、source map/snapshot PASS | 无 |
| MD-03.6 | 标题文字/ID/删除/碰撞变化诚实回退，重新绑定 | F1：EditorSemanticAcceptanceTest 的依赖编辑 PASS | 无 |

## MD-04 能力与语义语料

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-04.1 | [官方矩阵](../docs/extensions.md) 与实际 profile/capabilities | F1：officialCapabilityMatrixMatchesActualProfilesEnablementAndOutput PASS | 无 |
| MD-04.2 | Front Matter 起点/BOM/CRLF/空/未闭合/literal | F1：OfficialExtensionsTest 的两组精确 Front Matter 用例 PASS | 无 |
| MD-04.3 | Smart Punctuation 2.0 最长匹配，URI/code/HTML/metadata 保护 | F1：[SmartPunctuationTests](../src/smart_punctuation_test.cj) PASS；无引号引擎声明 | 无 |
| MD-04.4 | 精确多输出、关联、诊断、SourceSpan、组合 fixture | F1：binding/heading/definition/math/code-group/semantic contract tests PASS | 无 |
| MD-04.5 | 独立/组合/关闭、版本/注册/优先级、错误/limits/cancel | F1：官方矩阵、ExtensionLifecycleTests、SemanticContractTests PASS | 无 |
| MD-04.6 | 破坏性 API/SPIs 同步；有效旧边界迁到新 API | F1：1706 声明、原始 CM652/GFM671、旧 scanner 风险迁移 PASS；P1 门槛未变 | 无 |

## MD-05 可选富内容

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-05.1 | [preparer](../src/rich_preparation.cj) 与不可变 typed products，派生数据不进 AST | F1：RichContentTests；N1/C1 实际链路 PASS | 无 |
| MD-05.2 | 固定 KaTeX/Mermaid CLI/Shiki 的独立 [Node adapter](../docs/node-rich-backend.md)，许可/离线闭包 | N1：39,274 文件 manifest、离线重建同 identity、真实浏览器/产物 PASS | 无 |
| MD-05.3 | 默认纯仓颉，可信宿主显式路径/能力，无 author command 或隐式下载 | F1：禁用/missing/fail-closed；N1 网络 guard、C1 无安装步骤 PASS | 无 |
| MD-05.4 | 验证 MathML/token/PNG，固定 URI/预算；受信进程不称 sandbox | F1：不可信树/颜色/PNG 拒绝；N1 真实外部请求拦截 PASS | 无 |
| MD-05.5 | Disabled/Missing/Unsupported/TimedOut/Failed/Limited；原文回退，strict opt-in | F1：RichContentTests；N1 真正 timeout/cancel/crash；C1 fallback PASS | 无 |
| MD-05.6 | Unicode/BOM/CRLF 原始 copy，generated 粗粒度 source map，无伪字符映射 | F1；N1 实际 Clipboard API/MathML/PNG/彩色 token/SourceMap PASS | 无 |
| MD-05.7 | Code Groups 1.0 固定 Group/Item/title/ranges、普通代码 children、静态与可选控件 | F1：CodeGroupTests；N1 actual keyboard/AX/clipboard/no-script PASS | 无 |
| MD-05.8 | 成功缓存 key 含实际后端/config/theme 依赖，失败不缓存，proxy/subreaper 清理 | F1：缓存/配额；N1 七种 fixture+实际 Chrome 清理；C1 冷/热成本 PASS | 无 |

## MD-06 追加与可恢复输出

| ID | 实现 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-06.1 | 共享 parser/binder，feed-time 闭合 AST fragments；完整输入驱动保留 | F1：1323 原始标准输入 × 六种 chunk，共 7938 对照 PASS | 无 |
| MD-06.2 | session/from/to/sequence/target、Append/Replace/Remove/finalBind、Replica 原子校验 | F1：错序/丢失/重复/跨 session 不变状态 PASS | 无 |
| MD-06.3 | 后置链接/脚注、tight/loose、table/setext、最终 processor 修订 | F1：AppendSessionTests/AppendRevisionAndWorkTests/标准语料 PASS | 无 |
| MD-06.4 | 单字节/随机/逐行/整文、Unicode/CRLF/fence，语义与位置一致 | F1：7938 对照与 invalid-byte 分块 fuzz PASS | 无 |
| MD-06.5 | finish/error/cancel/终态误用、严格/替换 UTF-8 | F1：terminal encoding/resource/cancellation tests PASS | 无 |
| MD-06.6 | 跨 feed 累计 pending/input/node construction/scan/patch/batches；终态释放 | F1：累计上限和线性实际工作回归 PASS；S1 内存不作常量声明 | 无 |
| MD-06.7 | lazy HTML cursor + UTF-8 accepted-prefix backpressure，无整份预构造 | F1：1323×3 policies×3 widths=11907 暂停/恢复对照、sink/cancel/limits PASS | 无 |
| MD-06.8 | 首块/feed/finish/scan/node/patch/RSS 与小 chunk/长尾规模矩阵 | F1 线性收费回归；S1 七轮成本 PASS | 无 |

## MD-07 编辑

| ID | 实现/测量 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-07.1 | 真实 fast/full 命中、构造器/扫描/map 收费、端到端 timer、VmHWM | E1 全部原始行；构造器计数不冒充堆分配 | 无 |
| MD-07.2 | 实际普通段落/标题变长局部候选，不预设 rope/piece table | E1：中间插入/删除及最终 oracle PASS；未测得整体收益，不采用 | 无；测量型项允许有证据不采用 |
| MD-07.3 | byte/UTF16/span/CST/map/SourceMap/diagnostics 全链对照 | F1：[EditorSemanticAcceptanceTest](../src/editor_semantics_test.cj) PASS；E1 包含全量重建成本 | 无 |
| MD-07.4 | 引用/脚注/标题及文档 stage 无法证明局部时完整回退 | F1：依赖编辑和 ExtensionLifecycleTests PASS | 无 |
| MD-07.5 | 新 lineage/revision、共享节点归属、旧 NodeRef/lint fix 拒绝 | F1：NodeIdentityTests 与 editor 公开回归 PASS | 无 |
| MD-07.6 | CST/索引/源 hash/坐标/RSS 一起测，不以减少 scan 代替收益 | E1：不采用所有复杂候选；无 P95/零回退声明 | 无 |

## MD-08 格式与性能

| ID | 实现/测量 | 测试与结果 | 未完成原因 |
| --- | --- | --- | --- |
| MD-08.1 | 12 阶段 parse/snapshot/CST/map/编码写入/读校验/重解析/render/SourceMap | E1 全部样本；C1 增加实际扩展与后端成本 | 无 |
| MD-08.2 | 实际 source-reparse vs AST 中间恢复 vs AST+token 恢复 | E1：较大受限 wire 有收益但通用认证不全，保留生产简单 reader | 无；不把受限原型当作已交付 reader |
| MD-08.3 | 生产 wire3 重新 parse 和验证配置/source/AST/CST/边界；opaque payload 拒绝 | F1：binary/artifact/opaque tests PASS；未交付受限直接 reader | 无 |
| MD-08.4 | 读/写/损坏/截断/超限/错版本/配置；lossless 与多输出一致 | F1：binary artifact/editor/source-map tests；E1 1371 公开字节证明；C1 应用冷/热路径 PASS | 无 |
| MD-08.5 | 固定输入 API/profile/native/SDK/tree/flags，A/A 交替 A/B，完整 AST | E1/C1 保存身份和全部原始样本；P1 未放宽冻结门槛 PASS | 无 |
| MD-08.6 | 扩展密集/重复脚注/碰撞标题/chunk/编辑/缓存/实际 rich 开关 | S1/E1/C1 成本与原始数据齐全，均完成 oracle | 无 |
| MD-08.7 | 每个候选明确不采用及原因，区分噪声/无中位收益/认证不完整 | E1 决策表，保留失败与限制；P1 无未经证明的优化 | 无 |

## 原始最低验收 ID

| ID | 实现/测试映射 | revision/环境/实际结果 | 未完成原因 |
| --- | --- | --- | --- |
| ARC-T01 | MD-00.1/.2/.8、binding/typed payload 多输出样例 | F1 PASS | 无 |
| ARC-T02 | MD-00.4/.5/.7、failure/old scanner/old wire | F1 PASS | 无 |
| EXT-T01 | MD-01.1..4、完整脚注绑定/回链/多段 | F1 PASS | 无 |
| EXT-T02 | MD-01.5、未定义/重复/未使用/代码隔离 | F1 PASS | 无 |
| EXT-T03 | MD-02、DefinitionListTests | F1 PASS | 无 |
| EXT-T04 | MD-03、HeadingBindingTests+编辑依赖 | F1 PASS | 无 |
| EXT-T05 | MD-04.1/.5、官方 profile/开关矩阵 | F1 PASS | 无 |
| EXT-T06 | MD-04.2/.3、Front Matter/SmartPunctuationTests | F1 PASS | 无 |
| RND-T01 | MD-05.1..3、真实固定三种后端及 missing/default | F1/N1/C1 PASS | 无 |
| RND-T02 | MD-05.4..8、异常/超限/取消/不可信输出/代码组 | F1/N1 PASS | 无 |
| STM-T01 | MD-06.1/.4、7938 chunk/标准语料对照 | F1 PASS | 无 |
| STM-T02 | MD-06.2/.3、后置语义与原子错序校验 | F1 PASS | 无 |
| STM-T03 | MD-06.7、11907 resume/policy/width 对照 | F1 PASS | 无 |
| EDT-T01 | MD-07、公开编辑回归和真实候选实验 | F1/E1 PASS，不采用复杂候选 | 无 |
| ART-T01 | MD-08.3/.4、binary/artifact/opaque/cache tests | F1/E1/C1 PASS | 无 |
| PERF-T01 | MD-06.8、MD-07/08、固定完整工作量与 source-to-binary | S1/E1/C1/P1 PASS | G1/H1 已验证；实时最终检查见 PR #12 |

## DONE 关闭条件

| ID | 状态 | 实现/证据/剩余原因 |
| --- | --- | --- |
| DONE-01 | PASS | 已核对当前 issue、AGENTS、真实源码；零向后兼容已由 issue 明确要求；标准兼容与实用单一路径仍保留 |
| DONE-02 | PASS | 本页保留全部 ID、实现/测试/修订/环境/实际结果；本地与 hosted 维度明确区分 |
| DONE-03 | 本地 PASS | F1/P1/G1：完整构建/测试/标准语料/consumer/fuzz/benchmark/bundle；readiness 由真实 manifest 校验，最终执行记录独立保留 |
| DONE-04 | PASS | 未修改 SDK、原始标准语料、安全/资源/冻结性能门槛；旧接口的有效风险已迁移，无静默 skip |
| DONE-05 | 本地/离线/记录修订 hosted PASS | H1 保留真实 run、artifact、测试与独立重建；当前 canonical 指针已切到核心实际 CI，最终 head 状态见 PR #12 |
| DONE-06 | 已交付 PR #12；未合并 | 核心与测量矩阵、本地/离线/记录修订 hosted 均通过；测量型候选有证据不采用。issue 由 PR 关联，最终检查与合并由维护者审阅 |
| DONE-07 | PASS | 0.10 breaking pre-GA；无旧 facade/reader/双写主轨；核心 push/PR #12 已获单独授权；未 merge/release。先前保护检查迁移亦为明确单独授权，不自动修改规则 |
