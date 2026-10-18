# REF-004 startup diagnosis and bounded next attempt

**18 October 2026: no component defect demonstrated; no source/version change.**
`flex-scheduled-poller-host@0.2.0` remains an unqualified identity-only pilot.
This is the source/fixture investigation for [issue #112](https://github.com/nathanmcnulty/azd-reference/issues/112),
not permission to deploy, grant access, release, merge or adopt it.

## Evidence boundary

The canonical input is `3f88050332f9647da5e3bc8044f87cf2c7101c08`.
Read the [immutable native report](https://github.com/nathanmcnulty/azd-reference/blob/cef1ba8e781289e9f3f087c2bf58ee89debf846f/docs/flex-native-validation-20261018.md)
and [owner follow-up](https://github.com/nathanmcnulty/azd-reference/issues/112#issuecomment-6247339317)
with this analysis. PR #113 owns that report; this document does not rewrite it.
PRs #109 and #111 remain independent; their release/guard work is not replaced.

Both infrastructure shapes passed ARM deployment and configuration readback.
Both package uploads reported completion, but trigger synchronization returned
503, only platform `WarmUp` appeared, and host-key retrieval failed. Server
status 4 is not native acceptance. Some raw responses contained JSON followed
by HTML; a parsed prefix is not a valid complete JSON response.

The public evidence describes seven private fixture files and their behavior,
but does not contain their exact bytes, ZIP entries, import graph or raw host
exception. Those were **not** independently inspected here. The source review
covers the actual Bicep, manifest and checked-in wrapper fixtures, plus the
reported native fixture contract. It cannot certify that private package or
identify a failing JavaScript statement. Codex retains the private originals.
The old disposable group and identities were removed; there is no retained app
to query. No Azure operation was performed for this investigation.

## Contract comparison

### Host storage and deployment storage are separate startup boundaries

The component emits actual Blob/Queue/Table endpoint settings with
`AzureWebJobsStorage__credential=managedidentity`, a system identity, and one
account-scoped Storage Blob Data Owner role. Microsoft's [connection reference](https://learn.microsoft.com/en-us/azure/azure-functions/manage-connections?pivots=functions-auth-identity&tabs=host)
supports identity host storage on Flex and identifies Blob Data Owner for the
timer's host storage. HTTP plus timer and direct Blob operations do not by
themselves demonstrate a missing Queue/Table grant. Extra endpoints do not
require their roles unless an operation actually uses those services. Verify
the private fixture has no unexpected bindings before relying on that scope.

For deployment, the component uses `functionAppConfig.deployment.storage` with
`type=blobContainer` and `authentication.type=SystemAssignedIdentity`. This
matches Microsoft's [Flex infrastructure contract](https://learn.microsoft.com/en-us/azure/azure-functions/functions-infrastructure-as-code)
and official sample at commit
[`46c638a8f1053f6863f478e736290ba0646504fa`](https://github.com/Azure-Samples/azure-functions-flex-consumption-samples/tree/46c638a8f1053f6863f478e736290ba0646504fa/IaC):

- [Bicep main](https://github.com/Azure-Samples/azure-functions-flex-consumption-samples/blob/46c638a8f1053f6863f478e736290ba0646504fa/IaC/bicep/main.bicep)
  uses the same deployment identity and host endpoint/credential pattern.
- Its [RBAC module](https://github.com/Azure-Samples/azure-functions-flex-consumption-samples/blob/46c638a8f1053f6863f478e736290ba0646504fa/IaC/bicep/rbac.bicep)
  also grants Queue/Table and telemetry roles. That broader sample is not proof
  those grants are needed by this HTTP/timer fixture.
- The same repository's [ARM sample](https://github.com/Azure-Samples/azure-functions-flex-consumption-samples/blob/46c638a8f1053f6863f478e736290ba0646504fa/IaC/armtemplate/azuredeploy.json)
  uses system-assigned deployment storage, disabled shared keys, and Blob Data
  Owner without those extra storage roles. Neither sample establishes effective
  access in the failed apps.

Role creation depends on the app identity. ARM completion/readback does not
prove propagation or a successful host identity request. Adding a reverse app
resource dependency on its own role creates a dependency cycle, not readiness.
Do not add broad roles or enable shared keys to test an unproven permission theory.

### Runtime and fixture

The [Node reference](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-node)
explicitly supports Node 22 in both programming models; v3 uses function.json
and defaults when the `@azure/functions` package is absent. A dependency-free
v3 package is not disproved by using Node 22. No conversion to v4 or npm package
addition is justified by `WarmUp` alone. Missing package.json is a fixture
question to inspect, not an established startup cause from the public evidence.
The component's Node 22, FC1 and 512 MB shape is consistent with the
[Flex hosting contract](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan).
The native report specifically verified maximum one and no always-ready
instances. Do not change sizing or scale-to-zero to mask startup failure.

The fixture's `[4.36.0, 4.36.1)` bundle interval permits 4.36.0 and excludes
4.36.1. Microsoft's [4.36.0 release](https://github.com/Azure/azure-functions-extension-bundles/releases/tag/4.36.0)
exists and is labeled Linux-only; Flex is Linux. It is not evidence of a
nonexistent bundle or a Windows incompatibility on these apps. The
[extension-bundle guidance](https://learn.microsoft.com/en-us/azure/azure-functions/extension-bundles)
recommends `[4.0.0, 5.0.0)` and requires runtime access to
`cdn.functions.azure.com`. A public release does not prove that a particular
host resolved/downloaded it. A tight pin is a plausible fixture variable, not
a demonstrated cause. Do not change bundle behavior and roles/runtime simultaneously.

The general [binding registration reference](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-register)
says HTTP and timer triggers run natively. However, the more specific
[Flex trigger considerations](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan#considerations)
require non-C# apps to use the 4.x bundle interval (or a later version). Do not
remove the bundle based on the general guidance. The bounded experiment below
uses the documented `[4.0.0, 5.0.0)` interval, without changing programming model
or permissions. This aligns the fixture with the documented configuration; it
does not prove the original narrow interval caused the failure.

### Why upload success can coexist with failure

[Flex package deployment](https://learn.microsoft.com/en-us/azure/azure-functions/functions-deployment-technologies#flex-consumption-package-deployment)
stores a ready-to-run ZIP in deployment storage; the app subsequently runs from
that package. Upload completion and host initialization/indexing are different
checks. Supported tools select the Flex path even though the CLI command is
named `config-zip`; its name is not evidence that legacy ZIP deployment was used.
No `WEBSITE_RUN_FROM_PACKAGE` setting should be added as a workaround.

The observations locate the missing proof after upload, before verified user
function readiness. They do not uniquely distinguish package mount/read,
identity access, bundle resolution, worker load/import/indexing, host-key storage
or a platform fault. Host-key failure may be a consequence of the host not
starting; it does not demonstrate a key configuration defect. A module-level
exception could prevent loading before the intended handler executes; an error
inside the handler would require invocation first. The private import graph and
host exception are needed to distinguish those cases.

## One bounded Codex diagnostic attempt

This is a proposed runbook for the separately authorized sub-mvp operator.
It does not authorize a new live run. Prefer extracting existing private raw
errors first; do not recreate the already-cleaned resources merely to repeat
queries with no new evidence. If those errors identify the cause, stop here and
review the specific source or fixture correction before another deployment.

### 1. Offline preflight, before any new resource

Codex should inspect the exact retained ZIP and source manifest, verify its
reported SHA-256, and record each of the seven normalized root-relative entries.
Reject duplicate/traversal entries, a parent folder around host.json, missing
files, mismatched function names or a different package. Check function.json
bindings, `scriptFile` resolution/default index.js, CommonJS exports, required
modules, top-level side effects and host.json against the source manifest. Run
syntax and the existing seven boundary tests on actual Node 22; the earlier
Node 26 check is not a Node 22 proof. Keep expected-binding.json bound to the
new disposable app identity if a fresh run is authorized; record that necessary
fixture substitution and new package hash explicitly. Never reuse the old
identity values or describe the new ZIP as byte-identical to the old ZIP.

### 2. One fresh PIM shape, one isolated fixture change

If a run is authorized, use only one fresh PIM-shaped disposable app in the same
region first. Preserve canonical Bicep, Node 22, 512 MB, maximum one, no
always-ready, identity-only storage and seven-day retention. This is diagnosis,
not a substitute for later two-shape qualification. Before **each** write,
revalidate the approved subscription ID, tenant and Enabled state, original
account/cloud/default, exact resource IDs and source/owner/nonce journal. Require
the group to be absent before creation; stop on any preexisting-resource or
ownership mismatch. Do not change the CLI default or request credentials from
another operator. No new grants beyond the canonical disposable deployment.

After the binding/import audit, change only `extensionBundle.version` in
host.json from `[4.36.0, 4.36.1)` to `[4.0.0, 5.0.0)`. Keep the bundle ID,
version, functionTimeout and managedDependency unchanged; preserve the other
six file bytes except the
necessary, journaled expected-binding.json identity/resource substitutions for
the new app. Keep both function.json files, function-auth POST, timer monitoring,
startup-disabled timer and all shared-code identity/Blob guards unchanged. If
unreported bindings or package defects are found, stop and review first.
Record the exact file diff and new ZIP hash; rerun Node 22 syntax/boundary tests.
This proposes one documented-range diagnostic upload, not a proved bundle fix
or a v3 migration. Record the resolved bundle version from available diagnostics.

Perform the canonical configuration readback and that one package upload with remote
build disabled and the same 600-second client timeout. Record CLI version,
package hash, UTC times and server deployment ID. Do not interpret a client
failure or status 4 as permission to restart, sync, reupload or expand roles.

### 3. Capture key-free diagnostics immediately

Let `S` be the exact, journal-verified ARM site resource ID, beginning
`/subscriptions/<approved-id>/resourceGroups/<owned-group>/providers/Microsoft.Web/sites/<owned-app>`.
These are GET requests to `https://management.azure.com`; they are specifications
for Codex, not calls made by this source investigation:

| Read | Exact suffix appended to S | Purpose |
| --- | --- | --- |
| [OneDeploy status](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/get-one-deploy-status?view=rest-appservice-2025-05-01) | `/extensions/onedeploy?api-version=2025-05-01` | Record the Flex deployment result separately from host readiness. |
| [Deployments](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-deployments?view=rest-appservice-2024-11-01) | `/deployments?api-version=2024-11-01` | Select the ID matching this upload, not an arbitrary latest entry. |
| [Deployment](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/get-deployment?view=rest-appservice-2024-11-01) | `/deployments/<observed-id>?api-version=2024-11-01` | Preserve complete/active/status and timestamps. |
| [Deployment log](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-deployment-log?view=rest-appservice-2024-11-01) | `/deployments/<observed-id>/log?api-version=2024-11-01` | Preserve the first failing stage, exception and correlation IDs. |
| [Host status](https://github.com/Azure/app-service-announcements/issues/503) | `/hostruntime/admin/host/status?api-version=2022-03-01` | Capture resolved host version, state and any reported startup errors/bundle metadata without retrieving a function key. |
| [Functions](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-functions?view=rest-appservice-2024-11-01) | `/functions?api-version=2024-11-01` | Distinguish HttpProbe/TimerReceipt indexing from WarmUp-only. |
| [Available detectors](https://learn.microsoft.com/en-us/rest/api/appservice/diagnostics/list-site-detector-responses?view=rest-appservice-2024-11-01) | `/detectors?api-version=2024-11-01` | Discover the actual Flex deployment/startup detector ID; never guess a detector name. |
| [Selected detector](https://learn.microsoft.com/en-us/rest/api/appservice/diagnostics/get-site-detector-response?view=rest-appservice-2025-03-01) | `/detectors/<returned-name>?api-version=2025-03-01&startTime=<UTC-start>&endTime=<UTC-end>` | Read at most the deployment and startup detectors covering this attempt. |

URL-encode path/query substitutions. Validate any returned pagination/log-detail
link against the same trusted management host and owned site/deployment scope
before following it; do not follow secret-file, script or arbitrary returned URLs.
Capture HTTP status, content type, timestamps, request/correlation IDs and raw
body privately. Require the **entire** body to parse as JSON before using it as
structured evidence. Preserve HTML/mixed bodies as protocol failures, never
silently trim them into successful reads. Unsupported/empty detectors or 403/404
responses are evidence gaps, not a reason to add permissions. The portal's
named **Flex Consumption Deployment** diagnostic is a supported alternative
view of existing diagnostics, not authorization to enable monitoring resources.

Host-status reads can cold-start the app, as Microsoft warns in the linked
guidance. Treat those reads as part of this explicitly authorized diagnostic
window, not a passive observation of untouched scale-to-zero behavior. A 200
response alone is not readiness: inspect state/errors and user-function inventory.
Do not run the announcement's subscription-wide sample or change account context.

Take the status/log/inventory snapshot once after the client terminates and once
five minutes later if readiness remains unresolved. Detector reads cover that
fixed interval; stop after the second snapshot. Set a 60-second per-read limit;
stop on throttling with a Retry-After beyond the window. No unbounded polling.
Never list host/function keys, publishing credentials, storage keys, or request
new tokens for this collection. Do not follow secrets_file_href from inventory.
Retain raw evidence privately and publish only redacted excerpts and hashes.

### 4. Decide from evidence, then stop

- An explicit identity/Blob authorization error with the recorded principal,
  account and operation supports an access-path hypothesis; control-plane role
  presence still does not prove data-plane access. Preserve the exact error and
  role readback for review. Do not add Queue/Table/Contributor grants speculatively.
- If the documented-range package indexes both functions, the narrow pin becomes
  a stronger fixture hypothesis only if the resolved bundle actually changed.
  Correlate with retained baseline bundle errors before attributing a cause:
  fresh resources, elapsed time and platform recovery remain confounders. If
  both resolve 4.36.0, this did not test a different bundle. No second upload or
  pin bisect is authorized here. For resolver errors, preserve the exact requested
  and resolved versions, package identity and host.json rather than guessing.
- An explicit Node load/indexing error must be reconciled with the exact ZIP
  and import graph before proposing a fixture correction. Do not replace the
  fixture with v4, an anonymous endpoint or an unguarded Blob writer.
- If both functions appear, indexing is now observed; function authentication,
  timer coordination, state/dead-letter readback and restart continuity are still
  separate acceptance work. Do not claim REF-004 passes or start that work here.
- If only WarmUp/503 or malformed responses remain without an attributable
  error, return the timestamps, region, exact deployment/correlation IDs, package
  manifest and sanitized first-party diagnostics for platform investigation.
  Stop; another blind upload would not distinguish the hypotheses.

Codex owns cleanup even when collection fails: verify journal ownership, remove
only the disposable group under the approved cleanup procedure, and verify exact
group/role-target absence and recorded identity absence. Preserve the original
account/cloud/default and recheck subscription/tenant/Enabled state. Retain the
private ownership/evidence journal. No consumer changes, release, tag, telemetry
infrastructure or automatic role reconciliation are part of this work.

## Qualification remains open

This documentation does not change the component, manifest, wrappers or pilot
version. Offline checks test the existing source boundary only. Successful
native Node loading, authenticated execution, timer leases, exact synthetic Blob
readback, restart continuity, migration/RBAC reconciliation and separately
authorized release/adoption remain required. Issue #112 and REF-004 stay open
until evidence resolves their respective gates.
