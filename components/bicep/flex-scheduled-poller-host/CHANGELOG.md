# Changelog

## 0.2.0 - 2026-10-11

- Add an opt-in identityOnlyStorage mode for managed-identity host and Flex deployment storage; keep the shared-key compatibility default.
- Disable Storage shared keys in the identity mode, use service endpoint host settings and scope the required Blob Data Owner role to the shared storage account.
- Filter reserved application-setting and alias names only in identity mode, including case and colon/double-underscore variants.
- This is source-only pilot work: no component tag, consumer adoption or live acceptance.

## 0.1.0 - 2026-08-31

- Introduce a pilot Flex Consumption host shared by the PIM and Entra risk
  scheduled-poller infrastructure shapes.
- Default to 512 MB, a one-instance ceiling, scale to zero, and no always-ready
  instances.
- Keep Graph endpoints, permissions, schedules, queries, checkpoint semantics,
  message content, and delivery behavior solution-owned.
- Provide durable state and dead-letter containers without deploying Application
  Insights or a Log Analytics workspace.
- Keep exact resource and container names and additional application settings
  consumer-owned.
- Support temporary consumer-specific storage-setting aliases for zero-state-loss
  in-place migrations from solution-owned hosts.
