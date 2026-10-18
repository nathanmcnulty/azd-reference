# Two-shape Flex execution qualification

**18 October 2026: PIM- and risk-shaped fixture execution, final timer disable
and cleanup completed. REF-004 remains in progress for its separate release,
adoption and migration gates.**

This report records a fresh, disposable execution qualification for the
canonical PIM and risk wrapper shapes. It tests a synthetic fixture against the
shared host boundary. It does not run or qualify either consumer's production
poller, Graph query, checkpoint format, notification or webhook behavior.

## Bound inputs and deployment

The reviewed packet was frozen at SHA-256
`99152298925668acf3d43c6d1b815fc94ecaf749d08a3e3db3bdd4b105908ec1`.
It used canonical source
`3f88050332f9647da5e3bc8044f87cf2c7101c08`, the unchanged
`flex-scheduled-poller-host@0.2.0` component, and the canonical PIM and risk
wrapper shapes. The six shared fixture files retained the previously reviewed
bytes, including the documented extension-bundle range `[4.0.0, 5.0.0)`; each
seven-entry package added only its generated expected binding.

The PIM ZIP SHA-256 was
`5f7b4f8cdc57ba2a1b8f9809029e32d62ac88c652d015fb3b6608ba285792709`;
the risk ZIP SHA-256 was
`bbb0380f6c867a7731d7be14d00032d070d037fef3dc41d9a41de711ee210202`.
Both entry inventories and decompressed hashes passed before upload.

The target was sub-MVP subscription
`a80941e8-c2b9-4bc9-83ad-117cc40d0bea`, expected tenant
`847b5907-ca15-40f4-b171-eb18619dbfab`, region `eastus2`, and exact owned group
`rg-flex-execution-20261018-a6004a0d`. The bounded operator contract required a
fresh matching subscription, tenant, `Enabled` state, cached account and exact
source/owner/nonce group immediately before every write.

One deployment created both fresh shapes. Live binding checks confirmed Node 22,
512 MB, maximum one instance, no always-ready instances, identity-only host and
deployment storage, private deployment/state/dead-letter containers, PIM's
seven-day and risk's fourteen-day Blob retention, and one account-scoped Storage
Blob Data Owner assignment for each system identity. No Queue/Table role, Graph
grant, telemetry resource or operator Blob role was added.

The deployment completed at `2026-10-18T10:15:04.4136407Z`. Both timers were
disabled before package creation. The PIM and risk uploads returned exit code
zero without process or stream timeout at `2026-10-18T10:18:48.2387948Z` and
`2026-10-18T10:18:48.8525388Z`, respectively. Both exact `HttpProbe` and
`TimerReceipt` functions were then indexed with the expected bindings.

## First execution

The timer was enabled once for each shape. After the bounded wait, each
anonymous POST returned 401. The operator then obtained only the function-scoped
default key for that shape's `HttpProbe` and made one authenticated POST to the
exact ARM-derived app hostname. Both returned HTTP 200 and the fixture reported
Node `v22.23.2` with the `v3-function-json` programming model.

At approximately `2026-10-18T10:23:31Z`, both responses bound the expected
source revision, nonce, shape and app. Each reported its distinct timer receipt
present with the expected body. Its nonce-owned state and dead-letter paths both
reported `created` followed by `exact-readback`. The PIM receipt SHA-256 is
`be3fbf5f2b4361d30d0ea3119e2c71191a565f79026fc6c4709e81ee146d157e`;
the risk receipt SHA-256 is
`504a911d4b34b3467802dc2e75f8325b8af5a5811e8d65cf7761abb0475187aa`.
These are app-mediated managed-identity readbacks; no independent operator Blob
read was performed.

## Restart continuity

Both guarded restarts returned exit code zero without client or stream timeout
at approximately `2026-10-18T10:23:54Z`. After the fixed wait, exactly one
additional authenticated POST was made to each shape. PIM qualified at
`2026-10-18T10:26:36.0935401Z`; risk qualified at
`2026-10-18T10:26:35.7555148Z`. In each response, both the process and module
start timestamps were valid UTC values and strictly later than the first
response. The state and dead-letter paths both reported
`already-existed-exact` with `exact-readback`, and the expected timer receipt
remained present.

The PIM second receipt SHA-256 is
`69ab316ea61542fd354d5fb4a46f0df5872920756c415037db07455909578ba5`;
the risk second receipt SHA-256 is
`af7c654d0884cfb55efa3d083d3423ef391113edd0c903d31192d56a79f1d095`.
This is bounded fixture continuity under the maximum-instance-one configuration
across one guarded restart per shape. It does not independently prove worker
count, timer-lease concurrency or scale-out behavior.

## Cleanup and receipt representation

Both final timer-disable writes returned exit code zero, and live readback
confirmed the setting disabled at approximately `2026-10-18T10:27:35Z`.
Cleanup completed at `2026-10-18T10:29:14.3003669Z`. The exact owned group was
absent, both recorded Storage Blob Data Owner assignments returned 404, both
system identities returned 404, and the cached account/cloud/default context
was unchanged. The cleanup receipt reports `cleanupComplete` and
`identityRoleProofComplete` as true with two bindings proved. Its SHA-256 is
`cec9f222b7b9a82915327555dac019cc91552a377a01ddb5f0b3d27ff3e37c5f`.

The executed cleanup script parsed `live-journal.json` without
`ConvertFrom-Json -DateKind String`. When it appended the deletion receipts, it
reserialized earlier UTC timestamps with the local `-07:00` offset. The instants
remain equivalent; for example, rewritten
`2026-10-18T03:13:38.251133-07:00` is the same instant as the original
`2026-10-18T10:13:38.2511330+00:00`. Deploy had already validated the original
UTC receipts, so this representation change does not invalidate the run, but
the executed journal no longer preserves their exact original strings.

The executed cleanup remains preserved at SHA-256
`997b5f58828f0438ed28ea594ac6ff7a6f04333a72d7d6dd456ab1a05f452138`.
An unexecuted sibling adds only `-DateKind String` to that journal read; its
SHA-256 is
`c6e50c8a8543e2bc1f620cf883b504154778da609145fe6efd853dd6709c8006`.
The focused offline serialization receipt is SHA-256
`8d16451f1676bfad628406017f9b15d9a3ac14816943d83bff279ae9e99a3eb7`.
It proves exact `+00:00` strings survive that read/write path; the corrected
sibling was not used for this cleanup and no live action was replayed.

The terminal manifest is stored outside the executed packet so the originally
reviewed packet manifest remains unchanged. It binds 58 final evidence leaves
with SHA-256
`88b54ac50a50f17d088c1cce2dd23429e46dcc323cbe43bc3cd8d2a5b6bbe6ea`.

## Evidence boundary

The completed portion proves deployment, indexing, function authentication,
one distinct timer receipt per shape, conditional Blob creation/readback, and
one guarded restart continuity check for both fresh consumer-shaped fixtures.
It does not prove the
production PIM or risk applications, Graph or webhook behavior, independent
operator data-plane access,
scale-out timer-lease behavior, in-place migration, state continuity across a
consumer upgrade, role reconciliation, root cause for the earlier startup
failure, component release or consumer adoption. The run completes the fresh
two-shape runtime/cleanup evidence recorded here, while REF-004 remains in
progress until the separate release, consumer-adoption, in-place migration and
role-reconciliation gates are addressed.
