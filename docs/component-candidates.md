# Component candidate inventory

The initial portfolio review found useful duplication, but most runtime patterns
do not yet share one safe abstraction. This inventory records the intended
boundaries without promoting them prematurely.

## Teams transports

| Transport | Security and operating model | Current reference |
| --- | --- | --- |
| Teams Workflow/webhook URL | Anonymous HTTPS endpoint protected by a bearer URL. The URL is a secret and must never appear in receipts or logs. | `azd-risk-based-ca`, `azd-pim`, `azd-device-notifications` |
| Logic Apps Teams managed connector | Azure API connection with one-time user OAuth consent, connection readiness, workflow enablement, and delivery-run proof. | `azd-risk-based-ca`, `azd-emergency-access`, `azd-entra-health-monitoring` |
| Bot Service proactive delivery | Teams app installation, Bot Framework authentication, stored conversation references, and proactive personal messages. | `azd-device-notifications` |

These transports may share message and delivery-result schemas. They must remain
separate deployable components.

## Monitoring terminology

Modules in `azd-pim` and `azd-risk-based-ca` currently described as Sentinel
notifications primarily deploy `Microsoft.Insights/scheduledQueryRules` over Log
Analytics. Their future component name is **Azure Monitor scheduled-query alert**.

Reserve **Sentinel** for `Microsoft.SecurityInsights` analytic rules, incidents,
automation rules, and incident-triggered playbooks. `azd-emergency-access` is the
current reference for that pattern, and it remains local until a second consumer
proves a stable boundary.

## Promotion order after the validation pilot

`deployment-validation@1.0.0` is the first stable component. Its three adopted
consumer shapes proved managed-file ownership, drift detection, isolated update
preparation, repository-owned validation, and commit-only rollback. The stable
promotion changes release metadata only; its runtime implementation and report
schema are byte-identical to 0.3.3.

Remaining promotion order:

1. Notification envelope and delivery-result schemas: available as the
   `notification-contracts@1.0.0` pilot component.
2. Azure Monitor scheduled-query alert and action-group receiver modules:
   available as the `azure-monitor-scheduled-query-notifications@0.1.0` pilot
   component.
3. Teams managed-connector authorization and delivery proof.
4. Identity-only storage, observability, and Flex Consumption Function baseline.
5. Application-role planning beyond the delegated Graph authentication component.
6. Polling contracts and fixtures; shared runtime only after compatible state and
   credential interfaces exist.

Keep KQL, Adaptive Card content, domain event normalization, PIM custom-extension
behavior, Sentinel analytic rules, and Teams Bot domain integration solution-owned
through the initial pilots.
