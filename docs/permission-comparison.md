# Compare solution permission requirements

The comparison tool reads registered local metadata files and source hashes. It performs
no authentication, tenant reads, role grants, or deployment. The initial
portfolio inventory is partial; missing or changed evidence is visible in the
result and prevents a complete comparison claim.

Saved JSON records the selected phases, base/additional solutions, enabled and
excluded features, and optional-union switch. Paths must be ordinary portable
relative paths; colon-bearing paths, including NTFS alternate data streams, are
rejected. Registration and byte hashes do not establish Git tracking or current
tenant grants.

Run from the reference checkout with PowerShell 7:

```powershell
# Inspect all registered solutions and their recorded default runtime requirements.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ -AsJson

# See what adding AV and Firewall automation would add to the ASR design.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ `
  -BaseSolution azd-defender-asr-rules `
  -AdditionalSolution azd-defender-av-exclusions,azd-defender-firewall -AsJson

# Inspect optional host deployment and package publication authority separately.
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:\ `
  -BaseSolution azd-defender-asr-rules `
  -AdditionalSolution azd-defender-av-exclusions `
  -Phase deployment -Feature azd-defender-asr-rules:azure-host-deployment,azd-defender-av-exclusions:source-publication -AsJson

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

## Staged security host and collector alternatives

The four newer staged Defender/App Control for Business snapshot runners default to no cloud access.
Their solution-owned immutable vendor locks retain the host/runtime candidates from the preserved Reference branch. This metadata reconciliation does not register or release those components in Reference main, qualify shared-host isolation, or authorize a deployment.

Explicit optional features select `function-host`, `automation-host`, or
`logic-app-host`. Deployment features `azure-host-deployment` and
`source-publication` belong to the deployment operator and publisher, respectively;
they must not be folded into the runtime identity.

ASR and AV read transport supports application and delegated alternatives. Select
features ending in `-application` for managed identity or an application token,
and `-delegated` for a signed-in Azure CLI user with delegated consent. These are
alternatives; `-IncludeOptional` is an inventory union, not a grant recommendation.

```powershell
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot E:/ `
  -BaseSolution azd-defender-asr-rules -AdditionalSolution azd-defender-av-exclusions `
  -Phase runtime,discovery `
  -Feature azd-defender-asr-rules:function-host,azd-defender-av-exclusions:function-host,azd-defender-asr-rules:intune-contract-discovery-application,azd-defender-asr-rules:mde-collection-application,azd-defender-av-exclusions:intune-contract-discovery-application
```

Logical host scopes match only when engines really use the same deployed host.
Resource IDs differ for separate deployments, so a matching logical tuple alone
cannot justify reusing a live Azure assignment across resource groups.
