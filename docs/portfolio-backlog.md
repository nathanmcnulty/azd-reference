# Portfolio backlog preparation

Captured 3 October 2026. This is a generated preparation view of repository-local backlogs, not a second task database. Regenerate counts and links from `docs/backlog.json`; update task status only in the owning repository. The proposed order favors reliability and deployment readiness before new capabilities. No feature implementation, tenant deployment, delivery, release, merge, cleanup or required-check change is authorized by this report.

Coverage: 25 current GitHub `nathanmcnulty/azd-*` repositories, one retained local coordination checkout, and five staged solutions. 204 task records: 35 ready, 160 proposed, 9 done. All 30 AZD issues open at initial capture are linked in task sources, with 15 then-open PRs recorded for reconciliation. Execution reconciliation added 28 further open-report candidates and confirmed Device Cleanup PR #10 and staged App Control PR #32 as merged. The earlier read-only refresh recorded Health issue #6 / PR #8 as resolved at c2c63371ec182060b0e7e24f534e37e62c84d84e; it remains a completed record, with a separate historical-exposure assessment candidate. These GitHub search results are a dated snapshot, not a guarantee about changes after capture.

`azd-nathanmcnulty` exists locally, but authenticated `gh repo view` could not resolve its configured remote. It is preserved and treated as local coordination only. `AZD-for-beginners` is Microsoft-owned and excluded. Duplicate acceptance/build worktrees are not independent portfolio repositories. The legacy staged `azd-pim` copy is preserved and excluded from a competing implementation backlog pending history/owner reconciliation.

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
| 0 | Reconcile current source, issue/PR state and active owners | 63 | Actual offline commands and remaining work verified; no duplicate owner |
| 1 | Fix failure/secret boundaries and shared tracking/provenance gaps | 51 | Focused regressions pass; component decisions use exact hashes |
| 2 | Validate selected deployment paths and improve bounded operational behavior | 52 | Current-source service and human/endpoint evidence retained for authorized targets |
| 3 | Add selected new capabilities and optional components | 35 | Narrow design accepted; permission additions, rollout and rollback are explicit |
| 4 | Release/promotion packets | 3 | Named publication approval plus verified source/artifacts; cleanup separately authorized |

## Recommended first implementation packets

Select a small wave after the owning reconciliation task. Start at most three independent implementation owners; reserve the coordinator for integration and exact-diff review. Each owner gets one task and one mutable worktree. Reviewers receive an exact commit or stable diff. Do not dispatch every proposed task at once.

| Packet | Backlog items | Why first / dependency |
| --- | --- | --- |
| Device Cleanup blast-radius controls | CLEAN-009 | HTTP-404 fix CLEAN-010 is merged; batch-disable cap still needs a conservative policy decision and focused fixtures |
| Maester success/failure semantics | MAUTO-004, MCAJ-004, MADO-004, MFUNC-004/005 | A report must not make runner failure or timeout look passed; Function App active owner resolves its dirty work first |
| Health webhook secrets | HEALTH-002/003 | PR #8 callback fix is now merged and HEALTH-002 is done; HEALTH-003 remains a candidate. HEALTH-006 separates historical exposure assessment |
| Staged App Control cloud mapping | APP0-002 done | PR #32 is merged with cloud-mapping regressions; no new implementation dispatch needed |
| Canonical provenance | REF-006, AUTH-009, DEVICE-004, EA-004, PIM-005 | REF-006 is complete locally with reviewed registration and comparison; Auth Notifications and PIM upgrades are complete locally; Device Notifications and Emergency Access upgrades remain separate packets |

These are candidates for selection, not a standing instruction to implement or merge. Prioritize endpoint-security feature scaffolds next if that becomes the chosen focus; current ASR/AV/Firewall builders must finish or hand off their owned worktrees before new agents start.

## Repository backlogs

| Repository / solution | Records | Next local starting point |
| --- | ---: | --- |
| [azd-advanced-auditing](../../azd-advanced-auditing/docs/backlog.md) | 4 | AUD-001: current-source reconciliation |
| [azd-auth-notifications](../../azd-auth-notifications/docs/backlog.md) | 10 | AUTH-001: current-source reconciliation |
| [azd-cloud-pc-recommendations](../../azd-cloud-pc-recommendations/docs/backlog.md) | 4 | CPC-001: current-source reconciliation |
| [azd-defender-reporting](../../azd-defender-reporting/docs/backlog.md) | 4 | REPORT-001: current-source reconciliation |
| [azd-device-cleanup](../../azd-device-cleanup/docs/backlog.md) | 10 | CLEAN-001: current-source reconciliation |
| [azd-device-notifications](../../azd-device-notifications/docs/backlog.md) | 5 | DEVICE-001: current-source reconciliation |
| [azd-emergency-access](../../azd-emergency-access/docs/backlog.md) | 5 | EA-001: current-source reconciliation |
| [azd-entra-health-monitoring](../../azd-entra-health-monitoring/docs/backlog.md) | 6 | HEALTH-001: current-source reconciliation |
| [azd-entra-iga](../../azd-entra-iga/docs/backlog.md) | 6 | IGA-001: current-source reconciliation |
| [azd-global-secure-access](../../azd-global-secure-access/docs/backlog.md) | 4 | GSA-001: current-source reconciliation |
| [azd-gui](../../azd-gui/docs/backlog.md) | 16 | GUI-001: current-source reconciliation |
| [azd-maester](../../azd-maester/docs/backlog.md) | 8 | MCAT-001: current-source reconciliation |
| [azd-maester-azureautomation](../../azd-maester-azureautomation/docs/backlog.md) | 5 | MAUTO-001: current-source reconciliation |
| [azd-maester-azuredevops](../../azd-maester-azuredevops/docs/backlog.md) | 9 | MADO-001: current-source reconciliation |
| [azd-maester-containerappjob](../../azd-maester-containerappjob/docs/backlog.md) | 6 | MCAJ-001: current-source reconciliation |
| [azd-maester-functionapp](../../azd-maester-functionapp/docs/backlog.md) | 6 | MFUNC-001: current-source reconciliation |
| [azd-myworkid](../../azd-myworkid/docs/backlog.md) | 5 | MWID-001: current-source reconciliation |
| [azd-pim](../../azd-pim/docs/backlog.md) | 6 | PIM-001: current-source reconciliation |
| [azd-reference](../../azd-reference/docs/backlog.md) | 8 | REF-001: current-source reconciliation |
| [azd-risk-based-ca](../../azd-risk-based-ca/docs/backlog.md) | 5 | RISK-001: current-source reconciliation |
| [azd-santa](../../azd-santa/docs/backlog.md) | 6 | SANTA-001: current-source reconciliation |
| [azd-sysmon](../../azd-sysmon/docs/backlog.md) | 23 | SYS-001: current-source reconciliation |
| [azd-verified-id](../../azd-verified-id/docs/backlog.md) | 6 | VID-001: current-source reconciliation |
| [azd-website](../../azd-website/docs/backlog.md) | 4 | WEB-001: current-source reconciliation |
| [azd-work-in-progress](../../azd-work-in-progress/docs/backlog.md) | 5 | STAGE-001: current-source reconciliation |
| [azd-nathanmcnulty](../../azd-nathanmcnulty/docs/backlog.md) | 2 | INDEX-001: current-source reconciliation |
| [azd-work-in-progress/azd-app-control](../../azd-work-in-progress/azd-app-control/docs/backlog.md) | 4 | APP0-001: current-source reconciliation |
| [azd-work-in-progress/azd-app-control-for-business](../../azd-work-in-progress/azd-app-control-for-business/docs/backlog.md) | 7 | ACFB-001: current-source reconciliation |
| [azd-work-in-progress/azd-defender-asr-rules](../../azd-work-in-progress/azd-defender-asr-rules/docs/backlog.md) | 5 | ASR-001: current-source reconciliation |
| [azd-work-in-progress/azd-defender-av-exclusions](../../azd-work-in-progress/azd-defender-av-exclusions/docs/backlog.md) | 5 | AV-001: current-source reconciliation |
| [azd-work-in-progress/azd-defender-firewall](../../azd-work-in-progress/azd-defender-firewall/docs/backlog.md) | 5 | FW-001: current-source reconciliation |

## Component opportunities

[Per-repository component decisions](component-opportunities.md) distinguish existing adoption, compatible proposals and deferred extraction. The strongest near-term opportunities are stable deployment-validation, portable notification contracts, delegated Graph coordination in compatible PowerShell flows, and the existing Maester hook/report modules. Flex hosting needs identity/storage compatibility first; candidate deployment receipts do not replace domain or real-endpoint evidence.

Security-automation host/runtime 0.1.0 pilots were committed on the active reference branch during this review (9ed4c575cc057a4a96c05ce91c7dd9b7694da7b7), with further owner changes still active. The three staged Defender engines and optional host/bundle adapters are now being integrated. Qualify exact component pins, host/engine boundaries, independent identities and lifecycle evidence before adoption or deployment; local pilot labels alone do not establish published support.

## Selection, validation and handoff

From PowerShell, discover only the declared backlog roots and pass the full set when resolving cross-repository dependencies:

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

For live-validation tasks, the maintainer must separately name the target and permitted actions. Their principal authorization class is descriptive; the acceptance and validation gates can require additional independent permissions. Never infer approval from a status, successful CI, catalog metadata or a proposed wave.

## Preparation limits and preservation

- GitHub issues were inventoried and linked; most historical reports still require current-source reproduction before fixing. Health callback and legacy DoD mapping were checked directly in the current local source.
- Most solution checkouts are on active permission-tracking branches. Function App has active packaging/validation changes; PIM has active vendor/line-ending changes; staging has three active Defender builders. Backlog preparation preserves that work.
- Source revisions describe local snapshot provenance, not a promise that the remote default branch matches the checkout or that a test passed on current source.
- All original Sysmon unchecked items and all six Device Cleanup follow-ups are retained as bounded records. Existing GUI and App Control execution plans remain evidence/design sources; no historical release or endpoint gate was reset. HEALTH-002 and REF-003 are completed source/local-tool records with evidence, not live deployment passes.
- Local backlog/schema/tool validation does not prove Azure deployment, human-visible notification, endpoint convergence or release readiness.
- Files are prepared locally. No commits, pushes, new issues, external messages, releases, tenant changes or required-check changes were made by this preparation.
