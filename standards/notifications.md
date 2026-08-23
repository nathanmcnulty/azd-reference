# Notification implementation standard

Teams bots, Teams workflow/webhook delivery, Sentinel automation, and scheduled
pollers are separate deployable patterns. Do not hide their different identity,
consent, cost, and operating models behind one infrastructure module.

They should share portfolio contracts for:

- message facts and Adaptive Card content;
- correlation and idempotency identifiers;
- explicit connection and consent readiness;
- labeled delivery smoke tests;
- deployment receipts and validation results;
- managed identity and least-privilege expectations; and
- health and failure outputs.

Provisioning a connection resource is not proof of delivery. A component may
report infrastructure readiness, consent readiness, and proven delivery as
separate states.

No delivery test runs during ordinary read-only deployment validation.
