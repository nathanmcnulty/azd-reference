# Notification and delivery contracts

V1 defines two wire contracts: a normalized domain-event envelope and one safe
result for one logical delivery route. It does not define a shared delivery
request, renderer, dispatcher, or runtime.

## Event normalization

`schemas/notification-envelope.schema.json` carries source event metadata into
solution-owned routing and rendering. `eventId` is the stable source identity;
`correlationId` connects related processing and falls back to `eventId` when the
source has no correlation value.

Register namespaced values in consumer documentation. Initial source names are:

- `microsoftGraph.directoryAudit`
- `microsoftGraph.identityProtection`
- `microsoftGraph.deviceManagement`
- `microsoftSentinel.incident`
- `azureMonitor.commonAlert`

The schema leaves `data` open because a PIM activation, risk detection, device
event, and Sentinel incident do not share a useful domain payload. Consumers must
normalize and validate that object locally. The envelope is operational data and
may contain PII, so it is not safe to log wholesale. Schema validation must be
paired with `tooling/Test-AzdNotificationContractSafety.ps1`; JSON Schema cannot
identify every credential shape inside an intentionally extensible object.

## Route result

`schemas/notification-delivery-result.schema.json` records the result after
deduplication or an attempted delivery. It is deliberately not an aggregate run
summary. The route uses a non-PII logical ID and a namespaced transport value.

Registered transport names are:

| Transport | Authorization and delivery boundary |
| --- | --- |
| `teams.workflowWebhook` | HTTPS workflow endpoint protected by a bearer URL |
| `teams.logicAppsConnector` | Logic Apps Teams connector with user OAuth consent |
| `teams.bot` | Bot Framework proactive personal messaging |
| `email.graph` | Microsoft Graph sender and recipient authorization |
| `email.logicAppsConnector` | Logic Apps mail connector authorization |
| `azureMonitor.email` | Azure Monitor action-group email receiver |

These values stay distinct even when one Function or Logic App invokes another.
Record the final delivery mechanism, not generic HTTP.

### Idempotency

`idempotencyKey` is lowercase SHA-256 over UTF-8 text:

```text
tenantId + "\n" + eventType + "\n" + eventId + "\n" + route.id
```

This opaque value avoids exposing recipient or destination identifiers. The
checked-in fixture provides a cross-language test vector.

### Outcomes

- `succeeded`: the transport proved its delivery boundary.
- `alreadyDelivered`: the same route key was previously completed.
- `skipped`: only `initialBaseline`, `suppressedByPolicy`, or
  `concurrentDelivery`; `skipReason` is required.
- `failed`: delivery was required but did not complete; the closed `failure`
  object is required.

A missing or unusable selected destination is a `destinationUnavailable` failure,
not a skip. Retry scheduling and dead-letter persistence remain runtime policy.

## Secret and privacy boundary

Neither contract may contain callback/webhook URLs, Function keys, SAS values,
authorization headers, tokens, managed-connector credentials, Bot conversation
references, raw headers/bodies, rendered cards, HTML, or raw provider errors.

The envelope's `data` may contain required PII and must remain access controlled.
The delivery result is designed for administrator-facing logs and must never copy
`data`, recipient addresses, team/channel identifiers, or rendered content.
`route.id` resolves to the real destination only inside the transport adapter.

Evidence is closed and allowlisted. Codes and identifiers must be safe opaque
values; never copy exception messages or provider response bodies.

## Deferred

- shared delivery-request and aggregate-summary schemas;
- shared Adaptive Card or HTML bodies;
- shared recipient, subject, and destination models;
- common retry, outbox, checkpoint, or dead-letter runtime;
- KQL, Sentinel incident, or Azure Monitor alert schemas; and
- localization, mentions, action links, and retention policy.

Promote these only after at least two consumers prove compatible behavior across
different transport families.
