# Changelog

## 0.2.0

- Add optional solution-owned runbook, runtime and schedule names, bounded hourly interval and non-secret job parameters; preserve existing defaults.
- Keep package integrity gating, role scopes and separate-host identity unchanged. Reserved package parameters cannot be overridden.
- Expose exact resource IDs and runtime/schedule names for consumer readback. This does not implement existing-account adoption or grant Exchange permissions.

## 0.1.0

- Optional PowerShell 7.4 Flex, Automation and Logic App orchestration hosts.
- Local mode provisions no resources; scheduled processing starts disabled.
- Private Blob containers and managed identity storage access, without Graph grants.

## 0.1.1

- Separate Function host storage and scope evidence/package readers and report writers to containers.
- Refresh scheduled bundle parameters after publication and verify Automation pause requests.
- Reject dirty sources, component drift, mixed runtime revisions and unsafe POST pagination.
- Upload a final report completion manifest; keep incomplete prefixes unaccepted.
- Add azd hooks and package/transition regression tests.

## 0.1.2

- Verify complete component lock schema and every copied host entry point.
- Reject non-hexadecimal schedule package hashes at the template boundary.
- Stage explicitly declared companion artifacts and verify their hashes before execution.
- Constrain hosted file references to the downloaded evidence root.

## 0.1.3

- Normalize template EOF for clean consumer whitespace validation; runtime behavior is unchanged.

## 0.1.4

- Add workspace-backed Function diagnostics with 30-day retention and a 0.1 GB daily ingestion cap so invocation and deployment failures can be investigated.

## 0.1.5

- Select PowerShell 7.6 for Functions Flex and the Automation runtime shared by Automation and Logic App modes.
- Bind runbooks to the separately named SecurityPowerShell76 runtime environment, preserving any retained older environment.
- Keep the source-only pilot lifecycle, compute-free default, disabled scheduling and existing identity/permission boundaries. Native startup and execution remain separate validation gates.
