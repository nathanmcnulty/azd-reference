# azd-reference

Canonical standards, reusable components, and synchronization tooling for the
`nathanmcnulty/azd-*` solution portfolio.

This repository is an authoring source, not a deployment dependency. Every
published `azd` template must remain self-contained after `azd init`, even when
this private repository is unavailable.

## Principles

1. Keep independently supported `azd` solutions in independent repositories.
2. Incubate solution-specific work in `azd-work-in-progress`.
3. Promote only proven, genuinely reusable behavior into this repository.
4. Vendor versioned components into consumers and record their provenance.
5. Preserve project-owned extension points; never silently overwrite drift.
6. Separate read-only validation from explicitly authorized delivery tests.
7. Reuse cached Microsoft/Azure authentication and never use device-code flow.

## Foundation scope

The first foundation release establishes:

- repository, lifecycle, validation, and component-management standards;
- versioned JSON contracts for component manifests, consumer locks, deployment
  receipts, deployment-validation reports, notification envelopes, and delivery
  results;
- a small PowerShell deployment-validation component;
- a delegated Microsoft Graph session coordinator that proves context and token
  usability before reuse;
- safe component synchronization and drift-validation tooling;
- a machine-readable consumer registry, repository baseline, and read-only
  portfolio status audit;
- isolated-worktree preparation and guarded draft-PR publication of reviewed
  component updates;
- scheduled read-only drift surveillance across public consumers;
- a template skeleton that demonstrates the portfolio contract; and
- automated validation for the reference repository itself.

Notification envelope and delivery-result schemas are now a versioned pilot
component. Teams bots, Sentinel analytics/automation, Logic Apps, and polling
Functions remain extraction candidates until pilot adoption proves the correct
boundaries across multiple solutions.

## Layout

```text
components/   Versioned component source and component manifests
docs/         Architecture and extraction decisions
portfolio/    Consumer registry and repository baseline
schemas/      Machine-readable portfolio contracts
skeleton/     Starting point for a new independently supported solution
standards/    Normative portfolio conventions
tests/        Reference tooling and component tests
tooling/      Component synchronization and portfolio validation
```

## Using a component

From a trusted local clone of this repository:

```powershell
./tooling/Sync-AzdComponent.ps1 `
  -Component deployment-validation `
  -Version 0.3.3 `
  -TargetPath C:\GitHub\my-azd-solution `
  -WhatIf
```

Review the plan, rerun without `-WhatIf`, and commit both the vendored files and
the updated `azd-components.lock.json` in the consumer repository.

The lock file is metadata. It is never executable and deployment must not fetch
the source repository.

See [`docs/architecture.md`](docs/architecture.md) and
[`standards/component-lifecycle.md`](standards/component-lifecycle.md) before
adding a component.

## Portfolio status and updates

Audit the registered local checkouts without fetching or executing consumer code:

```powershell
./tooling/Get-AzdPortfolioStatus.ps1 -PortfolioRoot C:\GitHub
```

Plan a tagged component rollout without changing any checkout:

```powershell
./tooling/Update-AzdPortfolio.ps1 `
  -Component deployment-validation `
  -Version 0.3.3 `
  -PortfolioRoot C:\GitHub
```

`Prepare` creates and validates isolated local worktree branches. The separate
publisher verifies origin tag provenance, pushes without force, and opens draft
pull requests containing validation and rollback evidence. Neither tool can
approve or merge a pull request, force-push, or mutate an active checkout. See
[`docs/portfolio-updates.md`](docs/portfolio-updates.md).
