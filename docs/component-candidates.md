# Component candidate inventory

The initial portfolio review found useful duplication, but most runtime patterns
do not yet share one safe abstraction. This inventory records the intended
boundaries without promoting them prematurely.

## Permission metadata and current lifecycle boundaries

Use the [permission tracking standard](../standards/permission-requirements.md)
and [comparison guide](permission-comparison.md) alongside component manifests
and immutable consumer locks. The registry records declared requirements and
known gaps. It does not inspect effective grants or provide deployment input.
Optional features preserve their principal, phase, exact scope and evidence
state; the union of optional requirements is not a grant recommendation.

Current main manifests classify `deployment-validation@1.1.1` as stable;
`notification-contracts@1.0.0`, `graph-delegated-authentication@0.1.1`,
`maester-azd-hooks@0.1.5`, `maester-report-webapp@0.1.1`,
`azure-monitor-scheduled-query-notifications@0.1.0` and
`flex-scheduled-poller-host@0.1.0`, `intune-remediations@0.1.6`,
`security-automation-runtime@0.1.7` and `security-automation-host@0.1.4` as pilots; and
`deployment-receipt@0.2.1` as a candidate. Versions and lifecycle labels are
evidence of their respective contracts, not blanket deployment or release approval.

The permission schema, registry and comparison tool were reconciled separately
from preserved security host/runtime and Intune collection component work. A
later source-only packet imports the exact reviewed Intune Remediations 0.1.6
component and tests from `e5265492a949f2e111d3dac88d043b4f63175d3a` as a
pilot. Existing AV and Firewall locks continue to pin that immutable revision;
no consumer update, component tag or release is part of the import. Their live
evidence qualifies the reusable publication/readback boundary, not complete
endpoint inventory, delivery, policy migration or enforcement acceptance.

The 20 security host/runtime component and test paths are separately qualified as
source-only pilots. The host remains 0.1.4. Runtime 0.1.7 binds the Automation
package blob to the exact lowercase SHA-256 ZIP leaf before authentication or
download and manages the current hardened permission schema under a new version.
The four newer staged security solutions retain their existing 0.1.6/0.1.4 locks
until a separately reviewed consumer upgrade. Shared-host identities, lifecycle
isolation, actual Function/Automation/Logic App operation, endpoint policy
convergence and component release remain separate qualification gates. Teams
personal-bot and managed-connector extraction still needs the delivery and
lifecycle evidence described below.

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

All four consumers completed separate 1.1.1 adoption reviews and retain
their unbound schema 1.0 domain validation contracts. Each upgrade needs its
own consumer review because 1.1.1 adds an
evidence-binding contract and managed-file changes rather than a metadata-only
release.

| Consumer | Current lock evidence | Decision |
| --- | --- | --- |
| Auth Notifications | Reviewed local `deployment-validation@1.1.1` at `0c96cc89c554ffc3b3ca82ceda12da6591e816c1` | Adopted locally after independent review, zero-provider plan smoke and full offline validation. Existing schema 1.0 reports and notification-contracts 1.0.0 remain unchanged. |
| Device Notifications | Reviewed `deployment-validation@1.1.1` at `0c96cc89c554ffc3b3ca82ceda12da6591e816c1` | Adopted in a separate reviewed packet with full offline validation; notification-contracts 1.0.0 and the domain adapter remain unchanged. |
| Emergency Access | Reviewed `deployment-validation@1.1.1` at `0c96cc89c554ffc3b3ca82ceda12da6591e816c1` | Adopted in a separate reviewed packet with full offline validation; graph-delegated-authentication 0.1.1 and the domain adapter remain unchanged. |
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
