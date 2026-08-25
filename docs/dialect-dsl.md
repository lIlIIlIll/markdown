# Dialect DSL

`MarkdownDialect.define(id, version)` creates a typed builder. Select a base profile, enable versioned manifests, register syntax and renderer rules, then pass the immutable descriptor to `MarkdownEngine.builder().dialect(...)`.

Compilation validates IDs, SPI version, dependencies, conflicts, fixed delimiters/openers, finite lookahead/capture/block limits, renderer coverage, and deterministic priority/registration order. `disable(extensionId)` removes registrations before compilation. The compiled plan uses a canonical SHA-256 fingerprint.

`parserOptions` controls real result-affecting behavior such as extension
dispatch and unclosed-extension diagnostics. `limits` supplies dialect-level
resource limits; an explicit engine-builder limit overrides it. Both are
fingerprinted. Compilation also rejects unsupported profiles, dependency
cycles, minimum-version failures, cross-category duplicate rule IDs,
non-deterministic SPI/processors, and incomplete capability claims.
