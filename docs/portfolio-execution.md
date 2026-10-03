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

All four packets are integrated locally into their canonical checkouts. Source
worktrees remain frozen for preservation and review.

| Packet | Result | Validation |
| --- | --- | --- |
| REF-006 | Auth Notifications registered at its actual existing pins; offline validation adapter added; four independent upgrade decisions documented | Independent review; 47 focused Pester tests; full clean reference packet suite 282/282; static/PSSA, catalog 11/11/build, component/skeleton and Bicep checks |
| AUTH-005 | Optional terminal payload retention, disabled by default, with permanent deduplication tombstones and a resumable bounded sweep | Independent review; integrated offline wrapper 37/37 tests, audit with zero vulnerabilities, build/typecheck, Bicep and diff checks; real Azure Table test |
| AUTH-009 | Signed deployment-validation 1.1.1 vendored and locked; existing schema 1.0 plan output preserved | Independent frozen-file review; integrated retention-plus-upgrade wrapper 37/37; three plan checks with provider-call sentinels; managed-file hash parity |
| PIM-005 | Same immutable component adopted with an explicit schema 1.0 compatibility assertion | Independent frozen-file review; integrated canonical suite 121/121 Pester and 14/14 Node; build, Bicep and component drift checks |

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
The central desired-version registry now matches both reviewed consumer locks.
Its final focused suite passed 47/47 independently and during integration.
Device Notifications and Emergency Access remain at 1.0.0; their upgrades are
separate backlog packets. Existing PIM Flex-host drift and lab worktrees were
preserved, as were Auth Notifications permission-tracking changes.

The maintainer subsequently authorized review, commit and push of this batch.
Exact commit and remote-ref receipts are retained with the private execution
artifacts. Preservation branches do not imply a merge to main, a release,
a new hosted CI result or completion of remaining delivery gates.

The same fresh main confirms [Graph retry PR #8](https://github.com/nathanmcnulty/azd-auth-notifications/pull/8)
is merged and issue #7 closed. AUTH-010 records that remote resolution without
resetting the dirty canonical permission-tracking checkout.
