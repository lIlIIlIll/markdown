# Document-system and P2 contracts

`DocumentGraph.build` accepts only host-supplied `(id, source)` values. It never
reads files or accesses the network. It parses snapshots, records cross-document
link edges, and resolves versioned reference definitions deterministically in
input order.

`HtmlToMarkdownConverter` requires explicit input and fidelity policies. The
safe default rejects script/style/event handlers and dangerous URIs. Trusted
input can request preservation of unknown tags. Supported semantic tags lower
to headings, paragraphs, emphasis, strong, code, deletion, links, quotes,
lists, breaks, and thematic breaks.

`BinaryArtifactCodec` implements `markdown-snapshot-binary-1`. Length-prefixed
UTF-8 fields bind profile, dialect/engine fingerprints, source digest, AST
digest, CST digest, and source. Decode is size-bounded and fail-closed: any
schema, identity, digest, invariant, truncation, UTF-8, or trailing-byte issue
is a cache miss. Reconstruction reparses the validated source rather than
guessing around corrupt node bytes.

`VirtualSyntaxTree` exposes bounded byte pages containing intersecting tokens
and NodeIds. Page ranges remain original UTF-8 offsets and accept cancellation
and budgets. It is a virtualized view over a snapshot, not an assertion that
the underlying semantic document was only partially parsed.

`DocumentSnapshot.applyEdits` has a genuine block-local incremental path for a
single equal-byte-length plain-text edit inside one paragraph/heading when no
reference or extension dependencies exist. It reparses only that block,
rebases changed nodes, reuses unaffected NodeIds, and reports incremental
diagnostic/source-map ranges. Structural, newline, reference, extension, or
size-changing edits explicitly fall back to full parsing. `StableNodeId` is a
content/path identity separate from 1.x document-local `NodeId`.
Capability discovery reports this scope as `block-local-with-full-fallback`; it does not
claim a general incremental parser, incremental dependency graph, or reduced
peak memory for unsupported edits.
