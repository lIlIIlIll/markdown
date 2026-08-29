# 错误、诊断和 capabilities

Hard failure 使用 `MarkdownException`。可恢复问题保存在
`ParseResult.diagnostics`。

## 处理异常

```cangjie
try {
    let result = engine.parse(source)
} catch (error: MarkdownException) {
    println("code=${error.code}")
    println("phase=${error.phase}")
}
```

程序应根据 `MarkdownErrorCode` 分支，不要匹配英文 message。

常用错误包括：

- invalid encoding 和 input read failure
- cancellation
- parse limit 和 operation budget
- extension conflict 或 callback failure
- sink 和 render failure
- invalid artifact
- internal invariant violation

`LimitExceededException` 额外记录 limit kind、configured value、observed value、phase、
可选 span 和 extension。

## 诊断

`Diagnostic` 包含 code、severity、message、span、extension ID、rule ID 和可选
`DiagnosticFix`。诊断表示 parser 已恢复的问题；收到诊断不等于 parse 不完整。

`tryParse` 把 hard failure 放入 `ParseResult.errors`，并设置
`isComplete=false`。它不返回已完成 AST 前缀。

## Capability discovery

```cangjie
let capabilities = engine.capabilities()
let execution = engine.executionModels()
```

`EngineCapabilities` 报告：

- profile 和 dialect identity
- extension capabilities
- renderer、DSL、SPI、position 和 serialization version
- native scanner availability 和 enablement
- incremental、lossless、HTML-to-Markdown 等支持范围

`ExecutionModelCapabilities` 报告 buffered stream/chunk、Event、async HTML 和 native
accelerator 的真实语义。

## Explain

```cangjie
let dialect = engine.explainDialect()
let decision = engine.explain(source, byteOffset)
```

`explainDialect` 返回 rule order、renderer coverage、limits 和 fingerprint。
`explain` 返回 offset 上的候选规则、选中规则、priority、tie-break 和 extension。

完整入口见 [Core API](api/core.md) 和 [Editor API](api/editor.md)。

