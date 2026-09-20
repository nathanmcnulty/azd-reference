# GitHub repository governance standard

`portfolio/github-governance.json` is the machine-readable control contract
for independently supported `azd` repositories. It complements the local
repository baseline: the baseline checks committed files and workflow text,
while this contract checks live GitHub repository settings.

`portfolio/github-governance-repositories.json` is the explicit portfolio
registry for these controls. It records the exact required status-check names
for every supported template, including matrix job suffixes. This prevents a
workflow rename from silently leaving an obsolete branch-protection context.

## Single-maintainer model

Every default branch requires a pull request and successful, strict status
checks, but requires zero approving reviews. Conversation resolution, linear
history, and protection from force-push and deletion remain enabled. The
administrator bypass is retained only as a recovery path; it is not a normal
merge path and must not be used to hide a missing or stale check.

## Required controls

- GitHub Actions are selected-only. GitHub-owned actions are allowed; verified
  marketplace actions are not implicitly trusted; every third-party action has
  an explicit owner/repository pattern.
- Every external action reference uses a full 40-character commit SHA with a
  readable release comment.
- The repository default `GITHUB_TOKEN` permission is read-only. A workflow
  that needs writes declares them narrowly at job or workflow scope and is
  treated as an explicit exception.
- Dependabot security updates are enabled. Every configured update stream is
  grouped and bounded so one maintainer is not flooded with unreviewed PRs.
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
- Public release tags use a protected `v*` ruleset that blocks update and
  deletion.

The live audit is intentionally read-only. It reports private-repository
features that require a GitHub plan or a repository-administration credential
as unavailable rather than silently treating them as enabled. It does not
change settings, approve pull requests, or merge branches.
