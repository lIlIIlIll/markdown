#ifndef MARKDOWN_SCANNER_H
#define MARKDOWN_SCANNER_H

#include <stdint.h>

/* Each packed record stores end-with-newline in the high bits, newline width
 * in bits 0..1, and the inline-special flag in bit 2. */
int64_t MD_Markdown_ScanLines(const uint8_t *input, int64_t length,
                              uint64_t *records, int64_t capacity);

#endif
