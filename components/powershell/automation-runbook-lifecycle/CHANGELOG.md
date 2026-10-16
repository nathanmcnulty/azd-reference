# Changelog

## 0.1.0 - 2026-10-16

- Extract the exact-runtime read, published-content/metadata preservation checks,
  already-bound no-op and runtimeEnvironment-only PATCH from the reviewed Maester
  Automation preservation work.
- Parameterize runbook/runtime names and require a caller-provided ownership
  assertion and authenticated transport callbacks.
- Keep inventory, ARM creation/omission, source publication, schedules,
  associations, grants and receipts in the consumer.
- Source-only candidate. No component release, consumer adoption or Azure
  acceptance is established by this extraction.
