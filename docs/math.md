# Math 2.0：公式语义与原文

`OfficialExtensions.math(builder)` 显式开启公式扩展。基础 CommonMark/GFM profile
默认关闭它；Front Matter 不会替调用方开启扩展或指定程序。默认 HTML 只显示转义后的
TeX，不调用外部引擎。真实公式排版后端仍在 issue #10 中实现。

```cangjie
let dialect = OfficialExtensions.math(MarkdownDialect.define("formula", "2")).build()
let engine = MarkdownEngine.builder().dialect(dialect).build()
let result = engine.parse("Value $x + y$.")
let html = engine.htmlRenderer().render(result.document)
```

## 固定语法

行内 `$…$` 使用 CommonMark flanking 边界，正文不能换行，反斜杠保护 delimiter。
正文不解析 Markdown、实体、命令或宏；例如 `\frac{a}{b}` 和 `&amp;` 都保留为 TeX。
空格及匹配边界由该 DSL 的固定规则决定，不宣称与某个 TeX Markdown 方言完全相同。

块公式的 opener 是独占一行的 `$$`，允许零到三列前导空格。closer 是去除行首尾
ASCII 空白后等于 `$$` 的行，不嵌套。opener 后的同一行不能写表达式或参数。
正文可以为空或含空行；容器前缀按普通 Markdown quote/list 规则移除，换行统一为 LF，
最后一行正文的换行不属于语义表达式。四列缩进的 opener 保持代码语义。
未闭合公式保持基础解析结果和原文，不补写 closer。代码中的 `$` 不识别为公式。

## 读取来源

`MathPayload` 不保存排版 HTML、主题、进程路径或缓存结果：

| 字段 | 含义 |
| --- | --- |
| `display` | 块公式为 true，行内公式为 false |
| `expression` | 移除容器前缀并统一换行后的 TeX |
| `expressionSource` | 按原文顺序排列的 `MathSourcePart`；通过 `result.source.slice(part.span)` 读取 |
| `openerSpan` / `closerSpan` | 原始 `$` 或 `$$` 的精确范围 |

多行 quote 中的片段不必相邻。`part.span` 保留实际来源；中间行包含原始 CRLF/LF，
最后一行不包含换行。容器部分消费 tab 时，`expandedPrefixBytes` 个原始行首空白在
表达式中变为 `expandedPrefixSpaces` 个空格；其余字节只规范化换行。这个关系保存实际
原始 tab，避免把合成空格伪装成源字符。不能把片段间的 quote/list 标记拼入公式。非法 UTF-8 按调用方选择的策略处理，范围仍以
原始输入字节计。绑定器验证类别、children、来源顺序、delimiter、标量边界及表达式，
不接受伪造来源的 typed payload。

## 输出与资源

默认 HTML 使用 `span.math-inline` 或 `div.math-block`，转义表达式。Text 输出 TeX；
canonical Markdown 输出 `$…$` 或独占行的 `$$`，lossless CST 保留原始字节表示。
SourceMap 关联到公式节点的完整源范围，不伪造表达式字符与生成排版字符的一一对应。
标题文字、图片替代文本和可恢复输出使用相同 TeX 文本。

batch 与 append 的最终结果共享绑定和 payload；公开 raw/source events 与 RequireFused
路径明确拒绝这个需要完整 AST 验证的扩展，PreferFused 使用完整 AST。解析、来源验证和
输出共享累计预算与取消。块公式同时受 block bytes、规则及全局 capture bytes、literal
bytes 限制；capture 对原始正文行字节计数。`displayMath()` 拒绝被忽略的嵌套、Markdown
正文、自定义 emitter、参数、动态 kind 和 document-start-only 设置。结构化公式不接受
通用 RendererRule 覆盖。第三方派生输出将通过独立准备边界提供。

可运行 consumer 见 [cookbook](../examples/cookbook/src/main.cj) 的 `math-source` 段：

```sh
cd examples/cookbook
cjpm build
cjpm run --skip-build
```

该段输出 `expression=x + y, source=x + y` 和默认可读 HTML。
