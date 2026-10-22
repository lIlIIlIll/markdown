package markdown.extensions

import markdown.core.{CancellationToken, Diagnostic, Document, OperationBudget, ParseLimits, SourceBuffer}

/** 完整 AST 构建后的确定性转换；在语义绑定之前执行。
 * 实现必须遵守预算和协作式取消；共享 engine 的 callback 还必须保证并发调用安全。
 *
 * manifest 必须声明 transform 能力。阶段内按 priority 降序、extensionId、transformId
 * 升序执行。每次 callback 消耗扩展回调与 transform 预算，返回后再次检查取消，
 * 验证实际 source 归属、profile 与 dialect 身份，并按同一 limits、budget、cancellation
 * 验证完整 AST。构造新节点时也须传入这些约束，不能依赖返回后的验证限制临时分配。
 *
 * Cancelled、BudgetExceeded、LimitExceeded 和 ExtensionFailure 保留原错误类别；其他
 * callback 错误包装为 ExtensionFailureException，保留扩展版本、transformId 及
 * ast_transform 阶段。失败不产生成功的空文档。append 在 finish 执行此阶段；source
 * events 与独立 raw-block 会话预先拒绝，RequireFused 失败，PreferFused 回退完整 AST。
 */
public interface ExtensionAstTransform {
    /**
     * 所属扩展的稳定 id。
     * @return 所属扩展的稳定 id。
     */
    prop extensionId: String
    /**
     * 扩展内的转换 id。
     * @return 扩展内的转换 id。
     */
    prop transformId: String
    /**
     * 影响转换结果的实现版本。
     * @return 影响转换结果的实现版本。
     */
    prop version: String
    /**
     * 阶段内的执行优先级；较大值先执行。
     * @return 阶段内的执行优先级；较大值先执行。
     */
    prop priority: Int64
    /**
     * 相同输入和配置是否产生相同结果；当前仅接受 true。
     * @return 相同输入和配置是否产生相同结果；当前仅接受 true。
     */
    prop deterministic: Bool
    /** 转换完整但尚未绑定的 AST；返回值必须保留实际 source、profile 和 dialect 归属。
     * @param document 当前完整 AST。
     * @param source 与 document 关联的作者输入。
     * @param limits 引擎本次操作实际使用的结构上限。
     * @param budget 整次操作的累计预算。
     * @param cancellation 协作式取消信号。
     * @return 经验证后交给绑定器的 Document。
     */
    func transform(document: Document, source: SourceBuffer, limits: ParseLimits, budget: OperationBudget,
        cancellation: CancellationToken): Document
}

/** 绑定后对最终语义的只读分析。输出诊断，不替换或重写 Document。
 * callback 在宿主进程中运行；必须自行遵守预算、取消和共享调用的并发约定。
 *
 * manifest 必须声明 analysis 能力。所有转换和绑定完成后，按 priority 降序、
 * extensionId、analysisId 升序执行。每次 callback 消耗扩展回调预算，返回后再次检查取消。
 * 主范围、relatedSpans 与 fixes 范围必须在实际输入内并处于 UTF-8 解码边界；诊断代码、
 * 消息、ruleId 及 fix 文本受 literal 上限与累计扫描预算限制。
 *
 * 省略的 extensionId 和 ruleId 分别补为当前扩展与 analysisId，不能冒用其他扩展身份。
 * callback 的临时内存仍由宿主约束，此接口不提供进程隔离。Cancelled、BudgetExceeded、
 * LimitExceeded 和 ExtensionFailure 保留错误类别；其他错误包装为含 analysisId 与
 * document_analysis 阶段的 ExtensionFailureException。执行模式约束与绑定前转换一致。
 */
public interface ExtensionDocumentAnalysis {
    /**
     * 所属扩展的稳定 id。
     * @return 所属扩展的稳定 id。
     */
    prop extensionId: String
    /**
     * 扩展内的分析 id。
     * @return 扩展内的分析 id。
     */
    prop analysisId: String
    /**
     * 影响分析结果的实现版本。
     * @return 影响分析结果的实现版本。
     */
    prop version: String
    /**
     * 阶段内的执行优先级；较大值先执行。
     * @return 阶段内的执行优先级；较大值先执行。
     */
    prop priority: Int64
    /**
     * 相同输入和配置是否产生相同结果；当前仅接受 true。
     * @return 相同输入和配置是否产生相同结果；当前仅接受 true。
     */
    prop deterministic: Bool
    /** 读取已完成绑定的 Document，产生可恢复诊断。
     * @param document 包含最终引用、脚注和标题决策的完整文档。
     * @param source 与 document 关联的作者输入。
     * @param limits 引擎本次操作实际使用的结构上限。
     * @param budget 整次操作的累计预算。
     * @param cancellation 协作式取消信号。
     * @return 来源范围有效的诊断；宿主 callback 的临时分配不由此数组边界限制。
     */
    func analyze(document: Document, source: SourceBuffer, limits: ParseLimits, budget: OperationBudget,
        cancellation: CancellationToken): Array<Diagnostic>
}
