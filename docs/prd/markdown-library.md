# markdown 完整 Markdown 库产品需求文档

| 文档属性       | 内容                                    |
| ---------- | ------------------------------------- |
| 项目名称       | `markdown`                         |
| 公开根命名空间    | `markdown`                            |
| 产品类型       | 仓颉 Markdown 解析、转换、渲染与工具基础库            |
| PRD 版本     | 2.1                                   |
| 目标产品版本     | `markdown 0.9` breaking pre-GA       |
| 文档状态       | Draft for Review                      |
| 目标用户       | 仓颉应用、CLI、TUI、IDE、文档系统、静态站点及 Agent 开发者 |
| 核心实现约束     | 纯仓颉实现、无网络副作用、无非标准原生运行时依赖              |
| 默认解析方言     | CommonMark 0.31.2                     |
| 默认 HTML 策略 | Safe                                  |
| 文档日期       | 2026-08-17                            |

---

## 1. 文档约定

本文使用以下规范词：

* **必须**：`markdown 0.9` 发布阻断要求；满足后才可进入 1.0 GA 冻结。
* **应该**：原则上应实现，只有明确记录理由时可以推迟。
* **可以**：可选能力。
* **P0**：1.0 GA 范围。
* **P1**：1.1 计划范围。
* **P2**：2.0 或后续演进范围。
* **实验性 API**：允许在次版本中调整，不提供完整兼容承诺。

本文中的“Markdown”必须始终对应明确的标准版本或方言描述，不使用语义随时间变化的未版本化“Markdown latest”。

---

# 2. 产品摘要

`markdown` 是面向仓颉生态的完整 Markdown 基础库。

产品提供：

1. CommonMark 和 GFM 兼容解析。
2. 可版本化的 Markdown 方言模型。
3. 类型安全的方言 DSL、语法扩展 DSL 和 Renderer DSL。
4. 不可变语义 AST。
5. 精确源位置和 UTF-8、UTF-16 位置转换。
6. HTML、Safe HTML、纯文本和规范化 Markdown 渲染。
7. 可组合的解析扩展、转换扩展和渲染扩展。
8. 输入分块、输出 Sink、取消和资源预算。
9. AST 查询、遍历、转换和注解能力。
10. 面向 IDE 的 CST、Token、Source Map 和增量解析演进路径。
11. 官方规范测试、差分测试、模糊测试、复杂度测试和性能基准。
12. 配套 CLI、扩展测试套件和完整开发文档。

完整产品数据流为：

```text
Source
→ Versioned Dialect DSL
→ Compiled Dialect Plan
→ Bounded Parser
→ Syntax Representation
→ Semantic AST
→ Transform Pipeline
→ Explicit Renderer Policy
→ Output Sink
```

对于编辑器和保留格式场景，长期数据流为：

```text
Source Snapshot
→ Lossless CST
→ Semantic AST
→ Transform / Lint / Fix
→ Preserving Formatter
→ Text Edits
```

---

# 3. 背景与问题

仓颉生态中的应用如果分别实现 Markdown，通常会产生以下问题：

* 列表、引用、强调、链接和 HTML block 的行为不一致。
* “支持 Markdown”没有明确版本含义。
* GFM、脚注、数学公式等语法被硬编码在 parser 中。
* 解析器、HTML 转义、终端渲染被多个项目重复实现。
* AST 缺少精确源位置，无法支持 IDE、诊断和精确转换。
* 只保存语义值，丢失原始链接、实体和分隔符信息。
* 安全 HTML、规范 HTML 和 GitHub 风格 HTML 被混为一谈。
* 第三方扩展可以绕过资源限制或输出未转义 HTML。
* 深层嵌套和病态 delimiter 输入可能造成栈溢出或非线性耗时。
* 没有统一的取消、预算、输出限制和 Sink 错误传播。
* 没有官方规范测试、差分测试和长期性能基线。
* AST 缓存无法判断方言或扩展实现是否已经变化。
* 编辑器只能重新解析全文，且无法进行最小差异格式化。

`markdown` 的目标是成为仓颉生态统一的 Markdown 基础设施，而不是单一应用内部的字符串转 HTML 工具。

---

# 4. 标准依据

截至 2026 年 8 月 17 日，CommonMark 官方页面列出的最新正式规范为 **0.31.2**，发布日期为 2024 年 1 月 28 日，因此 `markdown 1.x` 的 CommonMark 精确兼容基线固定为该版本。

GitHub 公开的正式 GFM 规范版本为 **0.29-gfm**，发布日期为 2019 年 4 月 6 日。该规范定义了表格、任务列表、删除线、扩展自动链接和受限原始 HTML 等扩展。

GFM 规范同时说明，GitHub 在 Markdown 转换为 HTML 后还会执行额外后处理和安全净化。因此，GFM 的 `tagfilter` 不能被描述为完整 HTML sanitizer。

CommonMark 官方规范仓库包含规范本身和可执行一致性测试数据，其规范中嵌入了超过 500 个可作为 conformance tests 的示例。`markdown` 必须直接接入这些测试，而不是维护一套手工近似测试。

---

# 5. 产品愿景

为仓颉提供一个：

> 标准明确、行为确定、安全默认、资源有界、可扩展、可用于构建上层文档系统的 Markdown 基础库。

长期目标是让仓颉应用不再重复解决：

* Markdown 方言差异；
* 块级和行内优先级；
* 表格、任务列表和自动链接；
* 原始 HTML 与 URI 安全；
* AST、CST 和源位置；
* 文本提取与终端渲染；
* 方言扩展与扩展冲突；
* 格式化和最小差异修改；
* 增量重解析；
* 复杂度攻击；
* 规范测试与差分验证。

---

# 6. 产品原则

## 6.1 标准版本必须显式

不得使用语义随时间变化的内部 `latest` profile。

允许提供便利别名：

```cangjie
MarkdownProfile.commonMark()
MarkdownProfile.gfm()
```

但便利别名在同一主版本中必须固定。

例如：

```text
markdown 1.x:
commonMark() == commonmark-0.31.2
gfm()        == gfm-modern-v1
```

不得在 `1.4` 中将 `commonMark()` 静默切换到未来的 CommonMark 版本。

## 6.2 安全与规范兼容必须分离

以下输出模式必须是不同类型或不同显式构造器：

```text
SpecCompatible
GfmCompatible
Safe
```

不得让一个含糊的 `renderHtml()` 同时承担：

* 官方规范测试；
* 可信文档渲染；
* 不可信用户内容渲染。

## 6.3 AST 是主要稳定抽象

`String → HTML` 只是便利能力。

公共核心抽象必须是：

```text
Source
→ Document
→ Transform
→ Renderer
```

## 6.4 DSL 必须受约束

DSL 用于声明方言、有限语法、转换和 renderer，不用于执行任意文法脚本。

必须优先：

* 类型安全；
* 确定性；
* 有界 lookahead；
* 无任意回溯；
* 可静态验证；
* 可生成 fingerprint。

## 6.5 默认行为必须确定

相同：

```text
输入
+ profile
+ dialect fingerprint
+ engine version
+ renderer policy
```

必须得到相同：

* AST；
* NodeId；
* SourceSpan；
* diagnostics；
* HTML；
* formatted Markdown。

不得依赖哈希表随机迭代顺序、内存地址或平台默认换行。

## 6.6 资源使用必须有界

输入大小、行长度、嵌套深度、节点数、扫描步数、扩展回调次数和输出大小均必须可以限制。

## 6.7 普通 Markdown 错误不应成为异常

未闭合强调、链接和代码分隔符通常应解释为普通文本，而不是返回 parser error。

## 6.8 核心层不承担文档系统全部职责

代码高亮、HTML sanitizer、远程图片、跨文档链接、代码执行和 Mermaid 执行应通过独立模块或宿主系统实现。

---

# 7. 目标

## 7.1 P0：1.0 GA 目标

1. 完整通过 CommonMark 0.31.2 官方规范测试。
2. 完整通过 GFM 0.29-gfm 官方规范测试。
3. 提供基于 CommonMark 0.31.2 的现代 GFM 组合 profile。
4. 提供版本化 Dialect DSL。
5. 提供有限、类型安全的 Syntax DSL。
6. 提供结构化、安全的 Renderer DSL。
7. 提供不可变语义 AST。
8. 提供 UTF-8 SourceSpan 和 UTF-16 位置映射。
9. 提供原始值、语义值和规范化比较值。
10. 提供 HTML、Safe HTML、纯文本和规范化 Markdown renderer。
11. 提供 AST Walker、Visitor 和 TreeRewriter。
12. 提供取消、操作预算和资源限制。
13. 提供 String、UTF-8 bytes、stream 和 chunked input。
14. 提供面向 Sink 的流式输出。
15. 提供扩展 manifest、SPI 版本和能力矩阵。
16. 提供扩展冲突检测和 Extension TCK。
17. 提供方言编译计划和 fingerprint。
18. 提供 capability introspection。
19. 提供 CLI、规范测试和性能测试。
20. 核心库仅依赖仓颉标准库。

## 7.2 P1：1.1 目标

1. Lossless CST。
2. Syntax Token API。
3. Transform DSL。
4. Preserving Formatter。
5. Range Formatting。
6. Renderer Source Map。
7. Lint、Fix-It 和 Explain Mode。
8. Annotation Store。
9. Node Origin 和变换来源追踪。
10. Event API。
11. ANSI/TUI renderer。
12. Footnotes、Front Matter、Math、Definition List 等官方扩展。
13. 稳定 Parse Artifact。
14. Sanitizer adapter。
15. 异步 Sink adapter。
16. Document Snapshot API。

## 7.3 P2：2.0 或后续目标

1. 真正的局部增量解析。
2. 跨 snapshot 稳定 NodeId。
3. 增量 diagnostics。
4. 外部 JSON/YAML 方言描述。
5. 插件隔离执行。
6. 多文档引用解析。
7. 文档图。
8. HTML-to-Markdown。
9. 稳定二进制 AST/CST 格式。
10. 大文档分页或虚拟化语法树。

---

# 8. 非目标

1. 不实现浏览器 DOM。
2. 不实现完整通用 HTML sanitizer。
3. 不内置代码语法高亮引擎。
4. 不执行代码块、公式、图表或脚本。
5. 不主动访问网络。
6. 不主动读取 include 文件。
7. 不下载图片。
8. 不实现 WYSIWYG 编辑器。
9. 不保证兼容所有历史 Markdown 实现。
10. 不默认启用所有社区扩展。
11. 不通过 FFI 包装 `cmark` 作为生产实现。
12. 不提供任意回溯 grammar DSL。
13. 不执行从 JSON、YAML 或网络载入的代码回调。
14. 不在核心库中收集远程遥测。
15. 不由核心库拥有 wall-clock timeout 计时器。
16. 不允许第三方扩展绕过宿主进程权限。

---

# 9. 用户与核心场景

## 9.1 应用开发者

```text
不可信 Markdown
→ parse
→ AST
→ safe HTML
```

## 9.2 TUI 和终端应用

```text
Markdown
→ AST
→ ANSI/TUI renderer
```

1.0 可以先通过 PlainTextRenderer 和自定义 Renderer DSL 实现，官方 ANSI renderer 在 P1 提供。

## 9.3 文档工具

需要提取：

* 标题树；
* 链接；
* 图片；
* 代码块；
* 引用定义；
* Front Matter；
* 自定义容器；
* API 文档段落。

## 9.4 IDE 和编辑器

需要：

* SourceSpan；
* UTF-16 映射；
* Outline；
* Folding Range；
* Syntax Token；
* 点击预览定位源文档；
* Range Formatting；
* 增量解析。

## 9.5 Agent 与聊天系统

需要：

* Safe HTML；
* raw HTML 禁用；
* 危险 URI 拒绝；
* 取消；
* 节点和输出预算；
* 确定性文本提取；
* 不因模型输出的病态 Markdown 阻塞进程。

## 9.6 静态站点生成器

需要：

* 自定义方言；
* 标题 ID；
* 目录；
* 链接改写；
* 代码高亮 hook；
* 自定义容器；
* 可缓存 parse artifact。

---

# 10. 总体架构

## 10.1 核心数据流

```text
SourceInput
→ SourceBuffer
→ MarkdownDialect DSL
→ DialectCompiler
→ CompiledMarkdownDialect
→ ParseSession
→ Block Parse
→ Reference Resolution
→ Inline Parse
→ Extension Postprocess
→ AST Validation
→ Document
→ Transform Pipeline
→ Renderer
→ Output Sink
```

## 10.2 表示层

```text
SourceBuffer
    ↓
Syntax Representation / CST
    ↓
Semantic AST
    ↓
Event / Visitor / Renderer
```

职责：

| 表示                    | 职责                 | 稳定性         |
| --------------------- | ------------------ | ----------- |
| SourceBuffer          | 原始输入和切片            | P0 稳定       |
| Syntax Representation | token、trivia、原始分隔符 | P0 预留，P1 公开 |
| Semantic AST          | 稳定文档语义             | P0 稳定       |
| Event                 | 流式消费和低耦合处理         | P1          |
| Rendered Source Map   | 输出到源文档映射           | P1          |

## 10.3 依赖方向

```text
source
  ↓
core AST
  ↓
profile / dialect contracts
  ↓
parser
  ↓
transform
  ↓
renderer
  ↓
public façade
```

必须禁止：

```text
AST → HTML renderer
parser core → CLI
CommonMark parser → GFM extension
production module → testkit
```

---

# 11. Profile 与方言模型

## 11.1 内置 Profile

| Profile ID          | 语义                           |
| ------------------- | ---------------------------- |
| `commonmark-0.31.2` | 精确 CommonMark 0.31.2         |
| `gfm-0.29`          | 精确 GFM 0.29-gfm              |
| `gfm-modern-v1`     | CommonMark 0.31.2 加 GFM 扩展集合 |
| `custom`            | 显式基础 profile 加扩展             |

## 11.2 默认值

默认 parser profile：

```text
commonmark-0.31.2
```

默认不得启用：

* 表格；
* 删除线；
* 任务列表；
* 脚注；
* Front Matter；
* 数学公式；
* Heading ID。

## 11.3 `gfm-modern-v1`

包含：

* Tables；
* Task list items；
* Strikethrough；
* Extended autolinks；
* Tag filter。

`gfm-modern-v1` 是项目定义的现代组合，不得被描述为正式 GFM 规范的精确实现。

## 11.4 Profile 升级规则

* 新标准版本必须获得新的 profile ID。
* 已发布 profile 的语义不得静默改变。
* 同一主版本内便利别名不得更换目标。
* 规范修复必须关联规范章节或测试编号。
* 影响 AST 的行为修复必须记录在 changelog。

---

# 12. Dialect DSL

## 12.1 目标

Dialect DSL 用于声明：

* 基础 profile；
* 扩展；
* 扩展版本；
* parser options；
* 方言级安全限制；
* 依赖；
* 冲突；
* 规则顺序；
* renderer 覆盖要求。

示例为 API 草案，不代表最终仓颉语法：

```cangjie
let dialect = MarkdownDialect.define(
    id: "docs-v1",
    version: "1.0.0"
) {
    base(CommonMark.v0_31_2)

    enable(Gfm.tables)
    enable(Gfm.taskLists)
    enable(Gfm.strikethrough)

    enable(Footnotes.v1)
    enable(HeadingIds.v1)

    requireRenderer(HtmlRenderer.kind)
    requireRenderer(PlainTextRenderer.kind)
}
```

## 12.2 编译过程

```text
Dialect DSL
→ Schema validation
→ Dependency resolution
→ Conflict detection
→ Rule normalization
→ Rule ordering
→ Dispatch table compilation
→ CompiledMarkdownDialect
```

运行时 parser 不得每次重新解释 DSL。

## 12.3 核心类型

```text
MarkdownDialect
DialectId
DialectVersion
DialectDescriptor
CompiledMarkdownDialect
DialectFingerprint
ParserPlanVersion
RuleId
ExtensionImplementationId
```

## 12.4 Fingerprint

`DialectFingerprint` 必须至少包含：

* 基础 profile ID；
* 方言 ID 和版本；
* parser-affecting options；
* 扩展 ID；
* 扩展语义版本；
* 扩展实现版本；
* SPI 版本；
* 规范化规则；
* 规则顺序；
* parser plan version。

计算方式：

```text
Normalized Dialect Descriptor
→ canonical serialization
→ SHA-256
→ DialectFingerprint
```

必须排除 fingerprint 字段本身。

相同语义配置必须产生相同 fingerprint。

## 12.5 指纹分层

避免把无关配置全部混入 parse cache：

```text
DialectFingerprint
    只包含解析语义

EngineFingerprint
    DialectFingerprint
    + source policy
    + diagnostic policy
    + result-affecting limits

RendererFingerprint
    renderer kind
    + renderer policy
    + renderer extension versions
```

## 12.6 静态验证

构建 engine 时必须检查：

* 重复 extension ID；
* 不兼容 profile；
* 循环依赖；
* extension version 不满足；
* SPI version 不满足；
* rule ID 冲突；
* delimiter 冲突；
* block opener 冲突；
* 无界 lookahead；
* 缺失 renderer；
* 不受支持的嵌套；
* 不确定的 tie-break；
* extension capability 声明不完整。

---

# 13. Syntax DSL

## 13.1 定位

Syntax DSL 是受约束的仓颉内部 DSL，用于声明常见 Markdown 扩展。

支持：

* 成对 inline delimiter；
* 单 token inline syntax；
* 行首 block；
* 成对 container block；
* literal block；
* metadata suffix；
* 属性捕获。

不支持：

* 任意递归 grammar；
* 任意回溯正则；
* 动态执行脚本；
* 无界 lookahead；
* 无界捕获。

## 13.2 Inline Syntax DSL

示例：

```cangjie
let highlight = InlineSyntax.define("highlight") {
    delimiter("==")
    contentMode(InlineContentMode.parseChildren)
    nesting(NestingPolicy.allow)
    maximumLookahead(4096)
    priority(100)

    emit { content, span =>
        CustomInline(
            extensionId: "highlight",
            kindId: "highlight",
            children: content,
            span: span
        )
    }
}
```

必须可声明：

* opener；
* closer；
* 转义行为；
* flanking 规则；
* 是否允许嵌套；
* 是否解析内部 inline；
* 最大 delimiter 长度；
* 最大 lookahead；
* priority；
* conflict group；
* AST emitter。

## 13.3 Block Syntax DSL

示例：

```cangjie
let admonition = BlockSyntax.define("admonition") {
    opener {
        prefix(":::")
        captureIdentifier("kind")
        captureRest("title")
    }

    closer {
        exact(":::")
    }

    content(BlockContentMode.markdown)
    nesting(NestingPolicy.allow)
    maximumBlockBytes(1024 * 1024)
    priority(100)

    emit { match, children, span =>
        CustomBlock(
            extensionId: "admonition",
            kindId: match["kind"],
            attributes: {
                "title": match["title"]
            },
            children: children,
            span: span
        )
    }
}
```

## 13.4 规则确定性

每条 DSL 规则必须声明或推导：

```text
phase
priority
tieBreak
maximumLookahead
maximumCaptureLength
maximumDelimiterLength
nestingPolicy
backtrackingPolicy
resourceCost
```

固定排序：

```text
phase
→ priority
→ registration order
→ extension ID
→ rule ID
```

## 13.5 正则限制

Syntax DSL 不得接受可能产生灾难性回溯的任意正则。

可选方案：

* 仅支持固定前缀；
* 仅支持线性时间正则子集；
* 编译为 DFA；
* 无法证明有界时拒绝编译。

## 13.6 Escape Hatch

DSL 无法表示的复杂语法可以使用 Parser SPI。

Parser SPI 仍必须遵守：

* SourceSpan；
* OperationBudget；
* CancellationToken；
* 节点限制；
* 确定性；
* diagnostics；
* extension trust boundary。

---

# 14. Renderer DSL

## 14.1 目标

扩展语法必须能够为不同输出后端提供渲染逻辑：

```text
HTML
Safe HTML
Plain Text
Markdown
ANSI/TUI
```

## 14.2 结构化 HTML

推荐接口：

```cangjie
html("admonition") { node =>
    element("aside") {
        classToken("admonition")
        classToken(node.kind)

        element("header") {
            text(node.title)
        }

        renderChildren(node)
    }
}
```

结构化 builder 必须自动处理：

* tag name 校验；
* text escaping；
* attribute escaping；
* URI policy；
* class token 校验；
* 输出预算；
* source map；
* cancellation。

## 14.3 禁止默认字符串拼接

以下接口不得作为推荐路径：

```cangjie
output.write("<div>" + userValue + "</div>")
```

普通字符串必须按文本输出。

仅显式类型：

```text
TrustedHtml
```

可以绕过转义。

`TrustedHtml` 必须放入显式 unsafe API 或显式 unsafe 构造器中。

## 14.4 Renderer DSL 示例

```cangjie
let highlightRenderer = RendererExtension.define("highlight") {
    html("highlight") { node, html =>
        html.element("mark") {
            html.renderChildren(node)
        }
    }

    text("highlight") { node, output =>
        output.renderChildren(node)
    }

    markdown("highlight") { node, output =>
        output.text("==")
        output.renderChildren(node)
        output.text("==")
    }
}
```

## 14.5 缺失 Renderer

扩展必须声明缺失 renderer 时的策略：

```text
Error
RenderChildren
RenderLiteral
Drop
CustomFallback
```

默认必须为：

```text
Error
```

不得静默丢失内容。

---

# 15. Transform DSL

Transform DSL 在 P1 提供，底层 P0 使用 TreeRewriter。

示例：

```cangjie
let transform = MarkdownTransform.define {
    select<Heading> {
        where { it.level == 1 }
        apply { it.addClass("page-title") }
    }

    select<Link> {
        where { it.destination.isRelative }
        apply { it.withDestination(resolve(it.destination)) }
    }

    select<CodeBlock> {
        where { it.language == "mermaid" }
        replace {
            CustomBlock(
                extensionId: "diagram",
                kindId: "mermaid",
                literal: it.literal
            )
        }
    }
}
```

Transform DSL 必须：

* 类型安全；
* 不修改原 AST；
* 产生新的经过验证的 AST；
* 保留 Node Origin；
* 受 OperationBudget 限制；
* 具有固定 pass 顺序。

---

# 16. 输入与 Source 模型

## IN-001：String 输入

必须支持仓颉 `String`。

## IN-002：UTF-8 字节输入

必须支持：

```text
Strict
ReplaceInvalid
```

`Strict`：

* 遇到非法 UTF-8 返回 `InvalidEncoding`。

`ReplaceInvalid`：

* 使用 U+FFFD；
* 产生 diagnostic；
* SourceSpan 仍映射到原始字节。

不得使用平台默认编码。

## IN-003：Stream 输入

必须支持标准输入流抽象。

读取失败必须返回：

```text
InputReadFailure
```

并保留底层 cause。

## IN-004：Chunked Input

必须提供：

```cangjie
let session = engine.newSession()

session.feed(chunk1)
session.feed(chunk2)

let result = session.finish()
```

无论如何切分 chunk，最终结果必须一致。

必须测试：

* 每字节一个 chunk；
* 随机 chunk；
* UTF-8 多字节字符中间；
* CRLF 中间；
* fence 中间；
* entity 中间；
* HTML tag 中间；
* link destination 中间；
* DSL delimiter 中间。

## IN-005：Chunked 语义

1.0 的 chunked API 表示分块输入，不保证在 `finish()` 前产生最终语义节点。

原因包括：

* 后续 reference definition 可以影响前文 link；
* Setext heading 依赖下一行；
* block 边界可能在后续输入确定；
  -扩展可能需要有限跨 chunk lookahead。

## IN-006：换行

必须接受：

* LF；
* CRLF；
* CR。

规范化 renderer 默认输出 LF。

SourceSpan 必须对应原始输入。

## IN-007：BOM

必须明确处理 UTF-8 BOM，并保留原始 byte offset 映射。

## IN-008：SourceBuffer

`ParseResult` 默认持有不可变 `SourceBuffer`。

必须提供：

```cangjie
source.slice(span)
source.text(node)
source.line(lineNumber)
```

## IN-009：Literal Storage

必须支持：

```text
Copy
SourceSlice
```

P1 可以增加：

```text
Chunked
```

代码块、HTML block 和长文本默认应该使用 SourceSlice，避免重复复制。

## IN-010：Detach

必须提供：

```cangjie
let detached = document.detach()
```

将依赖 SourceBuffer 的 slice 转换为独立拥有数据，使调用者可以释放原始输入。

---

# 17. 位置模型

## 17.1 规范位置

唯一规范位置为：

```text
UTF-8 byte offset
```

SourceSpan 使用半开区间：

```text
[startByte, endByte)
```

## 17.2 位置类型

```text
SourceOffset
SourceSpan
SourcePosition
VisualPosition
Utf16Position
SourcePositionMap
```

## 17.3 SourcePosition

包含：

```text
line
byteColumn
```

行和列从 1 开始。

## 17.4 VisualPosition

用于展示：

* tab 按固定 tab stop 展开；
* 不作为修改文本的规范位置；
* 不承诺与 grapheme cluster 数量一致。

## 17.5 UTF-16 Position

必须提供 UTF-8 到 UTF-16 code unit 的转换，用于 LSP 等协议。

转换要求：

* 映射可缓存；
* 不修改源文本；
* 支持 emoji；
* 支持组合字符；
* 支持 CRLF；
* 非法 UTF-8 替换策略下仍可映射。

## 17.6 Unicode Normalization

parser 不得对整个输入执行 NFC、NFD 等 Unicode normalization。

只有标准明确要求的局部比较，例如 reference label normalization，才可以规范化。

---

# 18. 解析要求

## PAR-001：解析阶段

```text
Input view
→ Block parsing
→ Reference collection
→ Inline parsing
→ Extension postprocessing
→ AST validation
```

## PAR-002：块级结构

必须支持：

* Document；
* Block quote；
* Bullet list；
* Ordered list；
* List item；
* Paragraph；
* ATX heading；
* Setext heading；
* Thematic break；
* Indented code block；
* Fenced code block；
* HTML block；
* Link reference definition；
* Blank line 语义；
* GFM table。

## PAR-003：行内结构

必须支持：

* Text；
* Soft break；
* Hard break；
* Backslash escape；
* Entity；
* Code span；
* Emphasis；
* Strong；
* Link；
* Image；
* Autolink；
* Raw HTML；
* GFM strikethrough；
* GFM extended autolink。

## PAR-004：任务列表

GFM task list 必须保留：

```text
checked
unchecked
markerSpan
```

不得将 checkbox 作为输入控件状态写回 AST。

## PAR-005：引用定义

Document 必须提供引用定义表：

```text
labelRaw
labelNormalized
destinationRaw
destination
titleRaw
title
sourceSpan
isEffective
shadowedBy?
```

Link 节点必须区分：

```text
Inline
FullReference
CollapsedReference
ShortcutReference
Autolink
ExtendedAutolink
```

## PAR-006：代码块信息

Fenced CodeBlock 必须保留：

```text
fenceCharacter
fenceLength
openingFenceSpan
closingFenceSpan?
infoRaw
language
attributesRaw
literal
```

核心库不得执行代码。

## PAR-007：Raw HTML

parser 负责识别 raw HTML，renderer 负责决定：

* PassThrough；
* Escape；
* Drop；
* Sanitize；
* Custom。

## PAR-008：容错

以下输入默认不能造成 hard parse error：

```markdown
**unfinished
[unfinished
`unfinished
:::unfinished
```

它们应按照 profile 或扩展规则退化为文本或普通 block。

## PAR-009：非递归核心

以下路径必须使用显式栈或迭代实现：

* block containers；
* AST walker；
* AST validation；
* renderer traversal；
* formatter traversal；
* transform traversal。

## PAR-010：确定性

不得使用：

* 内存地址作为顺序；
* 随机 hash 顺序；
* 不稳定 extension registry；
* 未定义的相同 priority 行为。

---

# 19. 原始值、语义值与比较值

涉及解析和安全的字段必须区分三个层次。

## 19.1 原始值

来自 SourceBuffer：

```text
destinationRaw
titleRaw
labelRaw
infoRaw
entityRaw
delimiterRaw
```

## 19.2 语义值

按照 Markdown profile 解码后的值：

```text
destination
title
text
language
```

## 19.3 比较值

只用于规范匹配或安全判断：

```text
labelNormalized
schemeNormalized
extensionIdNormalized
```

## 19.4 禁止事项

不得：

* 重复 entity decode；
* 将 HTML escaped 值存入 AST；
* 使用输出转义后的值进行 URI policy；
* 使用展示值进行 reference label 比较；
* 将 percent-decoded URL 直接替换原始 destination。

---

# 20. AST 模型

## 20.1 AST 原则

AST 必须：

* 不可变；
* 无环；
* 可并发读取；
* 节点顺序确定；
* 不暴露 parser 临时状态；
* 支持扩展节点；
* 支持 SourceSpan；
* 支持 Node Origin。

0.9 的公开 AST 必须由 `Document` snapshot 持有 arena；节点身份使用轻量
`NodeRef`，类型化访问使用 value view。不得为每个语法节点构造独立、互相引用的
公开 class 对象树，也不得保留 0.8 object-tree AST 的运行时兼容适配器。

arena 的固定契约：

* node record 使用 4096 条固定 chunk；
* child id 使用 16384 条固定 chunk；
* snapshot/transform 以 copy-on-write chunk 实现结构共享；
* Parsed origin 由 node span 派生，不为每个普通解析节点分配 `NodeOrigin` 对象；
* extension、transform、synthetic 和 deserialized origin 才保存附加 metadata；
* `Document` 的生命期覆盖所有 `NodeRef`/view，跨 document 的引用必须拒绝。

## 20.2 Block 节点

| 节点              | 主要字段                                           |
| --------------- | ---------------------------------------------- |
| `Document`      | children、references、profile、dialectFingerprint |
| `BlockQuote`    | children                                       |
| `List`          | kind、start、delimiter、tight、children            |
| `ListItem`      | taskState、children                             |
| `Paragraph`     | inline children                                |
| `Heading`       | level、children                                 |
| `ThematicBreak` | marker metadata                                |
| `CodeBlock`     | kind、literal、info、fence metadata               |
| `HtmlBlock`     | literal、block type                             |
| `Table`         | alignments、rows                                |
| `TableRow`      | header、cells                                   |
| `TableCell`     | alignment、children                             |
| `CustomBlock`   | extension identity、kind、payload、children       |

## 20.3 Inline 节点

| 节点              | 主要字段                                     |
| --------------- | ---------------------------------------- |
| `Text`          | value                                    |
| `SoftBreak`     | 无                                        |
| `HardBreak`     | syntax kind                              |
| `CodeSpan`      | literal、delimiter metadata               |
| `Emphasis`      | children                                 |
| `Strong`        | children                                 |
| `Strikethrough` | children                                 |
| `Link`          | destination、title、syntax kind、children   |
| `Image`         | destination、title、syntax kind、children   |
| `HtmlInline`    | literal                                  |
| `CustomInline`  | extension identity、kind、payload、children |

## 20.4 NodeId

每个节点必须具有 NodeId。

要求：

* 单个 Document 内唯一；
* 同输入、同方言、同版本下确定；
* 不使用内存地址；
* 1.0 不保证跨编辑稳定；
* P2 可以增加 StableNodeId。

0.9 按确定性 arena record 创建顺序分配。

## 20.5 Node Origin

P1 提供：

```text
Parsed
ExtensionGenerated
Transformed
Synthetic
Deserialized
```

结构：

```text
NodeOrigin {
    kind
    sourceNodeIds
    sourceSpan?
    transformId?
    extensionId?
}
```

## 20.6 Custom Node

Custom Node 必须使用：

```text
extensionId
extensionSemanticVersion
localKindId
typed payload
```

不得要求每个第三方扩展修改核心 enum。

## 20.7 AST 不变量

必须验证：

* Document 无父节点；
* 节点只有一个父节点；
* NodeId 唯一；
* SourceSpan 合法；
* 子节点顺序确定；
* block 不出现在 inline 容器；
* inline 不直接成为 Document 子节点；
* table 行列满足方言规则；
* custom node 对应扩展存在；
* extension payload 类型匹配；
* synthetic 节点明确标记；
* transform 后结构仍有效。

---

# 21. CST 与 Syntax Token

## 21.1 CST 定位

完整 Lossless CST 在 P1 公开，但 P0 架构必须预留。

CST 负责保留：

* 空格；
* 换行；
* marker；
* delimiter；
* 原始 entity；
* 原始链接写法；
* fence；
* trivia；
* 无效或未完成语法。

## 21.2 核心类型

```text
SyntaxTree
SyntaxNode
SyntaxToken
Trivia
SyntaxKind
SyntaxToAstMap
```

## 21.3 AST 与 CST

必须支持：

```text
AST node → originating syntax nodes
Syntax node → semantic AST node?
```

不是所有 syntax token 都必须对应 AST 节点。

## 21.4 Syntax Token API

P1 提供 token stream，至少区分：

* text；
* whitespace；
* heading marker；
* list marker；
* block quote marker；
* fence；
* info string；
* delimiter；
* link label；
* link destination；
* HTML；
* entity；
* extension token；
* invalid token。

## 21.5 Preserving Formatter 依赖

Preserving Formatter 必须基于 CST 或等价 lossless 表示，不能只依赖 AST 猜测原始格式。

---

# 22. AST 遍历、查询与转换

## AST-001：Walker

必须提供非递归 Walker：

```text
Enter(node)
Exit(node)
```

## AST-002：Visitor

必须提供类型化 Visitor。

## AST-003：查询

应提供：

* 按 NodeId；
* 按节点类型；
* 按 SourceSpan；
* 查找祖先；
* 查找后代；
* 提取标题；
* 提取链接；
* 提取图片；
* 提取代码块；
* 提取 custom node。

## AST-004：TreeRewriter

必须支持：

```text
Keep
Replace
Remove
InsertBefore
InsertAfter
ReplaceChildren
MapText
```

## AST-005：结构共享

TreeRewriter 应使用路径复制、copy-on-write 或持久化结构，避免修改一个节点时复制整个文档。

公共 API 不绑定具体内存实现。

## AST-006：Transform Pipeline

P1 提供可组合 pass：

```text
Parse
→ Extension Postprocess
→ User Transform
→ Document Services
→ Renderer Preparation
```

每个 pass 声明：

```text
id
version
requires
produces
priority
purity
```

必须检测：

* 循环依赖；
* 重复 pass；
* 缺失依赖；
* 不确定顺序；
* transform 后不变量错误。

---

# 23. Annotation Store

P1 提供类型安全 side table：

```text
AnnotationStore
AnnotationKey<T>
```

用途：

* heading slug；
* syntax highlighting result；
* lint state；
* resolved external link；
* renderer cache；
* semantic category。

要求：

* AST 保持不可变；
* annotation 不进入默认 AST equality；
* annotation 生命周期独立；
* key 类型安全；
* 可以按 NodeId 查询；
* 可显式决定是否纳入 cache fingerprint。

不得在 AST 节点中加入：

```text
Map<String, Any>
```

作为通用扩展槽。

---

# 24. HTML Renderer

## 24.1 HTML Policy

必须提供：

| 模式               | Raw HTML           | URI 安全 | 默认用途         |
| ---------------- | ------------------ | ------ | ------------ |
| `SpecCompatible` | 按 profile 输出       | 仅规范要求  | 规范测试         |
| `GfmCompatible`  | 应用 tagfilter，其他可保留 | GFM 语义 | 可信 GFM 文档    |
| `Safe`           | 默认全部转义             | 强制策略   | 用户和 Agent 内容 |

默认：

```text
HtmlPolicy.safe()
```

## 24.2 Safe HTML

必须：

* 正确转义 text；
* 正确转义 attribute；
* 转义 raw HTML；
* 拒绝危险 URI；
* 限制 data URI；
* 不输出事件处理属性；
* 不把 info string 直接拼接到 class；
* 遵守输出限制；
* 不信任扩展普通字符串；
* 对 task checkbox 输出不可执行控件；
* 不生成脚本。

## 24.3 Link 与 Image 策略分离

必须提供：

```text
LinkUriPolicy
ImageUriPolicy
```

原因：

* `mailto:` 对 link 有意义，对 image 无意义；
* image 可能触发远程请求和隐私泄漏；
* SVG data URI 风险高于普通位图；
* link 和 image 的允许 scheme 不同。

Safe HTML 配置至少支持：

```text
allowRemoteImages
allowDataImages
allowedImageMimeTypes
rewriteExternalLinks
externalLinkRel
externalLinkTarget
```

## 24.4 URI 处理

URI 检查必须：

1. 处理控制字符和空白混淆；
2. 解析 scheme；
3. 对 scheme 进行大小写无关比较；
4. 按 link/image policy 判断；
5. 最后执行 HTML attribute escaping。

不得只做：

```text
raw.startsWith("javascript:")
```

## 24.5 Raw HTML 策略

```text
Escape
Drop
PassThrough
Sanitize
CustomHandler
```

`PassThrough` 必须通过显式 unsafe API 启用。

## 24.6 Sanitizer Adapter

P1 提供：

```text
HtmlSanitizerPort
```

建议组合：

```text
AST
→ HTML Renderer
→ Sanitizer
→ Output
```

或：

```text
RawHtml Node
→ Sanitizer Callback
→ Safe Fragment
```

Sanitizer 失败默认必须拒绝输出。

## 24.7 Source Map

P1 支持：

```text
RenderedOutput {
    content
    sourceMap
}
```

Source Map 项：

```text
outputRange
sourceSpan
nodeId
generated
```

用于：

* 预览同步滚动；
* 点击 HTML 定位 Markdown；
* TUI 交互；
* 渲染错误定位。

---

# 25. Plain Text Renderer

必须支持：

* 段落边界；
* 列表层级；
* heading 文本；
* link text；
* 可选 URL；
* image alt；
* code block literal；
* table 线性化；
* raw HTML 可见文本；
* soft break 策略；
* hard break；
* custom node fallback。

默认不得输出 ANSI 控制序列。

主要用途：

* 搜索索引；
* 摘要；
* TTS；
* Agent 上下文；
* 日志；
* 无样式终端。

---

# 26. Markdown Renderer 与 Formatter

## 26.1 Canonical Renderer

P0 必须提供 AST 到规范化 Markdown。

目标：

```text
parse(render(ast)) ≈ ast
```

不承诺恢复原始书写形式。

## 26.2 幂等性

必须满足：

```text
format(format(source)) == format(source)
```

## 26.3 选项

至少支持：

* LF/CRLF；
* bullet marker；
* ordered delimiter；
* heading style；
* emphasis marker；
* strong marker；
* fence marker；
* fence 最小长度；
* table padding；
* final newline；
* 最大行宽；
* 是否重排段落。

默认不得自动重排普通段落。

## 26.4 语义保持

不得改变：

* link destination；
* code block literal；
* code span literal；
* raw HTML literal；
* ordered list start；
* task state；
* table alignment；
* soft/hard break 语义。

## 26.5 Preserving Formatter

P1 提供：

```text
CanonicalFormatter
PreservingFormatter
```

Preserving Formatter 目标：

* 尽量保留 marker；
* 尽量保留空行；
* 尽量保留 entity 写法；
* 尽量保留 fence 风格；
* 只修改必要范围；
* 不改变未触及扩展语法。

## 26.6 Range Formatting

P1 提供：

```text
formatRange
formatNode
formatChangedRanges
```

扩展缺少 formatter 时必须：

* 保留原始 source；
* 或拒绝格式化相关范围；
* 或使用显式 fallback。

不得静默删除扩展节点。

---

# 27. Event API

P1 提供：

事件值不得引用 `Document`、`MarkdownNode` 或其他已构造 AST 对象。事件至少包含
kind、source range、必要属性和文本的 source range/semantic value。

必须区分两种模式：

```text
ResolvedEventMode
RawBlockEventMode
```

`ResolvedEventMode`：

* 对 replayable `SourceBuffer` 执行两遍：第一遍建立 reference index，第二遍产生完整语义事件；
* chunked 输入在 finish 前允许缓存，但不得伪装为增量输出。

`RawBlockEventMode`：

* 必须随 chunk 增量输出已经闭合的 block；
* 不承诺引用已解析；
* 不得伪装为最终语义事件。

从完整 AST walk 产生事件不能被描述为低内存流式解析。

HTML 便利入口必须提供显式执行选择 `FullAst`、`PreferFused`、`RequireFused`，
并在结果中报告实际使用的 `FullAst` 或 `Fused` 路径。document processor、需要完整
AST 的 transform、artifact/CST/annotation 或无法等价 lower 的扩展存在时，
`PreferFused` 回退完整 AST，`RequireFused` 返回结构化错误；不得静默降低能力。

---

# 28. 扩展系统

## 28.1 扩展类别

支持：

1. Block syntax extension；
2. Inline syntax extension；
3. Document postprocessor；
4. AST transform；
5. Renderer extension；
6. Lint extension；
7. Formatter extension。

## 28.2 Extension Manifest

每个扩展必须声明：

```text
extensionId
semanticVersion
implementationVersion
requiredSpiVersion
supportedProfiles
dependencies
conflicts
capabilities
rules
ruleBudget
trustLevel
```

## 28.3 版本区分

必须区分：

```text
扩展语义版本
扩展实现版本
Extension SPI 版本
DSL schema 版本
Parser plan 版本
```

## 28.4 Capability Matrix

扩展必须声明：

```text
Parse
SpecHtml
SafeHtml
PlainText
Markdown
CST
Format
Serialize
Incremental
Lint
```

示例：

```text
ExtensionCapabilities {
    parses: true
    rendersSpecHtml: true
    rendersSafeHtml: true
    rendersText: true
    rendersMarkdown: false
    supportsCst: true
    supportsIncremental: false
}
```

## 28.5 信任边界

必须明确：

```text
内置扩展
    由 markdown 维护和信任

代码扩展
    具有宿主进程权限
    由宿主应用信任

外部数据 DSL
    不允许携带任意代码

TrustedHtml
    显式 unsafe
```

核心库不能声称第三方代码扩展无文件或网络副作用。

## 28.6 扩展失败

```text
ExtensionFailure {
    extensionId
    semanticVersion
    implementationVersion
    phase
    ruleId?
    sourceSpan?
    cause
}
```

扩展失败不得破坏 parser 内部状态。

## 28.7 Extension TCK

必须提供：

```text
MarkdownExtensionTestKit
```

每个扩展至少测试：

* chunk 分割一致性；
* SourceSpan；
* Safe HTML；
* 未闭合语法；
* 嵌套；
* 冲突；
* 限制；
* cancellation；
* formatter；
* renderer coverage；
* fuzz；
* 确定性。

---

# 29. 官方扩展路线

| 扩展                    | 目标版本 | 默认            |
| --------------------- | ---- | ------------- |
| GFM Tables            | 1.0  | 仅 GFM profile |
| GFM Task Lists        | 1.0  | 仅 GFM profile |
| GFM Strikethrough     | 1.0  | 仅 GFM profile |
| GFM Extended Autolink | 1.0  | 仅 GFM profile |
| Footnotes             | 1.1  | 关闭            |
| Front Matter          | 1.1  | 关闭            |
| Math                  | 1.1  | 关闭            |
| Definition Lists      | 1.1  | 关闭            |
| Heading IDs           | 1.1  | 关闭            |
| Smart Punctuation     | 1.1  | 关闭            |
| GitHub Alerts         | 后续   | 关闭            |
| WikiLinks             | 后续   | 关闭            |

Front Matter 扩展只负责提取原始内容，不负责解析 YAML、TOML 或 JSON。

Math 扩展只保留 literal，不执行数学渲染。

---

# 30. 取消、预算与 Sink

## 30.1 CancellationToken

解析、转换和渲染必须接受：

```text
CancellationToken
```

取消检查点必须有明确上界，例如：

* 每处理固定数量字符；
* 每完成一个 block；
* 每访问固定数量 AST 节点；
* 每次扩展回调前后；
* 每次 Sink 写入前后。

## 30.2 取消语义

取消后：

* 返回 `Cancelled`；
* 不返回伪装成完整结果的 AST；
* 不继续调用扩展；
* 不继续写输出；
* 不自动 flush 外部 Sink；
* partial result 仅在显式配置时允许。

## 30.3 OperationBudget

必须支持：

```text
maximumScanSteps
maximumDelimiterSteps
maximumExtensionCallbacks
maximumTransformSteps
maximumRenderedNodes
maximumOutputBytes
```

OperationBudget 与静态 ParseLimits 相互独立。

## 30.4 Wall-Clock

核心库不拥有 wall-clock timeout。

宿主可以：

* 通过 CancellationToken 实现 deadline；
* 在外层线程或任务系统控制超时。

这样避免库内部存在多个超时所有者。

## 30.5 Sink

P0 同步 Sink：

```text
TextSink.write(slice) -> Result<Unit, SinkError>
```

要求：

* Sink error 原样向上传播；
* renderer 不吞掉错误；
* 不做无界输出缓存；
* 不在失败后继续写；
* 可以报告部分输出已发生。

P1 增加异步或可暂停 Sink：

```text
Continue
Pause
Failed
```

---

# 31. 资源限制

默认 `ParseLimits.safe()` 建议值：

| 限制             |       默认值 |
| -------------- | --------: |
| 最大输入           |    32 MiB |
| 最大单行           |     8 MiB |
| 最大嵌套深度         |       256 |
| 最大 AST 节点数     | 1,000,000 |
| 最大引用定义数        |   100,000 |
| 最大表格列数         |     1,024 |
| 最大单个 URL       |     1 MiB |
| 最大单个 literal   |    16 MiB |
| 最大输出           |   128 MiB |
| 最大扩展 capture   |     1 MiB |
| 最大扩展 lookahead |    64 KiB |

提供：

```text
ParseLimits.safe()
ParseLimits.trusted()
```

`trusted()` 可以提高限制，但不得关闭：

* 整数溢出检查；
* 容器容量检查；
* AST 无环检查；
* 调用栈安全；
* 输出长度溢出检查。

限制必须在分配超大对象之前检查。

---

# 32. 安全要求

## SEC-001：核心无副作用

核心 parser 和 renderer 不得：

* 访问网络；
* 读取任意文件；
* 启动进程；
* 加载动态库；
* 执行代码块；
* 执行脚本；
* 下载图片。

## SEC-002：复杂度

目标复杂度：

```text
时间：O(input + nodes + output)
空间：O(input + nodes)
```

不得存在已知可由简单重复模式触发的指数级或明显二次复杂度。

## SEC-003：输出放大

必须限制：

* entity 处理；
* 扩展生成内容；
* transform 生成节点；
* heading slug 冲突处理；
* table padding；
* renderer 输出。

## SEC-004：控制字符

不得将危险控制字符直接写入 HTML attribute。

## SEC-005：Bidi 和不可见字符

不得擅自删除合法 Unicode。

P1 lint 可以诊断：

* bidi control；
* zero-width 字符；
* 混淆换行；
* 不可见 separator。

## SEC-006：TrustedHtml

`TrustedHtml`：

* 必须显式构造；
* 不得从普通 String 隐式转换；
* 必须在文档中标记 unsafe；
* 不得绕过输出预算；
* 不得绕过 cancellation。

## SEC-007：安全响应

项目必须提供：

* `SECURITY.md`；
* 私密漏洞报告渠道；
* 安全公告流程；
* 受影响版本说明；
* 病态输入 regression corpus；
* 安全修复兼容策略。

---

# 33. 错误与诊断

## 33.1 错误类型

```text
InvalidEncoding
InputReadFailure
Cancelled
LimitExceeded
BudgetExceeded
ExtensionConflict
ExtensionFailure
SinkFailure
RenderFailure
UnsupportedNode
InvalidArtifact
InternalInvariantViolation
```

不得要求调用者匹配英文错误字符串。

## 33.2 LimitExceeded

必须包含：

```text
limitKind
configuredLimit
observedValue
sourceSpan?
phase
extensionId?
```

## 33.3 Diagnostic

```text
code
severity
message
span
relatedSpans
extensionId?
ruleId?
fixes?
```

稳定 code 示例：

```text
MD1001_INVALID_UTF8_REPLACED
MD2001_LIMIT_NESTING_DEPTH
MD2101_OPERATION_BUDGET_EXCEEDED
MD3001_EXTENSION_CONFLICT
MD4001_UNSAFE_LINK_URI
MD4002_REMOTE_IMAGE_BLOCKED
MD5001_UNUSED_REFERENCE
```

## 33.4 Partial Result

默认 hard error 不返回 AST。

显式开启：

```text
allowPartialResult
```

时，结果必须标记：

```text
isComplete = false
stoppedAt
unfinishedPhase
errors
```

---

# 34. Lint 与 Fix-It

P1 将 parser diagnostic 与 lint 分离。

Lint 分类：

```text
Syntax
Security
Style
Accessibility
DocumentStructure
Extension
```

规则示例：

* 重复引用定义；
* 未使用引用定义；
* heading level 跳跃；
* 空链接；
* 图片缺少 alt；
* unsafe URI；
* raw HTML；
* table 列数异常；
* 混合 bullet marker；
* 不可见 Unicode；
* extension ambiguity。

Fix：

```text
Fix {
    title
    edits: Array<TextEdit>
    applicability
}
```

Applicability：

```text
Always
MaybeIncorrect
ManualReview
```

应用 Fix 前必须验证：

* source digest；
* snapshot version；
* edit range 不重叠。

---

# 35. Explain Mode

P1 提供：

```cangjie
engine.explain(source, position)
```

返回：

```text
candidateRules
selectedRule
rejectedRules
priority
tieBreak
lookahead
containerState
extensionId
profileClause
```

还必须支持输出：

* compiled dialect；
* rule order；
* delimiter dispatch table；
* block opener table；
* conflicts；
* renderer coverage；
* limits；
* fingerprint。

该能力只用于调试，不应默认进入热路径。

---

# 36. 编辑器与增量模型

## 36.1 Document Snapshot

P1 提供：

```text
DocumentSnapshot
SnapshotVersion
SourceEdit
TextRange
ChangedNodeSet
ReparseResult
```

接口草案：

```cangjie
let snapshot1 = engine.parseSnapshot(source)

let snapshot2 = snapshot1.applyEdits([
    SourceEdit(range, replacement)
])
```

## 36.2 1.1 行为

1.1 可以先执行全文重解析，但必须：

* 保留 Snapshot API；
* 返回 changed range；
* 校验 edit；
* 支持 UTF-16 range 转换；
* 不对调用者承诺局部解析。

## 36.3 P2 增量解析

真正增量解析需要：

* block boundary invalidation；
* reference definition dependency；
* extension invalidation；
* stable syntax identity；
* incremental diagnostics；
* incremental source map；
  -跨 snapshot NodeId 策略。

## 36.4 NodeId

1.0：

```text
Document 内稳定
跨编辑不稳定
```

P2 可以增加：

```text
StableNodeId
```

不得在 1.0 暗示 NodeId 跨编辑稳定。

---

# 37. Capability Introspection

必须提供：

```cangjie
engine.capabilities()
```

返回：

```text
supportedProfiles
supportedExtensions
supportedRenderers
supportedSyntaxKinds
dslSchemaVersions
spiVersions
positionEncodings
serializationVersions
incrementalSupport
losslessSupport
```

应用不得通过尝试调用并捕获异常来判断能力。

---

# 38. Parse Artifact 与缓存

P1 提供稳定 parse artifact：

```text
MarkdownParseArtifact {
    schemaVersion = 2
    libraryVersion
    parserPlanVersion
    profileId
    dialectFingerprint
    engineFingerprint
    sourceDigest
    ast
    references
    diagnostics
}
```

schema v2 绑定 arena node/child chunks、紧凑 origin metadata、原始输入身份与
decode policy。0.8 schema v1 不提供尽量恢复；读取时必须返回 CacheMiss。

读取时必须验证：

* schema version；
* source digest；
* profile ID；
* dialect fingerprint；
* extension implementation identity；
* parser plan version；
* AST invariants。

任一不匹配时返回：

```text
CacheMiss
```

不得尽量恢复可能语义错误的缓存。

Debug JSON 与稳定 artifact 必须是不同承诺：

```text
Debug JSON
    可读，非稳定

Parse Artifact
    版本化，严格校验
```

---

# 39. 公共 API 草案

以下为语义草案。

## 39.1 Engine

```cangjie
let engine = MarkdownEngine.builder()
    .profile(MarkdownProfile.commonMark0312())
    .limits(ParseLimits.safe())
    .sourceMap(SourceMapMode.node)
    .build()
```

## 39.2 自定义方言

```cangjie
let dialect = MarkdownDialect.define(
    id: "docs-v1",
    version: "1.0.0"
) {
    base(CommonMark.v0_31_2)
    enable(Gfm.tables)
    enable(Admonition.v1)
}

let engine = MarkdownEngine.builder()
    .dialect(dialect)
    .build()
```

## 39.3 Parse

```cangjie
let result = engine.parse(
    source,
    cancellation: token,
    budget: OperationBudget.safe()
)

let document = result.document
```

## 39.4 Chunked Parse

```cangjie
let session = engine.newSession(
    cancellation: token,
    budget: budget
)

session.feed(chunk1)
session.feed(chunk2)

let result = session.finish()
```

## 39.5 Safe HTML

```cangjie
let renderer = HtmlRenderer(
    options: HtmlOptions.safe()
)

let html = renderer.render(document)
```

## 39.6 Sink

```cangjie
renderer.renderTo(
    document,
    sink,
    cancellation: token,
    budget: budget
)
```

## 39.7 Walk

```cangjie
for (event in document.walk()) {
    match (event) {
        case Enter(node) => ...
        case Exit(node) => ...
    }
}
```

## 39.8 Rewrite

```cangjie
let rewritten = document.rewrite { node =>
    match (node) {
        case Heading(level: 1) => replace(...)
        case _ => keep()
    }
}
```

## 39.9 便利 API

可以提供：

```cangjie
Markdown.parse(source)
Markdown.toSafeHtml(source)
Markdown.toSpecHtml(source)
Markdown.toText(source)
Markdown.format(source)
```

便利 API 仍必须允许指定 profile。

---

# 40. 模块与包结构

建议逻辑模块：

```text
markdown_core
markdown_commonmark
markdown_gfm
markdown_dsl
markdown_transform
markdown_html
markdown_format
markdown_lint
markdown_cli
markdown_testkit
```

Umbrella package：

```text
markdown
```

建议仓库：

```text
markdown/
├── cjpm.toml
├── src/
│   ├── markdown_core/
│   │   ├── source/
│   │   ├── ast/
│   │   ├── syntax/
│   │   ├── position/
│   │   ├── diagnostic/
│   │   └── budget/
│   ├── markdown_commonmark/
│   │   ├── block/
│   │   ├── inline/
│   │   └── reference/
│   ├── markdown_gfm/
│   ├── markdown_dsl/
│   │   ├── dialect/
│   │   ├── syntax/
│   │   └── renderer/
│   ├── markdown_transform/
│   ├── markdown_html/
│   ├── markdown_format/
│   ├── markdown_lint/
│   └── markdown/
├── tools/
│   └── markdown/
├── tests/
│   ├── unit/
│   ├── commonmark/
│   ├── gfm/
│   ├── differential/
│   ├── chunked/
│   ├── fuzz/
│   ├── security/
│   ├── extension-tck/
│   └── regression/
├── benchmarks/
├── docs/
└── examples/
```

要求：

* AST 不依赖 HTML；
* CommonMark 不依赖 GFM；
* CLI 不进入库依赖图；
* TestKit 不进入生产依赖；
* 扩展仅依赖 core 和 SPI；
* unsafe HTML API 放在独立命名空间。

---

# 41. CLI

工具名：

```text
markdown
```

## 41.1 命令

```text
markdown render
markdown parse
markdown format
markdown check
markdown explain
markdown dialect
```

## 41.2 Render

```text
--profile commonmark-0.31.2
--profile gfm-0.29
--profile gfm-modern-v1
--to spec-html
--to safe-html
--to text
--to markdown
```

## 41.3 Parse

支持输出：

* AST tree；
* Debug JSON；
* SourceSpan；
* reference table；
* diagnostics；
* dialect fingerprint。

## 41.4 Format

支持：

* stdin/stdout；
* 原地修改；
* `--check`；
* `--diff`；
* profile；
* newline；
* range。

## 41.5 Check

检查：

* limits；
* unsafe URI；
* remote image；
* raw HTML；
* extension conflict；
* formatter diff；
* lint。

## 41.6 Dialect

```text
markdown dialect describe
markdown dialect fingerprint
markdown dialect validate
```

## 41.7 Exit Code

| Code | 含义                |
| ---: | ----------------- |
|    0 | 成功                |
|    1 | 输入或解析失败           |
|    2 | 参数错误              |
|    3 | format check 存在差异 |
|    4 | 安全策略拒绝            |
|    5 | 扩展或方言错误           |
|    6 | 取消或预算耗尽           |
|    7 | 内部错误              |

---

# 42. 并发与线程安全

1. `MarkdownEngine` 配置必须不可变。
2. 同一 engine 可以并发 parse。
3. 每次 parse 拥有独立 session state。
4. Document 支持并发只读。
5. Renderer 配置不可变。
6. 单个 chunked session 不支持并发调用。
7. 扩展必须声明是否可以共享。
8. 不得使用可变全局 registry。
9. 只读静态表可以共享。
10. AnnotationStore 的线程安全策略必须显式。

---

# 43. 确定性与跨平台

相同输入、版本和配置下，Tier 1 平台必须一致：

* AST kind；
* NodeId；
* SourceSpan byte range；
* reference resolution；
* diagnostics code；
* HTML；
* Markdown format；
* dialect fingerprint；
* artifact digest。

允许差异：

* 显式选择 native newline；
* 底层 I/O 错误文本；
* benchmark 数值；
* wall-clock duration。

快照中不得包含：

* 内存地址；
* 随机数；
* thread ID；
* 未排序 map；
* 本地绝对路径。

---

# 44. 测试策略

## 44.1 官方规范测试

P0：

* CommonMark 0.31.2：100%。
* GFM 0.29-gfm：100%。
* 精确 profile 使用精确 HTML 比较。
* 不允许长期 allowlist 跳过。

## 44.2 差分测试

对比：

```text
markdown
cmark
cmark-gfm
commonmark.js
```

差异分类：

* 项目 bug；
* profile 版本差异；
* serializer 差异；
* 参考实现差异；
* 已记录的规范解释差异。

## 44.3 Chunk Metamorphic

必须验证：

```text
parse(allAtOnce) == parse(randomChunks)
```

覆盖：

* 1 byte chunk；
* random chunk；
* Unicode boundary；
* CRLF boundary；
* syntax delimiter boundary。

## 44.4 Formatter Metamorphic

必须验证：

```text
format(format(x)) == format(x)
parse(format(x)) ≈ parse(x)
```

## 44.5 Safe HTML

必须验证：

* raw HTML 不透传；
  -危险 URI 被拒绝；
* attribute 正确转义；
* extension 普通字符串无法注入；
* output limit 生效；
* cancellation 生效。

## 44.6 Fuzzing

必须 fuzz：

* String parse；
* bytes parse；
* chunked feed；
* dialect compiler；
* Syntax DSL compiler；
* Safe HTML；
* Markdown formatter；
* AST rewriter；
* artifact decoder；
* extension dispatch。

每个 crash 必须保留：

* 最小输入；
* corpus；
  -版本；
* regression；
* 修复说明。

## 44.7 病态输入

至少包括：

* 大量 `*`、`_`、`~`；
* 深层 `>`；
* 深层 list；
* 大量未闭合 `[`；
* 大量 HTML opener；
* 超长 URL；
* 大量 reference；
* 超宽 table；
* 超长单行；
* extension delimiter storm；
* transform 输出放大；
* renderer 输出放大；
* cancellation race。

## 44.8 Extension TCK

所有官方扩展必须通过同一 TCK。

第三方扩展作者可以独立运行 TCK。

## 44.9 API Compatibility

CI 必须检测：

* public symbol 删除；
* 字段类型修改；
* enum variant 风险；
* SPI 版本；
* artifact schema；
* DSL schema；
* profile behavior snapshots。

---

# 45. 性能要求

## 45.1 优先级

```text
正确性
> 安全与复杂度
> API 稳定性
> 性能
> 微优化
```

## 45.2 基准语料

必须包含：

* 官方规范示例；
* README；
* API 文档；
* 大型代码块；
* 大型表格；
* 大量引用；
* CJK；
* emoji；
* 深层列表；
* 病态 delimiter；
* 单行超长输入；
* 自定义扩展。

## 45.3 参考实现

测试和 benchmark 可以使用：

* `cmark`；
* `cmark-gfm`；
* `commonmark.js`。

不得成为生产依赖。

## 45.4 GA 门槛

在固定 reference host 和 release build 上：

1. CommonMark parse-only 几何平均耗时不超过 `cmark` 的 2.5 倍。
2. GFM parse + HTML 不超过 `cmark-gfm` 的 2.5 倍。
3. 普通代表性语料单项不超过参考实现 5 倍。
4. 1 MiB 到 16 MiB 扩展不得出现明显二次增长。
5. 10 MiB 普通文档 parse-only 峰值额外内存不超过输入大小 8 倍。
6. Renderer 不得无界缓存输出。
7. 相对已接受基线回退超过 10% 时 CI 必须失败或显式批准。
8. 开启 SourceMap、CST 等可选能力时必须分别记录开销。

## 45.5 分配目标

应该：

* ByteArray 输入避免完整复制；
* literal 使用 SourceSlice；
* parser 临时对象使用 arena 或等价生命周期；
* 不为每个字符创建 token 对象；
* renderer 直接写 Sink；
* entity table 共享只读；
* 小节点采用紧凑表示。

---

# 46. 可观测性

核心库不得上传遥测。

可选本地统计：

```text
inputBytes
lineCount
nodeCount
maxDepth
referenceCount
extensionCallbackCount
scanSteps
parseDuration
transformDuration
renderDuration
outputBytes
diagnosticCount
profileId
dialectFingerprint
```

计时必须显式开启。

不得默认记录：

* 完整文档；
* link destination；
* image URL；
* code block 内容；
* Front Matter 内容。

---

# 47. 文档要求

1.0 必须提供：

1. README。
2. 五分钟 Quickstart。
3. Profile 选择指南。
4. Dialect DSL 指南。
5. Syntax DSL 指南。
6. Renderer DSL 指南。
7. AST 节点参考。
8. SourceSpan 和 UTF-16 映射说明。
9. Safe HTML 安全指南。
10. URI policy 指南。
11. Extension SPI 指南。
12. Extension TCK 指南。
13. Chunked input 指南。
14. Cancellation 和 Budget 指南。
15. Formatter 行为说明。
16. 性能基准方法。
17. Error code 参考。
18. Capability introspection 说明。
19. 迁移指南。
20. 完整 API 文档。

示例至少覆盖：

```text
Markdown → Safe HTML
Markdown → AST → 提取标题
Dialect DSL → 自定义方言
Syntax DSL → 自定义容器
Renderer DSL → 安全 HTML
Cancellation → 中止超大输入
```

---

# 48. 版本与兼容策略

## 48.1 SemVer

项目使用 SemVer。

## 48.2 用户可观察变更

以下属于兼容性风险：

* AST 结构；
* NodeId 规则；
* SourceSpan；
* profile 行为；
* dialect rule 顺序；
* diagnostics code；
* HTML；
* formatter；
* default security policy；
* SPI；
* artifact schema。

## 48.3 Profile 稳定性

已发布的 versioned profile 不得改变语义。

必要规范修复必须：

* 关联规范编号；
* 加 regression；
* 更新 changelog；
* 评估新 profile revision。

## 48.4 AST 兼容性

0.9 是 GA 前明确的 breaking reset：删除 0.8 object-tree AST、修改 NodeOrigin
表示、升级 SPI/event/artifact schema 都允许，但必须同步 migration、API snapshot、
consumer fixture 和 changelog。0.9 不提供旧 AST runtime adapter。

1.x 中：

* 删除公开节点属于 breaking；
* 修改字段语义属于 breaking；
* 增加可选字段可以是 minor；
* 增加核心 node kind 必须评估 exhaustive match；
* 第三方语法优先使用 Custom Node。

## 48.5 SPI

扩展 SPI 必须单独版本化。

0.9 的 Inline Parser SPI v2 必须声明非空、无重复的 `triggerBytes`；编译后的
dialect 只在当前位置首字节命中时调用 SPI。Syntax DSL 也按 opener 首字节调度。
内部 hot plan 不进入 semantic fingerprint。

不兼容 SPI 必须在 engine build 阶段拒绝。

## 48.6 弃用

公开 API 删除前至少经过一个 minor 版本弃用期。

高危安全接口可以提前移除，但必须发布安全公告和迁移方案。

---

# 49. 发布产物

1.0 发布必须包含：

* 仓颉库包；
* `markdown` CLI；
* API 文档；
* CommonMark conformance report；
* GFM conformance report；
* benchmark report；
* fuzz summary；
* security guide；
* Extension TCK；
* changelog；
* license；
* 第三方测试数据归属；
* 示例工程；
* public API snapshot；
* dialect schema 和 SPI version 文档。

核心发布不得链接非标准原生动态库。

---

# 50. 实施里程碑

## M0：契约冻结

交付：

* profile IDs；
* AST schema；
* SourceSpan；
* raw/semantic value 模型；
* error codes；
* dialect descriptor；
* fingerprint；
* SPI version；
* test harness；
* benchmark harness。

退出条件：

* 核心语义有书面定义；
* 不使用临时公开 AST 开始大规模实现。

## M1：CommonMark Core

交付：

* SourceBuffer；
* block parser；
* inline parser；
* reference；
* AST；
* Spec HTML；
* limits；
* cancellation。

退出条件：

* CommonMark 0.31.2 100%；
* chunk tests 通过；
* 无已知 crash。

## M2：GFM

交付：

* Table；
* Task List；
* Strikethrough；
* Extended Autolink；
* Tag Filter；
* 两个 GFM profile。

退出条件：

* GFM 0.29-gfm 100%；
* modern profile 差异文档完成。

## M3：DSL 与扩展

交付：

* Dialect DSL；
* Dialect Compiler；
* Syntax DSL；
* Renderer DSL；
* SPI；
* capability matrix；
* Extension TCK。

退出条件：

* 冲突检测通过；
* fingerprint 稳定；
* 官方扩展全部通过 TCK。

## M4：安全与 Renderer

交付：

* Safe HTML；
* Link/Image policy；
* structured builder；
* Text renderer；
* Markdown renderer；
* Sink；
* output budget。

退出条件：

* 安全 corpus 通过；
* formatter 幂等；
* 无已知高危问题。

## M5：Transform 与工具

交付：

* Walker；
* Visitor；
* TreeRewriter；
* CLI；
* capability introspection；
* diagnostics。

退出条件：

* AST invariant 全通过；
* CLI 行为稳定；
* API review 完成。

## M6：发布加固

交付：

* fuzz；
* benchmark；
* docs；
* examples；
* conformance reports；
* package metadata。

退出条件：

* 全部 GA 验收标准通过。

## M7：1.1 编辑器能力

交付：

* CST；
* preserving formatter；
* range formatting；
* source map；
* lint/fix；
* explain；
* event；
* snapshot；
* parse artifact。

---

# 51. 1.0 GA 验收标准

## 51.1 标准兼容

* [ ] CommonMark 0.31.2 官方测试 100% 通过。
* [ ] GFM 0.29-gfm 官方测试 100% 通过。
* [ ] `gfm-modern-v1` 行为有完整文档。
* [ ] 未记录规范偏差为 0。

## 51.2 DSL 与扩展

* [ ] Dialect DSL 可定义 versioned dialect。
* [ ] Dialect 可编译为不可变 plan。
* [ ] 相同配置产生相同 fingerprint。
* [ ] Syntax DSL 支持有限 inline 和 block syntax。
* [ ] 无界规则会在编译阶段拒绝。
* [ ] Renderer DSL 使用结构化安全 builder。
* [ ] 扩展 dependency 和 conflict 可验证。
* [ ] SPI 版本不兼容会在 build 阶段失败。
* [ ] 官方扩展通过 Extension TCK。
* [ ] 缺失 renderer 不会静默丢失内容。

## 51.3 输入与解析

* [ ] String、bytes、stream、chunked input 可用。
* [ ] 任意 chunk 分割结果一致。
* [ ] UTF-8 Strict 和 ReplaceInvalid 可用。
* [ ] SourceBuffer 和 SourceSlice 可用。
* [ ] `document.detach()` 可用。
* [ ] Parser 核心非递归。
* [ ] 深层输入不会导致宿主栈溢出。

## 51.4 AST

* [ ] AST 不可变。
* [ ] NodeId 唯一且确定。
* [ ] SourceSpan 使用 UTF-8 半开区间。
* [ ] UTF-16 映射可用。
* [ ] raw、semantic、normalized 值分离。
* [ ] Custom Node 可用。
* [ ] AST invariant validator 可用。
* [ ] Walker、Visitor、TreeRewriter 可用。

## 51.5 Renderer

* [ ] Spec HTML 可用。
* [ ] GFM HTML 可用。
* [ ] Safe HTML 可用。
* [ ] Safe 为便利 API 默认模式。
* [ ] Plain Text 可用。
* [ ] Canonical Markdown 可用。
* [ ] Formatter 幂等。
* [ ] Link 和 Image policy 分离。
* [ ] TrustedHtml 不能隐式构造。
* [ ] Sink error 正确传播。

## 51.6 资源与安全

* [ ] 输入、行、深度、节点、引用、URL 和输出均有限制。
* [ ] OperationBudget 可限制扫描和扩展回调。
* [ ] CancellationToken 覆盖 parse、transform 和 render。
* [ ] 取消后不继续调用扩展或写输出。
* [ ] raw HTML 默认不透传。
* [ ] 危险 URI 默认拒绝。
* [ ] 远程图片策略可配置。
* [ ] 病态 delimiter 无已知非线性问题。
* [ ] 已知高危安全问题为 0。

## 51.7 工程质量

* [ ] 所有 bug 修复有 regression。
* [ ] Fuzz 无未处理 crash。
* [ ] 跨 Tier 1 平台输出一致。
* [ ] API compatibility gate 可用。
* [ ] Benchmark 达到 GA 门槛。
* [ ] 核心无非标准原生动态库依赖。
* [ ] Security guide 已发布。
* [ ] Conformance report 已发布。
* [ ] 示例可在干净环境构建。

---

# 52. 成功指标

| 指标                     |   目标 |
| ---------------------- | ---: |
| CommonMark conformance | 100% |
| GFM conformance        | 100% |
| 已知 crash               |    0 |
| 已知高危安全问题               |    0 |
| Chunk invariance       | 100% |
| Formatter 幂等           | 100% |
| 官方扩展 TCK               | 100% |
| 未记录规范偏差                |    0 |
| 默认 raw HTML 透传         |    0 |
| 核心非标准原生依赖              |    0 |
| 未批准性能回归                | ≤10% |
| Fingerprint 确定性        | 100% |

---

# 53. 主要风险与缓解

## 53.1 GFM 与 CommonMark 基线不同

**风险：** 正式 GFM 规范版本较旧，直接把 GFM 扩展叠加到 CommonMark 0.31.2 可能产生边界差异。

**缓解：**

* `gfm-0.29` 精确实现正式规范；
* `gfm-modern-v1` 明确为项目组合；
* 两者独立测试；
* profile ID 永久固定。

## 53.2 DSL 绑定 parser 内部实现

**风险：** 暴露 delimiter stack 和 container state 后难以重构。

**缓解：**

* DSL 只表达语义规则；
* Parser SPI 受控；
* 不公开内部 scanner 状态；
  -复杂扩展使用稳定上下文接口。

## 53.3 Syntax DSL 造成复杂度攻击

**风险：** 任意规则可能导致回溯或超大 capture。

**缓解：**

* 有界 lookahead；
* 线性规则；
* 无界规则拒绝编译；
* 回调预算；
* fuzz；
* extension TCK。

## 53.4 CST 范围过大

**风险：** 为 lossless 和编辑器能力推迟 1.0。

**缓解：**

* 1.0 冻结表示层边界；
* 1.0 提供 AST、SourceBuffer 和 SourceSpan；
* 完整 CST 在 1.1；
* 不把 trivia 塞入稳定 AST。

## 53.5 扩展信任误解

**风险：** 用户认为第三方代码扩展处于 sandbox。

**缓解：**

* 文档明确代码扩展具有宿主权限；
* 外部数据 DSL 不执行代码；
* 插件隔离作为独立 P2 能力；
* TrustedHtml 显式 unsafe。

## 53.6 Safe HTML 被误认为完整 sanitizer

**风险：** 用户开启 raw HTML 后仍认为输出安全。

**缓解：**

* Safe 默认转义 raw HTML；
* `PassThrough` 明确 unsafe；
* sanitizer adapter 独立；
* GFM Compatible 不命名为 Safe。

## 53.7 Unicode 位置混用

**风险：** byte、UTF-16 和视觉列混用导致编辑错误。

**缓解：**

* UTF-8 byte offset 为唯一规范位置；
* UTF-16 通过 mapper；
* VisualPosition 仅展示；
* 编辑 API 显式标注 PositionEncoding。

## 53.8 Fingerprint 不完整

**风险：** 扩展代码已变化但缓存仍命中。

**缓解：**

* 纳入 implementation version；
* 纳入 SPI；
* 纳入 parser plan version；
* artifact 加 source digest；
* 不匹配直接 cache miss。

---

# 54. 已冻结产品决策

1. 项目名为 `markdown`。
2. 公开根命名空间为 `markdown`。
3. CommonMark 精确基线为 0.31.2。
4. GFM 精确 profile 为 0.29-gfm。
5. 另提供 `gfm-modern-v1`。
6. 默认 parser profile 为 CommonMark。
7. 默认 HTML policy 为 Safe。
8. AST 是 1.0 稳定公共抽象。
9. CST 架构在 1.0 预留，完整公开能力在 1.1。
10. Event API 在 1.1。
11. Dialect DSL 是 P0。
12. 有限 Syntax DSL 是 P0。
13. Renderer DSL 是 P0。
14. Transform DSL 是 P1。
15. 任意 Grammar DSL 是非目标。
16. 外部 JSON/YAML DSL 不进入 1.0。
17. DSL 必须可静态验证。
18. 规则必须有界。
19. 方言必须编译为不可变执行计划。
20. 方言、引擎和 renderer 分别 fingerprint。
21. UTF-8 byte offset 是规范位置。
22. 必须提供 UTF-16 映射。
23. raw、semantic 和 normalized 值必须分离。
24. NodeId 在单 Document 内稳定，跨编辑不稳定。
25. AST 默认不可变。
26. parser、transform、renderer 都支持取消。
27. 核心库不拥有 wall-clock timeout。
28. 所有资源限制必须在超大分配前检查。
29. Link 和 Image 使用不同 URI policy。
30. Safe HTML 默认转义 raw HTML。
31. GFM tagfilter 不视为 sanitizer。
32. TrustedHtml 显式 unsafe。
33. 第三方代码扩展具有宿主进程权限。
34. 扩展必须声明 SPI、能力和 renderer coverage。
35. 扩展必须通过 TCK。
36. 核心无网络、文件和进程副作用。
37. 核心无非标准原生动态库依赖。
38. Formatter 1.0 以规范化和幂等为目标。
39. Preserving Formatter 在 1.1。
40. 真正增量解析在 P2。

---

# 55. 最终产品定义

只有当以下完整链路成立时，`markdown` 才能被称为完整 Markdown 库：

```text
Versioned Standard Profile
→ Typed Dialect DSL
→ Validated Bounded Syntax Rules
→ Compiled Dialect Plan
→ Bounded and Cancellable Parser
→ Immutable AST with Source Mapping
→ Validated Transform Pipeline
→ Explicit Safe Renderer Policy
→ Deterministic Sink Output
→ Conformance, Fuzz and Benchmark Evidence
```

对于编辑器级完整能力，还必须继续扩展为：

```text
Source Snapshot
→ Lossless CST
→ Semantic AST
→ Incremental Transform and Diagnostics
→ Preserving Range Formatter
→ Source-Mapped Preview
```

任何只提供：

```text
String → HTML
```

但缺少：

* 明确标准版本；
* DSL 和扩展契约；
* AST；
* SourceSpan；
* 安全模式；
* 资源预算；
* 取消；
* 确定性；
* 规范测试；

的实现，都不满足本 PRD 对“完整 Markdown 库”的定义。
