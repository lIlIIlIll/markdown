package markdown.core

/** 一次追加会话共享的节点构造计数器；回滚不会归还已用构造步数。 */
protected class NodeConstructionBudget {
    private let maximum: Int64
    /** 已消耗的节点构造步数，包含随后被回滚的节点。 */
    protected var used: Int64 = 0
    /** 创建从零计数的节点构造预算。
     * @param maximum 允许构造的累计节点数；consume 在达到该值时失败。
     */
    protected init(maximum: Int64) {
        this.maximum = maximum
    }
    /** 记入一次节点构造；达到上限时抛出 LimitExceededException。 */
    protected func consume(): Unit {
        if (used >= maximum) {
            throw LimitExceededException("node_construction_steps", maximum, used + 1, "append")
        }
        used++
    }
}
