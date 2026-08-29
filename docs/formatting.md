# 格式化 Markdown

`markdown` 提供两类 formatter：

- `CanonicalMarkdownRenderer` 从 AST 生成确定的 Markdown。
- `PreservingFormatter` 对 snapshot 的目标范围生成最小 source edits。

## Canonical formatting

```cangjie
let renderer = CanonicalMarkdownRenderer(
    options: MarkdownFormatOptions(
        newline: "\n",
        bulletMarker: "-",
        orderedDelimiter: ".",
        emphasisMarker: "*",
        strongMarker: "**",
        fenceMarker: "`",
        minimumFenceLength: 3,
        tablePadding: true,
        finalNewline: true,
        maximumLineWidth: 100,
        reflowParagraphs: false
    )
)
let formatted = renderer.render(document)
```

`reflowParagraphs` 默认 false。formatter 保留 link destination、code/raw literal、
ordered start、task state、table alignment 和 break semantics。

需要防止 text 和相邻 delimiter 产生新语义时，formatter 会使用 numeric entity。嵌套且
含混的 emphasis 可降低为合法 inline HTML。

## Preserving formatting

```cangjie
let snapshot = engine.parseSnapshot(source)
let edits = PreservingFormatter.formatRange(
    snapshot,
    SourceSpan(startByte, endByte),
    fallback: RangeFormatFallback.PreserveSource
)
let result = PreservingFormatter.applyEdits(snapshot, edits)
```

preserving formatter 只修改目标 range。未触及的 marker、blank line、entity spelling、
fence、code content 和 extension syntax 保持 byte-for-byte 不变。

## Range fallback

| Fallback | 扩展节点没有 Markdown lowering 时 |
| --- | --- |
| `PreserveSource` | 返回无 edit |
| `Error` | 抛出 `UnsupportedNode` |

还可使用 `formatNode` 和 `formatChangedRanges`。

## Snapshot edit

`DocumentSnapshot.applyEdits` 验证 range、拒绝 overlap，并返回
`ReparseResult`。单个等 byte 长度的顶层 paragraph/heading 纯文本 edit 可走
block-local fast path。其他 edit 回退完整 parse。

## CST

`SyntaxTree` 保留 whitespace、newline、marker、delimiter、link part、HTML、entity、
extension 和 invalid input。`losslessText()` 重建原始 source。

完整接口见 [Editor API](api/editor.md) 和 [Rendering API](api/rendering.md)。

