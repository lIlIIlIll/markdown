# 扩展模型

`markdown.extensions` 用不可变方言描述 Markdown 语义。扩展可以声明受限语法、
renderer lowering、AST transform、只读分析和 lint provider；engine 在第一次解析前完成依赖、冲突、
资源边界和 renderer coverage 校验。

如果只需要 CommonMark 或 GFM，请直接使用内置 profile。只有需要稳定复用自定义语法时，
才创建方言。

## 扩展生命周期

```text
ExtensionManifest + Syntax + Transform + Analysis + RendererRule
                 ↓ MarkdownDialectBuilder.build()
          MarkdownDialect 声明
                 ↓ MarkdownEngine.builder().dialect(...).build()
        CompiledMarkdownDialect
                 ↓ parse
          完整 AST → AST transform → 语义绑定 → 只读分析 → ParseResult
                                                            ↓ render / format
```

`CompiledMarkdownDialect` 是不可变且可并发复用的。运行时不会动态更改 rule 顺序。
`disable(extensionId)` 在编译前移除该扩展的 manifest、syntax、renderer、SPI、transform、
analysis 和 lint provider。

用 ExtensionAstTransform 修改语义树，返回值会验证 source、profile、dialect、节点上限
及图结构。然后绑定器统一确定引用、脚注编号和标题目标。ExtensionDocumentAnalysis
读取这些最终决策并返回诊断，不能通过返回值替换文档。诊断的主范围、关联范围和 fix
范围都必须在原始输入内，并落在 UTF-8 或非法字节替换后的解码边界；不合格的结果使
本次解析失败。

两种 callback 都接收 document、source、引擎实际 limits、累计 budget 和 cancellation。
调用 TreeRewriter 时传入同一 limits/budget/cancellation。阶段内按 priority 从高到低
执行，再按 extension ID 与 stage ID 排序。分析后的 HTML、Markdown 和查询使用同一
Document，不重新执行 transform 或 analysis。

batch 与 append 共用这条完整管线。append 在 finish 时执行整文阶段；source events
和独立 RawBlockEventSession 在调用 callback 前拒绝需要完整文档的配置。RequireFused
失败，PreferFused 回退完整 AST。含整文阶段的编辑在无法证明局部结果有效时完整回退。
可运行示例见 [cookbook](../examples/cookbook/src/main.cj) 的 bound-analysis 段。

## 官方扩展能力矩阵

六项 P1 扩展都默认关闭；可以单独启用，也可以用 OfficialExtensions.p1Dialect 组合。
下表是当前实现边界，不能把 literal 输出或目录中的版本号理解为真实后端已接入。

| 扩展 | 实现版本 | 状态 | 当前边界 |
| --- | --- | --- | --- |
| Footnotes | 2.0.0 | 结构化语义 | 引用/定义、整文编号/锚点/回链、各输出 |
| Definition Lists | 2.0.0 | 结构化语义 | List/Entry/Term/Definition、多段普通块正文、各输出 |
| Heading IDs | 2.0.0 | 结构化语义 | 标题尾部显式 ID、自动 ID、TOC 和 fragment 共享绑定 |
| Front Matter | 1.0.0 | 仅 literal | 绝对文档起点的可选 block；保留来源和 lossless CST，不解释或执行配置 |
| Math | 1.0.0 | 仅 literal | 行内/块原文、源范围和可读输出，尚未接入公式排版 |
| Smart Punctuation | 2.0.0 | 文本转换 | 确定性的 Text transform，无引号或语言排版引擎；见[规则](#智能标点) |

CommonMark 0.31.2 和 GFM modern 可组合这六项扩展；GFM 0.29 未列在其 supportedProfiles
中，方言编译明确拒绝。官方矩阵测试逐项检查受支持 profile 的精确输出、能力版本和
关闭行为，并检查 GFM 0.29 及重复注册被拒绝。四项 GFM
基础能力仅随对应 GFM profile 默认开启；github-alerts、wikilinks 仍是未实现的目录项。
真实富内容后端、编辑和性能的最终验收仍在 issue #10 中推进。

## 智能标点

Smart Punctuation 2.0 在每个语义 Text 节点内从左到右进行最长匹配：`...` → `…`，
`---` → `—`，`--` → `–`。例如 `....` → `….`，`-----` → `—–`。
匹配不会跨越 emphasis、link、code 等节点边界，也不把两个点补成省略号。
引号及已有 Unicode 标点保持不变；没有根据语言猜测开闭引号的规则。

parser 先处理实体和反斜杠转义，transform 再处理语义文本。因此普通 Text 中的
`&#45;&#45;` 也会成为 `–`。手写链接的 label 参与转换；destination、title、自动链接
的显示 URI、code span/block、raw HTML token 和 literal payload 保持原义。
两个 HTML inline token 之间的普通 Markdown Text 仍按文本规则处理。

transform 保留原始 raw 文本和 SourceSpan。SourceBuffer 与 lossless CST 可恢复作者
输入；canonical Markdown 使用转换后的语义文本，不承诺恢复原始标点拼写。
重复处理已经转换的文档不会再次替换内容；没有内容变化时保留 Document revision 和
NodeId。扫描消耗累计操作预算，并在长文本中检查取消。

该处理器需要完整文档。追加会话在 finish 后运行它；source events 明确拒绝，
RequireFused 明确失败，PreferFused 回退完整 AST。它不会在 feed 中把临时文本当作
最终语义反复处理。

## 最小块扩展

```cangjie
import markdown.core.*
import markdown.extensions.*

let manifest = ExtensionManifest(
    "docs",
    "1.0.0",
    "example-1",
    capabilities: ExtensionCapabilities(
        safeHtml: true,
        plainText: true,
        markdown: true
    )
)

let dialect = MarkdownDialect
    .define("docs-v1", "1.0.0")
    .enable(manifest)
    .block(BlockSyntax.define("docs", "container").opener(":::").closer(":::"))
    .renderer(
        RendererRule(
            "docs", "note", "aside",
            classToken: "note",
            markdownOpener: ":::note\n",
            markdownCloser: "\n:::"
        )
    )
    .build()

let engine = MarkdownEngine.builder().dialect(dialect).build()
let html = engine.htmlRenderer().render(engine.parse(":::note\n**important**\n:::").document)
```

## 选择 DSL 还是 SPI

| 需求 | 使用 |
| --- | --- |
| 固定 delimiter、token 或块 opener | `InlineSyntax` / `BlockSyntax` |
| 静态 HTML、Markdown、纯文本 lowering | `RendererRule` |
| DSL 无法表达、但 lookahead 有界的行内语法 | `InlineParserSpi` |
| 绑定前修改完整 AST | `ExtensionAstTransform` |
| 读取绑定结果并产生整文诊断 | `ExtensionDocumentAnalysis` |
| snapshot 级诊断 | `ExtensionLintProvider` |

优先使用 DSL。它的边界、优先级和资源成本可以在 dialect 编译时验证。SPI callback
运行在宿主进程内，必须自行保证确定性并遵守声明的 lookahead。

## 优先级、错误和 fallback

方言编译器按 phase、priority、registration order 和 rule identity 生成确定性执行计划。
重复 ID、opener 冲突、依赖缺失、版本不满足、依赖环和显式 conflict 都会在 engine 构建或显式编译
期间失败，而不是等到解析时随机选择。

未注册的语法保持普通文本。已注册但未闭合的扩展产生
`MD3002_UNCLOSED_EXTENSION`；非法参数产生
`MD3003_INVALID_EXTENSION_PARAMETER`。

`ExtensionCapabilities` 分别声明 parse、HTML、纯文本、Markdown、CST、format、
serialize、incremental、lint、analysis 和 transform。声明能力后必须提供实现，或在
manifest 中选择明确的 missing-renderer policy。默认 policy 是 `Error`。

脚注、标题 ID 和定义列表的 typed 节点由绑定结果决定输出。为这些语义注册通用
RendererRule 会明确失败；固定语法不支持的 builder 选项也会在编译时被拒绝。

## 安全边界

code extension 与宿主进程权限相同，库不声称对 callback 做进程内沙箱。
`IsolatedPluginRunner` 是 fail-closed IPC 契约；真正的 OS process、文件系统和网络隔离由
宿主提供的 `PluginIsolationTransport` 实现。

transport 的 `invoke` 实现必须把响应身份、output 和 diagnostics 增量写入
`IsolatedPluginResponseSink`。身份字段分别使用 `writeProtocolVersion`、`writeExtensionId` 和
`writeImplementationVersion`。输出使用 `writeOutput`。每条 diagnostic 使用
`beginDiagnostic`、分块 `writeDiagnosticMessage` 和 `finishDiagnostic`。`invoke` 返回
`Unit`。不要先把不可信字符串解码到宿主集合中。这样做会绕过
`PluginIsolationPolicy` 的 response 预算。

外部 JSON/YAML descriptor 只能携带数据，不能携带或执行 callback。Front Matter 和 Math
官方扩展也只保留 literal，不解释配置或执行数学引擎。

## 验证

```cangjie
import markdown.testkit.*

let report = MarkdownExtensionTestKit.verify(engine, sample)
```

TCK 覆盖 parse/render、SourceSpan、确定性、chunk invariance 和 AST 不变量。扩展包仍需增加
自身的未闭合、嵌套、冲突、limits、cancellation 和 renderer fallback 用例。

## 相关文档

- [Extensions API](api/extensions.md)
- [Dialect DSL](dialect-dsl.md)
- [Syntax DSL](syntax-dsl.md)
- [Renderer DSL](renderer-dsl.md)
- [SPI 与 schema 版本](spi-and-schema-versions.md)
- [Extension TCK](extension-tck.md)
