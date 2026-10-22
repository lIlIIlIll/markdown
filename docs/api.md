# API reference

[打开中文 API 站点](https://liliilill.github.io/markdown/)，按包浏览声明，或使用搜索定位类型、
方法与重载。站点由源码注释使用 [cjdoc v0.7.3](https://github.com/lIlIIlIll/cjdoc/releases/tag/v0.7.3)
生成，覆盖 external audience 可见的公开声明和成员。

在线站点跟随 `main`，当前开发版本为 `0.9.2` breaking pre-GA preview，工具链为官方
STS 1.2.0。查阅已发布版本时，以相应 tag 的源码和本地生成结果为准。
[`api/public-api.txt`](../api/public-api.txt) 记录当前公开声明，供接口变更检查使用。

## 选择导入包

根包 `markdown` 不公开声明或转导。导入所用类型实际所属的领域包：

```cangjie
import markdown.core.MarkdownProfile
import markdown.engine.MarkdownEngine
import markdown.render.HtmlOptions

let engine = MarkdownEngine.builder().profile(MarkdownProfile.gfm029()).build()
let html = engine.renderHtml("# Hello", options: HtmlOptions.safe()).html
```

| 子包 | 用途 |
| --- | --- |
| `markdown.core` | AST、源码与位置、诊断、限制、profile、query 和 rewrite |
| `markdown.engine` | parser、builder、events、追加会话、融合执行、能力与统计 |
| `markdown.render` | HTML、纯文本、Markdown、sink、source map 和富内容准备 |
| `markdown.extensions` | manifest、dialect、Syntax DSL、renderer DSL 和 SPI |
| `markdown.editor` | CST、snapshot、lint、编辑和范围格式化 |
| `markdown.artifact` | parse artifact 与 binary snapshot |
| `markdown.document` | document graph 与跨文档引用 |
| `markdown.testkit` | 第三方扩展 TCK |
| `markdown.native` | 显式链接的可选原生 line scanner |
| `markdown.node` | 显式安装的可选 KaTeX、Shiki 和 Mermaid 后端 |

解析与安全 HTML 通常从 `MarkdownEngine.builder().build()` 开始。配置、默认值、返回值和
失败条件随声明显示在站点中。按任务组合 API 时，阅读 [Cookbook](cookbook.md)、
[输入与资源](input-and-resources.md)或[文档系统](document-systems.md)。

## 本地生成与预览

先按[贡献指南](../CONTRIBUTING.md#准备环境)启用官方 STS 1.2.0，再从仓库根目录运行：

```sh
python3 scripts/generate_api_docs.py
```

命令固定使用 cjdoc v0.7.3 发布二进制并校验官方 SHA-256，完成注释、示例和站点检查后，
将 HTML 写入 `target/api-docs/html/`。生成文件属于构建产物，不提交到仓库。

通过本地 HTTP 服务预览：

```sh
python3 -m http.server 8000 --directory target/api-docs/html
```

打开 `http://localhost:8000/`，确认首页、搜索和类型页面可以访问。已提交的干净源码生成结果将源码链接绑定实际提交 SHA；本地未提交预览省略源码链接。PR 检查生成结果，`main` 的文档工作流通过后将站点部署到 GitHub Pages。

## 继续阅读

- [开始使用](getting-started.md)：构建消费工程并输出安全 HTML。
- [Cookbook](cookbook.md)：解析、查询、扩展、lint 与格式化的组合用法。
- [错误与能力](errors-and-capabilities.md)：处理结构化失败并确认执行模型。
