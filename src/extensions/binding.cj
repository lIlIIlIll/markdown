package markdown.extensions

import markdown.core.{CustomPayload, FootnoteReferencePayload}

internal class FootnoteReferenceEmitter <: InlinePayloadEmitter {
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        FootnoteReferencePayload(value.rawLiteral, value.literalSpan)
    }
}
