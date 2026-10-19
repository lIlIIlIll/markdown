# 结构化定义列表 2.0

定义列表是本库的可选扩展，不是 CommonMark/GFM 标准要求。默认 profile 关闭它。
2.0 使用完整分组结构，替换旧版逐行生成 dd 的行为。

```cangjie
import markdown.core.*
import markdown.extensions.*
import markdown.render.*

let dialect = OfficialExtensions.definitionLists(
    MarkdownDialect.define("glossary", "2")
).build()
let engine = MarkdownEngine.builder().dialect(dialect).build()
let result = engine.parse("Term\n: First meaning\n: Second meaning\n")
println(engine.htmlRenderer().render(result.document))
```

HTML 为 dl 包含 dt/dd；每个定义的正文继续使用普通块节点，例如 p、blockquote、ul 和
pre/code。renderer 消费 AST 归属，不从原文重新切分条目。

## 固定语法

```markdown
Term one
Term two
: First definition.
: Second definition.

Next term
: First paragraph.

  Second paragraph.

  - A nested list item.
```

一个 entry 包含一个或多个 term，再包含一个或多个 definition。规则如下：

- 连续的普通段落行分别构成 term；支持普通行内语法。term 的第一行不能是其它块的
  opener，setext underline 也不能成为 term。
- 定义标记是行首最多三个空格后的冒号，后面必须是 ASCII space、tab 或行尾。
  冒号后的一个 whitespace byte 属于标记间隔；更多缩进保留给普通正文解析。允许空定义。
- 首个定义可紧接 term，或隔一个空行。多个定义、多个 entry 之间也可紧接或隔一个空行。
  两个及以上的分隔空行结束列表。
- 定义续行需要至少两个容器列的缩进。移除两个前导空格；若前缀中遇到 tab，则移除完整的
  tab 前缀直到达到该最小缩进，不制造额外 source bytes。剩余文本按普通 Markdown 解析。
  一个前导 tab 或一个空格加 tab 都可以开始续行。
- 空行后仍有缩进续行时，空行属于定义正文；可以形成多个段落。没有缩进的后续内容，只有
  在其 term 行后找到定义标记时才归入下一个 entry，否则结束列表。
- 不提供未缩进正文的 lazy continuation。孤立冒号行、`:word`、代码中的伪语法保持普通
  Markdown。setext 标题、引用、列表、表格、代码和 HTML 块遵循原有块优先级。

作者需要把引言和术语分开时，应使用空行。例如紧邻的 `Introduction`、`Term`、
`: definition` 会构成共享定义的两个 term。

## AST 和来源

每个节点是带 DefinitionListPayload 的 CustomBlock，role 为：

| role | children |
| --- | --- |
| `List` | 一个或多个 Entry |
| `Entry` | 一个或多个 Term，随后一个或多个 Definition |
| `Term` | 行内节点 |
| `Definition` | 零个或多个普通 Markdown blocks |

对应 local kind 分别为 definition-list、definition-entry、definition-term 和
definition-body。Entry 是 AST 分组，不增加 HTML 包装元素。payload schema 为
`markdown.definition-list/1`；扩展语义版本为 2.0.0，implementation 为 builtin-2。

节点保留原始 SourceSpan。Definition 的 markerSpan 精确指向原始冒号；其它 role 没有
markerSpan。完整文档处理会验证父子归属、term/definition 顺序、节点类别及标记来源。
错误的 typed payload 明确失败，不会被当作普通标签映射输出。

```cangjie
let list = result.document.root().children()[0]
let entry = list.children()[0]
let term = entry.children()[0]
println(result.source.text(term))
```

lossless CST 和 preserving formatter 保留原始输入。canonical Markdown 可以使用实体转义
空格来保护普通文本，并把续行规范化为两个空格；不要把 canonical 输出当作原始拼写。
多段引用、列表项和 task list 中的定义列表仍保留容器归属。

## 组合、追加和输出

定义正文中的链接定义、脚注、标题和 ID 使用相同的 parser 与文档绑定。脚注内也可以
包含定义列表。HTML、Text、canonical Markdown、SourceMap 和当前 snapshot 消费同一
结构。可恢复 HTML 输出复用这些规则，包括暂停后重试。

追加会话会保留可能成为 term 的尾部段落。例如收到 `Term\n\n` 后仍需等待，后续
`: definition` 可以使其成为列表。相邻条目也不能提前被拆成两个列表。结构待定、更新
消费和终态见[追加输入](append-input.md)。长列表中的内层 literal 闭合不会强制反复
重扫整个列表；有累计工作量 scaling 回归。

此语法需要完整 AST 校验。source Event API 和 RawBlockEventSession 明确拒绝启用了该
语法的方言；PreferFused 回退完整 AST，RequireFused 明确失败。使用追加 AST 会话处理
分块输入。

## 限制和验证边界

`BlockSyntax.define(...).definitionList()` 是代码 DSL 专用声明；不能改成 Literal、
提供自定义 payload emitter、添加参数、关闭嵌套或限制为文档起点；编译器明确拒绝这些
配置。external descriptor schema 1 未新增对应语法。
关闭扩展后按基础 profile 解析。

maximumBlockBytes 默认 1 MiB，限制整个原始列表范围，包括 term、标记、缩进和换行；
在复制正文前检查。maximumCaptureLength 默认 4096，限制解码后的每个 term 行的文本
字节数。输入、行长、嵌套、AST 节点和操作预算仍然生效，追加路径的上限跨 feed 累计。
成功匹配还按整个列表的源字节数计入声明的 SyntaxResourceCost。

DefinitionListTests 覆盖精确分组/输出、普通块正文、Unicode/CRLF、歧义、关闭、后置
标记、脚注/标题/链接组合、SourceMap、snapshot、可恢复输出、错误 payload、限制和取消。
性能工作计数不等同于 heap allocation 或 RSS；最终性能与发布验证仍属于 issue #10 的
剩余收口。
