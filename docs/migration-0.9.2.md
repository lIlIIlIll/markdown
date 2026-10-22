# 从 0.9.1 迁移到 0.9.2

0.9.2 是 breaking pre-GA。它移除旧门面、转导和历史构建分支，并将声明与实现放入真实
领域包。使用官方 STS 1.2.0 重新构建全部消费者，按下列步骤更新调用。
已发布的 v0.9.1 tag 与历史证据保持不变；本页不表示 0.9.2 已发布。

## 更新导入和解析入口

根包 `markdown` 不再公开任何声明。按使用的能力导入领域包：

| 领域包 | 接口归属 |
| --- | --- |
| `markdown.core` | AST、source、ParseResult、profile、限制、诊断、query、rewrite、annotation |
| `markdown.extensions` | manifest、dialect、DSL、SPI、官方扩展 |
| `markdown.render` | HTML、文本、canonical Markdown、source map、异步输出、富内容 |
| `markdown.engine` | engine、builder、parser、事件、追加会话、融合执行和能力报告 |
| `markdown.editor` | snapshot、CST、编辑、lint、范围格式化 |
| `markdown.artifact` | parse artifact、binary snapshot |
| `markdown.document` | 多文档 graph 和跨文档工具 |
| `markdown.testkit` | 扩展测试契约 |

`Markdown` 门面已删除。复用一个 engine，直接选择解析或渲染操作：

```cangjie
import markdown.engine.MarkdownEngine
import markdown.render.{CanonicalMarkdownRenderer, PlainTextRenderer}

let engine = MarkdownEngine.builder().build()
let result = engine.parse("# title")
let html = engine.renderHtml("# title").html
let text = PlainTextRenderer().render(result.document)
let formatted = CanonicalMarkdownRenderer().render(result.document)
```

安全 HTML 仍是默认值。规范 HTML 通过 `unsafe { HtmlOptions.specCompatible() }` 显式选择，
并传入 `engine.renderHtml` 或 `engine.htmlRenderer`。`Document.detach()` 保留在 core，
继续执行来源持有与 payload ownership 检查。

## 配置 scanner

`AcceleratedMarkdownEngine`、`acceleratedBy()` 和 `nativeScannerEnabled()` 已删除。
在构建 engine 时配置可选端口：

```cangjie
import markdown.engine.MarkdownEngine
import markdown.native.NativeLineScanner

let engine = MarkdownEngine.builder().lineScanner(Some(NativeLineScanner())).build()
let result = engine.parse(bytes)
```

默认不配置端口，使用纯仓颉扫描。native archive 仍由消费端显式链接。
端口支持 bytes、owned/reusable UTF-8 和 stream 路径；String 不为启用 native 而复制成 bytes。
不支持的输入或容量不足继续有界回退，未知 record version 继续拒绝。

## 将 snapshot、lint 与缓存交给所属领域

```cangjie
import markdown.artifact.MarkdownParseArtifact
import markdown.editor.{DocumentSnapshot, MarkdownLinter}
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let snapshot = DocumentSnapshot.parse(engine, "# title")
let diagnostics = MarkdownLinter(engine).lint(snapshot)
let artifact = MarkdownParseArtifact.create(engine, snapshot.result)
let loaded = artifact.load(engine, "# title")
```

`ExtensionLintProvider` 位于 editor，通过 `MarkdownLinter(engine, providers: [...])` 注册。
删除 dialect builder 的 `.lint(provider)`，并将原 provider 传给 linter。provider 身份、
重复注册、snapshot 归属和异常仍会校验。`MarkdownLinter.applyFix` 保留。

parse artifact 和 binary snapshot 仍验证来源、profile、fingerprint、schema 和摘要。
parser plan 更新为 7，旧缓存返回 miss，调用方重新解析。lint provider 不再参与 dialect
解析指纹。不同所有权和 UTF-8 失败语义的输入重载仍保留。

`MarkdownEngineBuilder` 统一通过 `MarkdownEngine.builder()` 创建。
`SourcePositionMap` 使用一个构造器，以命名参数设置 `tabStop` 和 `displayWidthPolicy`。

## 更新构建与接口检查

- benchmark 只保留 canonical 构建，删除 `--mode` 参数和 `MARKDOWN_BENCHMARK_DRIVER_MODE`。
- release evidence 只接受 schema 4，旧 schema 在加载时拒绝。
- 当前声明仅维护 [`api/public-api.txt`](../api/public-api.txt)。历史 API 通过
  [v0.9.1 tag](https://github.com/lIlIIlIll/markdown/blob/v0.9.1/api/public-api-v0.9.1.txt) 查阅。

完成迁移后运行：

```sh
cjpm check
cjpm build
cjpm test --no-color --no-progress
python3 scripts/check_docs.py
python3 scripts/check_public_api.py
```

构建通过后运行实际消费者，再检查自定义扩展、编辑和缓存路径。标准语料、安全默认值、
资源上限与取消仍需通过原有行为门槛；接口迁移不放宽这些契约。
