# Safe HTML and URI security

Use `HtmlOptions.safe()` for untrusted input. It escapes text, attributes, and raw HTML; rejects `javascript:`, `vbscript:`, `file:` and unsupported schemes; blocks remote/data images by default; validates class/tag data; disables task checkboxes; and enforces cancellation/output budgets.

`LinkUriPolicy` and `ImageUriPolicy` are separate. Enabling raw pass-through or `TrustedHtml` is explicitly unsafe. GFM tagfilter is compatibility behavior, not a complete sanitizer. A host sanitizer can be composed as a separate adapter.

When data images are explicitly enabled, the renderer compares the complete
media type before the first `;` parameter, case-insensitively. For example,
allowing `image/png` does not also allow `image/pngx`. Under `HtmlPolicy.safe()`,
an external link configured with `target="_blank"` always receives both
`noopener` and `noreferrer` rel tokens; existing tokens are preserved and not
duplicated. Compatibility renderers do not add these Safe-only attributes.

Report vulnerabilities through the GitHub
[private vulnerability reporting form](https://github.com/lIlIIlIll/markdown/security/advisories/new)
described in `SECURITY.md`; do not disclose suspected vulnerabilities in a
public issue. The repository setting was verified through GitHub's official API
on 2026-08-24.
