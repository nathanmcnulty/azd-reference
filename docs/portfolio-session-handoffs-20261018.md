# AZD portfolio: focused-session handoffs

Inventory date: 2026-10-18. Scope: all 25 current nathanmcnulty azd-* repositories, including six independent staged solutions within azd-work-in-progress. This is an issue inventory and handoff, not new feature implementation or Azure acceptance.

**174 tracked streams: 105 new issues and 69 existing issues with focused handoffs.** Every issue that was open in the initial snapshot is mapped. Most new issues split existing feature/validation scope into sessions; they are not all new defects or urgent work.

A substantial portion of completed source work remains in reviewed draft PRs. It is preserved on GitHub but has not been merged into the default branches. Review/integration rows mean reconcile the exact existing candidate and reuse its review/CI evidence; they do not mean reimplement the feature or repeat unchanged tests. Source completion does not satisfy native, recipient, endpoint or publication gates.

## How to use this queue

Start a fresh session with one repository and one linked issue. The issue contains the source starting point, bounded scope, acceptance, validation, dependencies and missing inputs. Recheck current heads and owners first; claim one mutable worktree. Finish with a reviewed pushed draft and exact evidence, or the concrete blocker after one bounded distinguishing probe. Do not import this conversation or restart the whole portfolio goal.

The gate column describes the next action, not a promise that a feature is complete. Dependency links refer to required reviewed artifacts/inputs; umbrella issues can stay open while their child sessions run. Public summaries omit private lab account/group/resource selectors, credentials and callback URLs.
This dated report and its JSON index are snapshots. GitHub issues and each repository's canonical backlog remain the active records; update those during work rather than treating this report as another mutable backlog or deployment contract.

Common boundaries: PowerShell 7.6+, Pester 6.2.0 where used, no older-version compatibility effort, independent review and pushed work, no unapproved merge/release/promotion/grants, and no runtime dependency on Reference. Native Azure work stays in approved sub-mvp with exact expected tenant and a fresh scoped identity/tenant/Enabled check before every mutation, including cleanup. Use cached/WAM or normal browser/broker authentication; never device-code authentication.

## First source queue

- [Guard direct runtime file publication with explicit target and fresh Enabled state](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/38) — azd-maester-containerappjob. Ready for bounded session.
- [Add opt-in runtime-only validation to the maintained runbook](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/32) — azd-maester-azureautomation. Ready for bounded session.
- [Bind security-host operator writes to explicit tenant and Enabled subscription](https://github.com/nathanmcnulty/azd-reference/issues/117) — azd-reference. Dotty-owned.
- [Require fresh target guards in the solution-owned Exchange operator paths](https://github.com/nathanmcnulty/azd-work-in-progress/issues/78) — azd-work-in-progress. Ready for bounded session.
- [Implement an executable owned-state restore path](https://github.com/nathanmcnulty/azd-work-in-progress/issues/73) — azd-work-in-progress. Ready for bounded session.
- [Implement the durable admin notification outbox](https://github.com/nathanmcnulty/azd-work-in-progress/issues/74) — azd-work-in-progress. Ready for bounded session.
- [Implement the shared-mailbox agent evidence adapter](https://github.com/nathanmcnulty/azd-work-in-progress/issues/75) — azd-work-in-progress. Ready for bounded session.
- [Implement the direct quarantine evidence adapter](https://github.com/nathanmcnulty/azd-work-in-progress/issues/76) — azd-work-in-progress. Ready for bounded session.

The first three fixes retain Dotty ownership/queue order. Exchange restore, outbox and evidence adapters are independent bounded source candidates; assign disjoint paths/worktrees and respect their state/target contracts. The confirmed same-process evidence-root issue is a separate canonical follow-up after the existing operator-guard correction, not a demonstrated exploit in the default timer deployment.

## Per-repository issue report

### azd-reference

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#117](https://github.com/nathanmcnulty/azd-reference/issues/117) | Bind security-host operator writes to explicit tenant and Enabled subscription | Dotty-owned |
| [#118](https://github.com/nathanmcnulty/azd-reference/issues/118) | Reject false-green Pester validation and reconcile draft backlog IDs | Ready for bounded session |
| [#110](https://github.com/nathanmcnulty/azd-reference/issues/110) | Bind Maester pre-write checks and Exchange tokens to the selected tenant and Enabled subscription | Review existing draft |
| [#102](https://github.com/nathanmcnulty/azd-reference/issues/102) | Prevent Int32 overflow in deployment-validation duration reports | Review existing draft |
| [#98](https://github.com/nathanmcnulty/azd-reference/issues/98) | Adopt PowerShell 7.6 and Pester 6.2 minimums (live Azure validation needed) | Review existing draft |
| [#88](https://github.com/nathanmcnulty/azd-reference/issues/88) | Configure the dedicated read-only GitHub governance audit App | Needs stated input / prerequisite |
| [#112](https://github.com/nathanmcnulty/azd-reference/issues/112) | Investigate identity-only Flex native startup failure before qualifying REF-004 | Review existing draft |
| [#121](https://github.com/nathanmcnulty/azd-reference/issues/121) | Remove process-global evidence boundaries from overlapping hosted calls | After linked prerequisite |
| [#122](https://github.com/nathanmcnulty/azd-reference/issues/122) | Qualify in-place identity-only Flex migration and exact RBAC rollback | Native acceptance |
| [#100](https://github.com/nathanmcnulty/azd-reference/issues/100) | Coordinate canonical Foundry and security-host native qualification | Coordination |
| [#123](https://github.com/nathanmcnulty/azd-reference/issues/123) | Qualify the canonical Function security-worker lifecycle | After linked prerequisite |
| [#124](https://github.com/nathanmcnulty/azd-reference/issues/124) | Qualify the canonical Automation security-worker lifecycle | After linked prerequisite |
| [#125](https://github.com/nathanmcnulty/azd-reference/issues/125) | Qualify the canonical Logic App-to-Automation security-worker lifecycle | After linked prerequisite |
| [#126](https://github.com/nathanmcnulty/azd-reference/issues/126) | Qualify one bounded stateless Foundry Responses route and runtime role | Needs stated input / prerequisite |
| [#127](https://github.com/nathanmcnulty/azd-reference/issues/127) | Prepare a reusable immutable Caddy report-viewer component | After linked prerequisite |
| [#128](https://github.com/nathanmcnulty/azd-reference/issues/128) | Qualify the SWA Standard viewer authorization and publisher seam | Ready for bounded session |
| [#129](https://github.com/nathanmcnulty/azd-reference/issues/129) | Review two-host Caddy component adoption before promotion | After linked prerequisite |

### azd-work-in-progress

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#53](https://github.com/nathanmcnulty/azd-work-in-progress/issues/53) | Finish the supported PowerShell and Pester baseline integration | Review existing draft |
| [#65](https://github.com/nathanmcnulty/azd-work-in-progress/issues/65) | Prepare one named standalone publication packet | Needs stated input / prerequisite |
| [#36](https://github.com/nathanmcnulty/azd-work-in-progress/issues/36) | Qualify the Phase 0 read-only Intune and MDE contracts | Needs stated input / prerequisite |
| [#66](https://github.com/nathanmcnulty/azd-work-in-progress/issues/66) | Qualify the native Intune conditional-write and cross-resource contract | Needs stated input / prerequisite |
| [#55](https://github.com/nathanmcnulty/azd-work-in-progress/issues/55) | Implement the audit-only stale-safe plan/apply adapter | Needs stated input / prerequisite |
| [#35](https://github.com/nathanmcnulty/azd-work-in-progress/issues/35) | Run one populated audit-only endpoint convergence and removal pilot | Needs stated input / prerequisite |
| [#62](https://github.com/nathanmcnulty/azd-work-in-progress/issues/62) | Adopt the immutable Reference #117 target-guard correction | Needs stated input / prerequisite |
| [#67](https://github.com/nathanmcnulty/azd-work-in-progress/issues/67) | Qualify one selected ASR optional host mode | Needs stated input / prerequisite |
| [#68](https://github.com/nathanmcnulty/azd-work-in-progress/issues/68) | Qualify one selected Antivirus optional host mode | Needs stated input / prerequisite |
| [#69](https://github.com/nathanmcnulty/azd-work-in-progress/issues/69) | Qualify one selected Firewall optional host mode | Needs stated input / prerequisite |
| [#70](https://github.com/nathanmcnulty/azd-work-in-progress/issues/70) | Qualify one selected ACFB optional host mode | Needs stated input / prerequisite |
| [#71](https://github.com/nathanmcnulty/azd-work-in-progress/issues/71) | Prepare a coordinated ASR and Antivirus canary/rollback packet | Needs stated input / prerequisite |
| [#72](https://github.com/nathanmcnulty/azd-work-in-progress/issues/72) | Prepare the Firewall profile-specific canary/rollback packet | Needs stated input / prerequisite |
| [#54](https://github.com/nathanmcnulty/azd-work-in-progress/issues/54) | Split the Exchange live-acceptance umbrella into bounded children | Coordination |
| [#79](https://github.com/nathanmcnulty/azd-work-in-progress/issues/79) | Qualify one Exchange host deployment and effective permissions | Needs stated input / prerequisite |
| [#80](https://github.com/nathanmcnulty/azd-work-in-progress/issues/80) | Qualify Trace V2, Blob policy history and authenticated review | Needs stated input / prerequisite |
| [#81](https://github.com/nathanmcnulty/azd-work-in-progress/issues/81) | Qualify the disabled Exchange gate publisher and capacity contract | Needs stated input / prerequisite |
| [#82](https://github.com/nathanmcnulty/azd-work-in-progress/issues/82) | Run the enabled pilot mail-flow, expiry and rollback acceptance | Needs stated input / prerequisite |
| [#73](https://github.com/nathanmcnulty/azd-work-in-progress/issues/73) | Implement an executable owned-state restore path | Ready for bounded session |
| [#83](https://github.com/nathanmcnulty/azd-work-in-progress/issues/83) | Qualify point-in-time restore and owned cleanup | Needs stated input / prerequisite |
| [#74](https://github.com/nathanmcnulty/azd-work-in-progress/issues/74) | Implement the durable admin notification outbox | Ready for bounded session |
| [#84](https://github.com/nathanmcnulty/azd-work-in-progress/issues/84) | Verify one approved notification route | Needs stated input / prerequisite |
| [#75](https://github.com/nathanmcnulty/azd-work-in-progress/issues/75) | Implement the shared-mailbox agent evidence adapter | Ready for bounded session |
| [#76](https://github.com/nathanmcnulty/azd-work-in-progress/issues/76) | Implement the direct quarantine evidence adapter | Ready for bounded session |
| [#85](https://github.com/nathanmcnulty/azd-work-in-progress/issues/85) | Qualify the optional Foundry advisory deployment and paid invocation | Needs stated input / prerequisite |
| [#77](https://github.com/nathanmcnulty/azd-work-in-progress/issues/77) | Decide optional hunting coverage and high-volume partitioning from evidence | Deferred / upstream |
| [#78](https://github.com/nathanmcnulty/azd-work-in-progress/issues/78) | Require fresh target guards in the solution-owned Exchange operator paths | Ready for bounded session |
| [#63](https://github.com/nathanmcnulty/azd-work-in-progress/issues/63) | Coordinate selected staged hosting acceptance | Coordination |

### azd-advanced-auditing

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#21](https://github.com/nathanmcnulty/azd-advanced-auditing/issues/21) | Integrate bounded operational validation and Purview bootstrap corrections | Ready for bounded session |
| [#20](https://github.com/nathanmcnulty/azd-advanced-auditing/issues/20) | Complete the supported PowerShell and Pester baseline on the reviewed stack | After linked prerequisite |
| [#23](https://github.com/nathanmcnulty/azd-advanced-auditing/issues/23) | Bind all operator hook mutations to the approved tenant and Enabled subscription | After linked prerequisite |
| [#1](https://github.com/nathanmcnulty/azd-advanced-auditing/issues/1) | Retest Exchange and Purview on one Azure Automation host | Needs stated input / prerequisite |

### azd-auth-notifications

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#9](https://github.com/nathanmcnulty/azd-auth-notifications/issues/9) | registration and recipient delivery | Needs stated input / prerequisite |
| [#20](https://github.com/nathanmcnulty/azd-auth-notifications/issues/20) | AUTH-006 sanitized method-sample expansion | Needs stated input / prerequisite |
| [#17](https://github.com/nathanmcnulty/azd-auth-notifications/issues/17) | baseline review and integration | Review existing draft |

### azd-cloud-pc-recommendations

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#13](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/issues/13) | Qualify the read-only Cloud PC monitor from the reviewed validation draft | Needs stated input / prerequisite |

### azd-defender-reporting

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#20](https://github.com/nathanmcnulty/azd-defender-reporting/issues/20) | Integrate the .NET 10, PowerShell 7.6, and Pester 6.2 wrapper stack | Native acceptance |
| [#23](https://github.com/nathanmcnulty/azd-defender-reporting/issues/23) | Bind wrapper publication to the approved tenant and Enabled subscription | After linked prerequisite |
| [#24](https://github.com/nathanmcnulty/azd-defender-reporting/issues/24) | Qualify Function App self-contained reporting | Needs stated input / prerequisite |
| [#25](https://github.com/nathanmcnulty/azd-defender-reporting/issues/25) | Qualify Function App hosted Container App reporting | Needs stated input / prerequisite |
| [#26](https://github.com/nathanmcnulty/azd-defender-reporting/issues/26) | Qualify Azure Automation self-contained reporting | Needs stated input / prerequisite |
| [#27](https://github.com/nathanmcnulty/azd-defender-reporting/issues/27) | Qualify Azure Automation hosted Container App reporting | Needs stated input / prerequisite |

### azd-device-cleanup

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#24](https://github.com/nathanmcnulty/azd-device-cleanup/issues/24) | CLEAN-002 recovery proof | Needs stated input / prerequisite |
| [#25](https://github.com/nathanmcnulty/azd-device-cleanup/issues/25) | CLEAN-007 notification route qualification | After linked prerequisite |
| [#22](https://github.com/nathanmcnulty/azd-device-cleanup/issues/22) | baseline review and integration | Review existing draft |

### azd-device-notifications

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#47](https://github.com/nathanmcnulty/azd-device-notifications/issues/47) | DEVICE-002 recipient routes and Teams lifecycle | Needs stated input / prerequisite |
| [#42](https://github.com/nathanmcnulty/azd-device-notifications/issues/42) | baseline review and integration | Review existing draft |

### azd-emergency-access

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#32](https://github.com/nathanmcnulty/azd-emergency-access/issues/32) | EA-002 onboarding, alert routes and recovery | Needs stated input / prerequisite |
| [#27](https://github.com/nathanmcnulty/azd-emergency-access/issues/27) | hosted runtime baseline review | Review existing draft |
| [#20](https://github.com/nathanmcnulty/azd-emergency-access/issues/20) | HOL purge guard decision | Needs stated input / prerequisite |

### azd-entra-health-monitoring

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#17](https://github.com/nathanmcnulty/azd-entra-health-monitoring/issues/17) | HEALTH-004 subscription, consent and delivery | Needs stated input / prerequisite |
| [#18](https://github.com/nathanmcnulty/azd-entra-health-monitoring/issues/18) | HEALTH-006 historical callback exposure assessment | Deferred / upstream |
| [#14](https://github.com/nathanmcnulty/azd-entra-health-monitoring/issues/14) | baseline review and integration | Review existing draft |

### azd-entra-iga

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#23](https://github.com/nathanmcnulty/azd-entra-iga/issues/23) | Integrate the reviewed PowerShell prerequisite draft | Ready for bounded session |
| [#30](https://github.com/nathanmcnulty/azd-entra-iga/issues/30) | Review the staged IGA safety stack without merging it | Ready for bounded session |
| [#31](https://github.com/nathanmcnulty/azd-entra-iga/issues/31) | Decide the delegated administrator session contract | Needs stated input / prerequisite |
| [#32](https://github.com/nathanmcnulty/azd-entra-iga/issues/32) | Run the selected-profile plan, apply, retirement, and recovery pilot | Needs stated input / prerequisite |

### azd-global-secure-access

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#19](https://github.com/nathanmcnulty/azd-global-secure-access/issues/19) | Integrate the PowerShell 7.6 and Pester 6.2 baseline and retain its live gate | Native acceptance |
| [#25](https://github.com/nathanmcnulty/azd-global-secure-access/issues/25) | Integrate expected-operator Graph preflight | Ready for bounded session |
| [#27](https://github.com/nathanmcnulty/azd-global-secure-access/issues/27) | Qualify one named read-only GSA feature pilot | Needs stated input / prerequisite |

### azd-gui

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#149](https://github.com/nathanmcnulty/azd-gui/issues/149) | Adopt PowerShell 7.6 and Pester 6.2 tooling minimums | Ready for bounded session |
| [#143](https://github.com/nathanmcnulty/azd-gui/issues/143) | Complete exact-candidate Windows acceptance after human sign-in | Needs stated input / prerequisite |
| [#59](https://github.com/nathanmcnulty/azd-gui/issues/59) | Support tenant-object ownership preflight and verified adoption | After linked prerequisite |
| [#56](https://github.com/nathanmcnulty/azd-gui/issues/56) | Support conditional acknowledgements that must be accepted before deployment | Ready for bounded session |
| [#42](https://github.com/nathanmcnulty/azd-gui/issues/42) | Support conditional connections, scopes, prerequisites, and permission checks | Ready for bounded session |
| [#58](https://github.com/nathanmcnulty/azd-gui/issues/58) | Surface vendored component provenance, drift, and update status | Ready for bounded session |
| [#57](https://github.com/nathanmcnulty/azd-gui/issues/57) | Publish the manifest schema at a stable anonymously accessible URL | Needs stated input / prerequisite |
| [#55](https://github.com/nathanmcnulty/azd-gui/issues/55) | Support structured post-deployment reports and verification workflows | Ready for bounded session |
| [#41](https://github.com/nathanmcnulty/azd-gui/issues/41) | Support trusted dynamic option providers for tenant-backed template inputs | Ready for bounded session |
| [#11](https://github.com/nathanmcnulty/azd-gui/issues/11) | Track upstream glib security fix in the Tauri Linux stack | Deferred / upstream |
| [#5](https://github.com/nathanmcnulty/azd-gui/issues/5) | Evaluate remote environment backends and optional ADE compatibility | Ready for bounded session |
| [#151](https://github.com/nathanmcnulty/azd-gui/issues/151) | Design provider account transitions from the Windows multi-account trial | After linked prerequisite |
| [#152](https://github.com/nathanmcnulty/azd-gui/issues/152) | Show optional-feature recommendations from proven permission deltas and receipts | After linked prerequisite |
| [#153](https://github.com/nathanmcnulty/azd-gui/issues/153) | Prepare the exact-candidate release approval packet | After linked prerequisite |
| [#154](https://github.com/nathanmcnulty/azd-gui/issues/154) | Review and reconcile the current dependency-update PR batch | Ready for bounded session |
| [#155](https://github.com/nathanmcnulty/azd-gui/issues/155) | Add the PIM role-definition provider to the registered boundary | After linked prerequisite |
| [#156](https://github.com/nathanmcnulty/azd-gui/issues/156) | Wire conditional permission and prerequisite surfaces to the shared snapshot | After linked prerequisite |
| [#157](https://github.com/nathanmcnulty/azd-gui/issues/157) | Add trusted typed verification actions and separate verification state | After linked prerequisite |
| [#158](https://github.com/nathanmcnulty/azd-gui/issues/158) | Show remote component update availability without blocking deployment | After linked prerequisite |
| [#159](https://github.com/nathanmcnulty/azd-gui/issues/159) | Add explicitly trusted component sync from the provenance view | After linked prerequisite |
| [#160](https://github.com/nathanmcnulty/azd-gui/issues/160) | Invalidate acknowledgements when tenant-backed option results change | After linked prerequisite |
| [#161](https://github.com/nathanmcnulty/azd-gui/issues/161) | Wire one existing-object ownership verifier and explicit adoption path | After linked prerequisite |
| [#162](https://github.com/nathanmcnulty/azd-gui/issues/162) | Qualify the PIM option provider in one verified tenant | After linked prerequisite |

### azd-maester

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#2](https://github.com/nathanmcnulty/azd-maester/issues/2) | Coordinate drift in the canonical standalone hosts | Coordination |
| [#4](https://github.com/nathanmcnulty/azd-maester/issues/4) | Coordinate SWA in the canonical standalone hosts | Coordination |
| [#5](https://github.com/nathanmcnulty/azd-maester/issues/5) | Coordinate Caddy in the canonical standalone hosts | Coordination |
| [#8](https://github.com/nathanmcnulty/azd-maester/issues/8) | Coordinate custom tests in the canonical standalone hosts | Coordination |
| [#12](https://github.com/nathanmcnulty/azd-maester/issues/12) | Azure DevOps Solution - postprovision fails to push to empty repository | Review existing draft |
| [#13](https://github.com/nathanmcnulty/azd-maester/issues/13) | Azure DevOps solution - Null Path Binding error in manual fallback instructions | Review existing draft |
| [#14](https://github.com/nathanmcnulty/azd-maester/issues/14) | Azure DevOps Solution - Interactive Wizard - Security Group Validation | Review existing draft |
| [#15](https://github.com/nathanmcnulty/azd-maester/issues/15) | Azure DevOps solution - Authentication Sync between az and azd | Review existing draft |
| [#36](https://github.com/nathanmcnulty/azd-maester/issues/36) | Move hosted PowerShell runtimes from .NET 8 to .NET 10 LTS (live Azure validation needed) | Review existing draft |

### azd-maester-azureautomation

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#30](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/30) | Adopt canonical tenant and Enabled-subscription guards across deployment entrypoints | Review existing draft |
| [#32](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/32) | Add opt-in runtime-only validation to the maintained runbook | Ready for bounded session |
| [#33](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/33) | Reconcile reviewed host draft stacks into one validation candidate | After linked prerequisite |
| [#34](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/34) | Qualify one Automation assessment and existing report-webapp lifecycle | Native acceptance |
| [#35](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/35) | Implement approved default-off custom-test packages for this host | After linked prerequisite |
| [#36](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/36) | Integrate the optional immutable Caddy report viewer | After linked prerequisite |
| [#37](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/37) | Integrate the optional SWA Standard report viewer | After linked prerequisite |
| [#38](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/38) | Implement approved data-only drift inputs for this host | After linked prerequisite |
| [#39](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/39) | Qualify one Caddy viewer audience and lifecycle | After linked prerequisite |
| [#40](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/40) | Qualify one SWA Standard viewer audience and lifecycle | After linked prerequisite |
| [#41](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/41) | Qualify one approved custom-test package on the native host | After linked prerequisite |
| [#42](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/42) | Qualify approved data-only drift on the native host | After linked prerequisite |
| [#24](https://github.com/nathanmcnulty/azd-maester-azureautomation/issues/24) | Complete the remaining single-cell runtime baseline acceptance | Native acceptance |

### azd-maester-azuredevops

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#23](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/23) | Adopt PowerShell 7.6 and Pester 6.2 minimums | Review existing draft |
| [#27](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/27) | Adopt canonical tenant and Enabled-subscription guards across deployment entrypoints | Review existing draft |
| [#29](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/29) | Reconcile reviewed host draft stacks into one validation candidate | After linked prerequisite |
| [#30](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/30) | Qualify one Azure DevOps assessment and existing report-webapp lifecycle | Native acceptance |
| [#31](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/31) | Implement approved default-off custom-test packages for this host | After linked prerequisite |
| [#32](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/32) | Qualify optional approved drift on the native host | Native acceptance |
| [#33](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/33) | Reproduce selected-account az and azd authentication synchronization | Needs stated input / prerequisite |
| [#34](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/34) | Qualify empty-repository provisioning against Azure DevOps | Needs stated input / prerequisite |
| [#35](https://github.com/nathanmcnulty/azd-maester-azuredevops/issues/35) | Qualify one approved custom-test package on the native host | After linked prerequisite |

### azd-maester-containerappjob

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#33](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/33) | Run non-ACR Container App Jobs on PowerShell 7.6 and .NET 10 | Review existing draft |
| [#34](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/34) | Adopt canonical tenant and Enabled-subscription guards across deployment entrypoints | Review existing draft |
| [#38](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/38) | Guard direct runtime file publication with explicit target and fresh Enabled state | Ready for bounded session |
| [#39](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/39) | Reconcile reviewed host draft stacks into one validation candidate | After linked prerequisite |
| [#40](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/40) | Qualify one Container Apps Job assessment and existing report-webapp lifecycle | Native acceptance |
| [#41](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/41) | Implement approved default-off custom-test packages for this host | After linked prerequisite |
| [#42](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/42) | Integrate the optional immutable Caddy report viewer | After linked prerequisite |
| [#43](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/43) | Integrate the optional SWA Standard report viewer | After linked prerequisite |
| [#44](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/44) | Qualify optional approved drift on the native host | Native acceptance |
| [#45](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/45) | Qualify one Caddy viewer audience and lifecycle | After linked prerequisite |
| [#46](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/46) | Qualify one SWA Standard viewer audience and lifecycle | After linked prerequisite |
| [#47](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/47) | Qualify one approved custom-test package on the native host | After linked prerequisite |
| [#26](https://github.com/nathanmcnulty/azd-maester-containerappjob/issues/26) | Complete the remaining single-cell runtime baseline acceptance | Native acceptance |

### azd-maester-functionapp

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#30](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/30) | Adopt fresh target guards and close direct ZIP and Exchange context bypasses | Review existing draft |
| [#33](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/33) | Reconcile reviewed host draft stacks into one validation candidate | After linked prerequisite |
| [#34](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/34) | Qualify one Function App assessment and existing report-webapp lifecycle | Native acceptance |
| [#35](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/35) | Implement approved default-off custom-test packages for this host | After linked prerequisite |
| [#36](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/36) | Integrate the optional immutable Caddy report viewer | After linked prerequisite |
| [#37](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/37) | Integrate the optional SWA Standard report viewer | After linked prerequisite |
| [#38](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/38) | Implement approved data-only drift inputs for this host | After linked prerequisite |
| [#39](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/39) | Qualify one Caddy viewer audience and lifecycle | After linked prerequisite |
| [#40](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/40) | Qualify one SWA Standard viewer audience and lifecycle | After linked prerequisite |
| [#41](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/41) | Qualify one approved custom-test package on the native host | After linked prerequisite |
| [#42](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/42) | Qualify approved data-only drift on the native host | After linked prerequisite |
| [#26](https://github.com/nathanmcnulty/azd-maester-functionapp/issues/26) | Complete the remaining single-cell runtime baseline acceptance | Native acceptance |

### azd-myworkid

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#53](https://github.com/nathanmcnulty/azd-myworkid/issues/53) | Deferred: preserve local candidates and resume only after upstream readiness | Deferred / upstream |

### azd-pim

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#25](https://github.com/nathanmcnulty/azd-pim/issues/25) | PIM-002 selected-role pilot | Needs stated input / prerequisite |
| [#21](https://github.com/nathanmcnulty/azd-pim/issues/21) | baseline review and integration | Review existing draft |

### azd-risk-based-ca

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#29](https://github.com/nathanmcnulty/azd-risk-based-ca/issues/29) | RISK-002 report-only canary and rollback | Needs stated input / prerequisite |
| [#27](https://github.com/nathanmcnulty/azd-risk-based-ca/issues/27) | baseline review and integration | Review existing draft |

### azd-santa

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#29](https://github.com/nathanmcnulty/azd-santa/issues/29) | Complete the PowerShell 7.6 and Pester 6.2 baseline | Ready for bounded session |
| [#32](https://github.com/nathanmcnulty/azd-santa/issues/32) | Review deterministic Santa candidates and sync-profile guidance | Ready for bounded session |
| [#33](https://github.com/nathanmcnulty/azd-santa/issues/33) | Close the one-device Monitor and selected-sync native evidence gate | Needs stated input / prerequisite |

### azd-sysmon

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#27](https://github.com/nathanmcnulty/azd-sysmon/issues/27) | SYS-002/SYS-003 disposable Windows qualification | Native acceptance |
| [#28](https://github.com/nathanmcnulty/azd-sysmon/issues/28) | SYS-004/SYS-005 service publication qualification | Native acceptance |
| [#29](https://github.com/nathanmcnulty/azd-sysmon/issues/29) | SYS-006/SYS-007/SYS-008 disposable tenant canary and recovery | Needs stated input / prerequisite |
| [#18](https://github.com/nathanmcnulty/azd-sysmon/issues/18) | baseline ownership and checks review | Review existing draft |
| [#24](https://github.com/nathanmcnulty/azd-sysmon/issues/24) | AMA metadata-handle fix review | Review existing draft |

### azd-verified-id

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#13](https://github.com/nathanmcnulty/azd-verified-id/issues/13) | Integrate the supported authoring and validation baseline | Ready for bounded session |
| [#15](https://github.com/nathanmcnulty/azd-verified-id/issues/15) | Qualify domain, authority, issuance, presentation, resume, and cleanup | Needs stated input / prerequisite |

### azd-website

| Issue | One-session deliverable | Next gate |
| --- | --- | --- |
| [#73](https://github.com/nathanmcnulty/azd-website/issues/73) | Review the catalog source-contract draft | Ready for bounded session |
| [#74](https://github.com/nathanmcnulty/azd-website/issues/74) | Decide and implement opt-in public validation summaries | Needs stated input / prerequisite |
| [#53](https://github.com/nathanmcnulty/azd-website/issues/53) | Refresh the grouped dependency reachability record | Deferred / upstream |

## Specific inputs and decisions still needed

- Native endpoint/canary work: exact disposable devices/groups, policy/role targets, recovery owner and allowed changes. Do not infer these from the approved Azure subscription.
- Recipient and Teams tests: the selected route, recipient, catalog/installation owner and any required human consent/sign-in. Existing audience candidates remain in the private session evidence; verify them before use.
- Azure DevOps: selected organization/project/service connection and provider-specific traces; local Git tests did not reproduce the empty-repository service failure.
- Verified ID and optional inference: approved domain/authority/credential flow or model/project/version, explicit call/cost/retention limits and ownership-aware cleanup.
- Governance/schema/publication: dedicated read-only GitHub App setup, public schema hosting authority, and separate exact-candidate or named-solution release/promotion approval.

## Deferred and excluded work

MyWorkID remains explicitly deferred pending upstream readiness and an owner resume decision. Its single issue preserves the existing candidates/local-work gate; no source review, testing or deployment was restarted. The retired azd-nathanmcnulty project is excluded; it was absent from the current repository listing and no issue could be filed there. Meaningful shared improvements remain directed to azd-reference.

## Inventory validation

Read-only GitHub inventory captured main commits, open issues and exact draft heads. Parallel bounded reviewers checked the proposed streams; corrections split broad scopes, preserved completed work and removed unnecessary reruns. The issue writer resolved internal dependencies to actual URLs before publishing, preserved existing titles/content, and verified each changed issue by fresh readback. No Azure operations, credentials, source feature changes, merges, releases or catalog enforcement changes were performed by this inventory.