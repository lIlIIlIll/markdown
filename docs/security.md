# 安全 HTML 与 URI

处理不可信 Markdown 时，使用 `Markdown.toSafeHtml` 或
`HtmlOptions.safe()`。

## 安全默认值

`HtmlOptions.safe()`：

- 转义 text、attribute 和 raw HTML
- 拒绝 `javascript:`、`vbscript:`、`file:` 和未允许 scheme
- 允许 relative、HTTP、HTTPS 和 mailto link
- 允许 relative image
- 默认拒绝 remote image 和 data image
- 验证扩展 tag、class 和 attribute
- 禁止 event handler 和 style attribute
- 执行 cancellation、rendered-node 和 output-byte 限制

```cangjie
let html = Markdown.toSafeHtml(
    "<script>alert(1)</script> [x](javascript:alert(1))"
)
```

## Raw HTML

`specCompatible()` 和 `gfmCompatible()` 允许规范要求的 raw HTML。它们不是
sanitizer。

需要宿主 sanitizer 时，实现 `HtmlSanitizerPort`，并配置
`RawHtmlPolicyKind.Sanitize`。adapter 失败会终止 render，不会输出未清理 HTML。

## Link 和 image policy

`LinkUriPolicy` 和 `ImageUriPolicy` 分开配置。不要因为允许远程链接而自动允许远程
图片。

data image allowlist 比较第一个 `;` 之前的完整 media type，大小写不敏感。允许
`image/png` 不会允许 `image/pngx`。

Safe policy 下设置 `target="_blank"` 时，renderer 保证 `rel` 至少包含
`noopener noreferrer`。

## 扩展安全

renderer rule 的 `href` 和 `src` 必须声明 URI attribute kind，并经过同一 URI
policy。普通扩展字符串会被转义。

`TrustedHtml.fromString` 是 unsafe API。它只适用于宿主已经验证的 HTML。

host-code extension 拥有宿主进程权限。`IsolatedPluginRunner` 只定义 IPC contract。
宿主的 `PluginIsolationTransport` 必须建立 OS process、filesystem、network 和 child
process 限制。transport 必须在解码时将 output chunk 写入 `writeOutput`；diagnostic 依次
调用 `beginDiagnostic`、分块 `writeDiagnosticMessage`、逐项 related span/fix 和
`finishDiagnostic`。不能先构造无界 response 或 diagnostic message。

`PluginIsolationPolicy` 分别限制 output、diagnostic 数量、单条 diagnostic message、
diagnostic 聚合字节和完整 response 字节。达到任一上限时，sink 在保留该项之前失败。
这些协议预算不能替代 OS sandbox，两者都必须配置。

## 资源攻击面

`ParseLimits.safe()` 限制 input、line、depth、AST node、reference、table column、
URL、literal、output、extension capture 和 lookahead。`OperationBudget` 限制扫描、
delimiter、callback、transform 和 render work。

不要对不可信输入使用无限外部 timeout。通过 `CancellationToken` 实现宿主 deadline。

## 报告漏洞

仓库启用了 GitHub Private Vulnerability Reporting。通过
[私密报告表单](https://github.com/lIlIIlIll/markdown/security/advisories/new)
提交漏洞。不要在公开 issue 中披露未修复漏洞。

请附带版本、profile、最小输入、配置、输出或资源使用和复现步骤。维护策略见
[`SECURITY.md`](../SECURITY.md)。
