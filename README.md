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
  receipts, and deployment-validation reports;
- a small PowerShell deployment-validation component;
- a delegated Microsoft Graph session coordinator that proves context and token
  usability before reuse;
- safe component synchronization and drift-validation tooling;
- a template skeleton that demonstrates the portfolio contract; and
- automated validation for the reference repository itself.

Teams bots, Sentinel analytics/automation, Logic Apps, and polling Functions are
tracked as extraction candidates. They will be promoted only after pilot adoption
proves the correct boundaries across multiple solutions.

## Layout

```text
components/   Versioned component source and component manifests
docs/         Architecture and extraction decisions
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
Canonical standards, reusable components, and synchronization tooling for Nathan McNulty azd solutions.
