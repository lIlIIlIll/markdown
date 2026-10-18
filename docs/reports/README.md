# 验证与性能报告

这里保存规范兼容、性能、差分和 fuzz 的可追溯结果。当前发布结论以仓库根目录的
[`release-evidence.json`](../../release-evidence.json) 为唯一事实源；报告用于解释方法和展开明细。

[文档首页](../README.md) · [性能说明](../performance.md) · **报告索引**

## 当前报告

| 领域 | 人类可读报告 | 原始数据 |
| --- | --- | --- |
| Release benchmark | [Canonical benchmark](benchmark.md) | [`benchmark-raw.json`](benchmark-raw.json) |
| 同语言功能与性能对比 | [markdown4cj comparison](markdown4cj-comparison.md) | [`markdown4cj-comparison-raw.json`](markdown4cj-comparison-raw.json) |
| CommonMark 0.31.2 | [Conformance report](commonmark-0.31.2-conformance.md) | 结果绑定在 release evidence 中 |
| GFM 0.29 | [Conformance report](gfm-0.29-conformance.md) | 结果绑定在 release evidence 中 |
| Differential smoke | [`differential-smoke.json`](differential-smoke.json) | 同左 |
| Fuzz smoke | [Fuzz summary](fuzz-summary.md) | crash corpus 位于 `tests/fuzz/crashes` |

## 如何阅读性能数字

1. 先检查报告中的产品 commit、SDK、CPU、语料 checksum 和 driver identity。
2. 区分 `parse-only`、完整 AST、renderer-only 与 AST + HTML 工作负载。
3. 使用 raw report 复核聚合值，不把单个语料或单轮结果当作发布结论。
4. 只在能力边界一致时比较实现；event/pull parser 与完整 AST parser 应分组报告。
5. 同语言报告必须是 schema v5，并包含每个 timed corpus 的 untimed spec-HTML digest、
   SDK archive、target、完整 build identity、从声明 Git commit blobs 重算的产品/harness
   identity、从显式本地 Git 输入重算的 comparator core/完整依赖/迁移身份，以及独立重算
   的 gate。验证还必须取得专用 binary root，并从实际保留的三份执行文件重新计算路径、
   长度、SHA-256 与 mode；固定 comparator 采用 static dependency，其 adapter-owned runtime
   closure 必须为空，两侧执行环境必须相同。verifier 不信任 section table，并拒绝注入 DSO、
   `DT_RPATH`/`DT_RUNPATH` 或 loader path 差异。复验还必须使用 retained SDK archive、native
   compiler/archiver/resource inputs、native tools 的 retained ELF loader/递归 DSO 闭包和精确 Git roots
   以固定 seed、单 job 和静态 comparator 在全新目录重建 native scanner 与全部 executables，并逐字节
   比较 retained 产物。仅同步修改 binary 与 raw report digest 不能通过。

> [!IMPORTANT]
> 历史报告是不可变证据。更新当前结果时生成新的 canonical evidence，不要手工改写旧样本。

---

[← 文档首页](../README.md) · [性能方法与门槛](../performance.md)
