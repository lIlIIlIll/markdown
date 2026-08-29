# 故障排查

先确认 SDK 和依赖，再根据现象定位。仍无法解决时，请在 issue 中附上最小输入、profile、
SDK 版本、完整命令和结构化错误码。

[文档首页](README.md) · [开始使用](getting-started.md) · **故障排查** · [错误与能力](errors-and-capabilities.md)

## 快速定位

| 现象 | 最可能原因 | 跳转 |
| --- | --- | --- |
| `cjpm` 找不到包 | path 没有指向仓库根目录 | [安装与运行](#安装与运行) |
| 表格或删除线是普通文本 | 仍在使用默认 CommonMark profile | [解析结果](#解析结果不符合预期) |
| HTML 被转义 | 使用了安全渲染入口 | [raw HTML](#raw-html-变成转义文本) |
| 中文或 emoji 位置偏移 | 混用了 UTF-8 byte 与 UTF-16 offset | [位置偏移](#中文或-emoji-后的位置偏移) |
| `LimitExceededException` | 输入或操作超过安全预算 | [错误与限制](#错误限制和取消) |
| dialect 注册失败 | ID、冲突、capability 或 SemVer 无效 | [扩展](#扩展) |

## 安装与运行

### `cjpm` 找不到 `markdown`

`cjpm.toml` 的 path 必须指向直接包含本仓库 `cjpm.toml` 的目录，并且必须是实际路径：

```toml
[dependencies]
  "markdown" = { path = "/absolute/path/to/markdown", output-type = "static" }
```

manifest 不展开 `$HOME`、`${MARKDOWN_PATH}` 或 `~`。先用绝对路径排除配置问题。

### 构建成功但没有程序输出

先构建，再显式运行已构建程序：

```sh
cangjie_env
cjpm build
cjpm run --skip-build
```

### 出现 native scanner 链接错误

默认根库使用纯仓颉 scanner，不需要 C 编译器或 native archive。只有显式导入
`markdown.native.NativeLineScanner` 并给 engine 注入 accelerator 的工程才需要链接平台产物。
删除该显式加速配置，或按目标平台构建并链接对应 archive。不要把 benchmark driver 的
native 配置复制到普通应用。

## 解析结果不符合预期

### 表格、任务列表或删除线没有解析

默认 profile 是 CommonMark 0.31.2。显式使用 GFM：

```cangjie
Markdown.toSafeHtml(source, profile: MarkdownProfile.gfm029())
```

### raw HTML 变成转义文本

这是 `Markdown.toSafeHtml` 的安全默认行为。只有输入可信并且确实需要规范兼容输出时，
才使用 `Markdown.toSpecHtml` 或显式的 `HtmlOptions.specCompatible()`。

### `HeadingNodeView` 不能直接读取源码范围

typed view 的通用 AST 字段位于其 `node`：

```cangjie
let span = heading.node.span.getOrThrow()
```

### 中文或 emoji 后的位置偏移

`SourceSpan` 使用 UTF-8 byte offset，LSP 使用 UTF-16 code unit。不要直接混用：

```cangjie
let position = result.source.utf16Position(span.startByte)
```

反向转换和终端显示位置见[源码位置](source-position.md)。

## 错误、限制和取消

### `parse` 抛出 `LimitExceededException`

先读取 `MarkdownException.code`、`phase` 和可选 `span`。不要解析英文消息。确认输入是否
超过 `ParseLimits.safe()` 的输入、行、节点、literal、引用、URL、表格列或输出上限。

只在可信输入中考虑 `ParseLimits.trusted()`。服务器场景应构造更严格的 `ParseLimits`，
而不是关闭限制。

### `tryParse` 返回空文档

这是既定契约。`tryParse` 捕获结构化失败并返回 `isComplete == false`、空 `Document`
和 `errors`；它不提供已完成的 AST 前缀。

### 操作在开始前就被取消

确认是否复用了已经调用 `cancel()` 的 `CancellationSource`。每个独立操作应使用新的 source，
或使用 `CancellationToken.none()`。

## 扩展

### dialect 构建或注册失败

检查以下项目：

- manifest、syntax 和 renderer rule 的 extension ID 一致；
- rule ID 在 extension 内唯一；
- opener/closer 不为空，优先级和冲突策略明确；
- manifest capability 覆盖 renderer 或 callback 实际行为；
- extension、dialect 和 schema version 使用合法 SemVer。

用 [`MarkdownExtensionTestKit`](extension-tck.md) 验证第三方扩展，不要只测试正常输入。

## Artifact cache miss

artifact 会绑定输入、profile、dialect、renderer 和 schema 身份。源文本、配置或 fingerprint
不同都应返回显式 `CacheMiss`。不要绕过身份检查复用旧 AST；重新解析并写入新 artifact。

## 报告问题

公开缺陷请提交 GitHub issue，并包含：

- `cjpm.toml` 中的 markdown 版本或 commit；
- `cjc --version`；
- 最小 Markdown 输入；
- 使用的 profile、limits、renderer options 和 extension manifest；
- 实际输出、期望输出和完整结构化错误；
- 可重复执行的命令。

安全漏洞请使用
[Private Vulnerability Reporting](https://github.com/lIlIIlIll/markdown/security/advisories/new)，
不要先公开披露。

---

[← 文档首页](README.md) · [错误与能力](errors-and-capabilities.md) · [安全指南](security.md)
