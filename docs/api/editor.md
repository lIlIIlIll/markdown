# Editor API

`markdown.editor` 提供 AST traversal、query、rewrite、CST、snapshot、lint 和保留格式
编辑。它不会改变 `markdown.core` 的默认 parse 路径。

## 遍历

`Document.walk()` 和 `NodeRef.walk()` 返回深度优先 iterator：

```cangjie
for (event in document.walk()) {
    match (event) {
        case NodeRefWalkEvent.Enter(node) => println("enter ${node.kind}")
        case NodeRefWalkEvent.Exit(node) => println("exit ${node.kind}")
    }
}
```

`MarkdownVisitor` 提供可继承的 `enter` 和 `exit` callback。walker 是迭代式实现，
不会依赖宿主调用栈递归。

## `AstQuery`

常用查询：

```cangjie
let headings = AstQuery.headings(document)
let links = AstQuery.links(document)
let node = AstQuery.byNodeId(document, id)
let path = AstQuery.ancestors(document, id)
```

完整方法：

- `descendants(document)`
- `descendants(node)`
- `byNodeId(document, id)`
- `byKind(document, kind)`
- `containing(document, span)`
- `ancestors(document, id)`
- `headings(document)`
- `links(document)`
- `images(document)`
- `codeBlocks(document)`
- `customNodes(document)`

## `TreeRewriter`

```cangjie
let rewritten = TreeRewriter.rewrite(
    document,
    { node =>
        if (let NodeKind.Text <- node.kind) {
            RewriteAction.MapText(node.asText().getOrThrow().value.toUpper())
        } else {
            RewriteAction.Keep
        }
    },
    budget: OperationBudget.safe(),
    cancellation: CancellationToken.none()
)
```

`RewriteAction`：

- `Keep`
- `Replace(NodeRef)`
- `Remove`
- `InsertBefore(Array<NodeRef>)`
- `InsertAfter(Array<NodeRef>)`
- `ReplaceChildren(Array<NodeRef>)`
- `MapText(String)`
- `ReplaceText(raw, value)`
- `DetachLiteral`

作为 action 参数的 NodeRef 必须属于输入 Document。返回的 Document 重新验证 AST
invariants。没有变化时，rewriter 可以返回原 Document。

## Transform pipeline

`TransformPass` 声明 ID、version、依赖、产出、priority 和 purity。

```cangjie
let pipeline = TransformPipeline.compile(passes)
println(pipeline.orderedPassIds())
let transformed = pipeline.run(document)
```

编译器按依赖和 priority 生成确定顺序。duplicate ID、missing dependency 或 dependency
cycle 会失败。每个 pass 之后验证 AST。

## Annotation

```cangjie
let store = AnnotationStore()
let key = AnnotationKey<String>("example")
let channel = store.channel(key)
channel.put(node.nodeId, "value")
let value = channel.get(node.nodeId)
store.close()
```

`AnnotationStore.threadSafe` 为 false。store 是 owner-thread confined；跨线程共享时由
调用者同步。`close()` 后不能继续写入。

## `SyntaxTree`

`SyntaxTree` 是 lossless CST：

```cangjie
let syntax = SyntaxTree.parse(result.source, document: Some(result.document))
if (syntax.losslessText() != result.source.text()) {
    throw IllegalStateException("CST is not lossless")
}
```

`SyntaxToken` 保留 raw text 和 SourceSpan。`SyntaxNode` 包含 token range、children、
trivia 和可选 semantic NodeId。

查询：

| 方法 | 结果 |
| --- | --- |
| `losslessText()` | 重建原始输入 |
| `tokenAt(byteOffset)` | offset 对应 token |
| `originatingTokens(node)` | semantic node 对应 token |

`SyntaxToAstMap` 提供：

- `originatingTokens(node)`
- `originatingSyntaxNode(node)`
- `semanticNode(syntaxNode)`
- `semanticNode(token)`

CST 使用共享 token arena。嵌套节点保存 range，不复制整组 token。

## `DocumentSnapshot`

```cangjie
let snapshot = engine.parseSnapshot(source)
```

字段：

- `engine`
- `version`
- `result`
- `syntaxTree`
- `syntaxMap`
- `sourceDigest`

### 应用 byte edit

```cangjie
let reparse = snapshot.applyEdits([
    SourceEdit(SourceSpan(2, 5), "new")
])
```

edits 使用原始 UTF-8 byte range。范围必须有效且不能重叠。

### 应用 UTF-16 edit

```cangjie
let reparse = snapshot.applyUtf16Edit(
    Utf16Position(0, 2),
    Utf16Position(0, 5),
    "new"
)
```

结果 `ReparseResult` 包含新 snapshot、changed range、changed NodeIds、
`wasIncremental`、diagnostics changed range 和 source-map changed range。

单个、等 byte 长度、纯文本、顶层 paragraph 或 heading edit 在没有 reference/extension
依赖时可走 block-local fast path。其他 edit 明确回退完整解析。

## Stable node identity

```cangjie
let stable = snapshot.stableNodeId(node.nodeId)
```

`StableNodeId` 使用内容和路径身份，适合在 snapshot 之间关联节点。它不改变
`NodeId` 只在一个 Document 内稳定的契约。

## Preserving formatter

```cangjie
let edits = PreservingFormatter.formatRange(
    snapshot,
    range,
    fallback: RangeFormatFallback.PreserveSource
)
```

方法：

- `applyEdits(snapshot, edits)`
- `formatRange(snapshot, range, fallback)`
- `formatNode(snapshot, nodeId, fallback)`
- `formatChangedRanges(reparse, fallback)`

`PreserveSource` 在扩展节点没有 Markdown lowering 时返回无编辑。`Error` 会抛出
`UnsupportedNode`。

preserving formatter 只规范化目标范围内支持的语法。未触及内容保持 byte-for-byte
不变。

## Lint

```cangjie
let snapshot = engine.parseSnapshot(source)
let diagnostics = engine.lint(snapshot)
```

`LintDiagnostic` 包含：

- `code`
- `category`
- `severity`
- `message`
- `span`
- `fixes`

内置 lint 覆盖 heading level、link/image、危险 URI、raw HTML、table column、
invisible Unicode、duplicate/unused reference 和一组标记歧义。

应用 fix：

```cangjie
let reparse = MarkdownLinter.applyFix(snapshot, fix)
```

Fix 绑定 source digest 和 snapshot version。对旧 snapshot 使用 fix 会失败。

## Explain

```cangjie
let dialect = engine.explainDialect()
let decision = engine.explain(source, byteOffset)
```

`CompiledDialectExplanation` 报告 profile、rule order、renderer coverage、limits 和
fingerprint。`ExplainResult` 报告候选规则、选中规则、priority、tie-break、extension
和 profile clause。

## 下一步

- [Formatting](../formatting.md)
- [Document systems](../document-systems.md)
- [AST 与 Source API](ast-and-source.md)
