#include "markdown_scanner.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > (size_t)INT64_MAX - 1u) {
        return 0;
    }
    const int64_t capacity = (int64_t)size + 1;
    uint64_t *records = (uint64_t *)calloc((size_t)capacity, sizeof(uint64_t));
    if (records == NULL) {
        return 0;
    }
    const int64_t count = MD_Markdown_ScanLines(data, (int64_t)size, records, capacity);
    if (count <= 0 || count > capacity) {
        abort();
    }
    uint64_t previous_end = 0;
    for (int64_t index = 0; index < count; ++index) {
        const uint64_t packed = records[index];
        const uint64_t end = packed >> 6;
        const uint64_t newline_width = packed & 3u;
        if (end < previous_end || end > size || newline_width > 2u ||
            (newline_width != 0u && newline_width != 1u && newline_width != 2u)) {
            abort();
        }
        previous_end = end;
    }
    if ((records[count - 1] >> 6) != size) {
        abort();
    }
    free(records);
    return 0;
}
