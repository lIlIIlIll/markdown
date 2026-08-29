# 开始使用 markdown

本教程从空工程得到第一个安全 HTML 输出。基础包使用纯仓颉实现，不需要 C 编译器或
原生链接参数。

[文档首页](README.md) · **开始使用** · [Cookbook](cookbook.md) · [API 速查](api/quick-reference.md)

**完成时间：约 5 分钟**

`准备环境` → `创建工程` → `构建运行` → `验证输出`

## 前置条件

- Cangjie SDK `1.1.0`
- `cjpm`
- 当前仓库的绝对路径

## 创建消费工程

```sh
mkdir -p markdown_demo/src
cd markdown_demo
```

创建 `markdown_demo/cjpm.toml`，并替换依赖路径。manifest 不展开 shell 环境变量或 `~`。

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

创建 `markdown_demo/src/main.cj`：

```cangjie
package markdown_demo

import markdown.core.Markdown

main(): Int64 {
    let source = "# Hello\n\n<script>blocked</script>"
    println(Markdown.toSafeHtml(source))
    0
}
```

## 构建并运行

```sh
cangjie_env
cjpm build
cjpm run --skip-build
```

预期输出：

```html
<h1>Hello</h1>
&lt;script&gt;blocked&lt;/script&gt;
```

`Markdown.toSafeHtml` 默认转义 raw HTML，并拒绝危险 URI。现在你已经完成最小集成。

### 成功检查

- [ ] `cjpm build` 以 exit code `0` 结束。
- [ ] 输出包含 `<h1>Hello</h1>`。
- [ ] `<script>` 被输出为 `&lt;script&gt;`，没有作为 HTML 执行。

如果依赖或运行失败，查看[安装与运行问题](troubleshooting.md#安装与运行)。

## 运行仓库示例

仓库提供两个已经纳入文档门禁的消费工程：

```sh
cd /absolute/path/to/markdown/examples/quickstart
cangjie_env
cjpm build
cjpm run --skip-build
```

- `examples/quickstart`：最小入口、AST、扩展和取消。
- `examples/cookbook`：GFM、位置、lint、format 和自定义容器。

## 下一步

| 下一项任务 | 前往 |
| --- | --- |
| 复制 GFM、AST、lint 或扩展示例 | [开发者 Cookbook](cookbook.md) |
| 查常用签名、默认值和失败语义 | [API 速查](api/quick-reference.md) |
| 选择 CommonMark 或 GFM | [Profile 指南](profiles.md) |
| 遍历 AST 和转换源码位置 | [AST 与 Source API](api/ast-and-source.md) |

---

[← 文档首页](README.md) · [下一篇：开发者 Cookbook →](cookbook.md)
