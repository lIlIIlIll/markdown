# markdown4cj 同语言解析性能对比

状态：**PASS（CommonMark parse-only）**

## 对比边界

- 产品提交：`ebf445cf66311fb2253ab7be0ec5517c79f0205d`，Git tree `a87795fe167ff1660f0f22f9330ce9b0014e2aef`。
- `markdown4cj` 固定提交 `f43cfb3ae1cd3092d9a8a94332c64815fc4572f9`。
- `commonmark4cj` 固定提交 `41499e6d6e50efac71db3bba64d5300d251d9c90`，用于当前 SDK adapter。
- SDK：`Cangjie Compiler: 1.1.3 (cjnative)`。
- 只构建 `markdown4cj/src/core/**`。不构建 OHOS UI、DevEco、prism4cj 或 formula-ffi。
- 两侧都生成 AST；本报告不把 event parser 或 fused renderer 当作 `parse()`。

这不是 HTML renderer 对比。`markdown4cj` 没有与本库 `HtmlRenderer` 等价的 HTML
字符串入口，因此性能结论只适用于共同的 CommonMark parse-only 子集。

## 测量协议

- 同一主机、同一 SDK、release `-O2`、固定 CPU 24。
- 11 个确定性语料，每个 256 KiB；每进程解析 3 次。
- 每侧预热 1 次，再取 7 个交替样本；奇数轮反转顺序。
- 12 个共享 CommonMark 用例的 HTML 必须逐字一致。
- 门槛：几何平均至少 `1.20×`，单语料不得回退超过
  `10%`，峰值 RSS 不得超过 comparator 的
  `1.20×`。

## 当前结果

大于 `1×` 表示 `markdown` 更快。

| 语料 | parse 加速 | 峰值 RSS 比值 |
| --- | ---: | ---: |
| official-spec | 9.26× | 0.400× |
| readme-api | 8.64× | 0.354× |
| large-code | 3.11× | 0.358× |
| large-table | 153.10× | 0.062× |
| many-references | 18.35× | 0.267× |
| cjk | 13.00× | 0.253× |
| emoji | 14.49× | 0.383× |
| deep-list | 20.68× | 0.432× |
| pathological-delimiters | 18.07× | 0.461× |
| long-line | 10.33× | 0.284× |
| ordinary | 8.82× | 0.291× |
| **几何平均** | **14.13×** | — |

11 个语料的最小加速为 `3.11×`。最大峰值 RSS 比值为
`0.461×`。共享行为用例为
`12/12`。

## 合入门禁

GitHub Actions 的 `Same-language benchmark (current-1.1.3)` job 对每个 push 和 PR
重新构建两侧 driver，并重新计算全部统计量。`main` 将该 job 设为 required check。

运行以下命令可以复现同一 harness：

```sh
cangjie_env
python3 benchmarks/compare_markdown4cj.py \
  --tools-root /tmp/markdown-same-language-tools \
  --workspace /tmp/fresh-markdown4cj-adapter \
  --output /tmp/markdown4cj-comparison.json
```

原始样本、身份和派生统计见
[`markdown4cj-comparison-raw.json`](markdown4cj-comparison-raw.json)。
