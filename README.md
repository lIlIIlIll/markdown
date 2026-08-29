# markdown

`markdown` 是面向仓颉的 Markdown 解析、渲染和文档处理库。它提供完整
AST、UTF-8 源码范围、安全 HTML、CommonMark/GFM profile、扩展 DSL、
诊断、格式化和编辑器接口。

[![Cangjie 1.1.0](https://img.shields.io/badge/Cangjie-1.1.0-7B61FF?style=flat)](cjpm.toml)
[![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark-0.31.2-2F6F9F?style=flat)](docs/profiles.md)
[![GFM 0.29](https://img.shields.io/badge/GFM-0.29-24292F?style=flat)](docs/profiles.md)
[![License MIT](https://img.shields.io/badge/License-MIT-green?style=flat)](LICENSE)
[![Status pre-GA](https://img.shields.io/badge/Status-0.9_preview-orange?style=flat)](docs/versioning-and-compatibility.md)

当前版本是 `0.9.0` breaking pre-GA preview。发布验证、CommonMark/GFM
规范语料和性能门槛已经通过。0.9 仍允许破坏性 API 调整；升级前请阅读
[迁移指南](docs/migration.md)。

## 快速开始

在消费工程的 `cjpm.toml` 中添加源码依赖：

```toml
[dependencies]
  "markdown" = { path = "/absolute/path/to/markdown", output-type = "static" }
```

解析 Markdown 并生成默认安全 HTML：

```cangjie
package markdown_demo

import markdown.core.Markdown

main(): Int64 {
    println(Markdown.toSafeHtml("# Hello\n\n<script>blocked</script>"))
    0
}
```

输出：

```html
<h1>Hello</h1>
&lt;script&gt;blocked&lt;/script&gt;
```

完整的工程创建步骤、命令和故障排查见
[开始使用 markdown](docs/getting-started.md)。仓库中的
[quickstart](examples/quickstart) 只使用公开 API，并由发布门禁编译和运行。

## 选择入口

新代码应从用途明确的子包导入 API。根包 `markdown.*` 只作为兼容门面。

| 子包 | 用途 |
| --- | --- |
| `markdown.core` | parser、profile、完整 AST、SourceSpan、诊断、限制和 Event API |
| `markdown.render` | HTML、纯文本、Markdown renderer、sink、source map 和安全策略 |
| `markdown.extensions` | 方言、Syntax DSL、renderer DSL、manifest 和 SPI |
| `markdown.editor` | CST、查询、rewrite、lint、snapshot、range edit 和 preserving formatter |
| `markdown.artifact` | parse artifact 和 binary snapshot |
| `markdown.document` | document graph、snapshot 和跨文档引用 |
| `markdown.testkit` | 第三方扩展 TCK |
| `markdown.native` | 可选原生 line scanner；基础包不依赖原生链接 |

从 [API reference](docs/api.md) 查找类型、方法、默认值和错误语义。

## 常用任务

### 选择 CommonMark 或 GFM

```cangjie
import markdown.core.{MarkdownEngine, MarkdownProfile}

let commonMark = MarkdownEngine.builder()
    .profile(MarkdownProfile.commonMark0312())
    .build()

let gfm = MarkdownEngine.builder()
    .profile(MarkdownProfile.gfm029())
    .build()
```

profile ID、固定规范版本和便利方法的区别见
[Profile reference](docs/profiles.md)。

### 读取 AST 和源码范围

```cangjie
import markdown.core.Markdown
import markdown.editor.AstQuery

let result = Markdown.parse("# One\n\n## Two")
for (heading in AstQuery.headings(result.document)) {
    let span = heading.span.getOrThrow()
    println("level=${heading.level}, source=${result.source.slice(span)}")
}
```

`SourceSpan` 使用半开 UTF-8 byte range。LSP 客户端可通过
`SourcePositionMap` 转换 UTF-16 位置。详见
[AST 与 Source API](docs/api/ast-and-source.md)。

### 配置安全 HTML

```cangjie
import markdown.core.Markdown
import markdown.render.{HtmlOptions, HtmlRenderer}

let document = Markdown.parse("<script>x</script> [x](javascript:alert(1))").document
let html = HtmlRenderer(options: HtmlOptions.safe()).render(document)
```

`HtmlOptions.safe()` 会转义 raw HTML，并对链接和图片分别执行 URI policy。
规范兼容输出需要显式使用 `specCompatible()` 或 `gfmCompatible()`。
详见 [Rendering API](docs/api/rendering.md) 和
[安全指南](docs/security.md)。

### 限制资源并取消解析

```cangjie
import markdown.core.{CancellationSource, MarkdownEngine, OperationBudget, ParseLimits}

let engine = MarkdownEngine.builder()
    .limits(ParseLimits.safe())
    .build()
let cancellation = CancellationSource()

let result = engine.parse(
    "text",
    cancellation: cancellation.token,
    budget: OperationBudget.safe()
)
```

输入大小、行长、节点数、literal、URL、表格列数和扩展捕获均有独立上限。
详见 [输入、限制和取消](docs/input-and-resources.md)。

### 定义扩展

```cangjie
import markdown.core.MarkdownEngine
import markdown.extensions.{
    BlockSyntax,
    ExtensionCapabilities,
    ExtensionManifest,
    MarkdownDialect,
    RendererRule
}

let manifest = ExtensionManifest(
    "docs",
    "1.0.0",
    "example-1",
    capabilities: ExtensionCapabilities(safeHtml: true)
)
let dialect = MarkdownDialect
    .define("docs-v1", "1.0.0")
    .enable(manifest)
    .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
    .renderer(RendererRule("docs", "note", "aside", classToken: "note"))
    .build()
let engine = MarkdownEngine.builder().dialect(dialect).build()
```

编译器会验证依赖、冲突、优先级、资源边界和 renderer coverage。完整接口见
[Extensions API](docs/api/extensions.md)。

## 执行模型

默认 `parse` 构造完整不可变 AST。不同入口不会静默关闭 `NodeId`、
`SourceSpan`、`NodeOrigin` 或资源限制。

- `parse(String)`、`parse(Array<Byte>)`、`parse(InputStream)` 返回完整 AST。
- `BufferedInputSession` 和兼容类型 `ChunkedParseSession` 在 `finish()` 时解析。
- `parseEvents` 和 `emitEvents` 直接产生不持有 AST 的 source events。
- `RawBlockEventSession` 可在输入结束前发出已闭合的非最终 block events。
- `BufferedAsyncHtmlOutputSession` 先生成完整 HTML，再按 sink backpressure 分块发送。

各入口的复制、缓冲和语义保证见
[输入、限制和取消](docs/input-and-resources.md)。

## 文档

从 [开发者文档首页](docs/README.md) 开始。

| 目标 | 文档 |
| --- | --- |
| 完成第一个可运行工程 | [Getting started](docs/getting-started.md) |
| 查找公开类型和方法 | [API reference](docs/api.md) |
| 遍历 AST 和转换位置 | [AST 与 Source API](docs/api/ast-and-source.md) |
| 生成 HTML、文本或 Markdown | [Rendering API](docs/api/rendering.md) |
| 编写方言和扩展 | [Extensions API](docs/api/extensions.md) |
| 接入编辑器、lint 和 rewrite | [Editor API](docs/api/editor.md) |
| 使用 artifact、snapshot 和 document graph | [Artifact 与 Document API](docs/api/artifacts-and-services.md) |
| 使用 CLI | [CLI reference](docs/cli.md) |
| 了解安全默认值 | [Security](docs/security.md) |
| 查看性能方法和证据 | [Performance](docs/performance.md) |

## 验证状态

`release-evidence.json` 是 README、benchmark report 和验收记录的统一事实源。

<!-- release-evidence:start -->
| Release evidence | Value |
| --- | --- |
| Version / status | `0.9.0` / `ready` |
| Source commit | `856a6c7164fe97450b5ab7ff34926445b48dcc35` |
| CommonMark / cmark | `2.38x` / limit `2.5x` |
| GFM HTML / cmark-gfm | `2.45x` / limit `2.5x` |
| Benchmark identity | `current`; commit `856a6c7164fe97450b5ab7ff34926445b48dcc35`; SDK `1.1.0-alpha.20260803040049` |

The table is generated from [`release-evidence.json`](release-evidence.json).
The benchmark and source identities are commit-bound and the evidence tree is clean. The preview release evidence is ready and every mandatory gate passes.
<!-- release-evidence:end -->

当前证据包括：

- CommonMark `652/652`
- GFM `671/671`
- 全量测试 `1455/1455`
- 公开 API snapshot `1311` declarations
- fixed-host CommonMark `2.38x`、GFM `2.45x`，门槛均为 `2.5x`

详细方法、语料身份和 raw 数据见 [性能说明](docs/performance.md)。

## 开发与贡献

使用仓库要求的 Cangjie SDK 环境：

```sh
cangjie_env
cjpm check
cjpm test --no-color --no-progress
```

完整发布验证由 `scripts/release_gate.sh` 编排。文档和公开 API 必须与当前源码、
`api/public-api-v0.9.txt` 和 `release-evidence.json` 保持一致。

安全问题请通过
[GitHub Private Vulnerability Reporting](https://github.com/lIlIIlIll/markdown/security/advisories/new)
提交。不要在公开 issue 中披露未修复漏洞。

## License

[MIT](LICENSE)
