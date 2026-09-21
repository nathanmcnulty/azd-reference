# Proposal: azd catalog validation GitHub App

Status: Proposed

This document describes a possible GitHub App for validating the public `azd`
solution catalog across repositories. It is an architecture proposal, not a
normative repository standard and not an authorization to register or deploy
an App.

## Decision summary

Build a small, initially private GitHub App that acts as a read-mostly control
plane for catalog metadata. It should validate repository-owned
`.azd/catalog.json` files, publish a GitHub Check, and detect drift between the
canonical schema in `azd-reference` and the website's pinned schema copy.

The first version should not modify repositories, execute template code, open
pull requests, change branch protection, or merge changes. Remediation can be
added later as an explicit, user-requested action.

This approach is preferable to putting a copy of the same workflow in every
template repository when the portfolio grows. It also gives the catalog a
single, visible status surface without making the website or a deployment
workflow responsible for governing unrelated repositories.

## Goals

- Validate `.azd/catalog.json` against the canonical catalog schema.
- Detect malformed, unsupported, ambiguous, or obviously stale catalog data.
- Report results on pull requests and relevant default-branch pushes.
- Detect schema drift between `azd-reference` and `azd-website`.
- Revalidate enrolled repositories after a canonical schema release.
- Keep repository access, permissions, and mutations narrowly bounded.
- Produce actionable results without requiring an agent or maintainer to
  reconstruct the entire portfolio history.

## Non-goals

- Running `azd`, PowerShell, Bicep, deployment hooks, or repository scripts.
- Proving that a deployment succeeds or that a quick-start command is safe.
- Replacing the repository README, project documentation, or website editorials.
- Turning display metadata into a deployment, permission, or GUI contract.
- Automatically changing metadata, opening PRs, changing settings, or merging.
- Scanning every public repository on GitHub without an explicit opt-in.
- Making template deployment depend on the App, the website, or a network call
  to `azd-reference`.

## Existing ownership boundaries

The App must preserve the boundaries already established by the portfolio:

| Concern | Owner | App behavior |
| --- | --- | --- |
| Catalog schema and authoring guidance | `azd-reference` | Publish and validate against an immutable revision. |
| Solution facts and concise copy | Each solution's `.azd/catalog.json` | Read and validate; do not rewrite in the MVP. |
| Website-only curation | `azd-website/catalog/overrides.json` | Check for schema/reference drift; leave editorial decisions to the website. |
| Detailed setup, permissions, risks, cost, and cleanup | Solution README and docs | Do not infer deployment behavior from catalog metadata. |
| Deployment and GUI contracts | The solution and `azd-gui` contracts | Do not treat catalog metadata as executable configuration. |

`azd-reference` remains the canonical authoring source. The website may carry a
generated or synchronized copy for local builds, but that copy should identify
the exact reference commit or release from which it came. A website build must
not fetch a floating schema from `main` at runtime.

## Proposed architecture

```text
GitHub webhook
      |
      v
HTTP receiver -- verify signature, deduplicate, acknowledge quickly
      |
      v
Queue / durable work item
      |
      v
Validation worker -- installation token, pinned schema, static checks
      |
      +--> GitHub Check on the source commit
      |
      +--> drift/revalidation record and operational log
```

### GitHub App

Start with a private App installed on the account that owns the portfolio and
only the selected repositories that participate in catalog validation. The
installation's repository selection is the first access boundary. The App
should also require an explicit catalog opt-in, such as the presence of
`.azd/catalog.json` or a documented repository topic, before treating a
repository as a template.

The App should subscribe only to the events needed for the first release:

- `push` for the default branch and relevant catalog changes;
- `pull_request` for opened, reopened, synchronized, and updated PRs;
- installation and repository-selection events for enrollment changes;
- optionally `check_run` later if requested Check actions are introduced.

The App should not use a personal access token. It should mint a short-lived
installation token for the specific repository and minimum permissions needed
for each validation job. Private keys and the webhook secret belong in the
chosen secret store, never in a repository or application log.

### Webhook receiver and worker

The receiver should do only the work required to authenticate and enqueue a
delivery. It should validate the GitHub signature, retain the delivery ID,
return promptly, and avoid doing schema validation in the request path.

The worker should:

1. Verify that the repository is enrolled and that the event is relevant.
2. Bind the job to the commit SHA from the event, not to the moving branch head.
3. Obtain a repository-scoped installation token.
4. Read only the necessary files at that SHA.
5. Load the pinned canonical schema and policy revision.
6. Run deterministic, static validation.
7. Create or update one Check Run for that repository and SHA.

Delivery IDs and the tuple of repository, SHA, event kind, and validator
revision should make retries idempotent. A duplicate webhook must not create an
unbounded set of checks or repeat a future remediation action.

An Azure Function HTTP endpoint with a queue-backed worker is a reasonable
hosting shape for this portfolio. The exact queue and state store can remain an
implementation decision; the architecture requires durable retry and enough
state to recognize duplicate deliveries, token failures, and stale work.

### Validation layers

The MVP should remain deterministic and repository-independent:

1. **Schema validation** — JSON syntax, required fields, types, lengths,
   allowed properties, and the canonical schema revision.
2. **Copy policy** — concise summary, user-facing tags, highlight count,
   supported title shape, and no secrets, generated GitHub fields, or runtime
   configuration in the catalog.
3. **Repository consistency** — when available, compare catalog claims with
   static facts such as the root README, `azure.yaml`, and declared paths.
4. **Cross-repository drift** — compare the website's pinned schema/reference
   revision with the canonical revision in `azd-reference`.

The worker must not execute the README, `quickstartCommands`, `azure.yaml`,
hooks, Bicep, or PowerShell. Commands can be checked for safe shape and
presence, but real first-run validation belongs to repository CI and human
review.

### GitHub Check behavior

Use one stable check name, such as `azd catalog metadata`, and update the run
for the same commit where possible. The check output should include:

- pass, fail, skipped, or neutral result;
- the validator and canonical schema revision;
- a short explanation of each failure;
- links to the relevant standard and repository documentation;
- file and line annotations when GitHub can map an error to a source line.

Missing `.azd/catalog.json` should be neutral or skipped for unenrolled
repositories. A malformed or invalid file in an enrolled repository should
fail the check. Whether the check is required for merging belongs to branch
protection and repository policy; the App should not change that policy.

## Schema and release strategy

The canonical schema is currently
`azd-reference/schemas/catalog-metadata.schema.json`. Before implementation,
choose one immutable distribution mechanism:

- a versioned reference release with a content hash; or
- a commit-pinned schema lock consumed by the website and validator.

Do not validate production checks against a floating branch. A schema change
should be a deliberate contract change that updates the reference schema,
website validator, generated rendering, fixtures, and tests together.

The website should record the canonical schema revision it consumes. The App
can then report a precise drift error instead of comparing two files whose
provenance is unknown. If the website intentionally delays adoption, that
should be represented as an explicit reviewed pin, not as an unexplained copy.

## Permissions and trust model

### MVP permissions

- Repository metadata: read.
- Contents: read.
- Pull requests: read, if PR checks are enabled.
- Checks: write.
- Webhooks: enabled for the selected events.

The MVP should not request repository contents write, workflows, actions,
issues, administration, organization membership, or account permissions.

Those permissions should be added only for a separately designed feature. For
example, an automatic migration PR would need a new threat model, a clear user
action, protected branches, and a narrowly scoped write token.

### Security requirements

- Verify webhook signatures and reject malformed or replayed deliveries.
- Store the App private key and webhook secret in a managed secret store.
- Never log installation tokens, private keys, webhook secrets, or repository
  contents unnecessarily.
- Scope installation tokens to the current repository and minimum permissions.
- Treat all repository content as untrusted data, including metadata strings and
  links. Do not follow arbitrary URLs during validation.
- Do not execute repository-defined code in the App worker.
- Keep the App's own endpoint and queue operationally isolated from deployment
  credentials.
- Record enough evidence to explain which repository, SHA, schema revision, and
  validator revision produced each result.

## Failure and operational behavior

The App should distinguish these outcomes:

- **Invalid metadata** — a deterministic repository failure with file-level
  guidance.
- **Missing or inaccessible repository** — an enrollment or permission issue;
  retry only when the error is transient.
- **Expired or rejected installation token** — refresh once, then surface an
  operational failure without retrying indefinitely.
- **Canonical schema unavailable** — fail closed for the validator and do not
  report a false success.
- **Duplicate or out-of-order delivery** — use the commit and validator
  revision to ignore stale work safely.
- **App outage** — preserve the last Check result and make availability visible;
  do not silently convert an unavailable validator into a passing result.

Logs and metrics should include a correlation ID, delivery ID, installation,
repository, commit SHA, validator revision, duration, and outcome. They should
exclude secrets and unnecessary source content.

## Implementation phases

### Phase 0: settle the contract

- Review this proposal with Sol and record architectural decisions.
- Decide how the canonical schema is versioned and pinned.
- Decide the enrollment marker and whether the website/reference repositories
  are always enrolled.
- Define the check result contract and failure taxonomy.

### Phase 1: prove the App boundary

- Register a private development App with minimum permissions.
- Implement signature verification, delivery logging, idempotency, and health
  checks.
- Exercise installation and repository-selection changes against a test repo.
- Do not grant write access or run repository code.

### Phase 2: implement static catalog checks

- Validate `.azd/catalog.json` at the event SHA.
- Publish the stable Check Run with actionable errors and links.
- Add fixtures for valid, invalid, missing, duplicate, and retried deliveries.
- Test 403, 404, expired-token, malformed-payload, and queue-retry behavior.

### Phase 3: add drift detection and fan-out

- Pin the website schema to an immutable reference revision.
- Check the website/reference pair on changes to either repository.
- Revalidate enrolled repositories after an accepted schema revision.
- Keep fan-out bounded and observable; do not make one failing repository block
  unrelated repositories.

### Phase 4: evaluate explicit remediation

- Only if repeated failures justify it, design a requested Check action to open
  a migration PR.
- Keep the action user-triggered, reviewable, branch-protected, and limited to
  the metadata file or a generated lock file.
- Do not allow the App to approve or merge its own changes.

## Test and acceptance criteria

The first production candidate should demonstrate:

- exact validation at a PR commit SHA;
- successful and failed Check Runs visible in GitHub;
- safe webhook retry and idempotency;
- no token or secret leakage in logs;
- no execution of repository code;
- clear behavior when the catalog file is absent or intentionally opted out;
- detection of a known website/reference schema mismatch;
- bounded revalidation after a schema revision;
- clean recovery from temporary GitHub API, queue, and token failures;
- an installation that can be removed without leaving repository mutations.

## Open decisions for the architecture review

1. Should enrollment be based on App-selected repositories, a repository topic,
   a catalog file, or a combination?
2. Should the App remain private to this portfolio, or is public installation a
   future goal?
3. Should the canonical schema be distributed as a release artifact or a
   commit-pinned file with a lock record?
4. What exact static policy checks belong in the App versus website CI or the
   solution repository's own CI?
5. Which Azure hosting and durable-state services provide the simplest reliable
   operational footprint?
6. Should a missing catalog file be neutral, warning, or a failure for an
   enrolled repository?
7. What retention period and access boundary are appropriate for delivery and
   validation evidence?

## Starting prompt for the architecture review

Use the following prompt in a fresh Sol session:

> You are the architecture lead for the proposed azd Catalog Validation GitHub
> App. Begin by reading `E:\azd-reference\docs\catalog-validation-app-proposal.md`,
> `standards/catalog-metadata.md`, `schemas/catalog-metadata.schema.json`,
> `docs/architecture.md`, and the repository instructions. Perform read-only
> inspection first.
>
> Challenge the proposal rather than accepting it automatically. Compare the
> GitHub App plus Azure Function/queue design with a reusable GitHub Actions
> workflow and explain when each is appropriate. Pay particular attention to
> repository enrollment, cross-account installations, least-privilege
> permissions, schema versioning and immutable pinning, webhook idempotency,
> Check Run behavior, operational failure modes, and the boundary between
> static validation and repository CI.
>
> Preserve these constraints: `.azd/catalog.json` is display metadata only;
> `azd-reference` owns the canonical schema; website overrides remain
> website-only; deployments must not depend on this service; the validator must
> not execute repository-defined code; and no automatic writes, pull requests,
> approvals, or merges are part of the MVP.
>
> Produce an amended architecture recommendation, a permission matrix, a
> threat model, event and data-flow contracts, retry/idempotency behavior,
> observability requirements, a phased implementation plan, meaningful test
> cases, and a list of decisions that require user approval. Do not register an
> App, change GitHub settings, create code, or open a PR in this review session.
> End with a concise go/no-go recommendation for implementation.

## Platform references

- [Choosing permissions for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- [Using webhooks with GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/using-webhooks-with-github-apps)
- [Generating an installation access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [Using the REST API to interact with checks](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-checks)
