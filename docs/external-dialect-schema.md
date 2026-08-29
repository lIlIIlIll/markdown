# External dialect schema v1

外部 JSON/YAML descriptor 是纯数据格式。它适合配置固定边界的 syntax 和 renderer，不能
携带 callback、脚本、regex 或任意对象。

## 顶层字段

必需字段是 `schemaVersion`、`id`、`version` 和 `baseProfile`。可选数组是
`inlineRules`、`blockRules` 和 `rendererRules`。

## Rule 编码

```text
Inline:
ruleId|opener|closer|maxLookahead|parseChildren|allowNesting

Block:
ruleId|opener|closer|content|maxBlockBytes|maxCapture|allowNesting

Renderer:
kindId|htmlTag|classToken|markdownOpener|markdownCloser
```

`content` 只能是 `markdown` 或 `literal`。所有 delimiter、lookahead、capture 和 block
size 都必须是有限值。

## 拒绝规则

loader 会拒绝 unknown/duplicate field、不支持的 schema/profile、object/callback、错误的
rule field 数量、无界或非法数值、YAML tab、不受支持的 YAML 结构，以及非法 identity、
SemVer、opener、tag 或 class。

解析失败不会生成降级方言。外部 implementation digest、规范化 descriptor 和 rule 顺序
会进入 compiled dialect fingerprint。

data-only descriptor 不执行配置内容，但生成的 HTML 仍必须经过 escaping、URI policy、
output budget 和 Safe policy。需要执行宿主逻辑时，请实现显式 SPI，并按
[扩展模型](extensions.md)审计权限。

完整 typed builder API 见 [Extensions API](api/extensions.md)。
