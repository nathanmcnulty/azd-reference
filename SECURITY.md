# Security policy

Report a suspected vulnerability privately through GitHub Security Advisories
for this repository. Do not include tenant identifiers, tokens, webhook URLs,
connection strings, or deployment output containing secrets in a public issue.

## Trust boundaries

- This repository is a trusted authoring source, not a runtime dependency.
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
