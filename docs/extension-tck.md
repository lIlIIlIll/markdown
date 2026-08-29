# Extension TCK

第三方扩展可以只依赖公开 `markdown.testkit` API 运行共享契约测试。

```cangjie
import markdown.core.*
import markdown.testkit.*

let report = MarkdownExtensionTestKit.verify(engine, sample)
```

`verify` 检查：

- parse 和 renderer 可用；
- 所有 node SourceSpan 有效且被父范围包含；
- 相同输入重复执行结果确定；
- chunk partition 不改变最终语义；
- AST identity、category 和 child 关系满足不变量。

共享 TCK 不知道业务语法的完整输入域。扩展包还应覆盖合法、未知和未闭合 syntax，参数
错误，嵌套和 conflict，资源限制，cancellation，全部 renderer，SourceMap，UTF-8 和固定
seed fuzz。

engine 应在解析前拒绝 duplicate ID、missing dependency、version mismatch、declared
conflict、unsupported SPI、unbounded delimiter/capture、opener conflict、非法 HTML
tag/class/attribute 和缺失 renderer coverage。

TCK 验证协议行为，不是宿主代码沙箱证明。SPI 和 processor callback 拥有宿主进程权限。
需要隔离时，使用宿主实现的 `PluginIsolationTransport`，并测试 worker failure、协议版本、
oversized output、cancellation 和权限策略。

仓库内扩展测试入口和更多验证命令见 [贡献指南](../CONTRIBUTING.md)。

