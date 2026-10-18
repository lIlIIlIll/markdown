# 0.10 模型迁移（开发中）

本版本允许破坏性修改，不提供旧 API facade、旧缓存 reader 或自动迁移。
以下只列已经实施的修改；issue #10 的扩展、追加式 session、富内容后端及编辑/缓存
实测仍在推进，不能从版本号推断它们已完成或通过发布门禁。

- 使用 `result.document`；移除 `ParseResult.ast` 和 `parsePartial`。
- 移除 `MarkdownProfile.commonMark()` / `gfm()` 别名，显式选择
  `commonMark0312()` / `gfmModernV1()`。
- LineScannerAccelerator 只接受 packed record v4，以 `scanLineRecords` 返回有效前缀；
  移除旧 `scanLines` 数组接口和 v1–v3 解码。`None` 仍表示当前输入使用纯仓颉扫描。
- 移除旧 buffered 语义的 `newSession` 别名。仍需一次性缓冲时使用
  `newBufferedInputSession`；实际分块 AST 使用 `newAppendSession`。
- `parse` 成功返回 `ParseResult`，致命失败抛出异常。`tryParse` 返回
  `ParseOutcome.Success(result)` 或 `Failure(error)`，失败不携带 Document。
- `NodeId` 包含 lineage 与不回收的局部编号；不再由 arena 下标或文本内容推断身份。
  NodeRef 绑定 Document revision，持久化共享节点也必须重新查询当前视图的 NodeRef。
- 移除 `StableNodeId` 和 `stableNodeId`。使用当前 Document 的
  `AstQuery.byNodeId(document, id)` 查询实际保留的节点。
- lint `Fix` 绑定 `documentRevision` 和 source digest；不能跨独立 snapshot 或回退版本使用。
- 脚注和标题 ID 升为 2.0 语义，使用 typed payload 和 `Document.bindings`；删除旧 sup/aside
  及独立 heading span 的标签映射。HTML、Text、Markdown、查询与目录共享绑定结果。
- 标题 ID 位于 `hN`，显式 ID 先预留，标题与脚注共用冲突分配。拼装片段使用
  `BindingOptions(idScope: ...)`；具体规则见[文档绑定](semantic-binding.md)。
- `SourceBuffer.text(node/document)` 和 `ParseResult` 校验实际来源归属。
- 智能标点升为 2.0；保护自动链接的显示 URI，无内容变化时保留节点身份，并累计文本扫描预算。
- `InlineSyntaxMatch` 增加 `rawLiteral` 和 `literalSpan`，分别提供原始捕获文本与精确范围；
  `literal` 仍是容器规范化后的匹配内容。
- Extension SPI 为 `3`，parser plan 为 `6`，parse artifact 与 binary snapshot schema 为 `3`。
  旧缓存返回 CacheMiss；显式 `BinaryArtifactCodec.read` 遇到旧持久化版本报
  `MarkdownErrorCode.UnsupportedVersion`，不尝试旧格式解码。
- 移除 ExtensionDocumentProcessor、ExtensionProcessingPhase 和 documentProcessor 注册。
  改用绑定前的 ExtensionAstTransform 或绑定后的只读 ExtensionDocumentAnalysis；
  callback 接收实际 source/limits/budget/cancellation。见[扩展阶段](api/extensions.md#完整文档阶段)。
- executionModels 的失败模型字段为 parseOutcome；移除旧 partialParse 名称。
  CLI dialect validate 默认读取引擎当前 SPI；旧 SPI 1/2 明确拒绝。

公开声明见[0.10 API snapshot](../api/public-api-v0.10.txt)。开发期间的完整验证进度见
[issue #10 实施记录](../.agent/issue-10-status.md)。

## 追加输入

需要实际分块 AST 的消费者改用 `newAppendSession()` 和 `AppendReplica`。feed 返回
带会话/版本/目标身份的更新，finish 统一绑定；不要把临时块当作 ParseResult。
`newBufferedInputSession()` 仍用于只累计输入的场景。具体调用和终态处理见
[追加输入与更新消费](append-input.md)。

## 可恢复输出

移除 BufferedAsyncHtmlOutputSession。改用 `renderer.newOutputSession(document)`，构造
时不再渲染。AsyncSinkWriteResult 的 Pause 改为 `Pause(acceptedBytes)`；0 表示未接收，
前缀必须位于 UTF-8 边界。AsyncRenderState.Failed 现在携带 MarkdownException，包含
sink、取消、预算和 renderer 错误。Complete/Failed 后不允许 resume。详见
[暂停与恢复 HTML 输出](html-output.md)。

## 定义列表 2.0

移除旧的单行 definition → dd 映射。新 AST 使用 DefinitionListPayload 的
List/Entry/Term/Definition roles，定义正文包含普通块。格式化可以规范化缩进和文本转义；
原始拼写使用 SourceBuffer、lossless CST 或 preserving formatter。现有 consumer 应按
角色和 children 读取归属，不按旧 dd 节点猜测 term。见[定义列表](definition-lists.md)。

## Math 2.0

Math 不再返回通用 `SyntaxPayload`。使用 `MathPayload.expression` 读取不执行的 TeX，
`display` 区分行内与块，`expressionSource` 保存表达式的精确来源片段，
`openerSpan` / `closerSpan` 保存 delimiter。容器中的表达式可以有多个不连续来源片段。
默认输出继续显示转义后的 TeX；可选后端结果不写入 AST。语法见[公式模型](math.md)。

## Code Groups 1.0

使用 `OfficialExtensions.codeGroups(builder)` 显式注册；不改变默认标准 profile 或
p1Dialect 组合。代码组有 Group/Item payload 和普通 CodeBlock children，HTML 默认保持
完整静态可读。开启 `CodeGroupHtmlOptions(interactive: true)` 后仍需宿主显式加载静态
资产；见[代码组](code-groups.md)。结构化 literal 容器的引用收集复用实际 block 边界，
不会让公式或代码正文中的伪定义成为外部链接目标。parser plan 6 的 descriptor、engine
fingerprint 与 parse artifact 使用同一版本常量，旧配置缓存失效；binary layout 保持 3。

## 富内容准备

在完整 ParseResult 上显式调用 `RichContentPreparer.prepare`，再通过 renderer 的
`prepared` 参数提供注解。默认关闭；缺后端或准备失败时仍输出完整原文语义。注解绑定
不可变 revision，不能跨 snapshot 使用。派生 MathML/PNG 的 source map 使用
`generated: true` 并保留粗粒度来源；不能再用 generated 判断 sourceSpan 必为 None。
renderer fingerprint 升为 5，派生数据不进入 parse artifact。见[富内容准备](rich-content.md)。
