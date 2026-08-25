# Formatting

`CanonicalMarkdownRenderer` is deterministic and iterative. Options cover newline, list/heading/emphasis/fence markers, minimum fence length, table padding, final newline, width, and paragraph reflow; reflow is off by default. It preserves destinations, code/raw literals, ordered starts, tasks, alignment, and break semantics.

Canonical text punctuation/space is emitted as numeric entities where necessary
to prevent a literal from joining an adjacent Markdown delimiter or becoming
block indentation. Nested ambiguous emphasis may lower to legal inline HTML;
ordinary unambiguous emphasis still honors the configured marker.

`SyntaxTree` is lossless and binds nested block/inline syntax nodes to semantic
NodeIds. Tokens retain whitespace, newlines, markers, delimiters, link parts,
HTML, entities, extensions and invalid input; leading/trailing trivia remains
outside the stable AST. One shared token arena backs range views on nested
syntax nodes, so nested spans do not copy the same token references repeatedly.
`SyntaxToAstMap` builds NodeId and token-owner indexes once; byte-offset token
lookup is binary rather than a full token scan.

`DocumentSnapshot.applyEdits` and
`PreservingFormatter.applyEdits` preserve untouched bytes, validate ranges,
reject overlap, and return changed ranges. `formatRange`, `formatNode`, and
`formatChangedRanges` use an explicit preserve-or-error fallback for extension
nodes. Current snapshot reparsing is intentionally reported as full
(`wasIncremental=false`) unless the documented block-local fast path applies.

The preserving range formatter reads lossless source directly: it normalizes
only targeted heading-marker spacing and leaves markers, blank lines, entity
spelling, fences, code content and untouched extension syntax byte-for-byte
unchanged.
