package markdown

import markdown.core.{ArenaNodePayload, AstArenaBuilder, AstInvariantValidator, AstQuery, LiteralStorage, NodeId, 
    NodeKind, NodeOrigin, NodeOriginKind, NodeRef, NodeRefWalkEvent, ParseResult, SourceBuffer, SourceSpan}
import markdown.editor.{DocumentSnapshot, SourceEdit}
import std.collection.*

// Restricted feasibility candidate: preserve IDs of unchanged semantic nodes,
// rebuild their coordinates in one arena, then rebuild the full CST/map/hash.
// It intentionally rejects other node kinds and all semantic dependencies.
func probeVariableEdit(snapshot: DocumentSnapshot, edit: SourceEdit): ?DocumentSnapshot {
    let engine = snapshot.engine
    let previous = snapshot.result
    let document = previous.document
    let dialect = engine.dialect
    if (!previous.source.hasIdentityMapping() || !document.references.isEmpty() || !dialect.blockRules.isEmpty() ||
        !dialect.inlineRules.isEmpty() || !dialect.parserSpis.isEmpty() || dialect.parserHotPlan.hasDocumentStages ||
        edit.range.endByte > previous.source.byteLength()) {
        return None
    }
    previous.source.slice(edit.range)
    var target: ?NodeRef = None
    for (event in document.walk()) {
        if (let NodeRefWalkEvent.Enter(node) <- event) {
            match (node.kind) {
                case NodeKind.DocumentNode | NodeKind.Paragraph | NodeKind.Heading => ()
                case NodeKind.Text =>
                    let text = node.asText().getOrThrow()
                    if (text.raw != text.value || text.normalized.isSome()) {
                        return None
                    }
                    if (node.span.getOrThrow().containsSpan(edit.range)) {
                        target = Some(node)
                    }
                case _ => return None
            }
        }
    }
    let textNode = match (target) {
        case Some(value) => value;
        case None => return None
    }
    let ancestors = AstQuery.ancestors(document, textNode.nodeId)
    if (ancestors.size != 2) {
        return None
    }
    match (ancestors[1].kind) {
        case NodeKind.Paragraph | NodeKind.Heading => ();
        case _ => return None
    }
    let span = textNode.span.getOrThrow()
    let raw = textNode.asText().getOrThrow().raw
    let nextRaw = raw[..edit.range.startByte - span.startByte] + edit.replacement + raw[edit.range.endByte - span
            .startByte..]
    if (nextRaw.isEmpty() || nextRaw[0] == b' ' || nextRaw[0] == b'\t' || nextRaw[nextRaw.size - 1] == b' ' ||
        nextRaw[nextRaw.size - 1] == b'\t') {
        return None
    }
    for (byte in nextRaw.toArray()) {
        if (byte < 0x80 &&
            !((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || (byte >= b'0' && byte <= b'9') ||
            byte == b' ' || byte == b'\t')) {
            return None
        }
    }
    let source = previous.source.text()
    let nextText = source[..edit.range.startByte] + edit.replacement + source[edit.range.endByte..]
    if (nextText.size > engine.limits.maximumInputBytes) {
        return None
    }
    let nextSource = SourceBuffer(nextText)
    let delta = edit.replacement.size - edit.range.length()
    let changed = HashSet<NodeId>()
    changed.add(textNode.nodeId)
    for (node in ancestors) {
        changed.add(node.nodeId)
    }
    let builder = AstArenaBuilder(maximumNodes: engine.limits.maximumAstNodes, trustedParserConstruction: true,
        sourceBuffer: Some(nextSource), lineage: Some(document.nodeLineage()))
    let indexes = HashMap<Int64, Int64>()
    for (event in document.walk()) {
        if (let NodeRefWalkEvent.Exit(node) <- event) {
            let oldSpan = node.span.getOrThrow()
            let nextSpan = if (changed.contains(node.nodeId)) {
                SourceSpan(oldSpan.startByte, oldSpan.endByte + delta)
            } else if (oldSpan.startByte >= edit.range.endByte) {
                SourceSpan(oldSpan.startByte + delta, oldSpan.endByte + delta)
            } else {
                oldSpan
            }
            let children = node.children()
            let mapped = Array<Int64>(children.size, {index => indexes[children[index].index]})
            let payload = if (let NodeKind.Text <- node.kind) {
                let value = nextSource.slice(nextSpan)
                let normalized: ?String = None
                ArenaNodePayload.TextValue(LiteralStorage.Copy(value), LiteralStorage.Copy(value), normalized)
            } else {
                node.snapshotPayload()
            }
            let index = if (changed.contains(node.nodeId)) {
                builder.appendParserOwned(node.kind, node.category, Some(nextSpan), NodeOriginKind.Transformed, mapped,
                    payload: payload,
                    origin: Some(
                        NodeOrigin(NodeOriginKind.Transformed, sourceNodeIds: [node.nodeId], sourceSpan: Some(nextSpan),
                            transformId: Some("probe/variable-edit"))))
            } else {
                builder.appendSessionNode(node, mapped, Some(nextSpan), payload, Some(node.origin))
            }
            indexes.add(node.index, index)
        }
    }
    let result = builder.freeze(indexes[document.root().index])
    AstInvariantValidator().validate(result, limits: engine.limits)
    Some(DocumentSnapshot(engine, snapshot.version + 1, ParseResult(result, nextSource, previous.diagnostics.toArray())))
}
