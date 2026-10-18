# 扩展开关与真实富内容成本

本报告测量功能开销：开启和关闭的预期语义不同，比例不是同工作量的加速结论。
生产修订 `88db33b6498b1d9174be6f5a0962912947551854`，产品 tree `6c777aa402a9de37ca65bfc86b1fabcc5af9420678dfc78d9e31a40b1e6f1ce1`；官方 STS 1.2.0，
`-O2 --obf-seed 0`，CommonMark 0.31.2，native 关闭，单逻辑 CPU，heap 2GB、GC 500ms。
新增 workload 与 harness 的 SHA-256 独立记录在 [完整逐进程数据](feature-cost-raw.json)，
不将新测量重绑到旧报告。完整原始报告 SHA-256 为 `7f490f7c042e2e56d914fc51203eaa885475640bb6872086c411474f2c5802da`。

1056 个 feature 进程和 48 个真实 rich/fallback 进程均通过各自 oracle，首轮预热排除，
保留七轮。feature 每组有 A/A 和交替 on/off 配对，场景顺序每轮反转；基线单次 pilot
在测量前固定批次数为 `ceil(250ms / time)`，最多 1024 次。报告全部规模，未因波动重跑。

## 扩展密集、重复脚注和标题碰撞

dense 同时开启六项 P1 扩展，包含一次 Front Matter、显式标题 ID、公式、智能标点、
定义列表和两次脚注引用。footnotes 只开启脚注，每 unit 重复引用同一定义两次；headings
只开启标题 ID，每 unit 使用同一中文/emoji 标题。关闭时均为原始 CommonMark。
每个进程校验源码、诊断、绑定目标、回链数和唯一标题目标；snapshot/cache 还与全解析
比较 HTML+SourceMap 和每个 lossless token。两种配置不要求拥有相同 AST/输出。

以下为七轮中位数。A/A 为关闭配置的最大配对比值偏差，只用于显示测量波动。
RSS 是当前进程 VmHWM：包含 runtime、setup、保留输入和批次垃圾，计时结束后、
独立 oracle 之前记录。它不是 live heap，也不能当作每次操作新增内存。

| 输入 | units | bytes | 阶段 | off ms | on ms | on/off | 最大 A/A % | off/on RSS MiB |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| dense | 16 | 2427 | parse | 0.170 | 1.024 | 6.01 | 13.10 | 150.2 / 715.6 |
| dense | 16 | 2427 | snapshot | 0.806 | 1.956 | 2.43 | 11.39 | 339.5 / 646.3 |
| dense | 16 | 2427 | render | 0.090 | 0.182 | 2.02 | 71.58 | 39.5 / 90.9 |
| dense | 16 | 2427 | decode-hot | 1.805 | 3.545 | 1.96 | 40.58 | 220.7 / 467.2 |
| dense | 16 | 2427 | decode-read | 1.665 | 3.503 | 2.10 | 84.73 | 177.2 / 399.3 |
| dense | 64 | 9771 | parse | 0.625 | 3.936 | 6.30 | 38.87 | 241.6 / 922.8 |
| dense | 64 | 9771 | snapshot | 3.154 | 7.844 | 2.49 | 12.17 | 338.9 / 666.0 |
| dense | 64 | 9771 | render | 0.268 | 0.657 | 2.45 | 11.26 | 125.3 / 302.5 |
| dense | 64 | 9771 | decode-hot | 6.361 | 14.118 | 2.22 | 15.44 | 230.5 / 501.5 |
| dense | 64 | 9771 | decode-read | 6.457 | 14.501 | 2.25 | 18.48 | 210.7 / 486.2 |
| dense | 256 | 39927 | parse | 2.591 | 16.145 | 6.23 | 6.45 | 167.7 / 843.4 |
| dense | 256 | 39927 | snapshot | 13.078 | 31.489 | 2.41 | 10.95 | 360.2 / 683.1 |
| dense | 256 | 39927 | render | 1.121 | 2.657 | 2.37 | 8.94 | 129.6 / 340.8 |
| dense | 256 | 39927 | decode-hot | 26.840 | 63.997 | 2.38 | 26.94 | 190.5 / 446.3 |
| dense | 256 | 39927 | decode-read | 26.082 | 59.822 | 2.29 | 24.14 | 230.1 / 472.6 |
| footnotes | 16 | 710 | parse | 0.066 | 0.189 | 2.86 | 18.10 | 48.8 / 142.2 |
| footnotes | 16 | 710 | snapshot | 0.304 | 0.399 | 1.31 | 53.63 | 333.4 / 360.3 |
| footnotes | 16 | 710 | render | 0.075 | 0.082 | 1.08 | 12.20 | 40.4 / 43.2 |
| footnotes | 64 | 2726 | parse | 0.179 | 0.636 | 3.54 | 47.63 | 177.0 / 520.6 |
| footnotes | 64 | 2726 | snapshot | 1.158 | 1.413 | 1.22 | 14.62 | 372.0 / 397.2 |
| footnotes | 64 | 2726 | render | 0.225 | 0.262 | 1.16 | 19.21 | 115.6 / 153.3 |
| footnotes | 256 | 10790 | parse | 0.660 | 2.124 | 3.22 | 13.71 | 262.7 / 529.7 |
| footnotes | 256 | 10790 | snapshot | 4.869 | 5.583 | 1.15 | 4.04 | 379.9 / 414.3 |
| footnotes | 256 | 10790 | render | 0.899 | 1.026 | 1.14 | 39.74 | 154.1 / 173.6 |
| headings | 16 | 336 | parse | 0.014 | 0.098 | 6.97 | 37.24 | 32.2 / 71.5 |
| headings | 16 | 336 | snapshot | 0.102 | 0.177 | 1.73 | 21.77 | 107.8 / 167.6 |
| headings | 16 | 336 | render | 0.011 | 0.017 | 1.59 | 92.69 | 21.0 / 22.2 |
| headings | 64 | 1344 | parse | 0.068 | 0.301 | 4.44 | 16.68 | 59.0 / 288.0 |
| headings | 64 | 1344 | snapshot | 0.342 | 0.569 | 1.66 | 31.44 | 284.5 / 424.3 |
| headings | 64 | 1344 | render | 0.070 | 0.084 | 1.19 | 40.25 | 40.7 / 41.2 |
| headings | 256 | 5376 | parse | 0.204 | 0.911 | 4.46 | 18.65 | 217.0 / 598.0 |
| headings | 256 | 5376 | snapshot | 1.330 | 2.289 | 1.72 | 10.27 | 236.6 / 355.5 |
| headings | 256 | 5376 | render | 0.205 | 0.261 | 1.27 | 10.24 | 114.9 / 132.8 |

dense 最大组有 256 个脚注定义和 512 个引用；footnotes 最大组是单个定义的 512 个
引用；headings 最大组有 256 个互异目标。输入规模每次扩大四倍，完整原始数据保留节点
及绑定数量，不能把这三点样本推广为任意输入复杂度保证。追加输入的小 chunk 与长尾
成本见 [append 报告](append-cost.md)，编辑序列见 [editor/cache 报告](editor-cache-cost.md)。

decode-hot 在计时前加载 byte array；decode-read 包含文件读取，在新进程/engine 中执行，
没有预建 AST/CST。两者都运行生产 reader 的 source parse、CST/map 和校验。系统页缓存
未清除，这是应用冷启动与 warm-FS 成本，不是冷盘吞吐。缓存格式没有被称为“省去 parse”。

## 固定真实后端的首次准备与缓存命中

使用已显式安装的 KaTeX 0.19.0、Mermaid CLI 12.0.0、Shiki 4.5.0，Node 24.22.0、
Chrome 155.0.8059.84 和固定字体。runtime identity 为
`66482adc432167538bbcccac7a431bcbf9d6d93653981333609ef0ede5d0ba39`。
fixture 包含分式/根式、中文 flowchart、BOM/CRLF/Unicode 代码及空代码块，共四个请求。
所有四个真实结果均须 Ready，最终 HTML 验证 MathML fraction/root、彩色 token 和受控
PNG；warm 要求相同 preparation fingerprint。未安装/取消/异常/网络/进程清理的正确性
另见 [Node backend](../node-rich-backend.md) 及其真实 gate，这里不以 mock 替代成本。

下面计时只覆盖所列操作。构造 backend 仅读取显式 identity，另计中位约 0.024ms。
warm 和 prepared render 在计时前真实准备一次，因此它们的进程内存仍包含该次启动。
disabled/missing 明确返回四个相应 Unavailable；missing 是未传 backend，不会自动查找。

| 操作 | 中位 ms | 最小/最大 ms | 缓存项/计费 bytes | HTML bytes | Cangjie RSS MiB | 进程树 RSS 采样 MiB | 最大进程数采样中位 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| disabled | 0.016 | 0.013 / 0.025 | 0 / 0 | 0 | 14.40 | — | 1 |
| missing | 0.016 | 0.013 / 0.024 | 0 / 0 | 0 | 14.40 | — | 1 |
| cold | 9090.058 | 8855.117 / 9268.816 | 4 / 6657 | 0 | 15.55 | 1654.9 | 15 |
| warm | 0.222 | 0.221 / 0.225 | 4 / 6657 | 0 | 15.62 | 1621.8 | 14 |
| render-fallback | 0.019 | 0.013 / 0.024 | 0 / 0 | 500 | 14.46 | — | 1 |
| render-prepared | 0.212 | 0.205 / 0.403 | 4 / 6657 | 9264 | 15.68 | 1657.3 | 15 |

cold 包含实际 Node/Chrome 启动、全部后端及准备器验证；缓存初始为空。warm 只复用四个
已验证成功产物，仍收费、检查取消并验证配置。缓存的 6657 bytes 是受控计费量，不是
堆内存。首次准备成本和外部进程内存明显高于基础 parser，因此保持默认关闭和显式宿主
接入。七轮不能证明可靠 P95 或未来机器的延迟承诺。

进程树每 20ms 只读采样一次，覆盖该消费进程及其线程拥有的后代。RSS 求和会重复计算
共享页，也会错过短暂峰值，不能作为精确物理内存；短于采样间隔的 disabled/missing/
fallback 使用 VmHWM，树采样显示为“—”。prepared/warm 的树采样包含计时前准备，
不能把它归因于缓存命中或 render 单步。所有调用结束后没有遗留 job 目录；进程清理
本身由独立实际 backend gate 证明，不以这里的 RSS 观察代替。

## 复现

先在相同生产修订构建库，显式准备相同离线 runtime，激活 STS 1.2.0，并使用新的
磁盘输出目录。此命令只消费现有 runtime，不安装或下载。

```sh
python3 benchmarks/measure_features.py \
  --library-directory target/release/markdown --runtime <installed-runtime> \
  --output "$TMPDIR/feature-cost" --cpu <allowed-cpu> --allow-unsandboxed-chromium
python3 benchmarks/summarize_features.py "$TMPDIR/feature-cost/result.json" \
  --output "$TMPDIR/feature-report" --revision <measured-production-commit>
```

导出器验证每个样本及输入 hash，不覆盖不同历史报告。no-sandbox 是受信测试环境中的
明确选择，不宣称操作系统隔离。完整构建产物、原始日志和 runtime 离线准备结果独立
保留；本成本报告不代替 source-to-binary replay、冻结性能、hosted CI 或 release gate。
