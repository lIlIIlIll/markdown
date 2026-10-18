# Changelog

本文件记录用户可观察的变更。项目遵循 Keep a Changelog；0.x 仍允许明确记录的破坏性
调整。

## 0.10.0 - Unreleased

开发中的 breaking pre-GA，完整 issue #10 验收与发布门禁尚未完成。

### Changed

- Code Groups 1.0：普通 fenced code、标题、行高亮、原始换行复制与可选的本地化 tabs。

- Math 2.0 typed payload：TeX、精确来源片段与 delimiter 分离，默认可读输出。

- 节点身份使用 lineage 与不回收编号，NodeRef 和 lint fix 绑定不可变 revision。
- 共享 lineage 的短片段按构造规模预留编号，避免过早耗尽身份空间；改善稀疏编号的哈希分布。
- ParseResult 只表示成功；tryParse 返回独立的成功/失败枚举。
- 移除纯兼容别名、内容哈希型 StableNodeId 和旧 schema reader 路径。
- Extension SPI 3、parser plan 5、artifact schema 3 与独立的 0.10 API snapshot。
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

<!-- release-evidence:start -->
当前数字只由 [`release-evidence.json`](release-evidence.json)提供：

- benchmark evidence status `stale`；
- CommonMark `652/652`；
- GFM `671/671`；
- 测试 `1600/1600`，`0` skipped，`0` failed；
- public API snapshot `1620` declarations；
- last complete CommonMark ratio `2.361586x`；
- last complete GFM ratio `1.788010x`。

原始数据和受测 commit identity 见 `docs/reports/benchmark-raw.json`。
<!-- release-evidence:end -->

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
