#include "markdown_scanner.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

static void scan(const uint8_t *data, int64_t size) {
    const int64_t capacity = size + 1;
    uint64_t *records = (uint64_t *)calloc((size_t)capacity, sizeof(uint64_t));
    if (records == NULL) {
        abort();
    }
    const int64_t count = MD_Markdown_ScanLines(data, size, records, capacity);
    if (count <= 0 || count > capacity || (records[count - 1] >> 6) != (uint64_t)size) {
        abort();
    }
    free(records);
}

static void verify_classification(void) {
    static const uint8_t input[] = "a*b\n[x]\na&amp;b\n`code`\nplain";
    uint64_t records[5] = {0, 0, 0, 0, 0};
    const int64_t count = MD_Markdown_ScanLines(
        input, (int64_t)sizeof(input) - 1, records, 5);
    if (count != 5 ||
        (records[0] & 0x4u) == 0u || (records[0] & 0x8u) == 0u || (records[0] & 0x10u) != 0u ||
        (records[0] & 0x20u) != 0u || (records[1] & 0x4u) == 0u || (records[1] & 0x8u) != 0u ||
        (records[1] & 0x10u) != 0u || (records[1] & 0x20u) == 0u ||
        (records[2] & 0x4u) == 0u || (records[2] & 0x8u) != 0u || (records[2] & 0x10u) == 0u ||
        (records[2] & 0x20u) != 0u || (records[3] & 0x4u) == 0u || (records[3] & 0x8u) != 0u ||
        (records[3] & 0x10u) == 0u || (records[3] & 0x20u) != 0u ||
        (records[4] & 0x4u) != 0u || (records[4] & 0x8u) != 0u || (records[4] & 0x10u) != 0u ||
        (records[4] & 0x20u) != 0u) {
        abort();
    }
}

int main(void) {
    static const uint8_t empty[] = {0};
    static const uint8_t dense_newlines[] = "\n\r\r\n\n\r";
    static const uint8_t bom[] = {0xEF, 0xBB, 0xBF, '*', 'x', '\r', '\n'};
    static const uint8_t arbitrary[] = {0x00, 0xFF, 0x80, '\r', 'x', '\n', 0xC0};
    scan(empty, 0);
    scan(dense_newlines, (int64_t)sizeof(dense_newlines) - 1);
    scan(bom, (int64_t)sizeof(bom));
    scan(arbitrary, (int64_t)sizeof(arbitrary));
    verify_classification();
    if (MD_Markdown_ScanLines(NULL, 1, NULL, 0) != -1 ||
        MD_Markdown_ScanLines(empty, -1, NULL, 0) != -1 ||
        MD_Markdown_ScanLines(empty, 0, NULL, 0) != -2) {
        abort();
    }
    return 0;
}
