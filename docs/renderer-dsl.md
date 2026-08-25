# Renderer DSL

`RendererRule` maps an extension/local kind to a validated HTML tag/class,
canonical Markdown opener/closer, and plain-text prefix/suffix. Custom nodes
render through the same escaping, cancellation, node/output budgets, source-map
and Sink error path as built-in nodes. Missing required coverage fails dialect
compilation.

Runtime fallback is explicit: `Error` (default), `RenderChildren`,
`RenderLiteral`, `Drop`, or `CustomFallback`. A custom HTML fallback returns
only explicit `TrustedHtml`; missing fallback code fails rather than silently
dropping content. `engine.htmlRenderer()` installs the compiled manifest/rule
set so those policies are observable.

Structured attributes declare Text, LinkUri, or ImageUri kinds and obtain
values from fixed configuration, typed payload parameters, or payload literal.
Tag/class/attribute names are validated; event/style attributes are rejected;
`href`/`src` require their URI kind; URI values pass the same policy as built-in
links/images. Payload-literal and container/line Markdown lowering are explicit.

Ordinary strings are always escaped. `TrustedHtml` has only an explicit `unsafe` factory and does not bypass budgets or cancellation.

Raw HTML sanitization is an independent `HtmlSanitizerPort`; adapter failure is
propagated without falling back to unsanitized input. `AsyncHtmlRenderSession`
adapts bounded rendered output to `Continue`/`Pause`/`Failed` sinks and resumes
without duplicate writes.
