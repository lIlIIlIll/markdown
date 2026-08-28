#ifndef MARKDOWN_SCANNER_H
#define MARKDOWN_SCANNER_H

#include <stdint.h>

/* Version 4 packed records store end-with-newline above six low bits,
 * newline width in bits 0..1, inline-special in bit 2, delimiter in bit 3,
 * escape/entity/code text-lowering candidates in bit 4, and the presence of
 * an opening bracket in bit 5. */
int64_t MD_Markdown_ScanLines(const uint8_t *input, int64_t length,
                              uint64_t *records, int64_t capacity);

#endif
