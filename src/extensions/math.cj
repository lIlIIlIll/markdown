package markdown.extensions

import markdown.core.{CustomPayload, MathPayload, MathSourcePart, SourceSpan}

internal class MathInlineEmitter <: InlinePayloadEmitter {
    public func emit(value: InlineSyntaxMatch): CustomPayload {
        MathPayload(false, value.literal, [MathSourcePart(value.literalSpan)],
            SourceSpan(value.span.startByte, value.literalSpan.startByte),
            SourceSpan(value.literalSpan.endByte, value.span.endByte))
    }
}
