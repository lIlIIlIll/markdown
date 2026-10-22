# markdown 开发者文档

> **从任务出发，找到最短路径。** 代码符号、命令、错误码和 profile ID 保持源码拼写。

[开始使用](getting-started.md) · [Cookbook](cookbook.md) · [API reference](api.md) · [故障排查](troubleshooting.md) · [性能与证据](performance.md)

## 选择阅读路线

| 如果你是…… | 建议路线 | 完成后你将能够 |
| --- | --- | --- |
| 第一次使用 | [开始使用](getting-started.md) → [Cookbook](cookbook.md) | 构建工程并输出安全 HTML |
| 应用开发者 | [API reference](api.md) → 站点搜索或包导航 | 选择稳定入口并处理失败 |
| 扩展作者 | [扩展模型](extensions.md) → [Extension TCK](extension-tck.md) | 注册、渲染并验证自定义语法 |
| 工具开发者 | [AST](ast.md) → [文档系统](document-systems.md) | query、rewrite、lint 和保留格式编辑 |
| 维护者 | [贡献指南](../CONTRIBUTING.md) → [性能](performance.md) → [报告索引](reports/README.md) | 运行门禁并更新可追溯证据 |

## 第一次使用：15 分钟路径

1. [开始使用](getting-started.md)：从空工程得到第一个安全 HTML 输出。
2. [开发者 Cookbook](cookbook.md)：复制 GFM、AST、位置、扩展、lint 和 format 场景。
3. [故障排查](troubleshooting.md)：解决依赖、运行、profile、位置和限制问题。

## 按任务查找

| 任务 | 文档 |
| --- | --- |
| Markdown 转安全 HTML | [Cookbook：安全 HTML](cookbook.md#markdown-转安全-html) |
| 启用表格、任务列表和删除线 | [Cookbook：GFM](cookbook.md#启用-gfm) |
| 读取标题、链接和源码位置 | [Cookbook：AST 查询](cookbook.md#读取标题链接和位置) |
| 编写多 term、多段正文的定义列表 | [结构化定义列表](definition-lists.md) |
| 查看官方扩展能力、智能标点和 URI 保护 | [扩展模型](extensions.md#官方扩展能力矩阵) |
| 绑定前转换 AST、绑定后生成整文诊断 | [完整文档阶段](extensions.md#完整文档阶段) |
| 使用脚注、标题 ID 和结构化目录 | [文档绑定](semantic-binding.md) |
| 逐块接收 AST、处理后置引用和更新顺序 | [追加输入与更新消费](append-input.md) |
| 选择 String、bytes、stream 或 events | [输入、限制和取消](input-and-resources.md) |
| 处理 HTML sink 背压与部分字节确认 | [暂停与恢复 HTML 输出](html-output.md) |
| 显式准备公式、图表和颜色 token，处理后端缺失 | [富内容准备](rich-content.md) |
| 离线安装真实 KaTeX、Mermaid 和 Shiki 链路 | [可选 Node 后端](node-rich-backend.md) |
| 配置 HTML、URI 和 sanitizer | [安全 HTML 与 URI](security.md) |
| 自定义块或行内语法 | [扩展开发](extensions.md) |
| query、rewrite、lint 或 format | [AST](ast.md)、[文档系统](document-systems.md)与[格式化](formatting.md) |
| 缓存结果或处理多文档 | [文档系统](document-systems.md) |
| 使用命令行工具 | [CLI reference](cli.md) |
| 从 0.9.1 迁移 | [0.9.2 迁移](migration-0.9.2.md) |

## 我要查 API

- [中文 HTML API 站点](https://liliilill.github.io/markdown/)：按公开包浏览、搜索符号和重载，查看源码注释与提交链接。
- [API 入口与本地生成](api.md)：选择导入包，使用固定 cjdoc 发布版生成文档。
- [公开声明 snapshot](../api/public-api.txt)：检查接口变更。

## 我要写扩展

建议顺序：

1. [扩展模型](extensions.md)
2. [Dialect DSL](dialect-dsl.md)
3. [Syntax DSL](syntax-dsl.md)
4. [Renderer DSL](renderer-dsl.md)
5. [SPI 与 schema version](spi-and-schema-versions.md)
6. [Extension TCK](extension-tck.md)

外部配置还需要[External dialect schema](external-dialect-schema.md)。

## 理解设计

- [AST 与 transformation](ast.md)
- [SourceSpan 与位置编码](source-position.md)
- [安全 HTML 与 URI policy](security.md)
- [CST、snapshot 与 document system](document-systems.md)
- [并发与可观测性](concurrency-and-observability.md)
- [版本与兼容性](versioning-and-compatibility.md)

## 维护和证据

- [性能方法与当前结果](performance.md)
- [追加与可恢复输出成本](reports/append-cost.md)
- [编辑与缓存测量和取舍](reports/editor-cache-cost.md)
- [扩展开关与真实富内容成本](reports/feature-cost.md)
- [CommonMark/GFM、benchmark 与 fuzz 报告索引](reports/README.md)
- [release-evidence.json](../release-evidence.json)
- [贡献指南](../CONTRIBUTING.md)

---

[返回项目首页](../README.md) · [开始使用](getting-started.md) · [API reference](api.md)

- [代码组](code-groups.md)：版本化代码、复制原文与可选 tabs。
- [公式模型](math.md)：Math 2.0 的语义、原文和默认可读输出。
- [0.9.2 迁移](migration-0.9.2.md)：真实领域分包、入口收敛和构建路径清理。
- [0.9.1 模型迁移](migration-0.9.1.md)：历史语义、身份与流式模型调整。
- [0.8 → 0.9 迁移](migration.md)：历史版本变更。
