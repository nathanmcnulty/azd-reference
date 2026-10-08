# Portfolio backlog preparation and reconciliation

Prepared 3 October and refreshed from fetched default branches on 7 October 2026. This is an aggregate review view of repository-local backlogs, not a second task database. Regenerate counts and links from `docs/backlog.json`; update task status only in the owning repository. The proposed order favors reliability and deployment readiness before new capabilities. No feature implementation, tenant deployment, delivery, release, merge, cleanup or required-check change is authorized by this report.

Coverage: 25 GitHub `nathanmcnulty/azd-*` repositories and five staged solutions, totaling 30 backlog roots. The exact default-branch revisions linked below have 212 records: 104 done and 108 proposed, with no ready, in-progress, blocked or deferred records in that snapshot. Of the proposed records, 75 are local-only; that classification does not establish satisfied dependencies, readiness or approval. All 30 backlogs passed the canonical schema and cross-repository dependency validator. The snapshot excludes newer working-tree claims, including the current CLEAN-006 implementation, and is not an atomic portfolio revision.

Done includes bounded source reconciliation and previously implemented fixes, not 104 newly delivered features or live acceptance passes. The initial preparation had 202 records: 31 ready, 152 proposed and 19 done. The earlier 206-record review and later 210-record execution counts are historical snapshots. All 30 AZD issues open at initial capture were linked in task sources, with 15 then-open PRs recorded for reconciliation; those issue/PR inventory numbers have not been refreshed here. See the execution record for reviewed publication and validation evidence.

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
| 0 | Reconcile current source, issue/PR state and active owners | 66 | Actual offline commands and remaining work verified; no duplicate owner |
| 1 | Fix failure/secret boundaries and shared tracking/provenance gaps | 56 | Focused regressions pass; component decisions use exact hashes |
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
the active owner. CLEAN-006 primary-user archive indexing is being implemented in
an isolated worktree from Device Cleanup `c7b3e6e`; it is not complete in this
snapshot and must not receive a second implementation owner. HEALTH-003 fixtures,
WEB-004 dependency assessment, DEVICE-003 taxonomy and the Maester component
adoptions are already done in their source backlogs. HEALTH-006 remains proposed
with explicit historical-exposure gaps. Other ordinary engineering proposals
remain selectable without inventing a rollout decision; consult the owning
backlog rather than redispatching an old next-task label.

Reserve live GUI/Mac/endpoint/recipient acceptance and publication/enforcement
decisions for the explicit gates in the [current reconciliation record](portfolio-execution.md#current-main-reconciliation).
Use at most three implementation owners and an independent exact-diff reviewer;
retain one owner per mutable worktree and the coordinator's integration claim.

## Repository backlogs

| Repository / solution | Records | Done | Proposed | Reviewed source |
| --- | ---: | ---: | ---: | --- |
| [azd-advanced-auditing](https://github.com/nathanmcnulty/azd-advanced-auditing/blob/main/docs/backlog.md) | 6 | 4 | 2 | [edd48cd5ac38](https://github.com/nathanmcnulty/azd-advanced-auditing/blob/edd48cd5ac3866b13ddbe3640ae6181b7871975c/docs/backlog.json) |
| [azd-auth-notifications](https://github.com/nathanmcnulty/azd-auth-notifications/blob/main/docs/backlog.md) | 10 | 5 | 5 | [016a9ded4b97](https://github.com/nathanmcnulty/azd-auth-notifications/blob/016a9ded4b9777c95a975b271fb678a8d84ef615/docs/backlog.json) |
| [azd-cloud-pc-recommendations](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/blob/main/docs/backlog.md) | 5 | 2 | 3 | [f035b101ebe9](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/blob/f035b101ebe9c5928dae058ad871979a23b56e1e/docs/backlog.json) |
| [azd-defender-reporting](https://github.com/nathanmcnulty/azd-defender-reporting/blob/main/docs/backlog.md) | 4 | 2 | 2 | [8f258252417c](https://github.com/nathanmcnulty/azd-defender-reporting/blob/8f258252417cb9f675a8b1ec3a8649582bdca91c/docs/backlog.json) |
| [azd-device-cleanup](https://github.com/nathanmcnulty/azd-device-cleanup/blob/main/docs/backlog.md) | 13 | 7 | 6 | [c7b3e6eaa2a7](https://github.com/nathanmcnulty/azd-device-cleanup/blob/c7b3e6eaa2a76722fc45c61b95084c41f93bab24/docs/backlog.json) |
| [azd-device-notifications](https://github.com/nathanmcnulty/azd-device-notifications/blob/main/docs/backlog.md) | 5 | 4 | 1 | [6774c6509ea3](https://github.com/nathanmcnulty/azd-device-notifications/blob/6774c6509ea34388b61ce24eee025264dcee08d7/docs/backlog.json) |
| [azd-emergency-access](https://github.com/nathanmcnulty/azd-emergency-access/blob/main/docs/backlog.md) | 5 | 2 | 3 | [15a39144529f](https://github.com/nathanmcnulty/azd-emergency-access/blob/15a39144529f48faa7628a8dd02e3f8750879dcc/docs/backlog.json) |
| [azd-entra-health-monitoring](https://github.com/nathanmcnulty/azd-entra-health-monitoring/blob/main/docs/backlog.md) | 6 | 3 | 3 | [b5e3a57db7f2](https://github.com/nathanmcnulty/azd-entra-health-monitoring/blob/b5e3a57db7f20c49d01f4dcf52a0bed6801bdf94/docs/backlog.json) |
| [azd-entra-iga](https://github.com/nathanmcnulty/azd-entra-iga/blob/main/docs/backlog.md) | 6 | 3 | 3 | [91aa2cf45321](https://github.com/nathanmcnulty/azd-entra-iga/blob/91aa2cf45321983d282091109e9c7932797b03c2/docs/backlog.json) |
| [azd-global-secure-access](https://github.com/nathanmcnulty/azd-global-secure-access/blob/main/docs/backlog.md) | 4 | 2 | 2 | [2f153eb8e04f](https://github.com/nathanmcnulty/azd-global-secure-access/blob/2f153eb8e04f1cc0c7ac9f446e9b293fce94ff13/docs/backlog.json) |
| [azd-gui](https://github.com/nathanmcnulty/azd-gui/blob/main/docs/backlog.md) | 16 | 3 | 13 | [6432d90be206](https://github.com/nathanmcnulty/azd-gui/blob/6432d90be206aff52e053b70b2a92a1bb014c77f/docs/backlog.json) |
| [azd-maester](https://github.com/nathanmcnulty/azd-maester/blob/main/docs/backlog.md) | 8 | 4 | 4 | [d232b49e5d72](https://github.com/nathanmcnulty/azd-maester/blob/d232b49e5d727cb8427004bd798dcd6385ddedfe/docs/backlog.json) |
| [azd-maester-azureautomation](https://github.com/nathanmcnulty/azd-maester-azureautomation/blob/main/docs/backlog.md) | 5 | 4 | 1 | [e3fce00620e1](https://github.com/nathanmcnulty/azd-maester-azureautomation/blob/e3fce00620e147fef4ae210007af923d9ad78ef4/docs/backlog.json) |
| [azd-maester-azuredevops](https://github.com/nathanmcnulty/azd-maester-azuredevops/blob/main/docs/backlog.md) | 9 | 6 | 3 | [76ac648c7172](https://github.com/nathanmcnulty/azd-maester-azuredevops/blob/76ac648c7172981a22259f6d6fd701c2a085cb57/docs/backlog.json) |
| [azd-maester-containerappjob](https://github.com/nathanmcnulty/azd-maester-containerappjob/blob/main/docs/backlog.md) | 6 | 5 | 1 | [215d7bb70359](https://github.com/nathanmcnulty/azd-maester-containerappjob/blob/215d7bb703595ed460c9132014a6b9c5c503ace8/docs/backlog.json) |
| [azd-maester-functionapp](https://github.com/nathanmcnulty/azd-maester-functionapp/blob/main/docs/backlog.md) | 6 | 5 | 1 | [0c7462e942ac](https://github.com/nathanmcnulty/azd-maester-functionapp/blob/0c7462e942ac4d8b5bd4b8ac5a51d5fba7a6d94d/docs/backlog.json) |
| [azd-myworkid](https://github.com/nathanmcnulty/azd-myworkid/blob/main/docs/backlog.md) | 5 | 3 | 2 | [6b4f53868973](https://github.com/nathanmcnulty/azd-myworkid/blob/6b4f538689731a2bb8e90061f44929466fcaac2b/docs/backlog.json) |
| [azd-pim](https://github.com/nathanmcnulty/azd-pim/blob/main/docs/backlog.md) | 6 | 4 | 2 | [4c6ddfdb1cc0](https://github.com/nathanmcnulty/azd-pim/blob/4c6ddfdb1cc0d5f30c9cac817a259decd181cc31/docs/backlog.json) |
| [azd-reference](https://github.com/nathanmcnulty/azd-reference/blob/main/docs/backlog.md) | 12 | 10 | 2 | [5fc4bd7e952b](https://github.com/nathanmcnulty/azd-reference/blob/5fc4bd7e952b6ec0a2d39b6d03098b21d7acb2f4/docs/backlog.json) |
| [azd-risk-based-ca](https://github.com/nathanmcnulty/azd-risk-based-ca/blob/main/docs/backlog.md) | 5 | 3 | 2 | [1028ba8f0fba](https://github.com/nathanmcnulty/azd-risk-based-ca/blob/1028ba8f0fbaacd9c7d09807c36cf4e9207a1e3d/docs/backlog.json) |
| [azd-santa](https://github.com/nathanmcnulty/azd-santa/blob/main/docs/backlog.md) | 6 | 1 | 5 | [82c17ed961fa](https://github.com/nathanmcnulty/azd-santa/blob/82c17ed961fad5f38499f8b212a2889ece249b97/docs/backlog.json) |
| [azd-sysmon](https://github.com/nathanmcnulty/azd-sysmon/blob/main/docs/backlog.md) | 23 | 6 | 17 | [1d59a4381212](https://github.com/nathanmcnulty/azd-sysmon/blob/1d59a4381212900796d7f3bfaaf94d35a840a1e3/docs/backlog.json) |
| [azd-verified-id](https://github.com/nathanmcnulty/azd-verified-id/blob/main/docs/backlog.md) | 6 | 4 | 2 | [4d34f9a1c87c](https://github.com/nathanmcnulty/azd-verified-id/blob/4d34f9a1c87c948190bd188fd2aa97d7ca58798b/docs/backlog.json) |
| [azd-website](https://github.com/nathanmcnulty/azd-website/blob/main/docs/backlog.md) | 4 | 2 | 2 | [a6b63f8ba2cb](https://github.com/nathanmcnulty/azd-website/blob/a6b63f8ba2cb4e394d922a9b3f7c1db06e6875c9/docs/backlog.json) |
| [azd-work-in-progress](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/docs/backlog.md) | 5 | 3 | 2 | [cd455be45e62](https://github.com/nathanmcnulty/azd-work-in-progress/blob/cd455be45e620cd07d662ac1bfa206094317e751/docs/backlog.json) |
| [azd-work-in-progress/azd-app-control](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-app-control/docs/backlog.md) | 4 | 3 | 1 | [cd455be45e62](https://github.com/nathanmcnulty/azd-work-in-progress/blob/cd455be45e620cd07d662ac1bfa206094317e751/azd-app-control/docs/backlog.json) |
| [azd-work-in-progress/azd-app-control-for-business](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-app-control-for-business/docs/backlog.md) | 7 | 1 | 6 | [cd455be45e62](https://github.com/nathanmcnulty/azd-work-in-progress/blob/cd455be45e620cd07d662ac1bfa206094317e751/azd-app-control-for-business/docs/backlog.json) |
| [azd-work-in-progress/azd-defender-asr-rules](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-defender-asr-rules/docs/backlog.md) | 5 | 1 | 4 | [cd455be45e62](https://github.com/nathanmcnulty/azd-work-in-progress/blob/cd455be45e620cd07d662ac1bfa206094317e751/azd-defender-asr-rules/docs/backlog.json) |
| [azd-work-in-progress/azd-defender-av-exclusions](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-defender-av-exclusions/docs/backlog.md) | 5 | 1 | 4 | [cd455be45e62](https://github.com/nathanmcnulty/azd-work-in-progress/blob/cd455be45e620cd07d662ac1bfa206094317e751/azd-defender-av-exclusions/docs/backlog.json) |
| [azd-work-in-progress/azd-defender-firewall](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-defender-firewall/docs/backlog.md) | 5 | 1 | 4 | [cd455be45e62](https://github.com/nathanmcnulty/azd-work-in-progress/blob/cd455be45e620cd07d662ac1bfa206094317e751/azd-defender-firewall/docs/backlog.json) |

## Component opportunities

[Per-repository component decisions](component-opportunities.md) distinguish existing adoption, compatible proposals and deferred extraction. The strongest near-term opportunities are stable deployment-validation, portable notification contracts, delegated Graph coordination in compatible PowerShell flows, and the existing Maester hook/report modules. Flex hosting needs identity/storage compatibility first; candidate deployment receipts do not replace domain or real-endpoint evidence.

The earlier owner-branch-only assessment has been superseded by reviewed
source integration: Reference now contains security host 0.1.4 and runtime 0.1.7,
and the four current staged security consumers pin the runtime immutably. Their
source and package provenance evidence is recorded in the execution record.
Preserved older owner branches remain untouched. Enabled hosting, shared
identity, schedules, endpoint state and teardown still require their separate
acceptance gates; source integration does not establish deployed support.

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
