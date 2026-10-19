# Security automation runtime (pilot)

This component runs a vendored PowerShell domain engine against an explicit JSON
evidence snapshot. Local, Function, Automation and Logic App orchestration use
the same CLI contract: `scripts/Invoke-Solution.ps1 -InputPath -OutputDirectory`.
The runtime emits review artifacts. It has no policy publisher or enforcement
API. Engine-specific evidence freshness and coverage checks remain in the engine.

## Deployment

Vendor both `security-automation-runtime` and `security-automation-host` at an
immutable reference revision. A solution's main Bicep selects `none` (default),
`function`, `automation` or `logic-app`. No Graph grants are provisioned. Containers
are private, storage shared keys are disabled, and hosted access uses managed
identity. This initial implementation supports Azure public cloud only.

Commit reviewed source, then build an immutable package with `Build-SecurityBundle.ps1 -SolutionRoot <paths>
-OutputPath <new.zip>`. Multiple roots produce a combined host package; each
engine and its local dependencies are copied into the package. No sibling repo
or private reference repository is contacted at runtime. The package contains
a SHA256 file inventory and exact source commits. Dirty tracked source, component
drift and mixed runtime revisions are rejected. The Automation runbook verifies the full ZIP SHA256
before extraction. Rollback means redeploying a retained approved ZIP/hash.

Runtime 0.1.7 also requires the Automation package blob to be the exact lowercase
`<sha256>.zip` leaf bound to the normalized approved bundle hash before it requests
a managed-identity token or downloads content. Runtime 0.1.6 accepted path-like
blob values that could normalize outside the packages container. This was found
by source review; it is not evidence that a vulnerable job was deployed or run.
Retained 0.1.6 snapshots must not enable Automation or Logic App jobs until their
runtime lock and vendored runbook are upgraded to 0.1.7. Function and local modes
do not use this runbook package-download path.

`Publish-SecurityHost.ps1` uploads the package using cached Azure CLI credentials
and publishes Function source or an Automation runbook. It supports `-WhatIf`.
Publishing does not enable scheduling or grant permissions. Upload each explicit
snapshot as `<solution-id>.json` to the evidence container; hosted runs place
artifacts in a unique run directory in reports. A run is complete only when its
final `completed.json` marker exists and every listed artifact hash matches;
partial prefixes are never accepted as completed runs. Evidence writers can influence
the review result and must be trusted administrators. Use retention controls for
endpoint names, paths and identifiers; no input or token values are logged by
the transport.

For Automation and Logic App modes, the azd postdeploy hook records the published
blob/hash and refreshes provisioned job parameters without republishing another
package. Manual source publication requires a parameter refresh with its output.
Set a future `automationScheduleStartTime` for the
Automation schedule. Only then enable scheduling. Logic App mode is an independent
deployment which invokes its own PowerShell runbook every six hours; it adds
Automation Job Operator for its identity at the Automation account scope. It does
not attempt to execute PowerShell inside a Consumption Logic App action.

## Operator migration to 1.0.0

This major version changes the operator contract; lifecycle status remains pilot. Upgrade only through a
reviewed immutable component revision and normal synchronization tooling; do not
patch vendored files or modify existing locks in place. The host Bicep contract
and hosted managed-identity permission scopes are unchanged.

- Pass `-TenantId <expected-tenant-guid>` and `-SubscriptionId <subscription-guid>`
  to the publisher and schedule helper. These values express the approved target;
  they are never inferred from the CLI default.
- For exported `Invoke-SecurityBlobTransfer -AuthMode AzureCli`, also pass
  `-ResourceGroup <group>` with those selectors, for both upload and collision
  readback. ManagedIdentity mode requires none of these operator parameters.
- Set the intended `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`
  and `AZURE_ENV_NAME` in the selected azd environment, plus the existing storage
  and compute outputs, before hosted deployment. Hooks validate before packaging
  and bind persistent writes/provision to that named environment.
- The operator must already be permitted to read the selected ARM subscription
  and exact storage/compute metadata. A current `Enabled` subscription, matching
  tenant/resource IDs and exact public Azure Blob endpoint are required. The
  component grants no additional permissions to satisfy these checks.

Operator ARM/Blob token requests use `--subscription` and verify returned tenant
and subscription metadata against both expected selectors (Azure CLI makes
`--tenant` and `--subscription` mutually exclusive). Tenant-only
read-only Graph token use remains separate. Every actual write refreshes the
subscription guard; a change after packaging or an earlier write stops later
writes without retries or a success receipt. Earlier successful writes are not
rolled back automatically. CLI global defaults are never selected or modified.

The generic scripts retain `Invoke-SecurityReview` and `SecurityReviewSixHourly`.
Consumers with custom host names still own their separately reviewed publication,
pause/readback and teardown wrappers. This change is not existing-host adoption,
a permission union, runtime qualification, or the separate invocation-context
correction tracked in #121.

## Permission boundary

Local engines require no cloud credentials. The snapshot runtime itself requires
storage access, not Graph permissions. Optional read collectors use Graph permissions
listed in each solution's permission manifest. Combined collectors need the exact
union of selected features; this does not imply all engines should share a broadly
privileged publishing identity. Separate discovery and approved publishing identities.

Function timer hosts use Storage Blob Data Owner on a separate host/deployment
storage account. Both compute identities have only Blob Data Reader on evidence;
Automation also has Reader on approved packages. Reports use Blob Data Contributor
at the reports container scope. Deployment requires Azure resource
write and scoped role-assignment permissions; source upload additionally requires
Blob Data Contributor on packages. Pass an explicitly selected publisher object ID
to assign that container role during provisioning, or use an existing approved
assignment. The evidence writer is a separate administrator/collection identity.

## Verification limits

Offline tests and Bicep compilation do not establish Function startup, Automation
runtime binding, Logic App job delivery, Graph consent, endpoint acceptance or
policy enforcement. Those remain tenant pilot gates. See Microsoft's
[PowerShell Functions guidance](https://learn.microsoft.com/azure/azure-functions/functions-reference-powershell),
[timer storage permissions](https://learn.microsoft.com/azure/azure-functions/functions-bindings-timer),
and [Automation managed identity guidance](https://learn.microsoft.com/azure/automation/enable-managed-identity-for-automation).

Automation schedules are created only with an enabled, configured package. The azd
preprovision hook explicitly pauses and verifies any existing Automation schedule
when the flag is false. Direct ARM callers must use Set-SecuritySchedule.ps1 to
pause a retained schedule; incremental ARM omission does not remove it. Direct
template callers cannot enable a default/empty package hash. Logic App and Function
schedules have explicit disabled settings. Use separate azd environments for compute
alternatives; the hook rejects changing the compute kind of an existing deployment.

## Companion evidence files

An engine that references XML or approval JSON files declares each companion in
its committed `security-bundle.json` solution entry as `artifactFiles`:

```json
{"blob":"reviews/base.xml","path":"policies/base.xml","sha256":"<64 lowercase hexadecimal characters>"}
```

Upload the file to that private evidence blob. The host downloads it under the
input root, verifies its exact hash, and passes an immutable `InvocationContext`
to the engine. The runtime neither reads nor writes `SECURITY_EVIDENCE_ROOT`. Input JSON references must resolve beneath that root. Duplicate or
escaping paths, missing files, and hash mismatches stop processing before report
publication. The package builder preserves the reviewed artifact declarations.
Changing an artifact requires a new reviewed configuration and package.

Hosted processing requires the builder's `bundle-manifest.json`. It verifies
listed file hashes and configuration/runner coverage before downloading evidence.
The final `completed.json` records that manifest's SHA-256, exact source/runtime
revisions, and hashes of the actual downloaded inputs and companion artifacts,
alongside the output hashes. Compare the manifest hash with the approved package
to associate a report with its source. These are content bindings; they do not
authenticate evidence authors, establish reviewer identity, or prove endpoint
delivery. A package ZIP hash remains separate deployment/transport evidence.
Input bindings are captured before engine execution. If an engine alters or
removes downloaded evidence, processing fails before uploading any reports.

For a combined deployment, select one independently deployable solution's host,
then invoke its vendored `Deploy-SecuritySource.ps1 -SolutionRoot <roots>`.
It packages every selected engine, publishes once, and refreshes Automation job
parameters. Shared permission requirements are the union of selected manifest
features, not a prerequisite to running credential-free snapshot engines.


## Invocation contract 2.0 migration

This is a required consumer change and a major runtime version bump from 1.0.0
to 2.0.0. The component remains pilot. Existing locks and vendor copies are not
updated automatically. Synchronize an independently reviewed immutable revision,
then review each consumer's propagation before building or deploying a package.
The security host component is unchanged.

Hosted `security-bundle.json` now has `schemaVersion: "2.0"`; every solution entry
also declares `runnerContractVersion: "2.0"`. The committed source configuration
must include both. Its runner must explicitly declare `InvocationContext` in its
top-level parameter block. The builder and runtime check every runner before
execution; there is no retry that omits the context and no old hosted-bundle
fallback. `bundle-manifest.json` and `completed.json` retain their existing 1.0
content-binding formats.

The wrapper creates a new sealed
`System.Collections.Immutable.ImmutableDictionary[string,string]` for each call:
`contractVersion=2.0`, `mode=Hosted`, canonical absolute `evidenceRoot`, and fresh
`invocationId`. Values are strings. Dictionary updates return a different value;
there is no mutable caller-owned backing collection. No context is stored in
process environment, module state, a global registry, or a current-context stack.
Malformed, mutable, deserialized, missing, and unknown-version contexts fail
closed. Runspaces pass the original concrete immutable object directly; this
contract does not define serialization or remote-process transport.

Runners propagate the exact `InvocationContext` to every evidence-reading helper.
`Resolve-SecurityEvidencePath -Path ... -InputDirectory ... -InvocationContext ...`
accepts an existing file beneath the hosted evidence root, using platform-correct
case comparison, and rejects sibling-prefix escapes, cross-invocation paths,
provider paths and linked/reparse ancestors both above and below the root. A
nested helper that deliberately creates its own verified snapshot constructs a
fresh context with `New-SecurityInvocationContext -Mode Hosted -EvidenceRoot ...`;
it keeps the caller's value unchanged and owns cleanup of its own snapshot only.
Do not infer hosted/offline mode from an environment variable or absent context.

Local legacy schema-1.0 dispatch remains available only with explicit
`Invoke-SecurityBundle ... -Offline`. For helper calls, construct an explicit
`New-SecurityInvocationContext -Mode Offline -EvidenceRoot ...` value. Offline
resolution deliberately retains absolute and parent-relative local file reads.
Schema-2.0 local runners receive an explicit Offline context. Passing an invalid
context never selects Offline mode.

These helpers isolate accidental overlapping trusted invocations; they are not a
sandbox against a malicious runner with ordinary PowerShell filesystem access.
The existing single timer is serialized. A deterministic synthetic local fixture
proved overlap in exported helper calls, not a deployed exploit, disclosure,
default-timer overlap or other host reachability.

### Evidence and remaining consumer gate

The retained original actual-wrapper/AppControl-resolver harness is preserved
privately with SHA-256
`8e5143a49547d313de9c7ef4cdb7873da763c619ef7f639c731137886d481f67`.
It reproduces the old behavior on public source:

- Reference `f5f3e578b929966500a21ad811d11ddacef271f5`, runtime SHA-256
  `9e6a828e1ddd0f1d0990bbb4807fdba804a27bf9446959be2aff13bab106ecdc`
- WIP `5a876bb01e25c2611a5693f93b16d4186abe4618`, AppControl.Core.psm1 SHA-256
  `5be8dfb7a85077fa3df15764eb8a5d4161e49db7664b401bec98e14b51143cd2`

`tests/SecurityInvocationContext.Tests.ps1` and its bounded two-runspace fixture
exercise the actual canonical wrapper, dispatcher and shared resolver with
synthetic runners and strict offline transport/token guards. The nested snapshot
case demonstrates the proposed contract; it is not an actual consumer adoption
claim. App Control's actual runner, policy/candidate/supplemental paths and both
nested artifact helpers still require separately reviewed propagation and actual
consumer red-to-green overlap tests at the adopted canonical revision. Other
security runners also require their own capability and propagation review.
Issue #121 is not fully closed by canonical source evidence alone.
