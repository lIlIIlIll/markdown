# 开发者 Cookbook

本页按常见任务给出代码。先完成[开始使用](getting-started.md)，或直接运行仓库中的
[`examples/cookbook`](../examples/cookbook/)；完整源码位于
[`examples/cookbook/src/main.cj`](../examples/cookbook/src/main.cj)。

[文档首页](README.md) · [开始使用](getting-started.md) · **Cookbook** · [API reference](api.md)

## 场景导航

| 目标 | 配方 |
| --- | --- |
| 渲染不信任输入 | [Markdown 转安全 HTML](#markdown-转安全-html) |
| 表格、任务列表、删除线 | [启用 GFM](#启用-gfm) |
| 获取标题、链接和 LSP 位置 | [读取标题、链接和位置](#读取标题链接和位置) |
| 限制资源或取消请求 | [限制资源并取消操作](#限制资源并取消操作) |
| 注册 `:::` 容器 | [自定义容器语法](#自定义容器语法) |
| 读取最终标题绑定并产生诊断 | [完整文档阶段](extensions.md#完整文档阶段) |
| lint 或格式化 | [Lint 和格式化](#lint-和格式化) |

```sh
cd examples/cookbook
cangjie_env
cjpm build
cjpm run --skip-build
```

## Markdown 转安全 HTML

适合评论、说明文字和其他不信任输入。raw HTML 会被转义，危险 URI 不会进入链接属性。

```cangjie
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let html = engine.renderHtml("# Hello\n\n<script>blocked</script>").html
println(html)
```

可信输入需要 CommonMark 规范输出时，在 unsafe context 中构造
`HtmlOptions.specCompatible()` 并传给 `engine.renderHtml(source, options: options)`。

> [!WARNING]
> `specCompatible()` 允许规范 raw HTML。处理用户输入时保留默认安全策略。

## 启用 GFM

表格、任务列表、删除线和 autolink 需要 GFM profile。

```cangjie
import markdown.core.{MarkdownProfile}
import markdown.engine.{MarkdownEngine}

let source = "- [x] shipped\n\n~~old~~"
let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfm029()).build()
println(engine.renderHtml(source).html)
```

`gfm029()` 固定 GFM 0.29 行为。`gfmModernV1()` 是仓库固定的 modern profile。不要只为
某个输入临时切换二者；先选择应用需要的兼容目标。

## 读取标题、链接和位置

`AstQuery` 返回 typed view。标题的通用节点字段位于 `heading.node`，因此源码范围是
`heading.node.span`，而不是直接从 typed view 读取。

```cangjie
import markdown.engine.MarkdownEngine
import markdown.core.AstQuery

let result = MarkdownEngine.builder().build().parse("# Install\n\nSee [API](api.md).")
for (heading in AstQuery.headings(result.document)) {
    let span = heading.node.span.getOrThrow()
    let lsp = result.source.utf16Position(span.startByte)
    println("${result.source.slice(span)} at ${lsp.line}:${lsp.character}")
}
for (link in AstQuery.links(result.document)) {
    println(link.destination)
}
```

`SourceSpan` 是半开 UTF-8 byte range。编辑器协议通常需要 UTF-16 位置，请使用
`utf16Position` 转换，不要把 byte offset 当作字符列。

## 限制资源并取消操作

默认 `ParseLimits.safe()` 已限制输入、行、AST 节点、literal、引用、URL、表格列和
输出。需要更严格限制时，复制 `ParseLimits` 的全部字段并只调整目标值。构造器参数和
默认值见[格式化指南](formatting.md)。

取消由调用方持有 `CancellationSource`：

```cangjie
import markdown.core.{CancellationSource, ParseOutcome}
import markdown.engine.{MarkdownEngine}

let source = CancellationSource()
source.cancel()
let engine = MarkdownEngine.builder().build()
let result = engine.tryParse("# cancelled", cancellation: source.token)
match (result) {
    case ParseOutcome.Success(_) => println("parsed")
    case ParseOutcome.Failure(error) => println(error.phase) // input
}
```

正常的 `parse` 在取消或超限时抛出 `MarkdownException`；`tryParse` 返回
`ParseOutcome.Failure(error)`，不会返回空文档或部分 AST。

## 自定义容器语法

下面定义 `:::note` 块，并将它安全地降低为 `<aside class="note">`。manifest、语法和
renderer 使用同一个 extension ID。

```cangjie
import markdown.engine.MarkdownEngine
import markdown.extensions.{BlockSyntax, ExtensionCapabilities, ExtensionManifest, MarkdownDialect, RendererRule}
import markdown.render.HtmlOptions

let manifest = ExtensionManifest(
    "docs", "1.0.0", "cookbook-1",
    capabilities: ExtensionCapabilities(safeHtml: true)
)
let dialect = MarkdownDialect
    .define("docs-v1", "1.0.0")
    .enable(manifest)
    .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
    .renderer(RendererRule("docs", "note", "aside", classToken: "note"))
    .build()
let engine = MarkdownEngine.builder().dialect(dialect).build()
let document = engine.parse(":::note\n**important**\n:::").document
println(engine.htmlRenderer(options: HtmlOptions.safe()).render(document))
```

生产扩展还应定义冲突策略、预算和 TCK。继续阅读[扩展开发](extensions.md)。

## Lint 和格式化

```cangjie
import markdown.engine.MarkdownEngine
import markdown.editor.{DocumentSnapshot, MarkdownLinter}
import markdown.render.CanonicalMarkdownRenderer

let engine = MarkdownEngine.builder().build()
let snapshot = DocumentSnapshot.parse(engine, "# Title\n\n### Skipped level")
for (diagnostic in MarkdownLinter(engine).lint(snapshot)) {
    println("${diagnostic.code}: ${diagnostic.message}")
}

let document = engine.parse("#  Title\n\n* item").document
println(CanonicalMarkdownRenderer().render(document))
```

`CanonicalMarkdownRenderer` 生成 canonical Markdown。需要尽量保留原始排版或只编辑范围时，使用
`DocumentSnapshot` 和 `PreservingFormatter`，见[格式化指南](formatting.md)。

## 输出到 sink 并关联源码

通过 engine 创建 renderer 可自动使用 dialect 的 manifest、renderer rules 和固定输出上限。
以下示例使用内建收集 sink，再取得 HTML 字节与节点、源码范围的映射：

```cangjie
import markdown.engine.MarkdownEngine
import markdown.render.{HtmlOptions, StringTextSink}

let engine = MarkdownEngine.builder().build()
let document = engine.parse("# source").document
let renderer = engine.htmlRenderer(options: HtmlOptions.safe())
let sink = StringTextSink()
renderer.renderTo(document, sink)
println(sink.content())

let output = renderer.renderWithSourceMap(document)
let sourceSpan = output.sourceSpanAt(5)
let nodeId = output.nodeIdAt(5)
println(output.content)
```

StringTextSink 收集完整输出。需要避免保留完整 String 时，由宿主实现写入实际目标的
`TextSink`；`write` 返回 Success 或 Failure，返回 Failure 时转换为 SinkFailureException。
sink 直接抛出的异常原样传播。
固定 `maximumOutputBytes` 与操作预算在每次写入前执行。Source map 由写出路径同步记录，
按 output byte range 查询，不从 HTML 中反向搜索原文。需背压时使用
[可恢复输出会话](html-output.md)。

## 从 AST 生成纯文本

纯文本和 canonical Markdown 共用同一个完整 AST。下面保留链接显示文本，使用换行表示
soft break：

```cangjie
import markdown.engine.MarkdownEngine
import markdown.render.{PlainTextOptions, PlainTextRenderer}

let document = MarkdownEngine.builder().build().parse("[API](api.md)\ntext").document
let text = PlainTextRenderer(
    options: PlainTextOptions(includeLinkDestinations: false, softBreak: "\n")
).render(document)
println(text)
```

需要保留链接 destination 时修改 `includeLinkDestinations`；生成 Markdown 的选项见
[格式化指南](formatting.md)。

## 下一步

- 查签名和默认值：[API reference](api.md)
- 排查常见错误：[故障排查](troubleshooting.md)
- 选择输入形式和预算：[输入、限制和取消](input-and-resources.md)
- 编写、测试扩展：[扩展开发](extensions.md)

---

[← 开始使用](getting-started.md) · [文档首页](README.md) · [API reference →](api.md)

## 公式来源与代码组

可运行 cookbook 的 `math-source` 段展示 MathPayload 的语义与来源片段；`code-groups`
段生成包含中文标题、BOM、CRLF、多语言和空代码的真实 HTML。规则分别见
[公式模型](math.md)和[代码组](code-groups.md)。代码组控件需要宿主显式加载静态资产；
cookbook 不执行代码或启动第三方排版后端。
