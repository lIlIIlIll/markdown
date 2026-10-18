# 输入、限制和取消

`MarkdownEngine` 接受 String、bytes、ownership wrapper、InputStream 和 buffered
session。所有 AST parse 入口执行相同语义和资源限制。

## 选择输入 API

| API | 复制和验证 | 语义产生时间 |
| --- | --- | --- |
| `parse(String)` | 不转换；纯仓颉扫描 | 调用期间 |
| `parse(Array<Byte>)` | 防御性处理并按 UTF-8 policy 解码 | 调用期间 |
| `parse(OwnedUtf8Input)` | unsafe ownership-transfer；不重复验证 | 调用期间 |
| `parse(ReusableUtf8Input)` | 安全构造验证和复制一次；可 unsafe take | 每次调用期间 |
| `parse(InputStream)` | 完整缓冲后解码 | stream EOF 后 |
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
详细契约见 [Core API](api/core.md#source-events)。

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
| `maximumReferences` | reference definitions |
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

根包没有 foreign declaration 或 linker option。默认所有入口使用纯仓颉 scanner。

显式构建可选 accelerator：

```sh
CC=clang AR=ar python3 scripts/build_native_scanner.py \
    --enable \
    --out-dir target/native
```

消费端需要：

1. 为目标平台链接生成的 archive。
2. 导入 `markdown.native.NativeLineScanner`。
3. 调用 `engine.acceleratedBy(NativeLineScanner())`。

```cangjie
import markdown.native.NativeLineScanner

let accelerated = engine.acceleratedBy(NativeLineScanner())
let result = accelerated.parse(bytes)
```

`nativeScannerEnabled(false)` 可禁止已注入 accelerator。native off 必须保持功能完整。

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

`BufferedAsyncHtmlOutputSession` 先渲染完整 HTML，再分块写 sink。它不降低 peak
output memory。0.9 已删除会让使用者误以为是真正异步增量 renderer 的旧类型名
`AsyncHtmlRenderSession`。

## 下一步

- [Core API](api/core.md)
- [AST 与 Source API](api/ast-and-source.md)
- [并发与可观测性](concurrency-and-observability.md)
