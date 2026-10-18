# Extensions API

`markdown.extensions` 定义扩展身份、依赖、语法边界、renderer lowering 和测试契约。
方言在创建 engine 时编译成不可变 `CompiledMarkdownDialect`。

## 最小块扩展

```cangjie
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
    .block(
        BlockSyntax
            .define("docs", "container")
            .opener(":::")
            .closer(":::")
    )
    .renderer(
        RendererRule(
            "docs",
            "note",
            "aside",
            classToken: "note",
            markdownOpener: ":::note\n",
            markdownCloser: "\n:::"
        )
    )
    .build()

let engine = MarkdownEngine.builder().dialect(dialect).build()
```

扩展节点包含 extension ID、semantic version、local kind、typed payload、children、
SourceSpan 和 origin。

## `ExtensionManifest`

必需参数：

| 参数 | 含义 |
| --- | --- |
| `extensionId` | 稳定扩展 ID |
| `semanticVersion` | 完整 SemVer |
| `implementationVersion` | 构建或实现身份；不参与 SemVer 排序 |

可选参数及默认值：

| 参数 | 默认值 |
| --- | --- |
| `requiredSpiVersion` | `"3"` |
| `supportedProfiles` | CommonMark 0.31.2、GFM modern v1 |
| `dependencies` | `[]` |
| `dependencyConstraints` | `[]` |
| `conflicts` | `[]` |
| `capabilities` | 只有 parse 为 true |
| `ruleBudget` | `100000` |
| `trustLevel` | `"host-code"` |
| `missingRendererPolicy` | `Error` |
| `shareable` | `true` |

`ExtensionCapabilities` 分别声明 parse、spec HTML、safe HTML、plain text、
Markdown、CST、format、serialize、incremental、lint、analysis 和 transform。
声明能力后必须提供对应实现或明确 fallback。

## `MarkdownDialectBuilder`

```cangjie
MarkdownDialect.define(id, version)
    .base(profile)
    .parserOptions(options)
    .limits(limits)
    .enable(manifest)
    .inline(inlineRule)
    .block(blockRule)
    .renderer(rendererRule)
    .parserSpi(spi)
    .astTransform(transform)
    .documentAnalysis(analysis)
    .lint(provider)
    .disable(extensionId)
    .build()
```

`disable` 会在编译前移除该扩展的 manifest、syntax、renderer、SPI、transform、analysis
和 lint provider。

`DialectCompiler.compile` 验证：

- ID、SemVer 和 SPI version
- profile support
- dependency、minimum version、conflict 和 dependency cycle
- rule ID、opener、delimiter、lookahead、capture 和 block size
- priority、registration order 和 conflict group
- renderer coverage、tag、class、attribute 和 URI kind
- capability 声明
- deterministic SPI 和 processor

失败会抛出 `ExtensionFailureException` 或对应的结构化
`MarkdownException`。

## `InlineSyntax`

```cangjie
let mark = InlineSyntax
    .define("docs", "mark")
    .delimiter("==")
    .content(true)
    .nesting(false)
    .maximumDelimiterLength(2)
    .maximumLookahead(4096)
    .priority(100)
    .conflictGroup("emphasis-like")
```

Builder 方法：

| 方法 | 作用 |
| --- | --- |
| `delimiter(opener, closer)` | 成对 delimiter；closer 默认等于 opener |
| `token(value)` | 单 token 语法 |
| `metadataSuffix(opener, closer)` | 后缀 metadata |
| `escaping(policy)` | CommonMark 或 literal backslash 规则 |
| `flanking(rule)` | Any、CommonMark 或 word-boundary |
| `content(parseChildren)` | 是否解析 Markdown children |
| `emitContent(enabled)` | 是否保留可见内容 |
| `nesting(allow)` | 是否允许同规则嵌套 |
| `maximumDelimiterLength(value)` | delimiter 上限 |
| `maximumLookahead(value)` | lookahead 上限 |
| `priority(value)` | rule priority |
| `conflictGroup(value)` | 冲突分组 |
| `resourceCost(cost)` | 静态资源成本 |
| `emit(emitter)` | typed payload emitter |

## `BlockSyntax`

```cangjie
let note = BlockSyntax
    .define("docs", "container")
    .opener(":::")
    .closer(":::")
    .content(BlockContentMode.Markdown)
    .parameter("title", SyntaxParameterType.StringValue)
    .maximumBlockBytes(1048576)
    .maximumCaptureLength(4096)
    .nesting(true)
```

`linePrefix(prefix)` 定义单行语法。`documentStartOnly()` 限制 rule 只在文档开头
匹配。`kindFromFirstWord(false)` 让 local kind 固定为 rule ID。

对 paired block，`maximumBlockBytes` 在普通 parse 与 RawBlock streaming feed 中均实时
累计原始正文 bytes；嵌套边界和 CRLF 与最终 batch 解析使用同一规则。

参数类型：

- `StringValue`
- `IntegerValue`
- `BooleanValue`
- `IdentifierValue`

unknown、duplicate、missing、unclosed 或类型不匹配的参数产生
`MD3003_INVALID_EXTENSION_PARAMETER`。注册后未闭合的 block 产生
`MD3002_UNCLOSED_EXTENSION`。

## `SyntaxPayload`

Custom node 的 payload 保留：

- raw 参数拼写
- typed parameter values
- literal body
- nested child summary
- extension 和 rule identity
- 源码范围

renderer、formatter 或宿主代码可读取 payload，不需要重新解析原始 opener。

## `RendererRule`

```cangjie
let rule = RendererRule(
    "docs",
    "note",
    "aside",
    classToken: "note",
    markdownOpener: ":::note\n",
    markdownCloser: "\n:::",
    textPrefix: "Note: "
)
```

参数：

| 参数 | 默认值 |
| --- | --- |
| `classToken` | 空 |
| `markdownOpener`、`markdownCloser` | 空 |
| `textPrefix`、`textSuffix` | 空 |
| `attributes` | `[]` |
| `renderPayloadLiteral` | `false` |
| `markdownBlockLowering` | `Container` |

structured attribute 通过 `RendererAttributeSpec` 声明 Text、LinkUri 或 ImageUri，
值来自 fixed value、payload parameter 或 payload literal。URI attribute 会经过与内置
link/image 相同的 policy。

## Missing renderer policy

| Policy | 行为 |
| --- | --- |
| `Error` | 缺失实现时失败 |
| `RenderChildren` | 只输出 children |
| `RenderLiteral` | 输出 payload literal |
| `Drop` | 明确丢弃 |
| `CustomFallback` | 调用显式 fallback |

自定义 HTML fallback 只能返回 `TrustedHtml`。普通 String 会被转义。

## `InlineParserSpi`

DSL 无法表达的有限行内语法可实现 SPI v3。实现必须声明：

- `extensionId`
- `ruleId`
- `triggerBytes`
- `maximumLookahead`
- `priority`
- `deterministic`
- parse callback

`triggerBytes` 是所有可能 opener 的首 byte，必须非空且无重复。parser 只在这些位置
调用 SPI。runtime 会验证 consumed range、node identity 和 SourceSpan。

## 完整文档阶段

用 `ExtensionAstTransform` 在绑定前返回修改后的 Document；用
`ExtensionDocumentAnalysis` 在绑定后返回 `Array<Diagnostic>`。两种接口都声明
extensionId、transformId 或 analysisId、version、priority、deterministic。
当前编译器只接受 deterministic 为 true 的实现。

callback 签名中的参数均由引擎提供：

| 参数 | 类型 | 含义 |
| --- | --- | --- |
| document | Document | 完整 AST；analysis 接收到最终 bindings |
| source | SourceBuffer | 与当前文档关联的作者输入 |
| limits | ParseLimits | 引擎实际使用的结构上限 |
| budget | OperationBudget | 跨阶段累计的工作预算 |
| cancellation | CancellationToken | 同一操作的取消信号 |

注册方法分别是 `.astTransform(transform)` 和 `.documentAnalysis(analysis)`，manifest
必须声明对应能力。阶段内按 priority 降序、extension ID、stage ID 排序。
transform 返回值必须保留实际 source、profile 和 dialect，且通过有预算及取消检查的
AST 验证。TreeRewriter 接受同一 limits/budget/cancellation，构造时限制新节点数量。

analysis 返回值的主范围、relatedSpans 和 fixes 范围必须位于输入内并满足解码边界。
诊断代码、消息及 fix 文本消耗累计预算，并受 literal 上限限制。省略的 extensionId 和
ruleId 分别补为当前扩展与 analysis ID；不能冒用另一个扩展的身份。
callback 自身的临时分配需要宿主实现约束，此接口不是进程隔离。

Cancelled、BudgetExceeded 和 LimitExceeded 保持原错误类别。其它 callback 错误包装为
ExtensionFailureException，保留扩展版本、stage ID 与 ast_transform/document_analysis
阶段。本次解析不会因此返回成功的空文档。

append 在 finish 时执行整文阶段。source events 与独立 raw-block 会话在 callback 前
拒绝；RequireFused 失败，PreferFused 回退完整 AST。运行
cookbook 可检查绑定后的标题诊断。选择 STS 1.2.0 SDK 后，从仓库根目录执行：

```sh
cd examples/cookbook
cjpm build
cjpm run --skip-build
```

输出的 `== bound-analysis ==` 段包含 `heading=analyzed`。
完整实现见 [cookbook 源码](../../examples/cookbook/src/main.cj)。ExtensionLintProvider
仍为显式 snapshot lint 操作提供诊断。

## Official extensions

`OfficialExtensions` 提供版本化、默认关闭的 Footnotes、Front Matter、Math、
Definition Lists、Heading IDs 和 Smart Punctuation。使用 `catalog()` 查询 enablement
信息，或用 `p1Dialect()` 创建组合方言。

Front Matter 和 Math 只保留 literal，不执行配置或数学引擎。

脚注和标题 ID 使用 2.0 语义与 typed payload；编号、目标和目录来自
`Document.bindings`。定义列表 2.0 使用 List/Entry/Term/Definition typed 结构，支持多 term、
多定义和普通 Markdown 块正文。规则见[结构化定义列表](../definition-lists.md)；脚注和标题
见[文档绑定](../semantic-binding.md)。不能从 p1Dialect 的名字推断全部 issue #10 目标已验收。
Smart Punctuation 2.0 仅声明 transform，不声明 parser rule；Front Matter 与 Math 的
当前 literal 实现版本为 1.0.0。边界见[官方能力矩阵](../extensions.md#官方扩展能力矩阵)。

## External descriptor

`ExternalDialectDescriptor` 解析数据型 JSON/YAML descriptor。descriptor 不能携带
callback。未知字段、重复字段、无界规则和 unsupported schema 会失败。

## 测试扩展

```cangjie
let report = MarkdownExtensionTestKit.verify(engine, sample)
```

TCK 检查 parse/render、span、determinism、chunk invariance 和 AST invariants。扩展包还应
覆盖未闭合、嵌套、冲突、limits、cancellation 和 renderer fallback。

## 安全边界

host-code extension 拥有宿主进程权限。`IsolatedPluginRunner` 只定义 fail-closed IPC
协议；`PluginIsolationTransport` 必须由宿主创建真实 OS process 或 sandbox。

transport 通过 `IsolatedPluginResponseSink` 增量提交全部不可信字符串。依次使用
`writeProtocolVersion`、`writeExtensionId` 和 `writeImplementationVersion` 提交响应身份字段，
使用 `writeOutput` 提交 output chunk。每条诊断调用 `beginDiagnostic`，分块调用
`writeDiagnosticMessage`，按需调用 `addDiagnosticRelatedSpan` 和 `addDiagnosticFix`，然后调用
`finishDiagnostic`。`PluginIsolationTransport.invoke` 返回 `Unit`。
sink 在保留数据前执行 `maximumOutputBytes`、`maximumDiagnosticCount`、
`maximumDiagnosticMessageBytes`、`maximumDiagnosticAggregateBytes` 和
`maximumResponseBytes`。transport 不得先构造完整的身份字段、`IsolatedPluginResponse` 或
diagnostic message。

## 下一步

- [扩展模型](../extensions.md)
- [Syntax DSL](../syntax-dsl.md)
- [Renderer DSL](../renderer-dsl.md)
- [Extension TCK](../extension-tck.md)
