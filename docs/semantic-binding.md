# 脚注、标题和文档绑定

本页描述 batch 与追加会话的最终绑定语义。标准 CommonMark/GFM profile
不默认启用这些扩展。定义列表见[独立规则](definition-lists.md)；富内容需
[显式准备](rich-content.md)。

## 启用和查询

```cangjie
import markdown.core.*
import markdown.engine.MarkdownEngine
import markdown.extensions.{MarkdownDialect, OfficialExtensions}

let dialect = OfficialExtensions.headingIds(
    OfficialExtensions.footnotes(MarkdownDialect.define("article", "2"))
).build()
let engine = MarkdownEngine.builder()
    .dialect(dialect)
    .bindingOptions(BindingOptions(idScope: "chapter-a"))
    .build()
let result = engine.parse("# Introduction\n\nText[^n]\n\n[^n]: Note")
let bindings = result.document.bindings
let toc = bindings.tableOfContents(minimumLevel: 1, maximumLevel: 3)
```

`BindingOptions` 不含可变的跨请求计数器。拼装多个独立文档时，宿主为每个片段指定唯一
`idScope`；允许最多 128 个 ASCII 字母、数字、`_` 或 `-`。空 scope 不增加前缀。

`DocumentBindings` 提供只读脚注和标题绑定。`headingForNode`、`headingForId` 和
`HeadingNodeView.binding` 返回同一标题决策；`fragmentTarget` 使用最终 ID 查询实际输出的
标题、脚注或回链节点。传入其它文档的 NodeId 不会匹配。

已绑定文档的 `links` 和 `linkForNode` 提供作者 destination、输出 destination 和本地
目标。fragment 按 UTF-8 percent 解码后查找，优先解释为当前 scope 内的作者 ID；查不到
时再接受完整的最终 ID。HTML 和带 destination 的 Text 使用绑定后的链接，canonical
Markdown 保留作者 destination，重新解析时再绑定。lint 的
`MDL1005_MISSING_FRAGMENT` 使用同一索引，不独立生成标题 slug。

## 脚注 2.0

引用使用 `[^label]`，定义使用 `[^label]: body`。label 在反斜杠和 entity 解码后，按普通
引用 label 的大小写折叠及空白合并规则匹配。label 不跨行。payload 同时保留原始 label、
规范化 label 和不含分隔符的精确来源范围。

定义可后置；同名定义采用源码中的第一个。后续重复定义产生
`MD4002_DUPLICATE_FOOTNOTE`，诊断指向重复 label，并关联首个定义。

编号先按正文首次有效引用分配，再按已引用定义的顺序遍历其正文，发现可达的嵌套脚注。
循环不会重复展开定义。重复引用共用编号，拥有独立引用 ID；脚注区包含所有可达回链。
HTML 在正文后输出一个有序脚注区，定义正文继续使用普通 Markdown 节点渲染。

定义后续非空行至少缩进四个容器列；空行仅在后面还有缩进正文时归入定义。正文支持多段、
列表、引用、围栏、强调和链接。普通引用定义也使用同一块解析规则收集；代码里的伪定义
不会作为链接目标。脚注定义的 `maximumBlockBytes` 从首行正文起计入原始字节，包括后续
缩进和换行，在复制正文前检查。

未定义引用默认保留完整可见语法并产生 `MD4001_UNDEFINED_FOOTNOTE`；无效的空 label
产生 `MD4003_INVALID_FOOTNOTE`。`strictUndefinedFootnotes: true` 将其变为
`InvalidReference` 致命错误。未引用定义保留在 AST、lossless CST 和 canonical Markdown
中，不进入默认 HTML/Text 脚注区，其标题也不进入 TOC。

HTML、Text 和 canonical Markdown 消费同一绑定。Markdown 可以规范化 label 拼写；原始
拼写始终可通过 payload 和 source 查询。SourceMap 将派生脚注数字映射到原引用范围，
不声明数字具有逐字符源码对应。

## 标题 ID 2.0

只识别标题末尾的 `{#id}`，且它前面必须是标题起点或空格/tab。ID 非空，ASCII 部分只允许
字母、数字、`_`、`-`、`.` 和 `:`；非 ASCII 字符保留原样。非标题、代码或非末尾的同类
文本保留为普通内容。元数据是标题的 typed payload child，不产生独立的 HTML `span`。

标题绑定提供层级、显示文本、最终 ID、显式 ID 原始拼写、来源范围和 scope。
HTML 将最终 ID 写在 `h1` 至 `h6` 上。Text 省略 ID 语法；Markdown 保留作者显式 ID。

绑定先预留所有可渲染标题中不同的显式 ID，再为重复显式 ID 和自动 slug 分配唯一后缀：

1. 自动 slug 只将 ASCII 大写转为小写，空白合并为 `-`。
2. 去掉 ASCII 标点，保留 `_`、`-` 和非 ASCII 字符。
3. 去掉首尾 `-`，空结果使用 `section`。
4. 冲突依次使用 `-2`、`-3` 等后缀，避开已预留的完整显式 ID。

重复显式 ID 产生 `MD4010_DUPLICATE_HEADING_ID` 并关联首个 ID。标题、脚注目标和回链共享
分配器，因此作者的 `{#fn-1}` 不会与自动脚注 ID 冲突。scope 统一加在最终 ID 前。

`tableOfContents` 返回结构化条目，不生成网站侧栏。可以指定 1 至 6 内的层级范围；跳级
标题归属于此前最近的较低层级条目。

## 来源、资源和执行边界

`SourceBuffer.text(node/document)` 验证实际来源归属；不能将数值相同的范围用于另一个
文档的来源。需要显式按数字取范围时使用 `slice(span)`。`ParseResult` 构造器也验证
Document 和 SourceBuffer 属于同一结果。

绑定检查已知 payload 的节点种类、来源范围和原始文本；标题元数据必须是标题末尾的
无 child 节点。`maximumReferences` 累计限制普通引用定义、脚注定义/引用、标题锚点和
脚注目标/引用锚点/回链的工作单元。绑定扫描、标题文本和 slug 处理计入操作预算，并检查
取消。HTML 继续执行输出上限和 renderer 预算。

依赖完整文档绑定的方言目前拒绝 source Event 和 RawBlock session 路径。
`PreferFused` 可以回退 FullAst；`RequireFused` 明确失败。`newBufferedInputSession` 仍只在
finish 时解析；这不构成新的追加式语义入口。

payload 与索引不包含第三方 HTML。parse artifact 和 binary snapshot 的配置身份包含
scope 与严格策略；不同 scope 的缓存不能互用。snapshot 恢复重新建立相同语义决策，
不恢复旧运行中的 NodeRef 身份。
