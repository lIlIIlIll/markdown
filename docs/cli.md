# markdown CLI reference

仓库的 `tools/markdown` 提供 parse、render、format、check、explain 和 dialect 命令。

## 构建

```sh
cd tools/markdown
cangjie_env
cjpm build
```

发布门禁会构建并运行 CLI smoke。CLI 不是独立中心仓安装包。

## 命令

| 命令 | 用途 |
| --- | --- |
| `render` | 输出 HTML、text 或 Markdown |
| `parse` | 输出结构化 AST/diagnostic 信息 |
| `format` | 输出或检查 canonical/preserving Markdown |
| `check` | 执行 parse、安全和 lint 检查 |
| `explain` | 解释 byte offset 上的 rule decision |
| `dialect` | 检查或说明 dialect descriptor |

使用 `--profile` 选择 profile。render 使用 `--to` 选择输出。`format --range
start:end` 使用 UTF-8 byte offset。`--max-input-bytes N` 设置真实 parser limit。

当前 CLI 的精确参数以以下命令为准：

```sh
target/release/bin/main --help
```

## Exit codes

| Code | 含义 |
| ---: | --- |
| 0 | 成功 |
| 1 | 输入或 parse 失败 |
| 2 | 参数错误 |
| 3 | `format --check` 发现差异 |
| 4 | security 或 lint 拒绝 |
| 5 | extension 或 dialect 失败 |
| 6 | cancellation 或 budget 耗尽 |
| 7 | internal invariant failure |

`--fault-inject internal` 仅用于 release smoke，验证 exit 7。正常用户输入不应产生
internal invariant failure。

## 服务集成

服务端进程应：

- 使用 `ParseLimits.safe()` 或更严格 limits
- 为每次请求创建 `OperationBudget`
- 将请求 deadline 连接到 `CancellationToken`
- 对不可信输出使用 Safe HTML
- 根据 exit code 或 `MarkdownErrorCode` 分支，不解析英文 message

库 API 参考见 [Core API](api/core.md) 和 [Rendering API](api/rendering.md)。
