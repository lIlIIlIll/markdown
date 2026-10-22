package markdown.engine

import markdown.core.{ImmutableArray, NodeId, ParseResult}
import std.collection.*

/** 本地追加更新的参考消费端。每批原子应用；丢批、重复、过期或跨会话时拒绝且不改变状态。 */
public class AppendReplica {
    private var session: Int64 = 0
    private var currentVersion: Int64 = 0
    private var terminal = false
    private var blocksValue = ArrayList<AppendBlockView>()
    private var identities = HashSet<NodeId>()
    private var resultValue: ?ParseResult = None
    private var stateValue = AppendState.AwaitingInput

    /** 创建等待第一个批次的空消费端。重新开始输入时创建新实例。 */
    public init() {}

    /**
     * 当前版本，尚未应用批次时为 0。
     * @return 已成功应用的最新版本；首批之前为 0。
     */
    public prop version: Int64 {
        get() {
            currentVersion
        }
    }
    /**
     * 已应用会话身份，首批前为 None。
     * @return 已绑定的会话身份；首批之前为 None。
     */
    public prop sessionId: ?Int64 {
        get() {
            if (session == 0) {
                None
            } else {
                Some(session)
            }
        }
    }
    /**
     * 当前待定或终结状态。
     * @return 最近成功应用批次的状态；初始为 AwaitingInput。
     */
    public prop state: AppendState {
        get() {
            stateValue
        }
    }
    /**
     * 只有完整 Complete 批次成功应用后才提供结果。
     * @return Complete 批次成功应用后的完整结果；此前及失败后为 None。
     */
    public prop result: ?ParseResult {
        get() {
            resultValue
        }
    }
    /**
     * 返回当前顶层块的不可变副本；不会暴露可变消费端存储。
     * @return 当前顶层块的不可变副本。
     */
    public func blocks(): ImmutableArray<AppendBlockView> {
        ImmutableArray<AppendBlockView>(blocksValue.toArray())
    }

    /**
     * 验证并原子应用一批。错误抛出 IllegalArgumentException；状态保持不变。
     * @param batch 来自同一会话、紧接当前版本的完整原子更新。
     */
    public func apply(batch: AppendUpdateBatch): Unit {
        if (batch.protocolVersion != 1 || terminal || (session != 0 && session != batch.sessionId) ||
            batch.fromVersion != currentVersion || batch.toVersion != currentVersion + 1 || batch.sequence !=
            currentVersion + 1) {
            throw IllegalArgumentException("append update is terminal, cross-session, missing, repeated or stale")
        }
        var completed: ?ParseResult = None
        var isTerminal = false
        var failed = false
        match (batch.state) {
            case AppendState.AwaitingInput => ()
            case AppendState.Complete => isTerminal = true
            case AppendState.Failed(_) =>
                isTerminal = true
                failed = true
        }
        let appended = ArrayList<AppendBlockView>()
        let addedIds = HashSet<NodeId>()
        let replacements = HashMap<NodeId, AppendBlockView>()
        let removed = HashSet<NodeId>()
        var hasRevisions = false
        for (index in 0..batch.changes.size) {
            match (batch.changes[index]) {
                case AppendChange.Append(block) =>
                    if (!addedIds.add(block.node.nodeId)) {
                        invalidUpdate()
                    }
                    appended.add(block)
                case AppendChange.Replace(target, block) =>
                    hasRevisions = true
                    if (!identities.contains(target) || !removed.add(target) || !addedIds.add(block.node.nodeId)) {
                        invalidUpdate()
                    }
                    replacements.add(target, block)
                case AppendChange.Remove(target) =>
                    hasRevisions = true
                    if (!identities.contains(target) || !removed.add(target)) {
                        invalidUpdate()
                    }
                case AppendChange.Bind(value) =>
                    if (!isTerminal || failed || completed.isSome() || index != batch.changes.size - 1) {
                        invalidUpdate()
                    }
                    completed = Some(value)
            }
        }
        if ((isTerminal && !failed) != completed.isSome() || (failed && !batch.changes.isEmpty())) {
            invalidUpdate()
        }
        // An append-only feed validates just its new identities. It does not
        // copy or scan the entire previously delivered prefix on every feed.
        if (!hasRevisions && completed.isNone()) {
            for (block in appended) {
                if (identities.contains(block.node.nodeId)) {
                    invalidUpdate()
                }
            }
            blocksValue.add(all: appended)
            for (id in addedIds) {
                identities.add(id)
            }
        } else {
            let candidate = ArrayList<AppendBlockView>()
            let nextIdentities = HashSet<NodeId>()
            for (block in blocksValue) {
                let id = block.node.nodeId
                if (let Some(replacement) <- replacements.get(id)) {
                    candidate.add(replacement)
                } else if (!removed.contains(id)) {
                    candidate.add(block)
                }
            }
            candidate.add(all: appended)
            for (block in candidate) {
                if (!nextIdentities.add(block.node.nodeId)) {
                    invalidUpdate()
                }
            }
            if (let Some(value) <- completed) {
                let roots = value.document.root().children()
                if (roots.size != candidate.size) {
                    invalidUpdate()
                }
                for (index in 0..roots.size) {
                    let block = candidate[index]
                    if (!block.finalSemantics || block.sourceOffset != 0 || !refEq(block.source, value.source) ||
                        roots[index].nodeId != block.node.nodeId || roots[index].revision != block.node.revision) {
                        invalidUpdate()
                    }
                }
            }
            blocksValue = candidate
            identities = nextIdentities
        }
        session = batch.sessionId
        currentVersion = batch.toVersion
        terminal = isTerminal
        stateValue = batch.state
        resultValue = completed
    }

    private func invalidUpdate(): Nothing {
        throw IllegalArgumentException("append update targets or terminal binding are invalid")
    }
}
