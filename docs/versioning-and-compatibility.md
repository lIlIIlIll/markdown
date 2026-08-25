# Versioning and compatibility

The package uses SemVer. The dependency and import name is `markdown`; the
repository/product name is `markdown`.

Extension manifest semantic versions and dependency minimums use the complete
SemVer grammar: `major.minor.patch`, optional prerelease identifiers, and
optional build metadata. Incomplete versions, numeric leading zeroes, empty or
invalid identifiers, and numeric overflow are rejected when the dialect is
compiled. Dependency precedence follows SemVer: prereleases sort below the
associated release, numeric prerelease identifiers compare numerically, and
build metadata does not affect precedence. Implementation versions remain
opaque build identities and are not ordered as SemVer.

The following are candidate compatibility surfaces for the eventual 1.0 GA:
public AST types and fields, NodeId
assignment, byte SourceSpan semantics, versioned profile behavior, rule order,
diagnostic codes, HTML and canonical Markdown output, default security policy,
SPI/DSL versions, fingerprints, and artifact schema. The current
`0.8.0` is a pre-GA build and does not freeze these surfaces as a stable 1.x contract.
After 1.0 GA, a 1.x release does not
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
