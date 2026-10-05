# Portfolio backlog preparation and reconciliation

Prepared 3 October and reconciled 4 October 2026. This is an aggregate review view of repository-local backlogs, not a second task database. Regenerate counts and links from `docs/backlog.json`; update task status only in the owning repository. The proposed order favors reliability and deployment readiness before new capabilities. No feature implementation, tenant deployment, delivery, release, merge, cleanup or required-check change is authorized by this report.

Coverage: 25 current GitHub `nathanmcnulty/azd-*` repositories and five staged solutions. The refreshed aggregate has 206 records: 5 ready, 126 proposed and 75 done. Tracking for all 25 repositories and the existing staged App Control solution is reconciled on main; four unpublished staged solutions retain owner snapshots. Reference REF-002 is included as done in the report/CI-pilot packet, contingent on that packet passing hosted validation before merge. Done includes bounded source reconciliation and previously implemented fixes, not 75 newly delivered features. The initial preparation had 202 records: 31 ready, 152 proposed and 19 done. All 30 AZD issues open at initial capture are linked in task sources, with 15 then-open PRs recorded for reconciliation. Execution reconciliation added 28 further open-report candidates and confirmed Device Cleanup PR #10 and staged App Control PR #32 as merged. The earlier read-only refresh recorded Health issue #6 / PR #8 as resolved at c2c63371ec182060b0e7e24f534e37e62c84d84e; it remains a completed record, with a separate historical-exposure assessment candidate. These GitHub search results are a dated snapshot, not a guarantee about changes after capture.

`azd-nathanmcnulty` was retired on 4 October 2026 after maintainer approval. Its complete Git history and local files are archived; its two coordination-only records are excluded from this active aggregate. Portfolio coordination is owned by azd-reference. See the [retirement record](portfolio-execution.md#portfolio-coordination-stub-retirement). `AZD-for-beginners` is Microsoft-owned and excluded. Duplicate acceptance/build worktrees are not independent portfolio repositories. The legacy staged `azd-pim` copy is preserved and excluded from a competing implementation backlog pending history/owner reconciliation.

[Execution record](portfolio-execution.md) tracks selected owners, completed review packets, validation and verified lab cleanup.

## One tracking model

- `BACKLOG.md` is the discoverable entry point in every selected checkout/solution.
- `docs/backlog.json` is canonical; `docs/backlog.md` is its generated review view.
- [The standard](../standards/agent-backlogs.md) and [schema](../schemas/backlog.schema.json) live in azd-reference.
- Stable item IDs, bounded scope, acceptance, validation, dependencies, source links, authorization and evidence travel with each task.
- Existing TODO/roadmap/execution documents retain design and historical evidence. The Auth Notifications roadmap and Device Cleanup/Sysmon TODO files now point at the new task tracker.
- Proposed means unselected. Ready items are only read-only/local reconciliation. The user subsequently authorized coordinated implementation and necessary lab testing with cleanup; that session authorization is recorded separately from this report. Claims must be serialized by the coordinator before dispatch.

## Focused push order

| Wave | Purpose | Current records | Exit gate |
| --- | --- | ---: | --- |
| 0 | Reconcile current source, issue/PR state and active owners | 65 | Actual offline commands and remaining work verified; no duplicate owner |
| 1 | Fix failure/secret boundaries and shared tracking/provenance gaps | 51 | Focused regressions pass; component decisions use exact hashes |
| 2 | Validate selected deployment paths and improve bounded operational behavior | 52 | Current-source service and human/endpoint evidence retained for authorized targets |
| 3 | Add selected new capabilities and optional components | 35 | Narrow design accepted; permission additions, rollout and rollback are explicit |
| 4 | Release/promotion packets | 3 | Named publication approval plus verified source/artifacts; cleanup separately authorized |

## Next focused packets

The source fixes and tracking/component integrations below are complete on main;
do not redispatch them from an old preparation checkout. Device Cleanup's cap is
already implemented with regression coverage, as are the reconciled Maester
failure semantics, Health callback source fix and staged App Control DoD mapping.
The active local staging branch can still predate the main mapping correction.

Select one bounded proposed item after checking current source, dependencies and
the active owner. Suitable engineering work without a new rollout decision is
Website WEB-004 dependency assessment, Health HEALTH-003 offline receiver/lifecycle
fixtures and HEALTH-006 value-safe historical assessment, then compatible optional
component qualification. Four unpublished endpoint-security source baselines and
Reference permission/security-component proposals require exact comparison of
preserved owner histories before integration. They do not require inventing a product decision.

Reserve live GUI/Mac/endpoint/recipient acceptance and publication/enforcement
decisions for the explicit gates in the [current reconciliation record](portfolio-execution.md#current-main-reconciliation).
Use at most three implementation owners and an independent exact-diff reviewer;
retain one owner per mutable worktree and the coordinator's integration claim.

## Repository backlogs

| Repository / solution | Records | Next local starting point |
| --- | ---: | --- |
| [azd-advanced-auditing](https://github.com/nathanmcnulty/azd-advanced-auditing/blob/main/docs/backlog.md) | 6 | AUD-002: Prepare and execute the supported Exchange/Purview compatibility retest |
| [azd-auth-notifications](https://github.com/nathanmcnulty/azd-auth-notifications/blob/main/docs/backlog.md) | 10 | AUTH-008: Evaluate the optional shared Flex poller host |
| [azd-cloud-pc-recommendations](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/blob/main/docs/backlog.md) | 5 | CPC-004: Evaluate shared notification and deployment contracts |
| [azd-defender-reporting](https://github.com/nathanmcnulty/azd-defender-reporting/blob/main/docs/backlog.md) | 4 | REPORT-002: Qualify the locked compute and hosted-surface deployment matrix |
| [azd-device-cleanup](https://github.com/nathanmcnulty/azd-device-cleanup/blob/main/docs/backlog.md) | 11 | CLEAN-002: Prove recovery before expanding disable or deletion scope |
| [azd-device-notifications](https://github.com/nathanmcnulty/azd-device-notifications/blob/main/docs/backlog.md) | 5 | DEVICE-003: Compare retry/ambiguity taxonomy with authentication notifications |
| [azd-emergency-access](https://github.com/nathanmcnulty/azd-emergency-access/blob/main/docs/backlog.md) | 5 | EA-002: Qualify onboarding, alert routes and independent recovery drill |
| [azd-entra-health-monitoring](https://github.com/nathanmcnulty/azd-entra-health-monitoring/blob/main/docs/backlog.md) | 6 | HEALTH-003: Use secret, stable clientState with lifecycle behavior tests |
| [azd-entra-iga](https://github.com/nathanmcnulty/azd-entra-iga/blob/main/docs/backlog.md) | 6 | IGA-004: Reconcile unlocked delegated-Graph vendoring with canonical lock adoption |
| [azd-global-secure-access](https://github.com/nathanmcnulty/azd-global-secure-access/blob/main/docs/backlog.md) | 4 | GSA-002: Qualify the read-only readiness and exact-feature pilot |
| [azd-gui](https://github.com/nathanmcnulty/azd-gui/blob/main/docs/backlog.md) | 16 | GUI-002: Complete exact-candidate Windows 11 human acceptance |
| [azd-maester](https://github.com/nathanmcnulty/azd-maester/blob/main/docs/backlog.md) | 8 | MCAT-002: Make standalone migration and remaining catalog support explicit |
| [azd-maester-azureautomation](https://github.com/nathanmcnulty/azd-maester-azureautomation/blob/main/docs/backlog.md) | 5 | MAUTO-003: Reconcile shared hook/webapp versions and host permission deltas |
| [azd-maester-azuredevops](https://github.com/nathanmcnulty/azd-maester-azuredevops/blob/main/docs/backlog.md) | 9 | MADO-005: Azure DevOps solution - Authentication Sync between az and azd |
| [azd-maester-containerappjob](https://github.com/nathanmcnulty/azd-maester-containerappjob/blob/main/docs/backlog.md) | 6 | MCAJ-003: Reconcile shared hook/webapp versions and host permission deltas |
| [azd-maester-functionapp](https://github.com/nathanmcnulty/azd-maester-functionapp/blob/main/docs/backlog.md) | 6 | MFUNC-003: Reconcile shared hook/webapp versions and host permission deltas |
| [azd-myworkid](https://github.com/nathanmcnulty/azd-myworkid/blob/main/docs/backlog.md) | 5 | MWID-002: Qualify package, domain, authentication-context and optional Verified ID paths |
| [azd-pim](https://github.com/nathanmcnulty/azd-pim/blob/main/docs/backlog.md) | 6 | PIM-002: Qualify a selected-role authentication and notification pilot |
| [azd-reference](https://github.com/nathanmcnulty/azd-reference/blob/main/docs/backlog.md) | 8 | REF-004: Qualify identity-only Flex host storage before widening adoption |
| [azd-risk-based-ca](https://github.com/nathanmcnulty/azd-risk-based-ca/blob/main/docs/backlog.md) | 5 | RISK-002: Qualify report-only canary, routes and migration rollback |
| [azd-santa](https://github.com/nathanmcnulty/azd-santa/blob/main/docs/backlog.md) | 6 | SANTA-006: Evaluate delegated Graph session coordinator for Intune publishing |
| [azd-sysmon](https://github.com/nathanmcnulty/azd-sysmon/blob/main/docs/backlog.md) | 23 | SYS-010: Add a manual Windows integration workflow that runs only with explicitly supplied disposable Azure, Graph, Intune, and Sentinel targets |
| [azd-verified-id](https://github.com/nathanmcnulty/azd-verified-id/blob/main/docs/backlog.md) | 6 | VID-002: Qualify DNS/domain verification, issuance and presentation |
| [azd-website](https://github.com/nathanmcnulty/azd-website/blob/main/docs/backlog.md) | 4 | WEB-004: Triage affected build and deploy dependencies with explicit reachability evidence |
| [azd-work-in-progress](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/docs/backlog.md) | 5 | STAGE-004: Integrate the reviewed Firewall pagination fix after source-owner handoff |
| [azd-work-in-progress/azd-app-control](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-app-control/docs/backlog.md) | 4 | APP0-003: Reconcile the old Phase 0 architecture with the newer App Control product |
| azd-work-in-progress/azd-app-control-for-business | 7 | ACFB-001: Reconcile this backlog with current source and active work (owner snapshot) |
| azd-work-in-progress/azd-defender-asr-rules | 5 | ASR-001: Reconcile this backlog with current source and active work (owner snapshot) |
| azd-work-in-progress/azd-defender-av-exclusions | 5 | AV-001: Reconcile this backlog with current source and active work (owner snapshot) |
| azd-work-in-progress/azd-defender-firewall | 5 | FW-001: Reconcile this backlog with current source and active work (owner snapshot) |

## Component opportunities

[Per-repository component decisions](component-opportunities.md) distinguish existing adoption, compatible proposals and deferred extraction. The strongest near-term opportunities are stable deployment-validation, portable notification contracts, delegated Graph coordination in compatible PowerShell flows, and the existing Maester hook/report modules. Flex hosting needs identity/storage compatibility first; candidate deployment receipts do not replace domain or real-endpoint evidence.

The historical review captured security-automation host/runtime proposals on a separate owner branch at 9ed4c575cc057a4a96c05ce91c7dd9b7694da7b7. Neither component is in the main snapshot used for this backlog integration; their code remains with the active owner. The three staged Defender engines and optional host/bundle adapters remain on preserved source branches; they were not imported by this tracking reconciliation. Qualify exact component pins, host/engine boundaries, independent identities and lifecycle evidence before adoption or deployment; local pilot labels alone do not establish published support.

## Selection, validation and handoff

From PowerShell, use reviewed current-main checkouts plus explicitly declared unpublished owner roots. Canonical dirty checkouts may retain older tracking/source snapshots; inspect their provenance before selecting work. Discover only the declared backlog roots and pass the full set when resolving cross-repository dependencies:

```powershell
$backlogPaths = @(
  Get-ChildItem E:/ -Directory -Filter azd-* | ForEach-Object {
    $candidate = Join-Path $_.FullName "docs/backlog.json"
    if (Test-Path -LiteralPath $candidate) { $candidate }
  }
  Get-ChildItem E:/azd-work-in-progress -Directory -Filter azd-* | ForEach-Object {
    $candidate = Join-Path $_.FullName "docs/backlog.json"
    if (Test-Path -LiteralPath $candidate) { $candidate }
  }
)
& E:/azd-reference/tooling/Test-AzdBacklog.ps1 -Paths $backlogPaths
& E:/azd-reference/tooling/Get-AzdBacklogStatus.ps1 -Paths $backlogPaths -ReadyOnly
# Filter an aggregate view without changing task state:
& E:/azd-reference/tooling/Get-AzdBacklogStatus.ps1 -Paths $backlogPaths |
  Where-Object { $_.wave -eq 1 -and $_.priority -in "P0", "P1" }
```

For a selected item use a prompt that names its exact boundary:

```text
Read BACKLOG.md and the applicable instructions in <repository>. Select <item-id>
from docs/backlog.json for local implementation only after checking its current
source, dependencies and active owner. Reconcile any changed scope first. Record
the owner, exact base commit and one worktree in the coordinator-owned claim.
Preserve unrelated work, implement only its scope, run its validation, and record
acceptance evidence. Report blocked gates explicitly. This task does not authorize
deployment, permission grants, sends, publication, merges or cleanup.
```

For live-validation tasks, use the session authorization for necessary lab validation and cleanup; additional recipient, endpoint, policy or publication targets still need to be named where acceptance requires them. Their principal authorization class is descriptive; the acceptance and validation gates can require additional independent permissions. Never infer approval from a status, successful CI, catalog metadata or a proposed wave.

## Preparation limits and preservation

- GitHub issues were inventoried and linked; most historical reports still require current-source reproduction before fixing. Health callback and legacy DoD mapping were checked directly in the current local source.
- Most solution checkouts are on active permission-tracking branches. Function App has active packaging/validation changes; PIM has active vendor/line-ending changes; staging has three active Defender builders. Backlog preparation preserves that work.
- Source revisions describe local snapshot provenance, not a promise that the remote default branch matches the checkout or that a test passed on current source.
- All original Sysmon unchecked items and all six Device Cleanup follow-ups are retained as bounded records. Existing GUI and App Control execution plans remain evidence/design sources; no historical release or endpoint gate was reset. HEALTH-002 and REF-003 are completed source/local-tool records with evidence, not live deployment passes.
- Local backlog/schema/tool validation does not prove Azure deployment, human-visible notification, endpoint convergence or release readiness.
- Preparation itself was local. The subsequent authorized reconciliation committed, pushed, reviewed and merged the named packets recorded in portfolio-execution.md. No releases, permission grants or required-check changes were made by that reconciliation.
