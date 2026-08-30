# Changelog

本文件记录用户可观察的变更。项目遵循 Keep a Changelog；0.x 仍允许明确记录的破坏性
调整。

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

### Evidence

<!-- release-evidence:start -->
当前数字只由 [`release-evidence.json`](release-evidence.json)提供：

- benchmark evidence status `current`；
- CommonMark `652/652`；
- GFM `671/671`；
- 测试 `1457/1457`，`0` skipped，`0` failed；
- public API snapshot `1323` declarations；
- canonical CommonMark ratio `2.368184x`；
- canonical GFM ratio `2.367749x`。

原始数据和受测 commit identity 见 `docs/reports/benchmark-raw.json`。
<!-- release-evidence:end -->

## 0.8.0 - 2026-08-25

首个完整 pre-GA preview，包含 CommonMark/GFM parser、不可变 AST、renderer、扩展 DSL、
诊断、资源限制、CST/editor、artifact、document services、CLI、TCK 和 benchmark 基础设施。
该版本的历史性能 blocker 不代表当前 0.9 状态。
