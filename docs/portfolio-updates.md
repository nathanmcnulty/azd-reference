# Portfolio updates

## Registry

`portfolio/consumers.json` records machine-neutral checkout directories,
solution roots, repository validation workflows, offline validation entry points,
approved component versions, rollout rings, and adoption state.
Callers supply the local portfolio root; the registry contains no absolute paths
or credentials.

`repositoryValidationWorkflow` and `validation.entryPoint` are relative to the
consumer repository checkout root. This keeps a monorepo solution explicit: for
example, PIM registers `.github/workflows/validate-azd-pim.yml` and
`azd-pim/scripts/Test-Repository.ps1`, while validation still runs with the
solution root as its working directory.

A component-free standalone solution registers an empty `components` array.
This keeps its validation and governance contract visible without claiming a
vendored component dependency that does not exist.

Use [`standards/standalone-promotion.md`](../standards/standalone-promotion.md)
when a registered consumer is moving out of `azd-work-in-progress`. Component
rollout automation updates an existing consumer; it does not replace the
standalone-repository promotion process.

When a consumer declares `desiredBaseline`, both planning and preparation pass
that exact value to component synchronization. Preparation writes it into
`azd-components.lock.json` in the same transaction as the component update and
reports the resulting baseline.

`Get-AzdPortfolioStatus.ps1` is read-only. It does not fetch, clone, checkout,
execute consumer code, or write reports by default. It validates locks and reports
unavailable checkouts, unsafe or missing files, substantive drift, unmanaged
canonical targets, release-tag provenance mismatches, version differences, and
repository baseline findings. Each consumer's declared validation workflow must
exist; the generic baseline does not assume a file named `validate.yml`.
Baseline checks include SHA-pinned external
actions, top-level `contents: read` workflow permissions, and grouped, bounded
Dependabot updates.

The separate `tooling/Get-AzdGitHubGovernanceStatus.ps1` audit queries live
repository settings without changing them. It checks the selected-action
policy, SHA enforcement, default workflow permissions, Dependabot security
updates, public-repository scanning controls, and the authoritative default
branch and release-tag rulesets. Run it with an authenticated `gh` session
that can read repository administration settings:

```powershell
./tooling/Get-AzdGitHubGovernanceStatus.ps1 `
  -Repository nathanmcnulty/azd-risk-based-ca `
  -AsJson
```

The audit deliberately treats exact required status-check names as live
repository configuration. A workflow file can exist while a ruleset still
requires an obsolete context, as happened when a matrix validation job was
renamed. The audit does not approve, merge, bypass, or alter settings.

## Release tags

A reviewed component release uses:

```text
component/<component-id>/v<semantic-version>
```

The tag's committed manifest ID and version must match the requested component.
The lock records the resolved full commit, and status checks both the tag label
and committed manifest before accepting that provenance. Repository rules should
block tag update and deletion while retaining an administrator recovery path.
Create and verify releases using the fail-closed
[component release procedure](component-releases.md). Portfolio adoption starts
only after GitHub verifies the signed annotated tag and its exact attestation
workflow succeeds.

## Planning

Plan is the default and performs no consumer mutation:

```powershell
./tooling/Update-AzdPortfolio.ps1 `
  -Component notification-contracts `
  -Version 1.0.0 `
  -PortfolioRoot C:\GitHub
```

The requested version must match the registry and an exact reviewed tag. During
a staged rollout, consumers assigned another desired version are intentionally
skipped so pilot, early, and broad rings can advance independently.

## Preparing branches

Prepare requires a separate worktree root and a registered, repository-owned
PowerShell validation entry point:

```powershell
./tooling/Update-AzdPortfolio.ps1 `
  -Component notification-contracts `
  -Version 1.0.0 `
  -PortfolioRoot C:\GitHub `
  -Operation Prepare `
  -WorktreeRoot C:\GitHub\azd-component-update-worktrees
```

The updater creates a deterministic local branch from `origin/<defaultBranch>`,
synchronizes only managed component files and the lock, rejects all unrelated
changes, runs validation within the registry timeout, commits explicit paths,
and removes the temporary worktree after success. A no-op also removes its
temporary branch. A failure preserves the worktree for diagnosis and creates no
remote state.

On Windows, a successful preparation tolerates a short-lived directory handle
only when Git has already unregistered the exact worktree and the residual path
is an empty, non-reparse directory under the dedicated worktree root. Cleanup
uses bounded non-recursive retries; every other residue remains a hard failure.

If a reviewed component version intentionally stops managing a file, add
`-PruneRemovedFiles`. Pruning remains fail-closed: it requires a new component
version and refuses to delete a locally modified managed file.

## Publishing draft pull requests

Publishing is an explicitly confirmed operation layered on the same preparation
path:

```powershell
./tooling/Publish-AzdPortfolioUpdates.ps1 `
  -Component notification-contracts `
  -Version 1.0.0 `
  -PortfolioRoot C:\GitHub `
  -WorktreeRoot C:\GitHub\azd-component-update-worktrees
```

The publisher first verifies that the exact component tag exists on the
`azd-reference` origin and resolves to the same commit as the local tag. For each
consumer, it binds fetch and push operations to the registry's exact repository
URL, rejects Git URL rewrite configuration from every visible scope, refreshes
and verifies the live default branch immediately before isolated preparation,
and refuses to adopt an existing deterministic update branch. It then validates
and atomically creates the prepared branch with an expected-absent Git lease,
which cannot overwrite an existing ref, verifies
that the live remote head is the exact prepared commit, and opens
one draft pull request containing the source revision, prepared commit,
managed-file hashes, validation entry point, and rollback command. `-WhatIf`
stops before branch preparation or remote mutation and returns the intended
consumers and branch names.

The publisher requires an authenticated GitHub CLI session. The create-only
`--force-with-lease=<ref>:` form is used solely to require that the remote ref
does not exist; it cannot overwrite or adopt an existing remote branch. The
publisher cannot perform an unconditional force-push,
approve, merge, or alter repository settings. A partial failure may leave a local
or remote update branch for diagnosis; inspect that exact branch and its draft PR
before retrying or cleaning it up.

If a portfolio-wide publication stops after earlier consumers have already
received draft pull requests, resume one remaining registered consumer at a
time without revisiting those remote branches:

```powershell
./tooling/Publish-AzdPortfolioUpdates.ps1 `
  -Component deployment-validation `
  -Version 1.0.0 `
  -ConsumerId azd-pim `
  -PortfolioRoot C:\GitHub `
  -WorktreeRoot C:\GitHub\azd-component-update-worktrees `
  -WhatIf
```

Review the exact single-consumer plan, then rerun without `-WhatIf`. The
selector must identify exactly one registry entry that approves the requested
component version. Omitting `-ConsumerId` preserves the default all-consumer
publication behavior.

## Scheduled drift surveillance

`.github/workflows/portfolio-drift.yml` runs weekly and on manual dispatch. It
checks out fresh copies of the public registered consumers, runs the read-only
portfolio audit, fails on findings, and retains the JSON report for 30 days. The
workflow does not execute consumer validation scripts, authenticate to Azure or
Microsoft Graph, or mutate a consumer repository.

## Automated draft update pull requests

`.github/workflows/portfolio-updates.yml` reconciles the exact versions approved
in `portfolio/consumers.json`; it never discovers or selects a newer release on
its own. It runs after the weekly audit, on manual dispatch, and whenever the
registry changes on `main`. Existing exact update pull requests are skipped.

The workflow deliberately separates preparation from publication on different
fresh runners. It first
clones public consumers without persisted checkout credentials, audits their
current locks, updates an isolated local branch, and runs the registered
repository validation. Only the resulting Git bundle crosses the job boundary
through a one-day workflow artifact. Consumer validation code and the App secret
never share a runner. Only after validation succeeds does the protected
`portfolio-updates` environment expose the GitHub App private key to a fresh
publication job. The minted
installation token is limited to the one matrix repository and to `contents:
write` plus `pull_requests: write`; the publisher may only create the expected
branch and a draft pull request from the already validated commit.

Configure the reference repository with:

- environment: `portfolio-updates`, with a required reviewer when the repository
  plan supports deployment protection rules;
- repository or environment variable: `AZD_PORTFOLIO_APP_CLIENT_ID`;
- environment secret: `AZD_PORTFOLIO_APP_PRIVATE_KEY`.

Install the App only on registered consumer repositories. It does not need Azure
or Microsoft Graph permissions, Actions administration, repository
administration, issue access, or access to unregistered repositories. The weekly
read-only drift workflow remains independent of this publishing credential.
