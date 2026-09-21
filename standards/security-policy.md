# SECURITY.md standard

Every independently supported `azd` repository has a root `SECURITY.md`.
The file is part of the repository baseline, and public repositories use the
same minimum content even when their deployment or component details differ.

The machine-readable migration contract is
[`portfolio/release-integrity.json`](../portfolio/release-integrity.json).
The portable starter is [`skeleton/SECURITY.md`](../skeleton/SECURITY.md).

## Required sections

Use these headings so a maintainer and a security researcher can find the
same information in every repository:

- `## Reporting a vulnerability`
- `## Supported versions`
- `## Response targets`
- `## Safe disclosure`

The prose may be repository-specific, but it must preserve these boundaries:

- Vulnerabilities are reported through GitHub's private vulnerability
  reporting or Security Advisories path. Do not request secrets, tokens, tenant
  identifiers, callback URLs, or deployment output in a public issue.
- The supported-version table is honest about whether `main`, the latest
  release, older releases, or an incubation state receive security fixes.
- Response times are targets, not a promise of emergency staffing. State an
  acknowledgement target and a triage or next-steps target.
- Public disclosure waits until the maintainer has assessed impact and either
  shipped a fix, documented a mitigation, or coordinated an appropriate
  disclosure decision.

Do not put credentials, signing keys, private email addresses, or tenant-specific
configuration in `SECURITY.md`. A public contact path is enough; sensitive
details belong in the private report.

## Single-maintainer posture

The repository owner remains the sole maintainer and security decision maker.
The policy must not imply a staffed security team or guaranteed response
window. Pull requests, issues, and release workflows are still subject to the
repository's rulesets and release-integrity checks.
