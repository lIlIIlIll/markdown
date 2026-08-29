# markdown

仓颉 Markdown 解析、渲染和文档处理库。默认输出安全 HTML，也提供完整 AST、精确源码
位置、CommonMark/GFM、扩展 DSL、格式化和编辑器接口。

[![Cangjie 1.1.0](https://img.shields.io/badge/Cangjie-1.1.0-7B61FF?style=flat)](cjpm.toml)
[![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark-0.31.2-2F6F9F?style=flat)](docs/profiles.md)
[![GFM 0.29](https://img.shields.io/badge/GFM-0.29-24292F?style=flat)](docs/profiles.md)
[![Status pre-GA](https://img.shields.io/badge/Status-0.9_preview-orange?style=flat)](docs/versioning-and-compatibility.md)
[![Developed with Codex](https://img.shields.io/badge/Developed_with-Codex-111111?style=flat&logo=openai&logoColor=white)](https://openai.com/codex/)
[![License MIT](https://img.shields.io/badge/License-MIT-green?style=flat)](LICENSE)

当前版本是 `0.9.0` breaking pre-GA preview。规范语料、全量测试和性能发布门槛已经
通过。0.9 仍允许在 GA 前调整公开 API。

## 两分钟运行

你需要 Cangjie SDK 1.1 和当前仓库的本地路径。基础包不要求 C 编译器。

在消费工程的 `cjpm.toml` 中添加依赖：

```toml
[dependencies]
  "markdown" = { path = "/absolute/path/to/markdown", output-type = "static" }
```

将下面的代码保存为 `src/main.cj`：

```cangjie
package markdown_demo

import markdown.core.Markdown

main(): Int64 {
    println(Markdown.toSafeHtml("# Hello\n\n<script>blocked</script>"))
    0
}
```

构建并运行：

```sh
cangjie_env
cjpm build
cjpm run --skip-build
```

你会看到：

```html
<h1>Hello</h1>
&lt;script&gt;blocked&lt;/script&gt;
```

如果依赖路径或运行命令失败，查看[安装与运行问题](docs/troubleshooting.md#安装与运行)。

## 按任务选择 API

| 你要做什么 | 从这里开始 |
| --- | --- |
| Markdown 转安全 HTML | `Markdown.toSafeHtml(source)` |
| 启用 GFM 表格、任务列表和删除线 | `MarkdownProfile.gfm029()` |
| 读取标题、链接或源码位置 | `Markdown.parse` + `AstQuery` |
| 控制输入、节点和输出上限 | `MarkdownEngine.builder().limits(...)` |
| 自定义 `:::` 容器或行内语法 | `MarkdownDialect` + Syntax DSL |
| lint、rewrite 或保留格式编辑 | `DocumentSnapshot` + `markdown.editor` |
| 缓存解析结果 | `markdown.artifact` |

[开发者 Cookbook](docs/cookbook.md)提供可复制的完整场景。常用签名见
[API 速查](docs/api/quick-reference.md)。

## 常用示例

### 启用 GFM

```cangjie
import markdown.core.{Markdown, MarkdownProfile}

let html = Markdown.toSafeHtml(
    "- [x] shipped\n\n~~old~~",
    profile: MarkdownProfile.gfm029()
)
```

`gfm029()` 用于 GFM 0.29 规范兼容。`gfm()` 是仓库固定的 modern profile。
[Profile 指南](docs/profiles.md)解释两者差异。

### 读取标题和源码位置

```cangjie
import markdown.core.Markdown
import markdown.editor.AstQuery

let result = Markdown.parse("# Install\n\nSee [API](api).")
for (heading in AstQuery.headings(result.document)) {
    let span = heading.node.span.getOrThrow()
    let position = result.source.utf16Position(span.startByte)
    println("${result.source.slice(span)} at ${position.line}:${position.character}")
}
```

`SourceSpan` 使用半开 UTF-8 byte range。LSP 位置通过 `SourceBuffer.utf16Position`
转换。查看 [AST 与 Source API](docs/api/ast-and-source.md)。

### 定义块扩展

```cangjie
import markdown.core.MarkdownEngine
import markdown.extensions.{BlockSyntax, ExtensionCapabilities, ExtensionManifest, MarkdownDialect, RendererRule}

let manifest = ExtensionManifest(
    "docs", "1.0.0", "example-1",
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

下一步查看[自定义容器语法](docs/cookbook.md#自定义容器语法)。

## 包结构

新代码应导入用途明确的子包。根包 `markdown.*` 只作为兼容门面。

| 子包 | 用途 |
| --- | --- |
| `markdown.core` | 解析、AST、源码位置、诊断、资源限制和 Event API |
| `markdown.render` | HTML、纯文本、Markdown、sink 和 source map |
| `markdown.extensions` | 方言、Syntax DSL、renderer DSL 和 SPI |
| `markdown.editor` | 查询、rewrite、lint、CST、snapshot 和编辑 |
| `markdown.artifact` | parse artifact 和 binary snapshot |
| `markdown.document` | document graph 和跨文档引用 |
| `markdown.testkit` | 第三方扩展 TCK |
| `markdown.native` | 可选原生 line scanner |

## 性能对比

完整 AST benchmark 每轮仍创建 `Document`、`NodeId`、`SourceSpan`、`SourceBuffer` 和
`ParseResult`。以下结果不使用轻量 event parser 替代公开 `parse()`。

| 对比 | 工作负载 | 结果 | 证据 |
| --- | --- | ---: | --- |
| cmark 0.31.1 | CommonMark 完整 AST parse | `2.38x` 较慢 | [canonical report](docs/reports/benchmark.md) |
| cmark-gfm 0.29 | GFM 完整 AST + HTML | `2.45x` 较慢 | [canonical report](docs/reports/benchmark.md) |
| markdown4cj | 同语言 CommonMark parse-only | `11.00x` 较快 | [同语言对比](docs/reports/markdown4cj-comparison.md) |

markdown4cj 数据来自固定旧提交和 SDK，只证明报告中冻结的共同 parse subset，不代表当前
两库所有功能的端到端比较。cmark/cmark-gfm 数据来自当前唯一 canonical release
evidence。测量边界和输入 API 见[性能说明](docs/performance.md)。

## 执行模型

- `parse(String)`、bytes 和 stream 入口构造完整 AST。
- `BufferedInputSession` 在 `finish()` 时解析，不降低峰值内存。
- `parseEvents` 和 `emitEvents` 产生不持有 AST 的 source events。
- `BufferedAsyncHtmlOutputSession` 先生成完整 HTML，再处理 sink backpressure。
- Safe HTML 默认转义 raw HTML，并拒绝危险 URI。

需要选择输入 API、流式接口或资源上限时，查看[输入、限制和取消](docs/input-and-resources.md)。

## 文档入口

- [开始使用](docs/getting-started.md)：从空工程得到第一个输出。
- [开发者 Cookbook](docs/cookbook.md)：按任务复制代码。
- [API 速查](docs/api/quick-reference.md)：查常用签名、默认值和错误。
- [完整 API reference](docs/api.md)：按公开子包查找类型。
- [故障排查](docs/troubleshooting.md)：解决依赖、profile、HTML 和位置问题。
- [扩展开发](docs/extensions.md)：定义 syntax、renderer 和测试契约。
- [0.8 到 0.9 迁移](docs/migration.md)：处理破坏性 API 变化。

## 验证状态

`release-evidence.json` 是当前测试、规范和 benchmark 数字的唯一事实源。

<!-- release-evidence:start -->
| Release evidence | Value |
| --- | --- |
| Version / status | `0.9.0` / `evidence-ready` |
| Offline evidence ready | `ready` |
| CI verified at evidence repository HEAD | `no` |
| Published release | `no` |
| Artifact commit | `856a6c7164fe97450b5ab7ff34926445b48dcc35` |
| Evidence commit | `490dad69584761733586cd674f6bc2cfd2555a78` |
| Repository HEAD at generation | `490dad69584761733586cd674f6bc2cfd2555a78` |
| CommonMark / cmark | `2.38x` / limit `2.5x` |
| GFM HTML / cmark-gfm | `2.45x` / limit `2.5x` |
| Benchmark identity | `current`; commit `856a6c7164fe97450b5ab7ff34926445b48dcc35`; SDK `1.1.0-alpha.20260803040049` |

The table is generated from [`release-evidence.json`](release-evidence.json).
`evidenceReady` describes reproducible offline artifacts and gates only. It does not claim that
the current repository HEAD passed hosted CI or that a GitHub release was published.
<!-- release-evidence:end -->

- CommonMark `652/652`
- GFM `671/671`
- 全量测试 `1455/1455`
- 公开 API snapshot `1311` declarations

## 参与项目

开发命令和变更约束见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请使用
[GitHub Private Vulnerability Reporting](https://github.com/lIlIIlIll/markdown/security/advisories/new)，
不要在公开 issue 中披露未修复漏洞。

许可证：[MIT](LICENSE)。
