# 性能

`release-evidence.json` 是当前性能数字的唯一事实源。README、canonical report、raw 数据、
需求账本和 acceptance report 必须绑定同一份 release evidence。

## 当前 canonical 结果

<!-- release-evidence:start -->
当前 release benchmark 使用固定 CPU、Cangjie SDK
`Cangjie Compiler: 1.2.0 (cjnative)` 和 release 构建。

| Profile | 对比对象 | 当前 ratio | 门槛 | 状态 |
| --- | --- | ---: | ---: | --- |
| CommonMark 完整 AST parse | cmark 0.31.1 | `2.334814x` | `≤2.5x` | pass |
| GFM 完整 AST + HTML | cmark-gfm 0.29 | `1.995218x` | `≤2.5x` | pass |

ratio 大于 1 表示本库更慢。完整语料、样本、RSS、复杂度和 identity 见
[canonical report](reports/benchmark.md)与其链接的 raw JSON。
<!-- release-evidence:end -->

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

当前同语言比较见 [markdown4cj comparison](reports/markdown4cj-comparison.md)。该报告绑定
当前产品 tree、固定的 `markdown4cj`/`commonmark4cj` commits、SDK、语料和 harness，只
证明共同的 CommonMark parse-only 子集。GitHub Actions 会在每个 PR 上重新运行这项比较，
但它不替代 cmark/cmark-gfm 的端到端 canonical release evidence。

同语言 schema v5 在计时外对每个 timed corpus 生成 CommonMark spec HTML，并要求两侧
输出 byte length 和 SHA-256 完全一致。只有语义门禁通过的 corpus 才会进入计时。build
identity 绑定 SDK archive、实际 compiler/archiver executable bytes 与 SHA-256、完整版本
命令和输出、target triple、native scanner 最小 child environment、manifest 和命令、build
flags、源码输入以及最终 binary digest。
报告以完整 SHA 固定实测 commit。verifier 解析该 SHA 的真实 commit/tree，并从 commit
blobs 独立重算产品与 harness identity；`--require-current-product` 要求这些输入与干净的
当前 `HEAD` 一致。只提交生成报告可以保留证据；产品、构建输入或 harness 变化会使旧证据失效。
它还要求显式提供本地 `markdown4cj` 与 `commonmark4cj` Git 输入，从固定 commit 的
objects 独立重算两侧 tree、完整依赖内容、选择的 core blobs、迁移结果、driver 和
path-stable manifest。checkout、bare object store 与 Git bundle 均可离线验证；缺失 objects
时 fail closed，raw report 中的 preflight 布尔值不作为证据。
测量把实际执行的 product driver、CLI 和静态链接 comparator driver 复制到专用 binary
root。固定 adapter 将 `commonmark4cj` 以非增量 static package 构建，因此两侧使用完全
相同的 `LD_LIBRARY_PATH`，报告要求 comparator-owned runtime closure 为空。注入 DSO、
额外 artifact、symlink、路径逃逸或任一执行环境差异都会 fail closed。verifier 仍读取
loader 实际使用的 program headers，而不信任可分歧的 section table。这证明实际执行
bytes 的身份，不宣称报告中的 digest 本身能证明来源。verifier 还会在全新目录中，使用
retained product/comparator Git objects、retained SDK archive 和已验证的 native tools，
以固定 seed、单 job 和 `--trimpath` 重新构建 native scanner、两份 product executable 与
comparator executable，并逐字节比较实际测量产物。
因此同步篡改 retained binary 与报告 digest 也不能通过。
所有 Cangjie package 的 effective manifest 使用各自 fresh root 的 `--trimpath`，避免绝对
临时路径进入 executable。CI artifact 同时保留 native compiler、archiver 及 Clang resource
archive；rebuild 不再从 raw report 的原 runner 绝对路径读取工具。
native tools 的 ELF loader 与递归 DSO 闭包也一并保留；复验命令仅通过这些 retained
runtime bytes 启动 compiler/archiver，不解析或读取宿主机 PT_INTERP 对应文件。

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
- 每个 timed corpus 的 spec-HTML checksum 不同，或受测 driver/source identity 不匹配时
  fail closed；verifier 从 raw samples 独立重算统计和 gate。

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

同语言 gate 使用独立 raw report。验证仓库中的结果：

```sh
git bundle create /tmp/markdown-product.bundle HEAD
python3 benchmarks/compare_markdown4cj.py \
  --source /tmp/markdown-same-language-tools/markdown4cj \
  --commonmark4cj-source /tmp/markdown-same-language-tools/commonmark4cj \
  --product-source /tmp/markdown-product.bundle \
  --binary-root target/same-language-benchmark/binaries \
  --sdk-archive target/same-language-benchmark/toolchain/cangjie-sdk-linux-x64-1.2.0.tar.gz \
  --verify-report docs/reports/markdown4cj-comparison-raw.json \
  --markdown-report docs/reports/markdown4cj-comparison.md \
  --require-current-product
```

`Same-language benchmark (sts-1.2.0)` 还会在 PR merge commit 上重新构建两侧 driver，
执行固定 CPU 的交替测量，并上传 raw samples、生成报告、产品 commit bundle 和两套固定 comparator commit 的
最小 Git bundle、SDK archive、native tool/resource inputs 和实际执行产物；复验直接从这些输入重算源码身份并重建产物。
directory Git input 必须是精确 worktree/bare repository root，nested path、symlink root 与外部
`.git` indirection 会 fail closed。该 check 是 `main` 的 required check。
PR job 先测量当前 SHA，避免被上一提交的 committed report 阻断。归档中的
`same-language-benchmark.tar` 保留可执行权限。`.github/benchmark-evidence.json` 固定已提交
报告对应的 CI run、artifact ID、归档摘要和 raw 摘要。`main` push 下载该归档，使用该次实测的
retained binaries/SDK/native tools 完整重建，并验证源码与当前产品及 harness 一致；不混用新
runner 的产物。归档缺失、过期或摘要不匹配均失败。CI 保留 90 天，应提前保留离线副本；离线使用
`python3 scripts/verify_committed_benchmark.py --artifact-archive <evidence.zip> --work-dir "$TMPDIR/committed-evidence"`，
其中工作目录必须尚不存在。
