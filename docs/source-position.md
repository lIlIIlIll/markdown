# SourceSpan 与位置编码

`markdown` 使用 UTF-8 byte offset 作为 canonical 源码坐标。`SourceSpan` 是半开区间
`[startByte, endByte)`。

## 坐标类型

| 类型 | 基准 | 列语义 |
| --- | --- | --- |
| `SourceOffset` | 零基 byte | UTF-8 byte |
| `SourceSpan` | 零基 byte | 半开 range |
| `SourcePosition` | 一基 line | byte column |
| `Utf16Position` | 零基 line | UTF-16 code unit，适合 LSP |
| `VisualPosition` | 一基 line | Unicode scalar；可展开 tab |

## 转换

```cangjie
let result = Markdown.parse("A😀\nB")
let map = SourcePositionMap(result.source)

let utf16 = map.utf16Position(5)
let byte = map.byteOffset(utf16)
let source = map.sourcePosition(byte)
```

`SourcePositionMap` 建立 line index 和 checkpoint。重复查询不从文档开头重新扫描。

## UTF-16 限制

`byteOffset(Utf16Position)` 拒绝：

- 超出行范围的位置
- 超出行尾的位置
- 位于 surrogate pair 中间的位置

## Visual position

`DisplayWidthPolicy.UnicodeScalar` 让每个 Unicode scalar 增加一列。
`UnicodeScalarWithTabStops` 额外将 tab 展开到 tab stop。

这个 API 不计算终端 cell width。CJK wide character、combining mark、variation selector
和 ZWJ emoji 保持 scalar 语义。

## 非法 UTF-8

`Utf8Policy.Strict` 抛出 encoding error。`ReplaceInvalid` 产生 U+FFFD 和
`MD1001_INVALID_UTF8_REPLACED`，并通过 decoded-to-original mapping 保留原始 byte
range。

ReplaceInvalid source 不是 identity mapping。0.9 artifact API 会拒绝它，避免把不同原始
bytes 视为同一缓存输入。

完整方法见 [AST 与 Source API](api/ast-and-source.md)。

