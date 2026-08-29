# 并发与可观测性

`MarkdownEngine`、renderer 配置和 `Document` 是不可变对象，可由多个线程共享进行
parse、render 和只读 traversal。

## 并发规则

- 每次 parse 拥有独立 mutable state。
- `BufferedInputSession`、`ChunkedParseSession` 和
  `RawBlockEventSession` 不能并发 feed。
- 一个 session 在 `finish()` 后不能复用。
- 没有 mutable global extension registry。
- extension manifest 的 `shareable=false` 表示宿主不能并发复用同一个 callback
  instance。
- `AnnotationStore.threadSafe` 为 false。共享时由宿主同步。

## 收集统计

```cangjie
let parsed = engine.parseObserved(
    source,
    options: StatisticsOptions(timing: true)
)

let rendered = renderer.renderObserved(
    parsed.result.document,
    options: StatisticsOptions(timing: true)
)
```

`timing` 默认 false。关闭时 hot path 不读取时钟。

Parse statistics 包含 input byte、line、node、depth、reference、extension callback、
scan step、diagnostic、profile 和 dialect fingerprint。

Render statistics 包含 rendered node、output byte 和 renderer fingerprint。

## 隐私

统计信息不包含：

- 文档文本
- link destination 或 image URL
- code literal 或 front matter
- thread ID
- 绝对路径
- 远程 telemetry

库不会自动发送 metrics。宿主决定是否记录 `ObservedParseResult` 和
`ObservedRenderedOutput`。

完整字段见 [Artifact、Document 与 Service API](api/artifacts-and-services.md)。

