# 从 0.8 迁移到 0.9

0.9 重置了 pre-GA AST、Event、artifact 和 parser SPI。消费工程必须重新编译，并删除
0.8 cache artifact。

## 1. 更新包名和 import

依赖名和包名都是 `markdown`：

```toml
[dependencies]
  "markdown" = { path = "/path/to/markdown", output-type = "static" }
```

新代码优先使用子包 import：

```cangjie
import markdown.core.{MarkdownEngine, MarkdownProfile}
import markdown.render.{HtmlOptions, HtmlRenderer}
```

## 2. 使用 arena AST

0.9 的 `Document` 拥有 node/child arena。节点使用 `NodeRef` 和 typed view：

```cangjie
let result = engine.parse(source)
for (node in AstQuery.byKind(result.document, NodeKind.Heading)) {
    let heading = node.asHeading().getOrThrow()
}
```

删除依赖旧 object-tree subclass、parent pointer 或 mutable child array 的代码。

`NodeKind.Document` 和 `SyntaxKind.Document` 已改名为
`DocumentNode`，避免与公开 `Document` 类型冲突。

## 3. 更新 Event consumer

0.9 Event API 使用 `MarkdownSourceEvent`。Event 不包含 Document 或 NodeRef。

- 使用 `parseEvents` 收集最终事件。
- 使用 `emitEvents` 写 sink。
- 使用 `newRawBlockEventSession` 接收非最终的 incremental block events。

删除对 0.8 AST-walk event adapter 的依赖。

## 4. 更新 parser SPI

`InlineParserSpi` 必须实现 `triggerBytes`。它返回所有可能 opener 的 UTF-8 首 byte。
列表必须非空且无重复。

parser 只在匹配的 byte 位置调用 SPI。编译器拒绝 unbounded 或 non-deterministic SPI。

## 5. 更新 artifact

parse artifact 和 binary snapshot 使用 schema 2。schema 1 artifact 直接 cache miss。

0.9 artifact 绑定 original bytes、decoded text、UTF-8 policy 和 offset mapping。
`ReplaceInvalid` source 不能创建 identity-only artifact。

清除旧 cache，不要尝试修改 schema 字段绕过验证。

## 6. 选择 HTML execution

```cangjie
let output = engine.renderHtml(
    source,
    mode: HtmlExecutionMode.FullAst,
    options: HtmlOptions.safe()
)
```

`PreferFused` 只在 preflight 证明语义等价时使用 fused path。`RequireFused` 无法证明时
失败。0.9 不会为了 fused output 静默关闭 extension 或 processor。

## 7. 更新 native scanner 集成

基础包默认纯仓颉，不再要求所有消费工程链接 native archive。

需要 accelerator 时：

1. 使用 `scripts/build_native_scanner.py --enable` 为目标构建 archive。
2. 在最终 executable 配置 linker。
3. 导入 `markdown.native.NativeLineScanner`。
4. 调用 `engine.acceleratedBy(NativeLineScanner())`。

不要把本机构建的 `target` 或 `build-script-cache` 打入源码归档。

## 8. 更新版本假设

0.9 是 breaking pre-GA preview，不是 1.0 ABI 承诺。当前离线 release evidence 已通过
CommonMark/GFM、full tests、package 和性能门槛；这不等于当前 GitHub HEAD 已通过托管
CI，也不等于 GitHub Release 已发布。不要保留早期报告中的 blocked 状态或历史 ratio
作为当前结果。

当前结果以 [release-evidence.json](../release-evidence.json) 和
[性能说明](performance.md)为准。

## 9. 更新 buffered session 名称

`newSession()` 仍可使用，但返回类型改为 `BufferedInputSession`。显式代码优先写成：

```cangjie
let session = engine.newBufferedInputSession()
```

将 `ChunkedParseSession` 类型标注替换为 `BufferedInputSession`。将
`AsyncHtmlRenderSession` 构造替换为 `BufferedAsyncHtmlOutputSession`。这些 API 都会先
缓冲完整输入或输出，不是增量 parser 或 renderer。

## 验证迁移

```sh
cangjie_env
cjpm check
cjpm test --no-color --no-progress
python3 scripts/check_public_api.py
```

消费工程至少验证 parse、Safe HTML、profile、SourceSpan 和自定义 extension 路径。
