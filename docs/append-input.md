# 追加输入与更新消费

需要在完整输入到达前取得 AST 块时，使用 `MarkdownEngine.newAppendSession()`。
`feed` 执行共享 parser 的块解析，交付结构已经闭合的顶层块；引用和文档语义仍然待定。
`finish` 解析保留尾部，将依赖后置定义的行内单元各解析一次，组装完整 Document，再运行
与 batch 相同的文档处理和绑定流程。它不在每次 feed 重解析全文，也不在 finish 再做一次
全文块解析。

只需要累积输入后解析时，可以使用 `newBufferedInputSession()`。不需要 AST 的 raw
事件消费者继续使用 `newRawBlockEventSession()`。

## 消费全部更新

```cangjie
import markdown.core.*

let engine = MarkdownEngine.builder().build()
let session = engine.newAppendSession()
let replica = AppendReplica()
replica.apply(session.feed("[name][id]\n\n"))
replica.apply(session.feed("[id]: /guide\n"))
let last = session.finish()
replica.apply(last)
match (last.state) {
    case AppendState.Complete => {
        let result = replica.result.getOrThrow()
        println(engine.htmlRenderer().render(result.document))
    }
    case AppendState.Failed(error) => println(error.message)
    case AppendState.AwaitingInput => ()
}
```

任意一次 feed 都可能返回 `Failed`。调用方应当在收到终态时停止生产输入。
上述示例输入有效；实际接入还需要在每次 feed 后检查 `batch.state`。
`ParseResult` 只出现在成功的最终 `Bind` 操作中。失败不携带空文档或成功前缀。
会话和消费端都按顺序使用，不支持并发调用。

## 原子更新协议

每次 feed（包括空 chunk）和 finish 返回一个 `AppendUpdateBatch`。批次包含：

| 字段 | 规则 |
| --- | --- |
| `protocolVersion` | 当前为 1；仅描述本地契约，不提供旧版本 reader |
| `sessionId` | 进程内唯一会话身份；不能用另一会话的更新续接 |
| `fromVersion` / `toVersion` | 首批为 0 → 1，之后逐批加 1 |
| `sequence` | 首批为 1，逐批加 1；空更新也占一个序号 |
| `changes` | 不可变操作数组，整体应用后才可观察 |
| `state` | `AwaitingInput`、`Complete` 或 `Failed(error)` |
| `progress` | 原始输入/pending 字节与累计扫描、节点构造、patch 工作量 |

操作为 `Append(block)`、`Replace(oldNodeId, block)`、`Remove(oldNodeId)` 和
`Bind(result)`。Replace/Remove 的目标来自 **fromVersion 的块集合**，不按上一条操作
执行后的数组下标查找。最终修订可以更换块身份、删除块或改变顺序；不能逐条暴露中间态。
Complete 批次以唯一的 Bind 收尾，所有块必须与完整结果的顶层 children、来源和 revision
一致。Failed 批次没有结构操作，已显示的草稿仍然只是失败会话的草稿。

`AppendReplica.apply` 在修改状态前验证会话、版本、目标和最终绑定。重复、错序、缺失、
过期、跨会话或终态之后的更新会抛出 `IllegalArgumentException`，消费端状态不变。
丢失更新后应重新开始输入并创建新的消费端；本库不保留历史补发队列，也不提供跨进程
同步或自动重放协议。批次的构造器为内部接口。

## 草稿块与最终块

`replica.blocks()` 返回当前顶层块的不可变副本。`AppendBlockView` 包含：

- `node` 与同一来源视图的 `source`；节点中的范围相对于该 fragment。
- `sourceOffset`：fragment 在全文中的原始 byte 偏移。
- `sourceSpan`：已经加上偏移的全文范围。
- `finalSemantics`：只有最终修订中的块为 true。

结构闭合不代表无需修订。例如 `[name][id]` 的目标可能在后文，脚注编号和回链依赖所有
定义和引用，AST transform 也可能删除或改写块。草稿内可能存在内部待定行内节点，不应直接
作为已绑定 AST 渲染、序列化或缓存。需要完整语义时等待 `replica.result`。

未变化节点在最终存储组装时可以保留 NodeId；所有 NodeRef 仍绑定各自不可变 revision。
不要用最终 SourceBuffer 读取旧 fragment 的 NodeRef。需要读取草稿原文时使用该视图
自己的 `source` 和 `node.span`；完整结果使用 `result.source`。

未知自定义 payload 没有隐式的范围搬移规则。当前支持内建节点、`SyntaxPayload`、脚注、定义列表和
标题 ID typed payload；其他 payload 会明确失败为 `UnsupportedNode`。完整组装后依次执行
AST transform、统一绑定和只读 analysis；这些整文阶段不在 feed 中执行。

## UTF-8 与生命周期

String 和 byte feed 共用驱动。UTF-8 多字节序列、CRLF 和 delimiter 可以跨 chunk。
`Utf8Policy.Strict` 在可解析前缀或 finish 检查到非法序列时失败；未完成序列可以继续等待
后续 bytes。`ReplaceInvalid` 使用与 batch 相同的 U+FFFD 替换、诊断和原始 byte 映射。
未闭合内容按当前 profile/扩展规则收尾，不补作者没有输入的字符。

`MarkdownException`（包括取消、预算、编码、扩展失败）变成 Failed 批次并终结会话。
Complete 或 Failed 后再次 feed/finish 抛出 `IllegalStateException`。`AppendReplica`
只有完整消费 Complete 批次后才暴露 ParseResult。

## 累计资源限制与计数

会话沿用 engine 的 ParseLimits 和同一个 OperationBudget，不按 feed 重置。额外的
AppendLimits 用于限制追加路径；所有构造参数必须为正数。

| 上限 | 默认值与含义 |
| --- | --- |
| `maximumPendingBytes` | 32 MiB，尚未结构闭合的原始输入 |
| `maximumRetainedInputBytes` | 32 MiB，保留的原始输入；同时受 engine 输入上限约束 |
| `maximumNodeConstructionSteps` | 1600 万次，推测/回滚、待定行内解析和组装中的节点构造 |
| `maximumPatchSteps` | 400 万次，累计 patch 构造工作 |
| `maximumUpdateBatches` | 400 万批，最后一个名额保留给成功或失败终态 |

长未闭合块会占用 pending；很多小块的整文 feed 会按与逐行生产者相同的边界处理，
不因调用方一次给出大 chunk 就要求全部文本同时满足 pending 上限。达到上限会明确失败。
引用定义跨 fragment 累计，最终脚注/标题/锚点/回链使用同一绑定预算。

输入源、fragment、解码映射、AST 和应用保留的更新都占内存。原始输入字节限制不等同于
实际驻留内存限制；ReplaceInvalid 的解码文本也可能大于原始输入。节点构造计数不是
实际堆分配计数，扫描量不是耗时或 RSS。完成或失败后，会话释放内部输入和草稿引用，
调用方自己保留的批次仍然持有相应不可变视图。不要为展示需要之外的目的无限保存历史。

解析更新和 HTML sink 背压是两个独立流程。取得最终 Document 后，可使用
[可恢复 HTML 输出会话](html-output.md)处理 sink 暂停和字节确认。

## 验证范围

公开会话测试对固定的 652 条 CommonMark 和 671 条 GFM batch 语料分别执行单字节、
固定宽度、混合宽度、整文、逐行和可复现随机宽度六种分块。它们比较最终语义摘要、HTML/Text/Markdown、
SourceMap、diagnostics 和当前 snapshot 往返。另有后置脚注/链接、Unicode/CRLF、
更新拒绝、文档处理器删除、非法 UTF-8、取消、累计限制和长块 scaling 测试。

这些是正确性和实际工作计数验证。完整性能、峰值内存和发布门禁仍按 issue #10 单独收口。
