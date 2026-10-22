package markdown.engine

import markdown.core.CodeLineRange
import std.collection.*

internal class CodeGroupHeader {
    protected let title: String
    protected let ranges: Array<CodeLineRange>
    init(title: String, ranges: Array<CodeLineRange>) {
        this.title = title
        this.ranges = ranges
    }
}

/** Parses only the versioned info suffix, never source Markdown or a command. */
internal class CodeGroupHeaderParser {
    private let text: String
    private let maximumLine: Int64
    private var cursor: Int64 = 0

    init(text: String, maximumLine: Int64) {
        this.text = text
        this.maximumLine = maximumLine
    }

    protected func parse(fallbackTitle: String): ?CodeGroupHeader {
        skipSpace()
        var title = fallbackTitle
        if (text[cursor..].startsWith("title=")) {
            cursor += 6
            if (cursor >= text.size || text[cursor] != b'"') {
                return None
            }
            cursor++
            let out = StringBuilder()
            var run = cursor
            while (cursor < text.size && text[cursor] != b'"') {
                if (text[cursor] < 0x20 || text[cursor] == 0x7F) {
                    return None
                }
                if (text[cursor] == b'\\') {
                    out.append(text[run..cursor])
                    cursor++
                    if (cursor >= text.size || (text[cursor] != b'"' && text[cursor] != b'\\')) {
                        return None
                    }
                    out.append(text[cursor..cursor + 1])
                    cursor++
                    run = cursor
                } else {
                    cursor++
                }
            }
            if (cursor >= text.size) {
                return None
            }
            out.append(text[run..cursor])
            cursor++
            if (out.size > 0) {
                title = out.toString()
            }
            if (cursor < text.size && text[cursor] != b' ' && text[cursor] != b'\t') {
                return None
            }
            skipSpace()
        }
        let ranges = ArrayList<CodeLineRange>()
        if (cursor < text.size && text[cursor] == b'{') {
            cursor++
            while (true) {
                let first = number()
                if (first.isNone()) {
                    return None
                }
                var last = first.getOrThrow()
                if (cursor < text.size && text[cursor] == b'-') {
                    cursor++
                    let end = number()
                    if (end.isNone()) {
                        return None
                    }
                    last = end.getOrThrow()
                }
                if (last < first.getOrThrow() || (!ranges.isEmpty() && first.getOrThrow() <= ranges[ranges
                        .size - 1]
                    .lastLine)) {
                    return None
                }
                ranges.add(CodeLineRange(first.getOrThrow(), last))
                if (cursor >= text.size) {
                    return None
                }
                if (text[cursor] == b'}') {
                    cursor++;
                    break
                }
                if (text[cursor] != b',') {
                    return None
                }
                cursor++
            }
            skipSpace()
        }
        if (cursor != text.size) {
            return None
        }
        Some(CodeGroupHeader(title, ranges.toArray()))
    }

    private func skipSpace(): Unit {
        while (cursor < text.size && (text[cursor] == b' ' || text[cursor] == b'\t')) {
            cursor++
        }
    }

    private func number(): ?Int64 {
        let start = cursor
        var value: Int64 = 0
        while (cursor < text.size && text[cursor] >= b'0' && text[cursor] <= b'9') {
            let digit = Int64(text[cursor] - b'0')
            if (value > maximumLine / 10 || (value == maximumLine / 10 && digit > maximumLine % 10)) {
                return None
            }
            value = value * 10 + digit
            cursor++
        }
        if (cursor == start || value < 1) {
            None
        } else {
            Some(value)
        }
    }
}
