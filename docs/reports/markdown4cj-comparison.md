# markdown4cj 同语言解析性能对比

状态：**PASS（CommonMark parse-only）**

## 对比边界

- 产品提交：`dff237c8fe34196366db7f1be3e242c0b6e6efb2`，Git tree `98d6d43cd236b08c0b69babb6c21d4e3159f432d`。
- `markdown4cj` 固定提交 `f43cfb3ae1cd3092d9a8a94332c64815fc4572f9`。
- `commonmark4cj` 固定提交 `41499e6d6e50efac71db3bba64d5300d251d9c90`，用于当前 SDK adapter。
- SDK：`Cangjie Compiler: 1.2.0 (cjnative)`。
- 只构建 `markdown4cj/src/core/**`。不构建 OHOS UI、DevEco、prism4cj 或 formula-ffi。
- 两侧都生成 AST；本报告不把 event parser 或 fused renderer 当作 `parse()`。

这不是 HTML renderer 性能对比。HTML 只在计时区间外作为逐语料语义门禁；性能结论
只适用于共同的 CommonMark parse-only 子集。

## 测量协议

- 同一主机、同一 SDK、release `-O2`、固定 CPU 0。
- 两侧显式使用 `cjHeapSize=2GB`、
  `cjGCInterval=500ms`、`LC_ALL=C.UTF-8` 和
  `TZ=UTC`。子进程不继承主机环境。
- 两侧环境的唯一差异是 comparator 的 `LD_LIBRARY_PATH` 增加 retained binary root 的
  `libraries/commonmark4cj` 目录。raw report 记录并校验该差异。
- 11 个确定性语料，每个 256 KiB；每进程解析 3 次。
- 每侧预热 1 次，再取 7 个交替样本；奇数轮反转顺序。
- 12 个共享 CommonMark 用例以及每个被计时语料的 spec-HTML 摘要和长度必须一致；
  语义检查在计时区间外执行。
- 门槛：几何平均至少 `1.20×`，单语料不得回退超过
  `10%`，峰值 RSS 不得超过 comparator 的
  `1.20×`。

## 当前结果

大于 `1×` 表示 `markdown` 更快。

| 语料 | parse 加速 | 峰值 RSS 比值 |
| --- | ---: | ---: |
| official-spec | 6.04× | 0.517× |
| readme-api | 5.02× | 0.484× |
| large-code | 2.18× | 0.552× |
| large-table | 78.26× | 0.026× |
| many-references | 9.05× | 0.195× |
| cjk | 9.32× | 0.226× |
| emoji | 7.86× | 0.164× |
| deep-list | 6.38× | 0.582× |
| pathological-delimiters | 12.61× | 0.177× |
| long-line | 6.73× | 0.437× |
| ordinary | 6.49× | 0.460× |
| **几何平均** | **8.25×** | — |

11 个语料的最小加速为 `2.18×`。最大峰值 RSS 比值为
`0.582×`。共享行为用例为
`12/12`。

## 合入门禁

GitHub Actions 的 `Same-language benchmark (sts-1.2.0)` job 对每个 push 和 PR
重新构建两侧 driver，并重新计算全部统计量。`main` 将该 job 设为 required check。

运行以下命令可以复现同一 harness：

```sh
unset LD_PRELOAD LD_LIBRARY_PATH LIBRARY_PATH
unset MARKDOWN_NATIVE_ARFLAGS MARKDOWN_NATIVE_CFLAGS TARGET
unset cjHeapSize cjGCInterval
CC=clang AR=ar python3 scripts/build_native_scanner.py \
  --enable --target x86_64-unknown-linux-gnu
python3 scripts/build_benchmark_driver.py --build-cli \
  --identity-output /tmp/markdown-build-identity.json \
  --sdk-url 'https://cangjie-lang.cn/v1/files/auth/downLoad?nsId=142267&fileName=cangjie-sdk-linux-x64-1.2.0.tar.gz&objectKey=6ab1e26eece1f87ff5befa73' --sdk-sha256 8c5fd944cd9cc51ee63d4a240e3ecc4f540345dae1468e8b47c927ecf2ba998f \
  --sdk-archive /path/to/cangjie-sdk.tar.gz \
  --sdk-extract-dir /tmp/fresh-cangjie-sdk-verified \
  --target x86_64-unknown-linux-gnu
python3 benchmarks/compare_markdown4cj.py \
  --tools-root /tmp/markdown-same-language-tools \
  --workspace /tmp/fresh-markdown4cj-adapter \
  --binary-root /tmp/markdown4cj-retained-binaries \
  --build-identity /tmp/markdown-build-identity.json \
  --output /tmp/markdown4cj-comparison.json

python3 benchmarks/compare_markdown4cj.py \
  --source /tmp/markdown-same-language-tools/markdown4cj \
  --commonmark4cj-source /tmp/markdown-same-language-tools/commonmark4cj \
  --product-source /tmp/markdown-product.bundle \
  --binary-root /tmp/markdown4cj-retained-binaries \
  --sdk-archive /path/to/cangjie-sdk.tar.gz \
  --verify-report /tmp/markdown4cj-comparison.json \
  --require-current-product
```

验证器不会信任 raw report 中的 preflight 布尔值或 source-tree 摘要。上述三个显式
Git 输入可以是 checkout、bare object store 或 bundle；验证器从固定 commit 的 objects
重新计算产品 commit、tree、product tree、harness blobs，并从 comparator commits
重新计算两侧 tree、完整 `commonmark4cj` 依赖内容、选择的 core blobs、迁移结果、driver
与 manifest。它还从 `--binary-root` 读取测量实际执行的三份 binary，并重新解析
comparator adapter-owned ELF `PT_DYNAMIC`/`DT_NEEDED` 闭包。验证器读取 loader 使用的
program headers，不信任可独立分歧的 section table，并拒绝 `DT_RPATH`/`DT_RUNPATH`。
当前固定 adapter 只需 `libcommonmark4cj.commonmark.so`；未链接的 base、table 和 strikethrough DSO 不会被盲目
保留。验证器重新计算每个 artifact 的相对路径、长度、SHA-256 与 mode，并与 retained、
adapter build 和 build output 三方核对。缺少、额外、交换、symlink、路径逃逸、mode 或
bytes 漂移都会导致验证失败。最后，验证器从 retained Git objects、SDK archive 和
attested native tools 在全新目录重建三份 executable 与 runtime DSO closure，并逐字节
比较 measured artifacts。同步修改 binary 与 raw digest 不能绕过该检查。

原始样本、身份和派生统计见
[`markdown4cj-comparison-raw.json`](markdown4cj-comparison-raw.json)。
