# Flex scheduled-poller host

`flex-scheduled-poller-host@0.2.0` is a pilot Bicep component for small scheduled
pollers that need a Flex Consumption Function App and durable Blob state without
an unrelated Log Analytics deployment.

## Managed boundary

The component owns:

- one Standard LRS Storage account with deployment, state, and dead-letter
  containers;
- one scale-to-zero Flex Consumption plan and Node.js 22 Function App;
- a system-assigned managed identity with the compatibility Blob Data Contributor
  role or the opt-in host Blob Data Owner role;
- the Function host and deployment-storage settings; and
- generic `AZD_POLLER_*` state settings consumed by solution-owned poller code.

The default instance size is 512 MB and the default maximum instance count is
one. Consumers should optimize API projection, page size, overlap, and in-memory
processing before increasing memory. The supported Flex sizes remain available
as explicit overrides when measured evidence shows that a larger instance is
required.

The component deliberately does not create Application Insights or a Log
Analytics workspace. A consumer may add independently governed telemetry, but a
poller does not acquire that cost or ownership boundary merely by adopting this
host.

Resource and container names are inputs so an existing consumer can adopt the
component without replacing resources or abandoning its durable state. The
three setting-alias arrays support a bounded in-place package migration: keep
the old names for the first component adoption, deploy code that reads the
generic `AZD_POLLER_*` names, and remove the aliases in a later reviewed update.
Wrappers must also pass their existing Blob soft-delete retention explicitly
during adoption; the component default is seven days and must not silently
shorten a consumer's established recovery window.

## Solution-owned behavior

Consumers retain their Graph or other API endpoint, application permissions,
timer schedule, query and projection, transformation, checkpoint schema,
deduplication rules, initial-history policy, notification content, and delivery
transport. Additional settings are passed through the secure
`applicationSettings` object; component-owned host and storage settings take
precedence because the component emits them last. If alias arrays repeat a
name, the later state or dead-letter mapping wins deterministically. Consumers
must use unique, non-reserved aliases so the migration contract remains
unambiguous; the compiled migration fixture verifies the emitted ordering.

The compatibility default keeps shared-key access enabled because the Flex host and
One Deploy storage configuration use connection-string settings. The Function
identity uses Blob RBAC for application state access. Removing the host and
deployment connection strings is available through the new 0.2.0 opt-in mode
below, with separate native qualification and adoption gates.

The first reviewed shapes are the PIM audit poller and the Entra risk-detection
poller. Their host infrastructure is compatible, but their application behavior
is not. This component therefore shares the infrastructure without forcing a
premature common runtime library.

## Pilot adoption

After a reviewed `component/flex-scheduled-poller-host/v0.1.0` tag exists, vendor
the module with the normal synchronization tooling and call it from a thin,
solution-owned wrapper. Validate the Function package separately, build the
consumer root template, and perform a no-delete Azure what-if before deployment.

## Opt-in identity-only storage (source-only 0.2.0 pilot)

Set `identityOnlyStorage=true` explicitly in the consumer-owned wrapper after
reviewing storage/runtime requirements. The default false preserves shared-key
host/deployment settings, resource names, aliases, retention and the original
Blob Data Contributor role.

Identity mode disables Storage shared keys, uses actual Blob/Queue/Table service
endpoints and `AzureWebJobsStorage__credential=managedidentity`, and configures
Flex deployment storage with `SystemAssignedIdentity`. It emits no host or
deployment connection-string setting. ARM's lazy `if` confines `listKeys` to the
unselected compatibility branch. See [Microsoft's identity connection guidance](https://learn.microsoft.com/en-us/azure/azure-functions/manage-connections?pivots=functions-auth-identity&tabs=host)
and [Flex infrastructure guidance](https://learn.microsoft.com/en-us/azure/azure-functions/functions-infrastructure-as-code).

Storage Blob Data Owner is scoped to the one shared storage account and assigned
to the Function's system identity. Host, deployment, checkpoint and dead-letter
data share that identity/account; its effective role covers all containers.
This is not isolation between those purposes. Identity mode adds no redundant
Contributor grants. Deployment operators separately need resource and scoped
role-assignment authority; metadata does not authorize grants.

Only identity mode filters injected settings and aliases whose names, after case
folding and colon-to-double-underscore normalization, start with
`AzureWebJobsStorage`, `DEPLOYMENT_STORAGE_CONNECTION_STRING`, `AZD_POLLER_` or
`AZURE_ENV_NAME`. Legacy keys, client-ID/credential overrides and reserved case
or colon variants, including duplicate aliases, are removed before component
values are emitted. Non-reserved settings/aliases retain existing ordering;
legacy mode retains original pass-through behavior. Do not use reserved aliases.
The exact legacy names `AzureWebJobsDashboard` and
`WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`, and the Flex-unsupported deployment
override `WEBSITE_RUN_FROM_PACKAGE`, are also filtered in identity mode. Other
solution-owned secure application settings remain allowed; this boundary does
not promise that arbitrary application settings contain no secrets.

The documented host minimum covers the timer shape. Extra bindings, Durable
Functions and diagnostic Table writes can require additional roles; these are
consumer-owned gaps. Compiled roles depend on the Function identity. Deployment
completion does not prove RBAC propagation, OneDeploy or timer readiness; do not
add a Function-to-role dependency cycle to claim readiness.

PIM and risk fixtures preserve their exact 0.1.0 wrapper/lock shapes, naming,
application settings, aliases and 7/14-day retention without changing consumers.
Offline compilation does not prove native deployment, package/runtime operation,
checkpoint continuity, effective grants or delivery. Two native shape
qualifications, independent review and separately authorized immutable release
remain required. No 0.2.0 tag or consumer adoption is published by this source-only
change; rollback remains reverting a reviewed consumer commit.

Role conditions select grants for a fresh deployment; they do not delete an
existing assignment under ARM Incremental deployment. Moving a legacy account
to identity mode can retain the original Contributor assignment, and reverting
to legacy mode can retain Owner. A code rollback is not an RBAC rollback.
Inspect and explicitly reconcile the exact account's assignments under separate
review before adopting or rolling back a deployed consumer. The component does
not delete assignments automatically. Two fresh-shape proofs do not establish
in-place migration, state continuity or role-reconciliation behavior.

## Native startup investigation

The 18 October 2026 two-shape native attempt did not qualify the identity-only
pilot. See the [source comparison and bounded diagnostic plan](flex-startup-diagnostic-20261018.md)
for the immutable evidence, first-party contracts and remaining distinctions.
No component defect or version change is established by package-upload success
followed by host startup failure.

The follow-up [single-PIM startup diagnostic](flex-pim-startup-diagnostic-20261018.md)
records the later bounded indexing evidence, limitations and completed cleanup.
