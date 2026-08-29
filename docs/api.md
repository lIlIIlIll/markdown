# API reference

API reference 按公开子包组织。每页给出常用签名、参数默认值、返回值、错误语义和
可复制示例。完整声明清单由
[`api/public-api-v0.9.txt`](../api/public-api-v0.9.txt)维护。

## 导入策略

新代码应导入最小子包：

```cangjie
import markdown.core.{MarkdownEngine, MarkdownProfile}
import markdown.render.{HtmlOptions, HtmlRenderer}
```

根包 `markdown.*` 继续导出所有兼容符号，但会让代码无意依赖 editor、artifact
或 testkit API。

## Reference 页面

| 页面 | 主要类型 |
| --- | --- |
| [Core API](api/core.md) | `Markdown`、`MarkdownEngine`、`ParseResult`、profile、limits、diagnostics、Event API |
| [AST 与 Source API](api/ast-and-source.md) | `Document`、`NodeRef`、typed node views、`SourceBuffer`、`SourceSpan`、position map |
| [Rendering API](api/rendering.md) | `HtmlRenderer`、`HtmlOptions`、URI policy、sink、source map、plain text、Markdown formatter |
| [Extensions API](api/extensions.md) | manifest、dialect、block/inline syntax、renderer rule、SPI、official extensions |
| [Editor API](api/editor.md) | walk/query/rewrite、CST、snapshot、lint、preserving formatter |
| [Artifact 与 Document API](api/artifacts-and-services.md) | parse artifact、binary snapshot、document graph、HTML conversion、observability、testkit |

## 子包导出

### `markdown.core`

解析、AST、SourceSpan、诊断、资源限制、profile、capabilities、Event API 和显式
HTML execution mode。

### `markdown.render`

HTML、纯文本和 canonical Markdown renderer，以及 sink、source map、sanitizer port
和 URI policy。

### `markdown.extensions`

扩展 manifest、dialect compiler、Syntax DSL、renderer DSL、SPI、external descriptor
和 official extensions。

### `markdown.editor`

CST、source-to-AST map、walker、query、rewrite、transform、lint、snapshot 和保留格式编辑。

### `markdown.artifact`

内存 parse artifact 与 binary snapshot codec。cache mismatch 返回显式
`CacheMiss`，不会猜测恢复。

### `markdown.document`

`DocumentSnapshot`、`DocumentGraph` 和跨文档 reference。库只处理调用者提供的
文本，不读取文件或网络。

### `markdown.testkit`

第三方扩展的公开 TCK。

### `markdown.native`

可选 `NativeLineScanner`。只有显式导入并链接目标平台 archive 的消费工程才依赖
foreign symbol。

## 默认行为

| 行为 | 默认值 |
| --- | --- |
| Parser profile | `MarkdownProfile.commonMark0312()` |
| Parse limits | `ParseLimits.safe()` |
| Operation budget | `OperationBudget.safe()` |
| Cancellation | `CancellationToken.none()` |
| UTF-8 bytes | `Utf8Policy.Strict` |
| HTML policy | `HtmlOptions.safe()` |
| Event mode | `MarkdownEventMode.ResolvedEventMode` |
| HTML execution | `HtmlExecutionMode.FullAst` |
| Range-format fallback | `RangeFormatFallback.PreserveSource` |

## 错误处理

解析和渲染的结构化失败继承 `MarkdownException`。程序应根据
`MarkdownErrorCode`、`phase` 和可选 `span` 分支，不要解析英文错误文本。

```cangjie
try {
    let result = engine.parse(source)
} catch (error: MarkdownException) {
    println("code=${error.code}, phase=${error.phase}")
}
```

`tryParse` 返回失败的 `ParseResult`，其中包含空 `Document` 和结构化错误。它不返回
已经完成的 AST 前缀。

## 版本

当前 reference 对应 `0.9.0`。0.9 是 breaking pre-GA preview。API snapshot
`v0.9` 是当前声明事实源；历史 `public-api-v1.txt` 不是当前兼容承诺。
详见 [版本与兼容性](versioning-and-compatibility.md)。
