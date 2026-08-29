# markdown 开发者文档

这组文档面向使用仓颉集成 `markdown` 的开发者。先完成入门教程，再按任务进入
操作指南或 API reference。

## 从这里开始

1. [开始使用 markdown](getting-started.md)：创建消费工程，解析 Markdown，并验证安全 HTML 输出。
2. [API reference](api.md)：按子包查找公开类型、方法、默认值和错误语义。
3. [Profile](profiles.md)：选择固定版本的 CommonMark 或 GFM 行为。
4. [输入、限制和取消](input-and-resources.md)：选择 String、bytes、stream、buffered session 或 Event API。

## 按任务查找

| 任务 | 文档 |
| --- | --- |
| 解析输入并读取诊断 | [Core API](api/core.md) |
| 遍历 AST、读取 literal 或转换位置 | [AST 与 Source API](api/ast-and-source.md) |
| 生成安全 HTML、纯文本或 Markdown | [Rendering API](api/rendering.md) |
| 定义块语法、行内语法和 renderer | [Extensions API](api/extensions.md) |
| 查询、rewrite、lint、format 或应用编辑 | [Editor API](api/editor.md) |
| 缓存解析结果或构建 document graph | [Artifact 与 Document API](api/artifacts-and-services.md) |
| 使用命令行工具 | [CLI reference](cli.md) |
| 迁移 0.8 代码 | [0.8 到 0.9 迁移指南](migration.md) |

## 概念说明

- [AST 与 transformation](ast.md)
- [SourceSpan 与位置编码](source-position.md)
- [安全 HTML 与 URI policy](security.md)
- [方言和扩展模型](extensions.md)
- [并发与可观测性](concurrency-and-observability.md)
- [CST、snapshot 与 document system](document-systems.md)
- [版本与兼容性](versioning-and-compatibility.md)

## 扩展作者

按以下顺序阅读：

1. [扩展模型](extensions.md)
2. [Dialect DSL](dialect-dsl.md)
3. [Syntax DSL](syntax-dsl.md)
4. [Renderer DSL](renderer-dsl.md)
5. [SPI 与 schema version](spi-and-schema-versions.md)
6. [Extension TCK](extension-tck.md)
7. [External dialect schema](external-dialect-schema.md)

## 证据与维护

- [性能方法](performance.md)解释 canonical benchmark 的语料、身份和门槛。
- [CommonMark/GFM 报告](reports/)记录规范语料与 raw benchmark。
- [公开 API snapshot](../api/public-api-v0.9.txt)是 0.9 声明级兼容检查的事实源。
- [release-evidence.json](../release-evidence.json)绑定版本、源码、SDK、语料和验证结果。

主题文档使用中文作为当前事实源。代码符号、命令、错误码和 profile ID 保持源码拼写。

