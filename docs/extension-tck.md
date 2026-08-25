# Extension TCK

`MarkdownExtensionTestKit.verify(engine, sample)` is public and can be called
from a third-party cjpm test package using only the `markdown` dependency. It
checks parse/render availability, source-span validity, deterministic replay,
chunk invariance, and AST invariants. Extension packages must additionally run
negative cases for unclosed/nested syntax, conflicts, limits, cancellation,
formatter fallback, renderer coverage, and deterministic fuzz input.

The engine rejects duplicate IDs, missing dependencies, declared conflicts,
unsupported SPI versions, unbounded delimiters/captures, opener conflicts,
invalid HTML tag/class tokens, and missing required renderer coverage before
parsing. Host-code extensions have all host process permissions; the 1.x SPI is
not a sandbox. `TrustedHtml` is an explicit unsafe construction.
