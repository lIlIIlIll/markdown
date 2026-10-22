package markdown.engine

import markdown.render.{CodeGroupHtmlOptions, ExtensionRendererFallback, HtmlOptions, HtmlRenderer, HtmlSanitizerPort, 
    RawHtmlHandlerPort, RichContentPreparation}

extend MarkdownEngine {
    /**
     * 按 engine 的 dialect rules 创建 renderer，并继承 `maximumOutputBytes`。
     * @param options HTML 和 URI 策略，默认 `HtmlOptions.safe()`。
     * @param sanitizer Sanitize policy 使用的 sanitizer。
     * @param fallbacks custom node 的 fallback 列表。
     * @param rawHtmlHandler CustomHandler 使用的 handler。
     * @param codeGroups 可选代码组渐进增强数据和复制上限。
     * @param prepared 仅属于目标 Document revision 的已校验富内容注解。
     * @return 配置好的 `HtmlRenderer`。
     */
    public func htmlRenderer(options!: HtmlOptions = HtmlOptions.safe(), sanitizer!: ?HtmlSanitizerPort = None,
        fallbacks!: Array<ExtensionRendererFallback> = [], rawHtmlHandler!: ?RawHtmlHandlerPort = None,
        codeGroups!: CodeGroupHtmlOptions = CodeGroupHtmlOptions.defaults(), prepared!: ?RichContentPreparation = None): HtmlRenderer {
        HtmlRenderer(options: options, extensionRules: dialect.rendererRules.toArray(), sanitizer: sanitizer,
            extensionManifests: dialect.manifests.toArray(), extensionFallbacks: fallbacks,
            rawHtmlHandler: rawHtmlHandler, maximumOutputBytes: Some(limits.maximumOutputBytes), codeGroups: codeGroups,
            prepared: prepared)
    }
}
