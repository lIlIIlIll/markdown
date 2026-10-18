# Code Groups 1.0

Code Groups 是显式开启的本库扩展，不是 CommonMark/GFM 的标准语法，也不属于
`p1Dialect()` 的六项默认组合。它把多语言 fenced code、标题和行高亮组合成一个结构，
不执行代码。默认输出完整可读的静态 HTML；tabs 和复制按钮需要另行开启与加载脚本。

~~~~markdown
:::code-group
```js title="main.js" {2}
const answer = 42;
console.log(answer);
```

```text title="空内容"
```
:::
~~~~

## 解析与复制文本

```cangjie
let dialect = OfficialExtensions.codeGroups(MarkdownDialect.define("examples", "1")).build()
let engine = MarkdownEngine.builder().dialect(dialect).build()
let result = engine.parse(source)
let html = engine.htmlRenderer().render(result.document)
```

开启后，`CodeGroupPayload.role` 区分 Group 与 Item。Group 的 children 是 Item，
每个 Item 包含一个普通 `CodeBlock`。Item 保存 `title`、`highlightedLines` 和 `copyText`；
语言、原始 info string 和 fence 范围仍读取 child 的 `CodeBlockNodeView`。

`copyText` 是单个条目的代码正文，不是整个组的文本。它保留 CRLF、CR、LF、BOM 和
Unicode；先按输入 UTF-8 策略解码，再移除 Markdown 容器及 fence 的缩进。代码显示使用
普通 CodeBlock 的 LF 语义，复制内容不会通过 DOM `textContent` 重建而丢失原始换行。
无效 UTF-8 的替换策略不会承诺把原始无效字节放入文本剪贴板；原始输入仍由 source 保存。

## 固定语法和失败行为

- opener 是独占行的 `:::code-group`，允许零到三列缩进；closer 是去掉行首尾 ASCII
  空白后等于 `:::` 的行。quote/list、脚注和定义列表容器沿用普通 parser 边界。
- body 只允许空行与至少一个闭合 fenced-code block。代码里的 `:::` 或较短 fence
  属于代码，不结束组。没有通用嵌套组或 Markdown 正文模式。
- info string 是可选语言、可选 `title="…"`、可选 `{1,3-5}`，顺序固定。语言只允许
  ASCII 字母、数字、`_`、`-`、`+`。提供标题或行范围时必须先写语言，例如 `text`。
- 标题支持 Unicode，双引号和反斜杠用 `\"`、`\\` 转义，不解释实体或控制命令。
  标题未指定或为空时，使用语言；无语言时使用 `text`。
- 行范围从一计数、包含两端，必须递增、不重叠且不超过实际代码行数。空代码没有可高亮行。
  不展开巨大数字范围，也不接受溢出、零、重复、倒序、额外参数或未知属性。
- 非法 body/header 产生 `MD5001_INVALID_CODE_GROUP` 并保留基础 Markdown 输出。未闭合组或
  fence 保持可见原文，按诊断选项产生 `MD3002_UNCLOSED_EXTENSION`，不补结束标记。
- 未启用或显式关闭扩展时完全遵循基础 profile；Front Matter 不能替宿主开启它。

HTML 使用 `div.code-group`、每项 figure/figcaption 和普通 pre/code。需要强调的行使用
`mark.code-line`，无需脚本也可见。Text 包含标题和代码。canonical Markdown 从 typed
title/行范围生成规范化 header，必要时选择不会与正文或标题冲突的 fence；lossless CST 和 CodeBlock.infoRaw 保留原始输入。修改语义 metadata 不会被原始
info string 覆盖。没有语言时只允许默认 text 标题与无行范围；自定义 metadata 需提供语言。
SourceMap 关联到条目或代码块的完整范围，不伪造生成标签与代码字符的一一对应。

batch、append 最终绑定和 source snapshot 使用同一模型。公开 source/raw events 与
RequireFused 明确拒绝；PreferFused 退到完整 AST。通用 RendererRule 不能覆盖结构化组。
块、header capture、literal、节点、累计扫描和输出预算及取消仍生效。复制文本额外受
literal bytes 限制；它是可选扩展的实际保留成本，不宣称零额外内存。

## 可选 tabs 和复制按钮

```cangjie
let renderer = engine.htmlRenderer(codeGroups: CodeGroupHtmlOptions(
    interactive: true,
    groupLabel: "代码示例",
    copyLabel: "复制代码",
    copiedLabel: "已复制",
    copyFailedLabel: "复制失败",
    copyUnavailableLabel: "不可复制"
))
let html = renderer.render(result.document)
```

此设置只输出增强数据，不加载或执行脚本。宿主从仓库复制
[code-groups.js](../assets/code-groups.js) 和 [code-groups.css](../assets/code-groups.css)
到自己的静态资产目录，并显式初始化：

```html
<link rel="stylesheet" href="/assets/code-groups.css">
<script type="module">
  import { enhanceCodeGroups } from "/assets/code-groups.js";
  enhanceCodeGroups(document);
</script>
```

没有 JS 时所有代码保持可见。增强后使用 tablist/tab/tabpanel，支持左右键、Home/End、
独立 panel ID 和选中状态；重复初始化不会重复添加控件。新插入的 HTML 可再次显式初始化。
脚本只处理声明版本为 1 的组，不使用 `innerHTML`、动态执行或远程依赖。

复制数据用受限 UTF-8 hex 表示，保留 BOM 和原始换行。`maximumCopyBytes` 默认为 1 MiB，
最大为 4 MiB；超限不输出复制数据，完整代码继续显示，按钮有本地化不可用说明。
复制仅由按钮点击调用 Clipboard API，使用浏览器所要求的安全上下文和权限；失败通过
live status 表示并恢复按钮，不使用隐式降级命令。图表、公式或高亮后端不会替代复制文本。

## 验证

[cookbook](../examples/cookbook/src/main.cj) 的 `code-groups` 段生成实际的中文/BOM/CRLF、
多语言及空代码 HTML。可选浏览器 gate 只接收这段生成的 HTML，不读取 Markdown 源文件：

```sh
node tests/browser/code_groups.mjs --fixture <generated.html> \
  --runtime-root <installed-puppeteer-runtime> --chrome <chrome-executable> \
  --output <browser-results>
```

该 gate 不安装依赖；需要宿主预先提供 Puppeteer 和 Chrome。它启动独立 headless browser，
当前 Linux 测试参数包含 `--no-sandbox`，不代表 OS 安全沙箱。测试限于受信生成 fixture，
页面请求只允许 fixture 与本仓库两份静态资产。结果记录输入 hash、浏览器版本、真实
剪贴板、键盘、AX tree、无脚本回退和窄屏检查；其他浏览器和操作系统需单独验证。
