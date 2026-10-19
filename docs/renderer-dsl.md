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

脚注、标题 ID 和定义列表的 typed payload 使用共享语义绑定及固定输出。为这些 local
kind 注册通用 RendererRule 会在编译时失败；opaque emitter 运行后才产生 typed payload
时，各输出也会明确拒绝匹配的通用 override。相关边界见[完整文档阶段](api/extensions.md#完整文档阶段)。

## HTML 安全

普通 String 始终转义。tag、class 和 attribute 名称在 dialect 编译时验证；`on*` 与
`style` attribute 被拒绝。`href` 和 `src` 必须显式声明 URI kind，并经过内置 link/image
相同的 policy。

structured attribute 的值可来自固定配置、typed payload parameter 或 payload literal。
自定义 HTML fallback 只能返回通过显式 unsafe factory 创建的 `TrustedHtml`。它仍受 output
budget 和 cancellation 约束。`ExtensionRendererFallback` 必须提供稳定的
`extensionId` 和 `implementationVersion`，两者都进入 renderer fingerprint。

raw HTML sanitization 是独立的 `HtmlSanitizerPort`。adapter 失败会向调用者传播，不会回退
到未净化输出。sanitizer 必须提供稳定且非空的 `identity`。自定义 raw HTML lowering 使用
`RawHtmlHandlerPort`，并由 `RawHtmlPolicyKind.CustomHandler` 显式选择。

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

`missingRendererPolicy` 会改变缺失 rule 时的输出，因此进入 renderer fingerprint。
manifest 集合按稳定身份规范化，注册顺序本身不改变 fingerprint；renderer rule 的声明
顺序会影响冲突决策，所以仍按原顺序编码。

一个 renderer 中的 manifest `extensionId` 必须唯一。重复 ID 会在构造阶段被拒绝，不会
依赖 first-match 顺序产生无法由 fingerprint 区分的行为。

## Sink 与异步适配

renderer 写入前检查 output budget，并保留 sink 错误。SourceMap 在 writer 写出正文时同步
记录，不通过 HTML 字符串反向搜索。

`renderer.newOutputSession()` 在 resume 中执行实际遍历，按 `Continue`、`Pause(n)` 或
`Failed` 消费结果恢复；不会预先渲染整份 HTML。确认、预算和终态契约见
[暂停与恢复 HTML 输出](html-output.md)。

完整构造参数和 renderer API 见 [Extensions API](api/extensions.md)与
[Rendering API](api/rendering.md)。
