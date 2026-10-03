# Compare solution permission requirements

The comparison tool reads local tracked metadata and source hashes. It performs
no authentication, tenant reads, role grants, or deployment. The initial
portfolio inventory is partial; missing or changed evidence is visible in the
result and prevents a complete comparison claim.

Run from the reference checkout with PowerShell 7:

```powershell
# Inspect all registered solutions and their recorded default runtime requirements.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ -AsJson

# See what adding AV and Firewall automation would add to the ASR design.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ `
  -BaseSolution azd-defender-asr-rules `
  -AdditionalSolution azd-defender-av-exclusions,azd-defender-firewall -AsJson

# Inspect the optional Intune publisher permissions alongside default collection.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ `
  -BaseSolution azd-defender-asr-rules `
  -AdditionalSolution azd-defender-av-exclusions `
  -Feature azd-defender-asr-rules:policy-publisher,azd-defender-av-exclusions:policy-publisher -AsJson

# Deployment scopes are a separate comparison.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ `
  -BaseSolution azd-pim -AdditionalSolution azd-risk-based-ca -Phase deployment -AsJson
```

`shared` means both selected sets record the same requirement. `added` means the
additional solutions introduce that exact requirement. `existing` means only the
base set needs it. The `uses` array retains each logical principal, feature,
phase, and evidence state. Partial coverage, unavailable manifests, and changed
source files remain in `inventory`; `comparisonComplete` is false when any
selected inventory has gaps or findings. Always examine those fields before
using the permission list to assess a combined host.

These are requirements, not the permissions currently assigned to any identity.
The tool does not conclude that consent can be reused, that a write permission
implies a read permission, or that sharing permissions makes sharing a host safe.

To add a solution, author its manifest and register its portfolio-relative path.
Validate the schema and reconcile declared roles against project configuration.
Keep the solution usable without access to this repository or tooling. See the
[tracking standard](../standards/permission-requirements.md).
