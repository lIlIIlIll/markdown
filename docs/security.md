# 安全 HTML 与 URI

处理不可信 Markdown 时，使用 `engine.renderHtml(source)` 的默认安全策略，或显式配置
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
import markdown.engine.MarkdownEngine

let engine = MarkdownEngine.builder().build()
let html = engine.renderHtml(
    "<script>alert(1)</script> [x](javascript:alert(1))"
).html
```

## Raw HTML

`specCompatible()` 和 `gfmCompatible()` 允许规范要求的 raw HTML。它们是 `unsafe`
factory，不是 sanitizer：

```cangjie
let options = unsafe { HtmlOptions.specCompatible() }
```

普通 `HtmlOptions` 构造器拒绝 `RawHtmlPolicyKind.PassThrough`，避免安全配置意外降级。

需要宿主 sanitizer 时，实现 `HtmlSanitizerPort`，并配置
`RawHtmlPolicyKind.Sanitize`。adapter 失败会终止 render，不会输出未清理 HTML。
sanitizer 必须提供稳定且非空的 `identity`。

需要完全自定义 raw HTML 降低时，实现 `RawHtmlHandlerPort`，并配置
`RawHtmlPolicyKind.CustomHandler`。handler 返回 `TrustedHtml`，因此宿主负责验证输出。
缺少 handler 时 renderer 失败，不会退回 pass-through。

### 用固定安全标记替换 raw HTML

以下 handler 丢弃 raw literal，仅返回宿主写死的可信标记。使用 `CustomHandler` 时需要把
实例交给 renderer，库不会替宿主判断任意动态 HTML 是否安全：

```cangjie
import markdown.engine.MarkdownEngine
import markdown.render.*

public class MyRawHtmlHandler <: RawHtmlHandlerPort {
    public prop identity: String {
        get() { "my-raw-html-handler-v1" }
    }

    public func renderRawHtml(_: String, block: Bool): TrustedHtml {
        let replacement = if (block) {
            "<div>raw HTML removed</div>"
        } else {
            "<span>raw HTML removed</span>"
        }
        unsafe { TrustedHtml.fromString(replacement) }
    }
}

let engine = MarkdownEngine.builder().build()
let document = engine.parse("<script>untrusted</script>").document
let options = HtmlOptions(
    HtmlPolicy.safe(), RawHtmlPolicyKind.CustomHandler, LinkUriPolicy.safe(), ImageUriPolicy.safe()
)
let renderer = engine.htmlRenderer(options: options, rawHtmlHandler: Some(MyRawHtmlHandler()))
let html = renderer.render(document)
```

只有宿主已经验证的内容才能进入 `TrustedHtml.fromString`。TrustedHtml 仍受 output budget、
取消与 sink 错误约束。sanitizer、raw HTML handler 和 external-link rewriter 的 identity
必须稳定且非空，并参与 renderer fingerprint；实现语义改变时同步更新 identity。

## Link 和 image policy

`LinkUriPolicy` 和 `ImageUriPolicy` 分开配置。不要因为允许远程链接而自动允许远程
图片。

data image allowlist 比较第一个 `;` 之前的完整 media type，大小写不敏感。允许
`image/png` 不会允许 `image/pngx`。

Safe policy 下设置 `target="_blank"` 时，renderer 保证 `rel` 至少包含
`noopener noreferrer`。

`ExternalLinkRewriterPort` 只重写 HTTP 和 HTTPS destination。renderer 会对重写结果
重新执行 URI policy 和 escaping。rewriter 返回 `javascript:` 等危险 scheme 时，输出
不会包含 `href`。

### 显式允许 data image

默认安全策略拒绝 remote/data image。应用需要 PNG/JPEG data image 时，单独启用它，
保留 remote image 关闭：

```cangjie
import markdown.render.*

let options = HtmlOptions(
    HtmlPolicy.safe(),
    RawHtmlPolicyKind.Escape,
    LinkUriPolicy.safe(),
    ImageUriPolicy(
        true, false, true,
        allowedDataMimeTypes: ["image/png", "image/jpeg"]
    ),
    externalLinkRel: "noopener noreferrer",
    externalLinkTarget: "_blank"
)
```

### 重写外部链接

端口只接收已经解析的 HTTP(S) destination。下面将一个固定旧地址替换为新地址，其余地址
保留原义。relative URL 与 mailto 不经过此端口：

```cangjie
import markdown.render.*

public class Redirector <: ExternalLinkRewriterPort {
    public prop identity: String {
        get() { "docs-redirector-v1" }
    }

    public func rewriteExternalLink(uri: String): String {
        if (uri == "https://example.test/old") {
            "https://example.test/new"
        } else {
            uri
        }
    }
}

let options = HtmlOptions(
    HtmlPolicy.safe(), RawHtmlPolicyKind.Escape, LinkUriPolicy.safe(), ImageUriPolicy.safe(),
    rewriteExternalLinks: Some(Redirector())
)
```

重写后的 URI 仍执行 policy 与 attribute escaping。需要把原 URI 放入另一个 URL 的 query
参数时，由宿主按 URL 规则编码参数，不直接拼接未编码的用户内容。

## 扩展安全

renderer rule 的 `href` 和 `src` 必须声明 URI attribute kind，并经过同一 URI
policy。普通扩展字符串会被转义。

`TrustedHtml.fromString` 是 unsafe API。它只适用于宿主已经验证的 HTML。

host-code extension 拥有宿主进程权限。`IsolatedPluginRunner` 只定义 IPC contract。
宿主的 `PluginIsolationTransport` 必须建立 OS process、filesystem、network 和 child
process 限制。transport 必须在解码时将 output chunk 写入 `writeOutput`；diagnostic 依次
调用 `beginDiagnostic`、分块 `writeDiagnosticMessage`、逐项 related span/fix 和
`finishDiagnostic`。响应身份字段必须分块写入 `writeProtocolVersion`、`writeExtensionId` 和
`writeImplementationVersion`。不能先构造无界身份字段、response 或 diagnostic message。

`PluginIsolationPolicy` 分别限制 output、diagnostic 数量、单条 diagnostic message、
diagnostic 聚合字节和完整 response 字节。达到任一上限时，sink 在保留该项之前失败。
这些协议预算不能替代 OS sandbox，两者都必须配置。

## 资源攻击面

`ParseLimits.safe()` 限制 input、line、depth、AST node、reference、table column、
URL、literal、output、extension capture 和 lookahead。`OperationBudget` 限制扫描、
delimiter、callback、transform 和 render work。

`maximumAstNodes` 只统计实际构造的 AST 节点。fused HTML path 不创建 AST，因此该限制
在 fused path 中的观察值为零。fused path 仍执行 input、line、literal、output、
cancellation 和 operation budget。需要 AST node limit 参与执行结果时，使用
`HtmlExecutionMode.FullAst`。

Renderer 在 escape、URI encoding 和 GFM tagfilter 输出期间分段检查 output limit。
GFM tagfilter 只对规范定义的短标签名做有界、无切片的 ASCII 比较；超长 tag name 不会在
预算检查前创建同等大小的临时 lowercase String。denylist 名称只有在后继为输入结束、
HTML 空白、`/` 或 `>` 时成立，不会误过滤 `<script-x>` 一类自定义标签。
内建 text、attribute、URI 和 fused source range 同样在 substring 创建前消费固定上限与
operation budget。
Renderer 在入口、退出及长扫描期间按固定上界检查 cancellation，取消后不再写 Sink。
宿主 sanitizer、raw HTML handler 和 extension fallback 可能在返回前自行分配完整
String。对不可信插件，还必须在 adapter 或进程边界实施输入和内存限制。

不要对不可信输入使用无限外部 timeout。通过 `CancellationToken` 实现宿主 deadline。

## 报告漏洞

仓库启用了 GitHub Private Vulnerability Reporting。通过
[私密报告表单](https://github.com/lIlIIlIll/markdown/security/advisories/new)
提交漏洞。不要在公开 issue 中披露未修复漏洞。

请附带版本、profile、最小输入、配置、输出或资源使用和复现步骤。维护策略见
[`SECURITY.md`](../SECURITY.md)。
