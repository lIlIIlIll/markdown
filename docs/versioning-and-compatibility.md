# Versioning and compatibility

The package uses SemVer. The dependency and import name is `markdown`; the
repository/product name is `markdown`.

The following are compatibility surfaces: public AST types and fields, NodeId
assignment, byte SourceSpan semantics, versioned profile behavior, rule order,
diagnostic codes, HTML and canonical Markdown output, default security policy,
SPI/DSL versions, fingerprints, and artifact schema. A 1.x release does not
remove a public node or change field meaning. New optional fields may be minor;
new exhaustive node kinds require explicit compatibility review.

`commonMark()` remains `commonmark-0.31.2` and `gfm()` remains
`gfm-modern-v1` throughout 1.x. Specification fixes cite a clause/example, add
a regression, update this changelog, and decide whether a new profile revision
is needed. Public API deletion requires at least one minor deprecation cycle,
except an urgent unsafe API removal accompanied by a security advisory.

Run `python3 scripts/check_public_api.py` in CI. Any intentional additive API
change updates `api/public-api-v1.txt`; deletion or signature/enum changes need
the compatibility review described above.
