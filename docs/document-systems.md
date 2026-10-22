# 编辑、缓存与多文档

文档系统建立在完整 AST 和 lossless snapshot 之上。snapshot、CST 和 lint 位于
`markdown.editor`，多文档工具位于 `markdown.document`，持久化 codec 位于
`markdown.artifact`。这些能力不改变 parser 的默认执行模型。

## 创建 snapshot 并编辑

`DocumentSnapshot.parse` 同时建立语义 AST、CST、相互映射、source digest 和 snapshot
version。下面分别使用 UTF-8 byte range 和零基 UTF-16 range 编辑同一份原始 snapshot：

```cangjie
import markdown.core.{SourceSpan, Utf16Position}
import markdown.editor.{DocumentSnapshot, SourceEdit}
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let snapshot = DocumentSnapshot.parse(engine, "# old\n\nbody")
let byteEdit = snapshot.applyEdits([
    SourceEdit(SourceSpan(2, 5), "new")
])
let utf16Edit = snapshot.applyUtf16Edit(
    Utf16Position(0, 2), Utf16Position(0, 5), "new"
)
println(byteEdit.snapshot.result.source.text())
println(utf16Edit.snapshot.result.source.text())
```

两个结果都以 `# new` 开头。edit 范围相对于输入 snapshot，必须有效且不能重叠。
后续编辑使用返回的新 snapshot，避免将旧坐标应用到已经改变的文本。
`ReparseResult` 同时报告 changed range、changed NodeIds、diagnostics/source-map changed
range 和 `wasIncremental`。

## 判断局部重解析

以下条件同时成立时，可只重解析一个 block：

- 单个 edit。
- replacement byte 长度不变。
- edit 位于一个顶层 paragraph 或 heading 的普通文本内。
- 没有 reference 或 extension dependency。

此时结果的 `wasIncremental` 为 true。structural、newline、reference、extension 或
size-changing edit 回退完整 parse，并明确返回 false。这不是通用 incremental parser。

只有实际共享的节点保留 NodeId。新节点、独立解析和完整回退不会从相同文本推断身份。
需要在新 snapshot 中查找保留的节点时，使用 `AstQuery.byNodeId(newDocument, oldNodeId)`，
再使用新的 NodeRef。旧 NodeRef 不能用于新 revision 的 CST/AST 映射。

## 校验 lossless CST

snapshot 自带 `syntaxTree` 和 `syntaxMap`。已有 ParseResult 时，也可显式创建 CST，确认
它能逐字节恢复作者输入：

```cangjie
import markdown.editor.SyntaxTree
import markdown.engine.MarkdownEngine

let result = MarkdownEngine.builder().build().parse("# title\r\n\r\nbody")
let syntax = SyntaxTree.parse(result.source, document: Some(result.document))
if (syntax.losslessText() != result.source.text()) {
    throw IllegalStateException("CST is not lossless")
}
```

`SyntaxToken` 保留 raw text 和 SourceSpan，`SyntaxNode` 保留 token range、children、trivia
和可选 semantic NodeId。CST 使用共享 token arena，嵌套节点保存 range。
`tokenAt` 查询 token，`originatingTokens` 和 `SyntaxToAstMap` 在 CST 与语义节点之间转换。

## Lint 与修复新鲜度

在显式 snapshot 上运行 lint，再将选定的 Fix 应用到原 snapshot。每次应用后重新 lint
新 snapshot，不要把同一批旧 Fix 继续应用到已经编辑的文档：

```cangjie
import markdown.editor.{DocumentSnapshot, MarkdownLinter}
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let snapshot = DocumentSnapshot.parse(engine, "# title\n\n### skipped")
let diagnostics = MarkdownLinter(engine).lint(snapshot)
for (diagnostic in diagnostics) {
    println("${diagnostic.code}: ${diagnostic.message}")
}
```

`MarkdownLinter.applyFix(snapshot, fix)` 要求 source digest 和 `Fix.documentRevision`
同时匹配。snapshot version 不能证明修复仍有效：独立解析相同源码、或编辑后改回原文，
仍具有不同 revision，旧 Fix 会被拒绝。

扩展诊断通过 `MarkdownLinter(engine, providers: [...])` 显式注册
`ExtensionLintProvider`。provider 必须匹配 engine 已注册的扩展身份；重复注册及不同 dialect
的 snapshot 会失败。provider 不参与解析 fingerprint。lint 包含结构、安全、样式、引用与
不可见 Unicode 等检查。范围格式化与保留原文的编辑见[格式化指南](formatting.md)。

## 缓存 ParseResult

parse artifact 绑定 library/schema/parser plan、profile、dialect 与 engine fingerprint、原始
bytes/解码文本 digest、UTF-8 policy、offset mapping，以及 AST、references 和 diagnostics。
对相同 engine 和输入尝试加载，明确处理 cache miss：

```cangjie
import markdown.artifact.{ArtifactLoadResult, MarkdownParseArtifact}
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let source = "# cached"
let result = engine.parse(source)
let artifact = MarkdownParseArtifact.create(engine, result)
match (artifact.load(engine, source)) {
    case ArtifactLoadResult.Hit(document) => println(document.nodeCount)
    case ArtifactLoadResult.CacheMiss(reason) => println(reason)
}
```

create 验证 ParseResult 的实际来源、AST root profile、dialect、engine、digest、mapping 和
根范围，不能拼接另一份 SourceBuffer 或 engine。保留 parser provenance 的 TreeRewriter
结果可创建 artifact。非 identity UTF-8 mapping 会被拒绝；有效 UTF-8 即使选择
`ReplaceInvalid` 也仍是 identity mapping。

load 再次验证 AST 来源。任何身份、schema、输入、policy 或 mapping 不匹配均返回
`CacheMiss`。当前 parser plan 为 7，旧 artifact 不做猜测性迁移。缓存键使用公开
fingerprint 和 digest，不使用对象地址或英文错误消息。

## 持久化 binary snapshot

使用 `BinaryArtifactCodec` 保存 snapshot，然后验证加载结果：

```cangjie
import markdown.artifact.{BinaryArtifactCodec, BinaryArtifactLoadResult, BinarySnapshotArtifact}
import markdown.editor.DocumentSnapshot
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let snapshot = DocumentSnapshot.parse(engine, "# cached")
let bytes = BinaryArtifactCodec.encode(snapshot).bytes()
match (BinaryArtifactCodec.decode(engine, BinarySnapshotArtifact(bytes))) {
    case BinaryArtifactLoadResult.Hit(value) => println(value.version)
    case BinaryArtifactLoadResult.CacheMiss(reason) => println(reason)
}
```

schema 为 `markdown-snapshot-binary-3`。codec 校验 magic、profile、dialect、engine、source、
AST、CST、UTF-8、长度和 trailing bytes，然后从 source 重新解析新 snapshot。新的
lineage/revision 不继承进程内节点编号。内建 SyntaxPayload 按名称排序 typed 参数，并将
类型和值纳入语义 digest。未知 custom payload 缺少可验证的语义编码时不能持久化。

decode 作为缓存入口，对不匹配或无效内容返回 CacheMiss。显式持久化文件读取使用
`BinaryArtifactCodec.read(engine, bytes)`，旧版或未知版报 `UnsupportedVersion`，无效内容报
`InvalidArtifact`，不能把损坏的用户文件当成成功文档。

## 处理多个文档

显式传入文档 ID 与文本。graph 不读取文件或访问网络，重复 ID 会失败：

```cangjie
import markdown.document.{DocumentGraph, DocumentInput}
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let graph = DocumentGraph.build(engine, [
    DocumentInput("guide", "# Guide\n\n[API][api]"),
    DocumentInput("api", "[api]: /reference")
])
```

`documentIds` 保留输入顺序，`edges` 记录跨文档 destination 和 source NodeId，
`snapshot(id)` 返回指定文档。`resolveReference` 按输入顺序查找 effective definition。

## 分页查看完整语法树

`VirtualSyntaxTree` 按 byte range 返回相交 token 和 NodeId。page 支持取消与操作预算：

```cangjie
import markdown.core.{CancellationToken, OperationBudget}
import markdown.document.VirtualSyntaxTree
import markdown.editor.DocumentSnapshot
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let snapshot = DocumentSnapshot.parse(engine, "# page")
let tree = VirtualSyntaxTree(snapshot, pageBytes: 65536)
let page = tree.page(
    0, cancellation: CancellationToken.none(), budget: OperationBudget.safe()
)
```

这是已完整解析 snapshot 的分页视图，不表示底层文档只解析了一部分。

## 将 HTML 转为 Markdown

转换不可信 HTML 时保留 `RejectDangerous`，它拒绝 script、style、event handler 和危险 URI。
`Semantic` 对未知 tag 仅保留语义：

```cangjie
import markdown.document.{HtmlFidelityPolicy, HtmlInputPolicy, HtmlToMarkdownConverter, HtmlToMarkdownOptions}

let converter = HtmlToMarkdownConverter(
    options: HtmlToMarkdownOptions(
        inputPolicy: HtmlInputPolicy.RejectDangerous,
        fidelityPolicy: HtmlFidelityPolicy.Semantic
    )
)
let markdown = converter.convert("<p><strong>Hello</strong></p>")
println(markdown)
```

需要保留未知 tag 拼写时使用 `PreserveUnknownHtml`。`Trusted` 仅适用于宿主已经验证的 HTML。
转换支持 heading、paragraph、emphasis、strong、code、deletion、link、blockquote、list、
break 和 thematic break 等语义。精确声明与失败条件见 [API reference](api.md)。
