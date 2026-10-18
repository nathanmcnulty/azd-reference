# Portfolio backlog preparation and reconciliation

The [18 October focused-session handoff](portfolio-session-handoffs-20261018.md)
is the newer issue-by-issue inventory of current work and draft integration gates.
It preserves the dated captures below and does not replace repository-owned backlogs.

Prepared 3 October and refreshed from immutable default-branch captures on 15 October 2026. This is an aggregate review view of repository-local backlogs, not a second task database. Regenerate counts and links from `docs/backlog.json`; update task status only in the owning repository. The proposed order favors reliability and deployment readiness before new capabilities. No feature implementation, tenant deployment, delivery, release, merge, cleanup or required-check change is authorized by this report.

Coverage: 25 owning GitHub `nathanmcnulty/azd-*` repositories across 30 backlog roots, including the staging repository and five staged solutions. The exact default-branch captures linked below contain 218 records: 138 done, 78 proposed and two blocked, with no ready, in-progress or deferred records in that published snapshot. Of the proposed records, 45 are local-only; that label does not establish satisfied dependencies, readiness or approval. All 30 captured backlogs passed the canonical schema and cross-repository dependency validator on PowerShell 7.6.6. The snapshot excludes newer owner-branch claims, including unmerged AUTH-007 owner-branch work, and is not an atomic portfolio revision.

Done includes bounded source reconciliation, design assessments and previously implemented fixes; the count does not represent 138 new features or live acceptance passes. The initial preparation had 202 records: 31 ready, 152 proposed and 19 done. The earlier 206-record review, 210-record execution count and 11 October snapshot (215 records: 113 done, 101 proposed, one blocked) are historical snapshots. All 30 AZD issues open at initial capture were linked in task sources, with 15 then-open PRs recorded for reconciliation; those issue/PR inventory numbers have not been refreshed here. See the execution record for reviewed publication and validation evidence.

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
| 1 | Fix failure/secret boundaries and shared tracking/provenance gaps | 61 | Focused regressions pass; component decisions use exact hashes |
| 2 | Validate selected deployment paths and improve bounded operational behavior | 52 | Current-source service and human/endpoint evidence retained for authorized targets |
| 3 | Add selected new capabilities and optional components | 36 | Narrow design accepted; permission additions, rollout and rollback are explicit |
| 4 | Release/promotion packets | 3 | Named publication approval plus verified source/artifacts; cleanup separately authorized |

## Next focused packets

The source fixes and tracking/component integrations below are complete on main;
do not redispatch them from an old preparation checkout. Device Cleanup's cap is
already implemented with regression coverage, as are the reconciled Maester
failure semantics, Health callback source fix and staged App Control DoD mapping.
The active local staging branch can still predate the main mapping correction.

Select one bounded proposed item after checking current source, dependencies and
the active owner. CLEAN-006 primary-user archive indexing is now merged, with
86 PowerShell 7.6.6 tests and synthetic live Key Vault helper acceptance plus
verified owned cleanup. Its Graph relationship and real-device recovery gates
remain separate. RISK-003 feature validation, AUTH-008 Flex assessment and
REPORT-003 Web App assessment are also done on reviewed main; both assessments
recommend deferring unchanged component adoption. WEB-002 website provenance
and source-bound quickstarts have an active isolated implementation owner and
are excluded from this snapshot. HEALTH-003 fixtures, WEB-004 dependency
assessment, DEVICE-003 taxonomy and the Maester component adoptions are already
done. HEALTH-006 remains proposed with historical-exposure gaps. Other ordinary
engineering proposals remain selectable without inventing a rollout decision;
consult the owning backlog rather than redispatching an old next-task label.

CPC-004 compatibility assessment and CPC-006 provider-log safety are now done;
unchanged Flex adoption remains deferred and CPC-002 live delivery stays proposed.
MWID-003 and VID-003 repository-owned read-only status are done as local feature
acceptance, with no positive tenant setup or issuance/presentation claim.
MWID-006 compatible client dependency fixes are done; MWID-007 remains blocked
with nine high development dependency findings, so this is not a security all-clear.
AUD-003 and CLEAN-007 source drafts are also excluded from this published snapshot;
the [active work record](portfolio-execution.md#published-follow-through-and-held-work-11-october-2026)
retains their native validation limits and exact held revisions.

Reserve live GUI/Mac/endpoint/recipient acceptance and publication/enforcement
decisions for the explicit gates in the [current reconciliation record](portfolio-execution.md#current-main-reconciliation).
Use at most three implementation owners and an independent exact-diff reviewer;
retain one owner per mutable worktree and the coordinator's integration claim.

The 15 October follow-through completed IGA-003's bounded operator summaries and optional status contracts, CLEAN-003/004's source-only cleanup designs, EA-003's optional workspace-health design, EA-005's optional HOL Guard design and EA-006's selected-tenant guard, plus HEALTH-005's shared-contract assessment. These are source/design completions only; the published table remains the byte-bound default-branch snapshot and owning backlog status is not changed here. GUI ownership and input holds remain, as do native, provider, delivery, recipient and endpoint gates. MADO-008 still needs exact Azure DevOps clone/refs evidence; its completed offline Git proofs are not a new source defect.

## Repository backlogs

| Repository / solution | Records | Done | Proposed | Blocked | Reviewed source |
| --- | ---: | ---: | ---: | ---: | --- |
| [azd-advanced-auditing](https://github.com/nathanmcnulty/azd-advanced-auditing/blob/main/docs/backlog.md) | 6 | 4 | 2 | 0 | [edd48cd5ac38](https://github.com/nathanmcnulty/azd-advanced-auditing/blob/edd48cd5ac3866b13ddbe3640ae6181b7871975c/docs/backlog.json) |
| [azd-auth-notifications](https://github.com/nathanmcnulty/azd-auth-notifications/blob/main/docs/backlog.md) | 10 | 6 | 4 | 0 | [549f5a02443b](https://github.com/nathanmcnulty/azd-auth-notifications/blob/549f5a02443b9c82ada2010a776a6958f76eb036/docs/backlog.json) |
| [azd-cloud-pc-recommendations](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/blob/main/docs/backlog.md) | 6 | 5 | 1 | 0 | [285113a76bd1](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/blob/285113a76bd1cdf177de5a49e806a8327066be22/docs/backlog.json) |
| [azd-defender-reporting](https://github.com/nathanmcnulty/azd-defender-reporting/blob/main/docs/backlog.md) | 4 | 3 | 1 | 0 | [087d0d22303d](https://github.com/nathanmcnulty/azd-defender-reporting/blob/087d0d22303d837d31821f787a09821b26e67609/docs/backlog.json) |
| [azd-device-cleanup](https://github.com/nathanmcnulty/azd-device-cleanup/blob/main/docs/backlog.md) | 13 | 11 | 2 | 0 | [54d827649f00](https://github.com/nathanmcnulty/azd-device-cleanup/blob/54d827649f00e1956faa5cfe2c7915bfde47eef7/docs/backlog.json) |
| [azd-device-notifications](https://github.com/nathanmcnulty/azd-device-notifications/blob/main/docs/backlog.md) | 5 | 4 | 1 | 0 | [6774c6509ea3](https://github.com/nathanmcnulty/azd-device-notifications/blob/6774c6509ea34388b61ce24eee025264dcee08d7/docs/backlog.json) |
| [azd-emergency-access](https://github.com/nathanmcnulty/azd-emergency-access/blob/main/docs/backlog.md) | 6 | 5 | 1 | 0 | [b47bfd70252d](https://github.com/nathanmcnulty/azd-emergency-access/blob/b47bfd70252dabcc3c670d31e494ba1b61732b51/docs/backlog.json) |
| [azd-entra-health-monitoring](https://github.com/nathanmcnulty/azd-entra-health-monitoring/blob/main/docs/backlog.md) | 6 | 4 | 2 | 0 | [0cf185b8c2ad](https://github.com/nathanmcnulty/azd-entra-health-monitoring/blob/0cf185b8c2ad9cbeff36de8e8a39773208dc4ef2/docs/backlog.json) |
| [azd-entra-iga](https://github.com/nathanmcnulty/azd-entra-iga/blob/main/docs/backlog.md) | 6 | 4 | 2 | 0 | [0be709a9142c](https://github.com/nathanmcnulty/azd-entra-iga/blob/0be709a9142c01b1449a00ea70361ab24265dd28/docs/backlog.json) |
| [azd-global-secure-access](https://github.com/nathanmcnulty/azd-global-secure-access/blob/main/docs/backlog.md) | 4 | 2 | 2 | 0 | [1aed2738405c](https://github.com/nathanmcnulty/azd-global-secure-access/blob/1aed2738405c77fbd50b2cb042c3ac96450e6bfc/docs/backlog.json) |
| [azd-gui](https://github.com/nathanmcnulty/azd-gui/blob/main/docs/backlog.md) | 16 | 3 | 13 | 0 | [6432d90be206](https://github.com/nathanmcnulty/azd-gui/blob/6432d90be206aff52e053b70b2a92a1bb014c77f/docs/backlog.json) |
| [azd-maester](https://github.com/nathanmcnulty/azd-maester/blob/main/docs/backlog.md) | 8 | 5 | 3 | 0 | [ba417deae166](https://github.com/nathanmcnulty/azd-maester/blob/ba417deae1664e89f996233ddd0e3ced33bab2c4/docs/backlog.json) |
| [azd-maester-azureautomation](https://github.com/nathanmcnulty/azd-maester-azureautomation/blob/main/docs/backlog.md) | 5 | 4 | 1 | 0 | [544d356eca00](https://github.com/nathanmcnulty/azd-maester-azureautomation/blob/544d356eca0071cfaaab4d96a28502a0a75fbc6a/docs/backlog.json) |
| [azd-maester-azuredevops](https://github.com/nathanmcnulty/azd-maester-azuredevops/blob/main/docs/backlog.md) | 9 | 6 | 3 | 0 | [80dd3bcab64c](https://github.com/nathanmcnulty/azd-maester-azuredevops/blob/80dd3bcab64cdbf5adafd7131f5ea47b378065f6/docs/backlog.json) |
| [azd-maester-containerappjob](https://github.com/nathanmcnulty/azd-maester-containerappjob/blob/main/docs/backlog.md) | 6 | 5 | 1 | 0 | [2a55dab9c58f](https://github.com/nathanmcnulty/azd-maester-containerappjob/blob/2a55dab9c58f17aeecee72e5fd3381c79af428e6/docs/backlog.json) |
| [azd-maester-functionapp](https://github.com/nathanmcnulty/azd-maester-functionapp/blob/main/docs/backlog.md) | 6 | 5 | 1 | 0 | [bc4621abd10d](https://github.com/nathanmcnulty/azd-maester-functionapp/blob/bc4621abd10d44894bb22121300b4c459531ef6c/docs/backlog.json) |
| [azd-myworkid](https://github.com/nathanmcnulty/azd-myworkid/blob/main/docs/backlog.md) | 7 | 5 | 1 | 1 | [730df60022ca](https://github.com/nathanmcnulty/azd-myworkid/blob/730df60022ca701725b18af3493af55e53c0aabf/docs/backlog.json) |
| [azd-pim](https://github.com/nathanmcnulty/azd-pim/blob/main/docs/backlog.md) | 6 | 5 | 1 | 0 | [298b78dfa5cf](https://github.com/nathanmcnulty/azd-pim/blob/298b78dfa5cf644d01ce5d5ac794604f0f53f389/docs/backlog.json) |
| [azd-reference](https://github.com/nathanmcnulty/azd-reference/blob/main/docs/backlog.md) | 14 | 12 | 1 | 1 | [5e8c1c59b9ab](https://github.com/nathanmcnulty/azd-reference/blob/5e8c1c59b9ab84a7e50d5da397865f22c0fa6d86/docs/backlog.json) |
| [azd-risk-based-ca](https://github.com/nathanmcnulty/azd-risk-based-ca/blob/main/docs/backlog.md) | 5 | 4 | 1 | 0 | [f8eda4504566](https://github.com/nathanmcnulty/azd-risk-based-ca/blob/f8eda4504566e0521204fd884fd630c3a9910d24/docs/backlog.json) |
| [azd-santa](https://github.com/nathanmcnulty/azd-santa/blob/main/docs/backlog.md) | 6 | 3 | 3 | 0 | [e1f974f08979](https://github.com/nathanmcnulty/azd-santa/blob/e1f974f089798071654af0d0d3b7a414d26f96ee/docs/backlog.json) |
| [azd-sysmon](https://github.com/nathanmcnulty/azd-sysmon/blob/main/docs/backlog.md) | 23 | 7 | 16 | 0 | [2909e884409f](https://github.com/nathanmcnulty/azd-sysmon/blob/2909e884409fdb7fcfa422d5b699a193fe1161f9/docs/backlog.json) |
| [azd-verified-id](https://github.com/nathanmcnulty/azd-verified-id/blob/main/docs/backlog.md) | 6 | 5 | 1 | 0 | [a3c368e60585](https://github.com/nathanmcnulty/azd-verified-id/blob/a3c368e605852f30a66d82304b51907bb037ea67/docs/backlog.json) |
| [azd-website](https://github.com/nathanmcnulty/azd-website/blob/main/docs/backlog.md) | 4 | 2 | 2 | 0 | [e55b34ee8e5d](https://github.com/nathanmcnulty/azd-website/blob/e55b34ee8e5d5da3a6ecf65c67eedfda5be28276/docs/backlog.json) |
| [azd-work-in-progress](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/docs/backlog.md) | 5 | 3 | 2 | 0 | [4c974e166600](https://github.com/nathanmcnulty/azd-work-in-progress/blob/4c974e1666000df6025fe8a1dd977de970353b77/docs/backlog.json) |
| [azd-work-in-progress/azd-app-control](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-app-control/docs/backlog.md) | 4 | 3 | 1 | 0 | [4c974e166600](https://github.com/nathanmcnulty/azd-work-in-progress/blob/4c974e1666000df6025fe8a1dd977de970353b77/azd-app-control/docs/backlog.json) |
| [azd-work-in-progress/azd-app-control-for-business](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-app-control-for-business/docs/backlog.md) | 7 | 4 | 3 | 0 | [4c974e166600](https://github.com/nathanmcnulty/azd-work-in-progress/blob/4c974e1666000df6025fe8a1dd977de970353b77/azd-app-control-for-business/docs/backlog.json) |
| [azd-work-in-progress/azd-defender-asr-rules](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-defender-asr-rules/docs/backlog.md) | 5 | 3 | 2 | 0 | [4c974e166600](https://github.com/nathanmcnulty/azd-work-in-progress/blob/4c974e1666000df6025fe8a1dd977de970353b77/azd-defender-asr-rules/docs/backlog.json) |
| [azd-work-in-progress/azd-defender-av-exclusions](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-defender-av-exclusions/docs/backlog.md) | 5 | 3 | 2 | 0 | [4c974e166600](https://github.com/nathanmcnulty/azd-work-in-progress/blob/4c974e1666000df6025fe8a1dd977de970353b77/azd-defender-av-exclusions/docs/backlog.json) |
| [azd-work-in-progress/azd-defender-firewall](https://github.com/nathanmcnulty/azd-work-in-progress/blob/main/azd-defender-firewall/docs/backlog.md) | 5 | 3 | 2 | 0 | [4c974e166600](https://github.com/nathanmcnulty/azd-work-in-progress/blob/4c974e1666000df6025fe8a1dd977de970353b77/azd-defender-firewall/docs/backlog.json) |

## Component opportunities

[Per-repository component decisions](component-opportunities.md) distinguish existing adoption, compatible proposals and deferred extraction. The strongest near-term opportunities are stable deployment-validation, portable notification contracts, delegated Graph coordination in compatible PowerShell flows, and the existing Maester hook/report modules. Flex hosting needs identity/storage compatibility first; candidate deployment receipts do not replace domain or real-endpoint evidence.

The earlier owner-branch-only assessment has been superseded by reviewed
source integration: Reference now contains security host 0.1.5 and runtime 0.1.7,
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
- At initial preparation, most solution checkouts were on active permission-tracking branches. Function App has active packaging/validation changes; PIM has active vendor/line-ending changes; staging has three active Defender builders. Backlog preparation preserves that work.
- Source revisions describe local snapshot provenance, not a promise that the remote default branch matches the checkout or that a test passed on current source.
- All original Sysmon unchecked items and all six Device Cleanup follow-ups are retained as bounded records. Existing GUI and App Control execution plans remain evidence/design sources; no historical release or endpoint gate was reset. HEALTH-002 and REF-003 are completed source/local-tool records with evidence, not live deployment passes.
- Local backlog/schema/tool validation does not prove Azure deployment, human-visible notification, endpoint convergence or release readiness.
- Preparation itself was local. The subsequent authorized reconciliation committed, pushed, reviewed and merged the named packets recorded in portfolio-execution.md. No releases, permission grants or required-check changes were made by that reconciliation.
