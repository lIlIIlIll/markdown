package markdown.core

import std.unicode.*

/** 解码带分号的 HTML 命名或数值字符引用；未知或不合法拼写保持原样。
 * @param raw 包括 & 和 ; 的候选字符引用。
 * @return 解码结果；非法 Unicode 数值依 CommonMark 映射为替代字符，非引用文本原样返回。
 */
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

/** 依次处理链接目标或标题中的反斜线转义和带分号字符引用。
 * @param value 尚未执行 Markdown 转义处理的链接文本。
 * @return 用于链接语义的文本；不执行 URI 安全判断或百分号解码。
 */
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

/** 从指定字节下标向后查找第一个匹配字节。
 * @param text 要搜索的 UTF-8 文本。
 * @param byte 需要匹配的字节值。
 * @param start 开始搜索的零基字节下标，调用方须保证非负。
 * @return 首个匹配的零基字节下标；未找到时为 -1。
 */
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

/** 判断字节是否属于 Markdown 可被反斜线转义的 ASCII 标点范围。
 * @param byte 要判断的原始字节。
 * @return 字节落在 ASCII 标点范围时为 true。
 */
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

/** 先解码 Markdown 转义，再按引用 label 规则统一脚注身份。
 * @param label 脚注定义或引用中不含括号的原始 label。
 * @return 用于脚注定义查找的规范化 label。
 */
protected func normalizeFootnoteLabel(label: String): String {
    normalizeReferenceLabel(decodeLinkValue(label))
}

/** 裁剪首尾空格和 tab、折叠内部 ASCII 空白并统一大小写。
 * @param label 引用定义或引用使用的 label 文本。
 * @return 匹配用的 label；非 ASCII 使用小写转换，并将 ß 归一化为 ss。
 */
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

/** 仅移除文本两端的 ASCII 空格和 tab。
 * @param text 待裁剪的文本；换行和其他 Unicode 空白保持原样。
 * @return 移除首尾空格和 tab 后的文本。
 */
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
