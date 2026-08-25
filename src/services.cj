package markdown

import std.collection.*
import std.sync.AtomicBool

public enum EventMode {
    | Resolved
    | RawBlock
}

public enum MarkdownEvent {
    | DocumentStart(Document)
    | BlockStart(MarkdownNode)
    | InlineStart(MarkdownNode)
    | TextValue(Text)
    | InlineEnd(MarkdownNode)
    | BlockEnd(MarkdownNode)
    | DocumentEnd(Document)
}

public class MarkdownEventIterator <: Iterator<MarkdownEvent> {
    private let events: Array<MarkdownEvent>
    private var index: Int64 = 0

    internal init(document: Document, mode: EventMode) {
        let out = ArrayList<MarkdownEvent>()
        out.add(MarkdownEvent.DocumentStart(document))
        for (event in document.walk()) {
            match (event) {
                case WalkEvent.Enter(node) => match (node) {
                    case _: Document => ()
                    case text: Text =>
                        if (let EventMode.Resolved <- mode) {
                            out.add(MarkdownEvent.TextValue(text))
                        }
                    case _ => match (node.category) {
                        case NodeCategory.Block => out.add(MarkdownEvent.BlockStart(node))
                        case NodeCategory.Inline =>
                            if (let EventMode.Resolved <- mode) {
                                out.add(MarkdownEvent.InlineStart(node))
                            }
                    }
                }
                case WalkEvent.Exit(node) => match (node) {
                    case _: Document => ()
                    case _: Text => ()
                    case _ => match (node.category) {
                        case NodeCategory.Block => out.add(MarkdownEvent.BlockEnd(node))
                        case NodeCategory.Inline =>
                            if (let EventMode.Resolved <- mode) {
                                out.add(MarkdownEvent.InlineEnd(node))
                            }
                    }
                }
            }
        }
        out.add(MarkdownEvent.DocumentEnd(document))
        events = out.toArray()
    }

    public func next(): ?MarkdownEvent {
        if (index >= events.size) {
            return None
        }
        let value = events[index]
        index++
        Some(value)
    }
}

extend Document {
    public func events(mode!: EventMode = EventMode.Resolved): MarkdownEventIterator {
        MarkdownEventIterator(this, mode)
    }
}

public class AnnotationKey<T> {
    public let id: String
    public let version: String
    public let includeInFingerprint: Bool

    public init(id: String, version!: String = "1", includeInFingerprint!: Bool = false) {
        if (id.isEmpty()) {
            throw IllegalArgumentException("annotation key id must not be empty")
        }
        this.id = id
        this.version = version
        this.includeInFingerprint = includeInFingerprint
    }
}

public class AnnotationChannel<T> {
    private let values = HashMap<Int64, T>()
    private let closed: AtomicBool
    public let key: AnnotationKey<T>

    internal init(key: AnnotationKey<T>, closed: AtomicBool) {
        this.key = key
        this.closed = closed
    }

    public func put(nodeId: NodeId, value: T): Unit {
        ensureOpen();
        values.add(nodeId.value, value)
    }
    public func get(nodeId: NodeId): ?T {
        ensureOpen();
        values.get(nodeId.value)
    }
    public func remove(nodeId: NodeId): ?T {
        ensureOpen();
        values.remove(nodeId.value)
    }
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

public class AnnotationStore {
    private let closed = AtomicBool(false)
    public init() {}
    // Channels are intentionally owner-thread confined. Share immutable ASTs,
    // not a mutable annotation store, unless the host provides synchronization.
    public prop threadSafe: Bool {
        get() {
            false
        }
    }
    public func channel<T>(key: AnnotationKey<T>): AnnotationChannel<T> {
        AnnotationChannel<T>(key, closed)
    }
    public func close(): Unit {
        closed.store(true)
    }
    public func isClosed(): Bool {
        closed.load()
    }
}

public enum TransformPurity {
    | Pure
    | ReadsAnnotations
    | HostEffect
}

public interface TransformPass {
    prop id: String
    prop version: String
    prop requires: Array<String>
    prop produces: Array<String>
    prop priority: Int64
    prop purity: TransformPurity
    func apply(document: Document): Document
}

public class TransformPipeline {
    private let passes: ImmutableArray<TransformPass>

    internal init(passes: Array<TransformPass>) {
        this.passes = ImmutableArray<TransformPass>(passes)
    }

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

    public func orderedPassIds(): Array<String> {
        let out = ArrayList<String>()
        for (pass in passes.toArray()) {
            out.add(pass.id)
        }
        out.toArray()
    }
}
