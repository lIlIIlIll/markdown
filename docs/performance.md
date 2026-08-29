# 性能

`release-evidence.json` 是当前性能数字的唯一事实源。README、canonical report、raw 数据、
需求账本和 acceptance report 必须绑定同一份 release evidence。

## 当前 canonical 结果

当前 release benchmark 使用固定 Server CPU、Cangjie SDK
`1.1.0-alpha.20260803040049` 和 release 构建。

| Profile | 对比对象 | 当前 ratio | 门槛 | 状态 |
| --- | --- | ---: | ---: | --- |
| CommonMark 完整 AST parse | cmark 0.31.1 | `2.334095x` | `≤2.5x` | pass |
| GFM 完整 AST + HTML | cmark-gfm 0.29 | `2.466373x` | `≤2.5x` | pass |

ratio 大于 1 表示本库更慢。完整语料、样本、RSS、复杂度和 identity 见
[canonical report](reports/benchmark.md)与其链接的 raw JSON。

## 比较了什么

CommonMark profile 每轮构造完整 `Document`、`NodeId`、`SourceSpan`、`SourceBuffer` 和
`ParseResult`。GFM profile 在同样的完整 AST 后执行 HTML renderer。benchmark 不会用
轻量 event parser 替换公开 `parse()`。

benchmark driver 使用显式 `ReusableUtf8Input` 和可选 native scanner，并在 metadata 中
记录它们。默认 `parse(String)`、Array、ownership transfer 和 stream 的转换成本分项报告，
不得把最优输入入口描述成 String facade 的结果。

## 如何公平阅读结果

- cmark/cmark-gfm 是当前 GA 性能硬门槛，也是 canonical release evidence。
- pulldown-cmark 等低分配 pull/event parser 不构造相同完整 AST，应单独标注执行模型。
- AST + SourceSpan、GFM + 安全渲染和文档工具能力应使用能力匹配 profile。
- DSL、CST、SourceMap、formatter、lint 和 rewrite 报告绝对开销及关闭后的基础路径回退，
  不能混进标准 parse ratio。

历史同语言比较见 [markdown4cj comparison](reports/markdown4cj-comparison.md)。该报告固定旧
commit 和 SDK，只证明冻结的 CommonMark parse-only 子集；它不是当前端到端 canonical
结果。

## 测量协议

- release 构建，固定 CPU、SDK、target、reference commit 和 corpus digest；根库使用
  `-O2`，benchmark consumer 使用 `-O2 --lto thin`；
- 受测进程显式设置 `cjHeapSize=2GB` 和 `cjGCInterval=500ms`。后者是 heuristic GC
  最小间隔，不关闭 GC，也不改变库的默认进程环境；
- baseline/candidate 交替测量，并包含 A/A 与双向 A/B；
- README/API 输入会将生成的 release-evidence block 替换为固定 marker，避免报告写回改变
  下一轮 corpus；
- 1/2/4/8/16 MiB scaling 至少 7 个样本；log-log slope 超过 `1.35` 或相邻翻倍超过
  `3.0` 失败；
- 同时记录 wall time、raw samples、geomean、峰值附加 RSS 和可选能力开销；
- 输出 checksum 不同或受测 driver/source identity 不匹配时 fail closed。

## 输入和分配边界

- `String` 使用 identity SourceBuffer byte view。
- 普通 byte Array 保留验证和不可变防御性复制。
- `OwnedUtf8Input.take` 是显式 unsafe ownership transfer，只接受已经有效的 UTF-8。
- `ReusableUtf8Input` 在准备阶段验证或接管一次，后续每轮仍创建完整 AST。
- 长 text/code/raw HTML 可用 `SourceSlice`，语义转换后的小值使用 copy。
- CST 是 opt-in；一个 CST 共享 token arena，公开 `toArray()` 仍防御性复制。
- renderer 直接写有界 sink，并在写入过程中执行预算与取消检查。
- native scanner 是可选 accelerator；根库默认纯仓颉路径功能完整且没有 foreign link 依赖。

## 复现与更新

从仓库根目录运行发布门禁：

```sh
scripts/release_gate.sh
```

完整远端 canonical benchmark 需要固定 reference host 和依赖。运行后必须先更新
`release-evidence.json`，再由生成脚本同步 README 和报告；不要手工维护另一套“当前数字”。
