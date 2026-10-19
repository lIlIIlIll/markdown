# Artifact、Document 与 Service API

本页覆盖 `markdown.artifact`、`markdown.document`、observability 和
`markdown.testkit`。这些 API 不属于最小 parser 使用路径。

## Parse artifact

```cangjie
let result = engine.parse(source)
let artifact = engine.createArtifact(result)

match (engine.loadArtifact(artifact, source)) {
    case ArtifactLoadResult.Hit(document) => println(document.nodeCount)
    case ArtifactLoadResult.CacheMiss(reason) => println(reason)
}
```

`MarkdownParseArtifact` 绑定：

- schema 和 library version
- parser plan version
- profile kind、ID 和标准版本
- dialect 和 engine fingerprint
- original bytes digest
- decoded text digest
- UTF-8 policy
- offset mapping digest
- AST、references 和 diagnostics

`createArtifact` 只接受成功的 ParseResult，并拒绝非 identity UTF-8 mapping。只有输入实际
包含无效 UTF-8 并发生替换时，`ReplaceInvalid` 才产生非 identity mapping。有效 UTF-8
bytes 即使使用 `ReplaceInvalid` 也能创建和加载当前 parse artifact。

`createArtifact` 还会交叉验证 `ParseResult.source`、AST root profile、dialect fingerprint、
parser 保留的 `SourceBuffer`、UTF-8 policy、原始与解码 digest，以及根节点的完整源码
范围。不能把一个 Document 与另一个 SourceBuffer 或 engine 拼接后创建 artifact。
`TreeRewriter` 等保留 parser provenance 的变换结果仍可创建 artifact。

`loadArtifact` 接受 String 或 bytes。任何 schema、profile kind/ID/version、fingerprint、digest、policy
或 mapping 不匹配都返回 `CacheMiss(reason)`。加载时会再次检查 artifact 中 AST 的来源，
避免已篡改的 AST 与正确 digest 组合命中 cache。

0.10 的 parser plan、节点身份及 SPI 改变了 fingerprint。旧 artifact 返回 cache miss，
不进行猜测性迁移。

## Binary snapshot

```cangjie
let snapshot = engine.parseSnapshot(source)
let artifact = BinaryArtifactCodec.encode(snapshot)
let bytes = artifact.bytes()

match (BinaryArtifactCodec.decode(engine, BinarySnapshotArtifact(bytes))) {
    case BinaryArtifactLoadResult.Hit(value) => println(value.version)
    case BinaryArtifactLoadResult.CacheMiss(reason) => println(reason)
}
```

schema ID 是 `markdown-snapshot-binary-3`。codec 使用长度前缀字段，并验证 magic、
profile、dialect、engine、UTF-8 policy、source、AST、CST 和 trailing bytes。

decode 会验证 source 后重新解析 snapshot。它不会信任 artifact 中的未验证节点数据。
解码得到新的 lineage/revision，语义 digest 不包含进程内节点编号。
内建 `SyntaxPayload` 的 typed 参数按名称排序，连同类型和值参与摘要。未知 custom
payload 缺少可验证的语义编码：encode 报 `InvalidArtifact`，decode 返回 CacheMiss。

对显式提供的持久化文件，使用 `BinaryArtifactCodec.read(engine, bytes)`。旧版或未知版
报 `MarkdownErrorCode.UnsupportedVersion`；无效内容报 `InvalidArtifact`。
`decode` 是缓存入口，相同情况返回 CacheMiss。

## Rendered source map

`RenderedOutput` 和 `RenderedSourceMapEntry` 由
`HtmlRenderer.renderWithSourceMap` 返回。完整查询接口见
[Rendering API](rendering.md#source-map)。

## `DocumentGraph`

```cangjie
let graph = DocumentGraph.build(engine, [
    DocumentInput("guide", "# Guide\n\n[API][api]"),
    DocumentInput("api", "[api]: /reference")
])
```

`DocumentGraph.build` 只使用调用者提供的 `DocumentInput`。它不读取文件，不访问
网络。

| 成员 | 含义 |
| --- | --- |
| `documentIds` | 确定输入顺序 |
| `edges` | 文档链接边 |
| `snapshot(id)` | 指定文档 snapshot |
| `resolveReference(label)` | 按输入顺序查找 effective definition |

重复 document ID 会失败。

## HTML 转 Markdown

```cangjie
let converter = HtmlToMarkdownConverter(
    options: HtmlToMarkdownOptions(
        inputPolicy: HtmlInputPolicy.RejectDangerous,
        fidelityPolicy: HtmlFidelityPolicy.Semantic
    )
)
let markdown = converter.convert("<p><strong>Hello</strong></p>")
```

`RejectDangerous` 拒绝 script、style、event handler 和危险 URI。`Trusted` 只用于宿主
已经验证的 HTML。

`Semantic` 忽略未知 tag，仅保留语义。`PreserveUnknownHtml` 保留未知 tag spelling。

支持的语义 tag 包括 heading、paragraph、emphasis、strong、code、deletion、link、
blockquote、list、break 和 thematic break。

## Virtual syntax tree

```cangjie
let tree = VirtualSyntaxTree(snapshot, pageBytes: 65536)
let page = tree.page(
    0,
    cancellation: CancellationToken.none(),
    budget: OperationBudget.safe()
)
```

`VirtualTreePage` 包含 page index、源码范围、相交 token 和 NodeId。它是已完整解析
snapshot 的分页视图，不是 partial parser。

## Observability

```cangjie
let observed = engine.parseObserved(
    source,
    options: StatisticsOptions(timing: true)
)
println(observed.statistics.nodeCount)

let rendered = renderer.renderObserved(
    observed.result.document,
    options: StatisticsOptions(timing: true)
)
```

`StatisticsOptions.timing` 默认 false，因此普通 hot path 不读时钟。

`ParseStatistics` 包含 input bytes、line count、node count、max depth、reference
count、callback count、scan steps、可选 duration、diagnostic count、profile 和 dialect
fingerprint。

`RenderStatistics` 包含 rendered node、output bytes、可选 duration 和 renderer
fingerprint。

统计值不包含文档文本、destination、image URL、code literal、front matter、thread ID、
绝对路径或远程 telemetry。

## `MarkdownExtensionTestKit`

```cangjie
import markdown.testkit.MarkdownExtensionTestKit

let report = MarkdownExtensionTestKit.verify(engine, sample)
if (!report.isSuccess()) {
    for (failure in report.failedChecks.toArray()) {
        println(failure)
    }
}
```

`ExtensionTckReport` 提供 `checks`、`passed`、`failedChecks` 和
`isSuccess()`。

TCK 验证 AST invariants、chunk invariance、安全 HTML、determinism、取消、limits、
formatter 和其他扩展契约。扩展包仍需为自己的参数和嵌套语义增加针对性测试。

## Capability 与 fingerprint

`engine.capabilities()` 返回功能和 schema version。`engine.executionModels()` 返回
输入、Event、async output 和 native accelerator 语义。

artifact cache key 应使用公开 fingerprint 和 digest。不要用对象地址、注册顺序之外的
进程状态或英文错误消息构建 cache identity。

## 下一步

- [Document systems](../document-systems.md)
- [并发与可观测性](../concurrency-and-observability.md)
- [Extension TCK](../extension-tck.md)
