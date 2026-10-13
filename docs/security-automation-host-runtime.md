# Security automation host runtime

The supported development and validation baseline is PowerShell 7.6 or newer.
The `security-automation-host@0.1.5` source-only pilot selects `7.6` in the
Functions Flex `functionAppConfig.runtime` and in the Automation runtime
environment used by Automation and Logic App modes. Runbooks bind to
`SecurityPowerShell76`; updating source does not delete a retained older
environment or pause an existing deployed job.

Microsoft documents PowerShell 7.6 as generally available for
[Functions Flex and the other listed hosting plans](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell#powershell-versions).
The worker uses .NET 10. Microsoft also documents 7.6 support for cloud and
hybrid jobs through the [Automation runtime environment experience](https://learn.microsoft.com/en-us/azure/automation/automation-runbook-types#powershell-runbooks).
These product contracts were checked on 13 October 2026. They establish
platform support; startup, job execution and selected-region availability
still need deployment evidence for the exact source and package.

Compiled-template checks verify both runtime selections and the runbook's
environment binding, alongside the existing host role scopes and disabled
schedule conditions. The default `none` mode remains compute-free. No Graph
permission, collector assignment or policy write is introduced by this update.
Immutable consumer adoption and source/package review remain separate from
live Function, Automation, Logic App, identity, report, pause and teardown proof.
Earlier 7.4 source and validation records remain historical evidence; no
compatibility work or test run on that version is part of this update.

## Extraction and isolation boundaries

The host-neutral domain contract is `scripts/Invoke-Solution.ps1 -InputPath
-OutputDirectory`. Each consumer vendors its engine, runtime, host and local
dependencies and remains independently deployable. Function invokes the bundle
runtime; Automation downloads and verifies an approved package before invoking
that runtime; Logic App invokes its own Automation runbook. These adapters do
not introduce a runtime dependency on Reference or a sibling repository.

| Boundary | Source contract and limits |
| --- | --- |
| Deployment and process | Separate deployments own their selected host, storage and identities. An explicitly combined deployment shares one host identity, containers and package. Engines run sequentially in the same PowerShell process; per-solution directories are not a process sandbox or an authorization boundary. |
| Identity and permissions | Processing identities have evidence Reader and reports Contributor; Automation also has package Reader. Function has Owner on its separate host storage account. Logic App has Job Operator on its own Automation account. The optional source publisher and evidence writer remain separate roles. Optional collector requirements come from selected solution features; their union is metadata, not a grant or proof of effective access. Container roles do not isolate engines inside a combined host. |
| State and completion | Domain state, freshness and coverage decisions remain solution-owned. The host downloads an explicit snapshot and declared hash-bound companions into a temporary input root, writes per-solution output directories and publishes a unique report prefix. It supplies no generic domain watermark, acknowledgement or policy state store. A hosted run is complete only with a valid final `completed.json` and every declared artifact hash. |
| Failure | A terminating engine failure stops the combined run before hosted report upload and completion. A later upload failure can leave a partial remote prefix; a prefix without a valid completion marker and all matching hashes must be rejected. Temporary-directory cleanup is not cloud-resource teardown. |
| Teardown | Cleanup belongs to the selected deployment and requires an exact ownership inventory. Conditional ARM omission does not delete retained resources or pause a retained Automation schedule. The initializer rejects an in-place compute-kind change; use a separate azd environment. Direct ARM callers must explicitly pause and verify a retained schedule with `Set-SecuritySchedule.ps1`. Retained jobs, runbooks, containers, packages, reports, role assignments, soft-deleted data and shared resources require separately qualified cleanup; automatic cross-consumer deletion or RBAC rollback is not promised. |

Before tearing down a disposable host, retain the required source, package and
report evidence, verify the subscription and exact owned resource IDs, pause and
verify scheduled processing, and reconcile remaining resources and assignments
after cleanup. A shared deployment requires evidence of every consumer's
ownership and retention needs before removal. These are operational obligations;
this source review does not establish that live pause or teardown has run.

The reviewed four-consumer adoption pins `security-automation-host@0.1.5` to
`1f13ea06085fd1c7309a2b87601fd7dc5688355e` and
`security-automation-runtime@0.1.7` to
`1d126470ec0144820bd89e0eebb588cc183b6fbd`. This closes the extraction-boundary
source review, not component release, hosted activation or live lifecycle
acceptance. Function startup, Automation and Logic App execution, identity
propagation, durable report readback, schedule pause, teardown and endpoint
outcomes still need evidence for the selected deployment and exact package.
