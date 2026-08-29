# AST 与 Source API

`Document` 是不可变 arena AST。`NodeRef` 是绑定到一个 Document snapshot 的轻量
节点引用。源码位置统一使用 UTF-8 byte offset。

## `SourceSpan`

```cangjie
let span = SourceSpan(startByte, endByte)
```

range 是半开区间 `[startByte, endByte)`。

| 成员 | 类型 | 含义 |
| --- | --- | --- |
| `startByte` | `Int64` | 起始 UTF-8 byte offset |
| `endByte` | `Int64` | 结束 UTF-8 byte offset |
| `length()` | `Int64` | byte 长度 |
| `isEmpty()` | `Bool` | 起止位置是否相同 |
| `contains(offset)` | `Bool` | 是否包含 offset |
| `containsSpan(other)` | `Bool` | 是否包含另一个 span |

构造函数拒绝负 offset 和 `endByte < startByte`。

## `SourceBuffer`

`ParseResult.source` 是解析结果对应的 `SourceBuffer`。

| 方法 | 返回值 |
| --- | --- |
| `byteLength()` | UTF-8 byte 数 |
| `text()` | 完整解码文本 |
| `slice(span)` | span 对应文本 |
| `sourceSlice(span)` | 延迟读取的 `SourceSlice` |
| `line(lineNumber)` | 指定的一基行文本 |
| `lineCount()` | 行数 |
| `position(byteOffset)` | 一基 line 和 byte column |
| `utf16Position(byteOffset)` | 零基 line 和 UTF-16 character |
| `visualPosition(byteOffset, tabStop)` | scalar column，默认 tab stop 为 4 |
| `byteOffset(utf16Position)` | UTF-16 位置转 byte offset |

```cangjie
let result = Markdown.parse("A😀\nB")
let byte = result.source.byteOffset(Utf16Position(0, 3))
let position = result.source.position(byte)
```

`byteOffset` 拒绝位于 surrogate pair 中间的 UTF-16 位置。

## `SourcePositionMap`

需要大量位置查询时，创建一次索引：

```cangjie
let positions = SourcePositionMap(result.source, tabStop: 4)
let lsp = positions.utf16Position(node.span.getOrThrow().startByte)
let byte = positions.byteOffset(lsp)
```

`SourcePositionMap` 使用 line index、checkpoint 和二分查找。visual column 是 Unicode
scalar 语义，不是终端 cell width。CJK wide character、combining mark 和 ZWJ emoji
不会被伪装成终端显示宽度。

## 输入所有权

### `OwnedUtf8Input`

```cangjie
let input = unsafe { OwnedUtf8Input.take(bytes) }
let result = engine.parse(input)
```

`take` 要求 bytes 已是有效 UTF-8，并转移唯一所有权。调用者不得保留或修改 alias。
实例只能消费一次。

### `ReusableUtf8Input`

```cangjie
let input = ReusableUtf8Input(bytes)
let first = engine.parse(input)
let second = engine.parse(input)
```

安全构造函数验证并防御性复制一次。unsafe `take` 可转移已验证 bytes。每次 parse
仍构造新的完整 AST。

## `Document`

| 成员 | 类型 | 含义 |
| --- | --- | --- |
| `root()` | `NodeRef` | Document root |
| `nodeAt(index)` | `NodeRef` | 逻辑 arena index 对应节点 |
| `nodeCount` | `Int64` | 可达节点数 |
| `childCount` | `Int64` | 可达 child edge 数 |
| `children()` | `NodeChildren` | root children |
| `profile` | `MarkdownProfile` | parse profile |
| `dialectFingerprint` | `String` | 编译方言身份 |
| `references` | `ImmutableArray<ReferenceDefinition>` | reference definitions |
| `walk()` | `NodeRefWalker` | 深度优先 enter/exit iterator |
| `detach()` | `Document` | 将 slice-backed text/code/html literal 转成 owned text |

`NodeRef` 只能和其所属 `Document` 一起使用。把一个 snapshot 的 NodeRef 传给另一
个 Document 会抛出 `IllegalArgumentException`。

## `NodeRef`

通用属性：

- `nodeId`
- `kind`
- `category`
- `span`
- `originKind`
- `origin`
- `children()`

typed view 方法在 kind 匹配时返回 `Some`：

| Node kind | View |
| --- | --- |
| Document | `asDocument()` |
| Heading | `asHeading()` |
| Text | `asText()` |
| List/ListItem | `asList()`、`asListItem()` |
| Code block/span | `asCodeBlock()`、`asCodeSpan()` |
| HTML block/inline | `asHtmlBlock()`、`asHtmlInline()` |
| Link/Image | `asLink()`、`asImage()` |
| Table/row/cell | `asTable()`、`asTableRow()`、`asTableCell()` |
| Custom block/inline | `asCustomBlock()`、`asCustomInline()` |

```cangjie
for (event in result.document.walk()) {
    match (event) {
        case NodeRefWalkEvent.Enter(node) =>
            if (let Some(heading) <- node.asHeading()) {
                println("h${heading.level}")
            }
        case NodeRefWalkEvent.Exit(_) => ()
    }
}
```

## `NodeKind`

块节点：

`DocumentNode`、`BlockQuote`、`List`、`ListItem`、`Paragraph`、
`Heading`、`ThematicBreak`、`CodeBlock`、`HtmlBlock`、`Table`、
`TableRow`、`TableCell`、`CustomBlock`。

行内节点：

`Text`、`SoftBreak`、`HardBreak`、`CodeSpan`、`Emphasis`、`Strong`、
`Strikethrough`、`Link`、`Image`、`HtmlInline`、`CustomInline`。

## Node identity 和 origin

`NodeId` 在一个 Document 内确定且唯一。编辑或重新解析后，不保证保留同一 NodeId。
编辑器场景使用 `StableNodeId`。

`NodeOriginKind` 包含 `Parsed`、`ExtensionGenerated`、`Transformed`、
`Synthetic` 和 `Deserialized`。普通 parsed node 的 origin span 与 node span
一致。

## AST invariants

```cangjie
AstInvariantValidator.validate(document, limits: ParseLimits.safe())
```

validator 检查节点数量、范围包含、child category、acyclic ownership、NodeId 和自定义
payload 契约。parser 热路径在构造时执行限制检查，不依赖 parse 后的全树扫描。

## 查询

`AstQuery` 提供：

- `byNodeId`
- `byKind`
- `headings`
- `links`
- `images`
- `codeBlocks`
- `customNodes`
- `descendants`
- `ancestors`
- `containing`

```cangjie
for (link in AstQuery.links(document)) {
    println(link.destination)
}
```

## 下一步

- [Editor API](editor.md)
- [SourceSpan 与位置编码](../source-position.md)
- [AST 与 transformations](../ast.md)
