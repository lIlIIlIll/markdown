# 版本与兼容性

包名、依赖名和产品名均为 `markdown`。当前开发版本是 `0.9.1` breaking pre-GA preview。
issue #10 的模型迁移已经合入，完整交付状态见[0.9.1 迁移](migration-0.9.1.md)。
本版本包含原计划 0.10 的模型调整。虽然发布号为 0.9.1，它仍是 breaking pre-GA，
不承诺兼容 0.9.0 的 API、artifact 或缓存格式。

## 0.9.1 的兼容性范围

0.9.1 通过 `api/public-api-v0.9.1.txt` 记录公开声明，但仍允许在 GA 前做破坏性修改。
每个破坏性修改必须：

1. 更新 API snapshot。
2. 更新迁移指南。
3. 更新测试和文档。
4. 重新运行 release gate。

历史 `api/public-api-v1.txt` 不是当前兼容承诺。正式 1.0 接受后才创建新的 v1
snapshot。

## Extension SemVer

manifest semantic version 和 dependency minimum 使用完整 SemVer：

`major.minor.patch[-prerelease][+build]`

规则：

- prerelease 低于对应 release
- numeric prerelease 按数值比较
- build metadata 不影响 precedence
- incomplete version、numeric leading zero、空 identifier 和 overflow 会失败

implementation version 是 opaque build identity，不参与 SemVer 排序。

## Profile stability

未来 1.x 中：

- `commonMark()` 固定到 `commonmark-0.31.2`
- `gfm()` 固定到 `gfm-modern-v1`

新标准语义使用新 profile ID，不静默改变旧 profile。

## 候选 1.x compatibility surfaces

正式 GA 后计划冻结：

- AST type、field 和 NodeId 语义
- UTF-8 SourceSpan
- profile behavior
- rule order 和 diagnostic code
- HTML 和 canonical Markdown output
- default security policy
- SPI/DSL version
- fingerprint
- artifact schema

当前 0.9.1 不宣称这些已经冻结。

## Event 和 buffered API

0.9 已提供 source-driven Resolved/RawBlock Event API。Event 值不持有 Document 或
NodeRef。

`BufferedInputSession` 仍只累计输入。0.9.1 的 `newAppendSession` 实际在 feed 中交付
结构闭合块，`renderer.newOutputSession` 使用可恢复遍历。旧 buffered 输出实现已移除，
`Pause(n)` 明确报告 UTF-8 前缀确认。迁移规则见[0.9.1 模型迁移](migration-0.9.1.md)。

## 检查 API

```sh
python3 scripts/check_public_api.py
```

命令比较源码声明与 `api/public-api-v0.9.1.txt`。只有明确的 0.9.1 breaking 变更才可使用
`--update` 更新 snapshot。

迁移步骤见 [0.8 到 0.9](migration.md)。
