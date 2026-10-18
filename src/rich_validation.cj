package markdown

import std.collection.*

internal func validateRichProduct(request: RichContentRequest, product: RichContentProduct, limits: RichContentLimits,
    budget: OperationBudget, cancellation: CancellationToken): Int64 {
    cancellation.throwIfCancelled(phase: "prepare")
    let size = match ((request.kind, product)) {
        case (RichContentKind.Math, RichContentProduct.MathMl(root)) => validateRichMath(root, request.display, limits,
            budget, cancellation)
        case (RichContentKind.Highlight, RichContentProduct.Highlight(tokens)) => validateRichTokens(request.source,
            tokens, limits, budget, cancellation)
        case (RichContentKind.Diagram, RichContentProduct.Diagram(image)) => validateRichPng(image, limits, budget,
            cancellation)
        case _ => invalidRichProduct()
    }
    if (size > limits.maximumOutputBytes) {
        throw LimitExceededException("rich_output_bytes", limits.maximumOutputBytes, size, "prepare")
    }
    size
}

private func validateRichMath(root: MathMlNode, display: Bool, limits: RichContentLimits, budget: OperationBudget,
    cancellation: CancellationToken): Int64 {
    if (root.tag != "math") {
        invalidRichProduct()
    }
    let stack = ArrayList<(MathMlNode, Int64)>()
    stack.add((root, 1))
    var nodes: Int64 = 0
    var bytes: Int64 = 0
    while (!stack.isEmpty()) {
        cancellation.throwIfCancelled(phase: "prepare")
        budget.consumeScan()
        let frame = stack.remove(at: stack.size - 1)
        let node = frame[0]
        let depth = frame[1]
        nodes++
        if (nodes > limits.maximumTreeNodes || depth > limits.maximumTreeDepth) {
            throw LimitExceededException("rich_math_tree", limits.maximumTreeNodes, nodes, "prepare")
        }
        bytes += node.tag.size + node.text.size + 5
        budget.consumeScan(steps: node.text.size)
        if (bytes > limits.maximumOutputBytes) {
            throw LimitExceededException("rich_output_bytes", limits.maximumOutputBytes, bytes, "prepare")
        }
        if (node.tag.isEmpty()) {
            if (node.attributes.size != 0 || node.children.size != 0) {
                invalidRichProduct()
            }
            for (byte in node.text.toArray()) {
                if (byte < 32 && byte != 9 && byte != 10 && byte != 13) {
                    invalidRichProduct()
                }
            }
            continue
        }
        if (!node.text.isEmpty() || !richMathTag(node.tag) || (node.tag == "math" && depth != 1) ||
            node.attributes.size > 32) {
            invalidRichProduct()
        }
        if (node.children.size > limits.maximumTreeNodes - nodes - stack.size) {
            throw LimitExceededException("rich_math_tree", limits.maximumTreeNodes, limits.maximumTreeNodes + 1,
                "prepare")
        }
        let names = HashSet<String>()
        for (attribute in node.attributes.toArray()) {
            budget.consumeScan(steps: attribute.name.size + attribute.value.size)
            if (attribute.name.size > 32 || !names.add(attribute.name) || !richMathAttribute(attribute, node.tag,
                display)) {
                invalidRichProduct()
            }
            bytes += attribute.name.size + attribute.value.size + 4
        }
        var index = node.children.size
        while (index > 0) {
            index--
            stack.add((node.children[index], depth + 1))
        }
    }
    bytes
}

private func richMathTag(tag: String): Bool {
    for (allowed in ["math", "mrow", "mi", "mn", "mo", "mtext", "ms", "mspace", "mfrac", "msqrt", "mroot", "msub",
        "msup", "msubsup", "munder", "mover", "munderover", "mtable", "mtr", "mtd", "mstyle", "mpadded", "mphantom",
        "menclose", "semantics"]) {
        if (tag == allowed) {
            return true
        }
    }
    false
}

private func richMathAttribute(attribute: MathMlAttribute, tag: String, display: Bool): Bool {
    let name = attribute.name
    let value = attribute.value
    if (value.size > 128 || value.isEmpty()) {
        return false
    }
    match (name) {
        case "xmlns" => tag == "math" && value == "http://www.w3.org/1998/Math/MathML"
        case "display" => tag == "math" && value == (if (display) {
            "block"
        } else {
            "inline"
        })
        case "mathvariant" => richOneOf(value,
            ["normal", "bold", "italic", "bold-italic", "double-struck", "fraktur", "bold-fraktur", "script",
                "bold-script", "sans-serif", "bold-sans-serif", "sans-serif-italic", "sans-serif-bold-italic",
                "monospace", "initial", "tailed", "looped", "stretched"])
        case "fence" | "stretchy" | "symmetric" | "separator" | "largeop" | "movablelimits" | "accent" | "accentunder"
            | "displaystyle" | "bevelled" | "equalrows" | "equalcolumns" => value == "true" || value == "false"
        case "scriptlevel" => richOneOf(value, ["0", "1", "2", "+1", "+2", "-1", "-2"])
        case "columnalign" | "rowalign" => richMathWords(value,
            ["left", "center", "right", "top", "bottom", "baseline", "axis"])
        case "notation" => richMathWords(value,
            ["box", "roundedbox", "circle", "left", "right", "top", "bottom", "updiagonalstrike", "downdiagonalstrike",
                "verticalstrike", "horizontalstrike", "radical", "longdiv"])
        case "mathcolor" | "mathbackground" => richMathColor(value)
        case "width" | "height" | "depth" | "lspace" | "rspace" | "voffset" | "minsize" | "maxsize" | "linethickness"
            | "mathsize" | "columnspacing" | "rowspacing" => richMathLengths(value)
        case _ => false
    }
}

private func richOneOf(value: String, allowed: Array<String>): Bool {
    for (candidate in allowed) {
        if (value == candidate) {
            return true
        }
    }
    false
}

private func richMathWords(value: String, allowed: Array<String>): Bool {
    for (word in value.split(" ")) {
        if (word.isEmpty() || !richOneOf(word, allowed)) {
            return false
        }
    }
    true
}

private func richMathLengths(value: String): Bool {
    for (word in value.split(" ")) {
        var index: Int64 = 0
        if (word.isEmpty()) {
            return false
        }
        if (word[0] == b'+' || word[0] == b'-') {
            index++
        }
        var number: Int64 = 0
        var digits: Int64 = 0
        var dots: Int64 = 0
        while (index < word.size) {
            let byte = word[index]
            if (byte == b'.') {
                dots++;
                index++;
                continue
            }
            if (byte < b'0' || byte > b'9') {
                break
            }
            digits++
            if (dots == 0) {
                number = number * 10 + Int64(byte - b'0')
            }
            if (number > 10000) {
                return false
            }
            index++
        }
        if (digits == 0 || dots > 1 || !richOneOf(word[index..], ["", "em", "ex", "px", "pt", "mu", "%"])) {
            return false
        }
    }
    true
}

private func richMathColor(value: String): Bool {
    if (value[0] == b'#') {
        if (value.size != 4 && value.size != 7 && value.size != 9) {
            return false
        }
        for (index in 1..value.size) {
            if (!richHex(value[index])) {
                return false
            }
        }
    } else {
        if (value.size > 32) {
            return false
        }
        for (byte in value.toArray()) {
            if (!((byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z'))) {
                return false
            }
        }
    }
    true
}

internal func richHex(byte: Byte): Bool {
    (byte >= b'0' && byte <= b'9') || (byte >= b'a' && byte <= b'f') || (byte >= b'A' && byte <= b'F')
}

private func validateRichTokens(source: String, tokens: ImmutableArray<CodeHighlightToken>, limits: RichContentLimits,
    budget: OperationBudget, cancellation: CancellationToken): Int64 {
    if (tokens.size > limits.maximumTokens) {
        throw LimitExceededException("rich_tokens", limits.maximumTokens, tokens.size, "prepare")
    }
    var end: Int64 = 0
    var size: Int64 = 0
    for (token in tokens.toArray()) {
        cancellation.throwIfCancelled(phase: "prepare")
        budget.consumeScan()
        if (token.span.startByte < end || token.span.endByte > source.size || token.span.length() == 0 ||
            !richStringBoundary(source, token.span.startByte) || !richStringBoundary(source, token.span.endByte) ||
            token.color.size != 7 || token.color[0] != b'#' || token.fontStyle < 0 || token.fontStyle > 7) {
            invalidRichProduct()
        }
        for (index in 1..7) {
            if (!richHex(token.color[index])) {
                invalidRichProduct()
            }
        }
        end = token.span.endByte
        size += 32
    }
    size
}

internal func richStringBoundary(value: String, offset: Int64): Bool {
    offset >= 0 && offset <= value.size && (offset == value.size || (value[offset] & 0xC0) != 0x80)
}

private func validateRichPng(image: RichPngImage, limits: RichContentLimits, budget: OperationBudget,
    cancellation: CancellationToken): Int64 {
    let data = image.data
    if (data.size > limits.maximumOutputBytes) {
        throw LimitExceededException("rich_output_bytes", limits.maximumOutputBytes, data.size, "prepare")
    }
    let signature: Array<Byte> = [137, 80, 78, 71, 13, 10, 26, 10]
    if (data.size < 57) {
        invalidRichProduct()
    }
    for (i in 0..8) {
        if (data[i] != signature[i]) {
            invalidRichProduct()
        }
    }
    if (image.width <= 0 || image.height <= 0 || image.width > limits.maximumImagePixels / image.height) {
        throw LimitExceededException("rich_image_pixels", limits.maximumImagePixels, limits.maximumImagePixels + 1,
            "prepare")
    }
    var cursor: Int64 = 8
    var idat = false
    var ended = false
    while (cursor < data.size) {
        cancellation.throwIfCancelled(phase: "prepare")
        if (data.size - cursor < 12) {
            invalidRichProduct()
        }
        let length = richPngInteger(data, cursor)
        if (length > data.size - cursor - 12) {
            invalidRichProduct()
        }
        let kindStart = cursor + 4
        let kind = String.fromUtf8(Array<Byte>(4, {i => data[kindStart + i]}))
        if (cursor == 8) {
            if (kind != "IHDR" || length != 13 || data[cursor + 16] != 8 || (data[cursor + 17] != 2 &&
                data[cursor + 17] != 6) || data[cursor + 18] != 0 || data[cursor + 19] != 0 || data[cursor + 20] != 0) {
                invalidRichProduct()
            }
        } else if (kind == "IDAT" && !ended && length > 0) {
            idat = true
        } else if (kind == "IEND" && idat && length == 0 && cursor + 12 == data.size) {
            ended = true
        } else {
            // Only RGB/RGBA critical chunks are accepted. The optional adapter
            // removes ancillary metadata before returning the controlled image.
            invalidRichProduct()
        }
        var crc: UInt32 = 0xFFFFFFFF
        budget.consumeScan(steps: (length + 4) * 8)
        for (index in (cursor + 4)..(cursor + 8 + length)) {
            if (index % 1024 == 0) {
                cancellation.throwIfCancelled(phase: "prepare")
            }
            crc ^= UInt32(data[index])
            for (_ in 0..8) {
                crc = if ((crc & 1) != 0) {
                    (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >> 1
                }
            }
        }
        if (Int64(crc ^ 0xFFFFFFFF) != richPngInteger(data, cursor + 8 + length)) {
            invalidRichProduct()
        }
        cursor += length + 12
    }
    if (!ended) {
        invalidRichProduct()
    }
    data.size
}

internal func invalidRichProduct(): Nothing {
    throw MarkdownException(MarkdownErrorCode.RenderFailure, "invalid structured rich content product", phase: "prepare")
}
