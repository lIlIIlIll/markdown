# 贡献指南

感谢你改进 `markdown`。本仓库接受 parser、renderer、扩展、编辑器工具、文档和测试修改。
提交前请确认改动属于当前 PRD 范围，并保留公开 API、SourceSpan、资源限制和安全默认值。

## 准备环境

仓库使用仓颉 1.1 SDK。进入仓库后启用环境：

```sh
cangjie_env
cjpm check
```

不要把 `target`、`build-script-cache`、`.agent`、`.agents`、`.codex` 或本机 native
产物加入源码归档。

## 修改原则

- 解析行为、renderer 输出和文档必须一致。
- 新增公开 API 时同步更新 `api/public-api-v0.9.txt` 和对应 API 文档。
- parser 创建的每个节点都必须经过统一 node limit；literal 必须执行累计 byte limit。
- extension 必须声明有限 lookahead/capture，并提供 renderer 或明确 fallback。
- Safe HTML 默认值不能因便利入口或扩展而绕过。
- 性能修改必须保留完整 AST、NodeId、SourceSpan 和 ParseResult 契约。

## 测试

先运行与改动直接相关的测试，再运行完整门槛：

```sh
scripts/check_format.sh
python3 scripts/check_docs.py
python3 scripts/check_public_api.py
cjpm check
cjpm build
cjpm test --no-color --no-progress
```

修改 quickstart 或公开用法后，再运行：

```sh
cd examples/quickstart
cjpm build
cjpm run --skip-build
```

修改 release evidence、native scanner、benchmark、spec corpus 或发布路径时，运行
`scripts/release_gate.sh`。完整 gate 还包含 CommonMark/GFM 语料、CLI smoke、consumer
example、fuzz smoke、benchmark smoke、bundle 和 evidence 校验。

普通 Git checkout 会将 release evidence 绑定到 `HEAD`。GitButler 等使用合成
workspace commit 的环境必须将 `MARKDOWN_RELEASE_COMMIT` 设为可推送分支 tip：

```sh
MARKDOWN_RELEASE_COMMIT=<branch-tip-sha> scripts/release_gate.sh
```

gate 只接受可达提交，并要求该提交的完整 Git tree 与干净 workspace tree 完全相同；
因此不能用旧提交或只匹配产品源码子集的提交冒充受测版本。

门禁会在 `/tmp` 中按不可变 commit 获取 cmark 0.31.1、cmark-gfm 0.29.0.gfm.13 和
commonmark.js 0.31.2。设置 `MARKDOWN_DIFFERENTIAL_ROOT` 可改用预置缓存；目录存在但
commit 不匹配时门禁会拒绝覆盖并失败。

## 扩展贡献

使用 `MarkdownExtensionTestKit.verify` 验证共享契约，并增加语法特有的合法、非法、嵌套、
冲突、limits、cancellation、renderer 和 SourceSpan 用例。host-code extension 拥有宿主进程
权限；不要把 TCK 结果描述为沙箱证明。

## 文档

中文开发者文档是当前维护源。新增页面时：

- 从 [开发者文档索引](docs/README.md)建立入口；
- API 页写明 import、签名、默认值、失败语义和可运行示例；
- 不手工复制 benchmark 当前值，以 `release-evidence.json` 为唯一来源；
- 运行 `python3 scripts/check_docs.py` 检查链接、代码 fence 和核心 API 覆盖。

## 安全问题

不要公开披露未修复漏洞。按 [安全策略](SECURITY.md)使用 GitHub Private Vulnerability
Reporting。
