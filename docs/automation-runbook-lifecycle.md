# Automation runbook lifecycle candidate

`automation-runbook-lifecycle@0.1.0` is a source-only candidate extracted from
[Maester Automation's reviewed runtime-preservation implementation](https://github.com/nathanmcnulty/azd-maester-azureautomation/blob/e9294ff0daf955b48d2ec874e84a983a628ef6bc/scripts/JobScheduleOwnership.ps1).
That source revision has validated composition tree
`d46fc6f7cc6739fa89dca5bb2ec86484405f53c3`. It has no
adopted consumers or release tag. Maester's live evidence establishes its original
consumer behavior, not live acceptance of these extracted bytes.

## Small managed boundary

The component exports only `Update-AzdAutomationRunbookRuntime`. It handles an
**existing** PowerShell runbook and returns true after a verified runtime PATCH,
or false when the verified runbook already uses the requested runtime.

It verifies the exact desired runtime resource's account, ID, name, type,
PowerShell language and version using API `2024-10-23`. It then checks the exact
runbook's identity, Published state, PowerShell type, location, nonblank scalar
runtime binding and expected published source. Only when the binding differs does
it PATCH `properties.runtimeEnvironment`. It reads back the exact resource and
content, requiring the desired binding and unchanged mutable metadata/content.

It never PUTs the runbook, imports source, creates or publishes a draft, repairs
metadata, changes schedules/associations, or grants permissions. Metadata is a
comparison snapshot, never a replay payload. A failed post-PATCH assertion means
mutation may already have happened; there is no automatic rollback or retry.

Content equality deliberately follows the original consumer: remove a leading
UTF-8 BOM character and normalize CRLF to LF; all other text remains exact.
This is normalized text equality, not byte equality or a signed source claim.
Metadata comparison includes location, description, logging flags/activity trace
and tags, including their presence and null state. Read-only timestamps, draft
metadata and parameter declarations are not replayed or asserted equal.

## Caller contract

Required inputs are explicit `ExpectedAccountId`, `RunbookName`,
`ExpectedRuntimeName`, `ExpectedRuntimeVersion`, `ExpectedContent`, and four
scriptblocks:

- `AssertOwnership(accountId, runbookName)` must prove the caller's ownership
  evidence and return exactly the Boolean true. False, null, strings and multiple
  output values fail closed. This trusted adapter is not a security sandbox;
  returning true without proof does not establish ownership. It runs before reads.
- `GetResource(resourcePathWithApiVersion)` returns a detached JSON-compatible
  object or dictionary. The transport must throw on HTTP/authentication failures.
- `GetContent(contentPathWithApiVersion)` returns the exact published source as
  one string, not a draft or a listing entry.
- `PatchResource(resourcePathWithApiVersion, jsonBody)` performs the one PATCH;
  its output is ignored. It must throw on failure.

The callbacks own authenticated transport, selected tenant/subscription/cloud,
HTTP result handling and absence of unsafe redirects. The module never requests
credentials, uses ambient Azure context, downloads code or executes expected
runbook source. Inputs are resource paths rather than absolute network URLs.
Runbook/runtime names are restricted to 1–64 ASCII letters/digits/underscores/
hyphens, starting with a letter or digit. The account path is a canonical ARM
subscription/resource-group/Automation-account path, without trailing slash,
query or fragment. The runtime version must have a numeric major.minor form.
Consumers with unsupported naming shapes must review an explicit contract change,
not bypass validation by pre-encoding path segments.

Callers MUST retain:

1. Fresh versus existing classification from complete, correctly scoped inventory.
   Do not translate authorization, timeout or malformed-response errors into
   absence. Require existing resources in upgrade mode.
2. Account/principal/runbook ownership and provenance checks. Resource ID equality
   alone is not ownership. Maester's receipt/tag and association policy stays in
   Maester; Advanced Auditing uses its own ownership evidence.
3. The Bicep fresh-only creation condition. Existing runbooks must be omitted
   from ARM create-or-update PUTs. Fresh runbooks remain ARM-created. This module
   does not inspect compiled ARM or make that choice for the caller.
4. Before/after schedule and job-association identity/property checks, including
   parameters and runOn where relevant. The module makes no preservation claim
   for those resources. Do not import Maester's service-shape normalization into
   another consumer without reviewing its actual association contract.
5. Explicit source-publication operations, package pins, runner behavior, receipt
   serialization, scheduling, permissions and domain execution. A runtime-only
   upgrade must not invoke the content publisher just to recover a failed check.
6. Concurrency exclusion for other deployers/editors during the operation. Read,
   PATCH and readback are not an atomic compare-and-swap transaction; concurrent
   changes can be detected but cannot be prevented by this helper.

## Reviewed next consumer shape

Advanced Auditing has three runbooks: `Enable-AdvancedAuditing`,
`Validate-ExchangeManagedIdentity` and `Validate-AdvancedAuditingConfiguration`.
Its current template publishes placeholder content before postprovision replaces
it. A future adapter must omit each verified existing runbook from ARM, invoke
this helper per owned published runbook, and retain its own schedule/association
checks. Lifecycle qualification must use inert disposable runbooks and must not
run Exchange remediation or add grants merely to test runtime preservation.

Device Cleanup, Emergency Access and Defender Reporting require separate
adapters. Reporting's publisher also intentionally replaces content and schedules;
it cannot be used unchanged for runtime-only qualification. Security-host's
Automation and Logic-App-backed runbook modes are later candidates. Functions
(Flex/B1), Container Apps and native Logic App workflows have different update
contracts and are not consumers of this helper.

## Qualification and delivery

The candidate tests use injected in-memory callbacks. They must cover rejected
ownership, wrong runtime/target, Edit state, content mismatch, malformed binding,
metadata/content drift after PATCH, callback failures and the already-bound
no-write case. Temporary-consumer synchronization must prove pinned provenance,
exact managed bytes, clean drift detection and refusal to overwrite changed files.

Next gates are independent review, separately authorized immutable release and
explicit consumer adoption, followed by disposable native tests for fresh deploy,
existing runtime change, identical repeat, metadata/content/schedule preservation,
and reverse binding. Do not mass-register consumers or change desiredVersion to
this candidate. Keep the old runtime available when qualifying reverse binding.
Reverting vendored source alone does not revert a deployed runtime or grants.
