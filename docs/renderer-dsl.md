# Renderer DSL

`RendererRule` 把 custom node 降低为 HTML、Markdown 和纯文本。custom node 与内置节点
共用 escaping、URI policy、cancellation、node/output budget、SourceMap 和 sink 错误路径。

## 定义 rule

```cangjie
let rule = RendererRule(
    "docs",
    "note",
    "aside",
    classToken: "note",
    markdownOpener: ":::note\n",
    markdownCloser: "\n:::",
    textPrefix: "Note: "
)
```

前三个参数是 extension ID、local kind 和 HTML tag。可选字段定义 class、Markdown
opener/closer、text prefix/suffix、structured attributes、payload literal 和 Markdown block
lowering。

## HTML 安全

普通 String 始终转义。tag、class 和 attribute 名称在 dialect 编译时验证；`on*` 与
`style` attribute 被拒绝。`href` 和 `src` 必须显式声明 URI kind，并经过内置 link/image
相同的 policy。

structured attribute 的值可来自固定配置、typed payload parameter 或 payload literal。
自定义 HTML fallback 只能返回通过显式 unsafe factory 创建的 `TrustedHtml`。它仍受 output
budget 和 cancellation 约束。

raw HTML sanitization 是独立的 `HtmlSanitizerPort`。adapter 失败会向调用者传播，不会回退
到未净化输出。

## 缺失 renderer

manifest 的 `missingRendererPolicy` 默认是 `Error`：

| Policy | 行为 |
| --- | --- |
| `Error` | 缺失实现时失败 |
| `RenderChildren` | 只输出 children |
| `RenderLiteral` | 输出 payload literal |
| `Drop` | 明确丢弃节点 |
| `CustomFallback` | 调用显式 fallback |

如果 extension 声明某个 renderer capability，却没有 rule 或明确 fallback，dialect 编译
直接失败。

## Sink 与异步适配

renderer 写入前检查 output budget，并保留 sink 错误。SourceMap 在 writer 写出正文时同步
记录，不通过 HTML 字符串反向搜索。

`BufferedAsyncHtmlOutputSession` 会先生成完整、有界 HTML，再按 `Continue`、`Pause` 或
`Failed` 推送。它是 buffered backpressure adapter，不是增量 parser-renderer。

完整构造参数和 renderer API 见 [Extensions API](api/extensions.md)与
[Rendering API](api/rendering.md)。
