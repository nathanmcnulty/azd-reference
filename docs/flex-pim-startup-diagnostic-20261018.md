# Single-PIM Flex startup diagnostic

**18 October 2026: the single PIM fixture indexed and cleanup completed; REF-004
remains open.**
This report records one disposable PIM-shaped diagnostic following the bounded
plan in [REF-004 startup diagnosis](flex-startup-diagnostic-20261018.md). It is
not a component release, adoption decision, root-cause finding or REF-004
qualification.

## Bound input and upload

The run used canonical source
`3f88050332f9647da5e3bc8044f87cf2c7101c08` and the unchanged
`flex-scheduled-poller-host@0.2.0` PIM wrapper. The six retained fixture files
were byte-identical to the reviewed private source except that `host.json`
changed only `extensionBundle.version` from `[4.36.0, 4.36.1)` to the documented
range `[4.0.0, 5.0.0)`. The seventh file, `expected-binding.json`, contained the
required nonce and identifiers for this fresh app. The audited seven-entry ZIP
had SHA-256
`bffe9946a07cfc4ac91ae5f5e0827c57750fb5094bc9729cba25389a605f70cc`.

The disposable target was sub-MVP subscription
`a80941e8-c2b9-4bc9-83ad-117cc40d0bea`, expected tenant
`847b5907-ca15-40f4-b171-eb18619dbfab`, region `eastus2` and exact owned group
`rg-flex-pim-diagnostic-20261018-15abedf2`. The reviewed operator contract
freshly required that subscription's ID, tenant and `Enabled` state immediately
before every write, in addition to the exact source/owner/nonce group guard.

The deployment retained Node 22, 512 MB, maximum one instance, no always-ready
instances, identity-only host and deployment storage, seven-day Blob retention,
one account-scoped Storage Blob Data Owner assignment and no telemetry resource.
The timer was disabled before packaging. No Queue/Table role, Graph grant,
telemetry resource, explicit/manual restart or sync, reupload, function
invocation or key collection was added to the bounded procedure. This does not
characterize unobserved internal readiness behavior of the CLI upload command.

The single upload ran from `2026-10-18T09:33:57.5733746Z` through the bounded
client return at `2026-10-18T09:35:20.9623201Z`. The CLI result was exit code
zero with neither process nor stream timeout. That result establishes only the
client outcome; it does not establish host startup, package indexing or function
execution.

## Initial key-free snapshot

The first read-only snapshot completed at `2026-10-18T09:35:48.0903380Z`, about
27 seconds after the upload client returned. It recorded six direct diagnostic
ARM GET responses and no diagnostic write; the context/ownership guard and
app-binding reads also ran. The owned app and system identity matched the
journaled source, nonce, tenant and principal.

- Host status returned HTTP 200 and complete JSON with state `Running`, host
  version `4.1054.250.26428` and resolved extension bundle `4.39.1`.
- Deployment inventory returned HTTP 200 but its body was mixed JSON and HTML,
  so it was preserved as a protocol failure and not parsed. No deployment record
  or log was selected from that response.
- Function metadata returned HTTP 200 and parsed JSON, but the raw body was
  withheld by the collector's credential-pattern guard. This snapshot therefore
  makes no claim that `HttpProbe` or `TimerReceipt` was indexed.
- Detector discovery returned HTTP 200 and identified `FNAPPHostOffline`. Its
  bounded detail request returned HTTP 400 because the service rejected the
  time format. OneDeploy returned HTTP 404 with an empty body.

These observations are materially different from the earlier WarmUp-only/503
attempt, but they do not isolate why. The wider bundle resolved to 4.39.1 on a
fresh resource after additional elapsed time; fixture range, fresh resources,
platform state and timing remain confounded. `Running` plus upload exit zero is
not native acceptance. Function authentication, handler execution, timer dispatch,
conditional Blob writes/readback, restart continuity, the risk shape and
RBAC reconciliation remain untested here.

## Five-minute snapshot

The second read-only snapshot completed at `2026-10-18T09:41:23.5039279Z`.
Host status again returned HTTP 200, state `Running`, host version
`4.1054.250.26428` and bundle `4.39.1`. Function metadata returned the two exact
owned function IDs and expected bindings: function-auth POST-only `HttpProbe`
was enabled, and minute-schedule `TimerReceipt` was disabled as required for
this startup-only diagnostic. This proves that both fixture functions were
indexed in that snapshot. It does not prove either handler executed.

The functions record's `sourceBodySha256` summary field is null because the
collector's optional-property helper did not read an ordered dictionary. The
same snapshot's `records` entry binds the parsed functions response to SHA-256
`c8337892e241de0298b4f3fde261f6d541edb9a4c47ffe89fdad0ae55fd0634e`;
the raw body remained withheld by the credential-pattern guard. Deployment
inventory again returned the same HTTP 200 mixed JSON/HTML body and was not
parsed. OneDeploy again returned HTTP 404 with an empty body. The discovered
`FNAPPHostOffline` detector returned complete HTTP 200 JSON on the corrected
time window, but detector success does not replace deployment or execution
proof.

The exact collector file used for the first snapshot was overwritten during the
bounded correction before its bytes were preserved. The first snapshot JSON and
stored response bodies remain evidence, but that invocation cannot be bound to
a retained collector-file hash. The second snapshot retains its own structured
records and response hashes. This limits reproducibility of the first collection,
not the reported service response bytes.

## Cleanup and evidence boundary

Cleanup completed at `2026-10-18T09:43:02.2185011Z`. The exact owned resource
group was absent, the recorded Storage Blob Data Owner assignment and managed
identity each returned 404, and the original account/cloud/default context was
unchanged. The cleanup receipt reports `cleanupComplete` and
`identityRoleProofComplete` as true.

The terminal private manifest binds both artifact trees and the receipts above
with SHA-256
`c643045532c198ea5039c5dfc0dbbf49587db29df2aa109bba6ead398b3f6def`.
Key evidence hashes are:

- immediate snapshot:
  `90dce2b659f6e8f251817217b4c0eef865956a6d58e4725a09cdee57a28658bb`;
- five-minute snapshot:
  `c037a2d1d3f20f42c2654590d99ca793c0227b4a4b0d9d0b3f16171f7203decf`;
- cleanup receipt:
  `7eb670e4574e7ff21a881e5d5d27babd6dbfb7d625a568d549e8eab705344f5f`.

This run establishes that this fresh PIM-shaped app reached `Running`, resolved
bundle 4.39.1 and indexed both exact fixture functions while preserving the
canonical infrastructure and permission boundary. It does not attribute the
earlier failure to the narrow bundle interval: the resource, bundle, elapsed
time and platform state all changed together. It also does not prove handler
authentication/execution, timer coordination, Blob state/dead-letter behavior,
restart continuity, the risk shape, migration or role reconciliation. No
component/version change, release, consumer adoption or REF-004 completion is
authorized by this diagnostic.
