# markdown 开发者文档

> **从任务出发，找到最短路径。** 代码符号、命令、错误码和 profile ID 保持源码拼写。

[开始使用](getting-started.md) · [Cookbook](cookbook.md) · [API reference](api.md) · [故障排查](troubleshooting.md) · [性能与证据](performance.md)

## 选择阅读路线

| 如果你是…… | 建议路线 | 完成后你将能够 |
| --- | --- | --- |
| 第一次使用 | [开始使用](getting-started.md) → [Cookbook](cookbook.md) | 构建工程并输出安全 HTML |
| 应用开发者 | [API 速查](api/quick-reference.md) → 对应子包 reference | 选择稳定入口并处理失败 |
| 扩展作者 | [扩展模型](extensions.md) → [Extension TCK](extension-tck.md) | 注册、渲染并验证自定义语法 |
| 工具开发者 | [AST](ast.md) → [Editor API](api/editor.md) | query、rewrite、lint 和保留格式编辑 |
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
| 选择 String、bytes、stream 或 events | [输入、限制和取消](input-and-resources.md) |
| 配置 HTML、URI 和 sanitizer | [Rendering API](api/rendering.md) |
| 自定义块或行内语法 | [扩展开发](extensions.md) |
| query、rewrite、lint 或 format | [Editor API](api/editor.md) |
| 缓存结果或处理多文档 | [Artifact 与 Document API](api/artifacts-and-services.md) |
| 使用命令行工具 | [CLI reference](cli.md) |
| 从 0.8 迁移 | [迁移指南](migration.md) |

## 我要查 API

- [API 速查](api/quick-reference.md)：常用入口、默认值和返回值。
- [完整 API 索引](api.md)：按公开子包和类型定位 reference。
- [公开声明 snapshot](../api/public-api-v0.9.txt)：精确声明事实源。

按子包深入：

| 子包 | Reference |
| --- | --- |
| `markdown.core` | [解析、AST、限制、诊断和 events](api/core.md) |
| AST 与 Source | [节点、typed view、span 和位置](api/ast-and-source.md) |
| `markdown.render` | [HTML、文本、sink 和 source map](api/rendering.md) |
| `markdown.extensions` | [manifest、dialect、DSL 和 SPI](api/extensions.md) |
| `markdown.editor` | [query、rewrite、CST、lint 和 format](api/editor.md) |
| artifact/document/testkit | [Artifact 与 Document API](api/artifacts-and-services.md) |

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
- [CommonMark/GFM、benchmark 与 fuzz 报告索引](reports/README.md)
- [release-evidence.json](../release-evidence.json)
- [贡献指南](../CONTRIBUTING.md)

---

[返回项目首页](../README.md) · [开始使用](getting-started.md) · [API 速查](api/quick-reference.md)
