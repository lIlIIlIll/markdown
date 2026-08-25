# Safe HTML and URI security

Use `HtmlOptions.safe()` for untrusted input. It escapes text, attributes, and raw HTML; rejects `javascript:`, `vbscript:`, `file:` and unsupported schemes; blocks remote/data images by default; validates class/tag data; disables task checkboxes; and enforces cancellation/output budgets.

`LinkUriPolicy` and `ImageUriPolicy` are separate. Enabling raw pass-through or `TrustedHtml` is explicitly unsafe. GFM tagfilter is compatibility behavior, not a complete sanitizer. A host sanitizer can be composed as a separate adapter.

Report vulnerabilities through the GitHub
[private vulnerability reporting form](https://github.com/lIlIIlIll/markdown/security/advisories/new)
described in `SECURITY.md`; do not disclose suspected vulnerabilities in a
public issue. The repository setting was verified through GitHub's official API
on 2026-08-24.
