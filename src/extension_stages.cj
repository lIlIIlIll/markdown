package markdown

/** 完整 AST 构建后的确定性转换；在语义绑定之前执行。
 * 实现必须遵守预算和协作式取消；共享 engine 的 callback 还必须保证并发调用安全。
 */
public interface ExtensionAstTransform {
    /** 所属扩展的稳定 id。 */
    prop extensionId: String
    /** 扩展内的转换 id。 */
    prop transformId: String
    /** 影响转换结果的实现版本。 */
    prop version: String
    /** 阶段内的执行优先级；较大值先执行。 */
    prop priority: Int64
    /** 相同输入和配置是否产生相同结果；当前仅接受 true。 */
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
 */
public interface ExtensionDocumentAnalysis {
    /** 所属扩展的稳定 id。 */
    prop extensionId: String
    /** 扩展内的分析 id。 */
    prop analysisId: String
    /** 影响分析结果的实现版本。 */
    prop version: String
    /** 阶段内的执行优先级；较大值先执行。 */
    prop priority: Int64
    /** 相同输入和配置是否产生相同结果；当前仅接受 true。 */
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
