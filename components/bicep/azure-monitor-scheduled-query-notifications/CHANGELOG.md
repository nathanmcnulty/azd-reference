# Changelog

## 0.2.0 - 2026-10-16

- Add an optional `PT30M` query window for delayed Automation diagnostics.
- Preserve the `PT5M` default, `PT5M` evaluation frequency, and existing PIM/risk
  window, mitigation, routing, and dimension behavior.
- Add a compiled Automation fixture. Source qualification does not publish a
  release tag or prove alert evaluation, notification delivery, or deduplication.

## 0.1.0 - 2026-08-31

- Introduce pilot modules for a Logic App action-group receiver and an Azure
  Monitor scheduled-query alert.
- Keep the Logic App workflow, KQL, resource names, message content, storage,
  and runtime solution-owned.
- Parameterize the proven PIM and risk-alert differences: automatic mitigation,
  evaluation frequency, window size, and alert dimensions.
- Reject empty required strings and limit evaluation/window intervals to the two
  reviewed consumer shapes.
- Add representative PIM and risk wrappers with compiled-template assertions for
  property flow, resource dependencies, and callback-output safety.
