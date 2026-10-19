# 显式准备公式、图表与代码高亮

解析保留原文和结构化语义。`RichContentPreparer.prepare` 是解析之后的独立操作；
只有宿主开启相应能力并提供后端时，它才请求派生展示。默认 parser、HTML、Text 和
Markdown 不执行外部程序，也不下载或安装引擎。

共享准备层和固定版本的 [Linux Node 可选适配器](node-rich-backend.md)均已实现。
适配器提供真实 KaTeX MathML、Shiki 颜色 token 和 Mermaid flowchart PNG；基础默认路径
继续独立可用。安装、许可、离线输入、实际能力和进程边界见该指南。

## 选择能力并处理缺失

从 `markdown.render` 导入准备类型，从 `markdown.extensions` 导入公式扩展。
下面的调用没有后端，因此结果为 `Missing`，HTML 继续显示完整 TeX：

```cangjie
let prepared = RichContentPreparer.prepare(
    result,
    options: RichContentOptions(math: true)
)
let html = engine.htmlRenderer(prepared: Some(prepared)).render(result.document)
```

`result` 必须是完整成功结果。准备器识别 Math 2.0 节点、语言为 `mermaid` 的普通
代码块和其他有语言标记的代码块。代码组内的 fence 始终作为代码高亮，不能把其中的
Mermaid 示例自动变成图表。没有语言标记的代码块保持普通输出。

`RichContentOptions` 的 `math`、`diagrams`、`highlight` 默认均为 false。
每项注解的 `outcome` 为 `Ready(product)` 或 `Unavailable(reason)`：

| 原因 | 含义 |
| --- | --- |
| `Disabled` | 宿主没有开启该项能力 |
| `Missing` | 没有后端或所需运行时未安装 |
| `Unsupported` | 当前后端不支持该输入、语言或能力 |
| `TimedOut` | 后端超过约定时间 |
| `Failed` | 后端失败、协议不匹配或结构化产物无效 |
| `Limited` | 后端或派生产物超过准备上限 |

默认失败不改变 AST，renderer 使用原来的公式或代码输出。`strict: true` 将已开启
能力的不可用状态转为 `RenderFailure`。取消和操作预算耗尽始终抛出原有
`Cancelled` / `BudgetExceeded`；收集请求的结构/输入总量超限也会终止本次操作。

## 注入后端并限制工作量

`RichContentBackend` 只有按种类返回 `identity` 和批量 `prepare` 两个操作。
请求包含种类、源表达式、语言和公式 display 标志，没有命令、文件路径、Document
或 NodeRef。宿主端口是可信、协作式代码，必须遵守传入的取消、预算和整体时间上限；
此接口本身不是操作系统沙箱。

`RichContentLimits` 默认限制 128 个请求、每个 1 MiB/累计 4 MiB 输入、每个
8 MiB/累计 32 MiB 产物数据、65536 个 MathML 节点、128 层、131072 个 token、
4194304 个 PNG 像素和 30 秒后端时间。它们不表示操作系统堆或 RSS 上限。
HTML 输出继续遵守 renderer 的累计字节、工作量和取消限制。

准备器重新校验所有 Ready，包括缓存命中：

- MathML 只接受固定的元素、属性和值域；没有 script、style、事件或任意 URI。
  文本仍按 HTML 转义，第三方 HTML/SVG 没有 `TrustedHtml` 通道。
- 颜色 token 使用有序、不重叠、位于 UTF-8 scalar 边界的字节范围、`#RRGGBB`
  和 0..7 字体位。未覆盖的间隙和换行保留原文。代码组复制继续使用独立的原始
  `copyText`，不从带颜色 HTML 反推字符。
- PNG 接受有界的非交错 8-bit RGB/RGBA，验证签名、IHDR、像素数、critical chunk
  顺序、CRC 和完整结束；适配器须移除 ancillary metadata。该检查不替代 PNG 解码器。
  renderer 只构造固定的 `data:image/png;base64,`，按块编码，不接收任意图片 URI。

PNG 展示还需要宿主显式设置 `ImageUriPolicy.allowDataImages` 并允许 `image/png`。
安全默认值关闭 data image，此时即使图表准备成功，也输出完整 Mermaid 源代码。

## 绑定文档版本和来源

`RichContentPreparation` 只属于一个不可变 `documentRevision`。`entry(node)`、同步
renderer 和输出 session 都拒绝旧或外来的文档版本；不会因为文本或 NodeId 相同而复用
注解。准备结果不写回源 AST、Text/Markdown、CST 或持久化 snapshot。

`RichPreparedEntry.sourceParts` 保留表达式的原始 UTF-8 来源片段。HTML source map
将派生 MathML/PNG 标为 `generated: true`，并记录原节点的粗粒度来源；它不声称公式字形
或图表像素与源码逐字符对应。普通高亮文字仍来自原代码。同步和暂停/恢复输出共用
同一产物和规则，不预先构造整份富内容 HTML。

## 拥有并清理缓存

显式传入 `RichContentCache` 才会跨准备操作缓存。key 绑定协议、种类、传入引擎的完整表达式/代码、
语言、display 标志及后端 identity。identity 必须包含引擎版本及实际影响该产物的配置；
主题只在实际影响产物时参与，例如高亮颜色，而非与主题无关的 MathML。

缓存只存通过验证的 Ready，不保存请求对象、Document、NodeRef 或 SourceBuffer。暂时失败不会变成
成功缓存。默认最多 128 项/8 MiB 计费产物数据，容量满时整体清空；`productBytes`
不表示对象开销或进程 RSS。更严格的当前 limits 会重新拒绝过大的缓存产物。
缓存与 `OperationBudget` 一样按顺序使用；宿主负责并发隔离和调用 `clear()`。
