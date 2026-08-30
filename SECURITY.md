# Security policy

## Supported versions

`markdown` is a preview release. Security fixes are made on the latest 0.9.x
release and on `main`; older preview lines do not receive backports.

| Version | Security support |
| --- | --- |
| 0.9.x | Supported |
| 0.8.x and earlier | Not supported |
| Unreleased `main` | Best-effort validation; not a released support target |

Upgrade to the latest supported patch before reporting a problem that affects
an older preview version.

## Report a vulnerability

Please report suspected vulnerabilities through the repository's
[private vulnerability reporting form](https://github.com/lIlIIlIll/markdown/security/advisories/new)
rather than opening a public issue. Include the affected version/profile,
minimal input, configuration, observed resource use or output, and reproduction
steps.

If the GitHub form is unavailable, email `chenqian169@huawei.com` with the
subject `markdown security report`. Send only contact details and a brief
impact summary in the first message. Wait for agreement on a private channel
before sending exploit details or sensitive attachments.

Maintainers will acknowledge, reproduce against supported releases, identify affected versions, prepare a minimized regression corpus and compatibility assessment, coordinate an advisory and patched release, and publish migration guidance. High-risk unsafe APIs may be removed before the normal deprecation window when accompanied by an advisory.

GitHub Private Vulnerability Reporting is enabled for this repository. Reports
remain private to repository maintainers until an advisory is published.

## Response targets

These targets start when a report reaches either private channel. They are
service objectives, not guarantees.

| Stage | Target |
| --- | --- |
| Acknowledge receipt | 2 business days |
| Initial severity and affected-version assessment | 5 business days |
| Critical or high-risk mitigation plan | 7 calendar days |
| Status update while unresolved | Every 7 calendar days |

The fix date depends on complexity, downstream coordination, and disclosure
risk. Maintainers will tell the reporter the planned disclosure date and any
change to it.

## Advisories, CVEs, and backports

Maintainers use a GitHub Security Advisory for confirmed vulnerabilities that
affect a supported release. They request a CVE when the issue meets GitHub's
CVE eligibility rules and a CVE improves downstream coordination. The
advisory identifies affected versions, fixed versions, mitigations, and credit
agreed with the reporter.

Security fixes target the latest supported 0.9.x patch. A change is backported
only when another version is explicitly listed as supported above. Unsafe API
removal may bypass the normal compatibility window when keeping the API would
leave users exposed; the advisory and migration notes must explain that break.
