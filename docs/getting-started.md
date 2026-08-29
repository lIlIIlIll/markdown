# 开始使用 markdown

本教程创建一个仓颉可执行工程，解析 Markdown，并输出默认安全 HTML。完成后，你将有一个
可运行的最小集成工程。

## 前置条件

- Cangjie SDK `1.1.0`
- `cjpm`
- 当前仓库的本地路径

基础包使用纯仓颉实现。完成本教程不需要 C 编译器或原生链接参数。

## 1. 创建工程

创建消费工程和源码目录：

```sh
mkdir -p markdown_demo/src
cd markdown_demo
```

## 2. 添加依赖

创建 `cjpm.toml`。将 `/absolute/path/to/markdown` 替换为当前仓库的绝对路径。
`cjpm.toml` 不会展开 shell 环境变量。

```toml
[package]
  cjc-version = "1.1.0"
  name = "markdown_demo"
  version = "0.1.0"
  output-type = "executable"
  compile-option = "-O2"
  link-option = ""

[dependencies]
  "markdown" = { path = "/absolute/path/to/markdown", output-type = "static" }
```

运行依赖检查：

```sh
cangjie_env
cjpm check
```

命令成功时退出码为 `0`。

如果 `cjpm` 报告找不到依赖，请确认依赖路径直接包含 `markdown` 的
`cjpm.toml`，而不是它的父目录。

## 3. 解析并渲染

创建 `src/main.cj`：

```cangjie
package markdown_demo

import markdown.core.Markdown

main(): Int64 {
    let source = "# Hello\n\n<script>blocked</script>"
    println(Markdown.toSafeHtml(source))
    0
}
```

构建并运行工程：

```sh
cjpm run
```

首次执行只完成构建但没有启动程序时，再运行：

```sh
cjpm run --skip-build
```

输出为：

```html
<h1>Hello</h1>
&lt;script&gt;blocked&lt;/script&gt;
```

`Markdown.toSafeHtml` 使用 `HtmlOptions.safe()`。它不会执行 raw HTML，也不会
允许 `javascript:` 链接。

## 4. 使用完整 parser 结果

将 `src/main.cj` 改为：

```cangjie
package markdown_demo

import markdown.core.{MarkdownEngine, MarkdownProfile}
import markdown.editor.AstQuery
import markdown.render.{HtmlOptions, HtmlRenderer}

main(): Int64 {
    let engine = MarkdownEngine.builder()
        .profile(MarkdownProfile.gfm029())
        .build()
    let result = engine.parse("# One\n\n- [x] done")

    for (heading in AstQuery.headings(result.document)) {
        let span = heading.span.getOrThrow()
        println("heading=${result.source.slice(span)}")
    }

    let html = HtmlRenderer(options: HtmlOptions.safe()).render(result.document)
    println(html)
    0
}
```

这条路径公开完整的 `ParseResult`：

- `document`：不可变 arena AST
- `source`：原始文本和位置转换
- `diagnostics`：可恢复问题
- `isComplete`：解析是否完整
- `errors`：`tryParse` 捕获的结构化错误

## 5. 运行仓库示例

仓库的 `examples/quickstart` 覆盖安全 HTML、AST 查询、扩展和取消。

```sh
cd /absolute/path/to/markdown/examples/quickstart
cangjie_env
cjpm build
cjpm run --skip-build
```

输出包括：

```text
<h1>Hello</h1>
&lt;script&gt;blocked&lt;/script&gt;

heading level=1
heading level=2
<aside class="note"><p><strong>important</strong></p>
</aside>
cancelled=input
```

## 下一步

- 查找 parser、限制和 Event API：[Core API](api/core.md)
- 遍历节点和处理源码范围：[AST 与 Source API](api/ast-and-source.md)
- 配置 HTML 安全策略：[Rendering API](api/rendering.md)
- 注册自定义语法：[Extensions API](api/extensions.md)

