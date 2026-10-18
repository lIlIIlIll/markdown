package markdown

import std.collection.*

internal enum RichMathAction {
    | Node(MathMlNode)
    | Children(MathMlNode, Int64)
    | Close(String)
}

internal class RichMathRenderState {
    let sourceNode: NodeRef
    let display: Bool
    let actions = ArrayList<RichMathAction>()
    init(node: NodeRef, root: MathMlNode, display: Bool) {
        sourceNode = node
        this.display = display
        actions.add(RichMathAction.Node(root))
    }
}

internal class RichPngRenderState {
    let node: NodeRef
    let image: RichPngImage
    var offset: Int64 = 0
    init(node: NodeRef, image: RichPngImage) {
        this.node = node
        this.image = image
    }
}

internal class RichCodeRenderState {
    let node: NodeRef
    let code: String
    let tokens: ImmutableArray<CodeHighlightToken>
    let ranges: ImmutableArray<CodeLineRange>
    var offset: Int64 = 0
    var tokenIndex: Int64 = 0
    var rangeIndex: Int64 = 0
    var line: Int64 = 1
    var lineEnd: Int64 = 0
    var stage: Int64 = 0
    var selected = false
    init(node: NodeRef, code: String, tokens: ImmutableArray<CodeHighlightToken>,
        ranges!: ImmutableArray<CodeLineRange> = ImmutableArray<CodeLineRange>([])) {
        this.node = node
        this.code = code
        this.tokens = tokens
        this.ranges = ranges
    }
}

/** Reuses the existing escaping/output budget while recording derived provenance. */
internal class RichDerivedSink <: TextSink {
    private let sink: TextSink
    private let node: NodeRef
    init(sink: TextSink, node: NodeRef) {
        this.sink = sink
        this.node = node
    }
    public func write(value: String): SinkWriteResult {
        match (sink) {
            case mapped: StringTextSink => mapped.writeDerivedFromNode(value, node)
            case _ => sink.write(value)
        }
    }
}

internal func richBase64(image: RichPngImage, start: Int64, end: Int64): String {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    let out = StringBuilder()
    var index = start
    while (index < end) {
        let a = Int64(image.data[index])
        let b = if (index + 1 < end) {
            Int64(image.data[index + 1])
        } else {
            0
        }
        let c = if (index + 2 < end) {
            Int64(image.data[index + 2])
        } else {
            0
        }
        for (value in [a >> 2, ((a & 3) << 4) | (b >> 4)]) {
            out.append(alphabet[value..value + 1])
        }
        if (index + 1 < end) {
            let value = ((b & 15) << 2) | (c >> 6)
            out.append(alphabet[value..value + 1])
        } else {
            out.append("=")
        }
        if (index + 2 < end) {
            let value = c & 63;
            out.append(alphabet[value..value + 1])
        } else {
            out.append("=")
        }
        index += 3
    }
    out.toString()
}

internal func richProductFingerprint(product: RichContentProduct, budget: OperationBudget,
    cancellation: CancellationToken): String {
    let out = CanonicalDescriptor()
    match (product) {
        case RichContentProduct.MathMl(root) =>
            out.append("mathml/1")
            let stack = ArrayList<MathMlNode>()
            stack.add(root)
            while (!stack.isEmpty()) {
                cancellation.throwIfCancelled(phase: "prepare")
                let node = stack.remove(at: stack.size - 1)
                budget.consumeScan(steps: node.text.size + 1)
                out.append(node.tag);
                out.append(node.text);
                out.append(node.attributes.size);
                out.append(node.children.size)
                for (attribute in node.attributes.toArray()) {
                    out.append(attribute.name);
                    out.append(attribute.value)
                }
                var index = node.children.size
                while (index > 0) {
                    index--;
                    stack.add(node.children[index])
                }
            }
        case RichContentProduct.Highlight(tokens) =>
            out.append("highlight/1")
            for (token in tokens.toArray()) {
                cancellation.throwIfCancelled(phase: "prepare")
                budget.consumeScan()
                out.append(token.span.startByte);
                out.append(token.span.endByte);
                out.append(token.color);
                out.append(token.fontStyle)
            }
        case RichContentProduct.Diagram(image) =>
            out.append("png/1")
            budget.consumeScan(steps: image.data.size)
            out.append(Sha256.digestBytes(image.data.toArray()))
    }
    cancellation.throwIfCancelled(phase: "prepare")
    Sha256.digest(out.toString())
}
