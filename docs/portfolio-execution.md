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
`codex/backlog-reviewed-20261003`. Exact remote hashes were verified. The retained
`azd-nathanmcnulty` checkout has an unavailable configured remote; its local
commit and single-head Git bundle were independently verified instead. Existing
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
