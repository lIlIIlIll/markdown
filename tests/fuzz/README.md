# Fuzz regression corpus

Every minimized crash or semantic mismatch is added here with the originating
library/profile version, seed, expected behavior, and fix reference. The
current files are seed corpus entries rather than historical crashes.

The deterministic smoke harness uses seed `20260817` and exercises String,
bytes, chunks, dialect/Syntax compilation, Safe HTML, formatter, rewriter,
artifact validation, and extension dispatch. A failure must be minimized before
the release gate can return to green.
