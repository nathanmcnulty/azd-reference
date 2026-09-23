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

The scheduled cross-repository audit requires an Actions secret named
`AZD_GOVERNANCE_READ_TOKEN`. Use a fine-grained personal access token scoped to
the repositories listed in the governance registry, including its private
entry. Grant only these repository permissions:

- `Administration: read`
- `Contents: read`
- `Metadata: read`

Do not use a write token. The workflow fails with setup guidance when the
secret is missing. GitHub's
`GITHUB_TOKEN` is limited to the repository running the workflow, so it cannot
read the settings of the other repositories; see GitHub's
[token scope documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#authenticating-with-the-api-in-a-github-actions-workflow).
Give the fine-grained token an expiry and rotate the repository secret before
it expires.
