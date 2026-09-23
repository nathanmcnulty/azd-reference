# GitHub repository governance standard

`portfolio/github-governance.json` is the machine-readable control contract
for independently supported `azd` repositories. It complements the local
repository baseline: the baseline checks committed files and workflow text,
while this contract checks live GitHub repository settings.

`portfolio/github-governance-repositories.json` is the explicit portfolio
registry for these controls. It records the exact required status-check names
for every supported repository, including matrix job suffixes. This prevents a
workflow rename from silently leaving an obsolete branch-protection context.
It also records each repository's expected visibility and exact selected-action
allowlist, plus a repository-specific release-tag pattern when needed. The
live auditor compares the allowlist as a complete set, scans every workflow
and local action manifest for full-SHA references, and checks each action
outside the repository owner's account against that repository's declared
allowlist. Same-owner reusable workflows remain in the first-party trust
boundary; their references must still use a full commit SHA. It reports unused
visibility changes and default-branch changes until the registry is
deliberately updated.

The registry's `publicRepositoryDiscovery` contract defines the GitHub owner
and `azd-` name prefix. The scheduled governance audit enumerates that owner's
public repositories and fails if any matching repository is missing from the
registry. It also checks each registered repository's live default branch
against the registry.

The registry requires only status contexts that the repository actually
produces. A public repository using GitHub CodeQL default setup may have no
`Analyze (...)` pull-request check; its configured default setup still counts
as CodeQL coverage and must not be replaced with a fabricated required check.

`portfolio/release-integrity.json` is the migration contract for the stronger
`SECURITY.md`, signed release-tag, and artifact-attestation standard. See
[`security-policy.md`](security-policy.md) and
[`release-integrity.md`](release-integrity.md) for the required content and
rollout sequence.

## Single-maintainer model

Every default branch requires a pull request and successful, strict status
checks, but requires zero approving reviews. Conversation resolution and
protection from force-push and deletion remain enabled. GitHub currently models
the owner/administrator bypass as technically available (`always`); the
single-maintainer policy treats that bypass as emergency-only and it must not
be used to hide a missing or stale check.

## Required controls

- GitHub Actions are selected-only. GitHub-owned actions and actions or
  reusable workflows owned by the repository account are allowed; verified
  marketplace actions are not implicitly trusted; every other action has an
  explicit owner/repository pattern.
- Every external action reference uses a full 40-character commit SHA with a
  readable release comment.
- The repository default `GITHUB_TOKEN` permission is read-only. A workflow
  that needs writes declares them narrowly at job or workflow scope and is
  treated as an explicit exception.
- Dependabot security updates are enabled. Every configured update stream is
  grouped and bounded so one maintainer is not flooded with unreviewed PRs.
- GitHub's template-repository flag is disabled. An `azd` deployable template
  is identified by its committed `azure.yaml` and the portfolio registry; the
  GitHub **Use this template** feature is not part of the product contract.
- Public repositories contain a root `SECURITY.md`; its required reporting,
  supported-version, response-target, and safe-disclosure sections are defined
  in [`security-policy.md`](security-policy.md).
- Public repositories enable secret scanning and push protection.
- Public repositories have CodeQL coverage through either a pinned CodeQL
  workflow or GitHub's default setup, plus a dependency-review workflow on
  pull requests.
- Private repositories retain the action, token, Dependabot, pull-request,
  deletion, force-push, and tag controls that their GitHub plan supports. The
  portfolio registry records only validation checks that the repository can
  actually produce; it must not require a CodeQL or dependency-review status
  that GitHub cannot provide for an unlicensed private repository.
- The default branch uses one authoritative active ruleset. Required status
  check names are the current check names, including matrix suffixes; a stale
  legacy context must not be retained alongside the ruleset.
- Public deployable-template release tags use a protected `v*` ruleset that
  blocks update and deletion. `azd-reference` protects its
  `component/**/*` release-tag namespace instead because it publishes
  versioned components; this exception is explicit in the portfolio registry.

The live audit is intentionally read-only. It reports private-repository
features that require a GitHub plan or a repository-administration credential
as unavailable rather than silently treating them as enabled. It does not
change settings, approve pull requests, or merge branches.

The scheduled cross-repository audit uses a dedicated personal-account GitHub
App named `azd-governance-audit`, separate from any App that can publish
pull requests or otherwise write. Install it only on repositories in the
governance registry. Grant only `Administration: read` and `Contents: read`;
GitHub requires `Metadata: read` and includes it automatically. The workflow
limits each installation token to the current registry entries and requests
only the two read permissions it needs. It never changes repository settings.

Store the App's Client ID in the `AZD_GOVERNANCE_APP_CLIENT_ID` repository
variable and its private key in the `AZD_GOVERNANCE_APP_PRIVATE_KEY` secret
for the `github-governance-audit` environment in `azd-reference`. Restrict the
environment to the `main` branch, without a required reviewer, so weekly runs
remain unattended while non-main runs cannot receive the secret. The private
key remains a long-lived credential and must be protected and deliberately
rotated. The workflow uses the SHA-pinned `actions/create-github-app-token`
action to mint a token for the job; that token expires after one hour and is
revoked by the action when the job completes. The audit also guards for `main`,
does not persist checkout credentials, and exposes the installation token only
to its read-only audit step.

Do not reuse the portfolio-updater App or a personal access token for this
audit. A fine-grained PAT restricted to the same repositories and read
permissions is a viable fallback if operating an App becomes disproportionate,
but a recurring cross-repository integration should use the dedicated App.
GitHub's `GITHUB_TOKEN` is limited to the repository running the workflow, so
it cannot read the settings of other repositories; see GitHub's
[token scope documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#authenticating-with-the-api-in-a-github-actions-workflow).

For App registration, selected-repository installation, secret rotation, and
recovery steps, see the [governance audit runbook](../docs/github-governance-audit.md).
