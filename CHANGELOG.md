# Changelog

本文件记录用户可观察的变更。项目遵循 Keep a Changelog；0.x 仍允许明确记录的破坏性
调整。

## 0.9.2 - Unreleased

Breaking pre-GA：移除历史兼容层并收敛公开 API，升级步骤见
[0.9.2 迁移](docs/migration-0.9.2.md)。已发布的 v0.9.1 保持不变。

### Changed

- 将类型与实现移入真实领域包，新增 `markdown.engine`；根包不再公开声明或转导。
- 移除 `Markdown` 门面和 `AcceleratedMarkdownEngine` 包装器，统一 engine builder 与 scanner 配置。
- snapshot、lint 和 artifact 操作归所属领域类型；lint provider 与 dialect 解析配置分离。
- 仅维护 `api/public-api.txt` 当前声明快照，历史 API 通过对应 tag 查阅。
- 官方 STS 1.2.0 为唯一工具链，benchmark 仅保留 canonical 构建，release evidence 仅接受 schema 4。
- parser plan 更新为 7，旧解析缓存按身份检查失效。

### Evidence

<!-- release-evidence:start -->
当前数字只由 [`release-evidence.json`](release-evidence.json)提供：

- benchmark evidence status `current`；
- CommonMark `652/652`；
- GFM `671/671`；
- 测试 `1622/1622`，`0` skipped，`0` failed；
- public API snapshot `1679` declarations；
- canonical CommonMark ratio `2.467460x`；
- canonical GFM ratio `2.125837x`。

原始数据和受测 commit identity 见 `docs/reports/benchmark-raw.json`。
<!-- release-evidence:end -->

## 0.9.1 - 2026-10-21

Breaking pre-GA：本版本包含原计划 0.10 的模型调整，不承诺兼容 0.9.0。核心已通过 PR #12 合入；发布包使用官方 STS 1.2.0，发布状态以 GitHub Release 为准。

### Changed

- `Document.detach()` 使用独立 compact arena，保留绑定目标；未知 payload ownership 明确失败。
- Binary snapshot 拒绝未知 payload，typed 参数名称、类型和值纳入摘要，参数表防御性复制。

- 显式富内容准备：有界 MathML/token/PNG 校验、独立失败状态、Ready 缓存与 revision 绑定。
  同步/可恢复 HTML 共用产物；默认保留原文。
- 可选 Linux Node 适配器：固定 KaTeX/Shiki/Mermaid、显式离线准备与许可闭包、受控产物和
  有界进程监督；真实 Cangjie/Chrome 链路不依赖 mock。

- Code Groups 1.0：普通 fenced code、标题、行高亮、原始换行复制与可选的本地化 tabs。

- Math 2.0 typed payload：TeX、精确来源片段与 delimiter 分离，默认可读输出。

- 节点身份使用 lineage 与不回收编号，NodeRef 和 lint fix 绑定不可变 revision。
- 共享 lineage 的短片段按构造规模预留编号，避免过早耗尽身份空间；改善稀疏编号的哈希分布。
- ParseResult 只表示成功；tryParse 返回独立的成功/失败枚举。
- 移除纯兼容别名、内容哈希型 StableNodeId 和旧 schema reader 路径。
- Extension SPI 3、parser plan 6、artifact schema 3 与独立的 0.9.1 API snapshot。
- 整文处理分为绑定前 AST transform 和绑定后只读 analysis；共享实际 limits、预算和取消。
- 可恢复 HTML 遍历与部分 UTF-8 字节确认，移除预先渲染整份 HTML 的 buffered 输出实现。
- 实际分块解析的追加会话、带身份与版本的原子更新、参考消费端与最终后置引用绑定。
- 修正多行 setext 的 CRLF/container 来源映射、未闭合单 fence 的 EOF 范围和 Front Matter 起点。
- 定义列表 2.0 的完整分组、普通块正文、各输出和分块支持；修复容器 Markdown 续行归属。
- 智能标点 2.0 保护自动链接 URI、保留无变化节点身份，并累计扫描预算；补齐官方能力矩阵。
- 结构化脚注绑定、可达定义脚注区、独立引用锚点和完整回链。
- 标题显式 ID、自动 slug 和结构化 TOC，共用文档作用域及锚点冲突决策。
- 校验 Document 与 SourceBuffer 的来源归属；修正 GFM 表格转义后的来源映射和 Markdown
  行内语义保留。

### Evidence

历史测试、规范与性能证据保留在
[v0.9.1 的 release-evidence.json](https://github.com/lIlIIlIll/markdown/blob/v0.9.1/release-evidence.json)。

## 0.9.0 - 2026-08-30

这是 breaking pre-GA preview。当前离线 release evidence 状态为 evidence-ready，但托管
CI 验证和 GitHub Release 发布是独立状态；0.9 不构成 1.x ABI/行为冻结。

### Added

- arena-backed 完整 AST、`Document`/`NodeRef` typed views 和精确 SourceSpan。
- source-driven Event API，以及明确的 FullAst/PreferFused/RequireFused HTML 执行模式。
- `triggerBytes` 驱动的 parser SPI、版本化 DSL 和官方扩展集合。
- parse artifact schema 2、binary snapshot schema 2 和原始输入 identity 校验。
- buffered input/output 命名、可选 native scanner 和 native-on/off capability。
- `markdown.core`、`render`、`extensions`、`editor`、`artifact`、`document`、`testkit`
  公开子包。
- 完整开发者指南、分包 API reference 和离线文档一致性检查。

### Changed

- 0.8 object-tree AST 和 AST-walk event 表示不再作为 runtime compatibility adapter。
- SourceMap 在 renderer 写出内容时生成，不再通过输出字符串反向搜索。
- fingerprint 使用 canonical length-prefixed encoding。
- CST 使用共享 token arena；增量编辑明确为 block-local fast path。
- stream、chunk 和 async adapter 明确为 buffered 语义；source Event API 是独立执行模型。
- `newSession` 现在直接返回 `BufferedInputSession`；删除误导性的
  `ChunkedParseSession` 和 `AsyncHtmlRenderSession` 类型名。异步输出请使用
  `BufferedAsyncHtmlOutputSession`。
- `OperationBudget` 明确为单次操作拥有、不可并发共享的 mutable budget。

## 0.8.0 - 2026-08-25

首个完整 pre-GA preview，包含 CommonMark/GFM parser、不可变 AST、renderer、扩展 DSL、
诊断、资源限制、CST/editor、artifact、document services、CLI、TCK 和 benchmark 基础设施。
该版本的历史性能 blocker 不代表当前 0.9 状态。
