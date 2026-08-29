# 扩展模型

`markdown.extensions` 用不可变方言描述 Markdown 语义。扩展可以声明受限语法、
renderer lowering、文档处理器和 lint provider；engine 在第一次解析前完成依赖、冲突、
资源边界和 renderer coverage 校验。

如果只需要 CommonMark 或 GFM，请直接使用内置 profile。只有需要稳定复用自定义语法时，
才创建方言。

## 扩展生命周期

```text
ExtensionManifest + Syntax + RendererRule
                 ↓ MarkdownDialectBuilder.build()
        CompiledMarkdownDialect
                 ↓ MarkdownEngine.builder().dialect(...)
          parse / render / format
```

`CompiledMarkdownDialect` 是不可变且可并发复用的。运行时不会动态更改 rule 顺序。
`disable(extensionId)` 在编译前移除该扩展的 manifest、syntax、renderer、SPI、processor
和 lint provider。

## 最小块扩展

```cangjie
import markdown.core.*
import markdown.extensions.*

let manifest = ExtensionManifest(
    "docs",
    "1.0.0",
    "example-1",
    capabilities: ExtensionCapabilities(
        safeHtml: true,
        plainText: true,
        markdown: true
    )
)

let dialect = MarkdownDialect
    .define("docs-v1", "1.0.0")
    .enable(manifest)
    .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
    .renderer(
        RendererRule(
            "docs", "note", "aside",
            classToken: "note",
            markdownOpener: ":::note\n",
            markdownCloser: "\n:::"
        )
    )
    .build()

let engine = MarkdownEngine.builder().dialect(dialect).build()
let html = engine.renderHtml(engine.parse(":::note\n**important**\n:::"))
```

## 选择 DSL 还是 SPI

| 需求 | 使用 |
| --- | --- |
| 固定 delimiter、token 或块 opener | `InlineSyntax` / `BlockSyntax` |
| 静态 HTML、Markdown、纯文本 lowering | `RendererRule` |
| DSL 无法表达、但 lookahead 有界的行内语法 | `InlineParserSpi` |
| 需要整棵 AST 的后处理 | `ExtensionDocumentProcessor` |
| snapshot 级诊断 | `ExtensionLintProvider` |

优先使用 DSL。它的边界、优先级和资源成本可以在 dialect 编译时验证。SPI callback
运行在宿主进程内，必须自行保证确定性并遵守声明的 lookahead。

## 优先级、错误和 fallback

方言编译器按 phase、priority、registration order 和 rule identity 生成确定性执行计划。
重复 ID、opener 冲突、依赖缺失、版本不满足、依赖环和显式 conflict 都会在 `build()`
期间失败，而不是等到解析时随机选择。

未注册的语法保持普通文本。已注册但未闭合的扩展产生
`MD3002_UNCLOSED_EXTENSION`；非法参数产生
`MD3003_INVALID_EXTENSION_PARAMETER`。

`ExtensionCapabilities` 分别声明 parse、HTML、纯文本、Markdown、CST、format、
serialize、incremental、lint、postprocess 和 transform。声明能力后必须提供实现，或在
manifest 中选择明确的 missing-renderer policy。默认 policy 是 `Error`。

## 安全边界

code extension 与宿主进程权限相同，库不声称对 callback 做进程内沙箱。
`IsolatedPluginRunner` 是 fail-closed IPC 契约；真正的 OS process、文件系统和网络隔离由
宿主提供的 `PluginIsolationTransport` 实现。

transport 的 `invoke` 实现必须增量调用 `IsolatedPluginResponseSink.writeOutput`；每条
diagnostic 使用 `beginDiagnostic`、分块 `writeDiagnosticMessage` 和 `finishDiagnostic`，
最后只返回 `IsolatedPluginResponseIdentity`。不要先把不可信 output 或 diagnostics 解码到
宿主集合中；这样会绕过 `PluginIsolationPolicy` 的 response 预算。

外部 JSON/YAML descriptor 只能携带数据，不能携带或执行 callback。Front Matter 和 Math
官方扩展也只保留 literal，不解释配置或执行数学引擎。

## 验证

```cangjie
import markdown.testkit.*

let report = MarkdownExtensionTestKit.verify(engine, sample)
```

TCK 覆盖 parse/render、SourceSpan、确定性、chunk invariance 和 AST 不变量。扩展包仍需增加
自身的未闭合、嵌套、冲突、limits、cancellation 和 renderer fallback 用例。

## 相关文档

- [Extensions API](api/extensions.md)
- [Dialect DSL](dialect-dsl.md)
- [Syntax DSL](syntax-dsl.md)
- [Renderer DSL](renderer-dsl.md)
- [SPI 与 schema 版本](spi-and-schema-versions.md)
- [Extension TCK](extension-tck.md)
