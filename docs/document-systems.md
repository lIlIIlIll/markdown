# Document system

Document system API 建立在完整 AST 和 lossless snapshot 之上。它们不改变 parser 的
默认执行模型。

## Document snapshot

`engine.parseSnapshot(source)` 同时创建：

- `ParseResult`
- `SyntaxTree`
- `SyntaxToAstMap`
- source digest
- snapshot version

通过 `applyEdits` 或 `applyUtf16Edit` 产生新 snapshot。

## Block-local incremental path

以下条件同时成立时，可只重解析一个 block：

- 单个 edit
- replacement byte 长度不变
- edit 位于一个顶层 paragraph 或 heading 的普通文本内
- 没有 reference dependency
- 没有 extension dependency

结果的 `wasIncremental` 为 true。structural、newline、reference、extension 或
size-changing edit 回退完整 parse，并明确返回 false。

这不是通用 incremental parser。

## Document graph

```cangjie
let graph = DocumentGraph.build(engine, inputs)
```

graph 只处理调用者提供的 `DocumentInput(id, source)`。它不读取 filesystem 或
network。duplicate ID 会失败。

`edges` 记录跨文档 destination 和 source NodeId。`resolveReference` 按输入顺序查找
effective definition。

## Binary snapshot

`BinaryArtifactCodec` 使用 schema `markdown-snapshot-binary-2`。artifact 绑定
profile、dialect、engine、source、AST 和 CST digest。

decode 对任何 schema、identity、digest、truncation、UTF-8 或 trailing-byte 问题返回
`CacheMiss`。通过验证后，codec 从 source 重新 parse snapshot。

## Virtual syntax tree

`VirtualSyntaxTree` 按 byte range 返回相交 token 和 NodeId。page 支持 cancellation 和
budget。

它是完整 snapshot 的分页视图。它不表示底层文档只解析了一部分。

## HTML 转 Markdown

`HtmlToMarkdownConverter` 要求显式 input policy 和 fidelity policy。默认
`RejectDangerous + Semantic`。

危险 script、style、event handler 和 URI 会失败。Trusted input 可选择保留未知 tag。

完整 API 见 [Artifact、Document 与 Service API](api/artifacts-and-services.md) 和
[Editor API](api/editor.md)。

