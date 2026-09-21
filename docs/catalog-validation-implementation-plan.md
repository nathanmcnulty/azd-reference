# Catalog validation implementation plan

Status: Approved for implementation; non-blocking pilot in progress

## Decision

Implement catalog validation as a reusable GitHub Actions workflow before
building a GitHub App. Keep the App as a deferred option that must earn its
operational cost through evidence from the workflow pilot.

The workflow validates repository-owned `.azd/catalog.json` display metadata
against an immutable schema and validator release owned by `azd-reference`.
It does not execute repository-defined code, prove deployment behavior, or
change repositories. Deployments remain self-contained and never depend on the
validator, `azd-reference`, or `azd-website`.

## Portfolio operating model

This plan supports a single maintainer by keeping authority and desired state
central while leaving each solution independently deployable:

| Repository | Responsibility |
| --- | --- |
| `azd-reference` | Own standards, schemas, validator source, immutable releases, desired portfolio state, conformance tests, and read-only drift audits. |
| `azd-work-in-progress` | Stage solution-specific work and validate any staged catalog files by explicit solution path. It is not a public catalog enrollment boundary. |
| Standalone `azd-*` solution | Own solution facts in root `.azd/catalog.json` and a minimal caller workflow pinned to a reviewed validator release. |
| `azd-website` | Consume an exact, provenance-locked schema copy and maintain website-only editorial overrides. |

`portfolio/github-governance-repositories.json` remains the authoritative list
of independently supported repositories, including `azd-reference` itself.
Extend that registry to version 2 with catalog validation desired state instead
of introducing another repository inventory. Version 2 defines one top-level
catalog validator policy:

```text
reusable workflow repository and path
desired full workflow commit SHA
stable check context and source integration ID
```

Each repository defines `catalogValidation.state`:

- `pending`: not enrolled and the check is not required;
- `pilot`: caller workflow is present, but the check is not required;
- `required`: workflow and exact required-check context are governed;
- `exempt`: reviewed `exemptionReason` recorded for a repository that is not a
  deployable solution or cannot participate.

The planned version-2 shape is:

```json
{
  "schemaVersion": "2.0",
  "catalogValidationPolicy": {
    "workflow": "nathanmcnulty/azd-reference/.github/workflows/catalog-metadata.yml",
    "desiredWorkflowRevision": "<40-character commit C SHA>",
    "requiredStatusCheck": {
      "context": "azd catalog metadata",
      "integrationId": 15368
    }
  },
  "repositories": [
    {
      "id": "azd-example",
      "catalogValidation": {
        "state": "pending",
        "catalogPath": ".azd/catalog.json"
      }
    }
  ]
}
```

`catalogPath` defaults to `.azd/catalog.json`. It is optional for a normal
standalone solution and cannot contain traversal. `exemptionReason` is allowed
and required only for `exempt`.

The integration ID shown is an initial GitHub Actions value, not a timeless
constant. Observe it from a real pilot check and confirm it again immediately
before every ruleset mutation.

`required` entries must contain the stable context in `requiredStatusChecks`;
`pending`, `pilot`, and `exempt` entries must not. The live ruleset must bind
the required context to the configured source integration ID. Schema and
validator versions are derived from the
manifest at the one desired workflow revision rather than repeated in every
repository entry. An optional non-root catalog path is allowed only for an
explicitly supported repository shape.

A read-only audit compares desired state with the exact workflow pin committed
in each repository. The caller pin is authoritative; standalone consumers do
not need a second catalog lock. Updating desired state does not modify a
consumer or silently reinterpret an existing check. The website retains its
separate schema provenance lock, and `azd-work-in-progress` retains repository-
local staged-solution configuration because neither belongs to standalone
catalog enrollment.

## Non-negotiable boundaries

- `.azd/catalog.json` is optional display metadata until a repository is
  explicitly enrolled. It is never a deployment, permission, cleanup, GUI, or
  runtime contract.
- `azd-reference` owns the canonical schema, validator, releases, and tests.
- Website overrides remain in `azd-website` and are never accepted by solution
  validation.
- No deployment fetches the validator or schema.
- The validator never invokes `azd`, PowerShell, Bicep, repository scripts,
  hooks, package managers, commands from metadata, or other repository-defined
  code.
- Automatic repository writes, branches, pull requests, approvals, settings
  changes, and merges are outside this plan.
- A passing catalog check means structural and policy compliance only. It does
  not establish that claims are accurate, commands are safe, or deployment
  succeeds.

## Current-state findings to resolve

1. The reference and website schemas are semantically equivalent but are
   separate, differently formatted byte copies with no provenance lock.
2. The website generator duplicates schema rules in hand-written validation
   code instead of evaluating the canonical JSON Schema.
3. The current schema permits an empty object because every field is optional.
4. Writing guidance such as preferred tag, highlight, title, and summary sizes
   is advisory prose rather than a normative schema rule.
5. The current schema `$id` is stable but unversioned.
6. “Obviously stale” content and factual agreement with README or `azure.yaml`
   cannot be established reliably by a deterministic static validator.

These are contract decisions, not reasons to make the validator infer solution
behavior.

## Target architecture

```text
pull request / default-branch push / manual dispatch
                         |
                         v
        small repository-owned caller workflow
                         |
                         v
        reusable workflow pinned by full commit SHA C
                         |
                         v
      co-located validator action + schema at commit C
                         |
                         v
         read only the catalog file at event SHA
                         |
                         v
        deterministic result in GitHub Actions UI
```

### Caller workflow

Each enrolled standalone solution has a small caller in
`.github/workflows/catalog-metadata.yml` with:

- `pull_request` actions `opened`, `reopened`, `synchronize`, and optionally
  `ready_for_review`;
- `push` on the default branch;
- `workflow_dispatch` for base-repository diagnosis only;
- top-level `permissions: contents: read`;
- a reusable-workflow reference pinned to a full 40-character commit SHA with
  a readable release comment;
- no secrets and no write permissions.

Do not use `pull_request_target`. Do not use path filtering if the check will
be required; a required workflow must always produce its stable result. The job
may return quickly after determining whether the repository is enrolled and
the file exists.

The immutable validation input is event-specific:

- pull request: base repository ID, head repository ID and full name, exact
  head SHA, and normalized catalog path;
- push: event repository ID, exact `github.sha`, and normalized catalog path;
- manual dispatch: an explicitly selected base-repository ref for diagnosis.

Manual dispatch does not substitute for a required check on a fork PR head.
Fetch the catalog through a non-shell path at the bound repository and SHA.
Require an ordinary bounded blob; reject unsupported symlinks, submodules, Git
LFS pointers, deleted or inaccessible fork heads, and paths that escape the
configured solution root. Checkout, if used, must disable persisted
credentials and explicitly select the bound repository and SHA.

### Reusable workflow and validator action

The reusable workflow supplies orchestration, stable output, and least-
privilege defaults. It must not fetch validator or schema bytes from a floating
branch. A workflow SHA alone is not an adequate pin if its implementation then
downloads mutable content.

Use a dependency-bundled JavaScript action committed under `azd-reference` with
its schema and conformance fixtures. Do not download a release archive at run
time. Publish the workflow, action, schema, tests, and content manifest together
in one reviewed commit C. The reusable workflow invokes the co-located action
with `uses: $/.github/actions/catalog-validator`, which GitHub.com resolves in
the called workflow's repository at the running workflow commit. Consumer
callers invoke the reusable workflow at the full commit C SHA.

The reusable job asserts `job.workflow_repository`, `job.workflow_file_path`,
and the expected full-SHA shape of `job.workflow_sha`, then records the runtime
SHA in the result. It cannot inspect the caller's literal `uses@<commit-C>` pin
or embed its own commit SHA without creating a self-reference. After commit C
is published, a later governance-registry commit records C as desired state;
the separate central audit compares each caller's literal pin with that state.
`$/` and the `job.workflow_*` identity properties are GitHub.com features;
GitHub Enterprise Server is outside the initial support contract.

GitHub documents the `$/` resolution and reusable-job identity fields in its
[workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
and [contexts reference](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts).

This avoids an ambiguous checkout: a normal checkout in a called workflow
refers to the caller repository, while the `$/` action reference resolves to
`azd-reference` at commit C. The content manifest at commit C records:

```json
{
  "contractVersion": "1.0",
  "schemaVersion": "1.0.0",
  "schemaPath": "schemas/catalog-metadata.schema.json",
  "schemaSha256": "<SHA-256>",
  "validatorVersion": "1.0.0",
  "validatorSha256": "<SHA-256 of bundled validator bytes>"
}
```

The action verifies its committed manifest and schema digest before validation.
`job.workflow_sha` and GitHub run provenance establish commit C; the validator
must not trust a caller-supplied workflow revision.
Use `catalog-validator/v<semantic-version>` as a discoverability namespace.
Because full SHAs are authoritative, tag movement cannot change a consumer's
executed code. Before relying on tags operationally, extend governance to audit
multiple protected tag namespaces; the current governance registry protects
only `component/**/*`.

### Website consumption

`azd-website` keeps a local schema copy for deterministic local builds. Add a
lock that identifies the exact reference commit, release, source path, and
SHA-256. Website CI verifies exact bytes against that lock and uses the same
JSON Schema implementation and conformance fixtures as repository validation.

The website continues to validate `catalog/overrides.json` under its own
website-only contract. The shared solution validator neither reads nor merges
overrides.

### Staging behavior

`azd-work-in-progress` may contain multiple solutions. Its repository CI calls
the same immutable validator bundle with an explicit, committed solution-root
path. A staged solution does not become a supported catalog entry merely by
adding metadata.

Promotion to a standalone repository adds the root catalog file, caller
workflow, governance registry entry, and rollout state through the existing
linked promotion process.

## Validation contract

### Normative failures

The initial validator fails only for deterministic contract violations:

- catalog file missing from an explicitly enrolled repository;
- file exceeds the configured byte limit;
- invalid JSON, including a documented duplicate-key policy;
- value does not conform to the pinned JSON Schema;
- unsupported properties;
- prohibited remote schema resolution or other attempted network references;
- validator or schema digest does not match the release manifest.

Before implementation, amend the schema or a separately versioned deterministic
policy contract to define maximum file, string, array, and nesting limits. Do
not silently promote prose guidance into failures.

### Advisory findings

Writing guidance remains a notice and does not fail the check unless it is
first adopted as a normative contract change. Examples include preferred title
word count, summary length, number of tags or highlights, tone, and potentially
stale wording.

### Repository-owned CI and review

Repository CI and human review remain responsible for:

- whether claims describe implemented behavior;
- whether `quickstartCommands` agree with README, `azure.yaml`, hooks, and the
  supported first-run path;
- deployment, cleanup, permissions, consent, cost, and operational safety;
- any executable validation of Bicep, PowerShell, application code, or `azd`.

The catalog validator may treat command strings as inert text. It must not
execute or attempt to prove them safe.

## Result contract

Use one stable check/job name: `azd catalog metadata`.

The machine-readable result contains:

```text
contractVersion and eventKind
baseRepositoryId
sourceRepositoryId and sourceRepositoryFullName
validatedCommitSha
catalogPath
catalogBlobSha
workflowRepository, workflowPath, and workflowSha
schemaVersion and schemaSha256
validatorVersion and validatorSha256
outcome: valid | invalid | operational_error
errors[]
notices[]
durationMs
```

Presentation behavior:

| Condition | Result |
| --- | --- |
| Valid schema and policy | Success |
| Advisory writing findings only | Success with notices |
| Invalid or missing metadata in an enrolled repository | Failure |
| Repository not enrolled | No caller workflow and therefore no expected check |
| Validator/package integrity failure | Operational error; never success |
| Newer schema available | Current pin remains valid; central audit reports drift |

Cap output and annotations so malicious input cannot flood logs or the GitHub
UI. Do not include repository file contents in diagnostic telemetry.

## Least-privilege matrix

| Capability | Reusable workflow MVP | Deferred GitHub App |
| --- | --- | --- |
| Repository metadata | Event context | Read |
| Contents | Read | Read |
| Pull requests | None required for validation | Read |
| Checks | GitHub Actions publishes its own result | Write |
| Actions/workflows | None | None |
| Issues | None | None |
| Administration/settings | None | None |
| Contents write | None | None |
| Secrets | None | Webhook secret and App private key |
| Enrollment | Reviewed caller plus governance state | Selected installation plus numeric repository-ID allowlist |

## Threat model and controls

| Threat | Required control |
| --- | --- |
| Mutable validator or schema | Full-SHA workflow pin plus release-manifest digests; never fetch `main`. |
| Repository code execution | Read only bounded metadata bytes; no package manager or repository entry point. |
| Caller workflow bypass | This design cannot independently protect its caller. Use maintainer review and exact-pin/context audits as detective controls. |
| Malicious catalog content | Treat all strings as data; no command execution, URL following, templating, or remote `$ref`. |
| Parser denial of service | File, string, item, depth, runtime, output, and annotation limits. |
| Secret disclosure | No secrets in the workflow; redact paths/tokens and avoid logging source contents. |
| Validator differential | One conformance fixture set used by the validator, website, and release tests. |
| Stale pin | Desired versions in the governance registry and scheduled read-only drift reporting. |
| Check-name drift | Stable job name and live governance audit before making the check required. |
| Forked PR abuse | `pull_request`, read-only token, no secrets, no execution, and a live public-fork acceptance test. |
| Dependency compromise | Minimize dependencies and pin every external action and validator artifact immutably. |

The repository-owned caller is not an independent anti-tamper boundary. A PR
can attempt to change or replace its workflow while presenting a similarly
named Actions result. For this single-maintainer portfolio, maintainer review,
workflow-diff visibility, exact-pin auditing, and post-merge drift detection
are detective controls. Do not describe a required Actions check as resistant
to caller tampering. If independent enforcement becomes necessary, that is a
specific trigger to evaluate the deferred App or another base-controlled
external check.

## Operations and observability

The Actions-first design should not introduce a separate production service.
Use GitHub workflow logs and a scheduled read-only portfolio audit to report:

- enrolled, pending, required, and exempt repositories;
- actual versus desired schema and validator versions;
- missing caller or catalog files, plus a missing website provenance lock;
- mutable or unexpected workflow references;
- required-check context mismatches;
- most recent default-branch result when available;
- website schema provenance drift.

Before broad required rollout, implement a local preserve-first pin updater
using the established Plan → isolated Prepare → separately authorized Publish
model. It resolves the desired commit C from reviewed provenance, edits only the
exact caller pin, validates the consumer, and never approves or merges. Pilot
updates remain manual so the managed file boundary is proven before automation.
Record time spent updating pilot pins; repeated portfolio updates requiring
more than one maintainer work session are a signal to improve the updater, not
an automatic reason to build an App.

The audit must not execute consumer code, write repositories, or change GitHub
settings. Retain the generated report as a bounded workflow artifact consistent
with the existing portfolio drift process.

Operational errors must be distinguishable from invalid metadata. A validator
outage or integrity failure must not produce a passing result. Because this is
not a deployment dependency, an outage may block a protected merge but cannot
break an existing deployment or deployed solution.

## Phased execution plan

### Phase 0 — approve and version the contract

Deliverables:

- approve this Actions-first architecture;
- decide whether `{}` remains valid;
- decide which current writing rules, if any, become normative;
- define byte, depth, length, item, runtime, and output limits;
- version the schema `$id` and release/lock formats;
- reserve the stable check name and validator tag namespace;
- define the governance registry extension and schema migration.
- approve the single-commit-C action/workflow packaging pattern;
- define per-repository authorization for caller rollout and required-check
  mutation.

Exit gate: decisions are recorded, schemas validate, and no consumer behavior
has changed.

### Phase 1 — build the canonical validator in `azd-reference`

Deliverables:

- deterministic validator with no repository-code execution path;
- shared result contract;
- schema/validator release manifest and hash verification;
- conformance, security, and resource-limit fixtures;
- dependency-bundled JavaScript action, schema, manifest, and reusable workflow
  at commit C, using a `$/` self-repository action reference;
- assertions for `job.workflow_repository`, `job.workflow_file_path`, and the
  full-SHA shape of `job.workflow_sha`, plus runtime SHA evidence;
- release procedure and protected immutable tag convention;
- read-only desired-versus-actual audit support, including comparison of the
  required check's context and source integration ID.

Exit gate: local tests plus two disposable external callers prove deterministic
results from commit C. A normal checkout must be shown to target the caller,
while `$/` executes only the action co-located with the pinned reusable
workflow. After C exists, a separate registry commit records it as desired
state and the central audit proves each caller's literal pin.

### Phase 2 — align `azd-website`

Deliverables:

- provenance lock for the website schema copy;
- exact-copy/hash verification;
- shared schema evaluation replacing parallel hand-written shape rules;
- unchanged website-only override behavior;
- regression tests for generated catalog content.

Exit gate: reference and website conformance suites agree, and the website
build remains deterministic without fetching a floating reference branch.

### Phase 3 — non-required pilot

Pilot repositories:

1. one conventional standalone solution with a simple existing validation
   workflow;
2. one repository with materially different workflow naming or structure;
3. `azd-work-in-progress` with an explicit staged-solution path.

Deliverables:

- caller workflows pinned to the reviewed release;
- same-repository and public-fork PR evidence;
- default-branch push and manual-rerun evidence;
- central audit of exact versions and check names;
- measured runtime, maintenance friction, and false-positive rate.

The fork proof records pending-approval behavior for first-time contributors,
deleted/inaccessible fork heads, and whether organization Actions policy permits
the reusable workflow. Manual dispatch is tested only as a base-repository
diagnostic path.

Exit gate: at least two standalone solutions and one staged solution pass the
same release without repository-specific validator logic. Checks are still not
required.

### Phase 4 — staged portfolio rollout

- update governance registry states through `pilot`, `required`, and broader
  rollout rings only with authorization for that ring;
- add callers through focused, reviewable repository changes, with separate
  authorization for each consumer or explicitly approved rollout ring;
- update desired pins centrally only after the release is proven;
- implement and prove the preserve-first pin updater before broad rollout;
- authorize each selected-Actions/reusable-workflow policy change separately;
- authorize each required-check ruleset mutation separately;
- before requiring the check, read and fingerprint the current exact ruleset ID
  and JSON, confirm
  the caller on the default branch, observe the real context through the Checks
  API on same-repository and fork PRs, capture its source integration ID,
  confirm the administrator recovery path, re-read and abort if the ruleset
  fingerprint drifted, merge only the intended `(context, integrationId)` pair
  into current state, verify the post-write diff, and verify mergeability;
- preserve an administrator bypass solely as the existing recovery path.

Exit gate: every supported standalone solution is `required` or has a reviewed
`exempt` reason; staging and website behavior remain separately governed.

### Phase 5 — evaluate, do not assume, a GitHub App

An App receives a new architecture and approval review only if pilot evidence
shows at least one of these needs:

- repository-controlled workflows cannot provide an acceptable independent
  trust boundary;
- central revalidation without consumer changes is required;
- Actions policy prevents reliable validation;
- cross-account installations need centrally owned checks;
- repository-by-repository enrollment or pin updates create material ongoing
  burden for the maintainer.

If approved, start with a private App on one owning account and one test
repository. Cross-account installation requires a public or enterprise-internal
App and separate approval. The App design must include webhook authentication,
durable acceptance, retry, idempotency, dead-letter handling, forked-PR proof,
short-lived repository-scoped tokens, and observable Check Run lifecycle.

## Test plan

### Contract and conformance

- complete valid metadata;
- valid empty object if retained by the approved contract;
- invalid JSON and duplicate-key behavior;
- unknown properties, empty strings, duplicate arrays, and invalid integers;
- each size, count, depth, and runtime boundary;
- Unicode, line endings, and deterministic error ordering;
- identical results in the reference workflow and website validator.

### Trust boundary

- shell syntax, workflow expressions, Markdown, URLs, and path-like strings
  remain inert;
- malicious repository scripts, hooks, package manifests, and binaries are
  never invoked;
- remote schema references and arbitrary URLs are never fetched;
- checkout credentials are not persisted;
- no secret is available to the validation job;
- mutable workflow, action, or bundle references fail governance validation.
- corrupted manifest, schema, or validator bytes fail independently;
- truncated or oversized inputs fail before parsing or execution.

### GitHub integration

- same-repository PR at the exact head SHA;
- public-fork PR and first-time-contributor approval behavior;
- default-branch push;
- catalog addition, edit, deletion, and rename;
- manual rerun;
- stable result name across events;
- changed, renamed, deleted, skipped, and no-op/spoofed caller workflows, with
  documented proof that the check is detective rather than tamper-resistant;
- selected-Actions or reusable-workflow access denied;
- reference repository renamed, made private, or unavailable;
- fork head repository deleted or inaccessible;
- symlink, submodule, Git LFS pointer, path traversal, and staged-root escape;
- fork run awaiting approval or expiring;
- concurrent reruns or cancellation never produce false success;
- repository with catalog changes absent still produces the expected required
  result once enforcement is enabled.

### Portfolio operations

- pending, pilot, required, and exempt registry entries;
- atomic state/check invariants: only `required` contains the catalog context;
- actual pin older or newer than desired;
- correct context with the wrong source integration ID;
- missing workflow, catalog, website provenance lock, or required-check pair;
- website schema copy with wrong bytes or provenance;
- staged solution path and standalone promotion;
- one repository failure does not prevent auditing others;
- audit remains read-only and never executes consumer validation.
- stale required context and exact-context rollback that preserves all other
  ruleset settings.

## Rollback and recovery

- Before a check is required, rollback is removal of the pilot caller and
  registry state reversal through normal review.
- After it is required, use a separately authorized recovery operation against
  the previously captured ruleset ID. Re-read current state rather than
  restoring a stale snapshot, abort on unexpected drift, remove only the exact
  catalog `(context, integrationId)` pair, preserve every other rule, verify the
  resulting diff and mergeability, and only then permit caller removal. Never
  leave branch protection waiting for a check that cannot be produced.
- A bad validator release is never moved or overwritten. Publish a new version,
  return desired state to the last known-good release, and update pins through
  review.
- Existing deployments and initialized templates require no rollback because
  they do not consume this validation service.

## Decisions requiring maintainer approval

1. Approve Actions-first and defer the GitHub App.
2. Approve use of the governance registry for catalog rollout state.
3. Decide whether an enrolled catalog may be `{}` or must contain a minimum
   useful field set.
4. Select the normative size/count limits and any prose rules promoted to
   failures.
5. Approve the schema version, website lock, single-commit action/workflow release,
   and tag conventions.
6. Approve the pilot repositories.
7. Approve each consumer or rollout ring before caller changes are published.
8. Approve any Actions-policy change separately.
9. Approve each repository ruleset mutation that makes
   `azd catalog metadata` required, with its captured rollback evidence.
10. Approve the preserve-first pin updater before it can publish draft PRs.
11. Accept or reject the first-time-fork approval delay before requiring the
    check on public repositories.
12. Approve any future App evaluation separately from this workflow plan.

## Go/no-go gate

Go for Phase 0 contract decisions and Phase 1 implementation only after the
decisions above are approved. No-go for GitHub App registration, Azure service
deployment, consumer rollout, required-check changes, or automated repository
mutation under this plan.
