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

使用扩展方言时，优先通过 engine 创建 renderer：

```cangjie
let renderer = engine.htmlRenderer(options: HtmlOptions.safe())
```

这会自动安装 compiled dialect 的 manifest 和 renderer rules。

## HTML policy

| Factory | Raw HTML | URI 行为 | 用途 |
| --- | --- | --- | --- |
| `HtmlOptions.safe()` | 转义 | 安全 link policy；remote/data image 默认关闭 | 不可信输入 |
| `HtmlOptions.specCompatible()` | pass-through | CommonMark 兼容 | 规范对比或可信输入 |
| `HtmlOptions.gfmCompatible()` | pass-through + GFM tagfilter | GFM 兼容 | GFM 规范对比 |

`specCompatible()` 和 `gfmCompatible()` 不是 sanitizer。不要用于未经信任且会直接
插入网页的输入。

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
        SinkWriteResult.Continue
    }
}

renderer.renderTo(document, MySink())
```

`write` 返回 `Continue` 或 `Failed(SinkError)`。失败会转换为
`SinkFailureException`。每次写入前都会检查 output budget。

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

## Buffered async output

```cangjie
let session = BufferedAsyncHtmlOutputSession(
    renderer,
    document,
    chunkBytes: 4096
)
let state = session.resume(sink)
```

`resume` 返回 `Complete`、`Paused` 或 `Failed`。`bytesWritten()` 返回已经确认
写入的 byte 数。

这个 API 会在构造 session 时生成完整 HTML。它只让 sink delivery 支持 backpressure，
不会降低 renderer 的峰值输出内存。`AsyncHtmlRenderSession` 是相同行为的兼容名称。

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
