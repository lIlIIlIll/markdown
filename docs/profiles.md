# 选择 Markdown profile

Profile 固定 parser 的标准版本和扩展集合。选择 profile 后，同一输入在相同 dialect
和 limits 下得到确定的 AST 和 renderer 行为。

## 可用 profile

| Factory | ID | 行为 |
| --- | --- | --- |
| `commonMark0312()` | `commonmark-0.31.2` | CommonMark 0.31.2 |
| `commonMark()` | `commonmark-0.31.2` | 固定便利名称 |
| `gfm029()` | `gfm-0.29` | 官方 GFM 0.29 profile，包括 tagfilter |
| `gfmModernV1()` | `gfm-modern-v1` | CommonMark 0.31.2 + tables、tasks、strikethrough、extended autolinks、tagfilter |
| `gfm()` | `gfm-modern-v1` | 固定便利名称 |
| `custom(id, version)` | 调用者提供 | 自定义 identity；语法由 dialect 决定 |

## 配置 engine

```cangjie
let engine = MarkdownEngine.builder()
    .profile(MarkdownProfile.gfm029())
    .build()
```

需要官方语料兼容时，选择带明确规范版本的 factory。应用需要稳定的现代 GFM 组合时，
选择 `gfmModernV1()`。

`MarkdownDialectBuilder.base(profile)` 也会设置 base profile。把 dialect 传给 engine
后，dialect profile 覆盖 builder 之前的 profile。

## Renderer compatibility

Parser profile 和 HTML policy 是两个选择：

- `MarkdownProfile.gfm029()` 控制 parser。
- `HtmlOptions.gfmCompatible()` 控制 GFM HTML compatibility。
- `HtmlOptions.safe()` 控制不可信输出。

使用 GFM parser 不会自动启用 raw HTML pass-through。

## 版本规则

`commonMark()` 在未来 1.x 保持 CommonMark 0.31.2。`gfm()` 在未来 1.x 保持
`gfm-modern-v1`。新的标准语义需要新的 profile ID。

规范测试结果见 [CommonMark report](reports/commonmark-0.31.2-conformance.md) 和
[GFM report](reports/gfm-0.29-conformance.md)。

## 下一步

- [Core API](api/core.md)
- [安全 HTML](security.md)
- [版本与兼容性](versioning-and-compatibility.md)

