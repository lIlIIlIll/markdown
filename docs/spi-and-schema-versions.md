# SPI 与 schema 版本

扩展语义版本、实现身份、SPI 和 wire schema 是不同契约。不要用 implementation version
替代 SemVer，也不要假定未知 schema 可以向前兼容。

| 契约 | 当前版本 | 不匹配行为 |
| --- | --- | --- |
| Extension SPI | `3` | dialect 编译失败 |
| Dialect DSL schema | `1` | descriptor 拒绝加载 |
| Syntax DSL schema | `1` | descriptor 拒绝加载 |
| Parser plan | `5` | parse artifact cache miss |
| Binary artifact | schema `3` | 拒绝或 cache miss，不猜测恢复 |
| Public API snapshot | `v0.10` | `check_public_api.py` 报告差异 |

`ExtensionManifest.semanticVersion` 必须是完整 SemVer，并按 prerelease 规则比较。
`implementationVersion` 是构建身份；它可以参与缓存/实现身份，但不参与 dependency 的
SemVer 排序。

parser plan 的 descriptor、engine fingerprint 和 `MarkdownParseArtifact.parserPlanVersion`
使用同一版本常量。schema 3 表示 wire layout，不代替 parser plan 5。Code Groups 1.0、
结构化 literal 的引用隔离与完整 payload 验证使用 plan 5；旧配置缓存直接失效。

## Fingerprint 边界

dialect fingerprint 绑定 base profile、dialect identity、extension identity、规范化 rules
和语义相关顺序。engine fingerprint 额外绑定影响解析结果的 limits。renderer policy 不会
错误地混入 parse-only cache key。
AST transform 和 document analysis 的 ID、版本、优先级及对应能力参与 fingerprint。
analysis 在绑定后执行，返回诊断；它不能替代 transform 修改 AST。

canonical descriptor 使用长度前缀编码，不使用未转义的 `@`、`|` 或 `:` 拼接，因此字段中
包含 delimiter 或 Unicode 不会造成序列化歧义。

## 升级规则

- 新增可选字段且旧 reader 可安全忽略时，才可保持 schema version。
- 改变 normalized rule、ordering 或默认语义时，必须更新 schema 或语义版本。
- 不支持的 SPI、未知字段、callback descriptor 和无界规则都 fail closed。
- artifact identity 不匹配只能视为 cache miss；不得在来源不一致时复用 AST。

当前版本是 breaking pre-GA 0.10，公开 API 以
[`api/public-api-v0.10.txt`](../api/public-api-v0.10.txt)为准。
