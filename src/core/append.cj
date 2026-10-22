package markdown.core

protected class NodeConstructionBudget {
    private let maximum: Int64
    protected var used: Int64 = 0
    protected init(maximum: Int64) {
        this.maximum = maximum
    }
    protected func consume(): Unit {
        if (used >= maximum) {
            throw LimitExceededException("node_construction_steps", maximum, used + 1, "append")
        }
        used++
    }
}
