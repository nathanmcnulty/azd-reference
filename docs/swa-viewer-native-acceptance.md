# SWA report-viewer native acceptance packet

Linked source gate: [Reference #128](https://github.com/nathanmcnulty/azd-reference/issues/128).
Source: `examples/swa-report-viewer`. Status: **not run; offline prototype only**.
This packet does not authorize Azure, Graph, credentials, consent, deployment,
publication, identity attachment, cleanup or use of real report data.

## Entry gate and exact private inputs

Obtain explicit preview/support acceptance for function-based role assignment.
Select one disposable SWA Standard site, production environment only, with exact
subscription/tenant/resource group/site IDs, solution environment, application
client/object IDs, dedicated FIC managed-identity IDs/trust tuple and ownership
receipts. Record one approved test audience/app-role assignment, an allowed user,
an unassigned same-tenant user and an other-tenant user. Recover these privately;
do not put live identities, tokens or raw claims into issues/public Git.

Record the reviewed immutable source commit/tree, source/config/function hashes,
reviewed callback claim schema, exact Node runtime and publisher tool/version/digest.
No mutable image tag or automatically downloaded deployer is acceptable. Select
an isolated publisher identity/store and exact deployment-token secret reference
with separate approval; assessment runners must not receive it. Setting names
are not evidence that authentication values or token authority are correct.

Before every separately authorized Azure mutation, including cleanup, perform a
fresh scoped check for exact subscription, expected tenant and Enabled state.
Preserve global defaults and existing sessions. Never device-code authenticate.
Native work belongs in the approved lab boundary, not this source session.

## Ordered checks and evidence

1. **Empty baseline and ownership.** Inventory the site, API linkage, settings,
   app/identity/FIC, role assignments, preview environments and hostnames. Use only
   synthetic non-sensitive content until authorization is proved. Preserve adopted
   objects. Record an owned cleanup/rollback plan before any create or update.
2. **Support and runtime.** Verify Standard, the selected Node 22 runtime and the
   actual packaged v3 function/bindings. Confirm workforce FIC sign-in works with
   the exact issuer/client/identity tuple and no reader client secret. Check that
   the identity is attached only to this site and has no report archive, Graph,
   publisher-secret or resource-write authority. Do not add permissions to make a
   fixture pass. If the selected shape is unsupported, hold rather than silently
   switch to a broader linked Function or different authentication mechanism.
3. **Callback provenance and claims.** Confirm SWA's role function is unreachable
   by external HTTP on every default/custom/API hostname, alternate case/path,
   encoded path, method and preview URL. Try forged headers and a valid-looking
   forged callback body. Capture only sanitized claim-name/type/duplicate metadata
   for a real login. Prove expected tenant/object/role aliases and value formats;
   if the service differs, preserve the failure and review a source change rather
   than relaxing checks live. Prove other tenant/provider, missing roles,
   malformed/duplicate claims and overage fail closed where the service can
   produce them. Offline constructed claims are not platform acceptance.
4. **Audience and all paths.** Allowed user sees exact synthetic report bytes.
   Anonymous, unassigned, other-tenant and wrong-role users cannot retrieve `/`,
   `/index.html`, case/encoding variants, unknown paths, nonexistent assets,
   artifact/config/API paths or any retained/preview deployment. No fallback may
   bypass role checks. Confirm callback and auth endpoints still work under the
   wildcard policy. A redirect/status alone is not proof: inspect returned body
   bytes and every final redirect destination. Test with fresh independent browser
   sessions; a signed-in owner is not sufficient negative coverage.
5. **Revocation lifetime.** Remove/revoke the separately approved disposable test
   assignment, then exercise an existing session and a fresh login. Measure the
   actual session/role refresh and revocation behavior. Role mapping runs at login;
   this source does not promise immediate revocation. Select an acceptable bounded
   policy or keep deployment blocked. Administrator assignment exceptions must not
   bypass `Report.Reader` authorization.
6. **Publisher separation and integrity.** In the isolated privileged publisher,
   read the approved immutable projection, source and prior-state receipt; verify
   every source/config/function and projection hash. Match actual site settings
   against the descriptor's app/FIC IDs and exact target. Build a fresh artifact,
   independently verify its external descriptor digest, then pass only `app/`
   and `api/` to the separately approved fixed deployer. Do not upload the receipt,
   token, approval file, report archives, working tree or test fixtures. Prove the
   runner cannot read the publisher secret, change config/code or choose a target.
7. **Concurrency, interruption and retry.** Implement/review the publisher's
   one-site serialization/current-generation contract before enabling it. Exercise
   two writers, stale plans, canceled upload, failure before and after acceptance,
   lost response and repeated execution. Reconcile the authoritative deployment
   ID and served bytes before retrying an uncertain write. A local generation
   increment and artifact digest alone do not provide a compare-and-swap fence.
   Preserve every failed receipt and the prior qualified artifact.
8. **Token and artifact rollback.** With separate explicit approval, test reset
   and protected-reference update of the site deployment token; verify previous
   credential invalidation without logging credential values. Restore an exact
   previously reviewed artifact under the same concurrency/auth policy. Verify
   actual served bytes, API/config, hostnames and authorization after rollback.
   Receipt generation handling must not silently rewind or overwrite history.
9. **Terminal cleanup.** Follow exact owned-resource receipts and separately
   approved deletion/restoration. Preserve external/shared app, group, identity,
   storage, DNS, assignments and secrets unless their exact ownership/action is
   approved. Fresh readback must prove intended absence or restored state and
   unchanged unrelated inventories; an accepted DELETE is not sufficient. Retain
   failed evidence; no manual cleanup may hide a failed lifecycle acceptance.

## Completion rule

Return sanitized evidence bound to the exact source, target and artifact digest,
with pass/fail/not-run for every check and exact authoritative deployment IDs.
Keep preview support, reader authorization, publisher authority, real report
compatibility, concurrency, rollback and cleanup as distinct gates. Only after
independent review may a component/adoption proposal be prepared. This issue does
not authorize a tag, release, consumer integration, merge or wider deployment.
