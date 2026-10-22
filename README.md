<div align="center">

# markdown

**面向仓颉的高性能、可扩展 Markdown 文档引擎**

从安全 HTML 和完整 AST，到精确源码位置、扩展 DSL、格式化与编辑器工具。

[![Cangjie 1.2.0](https://img.shields.io/badge/Cangjie-1.2.0-7B61FF?style=for-the-badge)](cjpm.toml)
[![CommonMark 0.31.2](https://img.shields.io/badge/CommonMark-0.31.2-2F6F9F?style=for-the-badge)](docs/profiles.md)
[![GFM 0.29](https://img.shields.io/badge/GFM-0.29-24292F?style=for-the-badge)](docs/profiles.md)
[![Status pre-GA](https://img.shields.io/badge/Status-0.9.2_preview-F59E0B?style=for-the-badge)](docs/versioning-and-compatibility.md)
[![Developed with Codex](https://img.shields.io/badge/Developed_with-Codex-111111?style=for-the-badge&logo=openai&logoColor=white)](https://openai.com/codex/)
[![License MIT](https://img.shields.io/badge/License-MIT-16A34A?style=for-the-badge)](LICENSE)

[快速开始](#两分钟运行) · [开发者文档](docs/README.md) · [API 站点](https://liliilill.github.io/markdown/) · [性能报告](docs/performance.md) · [参与贡献](CONTRIBUTING.md)

</div>

当前开发版本是 `0.9.2` breaking pre-GA preview。公开 API 和实现按领域分包，
根包不再导出接口，旧门面和兼容构建路径已移除。升级前请阅读
[0.9.2 迁移](docs/migration-0.9.2.md)；已发布版本以 GitHub Release 为准。

> [!NOTE]
> 基础包是纯仓颉实现，不需要 C 编译器。原生 line scanner 是可选加速器，不是运行依赖。

真实公式、图表与代码高亮可选择[显式安装的 Node 后端](docs/node-rich-backend.md)；
默认解析和输出独立可用，不下载或启动该运行时。

## 为什么选择 markdown

| 能力 | 默认契约 |
| --- | --- |
| 安全输出 | raw HTML 默认转义，危险 URI 默认拒绝 |
| 完整语义树 | 每次 `parse` 都构造带 `NodeId`、`SourceSpan` 和来源信息的 AST |
| 标准兼容 | 固定 CommonMark 0.31.2 与 GFM 0.29 profile |
| 可控资源 | 输入、行、节点、literal、引用、URL、表格和输出均有预算 |
| 可扩展语法 | 块级、行内和 renderer DSL，含优先级、冲突和 TCK |
| 文档工具链 | query、rewrite、lint、CST、source map、format 和 snapshot |

## 两分钟运行

你需要 Cangjie STS SDK 1.2.0 和当前仓库的本地路径。基础包不要求 C 编译器。

在消费工程的 `cjpm.toml` 中添加依赖：

```toml
[dependencies]
  "markdown" = { path = "/absolute/path/to/markdown", output-type = "static" }
```

将下面的代码保存为 `src/main.cj`：

```cangjie
package markdown_demo

import markdown.engine.MarkdownEngine

main(): Int64 {
    let engine = MarkdownEngine.builder().build()
    println(engine.renderHtml("# Hello\n\n<script>blocked</script>").html)
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

| 目标 | 首选入口 | 深入阅读 |
| --- | --- | --- |
| Markdown 转安全 HTML | `engine.renderHtml(source).html` | [安全渲染](docs/security.md) |
| 启用表格、任务列表和删除线 | `MarkdownProfile.gfm029()` | [Profile 指南](docs/profiles.md) |
| 读取标题、链接或源码位置 | `engine.parse` + `AstQuery` | [AST 与位置](docs/ast.md) |
| 控制输入、节点和输出上限 | `MarkdownEngine.builder().limits(...)` | [输入与资源](docs/input-and-resources.md) |
| 自定义 `:::` 容器或行内语法 | `MarkdownDialect` + Syntax DSL | [扩展开发](docs/extensions.md) |
| lint、rewrite 或保留格式编辑 | `DocumentSnapshot` + `markdown.editor` | [文档系统](docs/document-systems.md) |
| 缓存解析结果 | `markdown.artifact` | [缓存与文档系统](docs/document-systems.md) |

[开发者 Cookbook](docs/cookbook.md)提供可复制的完整场景。按符号查询时打开
[API 站点](https://liliilill.github.io/markdown/)。

## 常用示例

### 启用 GFM

```cangjie
import markdown.core.{MarkdownProfile}
import markdown.engine.{MarkdownEngine}

let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfm029()).build()
let html = engine.renderHtml("- [x] shipped\n\n~~old~~").html
```

`gfm029()` 用于 GFM 0.29 规范兼容。`gfmModernV1()` 是仓库固定的 modern profile。
[Profile 指南](docs/profiles.md)解释两者差异。

### 读取标题和源码位置

```cangjie
import markdown.engine.MarkdownEngine
import markdown.core.AstQuery

let result = MarkdownEngine.builder().build().parse("# Install\n\nSee [API](api).")
for (heading in AstQuery.headings(result.document)) {
    let span = heading.node.span.getOrThrow()
    let position = result.source.utf16Position(span.startByte)
    println("${result.source.slice(span)} at ${position.line}:${position.character}")
}
```

`SourceSpan` 使用半开 UTF-8 byte range。LSP 位置通过 `SourceBuffer.utf16Position`
转换。查看[位置编码](docs/source-position.md)。

### 定义块扩展

```cangjie
import markdown.engine.MarkdownEngine
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

类型和实现位于各自领域包。根包 `markdown` 仅供 cjpm 发现模块，不导出公开声明或转导。

| 子包 | 用途 |
| --- | --- |
| `markdown.core` | AST、源码位置、诊断、资源限制、query 和 rewrite |
| `markdown.engine` | parser、builder、Event API、追加会话、融合 HTML 与能力报告 |
| `markdown.render` | HTML、纯文本、Markdown、sink 和 source map |
| `markdown.extensions` | 方言、Syntax DSL、renderer DSL 和 SPI |
| `markdown.editor` | lint、CST、snapshot、编辑和范围格式化 |
| `markdown.artifact` | parse artifact 和 binary snapshot |
| `markdown.document` | document graph 和跨文档引用 |
| `markdown.testkit` | 第三方扩展 TCK |
| `markdown.native` | 可选原生 line scanner |
| `markdown.node` | 显式、可选的 KaTeX/Shiki/Mermaid 准备端口 |

## 性能对比

完整 AST benchmark 每轮仍创建 `Document`、`NodeId`、`SourceSpan`、`SourceBuffer` 和
`ParseResult`。以下比较不使用轻量 event parser 替代公开 `parse()`；当前比值只在对应报告
和 release evidence 中维护。

| 对比 | 工作负载 | 当前结果 |
| --- | --- | --- |
| cmark 0.31.1 | CommonMark 完整 AST parse | [Canonical benchmark](docs/reports/benchmark.md) |
| cmark-gfm 0.29 | GFM 完整 AST + HTML | [Canonical benchmark](docs/reports/benchmark.md) |
| markdown4cj | 同语言 CommonMark parse-only | [同语言对比](docs/reports/markdown4cj-comparison.md) |

markdown4cj 报告绑定当前产品 tree、固定 comparator commits、SDK、语料和 harness，只证明
共同的 CommonMark parse-only subset，不代表两库所有功能的端到端比较。每个 PR 都会重新
运行这项同语言 benchmark；cmark/cmark-gfm 仍是唯一 canonical release evidence。
测量边界和输入 API 见[性能说明](docs/performance.md)。

> [!IMPORTANT]
> 性能数字只以 `release-evidence.json` 绑定的 commit、SDK、语料和 raw report 为准；
> README 不维护另一套手工结果。

## 执行模型

- `parse(String)`、bytes 和 stream 入口构造完整 AST。
- `newAppendSession()` 在 feed 中交付结构闭合块，通过原子更新在 finish 完成后置引用和绑定。
- `BufferedInputSession` 在 `finish()` 时解析，不降低峰值内存。
- `parseEvents` 和 `emitEvents` 产生不持有 AST 的 source events。
- `renderer.newOutputSession()` 保存实际遍历和转义状态，按 UTF-8 前缀确认暂停与恢复。
- Safe HTML 默认转义 raw HTML，并拒绝危险 URI。

需要选择输入 API、流式接口或资源上限时，查看[输入、限制和取消](docs/input-and-resources.md)。

## 文档入口

| 路线 | 适合你在…… | 入口 |
| --- | --- | --- |
| 学习 | 第一次集成或需要可运行示例 | [开始使用](docs/getting-started.md) → [Cookbook](docs/cookbook.md) |
| 查询 | 已经知道类型或错误，想快速定位 | [API 站点](https://liliilill.github.io/markdown/) → [本地生成](docs/api.md#本地生成与预览) |
| 扩展 | 正在设计 syntax、renderer 或 SPI | [扩展开发](docs/extensions.md) → [Extension TCK](docs/extension-tck.md) |
| 运维 | 遇到构建、profile、位置或限制问题 | [故障排查](docs/troubleshooting.md) → [安全指南](docs/security.md) |
| 升级 | 从 0.9.1 更新到领域分包 | [0.9.2 迁移](docs/migration-0.9.2.md) |

## 验证状态

`release-evidence.json` 是当前测试、规范和 benchmark 数字的唯一事实源。

<!-- release-evidence:start -->
| Release evidence | Value |
| --- | --- |
| Version / status | `0.9.2` / `evidence-ready` |
| Offline evidence ready | `ready` |
| CI verified at evidence repository HEAD | `no` |
| Published release | `no` |
| Tests | `1622/1622` passed; `0` skipped; `0` failed |
| CommonMark conformance | `652/652` |
| GFM conformance | `671/671` |
| Public API snapshot | `1679` declarations |
| Artifact commit | `6a375488a40092e2289f461b0e5d66bf39a5826f` |
| Evidence subject commit | `6a375488a40092e2289f461b0e5d66bf39a5826f` |
| Execution identity | `target/release-evidence/manifest.json` records and verifies the clean gate commit/tree |
| CommonMark / cmark | `2.31x` / limit `2.5x` |
| GFM HTML / cmark-gfm | `2.02x` / limit `2.5x` |
| Benchmark identity | `current`; commit `6a375488a40092e2289f461b0e5d66bf39a5826f`; SDK `Cangjie Compiler: 1.2.0 (cjnative)` |

The table is generated from [`release-evidence.json`](release-evidence.json).
`evidenceReady` describes reproducible offline artifacts and gates only. It does not claim that
the current repository HEAD passed hosted CI or that a GitHub release was published.
<!-- release-evidence:end -->

## 参与项目

开发命令和变更约束见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请使用
[GitHub Private Vulnerability Reporting](https://github.com/lIlIIlIll/markdown/security/advisories/new)，
不要在公开 issue 中披露未修复漏洞。

许可证：[MIT](LICENSE)。
