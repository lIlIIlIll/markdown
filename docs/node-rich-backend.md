# 安装并使用可选 Node 富内容后端

`markdown.node.NodeRichContentBackend` 为[共享准备层](rich-content.md)提供真实 KaTeX、
Mermaid 和 Shiki 产物。基础包不依赖已安装的 Node、Python 或浏览器；只有宿主显式调用
准备接口时，适配器才执行已安装的运行时。

当前安装器和进程监督器支持 Linux x86_64，要求 Python 3.12+、官方 STS 1.2.0 和
Chrome 所需的系统动态库。其他平台、浏览器和整个进程树的 RSS 尚未认证。

## 固定输入与许可

| 输入 | 固定版本 | 许可事实源 |
| --- | --- | --- |
| KaTeX | `0.19.0` | npm 包的 MIT `LICENSE` |
| Shiki | `4.5.0` | npm 包的 MIT `LICENSE` |
| Mermaid CLI | `12.0.0` | npm 包的 MIT `LICENSE`；Mermaid core 等传递版本由 lock 固定 |
| parse5 | `8.0.0` | npm 包的 MIT `LICENSE` |
| Node | `24.22.0` | 发行包的 `node/LICENSE`，含子组件条款 |
| Chrome for Testing | `155.0.8059.84` | 原发行包的 ABOUT、组件 notices 和适用发行条款 |
| Noto Sans CJK SC | `Sans2.004` | 原仓库的 SIL OFL 1.1，保留字体与 LICENSE |

完整 npm 闭包位于 [`package-lock.json`](../backends/node/package-lock.json)。安装器
只接受官方 npm registry，关闭依赖安装脚本、audit 和隐式 Puppeteer 下载。它保留原始
Node/Chrome 包、字体许可证、各 npm 包的许可证文件，并生成 `THIRD_PARTY_NOTICES.md`。
安装包只在宿主目录生成，不把这些二进制放入基础库。

归档 URL 与 SHA-256 固定在[安装脚本](../scripts/prepare_rich_runtime.py)的 `PINS`。
Node、Chrome、字体和字体 LICENSE 都先校验后使用。运行时的 `manifest.json` 使用相对
路径记录完整文件哈希，`identity` 是该清单的 SHA-256；每次实际启动都核对闭包。

## 显式准备运行时

使用有足够空间的磁盘目录；当前完整运行时约需 1.1 GiB。首次准备需要明确允许联网：

```sh
rich_inputs="$HOME/.cache/markdown-rich-inputs"
rich_runtime="$HOME/.cache/markdown-rich-runtime"
rich_work="$HOME/.cache/markdown-rich-work"
mkdir -p "$rich_work"
chmod 700 "$rich_work"
python3 scripts/prepare_rich_runtime.py \
  --inputs "$rich_inputs" --output "$rich_runtime" --online
```

`--output` 必须是新目录或空目录。安装失败保留已生成内容，便于诊断；脚本不覆盖其他
运行时，也不修改用户 npm 配置。`--online` 仅控制这次安装，不会让后续 Markdown
解析或准备获得下载权限。

保留 `--inputs` 下的四个归档/字体输入和 `npm-cache`，即可在另一空目录离线重建：

```sh
python3 scripts/prepare_rich_runtime.py \
  --inputs "$rich_inputs" --output "$HOME/.cache/markdown-rich-runtime-offline"
```

默认没有联网路径：缺输入或 npm 缓存即失败。部署时也可直接移动完整运行时目录；
清单没有构建机器绝对路径，identity 不因安装目录改变。

## 从完整解析结果准备展示

在消费者中导入 `markdown.node.NodeRichContentBackend` 和 `markdown.render` 的准备类型。
`runtimeDirectory`、`workDirectory` 来自可信宿主配置，必须是绝对路径：

```cangjie
let backend = NodeRichContentBackend(runtimeDirectory, workDirectory)
let prepared = RichContentPreparer.prepare(
    result,
    options: RichContentOptions(math: true, diagrams: true, highlight: true),
    backend: Some(backend),
    cache: Some(cache)
)
let html = engine.htmlRenderer(prepared: Some(prepared)).render(result.document)
```

`result` 已启用所需语法，例如 Math 2.0；`cache` 是宿主顺序使用的 `RichContentCache`。
图表显示还需显式允许 PNG data image，配置见[Rendering API](api/rendering.md)。否则
准备可以成功，HTML 仍显示完整 Mermaid 代码。

后端主题只支持 `shikiTheme: "github-light" / "github-dark"` 和
`diagramTheme: "default" / "dark" / "neutral" / "forest"`。它们只在实际影响对应产物时
加入缓存 identity。Markdown、Front Matter、fence title 和 Mermaid directive 都不能
选择命令、路径、主题或宿主安全配置。

默认保留 Chromium 自身的 sandbox 配置。宿主若显式传入
`allowUnsandboxedChromium: true`，才会加入 `--no-sandbox`。无论此参数如何，普通外部
进程与本适配器的请求 guard 都不表示操作系统沙箱；宿主决定进程隔离环境。

## 实际能力和失败状态

- KaTeX 使用 `trust: false`、严格错误、100 次 macro expansion 和固定大小限制，输出
  MathML 树，去掉重复 TeX annotation。核心再次校验元素、属性和值域。
- Shiki 仅加载内置语言及固定主题。UTF-16 token offset 单次转换为 UTF-8 byte range；
  保留 BOM、CRLF 和未着色间隙，不拼接规范化后的 token 文本作为复制内容。
- 首版 Mermaid 支持 `flowchart` / `graph` 的 TB/TD/BT/RL/LR；其他图种返回 Unsupported。
  YAML/config directive、click 指令不支持。每项最多 64 KiB 文本/512 条边，返回有界 PNG。
  固定字体通过受控资源响应加载，不读取作者指定的字体或文件。

浏览器只读取固定入口、已校验 npm 模块资产及固定字体；外部 origin、任意 file URL、
越界路径和图片请求在上游文件读取器之前拒绝。第三方 SVG 只在固定引擎的浏览器内部
用于光栅化，调用方只收到 critical PNG chunks，不收到 TrustedHtml 或原始 SVG。

缺运行时/Python 返回 Missing；Linux 能力或版本不支持返回 Unsupported；整体时间
耗尽返回 TimedOut；协议、执行和清理错误返回 Failed；输出/容量超限返回 Limited。
核心统一处理取消、预算、严格模式及完整原文回退。

## 资源与生命周期

每次准备只启动一次批量作业。Linux supervisor 使用 subreaper 回收分离子孙进程，
同时代理三路管道，限制各缓冲区和总输出。输入写入阻塞、Node 崩溃、子进程持有管道、
取消和父进程退出不会让 Cangjie 等待原始子进程管道。整体时间包含运行时清单核验；
清理另有 5 秒界限，异常清理不能返回 Ready。

临时数据位于宿主工作目录的私有 child。监督器持有目录描述符，为 Chrome 的短 Unix
socket 路径提供 `/proc` 引用，数据仍写入该磁盘目录。所有子进程回收后清理作业目录。
Node 的 V8 old-space 上限为 384 MiB，不能把它当作 Node/Chrome 进程树的 RSS 上限。
协议输入另限 32 MiB，产物最多每项 8 MiB/累计 32 MiB；更大宿主 limits 不取消这些界限。

## 执行真实门禁

激活官方 STS 1.2.0 后先执行 `cjpm build`，然后运行：

```sh
python3 scripts/check_node_rich_backend.py \
  --runtime "$rich_runtime" --work-directory "$rich_work" \
  --browser --supervisor-tests
```

需要上述显式无 sandbox 配置的测试宿主可加入 `--allow-unsandboxed-chromium`；门禁不
自动退回该模式。门禁不下载内容，保留 consumer、库、runtime identity 和 HTML 哈希。
它覆盖真实 parse/单字节 append → prepare → 校验/cache → HTML/source map/暂停恢复、
超时与取消、原生 MathML、PNG 像素、颜色 token、真实 clipboard 和请求拒绝。
进程部分包括 7 类受控生命周期夹具及实际 Chrome 的取消/Node 崩溃；夹具不冒充真实引擎。
这些本地结果不替代冻结性能、其他系统、托管 CI 或发布证据。
