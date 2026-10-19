# Changelog

## 2.0.0

- Breaking runner contract: hosted bundles require schema 2.0 and runnerContractVersion 2.0, with an explicit InvocationContext parameter on every runner. All runners are preflighted before any executes; old bundles are rejected without fallback.
- Pass a fresh immutable, invocation-local evidence boundary through the wrapper and bundle dispatcher. Remove all runtime reads/writes of SECURITY_EVIDENCE_ROOT.
- Add New-SecurityInvocationContext and Resolve-SecurityEvidencePath for explicit hosted confinement and intentional offline reads, including filesystem-aware comparison and ancestor-link rejection. Local legacy dispatch now requires explicit -Offline.
- Require reviewed source capability declarations during packaging. Preserve operator target guards, owned cleanup, package provenance, input hashes, and completion publication.
- Add bounded actual canonical two-runspace overlap/failure/cleanup tests. Consumer runner and nested artifact-helper migration requires separate reviewed immutable adoption; existing consumers are not changed here.

## 1.0.0

- Breaking operator contract: require explicit expected tenant and subscription for publisher, schedule helper, and Azure CLI Blob transfer; bind resources to exact ARM identity and public-cloud endpoints.
- Refresh current ARM subscription Enabled state before each operator write, with explicitly selected token requests and no global CLI default changes.
- Validate deployment targets before packaging and persistent environment changes; propagate expected selectors from azd hooks and bind writes to the selected named environment.
- Preserve hosted managed-identity transfers, immutable package collision verification, default runbook/schedule names and container-scoped permissions. Existing consumer locks remain unchanged pending immutable reviewed adoption.

## 0.1.7

- Require the Automation package blob to be the exact lowercase SHA-256 ZIP leaf bound to the normalized approved bundle hash before requesting a token or downloading content.
- Vendor the current hardened permission-requirements schema as new managed content instead of reusing the 0.1.6 component version.

## 0.1.6

- Capture downloaded input bindings before engine execution, and reject changed or removed inputs before uploading any report.
- Correct the input binding timing found during independent review of 0.1.5; consumers must advance to this version.

## 0.1.5

- Validate packaged file hashes, configuration coverage, runner coverage, and exact source revisions before hosted evidence processing.
- Bind completed reports to the package manifest hash, source commits, and hashes of the downloaded inputs and companion artifacts.
- Missing manifests and changed package files fail before evidence downloads or engine execution. These bindings do not authenticate evidence authors or reviewers.

## 0.1.0

- Pilot PowerShell evidence processing runtime for local, Function and Automation hosts.
- Read-only Graph transport, private Blob evidence transfer, bounded pagination and immutable runbook packages.
- Scheduled processing emits review artifacts; publishing policies requires a separate workflow.

## 0.1.1

- Separate Function host storage and scope evidence/package readers and report writers to containers.
- Refresh scheduled bundle parameters after publication and verify Automation pause requests.
- Reject dirty sources, component drift, mixed runtime revisions and unsafe POST pagination.
- Upload a final report completion manifest; keep incomplete prefixes unaccepted.
- Add azd hooks and package/transition regression tests.

## 0.1.2

- Verify complete component lock schema and every copied host entry point.
- Reject non-hexadecimal schedule package hashes at the template boundary.
- Stage explicitly declared companion artifacts and verify their hashes before execution.
- Constrain hosted file references to the downloaded evidence root.

- Reuse an already uploaded immutable package only after verifying its downloaded content hash; never overwrite it.

## 0.1.3

- Require the configured engine entry point to be tracked in the reviewed source commit.

## 0.1.4

- Support the Azure Flex link-local managed identity endpoint while retaining strict destination and redirect checks.
