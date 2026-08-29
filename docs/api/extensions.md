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
| `requiredSpiVersion` | `"1"` |
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
Markdown、CST、format、serialize、incremental、lint、postprocess 和 transform。
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
    .documentProcessor(processor)
    .lint(provider)
    .disable(extensionId)
    .build()
```

`disable` 会在编译前移除该扩展的 manifest、syntax、renderer、SPI、processor 和
lint provider。

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

DSL 无法表达的有限行内语法可实现 SPI v1。实现必须声明：

- `extensionId`
- `ruleId`
- `triggerBytes`
- `maximumLookahead`
- `priority`
- `deterministic`
- parse callback

`triggerBytes` 是所有可能 opener 的首 byte，必须非空且无重复。parser 只在这些位置
调用 SPI。runtime 会验证 consumed range、node identity 和 SourceSpan。

## Processor 和 lint provider

`ExtensionDocumentProcessor` 在声明的 `ExtensionProcessingPhase` 运行。
`ExtensionLintProvider` 为 snapshot 提供诊断。callback 抛出的错误会包装成
`ExtensionFailureException`，并保留 extension、version、phase 和 rule ID。

包含 document processor 的 dialect 不能使用 source Event API，因为 processor 需要
完整 AST。

## Official extensions

`OfficialExtensions` 提供版本化、默认关闭的 Footnotes、Front Matter、Math、
Definition Lists、Heading IDs 和 Smart Punctuation。使用 `catalog()` 查询 enablement
信息，或用 `p1Dialect()` 创建组合方言。

Front Matter 和 Math 只保留 literal，不执行配置或数学引擎。

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

transport 通过 `IsolatedPluginResponseSink` 增量提交解码结果：使用 `writeOutput` 写 output
chunk；每条诊断依次调用 `beginDiagnostic`、分块 `writeDiagnosticMessage`、按需调用
`addDiagnosticRelatedSpan` / `addDiagnosticFix`，再调用 `finishDiagnostic`。transport 返回
`IsolatedPluginResponseIdentity` 结束响应。
sink 在保留数据前执行 `maximumOutputBytes`、`maximumDiagnosticCount`、
`maximumDiagnosticMessageBytes`、`maximumDiagnosticAggregateBytes` 和
`maximumResponseBytes`。transport 不得先构造完整的 `IsolatedPluginResponse`。

## 下一步

- [扩展模型](../extensions.md)
- [Syntax DSL](../syntax-dsl.md)
- [Renderer DSL](../renderer-dsl.md)
- [Extension TCK](../extension-tck.md)
