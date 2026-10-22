package markdown

import markdown.artifact.{BinaryArtifactCodec, BinaryArtifactLoadResult, BinarySnapshotArtifact}
import markdown.core.{ArenaNodePayload, AstArenaBuilder, AstInvariantValidator, ImmutableArray, LiteralStorage, 
    NodeCategory, NodeKind, NodeOriginKind, NodeRef, NodeRefWalkEvent, ParseResult, ReferenceDefinition, Sha256, 
    SourceBuffer, SourceSpan, parserConfigurationFingerprint}
import markdown.editor.{DocumentSnapshot, SyntaxKind, SyntaxToken, SyntaxTree, syntaxRootForDocument}
import markdown.engine.MarkdownEngine
import std.collection.*

// Restricted feasibility format, never a production artifact reader. It handles
// only the primitive fixture and omits general Markdown grammar certification.
// Its cost is therefore an optimistic bound on a complete direct decoder.
private class ProbeWireWriter {
    protected let bytes = ArrayList<Byte>()
    protected func number(value: Int64): Unit {
        if (value < 0 || value > Int64(UInt32.Max)) {
            throw IllegalArgumentException("prototype integer range")
        }
        var rest = value
        while (rest >= 128) {
            bytes.add(UInt8((rest & 127) | 128));
            rest = rest >> 7
        }
        bytes.add(UInt8(rest))
    }
    protected func string(value: String): Unit {
        number(value.size);
        bytes.add(all: value.toArray())
    }
}

private class ProbeWireReader {
    protected let bytes: Array<Byte>
    protected var offset: Int64 = 0
    init(bytes: Array<Byte>) {
        this.bytes = bytes
    }
    protected func number(maximum: Int64): Int64 {
        var value: Int64 = 0
        for (index in 0..5) {
            if (offset >= bytes.size) {
                throw IllegalArgumentException("prototype truncated integer")
            }
            let byte = bytes[offset];
            offset++
            value = value | (Int64(byte & 127) << UInt64(index * 7))
            if ((byte & 128) == 0) {
                if (value > maximum || value > Int64(UInt32.Max)) {
                    throw IllegalArgumentException("prototype integer limit")
                }
                return value
            }
        }
        throw IllegalArgumentException("prototype overlong integer")
    }
    protected func take(size: Int64): Array<Byte> {
        if (size < 0 || size > bytes.size - offset) {
            throw IllegalArgumentException("prototype truncated bytes")
        }
        let value = bytes.slice(offset, size);
        offset += size
        value
    }
    protected func string(maximum: Int64): String {
        String.fromUtf8(take(number(maximum)))
    }
    protected func finish(): Unit {
        if (offset != bytes.size) {
            throw IllegalArgumentException("prototype trailing data")
        }
    }
}

private func probeAstTag(node: NodeRef): Int64 {
    match (node.kind) {
        case NodeKind.DocumentNode => 0
        case NodeKind.Heading => 1
        case NodeKind.Paragraph => 2
        case NodeKind.Text =>
            let text = node.asText().getOrThrow()
            if (text.raw != text.value || text.normalized.isSome()) {
                throw IllegalArgumentException("prototype normalized text")
            }
            3
        case _ => throw IllegalArgumentException("prototype unsupported AST kind")
    }
}

private func probeTokenTag(token: SyntaxToken): Int64 {
    match (token.kind) {
        case SyntaxKind.Text => 0
        case SyntaxKind.Whitespace => 1
        case SyntaxKind.Newline => 2
        case SyntaxKind.HeadingMarker => 3
        case _ => throw IllegalArgumentException("prototype unsupported token kind")
    }
}

func probeEncodeCache(snapshot: DocumentSnapshot, mode: String): Array<Byte> {
    if (mode == "source" || mode == "shared") {
        return BinaryArtifactCodec.encode(snapshot).bytes()
    }
    if (mode != "ast" && mode != "direct") {
        throw IllegalArgumentException("prototype cache mode")
    }
    let result = snapshot.result
    if (!result.source.hasIdentityMapping() || result.source.byteLength() > 1024 * 1024 ||
        !result.document.references.isEmpty() || !snapshot.engine.dialect.blockRules.isEmpty() ||
        !snapshot.engine.dialect.inlineRules.isEmpty() || !snapshot.engine.dialect.parserSpis.isEmpty() || snapshot
        .engine
        .dialect
        .parserHotPlan
        .hasDocumentStages) {
        throw IllegalArgumentException("prototype source scope")
    }
    let body = ProbeWireWriter()
    body.string(mode)
    body.string(snapshot.engine.profile.id)
    body.string(snapshot.engine.dialect.fingerprint)
    body.string(
        parserConfigurationFingerprint(snapshot.engine.dialect.fingerprint, snapshot.engine.limits,
            snapshot.engine.bindingOptions))
    body.string(result.source.text())
    body.number(result.document.nodeCount)
    let indexes = HashMap<Int64, Int64>()
    for (event in result.document.walk()) {
        if (let NodeRefWalkEvent.Exit(node) <- event) {
            let tag = probeAstTag(node)
            let span = node.span.getOrThrow()
            if (tag == 3 && node.asText().getOrThrow().raw != result.source.slice(span)) {
                throw IllegalArgumentException("prototype source text mismatch")
            }
            body.number(tag);
            body.number(span.startByte);
            body.number(span.length())
            body.number(if (tag == 1) {
                node.asHeading().getOrThrow().level
            } else {
                0
            })
            let children = node.children()
            body.number(children.size)
            for (index in 0..children.size) {
                body.number(indexes[children[index].index])
            }
            indexes.add(node.index, indexes.size)
        }
    }
    if (mode == "direct") {
        let tokens = snapshot.syntaxTree.root.tokens
        body.number(tokens.size)
        for (index in 0..tokens.size) {
            let token = tokens[index]
            body.number(token.span.length() * 8 + probeTokenTag(token))
        }
    }
    let payload = body.bytes.toArray()
    let out = ProbeWireWriter()
    out.string("MD-PROBE-CACHE/1")
    out.string(Sha256.digestBytes(payload))
    out.number(payload.size);
    out.bytes.add(all: payload)
    out.bytes.toArray()
}

private func probeReadToken(source: SourceBuffer, reader: ProbeWireReader, offset: Int64): SyntaxToken {
    let descriptor = reader.number(Int64(UInt32.Max))
    let tag = descriptor & 7
    let length = descriptor >> 3
    if (length == 0 || length > source.byteLength() - offset) {
        throw IllegalArgumentException("prototype token range")
    }
    let span = SourceSpan(offset, offset + length)
    let raw = source.slice(span)
    let kind = match (tag) {
        case 0 =>
            let first = raw[0]
            let width: Int64 = if (first < 0x80) {
                1
            } else if ((first & 0xE0) == 0xC0) {
                2
            } else if ((first & 0xF0) == 0xE0) {
                3
            } else {
                4
            }
            if (raw.size != width || !probeTextByte(first)) {
                throw IllegalArgumentException("prototype text token")
            }
            SyntaxKind.Text
        case 1 =>
            for (byte in raw.toArray()) {
                if (byte != b' ' && byte != b'\t') {
                    throw IllegalArgumentException("prototype whitespace token")
                }
            }
            SyntaxKind.Whitespace
        case 2 =>
            if (raw != "\r\n" && raw != "\n" && raw != "\r") {
                throw IllegalArgumentException("prototype newline token")
            }
            SyntaxKind.Newline
        case 3 =>
            if (raw != "#") {
                throw IllegalArgumentException("prototype heading token")
            }
            SyntaxKind.HeadingMarker
        case _ => throw IllegalArgumentException("prototype unknown token kind")
    }
    SyntaxToken(kind, raw, span)
}

func probeDecodeCache(engine: MarkdownEngine, data: Array<Byte>, mode: String): DocumentSnapshot {
    if (mode == "source" || mode == "shared") {
        match (BinaryArtifactCodec.decode(engine, BinarySnapshotArtifact(data))) {
            case BinaryArtifactLoadResult.Hit(value) => return value
            case BinaryArtifactLoadResult.CacheMiss(reason) => throw IllegalArgumentException(reason)
        }
    }
    if (data.size > 16 * 1024 * 1024) {
        throw IllegalArgumentException("prototype wire limit")
    }
    let outer = ProbeWireReader(data.clone())
    if (outer.string(64) != "MD-PROBE-CACHE/1") {
        throw IllegalArgumentException("prototype schema")
    }
    let digest = outer.string(64)
    let payload = outer.take(outer.number(16 * 1024 * 1024))
    outer.finish()
    if (digest != Sha256.digestBytes(payload)) {
        throw IllegalArgumentException("prototype checksum")
    }
    let reader = ProbeWireReader(payload)
    if (reader.string(16) != mode || (mode != "ast" && mode != "direct") || reader.string(128) != engine.profile.id ||
        reader.string(128) != engine.dialect.fingerprint || reader.string(128) != parserConfigurationFingerprint(
        engine.dialect.fingerprint, engine.limits, engine.bindingOptions)) {
        throw IllegalArgumentException("prototype configuration")
    }
    let source = SourceBuffer(reader.string(min(engine.limits.maximumInputBytes, 1024 * 1024)))
    let count = reader.number(min(engine.limits.maximumAstNodes, 1000000))
    if (count == 0) {
        throw IllegalArgumentException("prototype empty AST")
    }
    let builder = AstArenaBuilder(maximumNodes: engine.limits.maximumAstNodes, sourceBuffer: Some(source))
    var roots: Int64 = 0
    for (index in 0..count) {
        let tag = reader.number(3)
        let start = reader.number(source.byteLength())
        let length = reader.number(source.byteLength() - start)
        let span = SourceSpan(start, start + length)
        let sourceText = source.text()
        if ((start < sourceText.size && (sourceText[start] & 0xC0) == 0x80) || (span.endByte < sourceText.size &&
            (sourceText[span.endByte] & 0xC0) == 0x80)) {
            throw IllegalArgumentException("prototype scalar boundary")
        }
        let level = reader.number(6)
        let childCount = reader.number(index)
        let children = Array<Int64>(childCount, {_ => reader.number(index - 1)})
        let noNormalized: ?String = None
        let payload: ArenaNodePayload
        let kind: NodeKind
        match (tag) {
            case 0 =>
                if (index != count - 1 || start != 0 || length != source.byteLength() || level != 0) {
                    throw IllegalArgumentException("prototype root")
                }
                roots++
                kind = NodeKind.DocumentNode
                payload = ArenaNodePayload.DocumentValue(engine.profile, engine.dialect.fingerprint,
                    ImmutableArray<ReferenceDefinition>([]))
            case 1 =>
                if (level < 1) {
                    throw IllegalArgumentException("prototype heading level")
                }
                kind = NodeKind.Heading
                payload = ArenaNodePayload.HeadingValue(level)
            case 2 =>
                if (level != 0) {
                    throw IllegalArgumentException("prototype paragraph level")
                }
                kind = NodeKind.Paragraph
                payload = ArenaNodePayload.Empty
            case _ =>
                if (level != 0 || childCount != 0) {
                    throw IllegalArgumentException("prototype text shape")
                }
                let value = source.slice(span)
                kind = NodeKind.Text
                payload = ArenaNodePayload.TextValue(LiteralStorage.Copy(value), LiteralStorage.Copy(value),
                    noNormalized)
        }
        builder.append(kind, if (tag == 3) {
            NodeCategory.Inline
        } else {
            NodeCategory.Block
        }, Some(span), NodeOriginKind.Parsed, children, payload: payload)
    }
    let document = builder.freeze(count - 1)
    if (roots != 1 || document.nodeCount != count) {
        throw IllegalArgumentException("prototype disconnected AST")
    }
    AstInvariantValidator().validate(document, limits: engine.limits)
    let result = ParseResult(document, source, [])
    if (mode == "ast") {
        reader.finish()
        return DocumentSnapshot(engine, 1, result)
    }
    let tokenCount = reader.number(source.byteLength())
    let tokens = ArrayList<SyntaxToken>()
    var offset: Int64 = 0
    for (_ in 0..tokenCount) {
        let token = probeReadToken(source, reader, offset)
        tokens.add(token);
        offset = token.span.endByte
    }
    if (offset != source.byteLength()) {
        throw IllegalArgumentException("prototype token coverage")
    }
    reader.finish()
    let values = tokens.toArray()
    let syntax = SyntaxTree(source, syntaxRootForDocument(document, values), values, Some(document))
    DocumentSnapshot(engine, 1, result, restoredSyntax: syntax)
}
