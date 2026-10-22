# AST 与 transformation

`Document` 是不可变、无环的 arena AST。每个 parse 结果拥有自己的 node 和 child
storage。只读 Document 可由多个线程共享。

## 节点模型

`NodeRef` 绑定一个 Document，并公开 kind、category、NodeId、SourceSpan、origin 和
children。使用 `asHeading()`、`asText()`、`asLink()` 等 typed view 读取
kind-specific 字段。

```cangjie
import markdown.core.*
import markdown.engine.MarkdownEngine

let result = MarkdownEngine.builder().build().parse("# title")
let heading = result.document.children()[0].asHeading().getOrThrow()
println(heading.level)
```

`NodeId` 的 lineage 和不回收的局部编号表示节点身份，不是 arena 下标。独立解析相同文本
也生成不同 lineage。持久化分叉仅为实际共享的节点保留 NodeId，新节点分配新编号。
`Document.revision` 标识具体不可变视图，NodeRef 绑定该 revision。不要跨 Document 混用
NodeRef；在新视图中通过 `AstQuery.byNodeId` 重新查询，找不到表示节点未保留。

## Source-backed literal

普通 text、code block 和 HTML block 可引用 `SourceBuffer` 范围，避免复制 literal。
`Document.detach()` 返回等价 Document，并把这些 literal 转为 owned String。需要让
AST 脱离原始输入生命周期时调用 `detach()`。它复制可达节点到独立 arena，保留 NodeId
并创建新 revision，不保留旧 arena 中不可达的 source slice。未知 custom payload 的
ownership 无法验证时报告 `UnsupportedNode`；不会假装已解除来源持有。

## 遍历和查询

- `walk()` 返回 enter/exit iterator。
- `MarkdownVisitor` 提供继承式 traversal。
- `AstQuery` 提供 headings、links、images、code blocks、kind、ancestor 和 span 查询。

以下示例读取进入节点时的 typed view，再按 NodeId 查询同一文档中的路径：

```cangjie
import markdown.core.*
import markdown.engine.MarkdownEngine

let document = MarkdownEngine.builder().build().parse("# title\n\n[API](api.md)").document
for (event in document.walk()) {
    match (event) {
        case NodeRefWalkEvent.Enter(node) =>
            if (let Some(heading) <- node.asHeading()) {
                println("h${heading.level}")
                let retained = AstQuery.byNodeId(document, node.nodeId)
                let path = AstQuery.ancestors(document, node.nodeId)
                println(path.size)
            }
        case NodeRefWalkEvent.Exit(_) => ()
    }
}
for (link in AstQuery.links(document)) {
    println(link.destination)
}
```

## Rewrite

`TreeRewriter.rewrite` 接受一个 `NodeRef -> RewriteAction` callback。rewriter 复用
未改变的 arena 数据，并在返回前验证 invariants。

```cangjie
import markdown.core.*
import markdown.engine.MarkdownEngine

let document = MarkdownEngine.builder().build().parse("Hello").document
let rewritten = TreeRewriter.rewrite(document, {
    node =>
        if (let NodeKind.Text <- node.kind) {
            RewriteAction.MapText(node.asText().getOrThrow().value + "!")
        } else {
            RewriteAction.Keep
        }
}, budget: OperationBudget.safe(), cancellation: CancellationToken.none())
```

rewrite 会消耗 transform budget，并响应 cancellation。

## Transform pipeline

`TransformPipeline.compile` 根据 pass dependency 和 priority 生成确定顺序。每个 pass
返回新 Document。pipeline 会在每个 pass 后验证 AST。duplicate ID、missing dependency 和 dependency cycle
会使编译失败。宿主准备好 passes 后，可用 `orderedPassIds()` 检查确定顺序，再调用
`run(document)` 执行。

## 为节点保存宿主注释

`AnnotationStore` 以 NodeId 为键，不修改 AST。store 限于 owner thread；跨线程共享时由宿主
同步，关闭后不能继续写入：

```cangjie
import markdown.core.*
import markdown.engine.MarkdownEngine

let document = MarkdownEngine.builder().build().parse("# title").document
let node = document.root()
let store = AnnotationStore()
let key = AnnotationKey<String>("example")
let channel = store.channel(key)
channel.put(node.nodeId, "value")
let value = channel.get(node.nodeId)
store.close()
```

## Custom node

`CustomBlock` 和 `CustomInline` 保存：

- extension ID 和 semantic version
- local kind ID
- typed `CustomPayload`
- children
- SourceSpan
- NodeOrigin

扩展必须同时声明 renderer、formatter 和其他 capability coverage，或选择明确的 missing
renderer policy。

## 不变量

`AstInvariantValidator.validate` 检查 ownership、acyclic child edge、NodeId、节点类别、
范围包含和资源限制。parser 在节点构造路径执行 node/literal limits，不通过 parse 后全树
扫描弥补遗漏。

需要独立验证时，可将同一操作的 limits、budget 与 cancellation 交给 validator：

```cangjie
AstInvariantValidator().validate(
    document,
    limits: ParseLimits.safe(),
    budget: OperationBudget.safe(),
    cancellation: CancellationToken.none()
)
```

完整字段和方法见 [API reference](api.md)。

