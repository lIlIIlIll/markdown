# Issue #10 hosted 证据

核心已交付 [PR #12](https://github.com/lIlIIlIll/markdown/pull/12)。本页记录实际成功运行，
当前 head 的最终检查以 PR 页面为准；不预先认证随后的 metadata 提交，也不代表已合并或发布。

## 运行与真实 release evidence

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

## Canonical 同语言证据

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

## 维度边界

- 本地 C 参考性能仍绑定 `b930377` 的原始测量，CM2.2662/GFM1.7967，所有原门槛 PASS。
  本页的 CI 同语言数字不重绑本地 C 样本。
- 实际 KaTeX/Mermaid/Shiki、browser/clipboard、timeout/cancel 和进程清理由本地 N1/C1
  实测验证；hosted 默认 gate 验证基础库和测试端口，不声称 hosted 运行了可选真实 runtime。
- `release-evidence.json` 的 `ciVerifiedCommit` 记录上述已测 head；`ciVerifiedAtHead` 保守地
  保持 false，不假定新增证据提交本身已经通过 CI。实时最终状态通过 PR checks 独立报告。
- 合并、发布及关闭 issue 不由证据更新自动执行。交付内容与逐项需求见
  [验收矩阵](issue-10-matrix.md)。
