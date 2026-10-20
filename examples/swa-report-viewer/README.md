# SWA Standard report-viewer offline prototype

Source scope: [Reference #128](https://github.com/nathanmcnulty/azd-reference/issues/128).
This is **not an azd template, released component, enabled viewer, or deployer**.
No cloud resources, network calls, secrets, tokens, package installation or host
adoption are performed. Existing App Service and Caddy paths are unchanged.
The prototype has no consumer lock or new backlog identifier: it is the bounded
source investigation for the existing issue, not a promoted component stream.

## Support decision, checked 2026-10-20

[SWA custom authentication](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-custom)
requires Standard. Its function-based role assignment is still labelled preview;
custom authentication enables it and invitations are then ignored. The documented
callback is a platform POST with provider claims, and the configured function is
not externally HTTP-accessible. Workforce sign-in can use a dedicated user-assigned
identity/FIC instead of an app secret. That identity must not be shared with other
resources. This authenticates readers, not report deployment.

Decision: **retain as an offline-only preview prototype**. Do not enable it for
confidential reports without explicit preview/support acceptance and the native
packet below. No assertion of GA or production support is made.

The [SWA configuration reference](https://learn.microsoft.com/en-us/azure/static-web-apps/configuration)
lists Node 22 for managed APIs and warns that route rules do not apply to
`navigationFallback`. Therefore this artifact has no fallback. One wildcard rule
requires the custom `report_reader` role for every route, including unknown paths
and assets; there are no public report/error-page rewrites. Native proof must
establish both the role callback and auth endpoints work with this policy.

The [deployment-token guide](https://learn.microsoft.com/en-us/azure/static-web-apps/deployment-token-management)
documents a site deployment credential and token reset/update. A future publisher
holding that credential can replace site configuration and API code, not merely
report content. It must be separately trusted; this prototype never accepts,
retrieves, stores or uses a deployment token. FIC reader authentication is not
claimed to make publication keyless.

## Trust boundaries

- `api/roles.cjs` maps only the fixed `Report.Reader` app role to `report_reader`.
  The trusted callback must contain exactly one expected tenant and one valid
  object ID, the `aad` provider and a nonempty platform user ID. Explicit short
  and URI claim-name aliases are supported. Duplicate semantic tenant/object
  claims, duplicate roles, missing/other roles, malformed values and overage
  markers deny. Claims, counts and individual lengths are bounded. Email,
  `userRoles`, headers and access tokens cannot grant access; there is no Graph
  request, directory-membership expansion or token logging.
- This is **not a JWT verifier**. A body forged with valid-looking claims would
  pass the mapper if someone exposed it outside the SWA platform boundary.
  The configured `rolesSource` isolation is mandatory, not a string/header
  check this code can manufacture. Do not deploy this as a standalone public
  function, linked unauthenticated Function endpoint, or generic authorization API.
- `api/GetRoles/index.cjs` is the actual packaged callback adapter. Its policy is
  generated from the separately reviewed target. The adapter reads only POST
  bodies and never derives identity from `x-ms-client-principal` or caller headers.
  It emits empty roles on rejected claims; no user identity is logged.
- The issuer is exact-tenant, never `common`/`organizations`. The descriptor binds
  the expected sign-in application client ID and dedicated FIC identity client ID.
  Native readback must match `AZURE_CLIENT_ID` and
  `OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID` to those distinct IDs and verify the
  issuer, app role and ownership/trust tuple. Config hashing alone does not prove
  application-setting values, audience validation or effective platform policy.
- The privileged publisher and its approval/descriptor store are trusted and
  isolated from the assessment runner. SHA-256 detects substitution relative to
  a trusted expected digest; it does not authenticate an attacker-supplied digest
  or defend against a compromised publisher. These digests are not signatures.

## Narrow publication-preparation seam

`prepare.cjs` exports `prepareBundle(projectionBytes, approval)`,
`writeBundle(newDirectory, bundle)` and `verifyBundle(directory, expectedDigest)`.
There is deliberately no deployment CLI or network transport. The first operation
is pure apart from reading fixed canonical source files. The writer only creates a
fresh directory, writes fixed paths exclusively, writes the descriptor last and
rechecks every byte. It refuses overwrite. A failed/interrupted directory remains
for inspection and must not be resumed or published. Verification rejects symlinks,
extra/missing files, unexpected directories, wrong lengths and changed hashes.

The separately reviewed `approval` object must contain exactly:

- `schemaVersion: "1.0"`.
- `target`: exact lowercase tenant GUID, ARM `siteResourceId`, `environment` fixed
  to `production`, solution environment name, `applicationClientId` and distinct
  `federatedIdentityClientId`. The initial resource-ID grammar is intentionally
  narrower than all Azure naming forms; unsupported names are not normalized.
- `sourceHashes`: exact SHA-256 for all six canonical source files returned by
  `sourceHashes()`, including the preparer and callback adapter/bindings.
- `configSha256` and `policySha256`: hashes of the exact generated UTF-8 JSON
  bytes. `configFor()` and `jsonBytes()` allow a reviewer to inspect/reproduce them.
- `projection`: exact bounded byte length, SHA-256, run ID and generation of one
  already selected immutable input. Projection acquisition and latest-pointer
  integrity are not implemented here; the caller owns that separate contract.
- `previous`: the last qualified generation and artifact digest, or generation
  zero plus null for an initial fixture. The next generation must be exactly one
  greater and a safe integer.

The hash helpers produce **review candidates**, not approval. Never populate an
approval by hashing an untrusted checkout or taking hashes/config from the report
runner immediately before deployment. Freeze the reviewed source and trusted
approval independently, then prepare. Changing the target, configuration, function
or prior generation invalidates that approval and needs a fresh review.

The projection is bounded UTF-8 JSON, at most 256 KiB, with exactly
`schemaVersion`, `tenantId`, `environmentId`, `runId`, `generation`, `title` and
`sections`. Each section has `heading` and an array of plain-text `rows`.
The test fixture is the executable schema example. Values are escaped into a fixed
HTML layout; there is no raw HTML, archive, file path, URL/asset field or report-
supplied code/configuration. Apparent markup in a text value is displayed as text.
No scripts, styles, images, links, forms or external assets are generated. CSP
adds a restrictive sandbox with no scripts/network/form actions as defense in
depth; escaping and fixed output construction remain the primary content boundary.

This restricted synthetic projection does **not** qualify actual Maester HTML or
replace its report renderer. A real report adapter and compatibility tests remain
separate. Do not widen this parser to accept current HTML without a new reviewed
content/asset policy. Full report data remains in private archives, not this viewer.

Output has exactly two deployer inputs: `app/` and `api/`. `artifact.json` sits
outside both and records `prepared-not-published`, target, projection, prior state,
source hashes and all eight output file hashes/lengths. Keep it in protected
publisher evidence, not the site root. It is an integrity receipt, not a secret.

The previous-generation check is only a **plan**. It is not an atomic SWA
publication fence, and does not prevent two approved preparations racing. A future
publisher must serialize one site/environment, re-read authoritative current
state just before publication, reject stale plans, and reconcile uncertain
outcomes before any retry. Do not claim a failed upload left the old deployment
active without native readback. No publisher concurrency algorithm is enabled here.

## Offline validation

No downloads or Azure tooling are needed:

```sh
node --test --test-reporter=tap tests/swa-report-viewer/prototype.test.cjs
```

The repository aggregate discovers a wrapper in `tests/SwaReportViewer.Tests.ps1`:

```powershell
Import-Module Pester -RequiredVersion 6.2.0 -Force
Invoke-Pester -Path ./tests/SwaReportViewer.Tests.ps1 -CI
```

The Node suite covers callback bodies and actual packaged adapter, config pinning,
source drift, text escaping, exact target/generation/input binding, size/shape
rejection, repeated preparation, no overwrite, partial outputs, inventory/hash
checks and file substitution. Windows skips only symlink creation because the
required privilege is not assumed; all other tests remain required. Local Node
24 execution is source-contract evidence, not Node 22 or Azure runtime acceptance.
