# Security automation runtime (pilot)

This component runs a vendored PowerShell domain engine against an explicit JSON
evidence snapshot. Local, Function, Automation and Logic App orchestration use
the same CLI contract: `scripts/Invoke-Solution.ps1 -InputPath -OutputDirectory`.
The runtime emits review artifacts. It has no policy publisher or enforcement
API. Engine-specific evidence freshness and coverage checks remain in the engine.

## Deployment

Vendor both `security-automation-runtime` and `security-automation-host` at an
immutable reference revision. A solution's main Bicep selects `none` (default),
`function`, `automation` or `logic-app`. No Graph grants are provisioned. Containers
are private, storage shared keys are disabled, and hosted access uses managed
identity. This initial implementation supports Azure public cloud only.

Build an immutable package with `Build-SecurityBundle.ps1 -SolutionRoot <paths>
-OutputPath <new.zip>`. Multiple roots produce a combined host package; each
engine and its local dependencies are copied into the package. No sibling repo
or private reference repository is contacted at runtime. The package contains
a SHA256 file inventory. The Automation runbook verifies the full ZIP SHA256
before extraction. Rollback means redeploying a retained approved ZIP/hash.

`Publish-SecurityHost.ps1` uploads the package using cached Azure CLI credentials
and publishes Function source or an Automation runbook. It supports `-WhatIf`.
Publishing does not enable scheduling or grant permissions. Upload each explicit
snapshot as `<solution-id>.json` to the evidence container; hosted runs place
artifacts in a unique run directory in reports. Evidence writers can influence
the review result and must be trusted administrators. Use retention controls for
endpoint names, paths and identifiers; no input or token values are logged by
the transport.

For Automation and Logic App modes, redeploy `bundleBlob` and `bundleSha256`
using publication output. Set a future `automationScheduleStartTime` for the
Automation schedule. Only then enable scheduling. Logic App mode is an independent
deployment which invokes its own PowerShell runbook every six hours; it adds
Automation Job Operator for its identity at the Automation account scope. It does
not attempt to execute PowerShell inside a Consumption Logic App action.

## Permission boundary

Local engines require no cloud credentials. The snapshot runtime itself requires
storage access, not Graph permissions. Optional read collectors use Graph permissions
listed in each solution's permission manifest. Combined collectors need the exact
union of selected features; this does not imply all engines should share a broadly
privileged publishing identity. Separate discovery and approved publishing identities.

Function timer hosts use Storage Blob Data Owner on their storage account for host
coordination and deployment. Automation uses Storage Blob Data Contributor for
approved package/evidence reads and report writes. Deployment requires Azure resource
write and scoped role-assignment permissions; source upload additionally requires
Blob Data Contributor. Container-level separation is a future hardening option.

## Verification limits

Offline tests and Bicep compilation do not establish Function startup, Automation
7.4 runtime binding, Logic App job delivery, Graph consent, endpoint acceptance or
policy enforcement. Those remain tenant pilot gates. See Microsoft's
[PowerShell Functions guidance](https://learn.microsoft.com/azure/azure-functions/functions-reference-powershell),
[timer storage permissions](https://learn.microsoft.com/azure/azure-functions/functions-bindings-timer),
and [Automation managed identity guidance](https://learn.microsoft.com/azure/automation/enable-managed-identity-for-automation).

Automation schedules are created only when scheduleEnabled is true. To pause an
existing Automation schedule, use Set-SecuritySchedule.ps1 -Enabled:$false.
Incremental ARM deployment with scheduleEnabled=false does not remove a schedule
that was created earlier. Logic App and Function schedules have explicit disabled
settings and can be paused by redeploying with scheduleEnabled=false.
