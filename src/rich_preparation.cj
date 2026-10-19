package markdown

import std.collection.*

/** 对一个完整成功文档进行显式准备；解析本身不会调用此入口。 */
public class RichContentPreparer {
    /** 收集固定语义、查询有界缓存、调用后端并校验每个产物。
     * @param result 完整且来源匹配的解析结果。
     * @param options 宿主显式开启的能力和严格失败策略。
     * @param backend 可选可信端口；缺失不会尝试安装、联网或寻找可执行文件。
     * @param limits 准备阶段的独立累计上限。
     * @param cache 宿主拥有的非并发 Ready 缓存。
     * @param budget 整个操作共用的预算。
     * @param cancellation 整个操作共用的取消 token。
     */
    public static func prepare(result: ParseResult, options!: RichContentOptions = RichContentOptions(),
        backend!: ?RichContentBackend = None, limits!: RichContentLimits = RichContentLimits(),
        cache!: ?RichContentCache = None, budget!: OperationBudget = OperationBudget.safe(),
        cancellation!: CancellationToken = CancellationToken.none()): RichContentPreparation {
        result.document.requireSource(result.source)
        cancellation.throwIfCancelled(phase: "prepare")
        let work = RichPreparationWork(result.document, options, backend, limits, cache, budget, cancellation)
        work.run()
    }
}

private class RichPreparationItem {
    let node: NodeRef
    let request: RichContentRequest
    let parts: Array<SourceSpan>
    let key: String
    var outcome: ?RichContentOutcome
    init(node: NodeRef, request: RichContentRequest, parts: Array<SourceSpan>, key: String, outcome: ?RichContentOutcome) {
        this.node = node
        this.request = request
        this.parts = parts
        this.key = key
        this.outcome = outcome
    }
}

private class RichPreparationWork {
    private let document: Document
    private let options: RichContentOptions
    private let backend: ?RichContentBackend
    private let limits: RichContentLimits
    private let cache: ?RichContentCache
    private let budget: OperationBudget
    private let cancellation: CancellationToken
    private let items = ArrayList<RichPreparationItem>()
    private let pending = ArrayList<Int64>()
    private var inputBytes: Int64 = 0
    private var outputBytes: Int64 = 0

    init(document: Document, options: RichContentOptions, backend: ?RichContentBackend, limits: RichContentLimits,
        cache: ?RichContentCache, budget: OperationBudget, cancellation: CancellationToken) {
        this.document = document
        this.options = options
        this.backend = backend
        this.limits = limits
        this.cache = cache
        this.budget = budget
        this.cancellation = cancellation
    }

    func run(): RichContentPreparation {
        let stack = ArrayList<(NodeRef, Bool)>()
        stack.add((document.root(), false))
        while (!stack.isEmpty()) {
            cancellation.throwIfCancelled(phase: "prepare")
            budget.consumeScan()
            let frame = stack.remove(at: stack.size - 1)
            let node = frame[0]
            let inCodeGroup = frame[1]
            if (let Some(value) <- mathPayload(node)) {
                if (!node.documentBindings.semanticPayloadsValidated) {
                    throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                        "rich math preparation requires a bound document", phase: "prepare", span: node.span)
                }
                let parts = Array<SourceSpan>(value.expressionSource.size, {i => value.expressionSource[i].span})
                collect(node, RichContentRequest(RichContentKind.Math, value.expression, display: value.display), parts)
            } else if (let NodeKind.CodeBlock <- node.kind) {
                let code = node.asCodeBlock().getOrThrow()
                if (!code.language.isEmpty()) {
                    let kind = if (code.language == "mermaid" && !inCodeGroup) {
                        RichContentKind.Diagram
                    } else {
                        RichContentKind.Highlight
                    }
                    collect(node, RichContentRequest(kind, code.literal, language: code.language), match (node.span) {
                        case Some(span) => [span];
                        case None => []
                    })
                }
            }
            let children = node.children()
            let grouped = inCodeGroup || codeGroupPayload(node).isSome()
            var index = children.size
            while (index > 0) {
                index--;
                stack.add((children[index], grouped))
            }
        }
        if (!pending.isEmpty()) {
            invokeBackend()
        }
        let entries = ArrayList<RichPreparedEntry>()
        let descriptor = CanonicalDescriptor()
        descriptor.append("rich-content-preparation/1")
        for (item in items) {
            cancellation.throwIfCancelled(phase: "prepare")
            let outcome = item.outcome.getOrThrow()
            if (options.strict && options.enabled(item.request.kind)) {
                if (let RichContentOutcome.Unavailable(reason) <- outcome) {
                    throw MarkdownException(MarkdownErrorCode.RenderFailure, "rich content ${reason.code()}",
                        phase: "prepare", span: item.node.span)
                }
            }
            descriptor.append(item.request.kind.id())
            descriptor.append(item.key)
            match (outcome) {
                case RichContentOutcome.Ready(product) => descriptor.append(
                    richProductFingerprint(product, budget, cancellation))
                case RichContentOutcome.Unavailable(reason) => descriptor.append(reason.code())
            }
            entries.add(RichPreparedEntry(item.node.nodeId, item.request.kind, item.parts, outcome, item.key))
        }
        RichContentPreparation(document.revision, entries.toArray(), Sha256.digest(descriptor.toString()))
    }

    private func collect(node: NodeRef, request: RichContentRequest, parts: Array<SourceSpan>): Unit {
        if (items.size == limits.maximumRequests) {
            throw LimitExceededException("rich_requests", limits.maximumRequests, items.size + 1, "prepare")
        }
        if (request.source.size > limits.maximumInputBytes || request.source.size > limits.maximumTotalInputBytes -
            inputBytes) {
            throw LimitExceededException("rich_input_bytes", limits.maximumTotalInputBytes,
                inputBytes + request.source.size, "prepare", span: node.span)
        }
        inputBytes += request.source.size
        budget.consumeScan(steps: request.source.size)
        if (!options.enabled(request.kind)) {
            items.add(
                RichPreparationItem(node, request, parts, "",
                    Some(RichContentOutcome.Unavailable(RichContentFailure.Disabled))))
            return
        }
        if (request.language.size > 128) {
            items.add(
                RichPreparationItem(node, request, parts, "",
                    Some(RichContentOutcome.Unavailable(RichContentFailure.Unsupported))))
            return
        }
        let port = match (backend) {
            case Some(value) => value
            case None =>
                items.add(
                    RichPreparationItem(node, request, parts, "",
                        Some(RichContentOutcome.Unavailable(RichContentFailure.Missing))))
                return
        }
        let identity = try {
            port.identity(request.kind)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled | MarkdownErrorCode.BudgetExceeded => throw error
                case _ => ""
            }
        } catch (_: Exception) {
            ""
        }
        cancellation.throwIfCancelled(phase: "prepare")
        if (identity.isEmpty() || identity.size > 1024) {
            items.add(
                RichPreparationItem(node, request, parts, "",
                    Some(RichContentOutcome.Unavailable(RichContentFailure.Failed))))
            return
        }
        let descriptor = CanonicalDescriptor()
        descriptor.append("rich-content/1")
        descriptor.append(request.kind.id())
        descriptor.append(request.language)
        descriptor.append(request.display)
        descriptor.append(identity)
        descriptor.append(request.source)
        budget.consumeScan(steps: request.source.size)
        let key = Sha256.digest(descriptor.toString())
        let noOutcome: ?RichContentOutcome = None
        let item = RichPreparationItem(node, request, parts, key, noOutcome)
        if (let Some(store) <- cache) {
            if (let Some(product) <- store.find(key)) {
                item.outcome = Some(validate(item, RichContentOutcome.Ready(product)))
            }
        }
        if (item.outcome.isNone()) {
            pending.add(items.size)
        }
        items.add(item)
    }

    private func invokeBackend(): Unit {
        cancellation.throwIfCancelled(phase: "prepare")
        budget.consumeExtensionCallback()
        let requests = Array<RichContentRequest>(pending.size, {i => items[pending[i]].request})
        let outcomes = try {
            backend.getOrThrow().prepare(requests, limits, budget, cancellation)
        } catch (error: MarkdownException) {
            match (error.code) {
                case MarkdownErrorCode.Cancelled | MarkdownErrorCode.BudgetExceeded => throw error
                case MarkdownErrorCode.LimitExceeded => unavailable(RichContentFailure.Limited)
                case _ => unavailable(RichContentFailure.Failed)
            }
        } catch (_: Exception) {
            unavailable(RichContentFailure.Failed)
        }
        cancellation.throwIfCancelled(phase: "prepare")
        if (outcomes.size != pending.size) {
            for (index in pending) {
                items[index].outcome = Some(RichContentOutcome.Unavailable(RichContentFailure.Failed))
            }
            return
        }
        for (index in 0..pending.size) {
            let item = items[pending[index]]
            let checked = validate(item, outcomes[index])
            item.outcome = Some(checked)
        }
    }

    private func unavailable(reason: RichContentFailure): Array<RichContentOutcome> {
        Array<RichContentOutcome>(pending.size, repeat: RichContentOutcome.Unavailable(reason))
    }

    private func validate(item: RichPreparationItem, outcome: RichContentOutcome): RichContentOutcome {
        cancellation.throwIfCancelled(phase: "prepare")
        if (let RichContentOutcome.Ready(product) <- outcome) {
            let size = try {
                validateRichProduct(item.request, product, limits, budget, cancellation)
            } catch (error: MarkdownException) {
                match (error.code) {
                    case MarkdownErrorCode.Cancelled | MarkdownErrorCode.BudgetExceeded => throw error
                    case MarkdownErrorCode.LimitExceeded => return RichContentOutcome.Unavailable(
                        RichContentFailure.Limited)
                    case _ => return RichContentOutcome.Unavailable(RichContentFailure.Failed)
                }
            } catch (_: Exception) {
                return RichContentOutcome.Unavailable(RichContentFailure.Failed)
            }
            if (size > limits.maximumTotalOutputBytes - outputBytes) {
                return RichContentOutcome.Unavailable(RichContentFailure.Limited)
            }
            outputBytes += size
            if (let Some(store) <- cache) {
                store.insert(item.key, product, size)
            }
        }
        outcome
    }
}
