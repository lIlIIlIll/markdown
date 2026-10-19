# AGENTS.md

## 项目契约

- 以 `README.md`、`CONTRIBUTING.md`、`docs/profiles.md`、`docs/security.md`、当前源码与测试为准；区分内建 CommonMark 0.31.2、GFM 0.29、modern GFM 与自定义 dialect/profile。
- Parser 的 AST、`NodeId`、`SourceSpan`、资源预算以及 renderer/format/query/rewrite/source map 之间必须保持一致。默认安全 HTML 与危险 URI 限制不得被 convenience API、插件或可选后端绕过。
- 原生 scanner 与 Node rich backend 是可选能力；不得把它们变成基础解析的隐式依赖，也不能修改既有安全/资源默认值以隐藏回归。

## 修改与验证

- 行为变更同时检查 parser、renderer 与公开文档；新增公开声明时维护 `api/public-api-v0.10.txt`、API 文档及测试。扩展语法需覆盖交互、优先级、回退及 `MarkdownExtensionTestKit.verify`。
- 按 `CONTRIBUTING.md` 运行适用的 `scripts/check_format.sh`、`python3 scripts/check_docs.py`、`python3 scripts/check_public_api.py`、`cjpm check`、`cjpm build`、`cjpm test --no-color --no-progress`；发布/性能变更遵守独立的 release 和 retained-input gate。
- 基准测试必须有等语义和可复现的比较输入，性能改进不能以丢失 AST、位置、NodeId 或安全检查为代价。区分本机、CI、conformance、benchmark 证据。

## Code Review 专项不变量

- 对解析和 renderer 变更检查内建 profile、custom dialect、混合/嵌套块、CRLF 与分段边界、UTF-8、非法链接、HTML escape、table/task/autolink/tagfilter 的正反和冲突情形，关注可证明的规范差异。
- 对编辑器与 snapshot 检查节点身份、byte/line span、保持原文、增量编辑、缓存身份与重新解析结果的一致性；不为解决单个反例引入全局行为变化。
- 对扩展、外部渲染器和 native scanner 检查资源预算、回退、安全策略、取消与可选依赖隔离；不能把 host-code TCK 的通过描述为沙箱安全保证。

## Code Review Rules

- 每条阻塞性意见应给出可触发输入/执行序列、违反的具体契约、影响及相关代码；不要把纯风格、未经验证的假设或已有问题的无关优化升级为阻塞缺陷。
- 对同一根因，在**一次审查**中检查相邻的正反、缺失/空值、边界、回退和对称路径；合并同一不变量的反例，而非分多轮逐个提出。只检查受影响的调用链，不穷举无关情况。
- 对照输入生产者、解码/校验者和最终使用方；确认修复同时保留合法输入与失败语义。可访问 Review Thread 时先去重，后来发现的真实回归仍必须指出。
- 后续提交重点复核当前修复、相关不变量与引入的回归；区分当前 PR 引入/加重的问题、历史缺陷和可独立跟进的建议。不得仅因审查次数多就跳过真实阻塞问题。

## Review 反馈处理与收敛

- 先验证每条 Review 意见并按根因归类；同组边界情况集中修复并补回归/参数化测试。避免“修一条、Push 一次”的循环。
- 聚合一轮实现与受影响测试后再推送；记录已修复、证据反驳、仍阻塞及范围外跟进的具体原因。
- 合并前核对最新 HEAD 上实际完成的复审与 CI；旧 SHA 的 Review、评论数归零或本地构建通过不能替代最新提交的证据。自动复审是否触发由 Codex 设置管理，`AGENTS.md` 本身不会触发 Review。
- 当前 PR 的真实阻塞缺陷与 Issue 验收必须满足；非阻塞独立改进可单开 Issue。不能用固定轮数或“全部 Thread 清零”作为唯一条件，也不应自动合并。
