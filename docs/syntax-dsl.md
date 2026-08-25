# Syntax DSL

`InlineSyntax.define` declares paired delimiters, child parsing, nesting, maximum delimiter length, maximum lookahead, priority, and conflict group. `BlockSyntax.define` declares a fixed opener prefix, exact closer, Markdown/literal body mode, nesting, capture and block-byte limits, priority, and conflict group.

Inline rules also support single tokens, metadata suffixes, explicit
CommonMark/literal-backslash escaping, Any/CommonMark/word-boundary flanking,
visible-content control, typed payload emitters, and bounded resource cost.
Block rules support paired nested containers, document-start-only blocks,
single-line prefixes, fixed/dynamic local kinds, typed emitters, and resource
cost. Compiled rules expose phase, tie-break, no-backtracking policy, bounds,
nesting and cost metadata.

Block opener text after the prefix is split into a name and parameter string.
`parameter` declares string, integer, boolean, or identifier values and whether
they are required. Quoted values and backslash escapes are decoded once;
unknown, duplicate, missing, unclosed, or mistyped values produce
`MD3003_INVALID_EXTENSION_PARAMETER`. The raw parameter spelling, typed values,
literal body, nested child AST, extension identity, and SourceSpan are retained
in `SyntaxPayload`/`CustomBlock`.

Unknown syntax remains text. A registered but unclosed rule produces
`MD3002_UNCLOSED_EXTENSION`. Arbitrary regex, recursion scripts, and unbounded
backtracking are not accepted. Syntax outside the bounded declaration model can
use `InlineParserSpi`; the compiler rejects unbounded/non-deterministic SPI,
and runtime validates consumed offsets, identity and spans while wrapping
callback failures as `ExtensionFailureException`.
