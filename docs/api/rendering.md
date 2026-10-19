# Rendering API

`markdown.render` 提供 HTML、纯文本和 canonical Markdown 输出。HTML 默认使用安全
策略。

## `HtmlRenderer`

```cangjie
let renderer = HtmlRenderer(options: HtmlOptions.safe())
let html = renderer.render(
    document,
    cancellation: CancellationToken.none(),
    budget: OperationBudget.safe()
)
```

构造参数：

| 参数 | 类型 | 默认值 |
| --- | --- | --- |
| `options` | `HtmlOptions` | `HtmlOptions.safe()` |
| `extensionRules` | `Array<RendererRule>` | `[]` |
| `sanitizer` | `?HtmlSanitizerPort` | `None` |
| `extensionManifests` | `Array<ExtensionManifest>` | `[]` |
| `extensionFallbacks` | `Array<ExtensionRendererFallback>` | `[]` |
| `rawHtmlHandler` | `?RawHtmlHandlerPort` | `None` |
| `maximumOutputBytes` | `?Int64` | `None` |
| `codeGroups` | `CodeGroupHtmlOptions` | `CodeGroupHtmlOptions.defaults()` |
| `prepared` | `?RichContentPreparation` | `None` |

使用扩展方言时，优先通过 engine 创建 renderer：

```cangjie
let renderer = engine.htmlRenderer(options: HtmlOptions.safe())
```

这会自动安装 compiled dialect 的 manifest 和 renderer rules。

`prepared` 接收[显式富内容准备](../rich-content.md)的结果，并验证文档 revision。
准备结果与原文、语义 AST 和持久化缓存分离；安全默认值不会启动外部后端。

## HTML policy

| Factory | Raw HTML | URI 行为 | 用途 |
| --- | --- | --- | --- |
| `HtmlOptions.safe()` | 转义 | 安全 link policy；remote/data image 默认关闭 | 不可信输入 |
| `unsafe { HtmlOptions.specCompatible() }` | pass-through | CommonMark 兼容 | 规范对比或可信输入 |
| `unsafe { HtmlOptions.gfmCompatible() }` | pass-through + GFM tagfilter | GFM 兼容 | GFM 规范对比 |

`specCompatible()` 和 `gfmCompatible()` 不是 sanitizer。不要用于未经信任且会直接
插入网页的输入。两个 factory 都是 `unsafe`，因为它们会原样输出规范允许的 raw HTML。

## 自定义 `HtmlOptions`

```cangjie
let options = HtmlOptions(
    HtmlPolicy.safe(),
    RawHtmlPolicyKind.Escape,
    LinkUriPolicy.safe(),
    ImageUriPolicy(
        true,
        false,
        true,
        allowedDataMimeTypes: ["image/png", "image/jpeg"]
    ),
    externalLinkRel: "noopener noreferrer",
    externalLinkTarget: "_blank"
)
```

### `RawHtmlPolicyKind`

- `Escape`
- `Drop`
- `PassThrough`
- `Sanitize`
- `CustomHandler`

`Sanitize` 需要提供 `HtmlSanitizerPort`。adapter 抛错时 renderer 会传播错误，不会
回退到未清理 HTML。

普通 `HtmlOptions` 构造器拒绝 `PassThrough`。可信输入必须通过
`unsafe { HtmlOptions.passThrough(...) }`、`specCompatible()` 或 `gfmCompatible()`
显式启用。

`CustomHandler` 需要 `RawHtmlHandlerPort`。handler 接收 raw literal 和 block 标记，
并返回 `TrustedHtml`。缺少 handler 时 renderer 以 `RenderFailure` 失败。handler 的
`identity` 必须非空，并进入 renderer fingerprint。

```cangjie
public class MyRawHtmlHandler <: RawHtmlHandlerPort {
    public prop identity: String {
        get() { "my-raw-html-handler-v1" }
    }

    public func renderRawHtml(_: String, block: Bool): TrustedHtml {
        let replacement = if (block) { "<div>raw HTML removed</div>" } else { "<span>raw HTML removed</span>" }
        unsafe { TrustedHtml.fromString(replacement) }
    }
}
```

该示例丢弃 raw literal，并返回固定的宿主可信标记。库不会替 handler 判断输出是否安全。

### `LinkUriPolicy`

```cangjie
LinkUriPolicy(
    allowRelative,
    allowHttp,
    allowHttps,
    allowMailto
)
```

`safe()` 允许 relative、HTTP、HTTPS 和 mailto，拒绝
`javascript:`、`vbscript:`、`file:` 等 scheme。

### `ExternalLinkRewriterPort`

`rewriteExternalLinks` 只处理已经解析的 HTTP 或 HTTPS destination。renderer 先调用
rewriter，再对返回值执行 URI policy 和 attribute escaping。relative URL 和 `mailto:`
保持不变。返回危险 scheme 时，renderer 不生成 `href`。

```cangjie
public class Redirector <: ExternalLinkRewriterPort {
    public prop identity: String {
        get() { "docs-redirector-v1" }
    }

    public func rewriteExternalLink(uri: String): String {
        "https://redirect.example/?url=${uri}"
    }
}

let options = HtmlOptions(
    HtmlPolicy.safe(),
    RawHtmlPolicyKind.Escape,
    LinkUriPolicy.safe(),
    ImageUriPolicy.safe(),
    rewriteExternalLinks: Some(Redirector())
)
```

`identity` 必须稳定且非空。更改 rewrite 语义时，也要更改 identity。identity 进入
renderer fingerprint。

### `ImageUriPolicy`

```cangjie
ImageUriPolicy(
    allowRelative,
    allowRemoteImages,
    allowDataImages,
    allowedDataMimeTypes: []
)
```

允许 data image 时，renderer 比较完整 media type。允许 `image/png` 不会同时允许
`image/pngx`。

## Sink 输出

实现 `TextSink` 可避免先生成完整 String：

```cangjie
public class MySink <: TextSink {
    public func write(slice: String): SinkWriteResult {
        // 将 slice 写入调用者控制的目标。
        SinkWriteResult.Success
    }
}

renderer.renderTo(document, MySink())
```

`write` 返回 `Success` 或 `Failure(SinkError)`。失败会转换为
`SinkFailureException`。每次写入前都会检查 output budget。

`maximumOutputBytes` 是 renderer 的固定上限。`MarkdownEngine.htmlRenderer()` 自动使用
engine 的 `ParseLimits.maximumOutputBytes`。显式构造 `HtmlRenderer` 时，可以传入独立
上限。renderer 在写出每个 escape、URI 和 GFM tagfilter segment 前检查固定上限和
`OperationBudget`，不会先构造节点大小的 escaped output。

Renderer 在入口、退出、每 256 个辅助节点和长 text、attribute、URI、escape、tagfilter
扫描的至多 1024 bytes 间隔检查 cancellation。已经观察到取消后不会继续写 Sink；空文档
同样执行入口与退出检查。

固定 output limit 属于 renderer 可观察语义，因此进入 renderer fingerprint。extension
manifest 会按稳定身份规范化顺序；每个 manifest 的 `missingRendererPolicy` 进入
fingerprint，而 renderer rule 的声明顺序仍按语义保留。

同一个 `HtmlRenderer` 不能注册重复的 extension ID；构造器会 fail fast。这样运行时的
manifest 选择与规范化 fingerprint 保持一一对应。

Sanitizer、raw HTML handler 和 extension fallback 是宿主代码。它们返回的完整 String
会在写入 sink 前受 output limit 约束，但库不能限制 adapter 内部如何分配该 String。

对内建 text、attribute、URI 和 fused source range，renderer 会先按原始 range 计算并
消费预算，再创建 substring。低 output limit 因此不会先分配与攻击者输入等长的临时值。

GFM tagfilter 只在 denylist 名称后为输入结束、HTML 空白、`/` 或 `>` 时匹配。
`<script>` 会被过滤，而 `<script-x>`、`<script1>` 和 `<script_>` 保持普通自定义标签。

`StringTextSink` 是内置 String 收集器。

## Source map

```cangjie
let output = renderer.renderWithSourceMap(document)
let sourceSpan = output.sourceSpanAt(5)
let nodeId = output.nodeIdAt(5)
```

`RenderedOutput` 包含：

- `content`
- 按 output byte range 排序的 `sourceMap`
- `sourceSpanAt(outputByte)`
- `nodeIdAt(outputByte)`
- `outputRanges(nodeId)`

renderer 在写出内容时同步记录 source map。generated tag 和来自节点的文本不会通过
输出字符串搜索反推。

## 可恢复 HTML 输出

```cangjie
let session = renderer.newOutputSession(document, chunkBytes: 4096)
let state = session.resume(sink)
```

构造时不渲染。resume 从保存的遍历和转义状态写出，返回 Complete、Paused 或
`Failed(MarkdownException)`。sink 用 Continue 确认整个片段，或用 `Pause(n)` 确认 UTF-8
前缀后暂停。重试未确认片段不会再次渲染或计费。chunkBytes 至少为 4。

`bytesWritten()`、`bytesProduced()` 和 `bufferedBytes()` 分别记录确认、生成和待写出
字节。Complete/Failed 后不能再次 resume。旧 BufferedAsyncHtmlOutputSession 已移除。
完整契约见[暂停与恢复 HTML 输出](../html-output.md)。

## `PlainTextRenderer`

```cangjie
let text = PlainTextRenderer(
    options: PlainTextOptions(
        includeLinkDestinations: false,
        softBreak: "\n"
    )
).render(document)
```

`includeLinkDestinations` 控制是否在链接文本后输出 destination。`softBreak` 控制
SoftBreak 的文本形式。

## `CanonicalMarkdownRenderer`

```cangjie
let formatter = CanonicalMarkdownRenderer(
    options: MarkdownFormatOptions(
        newline: "\n",
        bulletMarker: "-",
        orderedDelimiter: ".",
        emphasisMarker: "*",
        strongMarker: "**",
        minimumFenceLength: 3,
        tablePadding: true,
        finalNewline: true,
        maximumLineWidth: 100,
        reflowParagraphs: false
    )
)
let markdown = formatter.render(document)
```

输出是确定性的 canonical Markdown。`reflowParagraphs` 默认关闭。扩展节点需要
renderer rule 的 Markdown lowering；缺失策略由 manifest 决定。

## `TrustedHtml`

`TrustedHtml.fromString` 是 unsafe factory，只用于宿主已经验证的 HTML：

```cangjie
let trusted = unsafe { TrustedHtml.fromString(value) }
```

`TrustedHtml` 不会绕过 output budget、取消或 sink error。不要把普通扩展字符串包装
成 TrustedHtml。

`HtmlSanitizerPort.identity`、`RawHtmlHandlerPort.identity` 和
`ExternalLinkRewriterPort.identity` 参与 renderer fingerprint。
`ExtensionRendererFallback` 还必须提供 `implementationVersion`。语义或实现发生变化时，
请同步更新这些稳定身份字段，避免 artifact 或 renderer cache 复用旧输出。

## 错误

| 错误 | 条件 |
| --- | --- |
| `SinkFailureException` | sink 返回失败 |
| `LimitExceededException` | output byte 或 rendered-node 限制超出 |
| `MarkdownException(RenderFailure)` | renderer coverage、fused preflight 或节点输出失败 |
| sanitizer adapter error | `HtmlSanitizerPort` 抛出异常 |

## 下一步

- [安全 HTML 与 URI](../security.md)
- [Renderer DSL](../renderer-dsl.md)
- [Formatting](../formatting.md)

## 代码组渐进增强

`HtmlRenderer(codeGroups: CodeGroupHtmlOptions(...))` 或
`engine.htmlRenderer(codeGroups: ...)` 显式输出 tabs/copy 数据，默认关闭且不加载 JS。
本地化标签、复制上限和完整静态回退见[代码组](../code-groups.md)。选项进入 renderer
fingerprint；未启用时不活跃的标签不改变 fingerprint，也不改变 parser 或 source 身份。
