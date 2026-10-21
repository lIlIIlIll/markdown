# Issue #10 hosted 证据

核心已通过 [PR #12](https://github.com/lIlIIlIll/markdown/pull/12) 合入 main。本页记录 0.9.1 版本改号前的
main 性能证据与合入前的历史验收；当前 head 的最终检查以
[PR #14](https://github.com/lIlIIlIll/markdown/pull/14) 为准，不预先认证后续提交。尚未发布。

## 版本改号前的 main 性能证据

PR #12 的 squash merge 保留了产品内容，但合入前测量提交不再属于 main 祖先链。
校验器按原规则拒绝旧身份。当前两份 canonical 报告均采用实际 main 提交
`ce4fae179a1586872c057601be87f8b452a35c33` 的测量，产品 tree 为
`6c777aa402a9de37ca65bfc86b1fabcc5af9420678dfc78d9e31a40b1e6f1ce1`。

- C 参考报告由该 main 提交重新构建并实测，官方 STS 1.2.0、协议和阈值不变。
  CommonMark `1.8864746701753454x`、GFM `1.6470812254036316x`，七项门槛全部 PASS。
  Raw SHA-256 为 `b1ae44b1b569550e6474b69067fc197820f21d62855507447baba1d0f38b7952`。
- 同语言报告直接采用 main run
  [39195978763](https://github.com/lIlIIlIll/markdown/actions/runs/39195978763)
  的实际 artifact `12162017686`。该 run 整体失败于旧 committed evidence 验证，
  `Run same-language benchmark gate` 实测步骤成功，不能将整个 run 描述为成功。
- Artifact ZIP 为 `305268730` bytes，SHA-256
  `2d8c80666ec30f3242d53f4cc6f3b6cda5ef860088c69ef62be7ae409a3bec32`。
  Raw SHA-256 为 `b521cdf367b01ffe9c3cb42a915f48513bff531715fc446a8fefa5a4350f5590`。
  共享行为 `12/12`，geomean speedup `10.3203658343143x`，全部同语言门槛 PASS。
- 只读取证 run
  [39574329033](https://github.com/lIlIIlIll/markdown/actions/runs/39574329033)
  已成功下载并验证固定 artifact，在 Ubuntu 中使用 retained Git inputs、SDK、native tools
  和 runtime 闭包完整重建，逐字节匹配原测量产物。随后导出的 raw 与 Markdown 报告
  经分块、长度及 SHA-256 校验后原样写入仓库。

`.github/benchmark-evidence.json` 固定上述实际 artifact。源码、harness、校验器和性能门槛
均未修改；main 合入后的完整 CI 仍须独立验证。`ciVerifiedAtHead=false`、
`ciVerifiedCommit=null` 和 `published=false` 保守保留。

## PR #12 合入前的历史证据

以下记录只描述原分支的成功运行、样本与重建，不代表当前 canonical 报告的身份或数值。

### 运行与真实 release evidence

| 项目 | 证据 |
| --- | --- |
| 已测核心 head | `d383eaca35c1c70802105cbf1ab8e942da6c4ea2` |
| SDK | 官方 STS 1.2.0，原始 archive SHA `8c5fd944cd9cc51ee63d4a240e3ecc4f540345dae1468e8b47c927ecf2ba998f` |
| Push CI | [39185741396](https://github.com/lIlIIlIll/markdown/actions/runs/39185741396)，两个 STS jobs 均 SUCCESS |
| PR CI | [39185745072](https://github.com/lIlIIlIll/markdown/actions/runs/39185745072)，两个 STS jobs 均 SUCCESS |
| 真实 release manifest | push 提交 `d383eac`，treeState=clean，27 步全部 exit0 |
| JUnit / API | 1621/1621，零 skipped/errors/failures；CM652/652、GFM671/671；API1706 |
| Push release artifact | `12158745545`，ZIP3313556 bytes，SHA `3de1f2455f5e46ec589bdb3de607c7b3c78ff7da6b7d1ff636a276c8184553de` |
| Push release manifest SHA | `ed85fa75361a18368579df5559c1f6d5a8d60afaef355e6c1c3c1af46c11a088` |

实际上传的 ZIP 已按 GitHub metadata 核对 SHA-256，安全提取并验证全部 SHA256SUMS。
不是从日志摘要手写测试数字。PR run 的源码身份是 GitHub 临时 merge commit
`81ac7d624dd5c02d260f000b199a2705f508e43f`，其 release proof 亦保留；公开 canonical
选择同一 head 的 push run，使测量提交保持在核心分支历史中。该选择依据来源可追溯性，
没有修改阈值、样本或失败结果。

### 当时的 canonical 同语言证据

| 项目 | 值 |
| --- | --- |
| Run / artifact | `39185741396` / `12158042400` |
| Artifact 名称 | `same-language-benchmark-sts-1.2.0` |
| ZIP bytes / SHA-256 | `305286665` / `49909b3ffab5fb39165306d9b60ff37c8f6b933a54c3f1b4645a6c40a650daff` |
| Raw report SHA-256 | `2758225050d8d9fb58fe75ff61f1f4c7e82ed36c43b4e289331f42d89d2e1cf0` |
| 测量提交 | `d383eaca35c1c70802105cbf1ab8e942da6c4ea2` |
| Product tree | `6c777aa402a9de37ca65bfc86b1fabcc5af9420678dfc78d9e31a40b1e6f1ce1` |
| 共享行为 / corpora | `12/12`；11 个 timed corpus 的 spec-HTML length/SHA 完全一致 |
| Geomean speedup / 最大 RSS 比 | `10.330166027944836` / `0.5552944527522609` |
| Gate | >=1.20 speedup、单项退化 <=10%、RSS <=1.20；全部 PASS |

`.github/benchmark-evidence.json`、raw 与 Markdown 报告直接采用实际成功 artifact 的
字节和身份。两次独立断网复验分别运行于 Arch 与 Ubuntu：从保留 Git bundle、官方 SDK、
native 工具及 runtime/link 闭包重建 driver、CLI 和 comparator，逐字节匹配实际 CI 产物。
实际 ZIP 的 executable modes 经受限 tar 提取保留，没有以本地重建产物替换 CI 样本。

最初向包装器传入不含 Git 元数据的源码归档，来源校验明确拒绝。随后使用实际 artifact
保留的 Git bundle 创建完整来源仓库并通过；没有放宽验证器或跳过 Git provenance。

### 当时的维度边界

- 本地 C 参考性能仍绑定 `b930377` 的原始测量，CM2.2662/GFM1.7967，所有原门槛 PASS。
  本页的 CI 同语言数字不重绑本地 C 样本。
- 实际 KaTeX/Mermaid/Shiki、browser/clipboard、timeout/cancel 和进程清理由本地 N1/C1
  实测验证；hosted 默认 gate 验证基础库和测试端口，不声称 hosted 运行了可选真实 runtime。
- `release-evidence.json` 的 `ciVerifiedCommit` 记录上述已测 head；`ciVerifiedAtHead` 保守地
  保持 false，不假定新增证据提交本身已经通过 CI。实时最终状态通过 PR checks 独立报告。
- 合并、发布及关闭 issue 不由证据更新自动执行。交付内容与逐项需求见
  [验收矩阵](issue-10-matrix.md)。
