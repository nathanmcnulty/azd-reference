# Component candidate inventory

The initial portfolio review found useful duplication, but most runtime patterns
do not yet share one safe abstraction. This inventory records the intended
boundaries without promoting them prematurely.

## Sysmon deployment

The public `nathanmcnulty/azd-sysmon` consumer vendors
`graph-delegated-authentication@0.1.1` for its optional Intune publisher. Its
Sysmon package builder, endpoint installer, Windows Event DCR, and target-selection
policy remain solution-owned until another consumer proves a reusable boundary.
Upstream configuration XMLs use their own release/hash manifest and retain their
original license; they are not relicensed as an azd-reference component.

## Teams transports

| Transport | Security and operating model | Current reference |
| --- | --- | --- |
| Teams Workflow/webhook URL | Anonymous HTTPS endpoint protected by a bearer URL. The URL is a secret and must never appear in receipts or logs. | `azd-risk-based-ca`, `azd-pim`, `azd-device-notifications` |
| Logic Apps Teams managed connector | Azure API connection with one-time user OAuth consent, connection readiness, workflow enablement, and delivery-run proof. | `azd-risk-based-ca`, `azd-emergency-access`, `azd-entra-health-monitoring` |
| Bot Service proactive delivery | Teams app installation, Bot Framework authentication, stored conversation references, and proactive personal messages. | `azd-device-notifications`, `azd-auth-notifications` |

These transports may share message and delivery-result schemas. They must remain
separate deployable components.

`azd-auth-notifications` is now a second consumer of the personal Bot Service
pattern. Both consumers should continue to own their Bot manifest, card content,
route policy, state schema, catalog publication, and installation workflow while
their recipient-visible delivery evidence is incomplete. Reconsider a narrowly
scoped `teams-personal-bot-lifecycle` component after both solutions prove a
human-visible personal receipt and converge on tenant-bound conversation capture,
safe provider-result taxonomy, ownership receipts, and propagation handling.

## Monitoring terminology

Modules in `azd-pim` and `azd-risk-based-ca` currently described as Sentinel
notifications primarily deploy `Microsoft.Insights/scheduledQueryRules` over Log
Analytics. Their future component name is **Azure Monitor scheduled-query alert**.

Reserve **Sentinel** for `Microsoft.SecurityInsights` analytic rules, incidents,
automation rules, and incident-triggered playbooks. `azd-emergency-access` is the
current reference for that pattern, and it remains local until a second consumer
proves a stable boundary.

## Promotion order after the validation pilot

`deployment-validation@1.1.1` is the current stable component. Version 1.0.0 was
the first stable release; its initial three adopted consumer shapes proved
managed-file ownership, drift detection, isolated update preparation,
repository-owned validation, and commit-only rollback. Version 1.1.1 adds the
optional 1.1 management-evidence binding while retaining schema 1.0 output.

Auth Notifications was the fourth adopted 1.0.0 consumer and also adopts
`notification-contracts@1.0.0`. Its registered pilot remains independently
deployable and uses a repository-owned offline adapter for the same npm, Bicep,
and Git checks as its validation workflow. Registration does not make catalog
validation required or authorize a component upgrade.
The reviewed local consumer lock now pins `deployment-validation@1.1.1` to
`0c96cc89c554ffc3b3ca82ceda12da6591e816c1` and
`notification-contracts@1.0.0` to
`bc2cf2aad4ff5ebadabe8fd0f0efcf71d94d0e0f`.

### Deployment-validation 1.1.1 upgrade decisions

Auth Notifications and PIM completed separate local 1.1.1 adoption reviews;
Device Notifications and Emergency Access retain 1.0.0. Each upgrade needs its
own consumer review because 1.1.1 adds an
evidence-binding contract and managed-file changes rather than a metadata-only
release.

| Consumer | Current lock evidence | Decision |
| --- | --- | --- |
| Auth Notifications | Reviewed local `deployment-validation@1.1.1` at `0c96cc89c554ffc3b3ca82ceda12da6591e816c1` | Adopted locally after independent review, zero-provider plan smoke and full offline validation. Existing schema 1.0 reports and notification-contracts 1.0.0 remain unchanged. |
| Device Notifications | `deployment-validation@1.0.0` at `ef60904fa3aa3dee81f36ba7bfed0eed18f72276` | Keep 1.0.0 desired. Prepare a separate consumer update and validate its existing project adapter before changing the registry. |
| Emergency Access | `deployment-validation@1.0.0` at `ef60904fa3aa3dee81f36ba7bfed0eed18f72276` | Keep 1.0.0 desired. Review evidence-binding semantics in an independent consumer update before changing the registry. |
| PIM | Reviewed local `deployment-validation@1.1.1` at `0c96cc89c554ffc3b3ca82ceda12da6591e816c1` | Adopted locally after independent review and full offline validation. Schema 1.0 output remains explicit; unrelated Flex-host and attribute edits are preserved. |

Remaining promotion order:

1. Notification envelope and delivery-result schemas: available as the
   `notification-contracts@1.0.0` pilot component.
2. Azure Monitor scheduled-query alert and action-group receiver modules:
   available as the `azure-monitor-scheduled-query-notifications@0.1.0` pilot
   component.
3. Flex Consumption host and durable Blob state: available as the
   `flex-scheduled-poller-host@0.1.0` pilot component. Identity-only host and
   deployment storage remains a hardening candidate.
4. Teams managed-connector authorization and delivery proof.
5. Application-role planning beyond the delegated Graph authentication component.
6. Polling contracts and fixtures; shared runtime only after compatible state and
   credential interfaces exist.

Keep KQL, Adaptive Card content, domain event normalization, PIM custom-extension
behavior, Sentinel analytic rules, and Teams Bot domain integration solution-owned
through the initial pilots.

## Maester hosting templates

The four Maester hosting shapes share two pilot components while retaining their
host-specific runners and provisioning behavior:

- `maester-azd-hooks@0.1.5` carries the shared azd lifecycle hooks, target-context
  helpers, and optional Graph permission setup.
- `maester-report-webapp@0.1.1` carries the optional report web app resources,
  publishing controls, host identity permission, tags, and delete lock.

Maester module execution is pinned independently to the stable `2.2.0` release.
The two reference components remain pilots until all four consumers validate the
same vendored files and optional-feature permissions in their normal azd flows.
