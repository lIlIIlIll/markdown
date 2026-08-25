# markdown4cj 同语言解析性能对比

状态：**PASS（仅限 CommonMark parse-only workload）**

## 对比边界

- `markdown4cj`：[`develop`](https://gitcode.com/Cangjie-TPC/markdown4cj/tree/develop)
  固定提交 `f43cfb3ae1cd3092d9a8a94332c64815fc4572f9`。
- `commonmark4cj`：固定提交
  `41499e6d6e50efac71db3bba64d5300d251d9c90`，用于让纯解析核心在当前 SDK
  下构建。
- SDK：Cangjie `1.1.0-alpha.20260817040003`，CJNative
  `x86_64-unknown-linux-gnu`。
- 只抽取 `markdown4cj` 的 `src/core/**`；排除 `components/**`、`plugin/**`、
  `cj_res/**`、DevEco、OHOS UI、prism4cj 和 formula-ffi。
- 兼容层只迁移旧集合 API，并让 `ParserBuilder` 使用当前
  `commonmark4cj` 的默认 inline parser；不改变 `Markdown.create().parse()` 数据流。

这不是 HAR/UI renderer 对比。`markdown4cj` 的公开渲染结果是 HarmonyOS
`NodeView`，没有与本库 `HtmlRenderer` 等价的 HTML 字符串性能入口，因此本报告只对
parse-only 作性能结论。

## 协议

- 同一主机、同一 SDK、release `-O2`、CPU 2。
- 11 个非自定义语料，每个 256 KiB；每进程解析 3 次。
- 每侧先 warmup 1 次，再各取 7 个样本；奇数轮反转执行顺序。
- 另用 12 个共享 CommonMark 用例比较逐字一致的 HTML，结果 `12/12`。
- 推广门槛：几何平均至少快 20%，任一语料不得慢于 10%，峰值 RSS 不高于
  comparator 的 120%。

## 结果

`markdown` 相对 `markdown4cj` 纯解析核心的 parse-only 加速如下；大于 `1×`
表示本库更快。

| 语料 | 加速 |
| --- | ---: |
| official-spec | 8.53× |
| readme-api | 9.66× |
| large-code | 4.15× |
| large-table | 50.27× |
| many-references | 8.60× |
| CJK | 6.55× |
| emoji | 14.78× |
| deep-list | 10.77× |
| pathological-delimiters | 13.78× |
| long-line | 11.42× |
| ordinary | 11.70× |
| **几何平均** | **11.00×** |

11 个语料全部更快；最小加速 `4.15×`。本库的逐语料峰值 RSS 比值最大约
`0.66×`，通过 `1.20×` 上限。

`many-references` 的顶层 AST 节点计数不同（`3856` 与 `7711`）；该差异作为
AST 表达诊断保留，不用于伪造相同内部结构。独立 reference 行为用例的最终 HTML
逐字一致，且完整共享行为矩阵为 `12/12`。

## 复现

准备两个精确、干净的 checkout，并先构建本仓库 benchmark driver 与 CLI：

```sh
cangjie_env
(cd benchmarks/driver && cjpm build -V)
(cd tools/markdown && cjpm build -V)

python3 benchmarks/compare_markdown4cj.py \
  --source /path/to/markdown4cj \
  --commonmark4cj-source /path/to/commonmark4cj \
  --workspace /tmp/fresh-markdown4cj-adapter \
  --cpu 2 \
  --output /tmp/markdown4cj-comparison.json
```

runner 会验证两个提交、复制纯核心、逐项执行 fail-closed 兼容迁移、检查零
`ohos.*` 导入、构建 adapter、运行共享行为门槛，再进行配对测量。原始样本和二进制
SHA-256 见 [`markdown4cj-comparison-raw.json`](markdown4cj-comparison-raw.json)。
