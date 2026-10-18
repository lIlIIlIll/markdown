# Optional rich runtime

The owned worker supports pinned KaTeX MathML, Shiki byte-range tokens and strict
Mermaid flowcharts rendered to PNG. It is an explicit Linux x86_64 adapter for
`markdown.node`, with no downloads or command selection from Markdown input.

Use the [maintained installation and API guide](../../docs/node-rich-backend.md).
Run `scripts/prepare_rich_runtime.py` explicitly; its default is offline.
The lock uses the official npm registry and installation scripts stay disabled.

The generated runtime retains vendor notices, npm licenses and the fixed Noto
font license in `THIRD_PARTY_NOTICES.md`, `licenses/` and the original packages.
The manifest binds the complete runtime closure; host paths are not serialized.
The supervisor is a bounded process mechanism, not an OS sandbox.
