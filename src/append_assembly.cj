package markdown

import std.collection.*

private class AppendAssemblyFrame {
    let node: NodeRef
    let exiting: Bool
    let children: Array<NodeRef>

    init(node: NodeRef, exiting: Bool, children: Array<NodeRef>) {
        this.node = node
        this.exiting = exiting
        this.children = children
    }
}

/** One final storage assembly, not another block/inline parse of the source. */
internal class AppendTreeAssembler {
    private let engine: MarkdownEngine
    private let source: SourceBuffer
    private let lineage: NodeLineage
    private let budget: OperationBudget
    private let cancellation: CancellationToken
    private let builder: AstArenaBuilder
    private let constructionBudget: ?NodeConstructionBudget
    private let references: PreparedReferences
    private let roots = ArrayList<Int64>()
    private let identities = HashSet<NodeId>()
    private let diagnostics = ArrayList<Diagnostic>()
    private var sealed = false
    private var resolvedInlineTaskCount: Int64 = 0

    init(engine: MarkdownEngine, source: SourceBuffer, lineage: NodeLineage, budget: OperationBudget,
        cancellation: CancellationToken, references: Array<ReferenceDefinition>,
        constructionBudget!: ?NodeConstructionBudget = None) {
        this.engine = engine
        this.source = source
        this.lineage = lineage
        this.budget = budget
        this.cancellation = cancellation
        this.references = PreparedReferences(references)
        this.constructionBudget = constructionBudget
        builder = AstArenaBuilder(maximumNodes: engine.limits.maximumAstNodes, trustedParserConstruction: true,
            sourceBuffer: Some(source), lineage: Some(lineage), constructionBudget: constructionBudget)
    }

    func append(fragment: ParsedDraft, offset: Int64): Unit {
        if (sealed) {
            throw IllegalStateException("append assembly is complete")
        }
        if (offset < 0 || offset > source.byteLength() || fragment.source.byteLength() > source.byteLength() - offset) {
            throw IllegalArgumentException("fragment source is outside the complete input")
        }
        fragment.document.requireSource(fragment.source)
        let mapped = HashMap<NodeId, Array<Int64>>()
        let stack = ArrayList<AppendAssemblyFrame>()
        stack.add(AppendAssemblyFrame(fragment.document.root(), false, []))
        while (!stack.isEmpty()) {
            cancellation.throwIfCancelled(phase: "append_assembly")
            budget.consumeScan()
            let frame = stack.remove(at: stack.size - 1)
            let node = frame.node
            let task = pendingTask(node)
            if (!frame.exiting) {
                var children = node.children().toArray()
                if (let Some(value) <- task) {
                    resolvedInlineTaskCount++
                    let noAccelerator: ?LineScannerAccelerator = None
                    let resolver = ParserSession(engine.profile, engine.limits, cancellation, budget, value.source,
                        engine.dialect, false, noAccelerator, bindingOptions: engine.bindingOptions,
                        lineage: Some(lineage), preparedReferences: Some(references), documentOffset: offset,
                        estimatedInputBytes: Some(value.text.size), constructionBudget: constructionBudget)
                    let resolved = try {
                        resolver.resolvePendingInline(value)
                    } catch (error: MarkdownException) {
                        throw shiftAppendException(error, offset)
                    }
                    children = resolved.nodes
                    for (diagnostic in resolved.diagnostics) {
                        diagnostics.add(shiftedDiagnostic(diagnostic, offset))
                    }
                }
                stack.add(AppendAssemblyFrame(node, true, children))
                var index = children.size - 1
                while (index >= 0) {
                    stack.add(AppendAssemblyFrame(children[index], false, []))
                    index--
                }
                continue
            }
            let children = ArrayList<Int64>()
            for (child in frame.children) {
                children.add(all: mapped[child.nodeId])
            }
            if (node.asDocument().isSome() || task.isSome()) {
                mapped.add(node.nodeId, children.toArray())
                continue
            }
            if (!identities.add(node.nodeId)) {
                throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                    "an append node was assembled more than once", phase: "append_assembly", span: node.span)
            }
            let span = shifted(node.span, offset)
            let payload = shiftedPayload(node.snapshotPayload(), offset)
            let origin: ?NodeOrigin = if (let NodeOriginKind.Parsed <- node.originKind) {
                None
            } else {
                let original = node.origin
                Some(
                    NodeOrigin(original.kind, sourceNodeIds: original.sourceNodeIds.toArray(),
                        sourceSpan: shifted(original.sourceSpan, offset), transformId: original.transformId,
                        extensionId: original.extensionId))
            }
            mapped.add(node.nodeId, [builder.appendSessionNode(node, children.toArray(), span, payload, origin)])
        }
        roots.add(all: mapped[fragment.document.nodeId])
    }

    func finish(): Document {
        if (sealed) {
            throw IllegalStateException("append assembly is complete")
        }
        sealed = true
        cancellation.throwIfCancelled(phase: "append_assembly")
        let root = builder.appendParserOwned(NodeKind.DocumentNode, NodeCategory.Block,
            Some(SourceSpan(0, source.byteLength())), NodeOriginKind.Parsed, roots.toArray(),
            payload: ArenaNodePayload.DocumentValue(engine.profile, engine.dialect.fingerprint,
                ImmutableArray<ReferenceDefinition>(references.definitions)))
        let document = builder.freeze(root)
        AstInvariantValidator().validate(document, limits: engine.limits)
        document
    }

    func resolvedInlineTasks(): Int64 {
        resolvedInlineTaskCount
    }

    func inlineDiagnostics(): Array<Diagnostic> {
        diagnostics.toArray()
    }

    private func shiftedDiagnostic(value: Diagnostic, offset: Int64): Diagnostic {
        let related = ArrayList<SourceSpan>()
        for (span in value.relatedSpans) {
            related.add(shiftSpan(span, offset))
        }
        let fixes = ArrayList<DiagnosticFix>()
        for (fix in value.fixes.toArray()) {
            fixes.add(DiagnosticFix(fix.title, shiftSpan(fix.span, offset), fix.replacement))
        }
        Diagnostic(value.code, value.severity, value.message, shiftSpan(value.span, offset),
            relatedSpans: related.toArray(), extensionId: value.extensionId, ruleId: value.ruleId,
            fixes: fixes.toArray())
    }

    private func shifted(span: ?SourceSpan, offset: Int64): ?SourceSpan {
        span.map({value => shiftSpan(value, offset)})
    }

    private func shiftSpan(span: SourceSpan, offset: Int64): SourceSpan {
        if (span.endByte > source.byteLength() - offset) {
            throw MarkdownException(MarkdownErrorCode.InternalInvariantViolation,
                "fragment span is outside complete input", phase: "append_assembly", span: Some(span))
        }
        SourceSpan(span.startByte + offset, span.endByte + offset)
    }

    private func shiftedPayload(payload: ArenaNodePayload, offset: Int64): ArenaNodePayload {
        match (payload) {
            case ArenaNodePayload.ListItemValue(state, marker) => ArenaNodePayload.ListItemValue(state,
                shifted(marker, offset))
            case ArenaNodePayload.CodeBlockValue(kind, literal, marker, length, opener, closer, info, language, attributes) => ArenaNodePayload
                .CodeBlockValue(kind, literal, marker, length, shifted(opener, offset), shifted(closer, offset), info,
                    language, attributes)
            case ArenaNodePayload.CustomValue(extensionId, version, kind, custom) => ArenaNodePayload.CustomValue(
                extensionId, version, kind, shiftedCustom(custom, offset))
            case _ => payload
        }
    }

    private func shiftedCustom(payload: CustomPayload, offset: Int64): CustomPayload {
        match (payload) {
            case value: DefinitionListPayload => DefinitionListPayload(value.role,
                markerSpan: shifted(value.markerSpan, offset))
            case value: FootnoteReferencePayload =>
                budget.consumeScan(steps: value.labelRaw.size)
                FootnoteReferencePayload(value.labelRaw, shiftSpan(value.labelSpan, offset))
            case value: FootnoteDefinitionPayload =>
                budget.consumeScan(steps: value.labelRaw.size)
                FootnoteDefinitionPayload(value.labelRaw, shiftSpan(value.labelSpan, offset))
            case value: HeadingIdPayload => HeadingIdPayload(value.rawId, shiftSpan(value.idSpan, offset))
            case value: SyntaxPayload => value
            case _ => throw MarkdownException(MarkdownErrorCode.UnsupportedNode,
                "append assembly has no source relocation contract for this custom payload", phase: "append_assembly")
        }
    }

    private func pendingTask(node: NodeRef): ?PendingInlineTask {
        if (let NodeKind.CustomInline <- node.kind) {
            if (let value: PendingInlineTask <- node.asCustomInline().getOrThrow().payload) {
                return Some(value)
            }
        }
        None
    }
}
