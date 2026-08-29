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

> [!IMPORTANT]
> 历史报告是不可变证据。更新当前结果时生成新的 canonical evidence，不要手工改写旧样本。

---

[← 文档首页](../README.md) · [性能方法与门槛](../performance.md)
