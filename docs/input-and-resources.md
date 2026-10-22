# 输入、限制和取消

`MarkdownEngine` 接受 String、bytes、ownership wrapper、InputStream、追加会话和 buffered
session。所有 AST parse 入口执行相同语义和资源限制。

## 选择输入 API

| API | 复制和验证 | 语义产生时间 |
| --- | --- | --- |
| `parse(String)` | 不转换；纯仓颉扫描 | 调用期间 |
| `parse(Array<Byte>)` | 防御性处理并按 UTF-8 policy 解码 | 调用期间 |
| `parse(OwnedUtf8Input)` | unsafe ownership-transfer；不重复验证 | 调用期间 |
| `parse(ReusableUtf8Input)` | 安全构造验证和复制一次；可 unsafe take | 每次调用期间 |
| `parse(InputStream)` | 完整缓冲后解码 | stream EOF 后 |
| `AppendInputSession` | 保留输入和结构闭合的 AST fragment | feed 产生草稿，finish 完成语义 |
| `BufferedInputSession` | 累计全部 chunks | `finish()` |

String、bytes、Owned、Reusable 和 Stream 每次都创建完整 AST、NodeId、SourceSpan、
SourceBuffer 和 ParseResult。

## UTF-8 policy

```cangjie
let strict = engine.parse(bytes, utf8Policy: Utf8Policy.Strict)
let replaced = engine.parse(bytes, utf8Policy: Utf8Policy.ReplaceInvalid)
```

`Strict` 遇到非法序列时失败。`ReplaceInvalid` 插入 U+FFFD，记录 diagnostic，并保留
原始 byte offset mapping。

## 选择输入所有权

bytes 需要重复解析时，使用 `ReusableUtf8Input` 验证和复制一次。每次 parse 仍生成独立的
完整 AST：

```cangjie
import markdown.core.ReusableUtf8Input
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let input = ReusableUtf8Input("# reusable".toArray())
let first = engine.parse(input)
let second = engine.parse(input)
```

只有能保证有效 UTF-8、唯一所有权且不再保留或修改 alias 时，才使用 unsafe transfer。
转移后的 `OwnedUtf8Input` 只能消费一次：

```cangjie
import markdown.core.OwnedUtf8Input
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let input = unsafe { OwnedUtf8Input.take("# owned".toArray()) }
let result = engine.parse(input)
```

## 追加输入

`newAppendSession()` 在 feed 中交付结构闭合块，并以带会话/版本/目标身份的更新完成最终
修订。使用 `AppendReplica` 验证并原子消费批次；完整结果只在最终成功后出现。
详见[追加输入与更新消费](append-input.md)。

## Buffered input

```cangjie
let session = engine.newBufferedInputSession()
session.feed(firstChunk)
session.feed(secondChunk)
let result = session.finish()
```

session 不提前产生 AST，也不降低 peak input memory。调用 `finish` 后再次 feed 或
finish 会失败。session 不是线程安全对象。

## Source Event API

需要不持有 AST 的事件时，使用：

- `parseEvents`：收集事件数组
- `emitEvents`：直接写入 sink
- `newRawBlockEventSession`：对已闭合 block 提前发出非最终事件

Resolved mode 会先建立 reference index。RawBlock mode 不提供后置 reference resolution。
两种 mode 的事件都不持有 `Document` 或 `NodeRef`。下面先解析后置 reference，再读取最终文本：

```cangjie
import markdown.engine.{MarkdownEngine, MarkdownEventMode, MarkdownSourceEventKind}

let engine = MarkdownEngine.builder().build()
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

需要 AST transform、只读整文 analysis、脚注、标题 ID 或定义列表绑定的 dialect 必须使用
完整 AST，事件 preflight 会拒绝这些配置。

`RawBlockEventSession.feed()` 只扫描新增 bytes，并在收到 chunk 时立即检查
`maximumInputBytes` 和 `maximumLineBytes`。session 通过共享 pending buffer 和游标保留
未闭合 block。fenced code 和 paired DSL 的 opener/closer 都由增量状态跟踪；正文中看似
新 block 的行或 closer 后的长尾随空白不会触发重复解析。实际字符比较会计入
`OperationBudget`。即使调用者逐 byte feed，也不会每次复制或重扫全部历史输入或增长中的
当前行。

## Parse limits

`ParseLimits.safe()` 是默认值。构造自定义 limits 时，所有参数必须为正数。

| Limit | 约束 |
| --- | --- |
| `maximumInputBytes` | 完整输入 |
| `maximumLineBytes` | 单行 |
| `maximumNestingDepth` | block/inline nesting |
| `maximumAstNodes` | 实际构造的内建、扩展和 SPI AST 节点 |
| `maximumReferences` | reference definitions、脚注定义/引用、标题锚点和脚注锚点/回链的累计工作单元 |
| `maximumTableColumns` | table columns |
| `maximumUrlBytes` | link/image destination |
| `maximumLiteralBytes` | code、HTML 和其他累计 literal |
| `maximumOutputBytes` | renderer output |
| `maximumExtensionCaptureBytes` | extension capture |
| `maximumExtensionLookaheadBytes` | extension lookahead |

`ParseLimits.trusted()` 提高 size limit，但不关闭 overflow、capacity、acyclic、stack 或
output protection。

节点和 literal 限制在构造/累计路径检查，不依赖 parse 后全树遍历。fenced code、
indented code 和 HTML literal 在追加每个片段前检查累计值。

Fused HTML execution 不创建 AST，因此 `maximumAstNodes` 不模拟“等价节点数”。它仍执行
input、line、literal 和 output limits。需要 AST node limit 参与执行结果时，选择
`HtmlExecutionMode.FullAst`。

## 选择 HTML 执行模型

默认 `FullAst` 总是先 parse 完整 AST。`PreferFused` 仅在 preflight 能证明语义等价时采用
fused path，否则回退完整 AST；`RequireFused` 在不能证明时以 `RenderFailure` 失败。
这些模式不会静默关闭扩展、整文阶段或安全策略。

```cangjie
import markdown.engine.{HtmlExecutionMode, MarkdownEngine}
import markdown.render.HtmlOptions

let engine = MarkdownEngine.builder().build()
let output = engine.renderHtml(
    "# title",
    mode: HtmlExecutionMode.FullAst,
    options: HtmlOptions.safe()
)
```

两种路径都执行 input、line、literal、output、cancellation 和操作预算。需要
`maximumAstNodes` 参与操作结果时保留 `FullAst`。

## Operation budget

`OperationBudget` 独立限制：

- scan steps
- delimiter steps
- extension callbacks
- transform steps
- rendered nodes
- output bytes

```cangjie
let budget = OperationBudget.safe()
let result = engine.parse(source, budget: budget)
println(budget.usedScanSteps())
```

budget 实例会递减。它不是线程安全对象；每次 parse、render 或 transform 都应创建独立
实例，不要跨请求复用或并发共享。

## 取消

```cangjie
let source = CancellationSource()
let token = source.token
source.cancel()
engine.parse(input, cancellation: token)
```

取消在 input、parse、extension、transform、virtual tree 和 render 检查点生效。宿主负责
把 deadline 或用户操作连接到 `cancel()`。

## Native line scanner

基础解析不包含 foreign declaration 或 linker option。默认所有入口使用纯仓颉 scanner。

显式构建可选 accelerator：

```sh
CC=clang AR=ar python3 scripts/build_native_scanner.py \
    --enable \
    --out-dir target/native
```

消费端需要：

1. 为目标平台链接生成的 archive。
2. 导入 `markdown.native.NativeLineScanner`。
3. 构建 engine 时调用 `.lineScanner(Some(NativeLineScanner()))`。

```cangjie
import markdown.engine.MarkdownEngine
import markdown.native.NativeLineScanner

let engine = MarkdownEngine.builder().lineScanner(Some(NativeLineScanner())).build()
let result = engine.parse(bytes)
```

不配置 `lineScanner` 即使用纯仓颉路径。字节、owned/reusable UTF-8 和 stream 入口可使用
注入端口；String 入口保持直接扫描，不为 native 复制 bytes。纯仓颉路径保持完整功能。

| Target | 工具 | 产物 |
| --- | --- | --- |
| Linux、macOS、Android、HarmonyOS、其他 Clang target | `CC`、`AR`、可选 `--target` | `libmarkdown_scanner.a` |
| MinGW | MinGW `CC` 和 `AR` | `libmarkdown_scanner.a` |
| MSVC | `cl` 和 `lib` | `markdown_scanner.lib` |

build helper 不写死编译器路径。最终 executable 提供 target-specific linker option。

## Source storage

`SourceSlice` 延迟读取一个 SourceBuffer range。`LiteralStorage.Slice` 引用源码，
`LiteralStorage.Copy` 持有独立 String。`document.detach()` 将 slice-backed
text/code/html literal 转成 owned text。

## Partial 和 async 名称

`tryParse` 返回 `ParseOutcome.Success(result)` 或 `Failure(error)`；失败不携带 Document。
它们不返回 AST prefix。

`renderer.newOutputSession()` 在 resume 时执行实际遍历，保留未确认的 UTF-8 输出和转义
状态。sink 用 `Pause(n)` 明确确认前缀。旧 buffered 输出实现已移除；详见
[暂停与恢复 HTML 输出](html-output.md)。

## 下一步

- [API reference](api.md)
- [并发与可观测性](concurrency-and-observability.md)
