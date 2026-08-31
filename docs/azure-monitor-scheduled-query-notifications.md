# Azure Monitor scheduled-query notifications

`azure-monitor-scheduled-query-notifications@0.1.0` is a pilot Bicep component
for routing Azure Monitor scheduled-query alerts to a solution-owned Logic App.
It reflects the compatible boundary currently present in the PIM and risk-based
Conditional Access solutions.

## Managed boundary

The component manages two independently callable modules:

- `logic-app-action-group.bicep` creates one enabled global action group with a
  Logic App receiver, the Logic App's HTTP trigger callback URL, and the common
  alert schema enabled.
- `scheduled-query-alert.bicep` creates one enabled scheduled-query rule over a
  supplied Log Analytics workspace. The rule uses `Count > 0`, one failing
  period out of one evaluation period, and a supplied action group.

The consumer continues to own the Logic App workflow and authorization model,
KQL, resource names, alert display text, cards or other message content,
storage, deduplication, delivery behavior, and application runtime. Callback
URLs remain deployment-time secrets and are never exposed as module outputs.

## Consumer differences

Consumers supply `autoMitigate`, `evaluationFrequency`, `windowSize`, and
`dimensions`. This preserves the two reviewed shapes without embedding their
policy:

| Shape | Automatic mitigation | Frequency | Window | Dimensions |
| --- | --- | --- | --- | --- |
| PIM activation | `true` | `PT5M` | `PT5M` | Activation event, correlation, actor, and role |
| Entra risk | `false` | `PT5M` | `PT10M` | Notification envelope |

Resource names, KQL, and dimension definitions are inputs so the component does
not determine security policy or notification content.

All required identifier, display, description, query, location, and resource-ID
strings reject empty values. The pilot permits only the intervals proven by its
two consumers: `PT5M` evaluation frequency and `PT5M` or `PT10M` window size.

The Bicep 0.42.1-compatible contract does not claim that a non-empty string is a
structurally valid Azure resource ID. Consumer wrappers must pass resource IDs
from symbolic resources or module outputs, as the checked PIM and risk fixtures
do. Compiled-template assertions verify those expressions and dependencies, and
Azure what-if plus resource-provider validation remain required before adoption.
This limitation is preferable to accepting a hand-written ID as proven merely
because it passes an incomplete string pattern.

## Pilot adoption

Vendor the component using the normal synchronization tooling after a reviewed
`component/azure-monitor-scheduled-query-notifications/v0.1.0` tag exists.
Adoption must preserve the consumer's existing resource IDs and properties.
Before merging a consumer update, run its full repository validation and an
Azure what-if against the intended environment; any delete or replacement of
an existing workflow, action group, or scheduled-query rule blocks adoption.

Promotion to stable requires successful deployment and delivery evidence from
both consumer shapes. A local Bicep build proves syntax and type compatibility,
not Azure deployment behavior or Teams delivery.
