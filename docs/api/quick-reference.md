# API 速查

本页只列常用公开入口。签名对应 `0.9.0`；完整声明以
[`api/public-api-v0.9.txt`](../../api/public-api-v0.9.txt) 为准。

## Facade

导入：`import markdown.core.{Markdown, MarkdownProfile}`

| 入口 | 返回值 | 用途 |
| --- | --- | --- |
| `Markdown.parse(source, profile: commonMark0312())` | `ParseResult` | 构造完整 AST、源码映射和诊断 |
| `Markdown.toSafeHtml(source, profile: commonMark0312())` | `String` | 不信任输入转安全 HTML |
| `Markdown.toSpecHtml(source, profile: commonMark0312())` | `String` | 可信输入的规范兼容 HTML |
| `Markdown.toText(source, profile: commonMark0312())` | `String` | 提取纯文本 |
| `Markdown.format(source, profile: commonMark0312())` | `String` | 输出 canonical Markdown |

## Profile

| 入口 | 兼容目标 |
| --- | --- |
| `MarkdownProfile.commonMark0312()` | CommonMark 0.31.2，默认 |
| `MarkdownProfile.gfm029()` | GFM 0.29 |
| `MarkdownProfile.gfmModernV1()` | 仓库版本化 modern GFM |
| `MarkdownProfile.gfm()` | `gfmModernV1()` 的稳定便捷入口 |
| `MarkdownProfile.custom(id, version)` | 自定义 profile identity |

## Engine

导入：`import markdown.core.*`

```cangjie
let engine = MarkdownEngine.builder()
    .profile(MarkdownProfile.gfm029())
    .limits(ParseLimits.safe())
    .build()
```

| 入口 | 默认值与结果 |
| --- | --- |
| `engine.parse(value, cancellation:, budget:)` | `CancellationToken.none()`、`OperationBudget.safe()`；失败时抛异常 |
| `engine.parse(bytes, utf8Policy:, cancellation:, budget:)` | `Utf8Policy.Strict`；保留原始 byte offset 语义 |
| `engine.parse(inputStream, utf8Policy:, ...)` | 全量缓冲后解析，不降低峰值内存 |
| `engine.tryParse(value, ...)` | 失败时返回不完整结果、空文档和 `errors` |
| `engine.newBufferedInputSession(...)` | `finish()` 时解析，不提前产出 AST |
| `engine.parseEvents(source, mode:, ...)` | 返回不持有 AST 的 source events |
| `engine.renderHtml(source, mode:, options:, ...)` | 默认 `FullAst` + `HtmlOptions.safe()` |

`MarkdownEngineBuilder.dialect(dialect)` 会采用 dialect 的 base profile 和 limits。

## ParseResult 和 AST

| 成员 | 类型 | 含义 |
| --- | --- | --- |
| `result.document` | `Document` | 不可变完整 AST |
| `result.source` | `SourceBuffer` | 原始文本、slice 和位置转换 |
| `result.diagnostics` | `ImmutableArray<Diagnostic>` | 可恢复诊断 |
| `result.isComplete` | `Bool` | 是否完成 |
| `result.errors` | `ImmutableArray<MarkdownException>` | `tryParse` 捕获的错误 |
| `node.id` | `NodeId` | 当前文档内稳定 identity |
| `node.kind` | `NodeKind` | 节点类型 |
| `node.span` | `?SourceSpan` | 半开 UTF-8 byte range |
| `node.children` | `ImmutableArray<NodeRef>` | 子节点 |

## 查询和位置

导入：`import markdown.editor.AstQuery`

| 入口 | 返回值 |
| --- | --- |
| `AstQuery.headings(document)` | `Array<HeadingNodeView>` |
| `AstQuery.links(document)` | `Array<LinkNodeView>` |
| `AstQuery.images(document)` | `Array<ImageNodeView>` |
| `AstQuery.codeBlocks(document)` | `Array<CodeBlockNodeView>` |
| `AstQuery.descendants(document)` | `Array<NodeRef>` |
| `AstQuery.byNodeId(document, id)` | `?NodeRef` |
| `source.slice(span)` | 源文本 slice |
| `source.utf16Position(byteOffset)` | LSP 风格 UTF-16 位置 |

Typed view 的通用字段从 `.node` 读取，例如 `heading.node.span`。

## Renderer

导入：`import markdown.render.*`

```cangjie
let renderer = HtmlRenderer(options: HtmlOptions.safe())
let html = renderer.render(result.document)
```

| 入口 | 用途 |
| --- | --- |
| `HtmlOptions.safe()` | 默认安全策略；转义 raw HTML，限制 URI |
| `HtmlOptions.specCompatible()` | CommonMark 规范兼容输出 |
| `HtmlOptions.gfmCompatible()` | GFM 规范兼容输出 |
| `renderer.render(document, cancellation:, budget:)` | 返回 `String` |
| `renderer.renderTo(document, sink, cancellation:, budget:)` | 写入有界 sink |
| `engine.htmlRenderer(options:, sanitizer:, fallbacks:)` | 使用 dialect renderer rules |

## Editor

| 入口 | 用途 |
| --- | --- |
| `engine.parseSnapshot(source)` | 生成语义 AST、CST 和映射 snapshot |
| `engine.lint(snapshot)` | 返回结构、安全和样式诊断 |
| `snapshot.applyEdits(edits)` | 应用 byte-range 编辑并返回 reparse 结果 |
| `snapshot.applyUtf16Edit(start, end, replacement)` | 应用编辑器 UTF-16 range |
| `PreservingFormatter.formatRange(...)` | 尽量保留未修改源码布局 |

## Extension

| 入口 | 用途 |
| --- | --- |
| `MarkdownDialect.define(id, version)` | 创建版本化 dialect builder |
| `builder.enable(manifest)` | 注册 extension manifest |
| `builder.block(BlockSyntax.define(...))` | 注册块语法 |
| `builder.inline(InlineSyntax.define(...))` | 注册行内语法 |
| `builder.renderer(RendererRule(...))` | 注册安全 lowering rule |
| `DialectCompiler.compile(dialect)` | 验证并编译 dialect |
| `MarkdownExtensionTestKit.verify(engine, sample)` | 运行公开扩展契约测试 |

完整例子见[开发者 Cookbook](../cookbook.md#自定义容器语法)。

## 错误默认值

- 异常基类：`MarkdownException`
- 程序分支字段：`code`、`phase`、可选 `span`
- Parser limits：`ParseLimits.safe()`
- Operation budget：`OperationBudget.safe()`
- Cancellation：`CancellationToken.none()`
- UTF-8 bytes：`Utf8Policy.Strict`
- HTML：`HtmlOptions.safe()`

不要解析英文错误消息。错误类别和恢复语义见[错误与能力](../errors-and-capabilities.md)。
