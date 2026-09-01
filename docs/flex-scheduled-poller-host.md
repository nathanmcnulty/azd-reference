# Flex scheduled-poller host

`flex-scheduled-poller-host@0.1.0` is a pilot Bicep component for small scheduled
pollers that need a Flex Consumption Function App and durable Blob state without
an unrelated Log Analytics deployment.

## Managed boundary

The component owns:

- one Standard LRS Storage account with deployment, state, and dead-letter
  containers;
- one scale-to-zero Flex Consumption plan and Node.js 22 Function App;
- a system-assigned managed identity and Storage Blob Data Contributor role;
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

The current pilot keeps shared-key access enabled because the Flex host and
One Deploy storage configuration use connection-string settings. The Function
identity uses Blob RBAC for application state access. Removing the host and
deployment connection strings is a follow-up hardening change that requires a
separately validated Flex configuration and a new component version.

The first reviewed shapes are the PIM audit poller and the Entra risk-detection
poller. Their host infrastructure is compatible, but their application behavior
is not. This component therefore shares the infrastructure without forcing a
premature common runtime library.

## Pilot adoption

After a reviewed `component/flex-scheduled-poller-host/v0.1.0` tag exists, vendor
the module with the normal synchronization tooling and call it from a thin,
solution-owned wrapper. Validate the Function package separately, build the
consumer root template, and perform a no-delete Azure what-if before deployment.
