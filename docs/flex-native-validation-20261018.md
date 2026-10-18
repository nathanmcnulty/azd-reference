# REF-004 native qualification attempt — 18 October 2026

**Result: runtime qualification failed; the identity-only pilot remains unqualified.**
Both fresh infrastructure shapes deployed, but neither synthetic package reached
verified Node execution, function authentication, timer coordination or state
readback. This is a failed acceptance attempt, not a demonstrated root cause or
a reason to enable shared keys.

## Source and fixture

The component, manifest and PIM/risk wrapper inputs were byte-exact to
`3f88050332f9647da5e3bc8044f87cf2c7101c08` in this repository.
`flex-scheduled-poller-host@0.2.0` remains a source-only pilot. The deployed outer
template composed the captured wrappers with `identityOnlyStorage=true` and
synthetic unused webhook values. It added no Log Analytics, Graph permissions,
consumer business code or runtime dependency on this repository.

Current consumer wrapper bytes still matched the captured inputs:

| Consumer | Verified current main | Wrapper |
| --- | --- | --- |
| PIM | `691ecf4d9b8977e19c66f8dfa2065a40d2e40601` | `infra/modules/polling-function.bicep` |
| Risk-based CA | `1ad0c0d623cbeb14187610c2224c91bbeab905d0` | `infra/modules/graph-notifications.bicep` |

The private qualification package used Node's file-based v3 programming model:
`host.json`, `shared.js`, two functions' `function.json`/`index.js` pairs and a fixed
`expected-binding.json` (seven files, no npm dependencies). Its function-auth HTTP
route was POST-only. Its one-minute timer had monitoring enabled and startup
execution disabled. The extension bundle was pinned to `[4.36.0, 4.36.1)`.
Environment and managed-identity tenant/principal checks preceded fixed synthetic
Blob operations, whose conditional creates required exact readback. This fixture
was not either consumer's production package; fixture assumptions remain part of
the investigation.

Offline preparation passed Bicep 0.42.1 compilation, PowerShell 7.6.6 parsing,
JavaScript syntax, JSON parsing and seven focused Node boundary tests. Local Node
was 26.7.0; it is not evidence of native Node 22 execution. Independent review
corrected identity-endpoint validation and removed a proposed overwrite of
component-owned settings before the first Azure write.

## Native observations

Testing used East US 2 in **sub-mvp**. Every operator write was explicitly scoped
and preceded by a fresh check of the approved subscription ID, tenant and Enabled
state. The original account, cloud and CLI default remained unchanged. The exact
group was absent before creation, then bound to source/owner/nonce tags and a
private creation journal.

Both ARM deployments succeeded. Exact readback verified:

- Node 22, FC1, 512 MB, maximum one instance and no always-ready instances;
- system-assigned identity for deployment storage and the intended app identity;
- shared keys disabled, identity-based host service endpoints and no legacy host
  or deployment connection-string settings;
- three private containers and intended generic/consumer setting aliases;
- PIM/risk soft-delete retention of seven/fourteen days; and
- one account-scoped Storage Blob Data Owner assignment per app identity.

These are configuration observations. They do not prove effective data access.
The deployed settings were verified without overriding them or adding grants.

Each shape received one guarded `config-zip` request with remote build disabled.
Both clients terminated with exit 3 (neither was a local timeout):
`Failed to fetch host key to check for function app status`.

The exact server deployment records reported status 4, complete and active. Their
logs recorded successful upload to storage, followed by trigger synchronization
failure with HTTP 503. Later function inventories contained only the platform's
`WarmUp` function, not `HttpProbe` or `TimerReceipt`. A later bounded PIM host-key
read also failed. Package-upload completion is not host-readiness proof.

Deployment/log ARM responses included a JSON prefix followed by an HTML runtime
error page. Raw responses were retained; extracted prefixes are diagnostic
observations, not clean JSON responses or a successful API-contract validation.

| Shape | Uploaded package SHA-256 |
| --- | --- |
| PIM | `D7D01E5395A1B028F8EF7A978BD7A8E138FD703E51942E9072A42D466C2E0B91` |
| Risk | `8BCF2E1E30C04725BC64C24D55781BFB63E851A8CF6368D96492E212EFA3C7EF` |

No authenticated probe invocation, restart, manual trigger synchronization,
reupload, storage-key fallback or telemetry deployment was attempted. No Graph
collection, webhook notification or real tenant-data operation ran.

## Remaining gates

Investigate source, fixture and platform behavior before selecting a fix or a
bounded retry. The host/deployment identity boundary, native Node execution,
function authentication, timer coordination, exact synthetic state/dead-letter
readback and restart continuity remain unqualified. Successful future fresh-shape
tests would still not establish existing-consumer migration, state continuity or
role reconciliation. Immutable release and consumer adoption require separate
authorization; no tag, release or consumer change was made.

Private evidence retains source/package manifests, raw deployment and function
reads, guard/ownership journals and independent review.


## Cleanup

One guarded deletion request removed the exact owned disposable group. Fresh
absence was verified at 07:46:21 UTC. Subsequent exact role-target GETs returned
not-found responses for the removed storage account/group; both recorded system
identity IDs returned Graph `Request_ResourceNotFound`. This establishes absence
from the active directory, not a purge of directory recycle-bin records. A final
subscription read remained Enabled in the approved tenant; account, cloud and
CLI default were unchanged. No test resources were retained.
