# Exchange component reuse and compatibility review

The Exchange pilot uses the portfolio's current contracts. Do not add a second
catalog or turn descriptive metadata into deployment authority.

| Concern | Existing authoring source | Exchange use |
| --- | --- | --- |
| Human discovery | Solution `.azd/catalog.json` and `catalog-metadata.schema.json` | Concise supported outcome/commands only; no grants or host adoption. |
| GUI configuration | `azd-gui.json` and the GUI contract | Host choice and optional Foundry values remain solution-owned. |
| Declared permissions | `azd-permissions.json`, `portfolio/permission-solutions.json`, `Get-AzdPermissionComparison.ps1` | Compare exact resource/kind/permission/scope tuples and selected features. |
| Component adoption | `component.json`, `portfolio/consumers.json`, `azd-components.lock.json` | Source-only pilots, full immutable revision and byte hashes; deployment uses only vendored files. |
| Lifecycle evidence | Deployment receipt/validation components | Distinguish infrastructure, permissions, collection, decision storage and actual mail flow. |

## Host seam

`security-automation-host@0.2.0` preserves `none` as its generic default and all
0.1.5 behavior when the new parameters are omitted. The Exchange wrapper selects
Automation as its own default. Function and Logic App remain explicit alternate
hosts; Logic App is an orchestrator of the native PowerShell Automation runbook,
not a native Exchange execution environment.

Optional runbook/runtime/schedule names, hourly interval and job parameters let
a solution publish its own worker without modifying a vendored file or creating
an unused snapshot worker. Function receives solution-owned app settings while
retaining the `SecurityReview` timer and host-owned pause/storage settings. Every
Function consumer must retain that exact entrypoint name; a different name is
not protected by `AzureWebJobs.SecurityReview.Disabled` and is unsupported. Job
parameter filtering is case-insensitive for the three reserved package keys.
Namespaced objects avoid accidental name collisions but do not isolate identity,
process, permission or data access. Default roles and package hash gates are
unchanged. Blob versioning is optional for domain-state recovery and does not
make evidence tamper-proof. The solution wrapper owns additional state containers
and their exact container-scoped role assignments.

The existing snapshot runtime remains unchanged and is not a cloud collector.
An Exchange worker owns trace windows, paging, validation, managed-identity EXO
connection, evidence normalization and durable writes. The consumer owns package
publication/readback, pinned modules, schedule enablement/pause and lifecycle
proof for each selected host. Changing a resource name does not pause or delete
an old runbook/schedule. In incremental ARM mode, omitting a schedule when disabled
does not disable the retained schedule. The wrapper must explicitly pause its
owned schedule/job bindings and read them back. `scheduledProcessingEnabled` is
desired template configuration, not evidence of the live scheduler state. The runtime scripts for the snapshot host still assume
their historical names: a custom-name consumer needs its own wrappers.

## Discover candidates before sharing

The existing registry already includes advanced auditing. Register the staged
Exchange permission manifest there and use the current comparison command:

```powershell
./tooling/Get-AzdPermissionComparison.ps1 -PortfolioRoot C:\GitHub `
  -BaseSolution azd-advanced-auditing `
  -AdditionalSolution azd-exchange-allow-list -Phase runtime -AsJson
```

Supply explicit `-Feature solution-id:feature-id` selections for the chosen
host and source. Do not use `-IncludeOptional` as a recommended grant set.
Missing manifests, partial coverage or stale evidence hashes prevent a complete
comparison. Read `inventory`, `comparisonComplete`, and every `uses` entry.
No command above authenticates, reads a tenant, grants a permission or adopts a
host. Matching logical scopes do not show that separately deployed resource IDs
or identities share assignments.

A source survey of the personal portfolio identified these candidates:

- [Advanced auditing at edd48cd](https://github.com/nathanmcnulty/azd-advanced-auditing/tree/edd48cd5ac3866b13ddbe3640ae6181b7871975c): nearest native Exchange/Automation precedent, PowerShell 7.6 and EXO module 3.10.1. Its auditing writes and broad existing authority are not Exchange collection requirements. The source's live runtime retest remains open.
- [Maester Automation at e3fce00](https://github.com/nathanmcnulty/azd-maester-azureautomation/tree/e3fce00620e147fef4ae210007af923d9ad78ef4): native runbook/module/publication precedent, but a different runtime profile and job workload. Do not adopt by account display name.
- [Entra IGA at 0be709a](https://github.com/nathanmcnulty/azd-entra-iga/tree/0be709a9142c01b1449a00ea70361ab24265dd28): useful Blob version/lease/state lifecycle, not an Exchange permission or host-isolation precedent.

A live candidate report, when explicitly selected, must read and bind the exact
Azure cloud, tenant, subscription, resource group/account IDs, account identity,
location, runtime language/version and exact installed module versions. It must
also inventory runbooks, schedules, job contention, private-network behavior,
current ownership/retention and relevant Azure/Exchange assignments. Compare
current assignments with selected runtime requirements; keep bootstrap/operator
roles out of the runtime set. Check for broader existing authority as a risk,
not a free benefit. All pages must be read; partial visibility means unknown.

Only the operator can approve the selected exact host/identity, the permission
additions and shared failure domain. This source pilot provisions a separate
host; it does not yet implement an existing-account mutation/adoption path. A
candidate can therefore be reported as compatible in principle only, never as
adopted, isolated, permission-ready or live-qualified. Separate deployment is the
safe supported default until ownership, cleanup and combined scheduling have
been proved. Never infer shared identity authority from a tag or name.
