# Security policy

## Reporting a vulnerability

Report a suspected vulnerability privately through GitHub's **Report a
vulnerability** flow on the repository Security tab. Do not open a public issue
or include tenant identifiers, tokens, webhook URLs, connection strings, or
deployment output containing secrets in a report. If private reporting is
unavailable, contact the repository owner privately through the GitHub profile
with only the minimum detail needed to establish contact.

## Supported versions

This repository is the trusted authoring source for the current `main` branch
and the latest published component release. Older component tags are supported
on a best-effort basis; security fixes are prioritized for `main` and the next
release. This repository is not a runtime dependency.

## Response targets

The sole maintainer aims to acknowledge a private report within 7 calendar days
and provide an initial triage or next-steps decision within 14 calendar days.
These are targets, not a guarantee of emergency staffing or remediation time.

## Safe disclosure

Keep vulnerability details private until impact has been assessed and a fix,
mitigation, or coordinated disclosure decision is available. Do not publish
credentials, signing keys, tenant-specific values, or sensitive deployment
output in issues, pull requests, examples, or release bundles.

## Trust boundaries

- Consumer repositories deploy only reviewed, vendored files.
- `azd-components.lock.json` is metadata and must never be executed.
- Synchronization refuses to overwrite consumer drift unless the author makes an
  explicit override decision.
- Component manifests may only address files beneath the selected consumer root.
- Validation is read-only by default. Delivery tests require an explicit switch.
- Microsoft and Azure tooling must reuse cached WAM, broker, CLI, or browser
  authentication. Device-code authentication is prohibited.

## Secrets

No reusable component may contain credentials or tenant-specific values. Use
documented `azd` environment variables, managed identities, Key Vault references,
or deployment-time parameters as appropriate for the consuming solution.

Validation report redaction is a defense-in-depth boundary, not permission to
capture arbitrary command output. Checks must emit only reviewed, allowlisted
evidence. The validation engine sanitizes the complete report again immediately
before schema validation and writing it to disk.
