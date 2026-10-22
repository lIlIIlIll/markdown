# 版本与兼容性

当前开发版本为 `0.9.2` breaking pre-GA，使用官方仓颉 STS `1.2.0`。本版本将公开接口与
实现迁入真实领域包，删除旧门面、转导和兼容构建路径。升级步骤见
[0.9.2 迁移](migration-0.9.2.md)。已发布版本及其产物以 GitHub Release 为准。

## 当前版本政策

GA 前允许明确记录的破坏性变更，包括 API、导入路径、artifact 和缓存身份。
本仓库只维护当前接口与格式，不提供历史 API 别名、旧 schema reader 或兼容构建模式。

公开接口变更必须同步更新：

1. `api/public-api.txt` 当前声明快照。
2. 迁移说明和对应 API 文档。
3. 调用方及行为测试。
4. 适用的 release gate 和绑定真实源码的性能证据。

删除兼容代码不会取消 CommonMark/GFM profile 语义、安全 HTML、资源限制、来源位置、
所有权和取消契约。可选 native scanner 与 Node 后端继续保持显式启用和有界回退。

历史声明通过对应 tag 查阅，例如
[v0.9.1 API snapshot](https://github.com/lIlIIlIll/markdown/blob/v0.9.1/api/public-api-v0.9.1.txt)。
已发布 tag 和证据保留原始身份，不能用新源码重绑旧测量。

## Extension SemVer

manifest semantic version 和 dependency minimum 使用完整 SemVer：

`major.minor.patch[-prerelease][+build]`

- prerelease 低于对应 release。
- numeric prerelease 按数值比较。
- build metadata 不影响 precedence。
- incomplete version、numeric leading zero、空 identifier 和 overflow 会失败。

implementation version 是 opaque build identity，不参与 SemVer 排序。
不支持的 SPI 和 wire schema 在配置或加载时拒绝，不猜测恢复。

## Profile 版本

使用带明确版本的 factory：`commonMark0312()`、`gfm029()` 或 `gfmModernV1()`。
它们分别选择 CommonMark 0.31.2、GFM 0.29 和仓库版本化 modern GFM。
新标准行为使用新 profile identity，完整差异见 [Profile 指南](profiles.md)。

## 检查公开声明

```sh
python3 scripts/check_public_api.py
```

该命令比较当前源码声明与 `api/public-api.txt`。确认本次 API 变更与迁移说明一致后，
使用 `--update` 更新快照，再运行检查。快照记录当前接口，不构成跨版本兼容承诺。
