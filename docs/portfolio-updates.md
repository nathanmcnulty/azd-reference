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

## Release tags

A reviewed component release uses:

```text
component/<component-id>/v<semantic-version>
```

The tag's committed manifest ID and version must match the requested component.
The lock records the resolved full commit, and status checks both the tag label
and committed manifest before accepting that provenance. Repository rules should
block tag update and deletion while retaining an administrator recovery path.

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

If a reviewed component version intentionally stops managing a file, add
`-PruneRemovedFiles`. Pruning remains fail-closed: it requires a new component
version and refuses to delete a locally modified managed file.

Publishing is deliberately absent until preparation is proven across the pilot
consumers. A future publisher may push and open one pull request per consumer but
must not force-push, approve, or merge.
