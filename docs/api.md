# API reference

先看[API 速查](api/quick-reference.md)。需要完整语义、错误和扩展示例时，再进入对应
子包页面。精确声明以 [`api/public-api-v0.9.txt`](../api/public-api-v0.9.txt) 为准。

[文档首页](README.md) · [API 速查](api/quick-reference.md) · **API reference** · [Cookbook](cookbook.md)

> [!TIP]
> 按任务学习时从 Cookbook 开始；按符号查询时从本页开始；生成器级精确签名以 public API snapshot 为准。

## 按符号定位

| 你在找的符号 | 页面 |
| --- | --- |
| `Markdown`、`MarkdownEngine`、`ParseResult` | [Core API](api/core.md) |
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
import markdown.core.{MarkdownEngine, MarkdownProfile}
import markdown.render.{HtmlOptions, HtmlRenderer}
```

根包 `markdown.*` 继续提供兼容门面，但容易让代码无意依赖 editor、artifact 或 testkit。

### 最小依赖原则

| 只需要…… | 导入 |
| --- | --- |
| 解析或便捷渲染 | `markdown.core` |
| 自定义 HTML 输出 | `markdown.core` + `markdown.render` |
| AST 查询和编辑 | `markdown.core` + `markdown.editor` |
| 自定义语法 | `markdown.core` + `markdown.extensions` |

## 公开子包

| 子包 | 职责 |
| --- | --- |
| `markdown.core` | parser、AST、source、diagnostic、limits、profile、events |
| `markdown.render` | HTML、纯文本、Markdown、sink、source map、sanitizer |
| `markdown.extensions` | manifest、dialect、Syntax DSL、renderer DSL、SPI |
| `markdown.editor` | walk/query/rewrite、CST、snapshot、lint、format |
| `markdown.artifact` | parse artifact 和 binary snapshot |
| `markdown.document` | document graph 和跨文档引用 |
| `markdown.testkit` | 第三方扩展 TCK |
| `markdown.native` | 可选原生 line scanner |

## 默认值和错误

默认 parser 是 CommonMark 0.31.2，limits 和 operation budget 使用 safe 配置，bytes
采用严格 UTF-8，HTML 使用安全策略。完整表见[API 速查](api/quick-reference.md#错误默认值)。

解析和渲染的结构化失败继承 `MarkdownException`。程序应根据 `code`、`phase` 和可选
`span` 分支，不要解析英文消息。`tryParse` 返回空文档和结构化错误，不返回部分 AST。

当前 reference 对应 `0.9.0` breaking pre-GA preview。详见
[版本与兼容性](versioning-and-compatibility.md)。

---

[← 文档首页](README.md) · [API 速查](api/quick-reference.md) · [故障排查](troubleshooting.md)
