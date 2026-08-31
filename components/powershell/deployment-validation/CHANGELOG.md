# Deployment validation changelog

## 1.0.0

- Promote the component from pilot to stable after adoption by Emergency
  Access, PIM, and Device Notifications consumer shapes.
- Preserve the exact `Azd.DeploymentValidation.psm1` implementation and
  `deployment-validation.schema.json` contract from 0.3.3; only lifecycle and
  module release metadata change.
- Keep rollback self-contained: consumers can revert their vendoring commit
  without contacting or loading `azd-reference` at deployment time.

## 0.3.3

- Add release metadata without changing the validation API.
- Retain exact managed source and schema behavior from 0.3.2.

## 0.3.2

- Validate prerequisite dependency graphs before executing checks.
- Preserve fail-closed report generation and final-boundary redaction.
