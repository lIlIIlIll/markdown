# Syntax DSL

Syntax DSL 只表达边界明确、资源有上限的语法。它不接受任意 regex、递归脚本或无界
backtracking。

## 行内语法

```cangjie
let mark = InlineSyntax
    .define("docs", "mark")
    .delimiter("==")
    .content(true)
    .nesting(false)
    .maximumDelimiterLength(2)
    .maximumLookahead(4096)
    .priority(100)
    .conflictGroup("emphasis-like")
```

`delimiter(opener, closer)` 定义成对边界；只传一个值时 opener 与 closer 相同。
`token(value)` 定义单 token 语法，`metadataSuffix` 定义后缀 metadata。

行内 rule 还可配置 CommonMark 或 literal-backslash escaping、flanking、children、可见内容、
嵌套、delimiter/lookahead 上限、priority、conflict group、resource cost 和 typed emitter。

## 块语法

```cangjie
let note = BlockSyntax
    .define("docs", "container")
    .opener(":::")
    .closer(":::")
    .content(BlockContentMode.Markdown)
    .parameter("title", SyntaxParameterType.StringValue)
    .maximumBlockBytes(1048576)
    .maximumCaptureLength(4096)
    .nesting(true)
```

`content(Markdown)` 解析正文 children；`Literal` 保留原文。`linePrefix(prefix)` 创建单行
语法，`documentStartOnly()` 只允许在文档开头匹配。默认 local kind 来自 opener 后的第一
个单词；`kindFromFirstWord(false)` 使用固定 rule ID。

参数支持 `StringValue`、`IntegerValue`、`BooleanValue` 和 `IdentifierValue`。quoted value
和 backslash escape 只解码一次。unknown、duplicate、required missing、unclosed 或类型
错误产生 `MD3003_INVALID_EXTENSION_PARAMETER`。

## AST、优先级和恢复

匹配结果生成 custom node。`SyntaxPayload` 保留 raw 参数、typed values、literal body、
nested children summary、extension/rule identity 和精确 SourceSpan。renderer 和 formatter
不需要重新解析 opener。

未知语法保持普通文本。注册 rule 的未闭合输入产生
`MD3002_UNCLOSED_EXTENSION`，解析器继续恢复后续内容。

内置语法使用静态 dispatch；Syntax DSL 按 opener 首 byte 调度。多个候选由编译后的 phase、
priority、registration order 和 conflict group 决定。冲突规则在 dialect 编译时拒绝。

DSL 无法表达的有限行内语法可使用 `InlineParserSpi`。SPI 必须声明非空、无重复的
`triggerBytes`、maximum lookahead、priority 和 deterministic。runtime 校验 consumed
offset、identity 和 span，并把 callback 错误包装成 `ExtensionFailureException`。

完整字段见 [Extensions API](api/extensions.md)。
