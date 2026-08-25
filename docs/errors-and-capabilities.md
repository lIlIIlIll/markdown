# Errors, diagnostics, and capabilities

Programs branch on `MarkdownErrorCode`, not English text. Typed errors cover encoding/read/cancel/limit/budget/extension/Sink/render/artifact/invariant failures. `LimitExceededException` includes kind, configured and observed values, phase, optional span, and extension.

`engine.capabilities()` reports profiles, extensions, renderers, syntax rules, DSL/SPI/position/serialization versions, and lossless/incremental flags. `engine.explain(source, offset)` reports actual candidates, selected rule, priority, tie-break order, extension, profile, and fingerprint.

