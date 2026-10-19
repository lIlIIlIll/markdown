# 暂停与恢复 HTML 输出

`renderer.newOutputSession(document)` 从完整、不可变 Document 创建 `HtmlOutputSession`。
构造时不遍历 AST、不生成 HTML，也不调用 sink、URI rewriter、sanitizer 或 fallback。
首次 `resume(sink)` 才开始实际 renderer 遍历。会话保留节点遍历、表格行、脚注回链、转义
进度及尚未确认的输出，不先渲染整份 HTML。

解析追加输入和 HTML 输出背压是两个独立流程。使用追加会话时，先等待完整绑定成功，再将
其 `result.document` 交给输出会话。

```cangjie
let session = renderer.newOutputSession(document, chunkBytes: 4096)
match (session.resume(sink)) {
    case AsyncRenderState.Complete => println(session.bytesWritten())
    case AsyncRenderState.Paused => () // Resume when the sink becomes writable.
    case AsyncRenderState.Failed(error) => println(error.message)
}
```

宿主在收到 Paused 后等待自己的可写通知，再对同一会话调用 resume。本库不创建后台
线程、事件循环或定时重试任务。会话顺序使用，不允许并发或在 sink 回调中重入。

## sink 的字节确认

`AsyncTextSink.write(slice)` 的每个非空片段都具有完整 UTF-8 编码，字节数不超过
`chunkBytes`。chunkBytes 至少为 4，以容纳任意 Unicode scalar。HTML tag、entity 和
百分号编码可以跨片段；连接所有已确认片段后得到与同步 renderer 完全一致的 HTML。

| 返回值 | 确认规则 |
| --- | --- |
| `Continue` | 已消费整个片段，继续写出 |
| `Pause(n)` | 已消费片段前 n 字节，然后暂停；0 表示本次未接收 |
| `Failed(error)` | 未确认本次片段，输出会话终结为 SinkFailure |

Pause 的 n 必须在 0 到当前片段长度之间，并位于 UTF-8 scalar 边界。全部接收后也可以
返回 `Pause(slice.size)`。非法确认会终结会话，不会按错误位置切割下一段 String。
原生 byte writer 若可能在一个 scalar 中间暂停，需要在宿主 adapter 内完成该 scalar 的
缓存与确认，再报告有效的前缀；不能直接将任意系统调用的 byte count 作为 Pause 参数。

已经确认的前缀不会重发；被拒绝或部分接收的余下字节会原样重试。重试不会再次遍历该
节点、调用宿主端口、做转义或重复消费输出预算。sink 抛出的异常同样表示 SinkFailure。

## 状态和取消

resume 返回 Complete、Paused 或 `Failed(MarkdownException)`。Failed 保留取消、预算、
输出限制、renderer 或 sink 的错误类别。会话沿用创建时的同一个 CancellationToken 和
OperationBudget；暂停和恢复不会重置预算。取消可以发生在首轮输出前、sink 写入后或暂停
期间。sink 已确认的字节会先计入 bytesWritten，随后观察到的取消不会否认该确认。

Complete 和 Failed 都是终态。此后再次 resume 抛出 IllegalStateException；需要重试
整个输出时创建新会话，并由宿主决定如何处理之前已经交付的前缀。失败输出不能冒充完整
HTML，也不能自动重试可能有副作用的宿主端口。终态会释放内部遍历和未确认缓冲。

## 预算、缓冲和可观察计数

- `bytesWritten()`：sink 确认的累计字节数。
- `bytesProduced()`：已实际生成并计入输出预算的累计字节数，包含尚未确认的字节。
- `bufferedBytes()`：当前未确认片段与小型编码缓冲的字节数，终态为 0。

会话独占其操作预算。不要在暂停期间将同一预算用于另一个请求或并发修改它。
renderer 的 maximumOutputBytes、rendered-node/scan/output 预算和安全策略仍然生效。
每个输出片段只生成和计费一次；预算耗尽不向 sink 写出超限部分。

普通 source text、attribute、URI 和 GFM tagfilter 按小段编码。遍历栈使用延迟 child
iterator，表格与脚注区不会先展开全部 HTML。AST、来源文本、规则和调用方保留的数据不
属于 bufferedBytes。宿主 sanitizer、raw HTML handler 或 fallback 仍按各自端口契约返回
内容；会话不会阻止它们在返回前自行分配完整的单节点结果。这些端口是显式受信任能力，
不能从普通外部进程推断出安全沙箱或内存隔离。

正确性测试对全部 652 条 CommonMark 和 671 条 GFM 输入比较 safe/spec/GFM 三种策略、
4/7/4096 字节输出块，并混合拒绝、部分确认、全部确认后暂停和连续写出。还覆盖脚注、
扩展、空输出、取消、sink 失败、非法确认和长文本缓冲上限。计数验证不等同于峰值 RSS 或
端到端性能测量；完整 release gate 仍按 issue #10 单独执行。
