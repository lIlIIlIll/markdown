package markdown

import std.collection.*

/** Built once after definition discovery and read by every deferred inline task. */
internal class PreparedReferences {
    let values = HashMap<String, ReferenceDefinition>()
    let definitions: Array<ReferenceDefinition>
    init(definitions: Array<ReferenceDefinition>) {
        this.definitions = definitions
        for (definition in definitions) {
            if (definition.isEffective && values.get(definition.labelNormalized).isNone()) {
                values.add(definition.labelNormalized, definition)
            }
        }
    }
}

/** Internal pending work, never a successful ParseResult or serializable payload. */
internal class PendingInlineTask <: CustomPayload {
    let source: SourceBuffer
    let text: String
    let baseOffset: Int64
    let depth: Int64
    let offsets: ?Array<Int64>
    let mapBase: Int64
    let suppressedRule: String
    let sourceIdentity: Bool

    init(source: SourceBuffer, text: String, baseOffset: Int64, depth: Int64, offsets: ?Array<Int64>, mapBase: Int64,
        suppressedRule: String, sourceIdentity: Bool) {
        this.source = source
        this.text = text
        this.baseOffset = baseOffset
        this.depth = depth
        this.offsets = offsets
        this.mapBase = mapBase
        this.suppressedRule = suppressedRule
        this.sourceIdentity = sourceIdentity
    }

    public func payloadTypeId(): String {
        "markdown.pending-inline/1"
    }
}

/** A structurally parsed fragment whose inline/binding work is not complete. */
internal class ParsedDraft {
    let document: Document
    let source: SourceBuffer
    let diagnostics: Array<Diagnostic>

    init(document: Document, source: SourceBuffer, diagnostics: Array<Diagnostic>) {
        this.document = document
        this.source = source
        this.diagnostics = diagnostics
    }
}

internal class ResolvedInline {
    let nodes: Array<NodeRef>
    let diagnostics: Array<Diagnostic>
    init(nodes: Array<NodeRef>, diagnostics: Array<Diagnostic>) {
        this.nodes = nodes
        this.diagnostics = diagnostics
    }
}

internal class CapturedDraft {
    let draft: ParsedDraft
    let offset: Int64
    let span: SourceSpan
    init(draft: ParsedDraft, offset: Int64, span: SourceSpan) {
        this.draft = draft
        this.offset = offset
        this.span = span
    }
}
