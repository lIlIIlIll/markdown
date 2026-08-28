#include "markdown_scanner.h"

#if defined(__SSE2__) || defined(_M_X64)
#include <emmintrin.h>
#define MARKDOWN_SCANNER_SSE2 1
#else
#define MARKDOWN_SCANNER_SSE2 0
#endif

#if defined(__x86_64__) && (defined(__clang__) || defined(__GNUC__))
#include <immintrin.h>
#define MARKDOWN_SCANNER_AVX2_DISPATCH 1
#else
#define MARKDOWN_SCANNER_AVX2_DISPATCH 0
#endif

static int has_core_inline_special(uint8_t value) {
    /*
     * The scanner executes this test for every input byte. Keep the semantic
     * set in two cache-resident bit masks instead of a nine-comparison chain.
     * Bytes >= 128 are never ASCII Markdown delimiters.
     */
    static const uint64_t special[2] = {
        (UINT64_C(1) << 33) | (UINT64_C(1) << 38) | (UINT64_C(1) << 42) |
            (UINT64_C(1) << 60),
        (UINT64_C(1) << (91 - 64)) | (UINT64_C(1) << (92 - 64)) |
            (UINT64_C(1) << (95 - 64)) | (UINT64_C(1) << (96 - 64)) |
            (UINT64_C(1) << (126 - 64))
    };
    return value < 128 && ((special[value >> 6] >> (value & 63)) & UINT64_C(1)) != 0;
}

static int64_t first_content_offset(const uint8_t *input, int64_t length) {
    if (length >= 3 && input[0] == 0xEF && input[1] == 0xBB && input[2] == 0xBF) {
        return 3;
    }
    return 0;
}

#if MARKDOWN_SCANNER_SSE2
static inline int scan_ascii_chunk(const uint8_t *input, int64_t *has_special,
                                   int64_t *has_delimiter,
                                   int64_t *has_text_lowering,
                                   int64_t *has_reference_opener) {
    const __m128i bytes = _mm_loadu_si128((const __m128i *)input);
    const __m128i newlines = _mm_or_si128(
        _mm_cmpeq_epi8(bytes, _mm_set1_epi8('\n')),
        _mm_cmpeq_epi8(bytes, _mm_set1_epi8('\r')));
    if (_mm_movemask_epi8(newlines) != 0) {
        return 0;
    }
    __m128i specials = _mm_cmpeq_epi8(bytes, _mm_set1_epi8('\\'));
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('&')));
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('`')));
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('~')));
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('*')));
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('_')));
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('!')));
    const __m128i reference_openers = _mm_cmpeq_epi8(bytes, _mm_set1_epi8('['));
    specials = _mm_or_si128(specials, reference_openers);
    specials = _mm_or_si128(specials, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('<')));
    *has_special |= _mm_movemask_epi8(specials) != 0;
    __m128i text_lowering = _mm_cmpeq_epi8(bytes, _mm_set1_epi8('\\'));
    text_lowering = _mm_or_si128(
        text_lowering, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('&')));
    text_lowering = _mm_or_si128(
        text_lowering, _mm_cmpeq_epi8(bytes, _mm_set1_epi8('`')));
    *has_text_lowering |= _mm_movemask_epi8(text_lowering) != 0;
    const __m128i delimiters = _mm_or_si128(
        _mm_cmpeq_epi8(bytes, _mm_set1_epi8('*')),
        _mm_cmpeq_epi8(bytes, _mm_set1_epi8('_')));
    *has_delimiter |= _mm_movemask_epi8(delimiters) != 0;
    *has_reference_opener |= _mm_movemask_epi8(reference_openers) != 0;
    return 1;
}
#endif

#if MARKDOWN_SCANNER_AVX2_DISPATCH
__attribute__((target("avx2"))) static int scan_ascii_chunk_avx2(
    const uint8_t *input, int64_t *has_special, int64_t *has_delimiter,
    int64_t *has_text_lowering, int64_t *has_reference_opener) {
    const __m256i bytes = _mm256_loadu_si256((const __m256i *)input);
    const __m256i newlines = _mm256_or_si256(
        _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('\n')),
        _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('\r')));
    if (_mm256_movemask_epi8(newlines) != 0) {
        return 0;
    }
    __m256i specials = _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('\\'));
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('&')));
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('`')));
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('~')));
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('*')));
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('_')));
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('!')));
    const __m256i reference_openers = _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('['));
    specials = _mm256_or_si256(specials, reference_openers);
    specials = _mm256_or_si256(
        specials, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('<')));
    *has_special |= _mm256_movemask_epi8(specials) != 0;
    __m256i text_lowering = _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('\\'));
    text_lowering = _mm256_or_si256(
        text_lowering, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('&')));
    text_lowering = _mm256_or_si256(
        text_lowering, _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('`')));
    *has_text_lowering |= _mm256_movemask_epi8(text_lowering) != 0;
    const __m256i delimiters = _mm256_or_si256(
        _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('*')),
        _mm256_cmpeq_epi8(bytes, _mm256_set1_epi8('_')));
    *has_delimiter |= _mm256_movemask_epi8(delimiters) != 0;
    *has_reference_opener |= _mm256_movemask_epi8(reference_openers) != 0;
    return 1;
}

__attribute__((target("avx2"))) static int64_t scan_lines_avx2(
    const uint8_t *input, int64_t length, uint64_t *records,
    int64_t capacity, int64_t first) {
    int64_t index = first;
    int64_t has_special = 0;
    int64_t has_delimiter = 0;
    int64_t has_text_lowering = 0;
    int64_t has_reference_opener = 0;
    int64_t line = 0;
    while (index < length) {
        while (index + 32 <= length &&
               scan_ascii_chunk_avx2(input + index, &has_special,
                                     &has_delimiter, &has_text_lowering,
                                     &has_reference_opener)) {
            index += 32;
        }
        if (index >= length) {
            break;
        }
        const uint8_t value = input[index];
        has_special |= has_core_inline_special(value);
        has_delimiter |= value == '*' || value == '_';
        has_text_lowering |= value == '\\' || value == '&' || value == '`';
        has_reference_opener |= value == '[';
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
            records[line] = (endWithNewline << 6) | (uint64_t)newlineWidth |
                (has_special != 0 ? 4u : 0u) |
                (has_delimiter != 0 ? 8u : 0u) |
                (has_text_lowering != 0 ? 16u : 0u) |
                (has_reference_opener != 0 ? 32u : 0u);
            ++line;
            has_special = 0;
            has_delimiter = 0;
            has_text_lowering = 0;
            has_reference_opener = 0;
        }
        ++index;
    }
    if (line >= capacity) {
        return -2;
    }
    records[line] = ((uint64_t)length << 6) |
        (has_special != 0 ? 4u : 0u) |
        (has_delimiter != 0 ? 8u : 0u) |
        (has_text_lowering != 0 ? 16u : 0u) |
        (has_reference_opener != 0 ? 32u : 0u);
    return line + 1;
}
#endif

int64_t MD_Markdown_ScanLines(const uint8_t *input, int64_t length,
                              uint64_t *records, int64_t capacity) {
    if (length < 0 || length > (INT64_MAX >> 6) || capacity < 0 ||
        (length > 0 && input == 0) || (capacity > 0 && records == 0)) {
        return -1;
    }

    const int64_t first = first_content_offset(input, length);
#if MARKDOWN_SCANNER_AVX2_DISPATCH
    if (first < length && input[first] != '|' && __builtin_cpu_supports("avx2")) {
        return scan_lines_avx2(input, length, records, capacity, first);
    }
#endif
    int64_t index = first;
    int64_t has_special = 0;
    int64_t has_delimiter = 0;
    int64_t has_text_lowering = 0;
    int64_t has_reference_opener = 0;
    int64_t line = 0;
    while (index < length) {
#if MARKDOWN_SCANNER_SSE2
        while (index + 16 <= length &&
               scan_ascii_chunk(input + index, &has_special, &has_delimiter,
                                &has_text_lowering, &has_reference_opener)) {
            index += 16;
        }
        if (index >= length) {
            break;
        }
#endif
        const uint8_t value = input[index];
        has_special |= has_core_inline_special(value);
        has_delimiter |= value == '*' || value == '_';
        has_text_lowering |= value == '\\' || value == '&' || value == '`';
        has_reference_opener |= value == '[';
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
            records[line] = (endWithNewline << 6) | (uint64_t)newlineWidth |
                (has_special != 0 ? 4u : 0u) |
                (has_delimiter != 0 ? 8u : 0u) |
                (has_text_lowering != 0 ? 16u : 0u) |
                (has_reference_opener != 0 ? 32u : 0u);
            ++line;
            has_special = 0;
            has_delimiter = 0;
            has_text_lowering = 0;
            has_reference_opener = 0;
        }
        ++index;
    }

    if (line >= capacity) {
        return -2;
    }
    records[line] = ((uint64_t)length << 6) |
        (has_special != 0 ? 4u : 0u) |
        (has_delimiter != 0 ? 8u : 0u) |
        (has_text_lowering != 0 ? 16u : 0u) |
        (has_reference_opener != 0 ? 32u : 0u);
    return line + 1;
}
