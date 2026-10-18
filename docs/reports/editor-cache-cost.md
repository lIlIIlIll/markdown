# 编辑与缓存：测量和取舍

结论：保留生产中的等长局部编辑、诚实的完整回退和 source-reparse snapshot reader。
本轮没有采用 CST 合并、变长局部编辑、直接 AST/CST reader 或 source hash 复用。
受限缓存原型测得收益，但仍缺通用语法认证；其他候选未达到预先固定的整体采用门槛。
这些结论不表示已经证明候选在所有负载下无收益。

## 身份与方法

被测生产修订为 `d90f112`（v3/v4）及 `8fa725e`（v6/v8/v9/public），对应产品 tree
`e601aadd050b9ee92730448fcee73a949b0a6f94121869a4ee61d8a30104ee87` 和
`3c3fa3fc336fd2c83e04ca132157edd934c18a4cebc1798d55c4a75c041173ef`。
官方 STS 1.2.0，`-O2 --obf-seed 0`，单逻辑 CPU，heap 2GB、GC interval 500ms，
CommonMark 0.31.2、native 关闭，无扩展。输入为含中文、emoji、CRLF 的段落/标题，
目标规模 16/64/256KiB；每个编辑序列含十次操作。v3 同时分离 parse、snapshot、CST、
map、encode/write、decode/read-decode、render 和 SourceMap，共 12 个阶段。

每组一轮预热后保留七轮，独立进程，A/A 配对，交替 A/B 并反转场景顺序。后续批次
在测量前由基线 pilot 固定到约 500ms（最多 1024 次），没有按结果调门槛。
采用要求为中位节省至少 10%、大于七对 A/A 的**最大绝对比值偏差的两倍**，且中位
峰值 RSS 不超过 1.20 倍。RSS 是进程 VmHWM，包含 runtime、setup、保留输入和批次
垃圾；不是 live heap 或阶段额外内存。构造器/扫描/map 访问计数不等于堆分配次数。
无 P95、冷存储、零回退或冻结 release gate 结论。

[完整逐进程数值、比较、输入及日志 SHA-256](editor-cache-cost-raw.json) 保留预热与失败门槛，
没有挑选通过的规模。导出器逐个验证原始日志和输入字节；历史 source/executable/
instrumenter 身份保持原值。当前格式化后的探针不会冒充当时源码的精确重放。

## CST 与编辑

v3 共 1728 个进程，比较标量 Text token 基线、排序边界和 byte bitmap 合并；所有
oracle 通过。候选保留全部语义 span 边界，未把 source events 换成完整 AST 结果。
v4 是预先按 v3 基线校准批次数的有界跟进，共 288 个进程；九组中八组未通过 A/A
门槛，仅 64KiB 等长编辑通过，因此没有扩大到生产。以下列出 v4 的全部九组。

| 阶段 / 候选 | KiB | 基线 ms | 候选 ms | 中位节省 % | 最大 A/A % | RSS 比 | 统计门槛 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| snapshot/bitmap | 16 | 2.768 | 1.902 | 31.30 | 21.51 | 0.730 | 未通过 |
| snapshot/bitmap | 64 | 10.938 | 7.706 | 29.54 | 19.01 | 0.714 | 未通过 |
| snapshot/bitmap | 256 | 66.866 | 42.346 | 36.67 | 18.87 | 0.684 | 未通过 |
| equal-edit/bitmap | 16 | 32.512 | 23.702 | 27.10 | 17.71 | 0.765 | 未通过 |
| equal-edit/bitmap | 64 | 131.658 | 97.136 | 26.22 | 10.07 | 0.760 | PASS |
| equal-edit/bitmap | 256 | 485.869 | 374.983 | 22.82 | 42.94 | 0.947 | 未通过 |
| variable-edit/bitmap | 16 | 29.683 | 21.730 | 26.79 | 21.33 | 0.736 | 未通过 |
| variable-edit/bitmap | 64 | 123.904 | 85.551 | 30.95 | 32.13 | 0.732 | 未通过 |
| variable-edit/bitmap | 256 | 487.723 | 375.656 | 22.98 | 17.84 | 0.836 | 未通过 |

v6 另做真实受限变长候选：普通段落/标题插入删除、无引用/扩展，保留未变节点身份，
执行 source/arena 坐标重建、结构验证和完整 CST/map/hash。中间插入、删除分别与全解析
对照，最终序列 oracle 全通过；96 个进程的中位数没有收益。A/A 本身为 22–37%，
因此也不把负收益中位数称为可靠回退。

| 阶段 / 候选 | KiB | 基线 ms | 候选 ms | 中位节省 % | 最大 A/A % | RSS 比 | 统计门槛 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| variable-edit/local | 16 | 28.441 | 32.030 | -12.62 | 26.34 | 1.100 | 未通过 |
| variable-edit/local | 64 | 124.502 | 132.942 | -6.78 | 37.01 | 1.101 | 未通过 |
| variable-edit/local | 256 | 478.506 | 498.513 | -4.18 | 22.14 | 1.128 | 未通过 |

256KiB 的十次编辑，扫描收费从 5,059,660 降到 276,070，但 AST record 构造仍为 92,030，
CST token 构造仍为 2,207,835，map token 访问仍为 6,439,445。减少 parser 扫描不足以
抵消坐标/CST/map/hash 成本。生产等长路径十次命中十次；该变长序列十次完整回退，
候选则十次局部命中。命中率只描述这个输入，不推广到任意编辑；raw rows 包含实际
editHits 汇总。跨块及引用/脚注/标题依赖的完整回退另由公开语义测试验证。

## 缓存恢复的受限可行性

v8 比较 MCJ3 source 重解析、恢复 AST 后完整重建 CST/map/hash、恢复 AST+token 后重建
层级/map/hash。576 个进程通过节点数、HTML+SourceMap、每个 CST token 的 raw/span
及生产 binary semantic digest 的字节对照。原型只支持 <=1MiB 的普通 Doc/Para/Heading/
Text，无引用/扩展。它校验版本/配置/checksum、UTF-8、范围、后序图归属、单一根、
token 覆盖和尾随数据，但**故意未实现通用 source grammar 认证**。checksum 不能替代
这一步。结果是乐观可行性下界，不能将该 reader 交付给不可信任意缓存。

| 输入目标 KiB | source wire bytes | AST wire bytes | AST+token wire bytes |
| ---: | ---: | ---: | ---: |
| 16 | 16954 | 21137 | 34949 |
| 64 | 66145 | 85862 | 141099 |
| 256 | 262738 | 344537 | 565326 |

以下完整列出 warm-filesystem read+decode；byte-array decode 是另列阶段，64/256KiB 未通过噪声门槛。

| 阶段 / 候选 | KiB | 基线 ms | 候选 ms | 中位节省 % | 最大 A/A % | RSS 比 | 统计门槛 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| cache-read-decode/ast | 16 | 5.275 | 3.112 | 41.00 | 8.93 | 0.811 | PASS |
| cache-read-decode/direct | 16 | 5.251 | 3.464 | 34.04 | 8.93 | 0.825 | PASS |
| cache-read-decode/ast | 64 | 21.125 | 13.253 | 37.26 | 13.07 | 0.820 | PASS |
| cache-read-decode/direct | 64 | 21.853 | 14.375 | 34.22 | 13.07 | 0.842 | PASS |
| cache-read-decode/ast | 256 | 114.323 | 79.876 | 30.13 | 10.10 | 0.815 | PASS |
| cache-read-decode/direct | 256 | 119.873 | 92.189 | 23.09 | 10.10 | 0.840 | PASS |

AST wire 约为 source 的 1.25–1.31 倍，AST+token 为 2.06–2.15 倍。AST 恢复在该受限
warm-FS 场景测得 30–41% 中位节省，直接 token 恢复为 23–34%。较大的格式、尚缺的
通用校验和未覆盖语义使其不能替代当前简单 reader；不能把不采用写成“未测得收益”。
写入包括 encode+close、不含 fsync；未清空操作系统页缓存，不宣称冷盘加速。新的
decoder 进程仅保留所选 wire，不预建源 AST/CST 或其他格式以抬高基线。

## 最小完整校验候选与公开复核

v9 不增加格式：仍为 MCJ3、完整 source parse 和 AST digest，只复用不可变 snapshot
已验证 source digest；CST 复用前仍逐字比较 source。384 个插桩进程中 encode 三组通过
预设门槛，decode/read 未通过，后者从未应用。短暂应用 encode 候选后，1620 项完整
测试通过，1371 份公开 API 产物逐字节相同并通过读取/重编码/HTML/source/CST 检查。
输入包括固定 CM 652 + GFM 671 以及四个公开 profile 下的 48 份语义 fixture。

随后用两份**未插桩正式库**独立测了 96 个进程，全部三组如下：

| 阶段 / 候选 | KiB | 基线 ms | 候选 ms | 中位节省 % | 最大 A/A % | RSS 比 | 统计门槛 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| encode | 16 | 2.883 | 2.190 | 24.04 | 11.38 | 0.849 | PASS |
| encode | 64 | 12.774 | 8.450 | 33.85 | 16.47 | 0.887 | PASS |
| encode | 256 | 42.932 | 31.108 | 27.54 | 33.04 | 0.898 | 未通过 |

256KiB 组 A/A 最大偏差 33.04%，因此即使三个规模的中位数均有节省，也不能认证整体
收益。未重新跑到通过、放宽门槛或只采用较小规模；生产 encode 修改已撤回。原库
重新构建 SHA-256 为 `7442475095517d3a9123dc09ebb8e496303f08239bdfde01cf644fd77647e163`，
与原基线字节一致。候选库为
`1e4dc4eab014a0fb9ecf73d3b27b508f8548bc668017bbe0a8313e3c508c0776`。
独立 byte proof 输入 SHA-256 为
`e31c7db59beb677f15c75f1264483a4209c60a7019dc420eb7e82001721af52b`。

## 决策与复现边界

| 候选 | 决策 | 依据 |
| --- | --- | --- |
| CST Text 合并 | 不采用 | 大部分目标组未越过预设 A/A 噪声门槛 |
| 变长局部编辑 | 不采用 | 完整坐标/CST/map/hash 后未测得中位收益，噪声不支持可靠回退结论 |
| AST 或 AST+token wire | 不交付 | 受限负载有收益，但通用语法认证未完成，格式更大 |
| source digest 复用 | 不采用 | 插桩门槛通过，正式公开库复核的最大规模噪声门槛失败 |

探针与命令见 [probe README](../../benchmarks/probes/README.md)。生产 source 基线归档
SHA-256 为 `073ec1a90c74c24ed9225d1634d619d590c043a32e340627616e5b6ec0668850`。
这批实验的修改源码、原始日志、执行文件和 build.json 独立保留；v3 的早期 Python runner
后来扩展过，未在原运行前单独复制，因此不声称 v3 runner 的精确离线重放。
新复现须生成新目录及身份，不能覆盖或重绑本报告。后续兼容清理、能力开关和富内容
测量使用各自新修订；本文不认证它们，也不替代最后的冻结性能和 release 门禁。
