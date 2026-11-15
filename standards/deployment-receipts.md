# Deployment receipt standard

A deployment receipt records intended and applied configuration plus remaining
operational verification. It is distinct from a validation report, which records
checks actually executed.

The reusable receipt envelope contains:

- schema version and generation time;
- template name and version;
- deployment mode (`plan` or `enforce`);
- relative artifact references;
- applied, unchanged, skipped, warning, and failed operation counts;
- feature-specific details in an explicitly named `details` object; and
- unresolved operational actions such as consent or live delivery proof.

Receipts must not serialize local absolute paths, access tokens, callback URLs,
connection strings, or tenant values that are not necessary to understand the
deployment result.

## Candidate shared writer

`deployment-receipt` is a candidate component with no consumer adoption yet. It
writes `reports/deployment-receipt.json` by default and does not establish
target provenance or prove a deployment succeeded. A producer remains
responsible for choosing truthful counts, artifacts, details, and operational
actions.

## Optional management evidence binding

Unbound receipts remain schema version 1.0. Supplying `EvidenceClass` and a
complete `EvidenceBinding` to `New-AzdDeploymentReceipt` emits schema version
1.1 and stores the typed record at `details.azdManagementEvidence`. Bound
receipts use `resourceMutation` for provision, deploy, or up operations and
`cleanup` for down or cleanup operations. The binding records an opaque project
ID and environment, Azure target, template source, and operation UUID. A
reviewed-contract digest and resource group are optional.

`ManagementNextActions` accepts at most 20 registered code, owner, and priority
triples. Consumers must map those codes to their own text. They must not render
arbitrary `details`, legacy `operationalActions`, artifact paths, URLs, or HTML.
The binding and every receipt count remain producer assertions. They support
exact correlation but do not prove resource mutation or cleanup.

Schema 1.1 requires the complete namespace; schema 1.0 forbids it. This makes
older readers reject bound evidence instead of silently ignoring a known
mismatch. Other `details` content remains available to producers and is not part
of the management contract.

## Payload provenance and registry schema 1.1

Receipt schema 1.2 is an opt-in extension for a completed deployment whose
deployed payload was read back and matched to an immutable source revision. The
writer emits it only when the caller explicitly sets
`PayloadReadbackVerified`, supplies resource-mutation evidence for `provision`,
`deploy`, or `up`, reports at least one applied or unchanged action and reports
zero failures. The caller must identify a repository-relative payload-readback
artifact, include it exactly once in `artifacts`, and record its SHA-256. The
source revision must be a full Git commit. The operation UUID is the deployment
identifier. `generatedAt` records receipt creation; the caller supplies the
distinct operation-completion time as `lastSuccessfulDeploymentAt`, which must
not be later than receipt creation. Timestamps are serialized in UTC using the
round-trip format. A 1.2 receipt also records whether a component lock was
verified, not applicable, unknown, or unsupported; it includes a SHA-256 only
for a verified lock. Put full component and file-hash manifests in the bounded
payload-readback artifact; the receipt carries its relative path and digest.

The receipt writer validates those relationships and the JSON schema. It still
records producer assertions. A consumer must check the referenced bounded
payload-readback artifact bytes against the recorded SHA-256 and the receipt
digest before calling the payload verified. The receipt digest belongs in
private evidence or the registry, never in an Azure tag.

Lab registry schema 1.0 remains valid and forbids provenance objects. Schema
1.1 requires an explicit per-environment provenance object. Migration from 1.0
must set its status to `unknown` or `unsupported`; an existing `sourceRevision`
string alone does not promote it to verified provenance. Unknown and
unsupported records carry null deployment identifiers, timestamps, lock
digests, and receipt digests with a bounded reason. Verified provenance requires
a commit, deployment UUID, successful-deployment timestamp and receipt digest.

The read-only status consumer maps verified provenance to four bounded Azure
tag keys: `azd-source-revision`, `azd-component-lock-sha256`,
`azd-deployment-id`, and `azd-last-successful-deployment`. The component-lock
tag is expected only when its status is verified. Tags are emitted only from a
schema 1.1 record whose provenance status is `verified`; legacy and unknown
records are reported as not evaluated. A missing `tags` property on a resource
is reported as unclassified, not as a proven mismatch, until its tag capability
is explicitly established. The status consumer never rewrites tags. A matching
tag still does not prove ownership, payload integrity, or permission to delete.
Solution-specific deployment code must apply these tags explicitly to supported
resources; this status tool only reports their observed drift.

After vendoring the component, import its manifest from the consumer's
`scripts/vendor` directory. The component vendors the matching schema beside
the module, so the default writer call uses that schema without a source-repo
path:

```powershell
Import-Module "$PSScriptRoot/vendor/Azd.DeploymentReceipt/Azd.DeploymentReceipt.psd1" -Force
$repositoryRoot = Split-Path -Parent $PSScriptRoot

$receipt = New-AzdDeploymentReceipt `
    -Template 'example-template' `
    -TemplateVersion '0.1.0' `
    -Mode plan `
    -Skipped 2 `
    -Details @{ feature = 'example' }

Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $repositoryRoot
```

Plan receipts always have `summary.applied` set to `0`; use `enforce` only when
the producer is recording actions it actually attempted. The writer bounds
output, rejects unsafe paths and obvious sensitive text, and writes through a
temporary file. Those checks are heuristic: producers must still avoid putting
secrets in arbitrary text, and a same-user process can race filesystem changes
after the final path check.
