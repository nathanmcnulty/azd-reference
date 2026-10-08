# Coordinated backlog execution

Session: 3 October 2026. The maintainer selected coordinated backlog work, with
independent review of new code and necessary validation in the lab subscription,
followed by removal of disposable test resources. This session authorization is
separate from the classification in each backlog record.

The canonical tasks remain in each repository's `docs/backlog.json`. See the
[portfolio view](portfolio-backlog.md) and [component opportunities](component-opportunities.md).

## Ownership and order

The existing code-quality task owns its active defect fixes. The endpoint-security
builder owns the staged ASR, AV exclusions and Firewall engines and the new shared
security host/runtime. Their work is reconciled before another implementation is
assigned. Canonical checkouts and unrelated worktrees are preserved.

| Packet | Owner | Selected boundary |
| --- | --- | --- |
| REF-006 | registry_adoption | Register actual Auth Notifications component adoption, add its offline validation entry point and prepare separate consumer upgrade decisions |
| AUTH-005 | notification_retention | Optional terminal-payload compaction that preserves deduplication and ambiguous delivery state |
| AUTH-009 | registry_adoption | Adopt the signed deployment-validation 1.1.1 component in Auth Notifications, retaining its current plan contract |
| PIM-005 | notification_retention | Adopt the same component in PIM with an explicit schema 1.0 compatibility assertion |
| EA-004 | registry_adoption | Upgrade Emergency Access using its preserved reviewed backlog branch and retain Graph authentication 0.1.1 |
| DEVICE-004 | notification_retention | Upgrade Device Notifications from current main and retain notification contracts 1.0.0 |
| AUTH-004 | registry_adoption | Operator-only ambiguous-send review with conditional atomic decision auditing; root owns disposable Table testing and cleanup |
| REF-008 | root | Complete PortfolioStatus fixture-local signing isolation after the upstream ComponentSync fix |
| Independent review | independent_reviewer | Frozen source hashes, offline behavior and disposable test/cleanup boundaries |

Claims were serialized in the canonical backlogs before dispatch. Implementation
worktrees are retained outside the source checkouts; each mutable worktree has
one author. The coordinator integrates only frozen, reviewed file sets after
checking that the canonical files have not diverged.

## Tracking reconciliation

The refreshed issue snapshot added 28 proposed discovery records. It does not
assign implementation to those reports. Two exact fixes were verified remotely:

- Device Cleanup HTTP-404 handling, CLEAN-010: [PR #10](https://github.com/nathanmcnulty/azd-device-cleanup/pull/10), merge `21877b299e9dfdb5dbada68dab0273357deb4f7c`.
- App Control DoD URI mapping, APP0-002: [PR #32](https://github.com/nathanmcnulty/azd-work-in-progress/pull/32), merge `f87acfb958b83ce765a559b8ec3fed22e17c8cf0`.

These resolutions do not complete recovery drills, tenant delivery, sovereign
service availability or endpoint acceptance tasks. The reconciliation script
was independently reviewed and a second execution changed no canonical backlog.

## Validation and resource evidence

The 31-root backlog set validates against the shared contract; its 10 regression
tests pass and all generated review views match their canonical JSON.

Live inventory verified the selected target as `sub-patriot-lab`, AzureCloud;
the exact subscription ID is retained in the private receipt. Every test command
specifies that subscription. The retention test uses a disposable identity-only Storage
account and synthetic Table records; no notification transport is exercised.

Private test receipts, exact resource identities, source manifests and the
reviewed cleanup harness are retained privately outside Git.

## Completed packets

The eight implementation packets below are independently reviewed and their
owned files are integrated into canonical checkouts. Their reviewed branches
are committed, pushed and verified; unrelated checkout work is preserved.

| Packet | Result | Validation |
| --- | --- | --- |
| REF-006 | Auth Notifications registered at its actual existing pins; offline validation adapter added; four independent upgrade decisions documented | Independent review; 47 focused Pester tests; full clean reference packet suite 282/282; static/PSSA, catalog 11/11/build, component/skeleton and Bicep checks |
| AUTH-005 | Optional terminal payload retention, disabled by default, with permanent deduplication tombstones and a resumable bounded sweep | Independent review; integrated offline wrapper 37/37 tests, audit with zero vulnerabilities, build/typecheck, Bicep and diff checks; real Azure Table test |
| AUTH-009 | Signed deployment-validation 1.1.1 vendored and locked; existing schema 1.0 plan output preserved | Independent frozen-file review; integrated retention-plus-upgrade wrapper 37/37; three plan checks with provider-call sentinels; managed-file hash parity |
| PIM-005 | Same immutable component adopted with an explicit schema 1.0 compatibility assertion | Independent frozen-file review; integrated canonical suite 121/121 Pester and 14/14 Node; build, Bicep and component drift checks |
| EA-004 | Emergency Access adopts the same signed component; Graph authentication 0.1.1 and unbound schema 1.0 remain unchanged | Independent source/staged review; full 114/114 tests, focused 9/9, schema/no-provider smoke 1/1, Bicep and exact drift; canonical focused 9/9 |
| DEVICE-004 | Device Notifications adopts the same component from current main; notification contracts 1.0.0 remain unchanged | Independent source/staged review; full 104/104 Pester and 109/109 application tests, focused 10/10, build/bundle/Bicep/metadata and zero-vulnerability audit; canonical focused 10/10 |
| AUTH-004 | Bounded paginated operator review; explicit accept/suppress/requeue decisions preserve delivery identity and atomically append a minimal audit | Independent source/staged review; 55/55 tests, focused 23/23, independent review 14/14, build/Bicep/schema/drift and audit 0; nine real Table assertions; exact resource and role cleanup |
| REF-008 | Both PortfolioStatus fixture repositories disable inherited signing locally, complementing merged ComponentSync PR #66 | Independent source/staged review; 12/12 tests with global signing enabled and an unavailable signer/key; zero new analyzer findings |

The reference suite used process-local Git signing overrides for disposable
fixtures because the inherited signing/editor behavior is tracked separately
in issue #65. The packet did not change that unrelated behavior. Local Bicep was
0.46.1; hosted reference CI pins 0.42.1. These results are local validation,
not a claim about a new hosted CI run.

Retention review found and corrected discarded page continuation and lower-cap
cursor reuse. Policy increases reset the active sweep before querying. Cursor
state uses conditional writes and canonical cutoffs; unfinished and ambiguous
delivery records are excluded. No incremental application permission is needed.

The first live harness attempt rejected a tenant-plus-subscription CLI token
request before table creation. The independently reviewed subscription-only
retry passed after the coordinator verified the subscription-to-tenant binding.
The real service proved bounded 2+1 compaction, three permanent tombstones,
replay suppression, strict cutoff, preservation of nonterminal/control records,
and an actual HTTP 412 concurrency conflict.

Cleanup is complete: the receipt-bound test role was removed, the disposable
resource group was deleted, and group/resource/assignment absence was verified.
The private receipt records `deleted-and-verified` and the cleanup timestamp.

## Next selection

Selection considers current ownership and required evidence as well as priority.
Reconcile completed quality-task fixes first, then select remaining failure
semantics and exact-pin consumer upgrades in separate packets. REF-005 retains
its broader permission-metadata and extraction qualification scope; only its
candidate-version portion was completed with REF-006.

Keep recipient-visible delivery, human endpoint acceptance, historical credential
rotation, fleet mutation policy decisions and named publication as explicit
tasks. Those gates are not completed by these offline and synthetic-storage
results. Each new code packet continues to receive independent frozen-diff
review and proportional lab validation with exact-owned cleanup.

AUTH-009 and PIM-005 are complete locally. Their deployment-validation 1.1.1
component resolves to signed immutable revision
`0c96cc89c554ffc3b3ca82ceda12da6591e816c1`. Both retain the existing unbound
schema 1.0 plan contract; optional management evidence binding is not enabled.
At that stage, the central desired-version registry matched those two reviewed
consumer locks. Its focused suite passed 47/47 independently and during integration.
Device Notifications and Emergency Access subsequently completed their own
reviewed adoption packets. All four consumers now pin the same signed 1.1.1
release; optional evidence binding remains a separate feature decision. Existing PIM Flex-host drift and lab worktrees were
preserved, as were Auth Notifications permission-tracking changes.

The maintainer subsequently authorized review, commit and push of this batch.
Exact commit and remote-ref receipts are retained with the private execution
artifacts. Preservation branches do not imply a merge to main, a release,
a new hosted CI result or completion of remaining delivery gates.

The same fresh main confirms [Graph retry PR #8](https://github.com/nathanmcnulty/azd-auth-notifications/pull/8)
is merged and issue #7 closed. AUTH-010 records that remote resolution without
resetting the dirty canonical permission-tracking checkout.

## Reviewed branch preservation

The first batch was independently reviewed across 135 paths, committed in 26
Git roots and pushed to 25 accessible repositories on
`codex/backlog-reviewed-20261003`. Exact remote hashes were verified. At that stage, the retained
`azd-nathanmcnulty` checkout had an unavailable configured remote;
its local commit and single-head Git bundle were independently verified instead. Existing
checkouts, indexes, local environments and unrelated builders were preserved.

EA-004 and DEVICE-004 continue on separate reviewed branches based on their
recorded source snapshots. Their focused plan tests block provider and delivery
calls. These component-only updates needed no further lab resource provisioning.
The final central desired-version follow-up passed 47 focused tests. Branch
preservation does not change required checks, merge to main or release a template.


## Operator review and subsequent reconciliation

AUTH-004 is saved at [8254348](https://github.com/nathanmcnulty/azd-auth-notifications/commit/8254348637b7ca8b952ce49dfa98a071503fb934).
The read-only default CLI uses the cached subscription-bound Storage token,
validates the tenant and records that token's actor. Decisions require an exact
delivery row, current ETag and stable decision UUID. Provider evidence is an
operator assertion; the tool does not contact a provider to verify it. Requeue
preserves the original payload and delivery identity, and normal dispatch checks
current eligibility before sending. Decision audits omit event, recipient,
audience and channel identities; terminal transitions refresh the retention clock.

The synthetic lab account proved bounded redacted pagination, stable decision
replay, accept/suppress payload and creation-time preservation, a real stale-ETag
transaction conflict with no partial audit, retention exclusions and the actual
Windows read-only CLI. No notification transport was invoked. The private result
is hash-bound to the reviewed source, harness, infrastructure and cleanup receipts.

The first provisioning preflight stopped before mutation because the directory
CLI command rejected its subscription argument. The reviewed replacement used
cached Storage-token identity. Receipt readers were then qualified against actual
PowerShell timestamp formats and JSON date coercion before their live actions.
The test account-scoped role and group were removed. Independent checks confirmed
the group absent, zero target resources, zero matching role-assignment GUIDs and
zero direct account assignments. The final receipt is `deleted-and-verified`.

REF-008 is saved at [ddee016](https://github.com/nathanmcnulty/azd-reference/commit/ddee016cf5f0231a9d9a59e86a48257c586d95d0).
Its eight-line change affects only disposable PortfolioStatus fixtures. The
host's Git signing configuration was preserved; the regression temporarily
supplied unusable global signing settings and restored its process environment.

Five Maester records reconcile source fixes already merged on their exact main
snapshots. Each has regression coverage and a successful exact-head validation
job. Function packaging/receipt checks also passed 14/14 locally and independently.

| Records | Reviewed source snapshot | Merged resolution |
| --- | --- | --- |
| MAUTO-004 | `c50ed1f9f5ce34d2567b2708e86fd54998328661` | [Automation PR #11](https://github.com/nathanmcnulty/azd-maester-azureautomation/pull/11) |
| MCAJ-004 | `d5efff3998af6a2f889d6da71ee0fa46fa88d537` | [Container job PR #13](https://github.com/nathanmcnulty/azd-maester-containerappjob/pull/13) |
| MADO-004 | `67b9c6c91013fc4f6a0c05a0ffc252cba231ba15` | [DevOps PR #14](https://github.com/nathanmcnulty/azd-maester-azuredevops/pull/14) |
| MFUNC-004, MFUNC-005 | `b1ad59802ef9f952ac024e0fd2dcfdae328cd643` | [Function PR #13](https://github.com/nathanmcnulty/azd-maester-functionapp/pull/13), [PR #14](https://github.com/nathanmcnulty/azd-maester-functionapp/pull/14) |

This reconciliation changes tracking files only. The four backlog source revisions
now reference the reviewed main snapshots. Dirty canonical runtime and detached
quality worktrees are preserved. Live Automation/Container status propagation,
real DevOps pipelines and Function invocation/Graph/HTML/queue acceptance remain
separate integration evidence gaps. These fixes add no new component adoption;
the reviewed snapshots retain Maester hooks 0.1.5 and report-webapp 0.1.1.


## Health source reconciliation and assessment preparation

HEALTH-001 is saved at [b341445](https://github.com/nathanmcnulty/azd-entra-health-monitoring/commit/b341445138f8df5f1c1ba3c8d84fe558f5803879),
based on main `7bdae8bad4497331bf50083d8614053348a998b3` (merged PR #9).
PowerShell and JSON parsing, 14/14 Pester tests and Bicep compilation passed at
that source; the existing connection-kind BCP187 warning remains. This packet
changes only three tracking files and operations documentation. All 31 portfolio
backlogs and generated views passed after the reviewed tracking integration.

The protected random client-state implementation is recorded, while HEALTH-003
retains its broader receiver, removed-subscription, duplicate-delivery and
transient/renewal-failure fixture gaps. HEALTH-004 retains live Graph/Teams gates.
HEALTH-006 now has value-safe assessment and callback-key rotation preparation,
but remains proposed: no target-bound environment/history assessment, key
regeneration, Graph mutation, cleanup or delivery was performed. The instructions
retrieve all subscription pages and identify provisioning as the lifecycle
workflow's state-Enabled release point. The old canonical runtime checkout and
its local environments were preserved; the new operations text is saved only
in the separately reviewed source branch.


## Follow-up cleanup and preservation validation

A fresh read-only audit verified 37/37 published branch refs against their saved
commit IDs. Both exact synthetic-test resource groups remain absent from the
selected lab subscription, and neither owned test-role assignment GUID remains.
No new Azure resources, grants or delivery operations were needed. The published
backlog tooling revalidated all 31 backlogs and generated views; its ten regression
tests passed and all three tools had zero analyzer findings.

Six completed linked worktrees were independently reviewed and removed through
non-force Git worktree removal: the four Maester reconciliation worktrees, Health
reconciliation and the portfolio signing fixtures. Each had no dirty, untracked,
ignored, nested-repository or environment state. Exact local branch refs, remote
commits, verified complete single-branch bundles and private evidence were retained.
Dirty worktrees and those carrying ignored validation results remain preserved.

The unavailable `azd-nathanmcnulty` checkout was inspected separately. Its five
tracked baseline files are portfolio notes and generic repository hygiene; there
is no AZD template, infrastructure, script or application implementation to move.
Its three local backlog files already match the reviewed preservation commit.
A second complete bundle and recovery manifest were saved outside task artifacts.
At that inspection the checkout and aggregate entries were retained pending
the maintainer's retirement decision, subsequently recorded below. Coordination already belongs in azd-reference; this stub
should not become another staged solution.


## Portfolio coordination stub retirement

On 4 October 2026 the maintainer explicitly approved retiring azd-nathanmcnulty
and converging its useful material into azd-reference. The entire primary checkout,
including Git metadata and the three raw local backlog files, was moved into the
existing durable archive. The active checkout path is absent. The reviewed commit
`41fa2c47d3ac1aaab908827f59450c6a89c3d240`, its parent main snapshot and complete
bundle remain recoverable. The bundle SHA-256 is
`129644e0a354aa87af4849ee4c66d5bccc47cb964af40870ae233a7d27576104`.

The five baseline files add no missing reference capability: the license matches,
Dependabot settings are equivalent, portfolio ownership is already documented,
and reference security policy, governance and validation cover the hygiene needs.
The stub-only prohibition on azure.yaml is inappropriate for reference. Existing
reference controls remain authoritative; no duplicate workflow or competing task
tracker was introduced. The two archived INDEX records and stub component row
were removed from the active aggregate, leaving 30 backlog roots and 202 records.
This retirement concerns only the unavailable local coordination stub; historical
execution evidence and all independently deployable solution repositories remain.


## Current-main reconciliation

This section records the 4–5 October snapshot. The completed 6–7 October
follow-through below supersedes its then-current source-handoff, Website and
Health fixture gaps while preserving the historical evidence.

The maintainer authorized completing remaining reconciliation that needs no new
judgment. On 4 October 2026 the coordinator rebuilt the owned packets against
current main instead of merging old preservation-branch ancestry. All 25 active
repositories have their tracking integration on main; the staging repository also
contains tracking for its existing historical App Control solution. Four newer
unpublished staged solution trackers remain on their owners' preserved snapshots.
No staged solution was published, moved or absorbed merely because it was present.

Each packet received independent review of its exact diff, appropriate offline
validation, passing registered PR-head checks before ordinary squash merge and
exact merged tree comparison. Triggered post-merge main workflows passed. GUI's
tracking-only branch had no registered PR checks or post-merge workflows;
Website's PR site/catalog check passed but no post-merge workflow was triggered.
Their separately reviewed offline validation remains the recorded test evidence.
MyWorkID's supported .NET 8 hosted tests passed; the local .NET 10 roll-forward
attempt was not treated as equivalent acceptance. Reference's foundation passed
292 local tests and Windows/Linux hosted validation. Earlier execution sections
are dated historical evidence; this table supersedes their branch-only integration
state without changing the source to which their live proof was bound.

| Repository | Reviewed integration | Verified merged main |
| --- | --- | --- |
| azd-advanced-auditing | [PR #18](https://github.com/nathanmcnulty/azd-advanced-auditing/pull/18) | [`edd48cd5`](https://github.com/nathanmcnulty/azd-advanced-auditing/commit/edd48cd5ac3866b13ddbe3640ae6181b7871975c) |
| azd-auth-notifications | [PR #10](https://github.com/nathanmcnulty/azd-auth-notifications/pull/10) | [`715fcafc`](https://github.com/nathanmcnulty/azd-auth-notifications/commit/715fcafc70cecdc831a512699c1e0129e11167ea) |
| azd-cloud-pc-recommendations | [PR #7](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/pull/7) | [`f035b101`](https://github.com/nathanmcnulty/azd-cloud-pc-recommendations/commit/f035b101ebe9c5928dae058ad871979a23b56e1e) |
| azd-defender-reporting | [PR #18](https://github.com/nathanmcnulty/azd-defender-reporting/pull/18) | [`8f258252`](https://github.com/nathanmcnulty/azd-defender-reporting/commit/8f258252417cb9f675a8b1ec3a8649582bdca91c) |
| azd-device-cleanup | [PR #14](https://github.com/nathanmcnulty/azd-device-cleanup/pull/14) | [`95ec50bf`](https://github.com/nathanmcnulty/azd-device-cleanup/commit/95ec50bfe96a6a704359a70dd97ea92008a23840) |
| azd-device-notifications | [PR #38](https://github.com/nathanmcnulty/azd-device-notifications/pull/38) | [`bbc8984d`](https://github.com/nathanmcnulty/azd-device-notifications/commit/bbc8984d92ecbb11049645963f10fe3706461fe9) |
| azd-emergency-access | [PR #22](https://github.com/nathanmcnulty/azd-emergency-access/pull/22) | [`15a39144`](https://github.com/nathanmcnulty/azd-emergency-access/commit/15a39144529f48faa7628a8dd02e3f8750879dcc) |
| azd-entra-health-monitoring | [PR #10](https://github.com/nathanmcnulty/azd-entra-health-monitoring/pull/10) | [`6e509bfb`](https://github.com/nathanmcnulty/azd-entra-health-monitoring/commit/6e509bfbc8cb90d7ce8c1a321515e4a0584180e3) |
| azd-entra-iga | [PR #18](https://github.com/nathanmcnulty/azd-entra-iga/pull/18) | [`7799e494`](https://github.com/nathanmcnulty/azd-entra-iga/commit/7799e494d5138bbaf9a4796e21406afa37c88140) |
| azd-global-secure-access | [PR #16](https://github.com/nathanmcnulty/azd-global-secure-access/pull/16) | [`2f153eb8`](https://github.com/nathanmcnulty/azd-global-secure-access/commit/2f153eb8e04f1cc0c7ac9f446e9b293fce94ff13) |
| azd-gui | [PR #144](https://github.com/nathanmcnulty/azd-gui/pull/144) | [`6432d90b`](https://github.com/nathanmcnulty/azd-gui/commit/6432d90be206aff52e053b70b2a92a1bb014c77f) |
| azd-maester | [PR #31](https://github.com/nathanmcnulty/azd-maester/pull/31) | [`9c86e879`](https://github.com/nathanmcnulty/azd-maester/commit/9c86e879f43de090f6fbee0fbb5f35ecbc83c374) |
| azd-maester-azureautomation | [PR #20](https://github.com/nathanmcnulty/azd-maester-azureautomation/pull/20) | [`f307d58a`](https://github.com/nathanmcnulty/azd-maester-azureautomation/commit/f307d58aa2616c3eea2f23bf366e3bc25bbb081d) |
| azd-maester-azuredevops | [PR #17](https://github.com/nathanmcnulty/azd-maester-azuredevops/pull/17) | [`760ac2d8`](https://github.com/nathanmcnulty/azd-maester-azuredevops/commit/760ac2d854b54367376b6c9892ff8c0385ab92c6) |
| azd-maester-containerappjob | [PR #22](https://github.com/nathanmcnulty/azd-maester-containerappjob/pull/22) | [`c29019a4`](https://github.com/nathanmcnulty/azd-maester-containerappjob/commit/c29019a489ea76d34181ac6f4479db1715f090f3) |
| azd-maester-functionapp | [PR #22](https://github.com/nathanmcnulty/azd-maester-functionapp/pull/22) | [`ed8668d8`](https://github.com/nathanmcnulty/azd-maester-functionapp/commit/ed8668d84ed2ccd66bba94c1298916ca285ca64d) |
| azd-myworkid | [PR #40](https://github.com/nathanmcnulty/azd-myworkid/pull/40) | [`6b4f5386`](https://github.com/nathanmcnulty/azd-myworkid/commit/6b4f538689731a2bb8e90061f44929466fcaac2b) |
| azd-pim | [PR #18](https://github.com/nathanmcnulty/azd-pim/pull/18) | [`4c6ddfdb`](https://github.com/nathanmcnulty/azd-pim/commit/4c6ddfdb1cc0d5f30c9cac817a259decd181cc31) |
| azd-reference | [PR #67](https://github.com/nathanmcnulty/azd-reference/pull/67) | [`cd5d64ee`](https://github.com/nathanmcnulty/azd-reference/commit/cd5d64ee37aa58553074966342dc553decfa31c8) |
| azd-risk-based-ca | [PR #24](https://github.com/nathanmcnulty/azd-risk-based-ca/pull/24) | [`1028ba8f`](https://github.com/nathanmcnulty/azd-risk-based-ca/commit/1028ba8f0fbaacd9c7d09807c36cf4e9207a1e3d) |
| azd-santa | [PR #26](https://github.com/nathanmcnulty/azd-santa/pull/26) | [`82c17ed9`](https://github.com/nathanmcnulty/azd-santa/commit/82c17ed961fad5f38499f8b212a2889ece249b97) |
| azd-sysmon | [PR #11](https://github.com/nathanmcnulty/azd-sysmon/pull/11) | [`bb11af88`](https://github.com/nathanmcnulty/azd-sysmon/commit/bb11af88551b3c18be1954a288898a3a3a741577) |
| azd-verified-id | [PR #11](https://github.com/nathanmcnulty/azd-verified-id/pull/11) | [`4d34f9a1`](https://github.com/nathanmcnulty/azd-verified-id/commit/4d34f9a1c87c948190bd188fd2aa97d7ca58798b) |
| azd-website | [PR #58](https://github.com/nathanmcnulty/azd-website/pull/58) | [`0886e99f`](https://github.com/nathanmcnulty/azd-website/commit/0886e99f51fb884100765bbcb3a81f918fe4631c) |
| azd-work-in-progress | [PR #37](https://github.com/nathanmcnulty/azd-work-in-progress/pull/37) | [`996d0585`](https://github.com/nathanmcnulty/azd-work-in-progress/commit/996d0585921c3cceae43ab04f702c20c031751a7) |

The Reference entry records foundation PR #67. This follow-up report packet adds
REF-002's backlog-schema and generated-view checks to the existing Windows/Linux
validation job. It has ten focused local regressions and aggregate validation;
hosted PR validation must pass before merge. It introduces no new required check,
catalog enforcement, runtime dependency, deployment or permission grant.

### Refreshed backlog accounting

The 30-root aggregate contains 206 records: 75 done, 126 proposed and five ready.
It uses the 26 reviewed tracking roots described above, including this Reference
CI-pilot packet, and four read-only unpublished owner snapshots. Done includes
source reconciliation and existing implemented fixes; it is not a count of newly
delivered features. Four new resolved issue records in Auditing, Cloud PC and
Device Cleanup explain the change from the earlier 202-record preparation.
Schema, dependency, evidence and generated-view checks passed for all 30 roots.

Device Cleanup's batch cap, Maester failure semantics, Health's callback source
fix and App Control's DoD mapping are already implemented. All four validation
component consumers have the reviewed immutable deployment-validation 1.1.1
revision `0c96cc89c554ffc3b3ca82ceda12da6591e816c1`, with schema 1.0 output
contracts preserved. Their broader live acceptance remains a separate gate.
Website's local dependency audit reported 29 high findings; WEB-004 retains
assessment/remediation as proposed. Tracking integration does not declare that
dependency gap resolved or establish exploitability of every raw audit finding.

### Work that agents can continue without a rollout decision

- Reconcile exact owner handoffs for App Control for Business and the three
  Defender engines, then map historical App Control architecture under APP0-003.
  Preserve both source histories and active dirty work; do not import unfinished
  permission/security-host/runtime ancestor commits as part of tracking changes.
- Assess Website WEB-004 dependency findings against current source, and implement
  bounded offline fixes/fixtures such as Health HEALTH-003. HEALTH-006's historical
  exposure assessment is prepared but no target-bound assessment or rotation has
  been completed.
- Qualify optional component candidates only against their actual runtime and
  identity contracts, with immutable pins and permission gaps recorded. A proposed
  opportunity is not approval to grant a scope, combine identities or deploy.
- Use clean current-main worktrees for the next wave. Canonical dirty checkouts
  intentionally remain; their older local backlog/source files must not overwrite
  the reviewed main packets.

The four newer roots are preserved at aggregate branch
`codex/staged-security-solutions-20261003@9df79e0290ce340641d8aab653ce0a7c088b075c`.
Their source trees match `9dc18622bfee88a8c8eadfa423bc56070a40dbd1`, whose
[three-platform staged validation](https://github.com/nathanmcnulty/azd-work-in-progress/actions/runs/37258211018)
passed 316 Windows tests, 316 PowerShell 7.4.20 tests and 310 Linux tests with six
explicit Windows-only skips, plus Bicep, permissions, locks and packaging.
There is no current live agent owner. Clean builder histories and a separate dirty
four-file ACFB/Firewall quality worktree remain preserved. Later aggregate code
contains the same safety concepts with different blobs, so the next owner must
compare semantics before replaying a reviewed source packet onto current main.
APP0-003 maps retained historical research/probes into the newer ACFB roadmap;
both roots and histories remain, with no implied archive or policy enforcement.

### Gates requiring a target, human acceptance or product decision

- GUI: signed exact-candidate Windows 11 standard-user account/WAM, draft/cancel
  and target-identity acceptance. Native tests do not establish human UI success.
- Santa: actual Mac Monitor configuration delivery and on-device/per-device proof.
  Package/profile preparation does not establish the previously pending main
  configuration was delivered.
- App Control and Defender: populated pilot endpoints, real update/rollback and
  policy convergence. No broader assignment or enforcement is inferred.
- Notifications and recovery: named recipients/routes and visible delivery or
  recovery drill acceptance where required by the selected task.
- Rollout/promotion: policy thresholds, retention/privacy/cost choices, shared
  hosting/identity decisions, named standalone publication/release and any named
  catalog-required enforcement approval. The lab authorization already permits
  necessary bounded validation and cleanup; it is not a blanket rollout target.

### Cleanup and preservation

No cloud resources, grants, notifications or endpoint assignments were created
by this reconciliation. A fresh read-only audit explicitly selected the commercial
lab subscription `43babb60-9e73-4dc8-b769-4401c01aad73`, AzureCloud and tenant
`847b5907-ca15-40f4-b171-eb18619dbfab`. Both owned test groups
`rg-azd-backlog-retention-7ff6fd16` and
`rg-azd-backlog-auth004-b4286f5e6acb` were absent, and both exact owned role
assignment GUIDs had zero matches. The absence receipt SHA-256 is
`0d130ef3968e853235109fcbb834a71fe59ced5d7174a30c59b61b8094448727e`.

The Auth dependency cache was recoverably moved to C: with exact manifest parity
for all 16,053 path/type/size entries; source and Git state stayed unchanged.
Separately, GUI/Santa/Website generated outputs were removed by their owner to
recover disk capacity. Independent review verified bounded paths and unchanged
source; the accounting receipt explicitly records unknown size limits and deletion
of successful ignored Pester XML. Bounded logs and the failed ENOSPC/fresh-C retry
logs were retained; no failed live evidence was deleted. The accounting receipt
SHA-256 is `1879c344dc7de4f65744bd889461b6a5387c57d1711798d92da4d04bd9b1ef67`.

The azd-nathanmcnulty stub retirement remains complete and recoverable as recorded
above. There was no unique application code to migrate. Dirty source worktrees,
environment state, preservation commits and raw lab proof remain retained.

## Follow-through reconciliation, 6–7 October 2026

Twelve independently reviewed follow-through packets are merged into main. Each
merged tree matches its reviewed candidate, and PR plus post-main checks passed.
The four newer staged source roots are now present on staging main; the original
aggregate branches and dirty quality worktree remain preserved.

| Packet | Reviewed integration | Verified main |
| --- | --- | --- |
| Staged App Control for Business, ASR, AV and Firewall convergence | [PR #38](https://github.com/nathanmcnulty/azd-work-in-progress/pull/38) | `fd1e708f26e01d7ccfc2d1fb1eaa0a6e80c99799` |
| Health receiver and lifecycle fixtures | [PR #11](https://github.com/nathanmcnulty/azd-entra-health-monitoring/pull/11) | `3a7eeffd020f865570e625e596601d5827228fa2` |
| Health challenge wire-shape fixture | [PR #12](https://github.com/nathanmcnulty/azd-entra-health-monitoring/pull/12) | `b5e3a57db7f20c49d01f4dcf52a0bed6801bdf94` |
| Website dependency remediation | [PR #61](https://github.com/nathanmcnulty/azd-website/pull/61) | `3e2cdd3b0dec142f7235e3f1f6224d9b69484273` |
| Auth Notifications generated-view entity repair | [PR #11](https://github.com/nathanmcnulty/azd-auth-notifications/pull/11) | `016a9ded4b9777c95a975b271fb678a8d84ef615` |
| Sysmon generated-view entity repair | [PR #12](https://github.com/nathanmcnulty/azd-sysmon/pull/12) | `719915e6adb36881085a0aad2275c45933490edb` |
| Sysmon recoverable receipt writes | [PR #13](https://github.com/nathanmcnulty/azd-sysmon/pull/13) | `c20bbdb63e03279aec524ead39cdf1359ebc5701` |
| Reference Intune source-only pilot | [PR #70](https://github.com/nathanmcnulty/azd-reference/pull/70) | `73009c6ebb91b29a48c3de376e43a8d1da889630` |
| Maester Azure DevOps temporary staging fallback | [PR #18](https://github.com/nathanmcnulty/azd-maester-azuredevops/pull/18) | `6d1930742b93b16dfaf61bc0ceb8f215f6eff5f4` |
| Reference security automation source-only pilots | [PR #71](https://github.com/nathanmcnulty/azd-reference/pull/71) | `1d126470ec0144820bd89e0eebb588cc183b6fbd` |
| Entra IGA authentication-contract reconciliation | [PR #19](https://github.com/nathanmcnulty/azd-entra-iga/pull/19) | `91aa2cf45321983d282091109e9c7932797b03c2` |
| Four-consumer security runtime 0.1.7 upgrade | [PR #39](https://github.com/nathanmcnulty/azd-work-in-progress/pull/39) | `cd455be45e620cd07d662ac1bfa206094317e751` |

The staged packet passed 278 local tests, four Bicep builds, immutable vendor and
permission checks, and committed-source combined packaging before push. Its
[post-main three-platform validation](https://github.com/nathanmcnulty/azd-work-in-progress/actions/runs/37583973606)
and [historical App Control validation](https://github.com/nathanmcnulty/azd-work-in-progress/actions/runs/37583973633)
passed. Historical App Control remains separate Phase 0 research, with its
meaningful architecture mapped into the newer ACFB plan. No standalone publication,
policy assignment or endpoint convergence is inferred.

Health now enforces declared request types, ignores missing change types,
mismatched states and empty IDs, URI-escapes alert IDs, processes identical
normalized records once within a batch, and explicitly terminates failed renewal
even after its warning relay succeeds. Fifteen offline tests passed. The actual
Azure workflow engine passed 15 synthetic fixture cases in a fresh lab attempt,
including a query-token response to a JSON-bodied synthetic challenge, one counted
batch iteration,
fail-closed cases skipping creation/renewal, and failed renewal followed by a
successful warning relay and Terminate. The strengthened lifecycle assertions
were also checked against the retained run receipt. Receipt SHA-256:
`c4f7f91c1a8a315013b4b6f6604fe79e4707c89efda2fa337fc7d9a4cdb924b8`.
Both earlier failed harness attempts remain retained. This proves synthetic
workflow expressions/topology/failure paths; it does not prove real Graph
renewal, Teams receipt, production confidentiality, default retry timing or
cross-request deduplication. HEALTH-004 retains those acceptance gates.

A fourth fresh lab attempt repeated all 15 cases against unchanged production
workflow definitions using the actual Graph challenge shape: observed POST,
`text/plain`, UTF-8 and zero Content-Length. It returned HTTP 200 with the exact
decoded validation token while a notification with an invalid declared type returned
HTTP 400. Independent final review verified the one-path harness change and
receipt SHA-256
`c11c5dcd06e4d336ca4780f9aaa659485fafbe51279cde6317bba0b5a250bed2`.
The harness records parsed observed request metadata without retaining the
signed callback URI. This closes the wire-shape fixture gap without a production
change; it still does not establish real Graph or Teams acceptance.

Website addressed seven of the eight vulnerable root packages in its fresh
baseline audit. The candidate audit remains nonzero: 28 high affected entries
propagate solely from the unpatched braces advisory GHSA-vfj7-8cjw-p6xm. The
hash-bound depth patch remains and issue #53 is open; there is no security-clean
or deployed exploitability claim. Clean installation, four patch tests, six
catalog tests, type checking and static build passed. Independent validation also
forced the two-thread Docusaurus path for the Tinypool major override. The existing
automatic Workers Builds check passed after merge; no manual deployment was invoked.

The Auth/Sysmon packets only repaired one/three numeric entity markers in their
generated Markdown. Their canonical backlog JSON and runtime source remained
unchanged. This Reference packet fixes the generator and records its persistent
apostrophe, Unicode, literal-heading and raw-entity regressions under REF-009.

SYS-012 adds recoverable writes for the four local deployment/teardown ownership
receipts across eight lifecycle scripts. The helper writes and flushes a unique
sibling candidate, validates its JSON, then atomically moves or replaces it; a
replaced primary is retained as `.previous`. Locked replacement preserves the
primary and validated candidate. Corrupt/truncated primary reads fail closed and
never automatically trust a backup or candidate for tenant cleanup.

The full offline validation passed 74 tests, static checks and package checks;
independent receipt tests passed six cases including native Windows PowerShell
5.1 and the locked-target failure. Isolated script-copy fixtures include the new
helper. Generated endpoint packages, immutable locks and upstream report output
remain unchanged. No cloud test or tenant mutation was needed for this local
filesystem change. Canonical backlog validation and the reviewed fixed exporter
keep the new metadata and existing canary apostrophe entities consistent. The
retained integration receipt has SHA-256
`8d13394bb46f3d46d514ee30beab9fc680dee13313f20c5626e4815a8ffa1549`;
all four PR and two post-main checks passed on merged tree
`9f06fcb1a70a8e5e1595937b5fa806312427cfe4`.

MADO-007 now stages repositories when `TEMP` is absent by falling back to
`[IO.Path]::GetTempPath()`. Focused no-change and clone-failure cleanup tests
preserve and restore process state. The exact reviewed tree `6dd78081` passed 39
tests, 23 script parses, all four PR checks and both post-main workflows. No
authentication or network behavior changed. The retained integration receipt has SHA-256
`91c7a8658e68fe6ad5bf73b2ed6f91cde5907f1cca02cb7f13d033e887b0a6ae`.

## Runtime compatibility and notification discovery, 7 October 2026

SYS-013 is complete in [Sysmon PR #15](https://github.com/nathanmcnulty/azd-sysmon/pull/15).
Reviewed head `c71fec1b558529b822a9f94d34e2a7090639b6f6` merged as
`1d59a4381212900796d7f3bfaaf94d35a840a1e3`, with identical tree
`ea118ccfad4ec8c5f8fab0fab4eb14bf6227852c`. The matrix covers Windows 2022 and
2025 hosted runners, each using hosted PowerShell or the archived 7.2.24
compatibility floor. Each leg runs 74 behavioral tests plus static/package
validation, two offline builds with hash comparison, and rebuilt package checks.
The original terminal `validate` identity remains and requires all four legs to
succeed. The portable bootstrap verifies a pinned archive hash before fresh
extraction; a hostile pre-existing executable fixture cannot bypass it.

Both local interpreters passed 74 tests with zero failed, skipped or not-run.
Initial qualification run `37705865764` passed all four cells and terminal
validation on implementation head `b4b18c8cfee4a1d97464bb3c99543c64e147b6ad`;
all eight PR checks passed again on the final reviewed head. Post-main matrix,
terminal validation and CodeQL passed on merged main. This proves source compatibility, not elevated Windows 11/Sysmon
installation, AMA/Intune behavior, ingestion, rollback or live cleanup.

DEVICE-003 discovery is complete in
[Device Notifications PR #39](https://github.com/nathanmcnulty/azd-device-notifications/pull/39).
Reviewed head `094c4157379f44c253f4a5f2e440b57feef09819` merged as
`6774c6509ea34388b61ce24eee025264dcee08d7`, with identical tree
`fd8cb9037a32ccbe425909f62cce6c712bee8fec`. The source comparison documents
Auth's accepted/review/suppressed outcomes and gaps in normalized duplicate,
retry, destination and stranded-state recovery classifications. Device fixtures
execute production propagation logic and owner-scoped conversation operations;
Auth's missing propagation and conversation-isolation fixtures remain explicit.
Per-recipient identity and actual delivery/lifecycle proof remain prerequisites
for shared bot extraction. Neither runtime nor component locks changed.

Required Device validation passed 106 Pester and 114 Vitest tests, build,
bundle, production audit, pinned Bicep 0.46.1, metadata and documentation gates.
The initial compiler mismatch remains retained; the successful rerun used a
private compiler configuration. All four PR checks and post-main validation
plus CodeQL passed on merged main. Both changes passed independent review. No lab resource, authentication,
message, permission, assignment, endpoint action or catalog enforcement changed.

After the runtime/notification batch, the 30-root snapshot had 210 records: 101 done and 109 proposed,
including 76 proposed records classified `local-only`. All schemas and generated
views pass, with no ready or in-progress records. Ordinary implementation and
fixture work remain available alongside the separate live acceptance gates.

## Device Cleanup archive safety, 7 October 2026

CLEAN-012 is complete in
[Device Cleanup PR #15](https://github.com/nathanmcnulty/azd-device-cleanup/pull/15).
Default discovery uses tags for both single and multiple matches and reads no
recovery value. Explicit recovery requires one unambiguous record. Missing
optional tags and duplicate hostnames are covered, and request authority,
collection-only continuations and sanitized failure output are checked.
Reviewed head `d56d3b0d88cab8f24ace4c937953618d8ac26788` merged as
`f21713c7e58b897db2124a49060a15c5a6f13f54`, with identical tree
`41b2916bb70ef2922c5df638bf03fbf85e624c46`. Independent review and 26 tests
passed, along with all four PR and both post-main workflows.

CLEAN-008 and CLEAN-013 are complete in
[Device Cleanup PR #16](https://github.com/nathanmcnulty/azd-device-cleanup/pull/16).
The existing 24,000-byte compact UTF-8 ceiling and refusal before deletion now
have exact-limit, multibyte, writer and full-job fixtures. The job failure is
bound to the production size refusal with zero token, PUT and Entra DELETE
calls. Testing exposed a prior PowerShell interpolation defect in archive PUT
and explicit recovery GET; braced variable boundaries fix both expressions,
and production helper tests assert the exact request URIs.
Reviewed head `488ec24a12980f888c44cefd707ffde2f0be1971` merged as
`c7b3e6eaa2a76722fc45c61b95084c41f93bab24`, with identical tree
`ab444ec52deeedc9db9b4f7692bbcdc688a30fdf`. Independent review and 32 tests
passed, along with all four PR checks and both post-main workflows. The earlier
review coverage finding was corrected before publication.

Both packets passed local parsing, JSON, Bicep and canonical backlog/generated
view checks. Cleanup eligibility, retention settings, grants, infrastructure
and lifecycle action flags are unchanged. Soft-delete retention remains a
recovery window rather than automatic active-archive expiration. No Azure/tenant
authentication, Key Vault recovery/archive reads, lab cloud resources or device
actions ran.
CLEAN-006 primary-user indexing and CLEAN-002 human recovery acceptance remain
proposed. The older aggregate counts above are a historical snapshot; this
packet records repository-local completions without claiming a fresh portfolio
inventory or live recovery qualification.

## Sysmon promotion and path evidence guides, 7 October 2026

SYS-016 and SYS-017 are complete as documentation work in
[Sysmon PR #14](https://github.com/nathanmcnulty/azd-sysmon/pull/14).
The [release evidence guide](https://github.com/nathanmcnulty/azd-sysmon/blob/main/docs/release-evidence.md)
provides a promotion checklist and evidence requirements for client-only,
Sentinel/DCR, Azure VM, Intune, tenant-wide client AMA and MDE Live Response paths.
It separates source, publication, endpoint execution, ingestion and cleanup
claims, with ownership and rollback requirements for each applicable path.

Independent review approved commit
`47f92d4013571d23f75628208e9c9298dd7c995d`; merged main
`0f485ba02fb19b63bf2b819487f4eebd2090c280` has the identical tree
`557588edd9a5d27fdbbd25ca97e0058ddb46b05d`. Required offline validation
passed 74/74 tests, all four PR checks passed, and post-main validation and
CodeQL passed on that merged revision. Only the guide, its README link, canonical
backlog metadata and the two records/generated view changed; runtime behavior is
unchanged.

This does not qualify a deployment or release. Historical live evidence retains
its original limits; helper publication is not endpoint acceptance. Sysmon has
no canonical permission manifest yet, and partial documented requirements remain
gaps rather than authorization to grant permissions. Client AMA API versions are
runtime-discovered; qualified reports and successful independent cleanup reads
must be captured separately where helpers do not produce them. No bearer token,
secret or SAS URL should be retained in evidence. No lab resource, identity,
permission, assignment, endpoint action or catalog enforcement was changed.

After the Sysmon guide batch, the 30-root snapshot contained 210 records: 99 done and 111 proposed,
with no ready or in-progress records. All 30 schemas and generated views pass.
Of those proposed records, 78 were classified `local-only`; further ordinary
engineering remains available without a product or rollout decision.

## Maester standalone source and consumer convergence, 7 October 2026

[Reference PR #73](https://github.com/nathanmcnulty/azd-reference/pull/73)
advanced the pilot `maester-azd-hooks` component to 0.1.6 at immutable main
`a09cac311aac7362f56d2a31833ed90ce5812649`, tree
`3f559a800a31870a461b2168b3018554e26c7ccd`. When the optional Web App is
enabled, the shared wizard rejects blank, malformed and nil security-group IDs
and normalizes a valid value to GUID `D` format before the first environment
write. The disabled path does not require or persist a group ID. The change does
not query or create groups, verify directory-object properties or change Graph
permissions. Local source validation passed the complete 383-test matrix before
the final guidance-only wording correction and then the exact final focused
9-test suite; all five PR checks and hosted validation on the final head,
including post-main CodeQL
`37675236902` plus Windows/Linux validation `37675236975` passed. No component
tag or release was created.

[Catalog PR #32](https://github.com/nathanmcnulty/azd-maester/pull/32) maps the
four retained legacy folders to the corresponding standalone repositories and
host backlogs while keeping the catalog root non-deployable. Its exact reviewed
tree passed 124 tests, four Bicep builds, parser and root-guard checks, all four
PR checks and both post-main workflows. The retained receipt has SHA-256
`25410271a37e4825a99b838e6500e10037bb9ffcdf75245d851c18fc0a3a4b7b`.
No folder was removed or archived.

[Azure DevOps PR #19](https://github.com/nathanmcnulty/azd-maester-azuredevops/pull/19)
records MADO-008's bounded empty-repository investigation at main
`80e99c8acc486e985988d06b9ddce75990e4fd38`, tree
`f5dc70b270b22025a6c3ab6698688e55bf79372d`. Four offline cases prove ordinary
empty-repository bootstrap, preservation of existing history/unrelated files,
an identical rerun no-op and native clone-failure propagation with cleanup.
MADO-008 remains proposed because no Azure DevOps provider, account, permission,
timing or REST branch-resolution behavior was exercised or repaired.

All four standalone hosts then adopted only `maester-azd-hooks@0.1.6` from the
immutable Reference revision. Their report-webapp 0.1.1 pins, host-specific
runners and pilot catalog enforcement remain unchanged.

| Standalone host | Reviewed integration | Verified main and tree | Offline and hosted proof |
| --- | --- | --- | --- |
| Azure Automation | [PR #21](https://github.com/nathanmcnulty/azd-maester-azureautomation/pull/21), `5a974c8887acfe5bbd2809549ebbd4b2fffea3a3` | `e3fce00620e147fef4ae210007af923d9ad78ef4`, tree `3428b306bca9235d6a70590dce607c6d8f3bdc94` | 48 tests; four PR checks; post-main validation `37678543910` and CodeQL `37678543749` passed |
| Container App Job | [PR #23](https://github.com/nathanmcnulty/azd-maester-containerappjob/pull/23), `2f2353c8f388e9a31a068e4d8d1e942ae5761615` | `215d7bb703595ed460c9132014a6b9c5c503ace8`, tree `d697518ae670c1684d0ecd9fb81d6c4d12b24a17` | 43 tests; four PR checks; post-main validation `37678564129` and CodeQL `37678563365` passed |
| Function App | [PR #23](https://github.com/nathanmcnulty/azd-maester-functionapp/pull/23), `0242fa68a4ee652d9bfe75f53f832c77d9aed8e2` | `0c7462e942ac4d8b5bd4b8ac5a51d5fba7a6d94d`, tree `504c4982b9c1d4cfcb1001ef8d347436073d0aa8` | 42 tests; four PR checks; post-main validation `37678617200` and CodeQL `37678616654` passed |
| Azure DevOps | [PR #20](https://github.com/nathanmcnulty/azd-maester-azuredevops/pull/20), `4a9fe04ce6cf6d397d2f55d2f9301ef773d60317` | `76ac648c7172981a22259f6d6fd701c2a085cb57`, tree `6fb0bad34ff7f9a96e27649728c3ea474a299dc4` | 39 repository tests plus nine actual-vendor GUID cases; four PR checks; post-main validation `37678168871` and CodeQL `37678169652` passed |

All 36 managed component files (32 hook files and four report-webapp files)
match their locks. The three-consumer publication
receipt has SHA-256
`67f01a5064affd5dfd474565f6d0441c12488ceefd0bfbe073bb989b1930c48d`;
its publication artifact manifest has SHA-256
`962c57247e8f85012620966c4ddb5078a8bfc949a05d16b1fd1693e33fe832cd`.
The Azure DevOps integration receipt has SHA-256
`9639da62e4e5edd27cfb5fe05af98d659510acc2011fac3c61d7024570951079`.
Source branches and clean worktrees remain preserved.

Each host now has a partial, source-bound inventory of 24 requirements: eight
Minimal application roles, eleven Extended additions, four deployment-operator
delegated scopes used by the shared grant helper and optional `Mail.Send`.
Azure RBAC, host-specific setup authority, Exchange, Teams, optional Azure and
report-webapp operations, and cleanup remain explicit gaps. The inventories do
not prove consent or effective grants and did not add roles or permissions.

The four host reconciliation items and Azure DevOps MADO-006 are done.
MADO-002 live pipeline/report-webapp acceptance, MADO-005 authentication sync
and MADO-008 provider failure classification remain proposed. This source and
consumer evidence does not claim live deployment, group existence/type, pipeline
execution, report publication, cleanup acceptance, component release or required
catalog enforcement.

The Maester batch 30-root aggregate snapshot had 210 records: 97 done and 113
proposed, with no ready or in-progress records; all 30 generated views pass.
Eighty proposed items in that snapshot were classified `local-only`, so proposed status must not
be read as a claim that all remaining work requires a human product decision.

### Canonical permission metadata and accounting

This Reference packet reconciles the finished permission schema, standard,
registry, comparison tool/tests and starter manifests from immutable preserved
branch `e5265492a949f2e111d3dac88d043b4f63175d3a`, plus bounded path-safety and
selection-receipt corrections required by independent review. That metadata
snapshot excluded 29 security-host/runtime/Intune component and test paths. The
later Intune qualification imported nine of those paths as source-only pilot
0.1.6, and the current candidate imports the remaining 20 host/runtime paths with
the reviewed runtime repair. Registry files are review
metadata; deployment hooks do not execute them or grant roles.
Colon-bearing manifest/evidence paths, including NTFS alternate data streams,
are rejected. Saved JSON records enabled/excluded features and optional-union
selection, without claiming Git tracking or effective tenant permissions.

The candidate's 11 component manifests comprise one stable, nine pilots and one
candidate. The added Intune pilot retains its reviewed 0.1.6 bytes; existing
immutable consumer pins are unchanged and no component tag or release was created. Teams
personal-bot and managed-connector extraction, shared-host isolation and identity
choices remain behind their evidence gates. Local ASR/AV/Firewall comparisons
reported zero default runtime requirements and six explicitly selected optional
runtime/discovery requirements; all three inventories remained partial with
`comparisonComplete: false`. That is an incomplete inventory, not a permission-free
or least-privilege conclusion.

The earlier pre-Maester-adoption 30-root aggregate snapshot had 209 records: 90
done and 119 proposed, with no ready or in-progress records. REF-005's
metadata reconciliation and HEALTH-003's bounded fixture work are complete; the
new REF-009, REF-010 and REF-011 records explain the generator correction and
the two source-only pilot qualifications. Schema, dependency, evidence
and generated-view checks passed for all 30 roots. Done includes reconciliation
and previously implemented fixes, rather than a count of newly delivered features.

Local Reference validation passed a full 301-test run on the preliminary
candidate, followed by the focused 19-test permission/backlog suite for final
path and selection corrections. Registered PowerShell parsing/analysis,
11 catalog action tests/build, unchanged component versions, skeleton
locks/drift/sync WhatIf, and Bicep positive/negative assertions passed. Hosted
Windows/Linux validation on source commit
`397529e4a1ac66b832845633a4f59efac5e90b17` passed 301 tests on each platform, plus
the registered static, catalog and Bicep checks.
[Reference PR #69](https://github.com/nathanmcnulty/azd-reference/pull/69)
merged as `d3da9b0bd0d2df50bf55f736fd5f8986b3751341` after its exact reviewed
Windows and Linux suites, static checks, catalog build, CodeQL and post-main
validation passed. Catalog validation remains a non-required pilot; no check
requirement, enforcement approval, component release or runtime dependency changed.

The later Intune source-only qualification retained all nine reviewed 0.1.6
source/test blobs from `e5265492a949f2e111d3dac88d043b4f63175d3a`. Focused
tests passed 32/32. Complete registered local validation passed 333 Pester tests,
the exact module-hash and six-finding analyzer gate, 11 catalog tests and build,
component/version and skeleton lock/drift/sync checks, and every registered Bicep
build and positive/negative assertion. All 12 AV/Firewall immutable lock entries
match both the imported source and current vendored files on staging main
`fd1e708f26e01d7ccfc2d1fb1eaa0a6e80c99799`. This evidence qualifies canonical
source compatibility only; it does not create a release or endpoint acceptance.

[Reference PR #70](https://github.com/nathanmcnulty/azd-reference/pull/70)
merged that exact reviewed Intune tree as
`73009c6ebb91b29a48c3de376e43a8d1da889630`. All five PR checks and post-main
Windows/Linux validation plus CodeQL passed. The security automation source-only
pilot imports the remaining 20 preserved source/test paths, retains host 0.1.4,
and advances runtime to 0.1.7. The repair rejects traversal, encoded or
backslash separators, mismatched hashes, uppercase blob names and final-newline
suffixes before token acquisition or download. Four focused suites pass 43 tests;
compiled-template assertions cover default-none behavior, schedule/hash gating
and Function, Automation and Logic App role scopes. This is offline source proof,
not Function startup, Automation binding, Logic delivery, identity propagation,
report durability, schedule pause, teardown or endpoint acceptance.

A preliminary full runtime/host candidate passed 376/376 tests with an
artifact-isolated Pester 5.7.1. The first attempt remains retained: a concurrent
replacement of the shared CurrentUser module removed `Pester.ps1` after the long
ComponentSync suite, invalidating 320 later container results. After adding
fixture-local commit/tag signing isolation, SecurityPackage passed 11/11 normally
and 11/11 with a hostile inherited signing configuration. Registered parsing and
analysis, backlog and generated-view checks, catalog audit plus 11 tests/build,
component/version and skeleton checks, and all Bicep builds/assertions passed.
Hosted CI ran the complete suite on the exact reviewed commit.

The shared CurrentUser Pester 5.7.1 installation was repaired separately after
independent review. Only the missing `Pester.ps1` runner was copied with
overwrite disabled; all 18 pre-existing files, including installation metadata,
remained byte-identical. The final module has 18/18 trusted payload files, and a
fresh default-module process passed the 10 backlog tests. This repaired the local
validation environment only; no repository file, module version or runtime was
changed. Receipt SHA-256:
`39ed633fd6abe292e60e642ab3036b7576d632439dbe00c24ad38ac1ebe1b2d0`.

[Reference PR #71](https://github.com/nathanmcnulty/azd-reference/pull/71)
merged as `1d126470ec0144820bd89e0eebb588cc183b6fbd`; its tree exactly matches the
independently reviewed candidate. All five PR checks and post-main Windows/Linux
validation plus CodeQL passed. The retained integration receipt has SHA-256
`6420692a33f0960217e96f097615df4f9b00ac4bbbbf16f23f7df748b7147118`.
The source branch was restored at the exact reviewed head. No tag, release,
deployment, identity, grant, schedule or endpoint operation was performed.

IGA-004 reconciled four documentation files in
[PR #19](https://github.com/nathanmcnulty/azd-entra-iga/pull/19). The grant script
and all 58 SDK files are unchanged, and no coordinator or component lock was
adopted. IGA-004 remains proposed because an implementation still needs an exact
tenant/account contract, delegated-scope selection, a successful read-only probe,
an interaction/consent boundary and safe handling or replacement of an existing
Graph context. The exact reviewed tree passed PR and post-main validation. Its
retained integration receipt has SHA-256
`92250c8d85e662dccbfcdd89f01024f8f9c8a7d5aa0ce0f30992cd52e4a70e38`.

The four current staged security consumers upgraded only their runtime lock,
vendored runbook and hardened permission schema in
[PR #39](https://github.com/nathanmcnulty/azd-work-in-progress/pull/39). Each now
pins runtime 0.1.7 to canonical Reference
`1d126470ec0144820bd89e0eebb588cc183b6fbd`; all 48 managed runtime targets match.
Host 0.1.4, Intune 0.1.6, domain/provider/cloud configuration and the historical
Phase 0 root are unchanged. A committed-source combined package verified four
solutions, one source revision, one canonical runtime revision and 123 declared
file hashes. Local validation passed 278 tests, parsing and Bicep compilation;
all three PR and all three post-main checks passed on merged staging main
`cd455be45e620cd07d662ac1bfa206094317e751`, tree
`838421eaef236cbeb9a787d6ec751a00371efc66`. The retained integration receipt has SHA-256
`8b093790f7c8043642fffce15f529271ada59a8b48089fe6b6fcd5f0b03b689a`.
This proves immutable consumer adoption and package provenance, not enabled
hosting, identity propagation, live schedules, endpoint state or teardown.

### Remaining reconciliation and acceptance

HEALTH-006 has a partial value-safe historical assessment: one selected retained
environment has the legacy callback key, another does not, and the exact resource
group recorded by the legacy environment is absent in the selected lab. No
credential value was displayed/copied, and no rotation or environment removal
ran. Historical terminal/CI/artifact locations and tenant-side subscriptions
remain unassessed. Keep those gaps separate from the completed callback source fix.

The remaining proposals still include ordinary engineering that can be selected without
a rollout decision. Proposed status does not mean every item needs human judgment.
The source-only host/runtime pilot and four immutable consumer upgrades do not
complete enabled-hosting, shared identity or lifecycle acceptance. The historical
Phase 0 App Control root has no runtime lock on current staging main and remains
untouched. Historical aggregate branches, dirty quality lineages and other
preserved working copies were intentionally not absorbed or mutated. Retained
runtime 0.1.6 snapshots should not enable Automation or Logic App jobs until
their lineage is selected and upgraded; new work should start from verified
merged main. The source validation finding does not establish deployed exposure.
The gates requiring a concrete target or human acceptance remain Windows GUI/WAM
acceptance, Santa Mac configuration delivery, populated App Control/Defender
pilot endpoints and effective-state/update/rollback proof, real notification or
recovery recipients/routes, standalone publication/releases, and any explicitly
approved catalog-required enforcement. Policy thresholds and shared-identity,
privacy/retention/cost choices also remain product decisions.

### Cleanup and preservation

A fresh read-only AzureCloud audit explicitly selected the lab subscription and
tenant already recorded above. All four exact Health fixture groups and both
prior owned retention/Auth test groups are absent; both prior exact owned role
assignment GUIDs have zero matches. Absence receipt SHA-256:
`1d2e16b22fd9dc3d9855bf0b21e41b55417ae4f8ce7ad36948934d173808fc89`.
No identity, role assignment, Graph subscription, Teams message or endpoint
assignment was created by the synthetic Health fixtures. Their tokens and signed
callbacks remained in memory, and cleanup refused unexpected resources or direct
role assignments before deleting the tagged owned group.

The azd-nathanmcnulty retirement remains recoverable with no unique application
code to migrate. Canonical dirty checkouts, retained environments, immutable
preservation branches, failed lab evidence and successful ignored validation
artifacts remain preserved. Use reviewed current-main sources for new work;
older local snapshots must not overwrite the reconciled backlogs or source.
