# 贡献指南

感谢你改进 `markdown`。本仓库接受 parser、renderer、扩展、编辑器工具、文档和测试修改。
提交前请确认改动属于当前 PRD 范围，并保留 AST、SourceSpan、资源限制和安全默认值。
当前开发版本为 0.9.2 breaking pre-GA；公开接口调整需同步迁移说明，不增加旧接口转导。

## 准备环境

仓库使用官方仓颉 STS 1.2.0 SDK。将 SDK 安装到下面的目录，或按实际安装目录调整变量，再启用环境：

```sh
export CANGJIE_SDK_ROOT="$HOME/cangjie_sdk/sts1.2.0"
cangjie_env
cjc -v
cjpm check
```

不要把 `target`、`build-script-cache`、`.agent`、`.agents`、`.codex` 或本机 native
产物加入源码归档。

## 修改原则

- 解析行为、renderer 输出和文档必须一致。
- 调整公开 API 时同步更新 `api/public-api.txt`、源码 API 注释和迁移说明。
- 按领域放置类型与实现，依赖保持单向；根包不公开声明或转导。共享内部 helper 使用最小可见性。
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

修改 parser、AST 分配、输入路径、native scanner 或 benchmark harness 时，还必须刷新并
验证同语言 benchmark：

```sh
python3 benchmarks/compare_markdown4cj.py \
  --source target/same-language-benchmark/comparator-sources/markdown4cj.bundle \
  --commonmark4cj-source target/same-language-benchmark/comparator-sources/commonmark4cj.bundle \
  --product-source target/same-language-benchmark/product-source/markdown.bundle \
  --binary-root target/same-language-benchmark/binaries \
  --sdk-archive target/same-language-benchmark/toolchain/cangjie-sdk-linux-x64-1.2.0.tar.gz \
  --verify-report docs/reports/markdown4cj-comparison-raw.json \
  --markdown-report docs/reports/markdown4cj-comparison.md \
  --require-current-product
```

这些路径是 canonical job 保留并上传的 evidence；如果本地尚未生成它们，请按
[`benchmarks/README.md`](benchmarks/README.md) 的 canonical measurement 流程构建，不能用
当前 checkout、`PATH` 工具或手写 digest 代替 retained input。

`Same-language benchmark (sts-1.2.0)` 会在每个 PR 上重新测量固定的
`markdown4cj` CommonMark parse-only 子集。计时前，每个语料还必须通过 exact spec-HTML
byte length 和 SHA-256 对比。门禁要求共享行为 `12/12`、几何平均加速至少 `1.20×`、
任何单语料回退不超过 `10%`，并且最大峰值 RSS 不超过 comparator 的 `1.20×`。
schema v6 同时绑定 SDK archive、target、工具、build 命令、源码和 binary。verifier 从
retained product、markdown4cj 和 commonmark4cj Git objects 重算源码身份，再使用保留的
toolchain/runtime 在 fresh root 可复现重建 driver、CLI、comparator 与 DSO，并逐字节比较
retained outputs；旧祖先冒名、nested/indirect Git source、replace refs、工具或 binary
漂移都会 fail closed。该 job 是
`main` 的 required check，不能以本地 smoke 或手工编辑 report 代替。

普通 Git checkout 会将 release evidence 绑定到 `HEAD`。GitButler 等使用合成
workspace commit 的环境必须将 `MARKDOWN_RELEASE_COMMIT` 设为可推送分支 tip：

```sh
MARKDOWN_RELEASE_COMMIT=<branch-tip-sha> scripts/release_gate.sh
```

gate 只接受可达提交，并要求该提交的完整 Git tree 与干净 workspace tree 完全相同；
因此不能用旧提交或只匹配产品源码子集的提交冒充受测版本。

门禁按不可变 commit 获取 cmark 0.31.1、cmark-gfm 0.29.0.gfm.13 和
commonmark.js 0.31.2。设置 `MARKDOWN_DIFFERENTIAL_ROOT` 可改用预置缓存；目录存在但
commit 不匹配时门禁会拒绝覆盖并失败。

## 扩展贡献

使用 `MarkdownExtensionTestKit.verify` 验证共享契约，并增加语法特有的合法、非法、嵌套、
冲突、limits、cancellation、renderer 和 SourceSpan 用例。host-code extension 拥有宿主进程
权限；不要把 TCK 结果描述为沙箱证明。

## 文档

中文开发者文档是当前维护源。API reference 从源码注释生成，按声明查询时使用
[HTML 站点](https://liliilill.github.io/markdown/)。签名、默认值和局部契约只在源码维护；
跨 API 流程放入 Cookbook 或主题指南。新增指南时从[开发者文档索引](docs/README.md)建立入口。

为 external audience 可见的公开声明和成员补齐实质性摘要。函数的命名参数说明输入含义、
约束与默认行为，返回值说明结果或状态，失败说明错误条件。字段说明值的含义；不要添加
无意义的返回值标签或重复声明来填充覆盖率。示例按类型或重载共享，注明安全与资源边界。

启用官方 STS 1.2.0 后，从仓库根目录运行：

```sh
python3 scripts/generate_api_docs.py
python3 scripts/check_docs.py
python3 scripts/check_public_api.py
```

生成命令固定使用 [cjdoc v0.7.3](https://github.com/lIlIIlIll/cjdoc/releases/tag/v0.7.3)
发布二进制并校验官方 SHA-256，通过注释、示例和站点检查后输出
`target/api-docs/html/index.html`。完整用法见[API 入口](docs/api.md#本地生成与预览)。
HTML、Doc IR 和检查报告是构建产物，不提交生成站点。PR 执行文档验收，`main` 通过后部署
GitHub Pages；源码链接绑定生成时的提交 SHA。

不要手工复制 benchmark 当前值，以 `release-evidence.json` 为唯一来源。源码注释和
`docs/api.md` 变更也可能影响源码或 benchmark 输入身份，应按适用的 retained-input gate
刷新证据，不能给旧测量替换 digest。

## 安全问题

不要公开披露未修复漏洞。按 [安全策略](SECURITY.md)使用 GitHub Private Vulnerability
Reporting。
