# 开发者 Cookbook

本页按常见任务给出代码。先完成[开始使用](getting-started.md)，或直接运行仓库中的
[`examples/cookbook`](../examples/cookbook/)；完整源码位于
[`examples/cookbook/src/main.cj`](../examples/cookbook/src/main.cj)。

```sh
cd examples/cookbook
cangjie_env
cjpm build
cjpm run --skip-build
```

## Markdown 转安全 HTML

适合评论、说明文字和其他不信任输入。raw HTML 会被转义，危险 URI 不会进入链接属性。

```cangjie
import markdown.core.Markdown

let html = Markdown.toSafeHtml("# Hello\n\n<script>blocked</script>")
println(html)
```

需要 CommonMark 规范兼容输出，而不是面向不信任输入的默认策略时，显式调用
`Markdown.toSpecHtml`。不要对用户输入使用该入口。

## 启用 GFM

表格、任务列表、删除线和 autolink 需要 GFM profile。

```cangjie
import markdown.core.{Markdown, MarkdownProfile}

let source = "- [x] shipped\n\n~~old~~"
println(Markdown.toSafeHtml(source, profile: MarkdownProfile.gfm029()))
```

`gfm029()` 固定 GFM 0.29 行为。`gfm()` 是仓库固定的 modern profile。不要只为
某个输入临时切换二者；先选择应用需要的兼容目标。

## 读取标题、链接和位置

`AstQuery` 返回 typed view。标题的通用节点字段位于 `heading.node`，因此源码范围是
`heading.node.span`，而不是直接从 typed view 读取。

```cangjie
import markdown.core.Markdown
import markdown.editor.AstQuery

let result = Markdown.parse("# Install\n\nSee [API](api).")
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
默认值见 [Core API](api/core.md#资源限制)。

取消由调用方持有 `CancellationSource`：

```cangjie
import markdown.core.{CancellationSource, MarkdownEngine}

let source = CancellationSource()
source.cancel()
let engine = MarkdownEngine.builder().build()
let result = engine.tryParse("# cancelled", cancellation: source.token)
println(result.isComplete) // false
```

正常的 `parse` 在取消或超限时抛出 `MarkdownException`；`tryParse` 返回
`isComplete == false`、空文档和结构化 `errors`，不会返回部分 AST。

## 自定义容器语法

下面定义 `:::note` 块，并将它安全地降低为 `<aside class="note">`。manifest、语法和
renderer 使用同一个 extension ID。

```cangjie
import markdown.core.MarkdownEngine
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
import markdown.core.{Markdown, MarkdownEngine}

let engine = MarkdownEngine.builder().build()
let snapshot = engine.parseSnapshot("# Title\n\n### Skipped level")
for (diagnostic in engine.lint(snapshot)) {
    println("${diagnostic.code}: ${diagnostic.message}")
}

println(Markdown.format("#  Title\n\n* item"))
```

`Markdown.format` 生成 canonical Markdown。需要尽量保留原始排版或只编辑范围时，使用
`DocumentSnapshot` 和 `PreservingFormatter`，见 [Editor API](api/editor.md)。

## 下一步

- 查签名和默认值：[API 速查](api/quick-reference.md)
- 排查常见错误：[故障排查](troubleshooting.md)
- 选择输入形式和预算：[输入、限制和取消](input-and-resources.md)
- 编写、测试扩展：[扩展开发](extensions.md)
