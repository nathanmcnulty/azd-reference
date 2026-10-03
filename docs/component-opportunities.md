# Component opportunities

Read-only suitability review of local tracked manifests and consumer locks on 3 October 2026. These are proposed adoption decisions, not instructions to sync, deploy or publish components. The lock/source/identity review remains part of each owning backlog task.

## Tracked catalog

| Component | Current manifest version | Lifecycle |
| --- | --- | --- |
| deployment-validation | 1.1.1 | stable |
| deployment-receipt | 0.2.1 | candidate |
| notification-contracts | 1.0.0 | pilot |
| flex-scheduled-poller-host | 0.1.0 | pilot |
| azure-monitor-scheduled-query-notifications | 0.1.0 | pilot |
| graph-delegated-authentication | 0.1.1 | pilot |
| maester-azd-hooks | 0.1.5 | pilot |
| maester-report-webapp | 0.1.1 | pilot |
| security-automation-host | 0.1.0 | new active-branch pilot |
| security-automation-runtime | 0.1.0 | new active-branch pilot |

Manifests are authoritative for the current authored version; immutable tags and consumer locks are the delivery evidence. Candidate and pilot status remain explicit. `docs/component-candidates.md` contains older version examples that REF-005/006 will reconcile.

## Suitability by repository

| Repository | Locked adoption now | Proposed next decision |
| --- | --- | --- |
| [azd-advanced-auditing](../../azd-advanced-auditing/docs/backlog.md) | No root lock (not established adoption) | Stable deployment-validation; candidate receipts only where Exchange/Automation ownership evidence fits. Exchange auth is not delegated Graph auth. |
| [azd-auth-notifications](../../azd-auth-notifications/docs/backlog.md) | deployment-validation@1.1.1, notification-contracts@1.0.0 | Existing adoption is registered and reviewed validation 1.1.1 is adopted locally. Evaluate Flex only if Table state and identity-only storage are preserved. Bot lifecycle remains local. |
| [azd-cloud-pc-recommendations](../../azd-cloud-pc-recommendations/docs/backlog.md) | No root lock (not established adoption) | Validation + notification contracts fit. Flex host is a compatibility study: Python and current identity-only storage must not regress. |
| [azd-defender-reporting](../../azd-defender-reporting/docs/backlog.md) | No root lock (not established adoption) | Validation and candidate receipts fit wrapper state. Optional WebApp needs its own asset/Easy Auth contract; Maester webapp is not a drop-in general module. |
| [azd-device-cleanup](../../azd-device-cleanup/docs/backlog.md) | No root lock (not established adoption) | Validation and candidate receipts can bound plan/enforce outcomes. Delegated Graph module does not fit app-only runbook calls. Portable notification contracts may support route formatting. |
| [azd-device-notifications](../../azd-device-notifications/docs/backlog.md) | deployment-validation@1.1.1, notification-contracts@1.0.0 | Retain portable notification contracts; reviewed validation 1.1.1 is adopted. Personal-bot extraction waits for both consumer delivery proofs. |
| [azd-emergency-access](../../azd-emergency-access/docs/backlog.md) | deployment-validation@1.1.1, graph-delegated-authentication@0.1.1 | Retain Graph auth; reviewed validation 1.1.1 is adopted. Normalize route results before adding notification contracts; keep Sentinel analytics and connector behavior local. |
| [azd-entra-health-monitoring](../../azd-entra-health-monitoring/docs/backlog.md) | No root lock (not established adoption) | Fix callback/clientState first, then validation and portable notification results. Managed-connector lifecycle is a future extraction candidate. |
| [azd-entra-iga](../../azd-entra-iga/docs/backlog.md) | No root lock (not established adoption) | Reconcile unlocked Graph coordinator tooling with formal hash-locked adoption; add validation around plan/apply rather than replacing reconciliation. |
| [azd-global-secure-access](../../azd-global-secure-access/docs/backlog.md) | No root lock (not established adoption) | Delegated Graph coordinator fits direct Connect-MgGraph flows; validation can expose licensing/connector/target and optional CRL health. |
| [azd-gui](../../azd-gui/docs/backlog.md) | No root lock (not established adoption) | Consumes template/permission/receipt contracts as a reader; no Azure runtime host component adoption. Candidate receipts cannot imply human acceptance. |
| [azd-maester](../../azd-maester/docs/backlog.md) | No root lock (not established adoption) | Legacy catalog/root guard; route fixes to the four standalone hosts, avoiding new root runtime adoption. |
| [azd-maester-azureautomation](../../azd-maester-azureautomation/docs/backlog.md) | maester-azd-hooks@0.1.5, maester-report-webapp@0.1.1 | Retain existing hooks/webapp pilots; validate runbook failure/report semantics and exact optional-feature permissions. |
| [azd-maester-azuredevops](../../azd-maester-azuredevops/docs/backlog.md) | maester-azd-hooks@0.1.5, maester-report-webapp@0.1.1 | Retain existing hooks/webapp pilots; pipeline failure taxonomy and old wizard issues need canonical-host reconciliation. |
| [azd-maester-containerappjob](../../azd-maester-containerappjob/docs/backlog.md) | maester-azd-hooks@0.1.5, maester-report-webapp@0.1.1 | Retain existing hooks/webapp pilots; job failure/report semantics and optional ACR naming take priority. |
| [azd-maester-functionapp](../../azd-maester-functionapp/docs/backlog.md) | maester-azd-hooks@0.1.5, maester-report-webapp@0.1.1 | Retain existing hooks/webapp pilots; finish active packaging/timeout/report work before new component updates. |
| [azd-myworkid](../../azd-myworkid/docs/backlog.md) | No root lock (not established adoption) | Validation and candidate receipts can show pending DNS/certificate/setup. azd-token/REST Graph flow is not a direct delegated Graph module fit. |
| [azd-pim](../../azd-pim/docs/backlog.md) | azure-monitor-scheduled-query-notifications@0.1.0, deployment-validation@1.1.1, flex-scheduled-poller-host@0.1.0, graph-delegated-authentication@0.1.1, notification-contracts@1.0.0 | Retain existing pilots; reviewed validation 1.1.1 is adopted locally, preserving the separate Flex vendor provenance work. Keep role policy, callback, state and KQL local. |
| [azd-reference](../../azd-reference/docs/backlog.md) | No root lock (not established adoption) | Canonical authoring/validation only. Review newly committed host/runtime boundaries before registration, publication or adoption. |
| [azd-risk-based-ca](../../azd-risk-based-ca/docs/backlog.md) | azure-monitor-scheduled-query-notifications@0.1.0, flex-scheduled-poller-host@0.1.0 | Retain Flex/Azure Monitor pilots; add contracts only when result/validation entry points conform. Keep KQL/migration/CA behavior local. |
| [azd-santa](../../azd-santa/docs/backlog.md) | No root lock (not established adoption) | Delegated Graph coordinator is a strong compatible bootstrap candidate. Validation must preserve real-Mac/profile gates; keep native package/profile receipts and compute-free baseline. |
| [azd-sysmon](../../azd-sysmon/docs/backlog.md) | graph-delegated-authentication@0.1.1 | Retain Graph pilot. Add deployed-state validation only after separating repository validation from endpoint/ingestion evidence. |
| [azd-verified-id](../../azd-verified-id/docs/backlog.md) | No root lock (not established adoption) | Validation/candidate receipts can expose pending DNS/issuance. azd-token/REST bootstrap is not a delegated Graph module fit. |
| [azd-website](../../azd-website/docs/backlog.md) | No root lock (not established adoption) | Display/source-provenance contracts only; no deployment host adoption. Never publish private backlog/lab data automatically. |
| [azd-work-in-progress](../../azd-work-in-progress/docs/backlog.md) | No root lock (not established adoption) | Coordination only; staged solutions independently evaluate components. Preserve copies until separately authorized promotion/cleanup. |
| [azd-nathanmcnulty](../../azd-nathanmcnulty/docs/backlog.md) | No root lock (not established adoption) | Local coordination only while configured remote is unresolved; no runtime components. |
| [azd-work-in-progress/azd-app-control](../../azd-work-in-progress/azd-app-control/docs/backlog.md) | security-automation-host@0.1.4, security-automation-runtime@0.1.4 | Retained Phase 0 probes/design; reconcile with newer product before runtime extraction. |
| [azd-work-in-progress/azd-app-control-for-business](../../azd-work-in-progress/azd-app-control-for-business/docs/backlog.md) | security-automation-host@0.1.4, security-automation-runtime@0.1.4 | Portable engine first; optional Flex/validation/receipt decisions must preserve compute-free deployment, human approval and real endpoint proof. |
| [azd-work-in-progress/azd-defender-asr-rules](../../azd-work-in-progress/azd-defender-asr-rules/docs/backlog.md) | security-automation-host@0.1.4, security-automation-runtime@0.1.4 | Offline engine/read-only proposals now exist. Review new security-automation host/runtime adapters and bundle provenance; keep separate hosts/write identities and real endpoint gates. |
| [azd-work-in-progress/azd-defender-av-exclusions](../../azd-work-in-progress/azd-defender-av-exclusions/docs/backlog.md) | security-automation-host@0.1.4, security-automation-runtime@0.1.4 | Offline exclusions/coverage engine now exists. Qualify new security-automation host/runtime integration, captured tenant contract and complete observation/merge evidence. |
| [azd-work-in-progress/azd-defender-firewall](../../azd-work-in-progress/azd-defender-firewall/docs/backlog.md) | security-automation-host@0.1.4, security-automation-runtime@0.1.4 | Offline domain engine and collector now exist. Review new host/runtime adapters while preserving rule filter fidelity, per-profile merge and connectivity rollback. |

## Extraction and permission boundaries

- Teams webhook URLs, managed connector consent and proactive bot conversation lifecycle are different transports. Share portable result/envelope contracts; keep transport implementation separate.
- Keep Sentinel analytic/automation rules separate from Azure Monitor scheduled-query alerts. KQL, cards, event normalization and domain reconciliation remain solution-owned.
- Deployment receipt is a candidate writer and must not replace Santa package/profile ownership or Sysmon endpoint evidence without explicit contract review.
- New `security-automation-host` and `security-automation-runtime` 0.1.0 manifests are tracked in active-branch commit 9ed4c575cc057a4a96c05ce91c7dd9b7694da7b7, while additional files remain under owner development. Inspect the finished exact diff, host-neutral versus host-adapter boundary, immutable publication and independent lifecycle evidence before adoption.
- Every optional feature compares exact incremental permissions in azd-permissions.json against the canonical schema. Unknown requirements are gaps. A disabled feature adds no grant merely because its metadata is present.
- Components are vendored at reviewed immutable revisions with exact hashes. Deployed templates never fetch azd-reference, the catalog or these backlog tools at runtime.

The webhook authenticity/lifecycle design should be checked against [Microsoft Graph webhook guidance](https://learn.microsoft.com/en-us/graph/change-notifications-delivery-webhooks) and [lifecycle notifications](https://learn.microsoft.com/en-us/graph/change-notifications-lifecycle-events). AZD orchestration conventions come from the [official azure.yaml schema](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/azd-schema); they do not replace repository-owned permission and deployment authority gates.
