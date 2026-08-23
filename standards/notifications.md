# Notification implementation standard

Teams bots, Teams workflow/webhook delivery, Sentinel automation, and scheduled
pollers are separate deployable patterns. Do not hide their different identity,
consent, cost, and operating models behind one infrastructure module.

They should share portfolio contracts for:

- normalized domain-event metadata and route-level delivery outcomes;
- correlation and opaque idempotency identifiers;
- explicit connection and consent readiness;
- labeled delivery smoke tests;
- deployment receipts and validation results;
- managed identity and least-privilege expectations; and
- health and failure outputs.

Provisioning a connection resource is not proof of delivery. A component may
report infrastructure readiness, consent readiness, and proven delivery as
separate states.

No delivery test runs during ordinary read-only deployment validation.

Portable notification data conforms to
`schemas/notification-envelope.schema.json`. Each route records a result that
conforms to `schemas/notification-delivery-result.schema.json`. See
`docs/notification-contracts.md` for identifier, evidence, and secret boundaries.
