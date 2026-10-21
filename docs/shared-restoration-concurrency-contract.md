# Shared restoration: offline concurrency contract

Issue #136 prerequisite only. This is not shared-resource cleanup support and does not close #136.

`tooling/Maester-SharedRestorationPlan.psm1` exports `Get-MaesterSharedRestorationPlan`. It reads supplied dictionaries without opening a journal session, writing locks, contacting providers, or changing resources. The production hooks do not import it. It deliberately remains outside the vendored runtime component until an executor and its independent validation exist.

## Inputs and binding

- `Journal` and `Binding`: the existing version 1 ownership journal and its exact environment, tenant, subscription, resource group, solution and setup-client binding. Existing journal validation applies.
- `Protection`: explicit `applicationObjectIds`, `appIds`, and `servicePrincipalIds` arrays, each limited to 128 GUIDs. Populate these with protected infrastructure identities. The bound setup client is always protected. Access groups cannot be restored or deleted by this contract.
- `Evidence`: `schemaVersion: "1.0"`, exact `binding`, SHA-256 `journalHash`, and an `observations` array (at most 512 entries and 1 MiB canonical UTF-8 total).
- Each observation contains `operationId`, exact UTC round-trip-format `observedUtc`, `state` (`present`, `absent`, or `unknown`), exact receipt `expected` and `exactIds`, and `values`. OAuth observations additionally require explicit `principalId`, which must be null for AllPrincipals. Missing observations never imply resource absence.
- `MaximumAgeSeconds`: 1–3600 seconds, default 900. `Now` defaults to UTC now and is injectable for deterministic offline tests. Neither caller-selected time nor an input hash authenticates provider evidence.

Hashes use the journal's canonical JSON: dictionary keys sorted ordinally, arrays preserved in order, then SHA-256 of UTF-8. They bind snapshots, not identities, authorization, authenticity, or approval. The tests provide synthetic construction examples; no operational registry is needed.

Supported projections must have every field, even when its value is explicitly null:

| Kind | Fields |
| --- | --- |
| ApplicationConfiguration | redirectUris, identifierUris, groupMembershipClaims, enableIdTokenIssuance, enableAccessTokenIssuance |
| OAuth2PermissionGrant (AllPrincipals only) | scopes |

Array fields must be explicit arrays or null; members must be unique strings. Flags must be Boolean or null. Missing, null, empty arrays, false, and differently ordered arrays are not collapsed. Unknown fields and identity mismatches reject the input. An absent or unknown observation must carry an empty values dictionary.

## Decisions

Only an applied, independently recorded shared mutation can be a candidate. Mutations covered by an owned parent are excluded, not reinterpreted as independent restore authority.

- Current exactly equals before: `alreadyAtBefore`, with `noWriteNeededNotRestoreProof`. This does not prove who restored it.
- Current exactly equals acknowledged after: `reviewCandidate`, with `capturedAfterStateMatches`.
- Any other current projection: `blocked / concurrentChangeConflict`. Do not subtract scopes, merge URI arrays, or overwrite unrelated edits.
- Missing, stale, unknown or absent current state, protected identities, unresolved receipt states, unsupported kinds, unsupported principal consent, or receipt chronology inconsistency: blocked.
- An overlapping application object/app identity, repeated OAuth grant ID, or OAuth client/resource/consent tuple is blocked even if an earlier record is terminal or uses a different key. No implicit generation chain is inferred from ordering, timestamps or the newest receipt. This slice detects generation boundaries; it does not implement generation creation or replay.

Every output contains `executable: false` and `authoritativeProviderRead: false`. Every result has `mutationAllowed`, `deletionAllowed`, and `adoptionAllowed` set to false. Output includes operation IDs and reasons but no provider values, target IDs, write payloads, or execution commands. An empty result is not cleanup success. A no-op before/after pair reports already-before rather than a write candidate.

## Required before any future executor

This contract compares captured inputs, so a passing result cannot prevent time-of-check/time-of-use races. A future executor requires an independent review of immutable generation checkpoints, exact object and full grant tuple binding, acknowledged afterstate capture, protected identity enforcement, and partial/unknown write reconciliation. It must obtain fresh authoritative provider state immediately before any action and use provider-supported conditional-write/concurrency mechanisms. Where atomic concurrency cannot be established, it must refuse automatic restoration rather than imply that a second read removes the race.

Execution additionally needs explicit scoped approval and actual caller/cleanup regression tests. Never replay an uncertain provider write or convert a failed shared restore into adoption or deletion. WebAppAuthConfiguration/EasyAuth restoration, per-principal consent, access groups, grant creation, and any Azure/Graph writes are explicitly unimplemented. Native Azure/Graph validation is a separate approval and environment gate, not a prerequisite for these offline tests.

## Validation

Run from repository root with PowerShell 7.6 and the existing Pester toolchain:

```powershell
Invoke-Pester -Path tests/MaesterSharedRestorationPlan.Tests.ps1 -CI -Output Detailed
```

All fixtures are synthetic. No dependency installation, sign-in, provider read, deployment, permission change, or publication is part of the test.
