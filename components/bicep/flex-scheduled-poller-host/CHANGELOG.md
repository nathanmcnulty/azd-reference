# Changelog

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
