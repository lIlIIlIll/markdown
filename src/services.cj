package markdown

import std.collection.*
import std.sync.AtomicBool

/** annotation channel 的稳定名称、版本和 fingerprint 参与标记。 */
public class AnnotationKey<T> {
    /** channel 的稳定唯一 id。 */
    public let id: String
    /** annotation 语义版本。 */
    public let version: String
    /** 该 channel 的值是否参与 dialect fingerprint。 */
    public let includeInFingerprint: Bool

    /**
     * 创建 annotation key。
     * @param id channel 的稳定唯一 id，不能为空。
     * @param version annotation 语义版本。
     * @param includeInFingerprint 值是否参与 dialect fingerprint。
     */
    public init(id: String, version!: String = "1", includeInFingerprint!: Bool = false) {
        if (id.isEmpty()) {
            throw IllegalArgumentException("annotation key id must not be empty")
        }
        this.id = id
        this.version = version
        this.includeInFingerprint = includeInFingerprint
    }
}

/** 以 NodeId 为键的可变 annotation channel。 */
public class AnnotationChannel<T> {
    private let values = HashMap<NodeId, T>()
    private let closed: AtomicBool
    /** 创建本 channel 的 key。 */
    public let key: AnnotationKey<T>

    internal init(key: AnnotationKey<T>, closed: AtomicBool) {
        this.key = key
        this.closed = closed
    }

    /** 写入节点 annotation；store close 后会失败。
     * @param nodeId 目标节点 id。
     * @param value 要写入的 annotation 值。
     * @throws IllegalStateException store 已关闭时。
     */
    public func put(nodeId: NodeId, value: T): Unit {
        ensureOpen();
        values.add(nodeId, value)
    }
    /** 读取节点 annotation；不存在时返回 `None`。
     * @param nodeId 目标节点 id。
     * @return 对应 annotation；不存在时为 `None`。
     * @throws IllegalStateException store 已关闭时。
     */
    public func get(nodeId: NodeId): ?T {
        ensureOpen();
        values.get(nodeId)
    }
    /** 移除并返回节点 annotation。
     * @param nodeId 目标节点 id。
     * @return 被移除的 annotation；不存在时为 `None`。
     * @throws IllegalStateException store 已关闭时。
     */
    public func remove(nodeId: NodeId): ?T {
        ensureOpen();
        values.remove(nodeId)
    }
    /** 当前存储的 annotation 数量。 */
    public prop size: Int64 {
        get() {
            ensureOpen();
            values.size
        }
    }

    private func ensureOpen(): Unit {
        if (closed.load()) {
            throw IllegalStateException("annotation store is closed")
        }
    }
}

/** owner-thread confined 的 annotation channel owner。 */
public class AnnotationStore {
    private let closed = AtomicBool(false)
    /** 创建空的 annotation store。 */
    public init() {}
    // Channels are intentionally owner-thread confined. Share immutable ASTs,
    // not a mutable annotation store, unless the host provides synchronization.
    /** 恒为 `false`：channel 仅限 owner 线程使用。 */
    public prop threadSafe: Bool {
        get() {
            false
        }
    }
    /** 为 key 创建一个 channel view。
     * @param key channel 的 annotation key。
     * @return 对应 key 的 channel view。
     */
    public func channel<T>(key: AnnotationKey<T>): AnnotationChannel<T> {
        AnnotationChannel<T>(key, closed)
    }
    /** 关闭 store；关闭后 channel 读写都会失败。 */
    public func close(): Unit {
        closed.store(true)
    }
    /**
     * 查询 store 是否已经关闭。
     * @return 已关闭时为 `true`。
     */
    public func isClosed(): Bool {
        closed.load()
    }
}

/** transform pass 对 annotation 和 host effect 的声明。 */
public enum TransformPurity {
    /** 不读 annotation，也没有 host effect。 */
    | Pure
    /** 读取 annotation channel。 */
    | ReadsAnnotations
    /** 产生 host 可见的副作用。 */
    | HostEffect
}

/** 可由 `TransformPipeline` 排序和执行的 AST transform pass。 */
public interface TransformPass {
    /** pass 的稳定唯一 id。 */
    prop id: String
    /** pass 的语义版本。 */
    prop version: String
    /** 依赖的 capability 名称列表。 */
    prop requires: Array<String>
    /** 产出的 capability 名称列表。 */
    prop produces: Array<String>
    /** 同就绪 pass 之间的执行优先级，数值越大越先执行。 */
    prop priority: Int64
    /** pass 的纯度声明。 */
    prop purity: TransformPurity
    /** 对输入 Document 执行一次 transform 并返回新 Document。
     * @param document 输入 Document。
     * @return transform 后的 `Document`。
     */
    func apply(document: Document): Document
}

/** 按依赖和 priority 确定性排序并执行 transform pass。 */
public class TransformPipeline {
    private let passes: ImmutableArray<TransformPass>

    internal init(passes: Array<TransformPass>) {
        this.passes = ImmutableArray<TransformPass>(passes)
    }

    /** 编译 pass 顺序；duplicate ID、缺失依赖或 cycle 会失败。
     * @param passes 要编排的 transform pass 列表。
     * @return 编译后的 pipeline。
     * @throws MarkdownException id 为空、重复或依赖成环时。
     */
    public static func compile(passes: Array<TransformPass>): TransformPipeline {
        let ids = HashSet<String>()
        for (pass in passes) {
            if (pass.id.isEmpty() || !ids.add(pass.id)) {
                throw MarkdownException(MarkdownErrorCode.ExtensionConflict, "duplicate or empty transform pass id",
                    phase: "transform_compile")
            }
        }
        let remaining = ArrayList<TransformPass>()
        remaining.add(all: passes)
        let ordered = ArrayList<TransformPass>()
        let produced = HashSet<String>()
        while (!remaining.isEmpty()) {
            var selected: Int64 = -1
            for (index in 0..remaining.size) {
                var ready = true
                for (required in remaining[index].requires) {
                    if (!produced.contains(required)) {
                        ready = false
                        break
                    }
                }
                if (ready && (selected < 0 || remaining[index].priority > remaining[selected].priority)) {
                    selected = index
                }
            }
            if (selected < 0) {
                throw MarkdownException(MarkdownErrorCode.ExtensionConflict,
                    "transform dependency cycle or missing dependency", phase: "transform_compile")
            }
            let pass = remaining.remove(at: selected)
            ordered.add(pass)
            for (capability in pass.produces) {
                produced.add(capability)
            }
        }
        TransformPipeline(ordered.toArray())
    }

    /** 执行已排序 passes，并在每一步验证 AST invariants。
     * @param document 输入 Document。
     * @param budget 每一步 transform 的操作预算。
     * @param cancellation 协作式取消信号。
     * @return 全部 pass 执行后的 `Document`。
     * @throws MarkdownException 取消、预算耗尽或校验失败时。
     */
    public func run(
        document: Document,
        budget!: OperationBudget = OperationBudget.safe(),
        cancellation!: CancellationToken = CancellationToken.none()
    ): Document {
        var current = document
        for (pass in passes.toArray()) {
            cancellation.throwIfCancelled(phase: "transform")
            budget.consumeTransform()
            current = pass.apply(current)
            AstInvariantValidator().validate(current)
        }
        current
    }

    /**
     * 返回编译后的 pass ID 顺序。
     * @return 编译后的 pass id 顺序。
     */
    public func orderedPassIds(): Array<String> {
        let out = ArrayList<String>()
        for (pass in passes.toArray()) {
            out.add(pass.id)
        }
        out.toArray()
    }
}
