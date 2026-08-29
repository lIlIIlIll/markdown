# Dialect DSL

`MarkdownDialect` 把 profile、extension manifest、syntax、renderer 和 processor 编译成
不可变执行计划。方言适合应用、协议或文档系统复用同一套 Markdown 语义。

## 创建方言

```cangjie
import markdown.core.*
import markdown.extensions.*

let dialect = MarkdownDialect
    .define("acme-docs", "1.0.0")
    .base(MarkdownProfile.GfmModernV1)
    .enable(manifest)
    .inline(inlineRule)
    .block(blockRule)
    .renderer(rendererRule)
    .build()

let engine = MarkdownEngine.builder().dialect(dialect).build()
```

可选的 `.parserOptions(options)` 和 `.limits(limits)` 也会影响结果。engine builder 上显式
设置的 limit 优先于 dialect limit。

## 编译时校验

`build()` 会验证：

- dialect、extension 和 rule identity；
- 完整 SemVer、SPI version 和 profile support；
- dependencies、minimum version、conflicts 和 dependency cycle；
- delimiter、opener、lookahead、capture 和 block byte 上限；
- priority、registration order 和 conflict group；
- renderer coverage、HTML tag/class/attribute 和 URI kind；
- capability 声明与实际注册项；
- SPI 和 processor 的确定性约束。

非法方言不会生成“部分可用”的 engine。编译失败会抛出带 extension、phase 和 rule
上下文的 `ExtensionFailureException` 或对应 `MarkdownException`。

## 禁用扩展

```cangjie
let dialect = MarkdownDialect
    .define("without-math", "1.0.0")
    .enable(first)
    .enable(second)
    .disable("math")
    .build()
```

`disable` 在编译前删除该 extension 的所有注册内容。它不是解析时开关，因此关闭能力的
基础路径不会继续执行无用 callback。

## Fingerprint

编译结果使用 canonical length-prefixed encoding 计算 SHA-256 fingerprint。base profile、
dialect identity、extension identity、规范化 rule 和语义相关顺序都会参与 fingerprint；
内部 hash table 或 dispatch 布局不会参与。

engine fingerprint 还绑定影响结果的 parser limits。不同语义配置不能共享 parse
artifact；声明上无序的注册内容不会因输入顺序不同产生不必要变化。

## 官方扩展

`OfficialExtensions.p1Dialect()` 提供默认关闭的 Footnotes、Front Matter、Math、Definition
Lists、Heading IDs 和 Smart Punctuation 组合。它们不会被 CommonMark/GFM convenience
profile 自动启用。使用 `OfficialExtensions.catalog()` 查询版本与启用矩阵。

完整 builder 方法和默认值见 [Extensions API](api/extensions.md)。

