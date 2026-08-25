# Historical crash corpus

`2026-08-25-invalid-utf8-gfm.hex` is the minimized retained input identity for
the arbitrary-byte case that exposed invalid UTF-8 slicing in GFM email
autolinks and then the HTML-block ASCII-normalization path. The regression test
decodes this hex input directly and checks Strict/ReplaceInvalid behavior across
whole-buffer and partitioned buffered input. Never replace a crash entry with a
random seed: retain the exact bytes, discovery date, affected profile, and fixed
behavior.
