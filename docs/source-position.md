# Source, SourceSpan, and positions

Canonical positions are UTF-8 byte offsets. `SourceSpan` is `[startByte, endByte)`. Lines and byte columns are one-based; LSP-style `Utf16Position` is zero-based. `SourceBuffer` maps in both directions and rejects a UTF-16 position that splits a surrogate pair.

Strict byte input returns `InvalidEncoding`. ReplaceInvalid emits U+FFFD plus `MD1001_INVALID_UTF8_REPLACED` while retaining original-byte spans through a decoded-to-original map. LF, CRLF, CR, BOM, emoji, and combining text do not trigger whole-document normalization.

