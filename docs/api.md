# API reference

先看[API 速查](api/quick-reference.md)。需要完整语义、错误和扩展示例时，再进入对应
子包页面。精确声明以 [`api/public-api.txt`](../api/public-api.txt) 为准。

[文档首页](README.md) · [API 速查](api/quick-reference.md) · **API reference** · [Cookbook](cookbook.md)

> [!TIP]
> 按任务学习时从 Cookbook 开始；按符号查询时从本页开始；生成器级精确签名以 public API snapshot 为准。

## 按符号定位

| 你在找的符号 | 页面 |
| --- | --- |
| `MarkdownEngine`、`MarkdownEngineBuilder`、`ParseResult` | [Core 与 Engine API](api/core.md) |
| `MarkdownProfile`、`ParseLimits`、`CancellationToken` | [Core API](api/core.md) |
| `Document`、`NodeRef`、typed node view | [AST 与 Source API](api/ast-and-source.md) |
| `SourceSpan`、`SourceBuffer`、`Utf16Position` | [AST 与 Source API](api/ast-and-source.md) |
| `HtmlRenderer`、`HtmlOptions`、sink、source map | [Rendering API](api/rendering.md) |
| `MarkdownDialect`、syntax、renderer rule、SPI | [Extensions API](api/extensions.md) |
| `AstQuery`、rewrite、CST、snapshot、lint | [Editor API](api/editor.md) |
| artifact、document graph、testkit | [Artifact 与 Document API](api/artifacts-and-services.md) |

## 导入方式

新代码导入用途明确的最小子包：

```cangjie
import markdown.core.{MarkdownProfile}
import markdown.engine.{MarkdownEngine}
import markdown.render.{HtmlOptions, HtmlRenderer}
```

根包 `markdown` 不公开声明或转导。类型和实现位于各自领域包；按用途导入对应包。可选真实富内容准备使用 `markdown.node`，见[安装指南](node-rich-backend.md)。

### 最小依赖原则

| 只需要…… | 导入 |
| --- | --- |
| 解析或安全 HTML | `markdown.engine` |
| 自定义 HTML 输出 | `markdown.core` + `markdown.render` |
| AST 查询或 rewrite | `markdown.core` |
| snapshot、编辑和 lint | `markdown.engine` + `markdown.editor` |
| 自定义语法 | `markdown.core` + `markdown.extensions` + `markdown.engine` |

## 公开子包

| 子包 | 职责 |
| --- | --- |
| `markdown.core` | AST、source、diagnostic、limits、profile、query、rewrite、annotation |
| `markdown.engine` | parser、builder、events、追加会话、融合执行、能力与统计 |
| `markdown.render` | HTML、纯文本、Markdown、sink、source map、sanitizer |
| `markdown.extensions` | manifest、dialect、Syntax DSL、renderer DSL、SPI |
| `markdown.editor` | CST、snapshot、lint、编辑、范围 format |
| `markdown.artifact` | parse artifact 和 binary snapshot |
| `markdown.document` | document graph 和跨文档引用 |
| `markdown.testkit` | 第三方扩展 TCK |
| `markdown.native` | 可选原生 line scanner |

## 默认值和错误

默认 parser 是 CommonMark 0.31.2，limits 和 operation budget 使用 safe 配置，bytes
采用严格 UTF-8，HTML 使用安全策略。完整表见[API 速查](api/quick-reference.md#错误默认值)。

解析和渲染的结构化失败继承 `MarkdownException`。程序应根据 `code`、`phase` 和可选
`span` 分支，不要解析英文消息。`tryParse` 返回 `ParseOutcome.Success` 或 `Failure`；
失败结果不携带 Document。

当前 reference 对应 `0.9.2` breaking pre-GA preview。详见
[版本与兼容性](versioning-and-compatibility.md)。

---

[← 文档首页](README.md) · [API 速查](api/quick-reference.md) · [故障排查](troubleshooting.md)
