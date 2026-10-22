package markdown.core

import std.unicode.*

protected func decodeEntity(raw: String): String {
    if (!raw.startsWith("&") || !raw.endsWith(";") || raw.size < 3) {
        return raw
    }
    if (raw.startsWith("&#")) {
        let hex = raw.size > 3 && (raw[2] == b'x' || raw[2] == b'X')
        let start: Int64 = if (hex) {
            3
        } else {
            2
        }
        let digitCount = raw.size - 1 - start
        if ((hex && digitCount > 6) || (!hex && digitCount > 7)) {
            return raw
        }
        let value = parseEntityNumber(raw, start, raw.size - 1, if (hex) {
            16
        } else {
            10
        })
        if (value < 0) {
            return raw
        }
        return entityCodePoint(value)
    }
    if (let Some(value) <- lookupHtml5Entity(raw[1..raw.size - 1])) {
        return value
    }
    raw
}

protected func decodeLinkValue(value: String): String {
    if (!value.contains("\\") && !value.contains("&")) {
        return value
    }
    let unescaped = unescapeBackslashes(value)
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < unescaped.size) {
        if (unescaped[index] == b'&') {
            let end = findByte(unescaped, b';', index + 1)
            if (end > index) {
                let raw = unescaped[index..end + 1]
                let decoded = decodeEntity(raw)
                out.append(decoded)
                index = end + 1
                continue
            }
        }
        let next = nextRuneOffset(unescaped, index)
        out.append(unescaped[index..next])
        index = next
    }
    out.toString()
}

private func entityCodePoint(input: Int64): String {
    var value = input
    if (value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
        value = 0xFFFD
    }
    value = windows1252Replacement(value)
    Rune(UInt32(value)).toString()
}

protected func findByte(text: String, byte: Byte, start: Int64): Int64 {
    var index = start
    while (index < text.size) {
        if (text[index] == byte) {
            return index
        }
        index++
    }
    -1
}

protected func isAsciiPunctuation(byte: Byte): Bool {
    (byte >= 33 && byte <= 47) || (byte >= 58 && byte <= 64) || (byte >= 91 && byte <= 96) || (byte >= 123 && byte <= 126)
}

internal func nextRuneOffset(text: String, offset: Int64): Int64 {
    if (offset >= text.size) {
        return text.size
    }
    let first = text[offset]
    let width: Int64 = if ((first & 0b1000_0000) == 0) {
        1
    } else if ((first & 0b1110_0000) == 0b1100_0000) {
        2
    } else if ((first & 0b1111_0000) == 0b1110_0000) {
        3
    } else if ((first & 0b1111_1000) == 0b1111_0000) {
        4
    } else {
        1
    }
    let end = offset + width
    if (end < text.size) {
        end
    } else {
        text.size
    }
}

protected func normalizeFootnoteLabel(label: String): String {
    normalizeReferenceLabel(decodeLinkValue(label))
}

protected func normalizeReferenceLabel(label: String): String {
    let text = trimAscii(label)
    var needsNormalization = false
    var hasNonAscii = false
    var index: Int64 = 0
    while (index < text.size) {
        let byte = text[index]
        if (byte >= 0x80) {
            hasNonAscii = true
            needsNormalization = true
            break
        }
        if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13 || (byte >= b'A' && byte <= b'Z')) {
            needsNormalization = true
            break
        }
        index++
    }
    if (!needsNormalization) {
        return text
    }
    let out = StringBuilder()
    var pendingSpace = false
    index = 0
    while (index < text.size) {
        let byte = text[index]
        if (byte == b' ' || byte == b'\t' || byte == 10 || byte == 13) {
            pendingSpace = true
            index++
        } else {
            if (pendingSpace && index > 0) {
                out.append(" ")
            }
            pendingSpace = false
            if (byte >= b'A' && byte <= b'Z') {
                out.appendFromUtf8([byte + 32])
                index++
            } else {
                if (byte >= 0x80) {
                    hasNonAscii = true
                }
                let next = nextRuneOffset(text, index)
                out.append(text[index..next])
                index = next
            }
        }
    }
    let normalized = out.toString()
    if (hasNonAscii) {
        normalized.toLower().replace("ß", "ss")
    } else {
        normalized
    }
}

private func parseEntityNumber(value: String, start: Int64, end: Int64, radix: Int64): Int64 {
    if (start >= end) {
        return -1
    }
    var result: Int64 = 0
    for (index in start..end) {
        let byte = value[index]
        let digit: Int64 = if (byte >= b'0' && byte <= b'9') {
            Int64(byte - b'0')
        } else if (byte >= b'a' && byte <= b'f') {
            Int64(byte - b'a') + 10
        } else if (byte >= b'A' && byte <= b'F') {
            Int64(byte - b'A') + 10
        } else {
            return -1
        }
        if (digit >= radix) {
            return -1
        }
        if (result > (0x110000 - digit) / radix) {
            return 0x110000
        }
        result = result * radix + digit
    }
    result
}

protected func trimAscii(text: String): String {
    var start: Int64 = 0
    var end = text.size
    while (start < end && (text[start] == b' ' || text[start] == b'\t')) {
        start++
    }
    while (end > start && (text[end - 1] == b' ' || text[end - 1] == b'\t')) {
        end--
    }
    text[start..end]
}

private func unescapeBackslashes(value: String): String {
    let out = StringBuilder()
    var index: Int64 = 0
    while (index < value.size) {
        if (value[index] == b'\\' && index + 1 < value.size && isAsciiPunctuation(value[index + 1])) {
            out.append(value[index + 1..index + 2])
            index += 2
        } else {
            let next = nextRuneOffset(value, index)
            out.append(value[index..next])
            index = next
        }
    }
    out.toString()
}

private func windows1252Replacement(value: Int64): Int64 {
    match (value) {
        case 0x80 => 0x20AC
        case 0x82 => 0x201A
        case 0x83 => 0x0192
        case 0x84 => 0x201E
        case 0x85 => 0x2026
        case 0x86 => 0x2020
        case 0x87 => 0x2021
        case 0x88 => 0x02C6
        case 0x89 => 0x2030
        case 0x8A => 0x0160
        case 0x8B => 0x2039
        case 0x8C => 0x0152
        case 0x8E => 0x017D
        case 0x91 => 0x2018
        case 0x92 => 0x2019
        case 0x93 => 0x201C
        case 0x94 => 0x201D
        case 0x95 => 0x2022
        case 0x96 => 0x2013
        case 0x97 => 0x2014
        case 0x98 => 0x02DC
        case 0x99 => 0x2122
        case 0x9A => 0x0161
        case 0x9B => 0x203A
        case 0x9C => 0x0153
        case 0x9E => 0x017E
        case 0x9F => 0x0178
        case _ => value
    }
}
