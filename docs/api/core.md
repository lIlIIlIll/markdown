# Core API

`markdown.core` 提供解析入口、profile、完整 AST、资源限制、诊断和 source Event API。

## 导入

```cangjie
import markdown.core.{
    CancellationSource,
    Markdown,
    MarkdownEngine,
    MarkdownException,
    MarkdownProfile,
    OperationBudget,
    ParseLimits,
    Utf8Policy
}
```

## `Markdown`

`Markdown` 是无状态便利门面。所有方法默认使用
`MarkdownProfile.commonMark0312()`。

| 方法 | 返回值 | 行为 |
| --- | --- | --- |
| `parse(source, profile)` | `ParseResult` | 构造完整 AST |
| `toSafeHtml(source, profile)` | `String` | 使用安全 HTML 默认值 |
| `toSpecHtml(source, profile)` | `String` | 使用 CommonMark 兼容 raw HTML 行为 |
| `toText(source, profile)` | `String` | 输出纯文本 |
| `format(source, profile)` | `String` | 输出 canonical Markdown |

需要自定义限制、方言、取消或 budget 时，使用 `MarkdownEngine`。

## `MarkdownEngineBuilder`

```cangjie
let engine = MarkdownEngine.builder()
    .profile(MarkdownProfile.gfm029())
    .limits(ParseLimits.safe())
    .nativeScannerEnabled(false)
    .build()
```

| 方法 | 参数 | 结果 |
| --- | --- | --- |
| `profile(profile)` | `MarkdownProfile` | 选择 profile，并清除之前设置的 dialect |
| `limits(limits)` | `ParseLimits` | 覆盖 parser 限制 |
| `dialect(dialect)` | `MarkdownDialect` | 编译并安装方言；未显式设置 limits 时使用 dialect limits |
| `nativeScannerEnabled(enabled)` | `Bool` | 允许或禁止已注入 accelerator；不会自动链接 native library |
| `build()` | 无 | 返回不可变 `MarkdownEngine` |

默认 profile 是 CommonMark 0.31.2，默认限制是 `ParseLimits.safe()`。

## `MarkdownEngine.parse`

所有 parse overload 都构造完整 `Document`、`NodeId`、`SourceSpan` 和
`ParseResult`。

| 输入 | 额外参数 | 说明 |
| --- | --- | --- |
| `String` | cancellation、budget | 直接使用不可变 String |
| `Array<Byte>` | utf8Policy、cancellation、budget | 默认 Strict UTF-8 |
| `OwnedUtf8Input` | cancellation、budget | unsafe ownership-transfer，一次性消费 |
| `ReusableUtf8Input` | cancellation、budget | 验证和复制一次，可重复解析 |
| `InputStream` | utf8Policy、cancellation、budget | 完整缓冲后解析 |

公共参数默认值：

```cangjie
cancellation: CancellationToken = CancellationToken.none()
budget: OperationBudget = OperationBudget.safe()
utf8Policy: Utf8Policy = Utf8Policy.Strict
```

`Utf8Policy.Strict` 遇到非法 UTF-8 时失败。`ReplaceInvalid` 使用 U+FFFD，并在
`diagnostics` 中记录替换，同时保留原始 byte offset。

## `ParseResult`

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `document` | `Document` | 完整不可变 AST |
| `ast` | `Document` | `document` 的兼容属性 |
| `source` | `SourceBuffer` | 源文本、切片和位置转换 |
| `diagnostics` | `ImmutableArray<Diagnostic>` | parser 恢复后保留的诊断 |
| `isComplete` | `Bool` | 正常 parse 为 true |
| `stoppedAt` | `?SourceSpan` | `tryParse` 失败位置 |
| `unfinishedPhase` | `String` | `tryParse` 失败阶段 |
| `errors` | `ImmutableArray<MarkdownException>` | `tryParse` 捕获的错误 |

## `tryParse` 和 `parsePartial`

`tryParse` 捕获 `MarkdownException`，并返回 `isComplete=false` 的结果。失败结果
包含空 `Document`，不包含已完成的 AST 前缀。

```cangjie
let result = engine.tryParse(source)
if (!result.isComplete) {
    for (error in result.errors.toArray()) {
        println("code=${error.code}, phase=${error.phase}")
    }
}
```

`parsePartial` 是同一行为的兼容名称。

## Buffered input

`newBufferedInputSession` 返回 `BufferedInputSession`：

```cangjie
let session = engine.newBufferedInputSession()
session.feed("# title\n")
session.feed("body")
let result = session.finish()
```

`feed` 只累计输入。`finish` 才执行解析。session 不能在 `finish` 后继续使用，也
不支持并发调用。PRD 保留的 `newSession` 入口同样返回 `BufferedInputSession`；它不会
提前产生 AST。

## Source events

`parseEvents` 收集事件数组。需要降低保留内存时，实现 `MarkdownEventSink` 并调用
`emitEvents`。

```cangjie
let events = engine.parseEvents(
    "[name][id]\n\n[id]: /target\n",
    mode: MarkdownEventMode.ResolvedEventMode
)
for (event in events.events.toArray()) {
    if (let MarkdownSourceEventKind.Text <- event.kind) {
        println(event.semanticValue.getOrThrow())
    }
}
```

| Mode | 语义 |
| --- | --- |
| `ResolvedEventMode` | 先建立 reference index，再发出最终语义 |
| `RawBlockEventMode` | 跳过全局 reference resolution，事件标记为非最终 |

`newRawBlockEventSession` 接收 String 或 byte chunks。它会在后续输入证明 block 已闭合时
返回事件，`finish()` 发出最后一个 block 和 `DocumentEnd`。

Event 值不持有 `Document` 或 `NodeRef`。配置 document processor 的 dialect 需要
完整 AST，因此 Event preflight 会失败。

## HTML execution mode

```cangjie
let output = engine.renderHtml(
    source,
    mode: HtmlExecutionMode.FullAst,
    options: HtmlOptions.safe()
)
```

| Mode | 行为 |
| --- | --- |
| `FullAst` | 始终 parse AST 后渲染 |
| `PreferFused` | 只有 preflight 证明等价时使用 fused path，否则回退 FullAst |
| `RequireFused` | 无法证明等价时抛出 RenderFailure |

Fused path 不会静默关闭扩展、processor 或安全策略。

## Profile

| Factory | ID |
| --- | --- |
| `commonMark0312()`、`commonMark()` | `commonmark-0.31.2` |
| `gfm029()` | `gfm-0.29` |
| `gfmModernV1()`、`gfm()` | `gfm-modern-v1` |
| `custom(id, version)` | 调用者提供 |

需要与官方 GFM 0.29 语料逐项对齐时使用 `gfm029()`。需要仓库固定的现代 GFM
组合时使用 `gfmModernV1()`。

## Limits、budget 和取消

`ParseLimits` 固定结构上限：

- `maximumInputBytes`
- `maximumLineBytes`
- `maximumNestingDepth`
- `maximumAstNodes`
- `maximumReferences`
- `maximumTableColumns`
- `maximumUrlBytes`
- `maximumLiteralBytes`
- `maximumOutputBytes`
- `maximumExtensionCaptureBytes`
- `maximumExtensionLookaheadBytes`

`OperationBudget` 是每次操作递减的 scan、delimiter、extension callback、transform、
rendered node 和 output byte 预算。实例不是线程安全对象，也不能跨操作复用；每次
parse、render 或 transform 应创建独立 budget。`CancellationSource.cancel()` 会使共享
token 在下一个检查点抛出取消错误。

## Errors 和 diagnostics

`MarkdownException` 提供：

- `code: MarkdownErrorCode`
- `phase: String`
- `span: ?SourceSpan`
- extension 和 cause 上下文

常用子类型包括 `LimitExceededException`、`InputReadFailureException`、
`ExtensionFailureException` 和 `SinkFailureException`。

`Diagnostic` 表示可恢复问题，包含 code、severity、message、span、extension、
rule 和可选 fix。程序应根据 code 分支。

## Capability discovery

```cangjie
let capabilities = engine.capabilities()
let models = engine.executionModels()
```

`EngineCapabilities` 报告 profile、扩展、renderer、schema version、位置编码和 native
scanner 状态。`ExecutionModelCapabilities` 明确 buffered input、Event 和 async output
语义。

## 下一步

- [AST 与 Source API](ast-and-source.md)
- [Rendering API](rendering.md)
- [输入、限制和取消](../input-and-resources.md)
