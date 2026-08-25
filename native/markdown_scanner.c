#include "markdown_scanner.h"

static int has_core_inline_special(uint8_t value) {
    return value == '\\' || value == '&' || value == '`' || value == '~' || value == '*'
        || value == '_' || value == '!' || value == '[' || value == '<';
}

static int64_t first_content_offset(const uint8_t *input, int64_t length) {
    if (length >= 3 && input[0] == 0xEF && input[1] == 0xBB && input[2] == 0xBF) {
        return 3;
    }
    return 0;
}

int64_t MD_Markdown_ScanLines(const uint8_t *input, int64_t length,
                              uint64_t *records, int64_t capacity) {
    if (length < 0 || length > (INT64_MAX >> 3) || capacity < 0 ||
        (length > 0 && input == 0) || (capacity > 0 && records == 0)) {
        return -1;
    }

    const int64_t first = first_content_offset(input, length);
    int64_t index = first;
    int64_t has_special = 0;
    int64_t line = 0;
    while (index < length) {
        const uint8_t value = input[index];
        if (has_core_inline_special(value)) {
            has_special = 1;
        }
        if (value == '\n' || value == '\r') {
            if (line >= capacity) {
                return -2;
            }
            int64_t newlineWidth = 1;
            if (value == '\r' && index + 1 < length && input[index + 1] == '\n') {
                newlineWidth = 2;
                ++index;
            }
            const uint64_t endWithNewline = (uint64_t)(index + 1);
            records[line] = (endWithNewline << 3) | (uint64_t)newlineWidth |
                (has_special != 0 ? 4u : 0u);
            ++line;
            has_special = 0;
        }
        ++index;
    }

    if (line >= capacity) {
        return -2;
    }
    records[line] = ((uint64_t)length << 3) | (has_special != 0 ? 4u : 0u);
    return line + 1;
}
