# AST 与 transformation

`Document` 是不可变、无环的 arena AST。每个 parse 结果拥有自己的 node 和 child
storage。只读 Document 可由多个线程共享。

## 节点模型

`NodeRef` 绑定一个 Document，并公开 kind、category、NodeId、SourceSpan、origin 和
children。使用 `asHeading()`、`asText()`、`asLink()` 等 typed view 读取
kind-specific 字段。

```cangjie
let result = Markdown.parse("# title")
let heading = result.document.children()[0].asHeading().getOrThrow()
println(heading.level)
```

不要跨 Document 保存或混用 NodeRef。重新解析后重新查询节点。

## Source-backed literal

普通 text、code block 和 HTML block 可引用 `SourceBuffer` 范围，避免复制 literal。
`Document.detach()` 返回等价 Document，并把这些 literal 转为 owned String。需要让
AST 脱离原始输入生命周期时调用 `detach()`。

## 遍历和查询

- `walk()` 返回 enter/exit iterator。
- `MarkdownVisitor` 提供继承式 traversal。
- `AstQuery` 提供 headings、links、images、code blocks、kind、ancestor 和 span 查询。

## Rewrite

`TreeRewriter.rewrite` 接受一个 `NodeRef -> RewriteAction` callback。rewriter 复用
未改变的 arena 数据，并在返回前验证 invariants。

```cangjie
let rewritten = TreeRewriter.rewrite(document, {
    node =>
        if (let NodeKind.Text <- node.kind) {
            RewriteAction.MapText(node.asText().getOrThrow().value.toUpper())
        } else {
            RewriteAction.Keep
        }
})
```

rewrite 会消耗 transform budget，并响应 cancellation。

## Transform pipeline

`TransformPipeline.compile` 根据 pass dependency 和 priority 生成确定顺序。每个 pass
返回新 Document。pipeline 会在每个 pass 后验证 AST。

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

完整字段和方法见 [AST 与 Source API](api/ast-and-source.md)。

