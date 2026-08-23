# Deployment validation standard

`scripts/Test-Deployment.ps1` is the portfolio convention for validating a
deployed solution. It is not an Azure Developer CLI built-in command.

## Required interface

```powershell
./scripts/Test-Deployment.ps1
./scripts/Test-Deployment.ps1 -Plan
./scripts/Test-Deployment.ps1 -TestDelivery
./scripts/Test-Deployment.ps1 -OutputPath ./reports/deployment-validation.json
./scripts/Test-Deployment.ps1 -PassThru
```

## Modes

| Mode | Authentication | Side effects | Purpose |
| --- | --- | --- | --- |
| `-Plan` | None preferred | Prohibited | Explain checks, prerequisites, and proposed delivery probes. |
| Default | Reuse existing session | Read-only | Verify deployed state and negative security probes. |
| `-TestDelivery` | Reuse existing session | Explicitly allowed | Send clearly labeled smoke-test events and prove downstream delivery. |

Planning must not call cloud APIs. Default validation must not send messages,
create incidents, invoke callbacks, or mutate configuration.

## Authentication

Validation first tries existing CLI or module context. If a required session is
absent, provide the normal `az login`, `Connect-AzAccount`, or `Connect-MgGraph`
instruction. Never initiate, recommend, or fall back to device-code flow. Avoid
multiple login prompts by sharing the selected cached context across checks.

## Results

Each result conforms to `schemas/deployment-validation.schema.json` and contains:

- stable check ID and category;
- `Pass`, `Fail`, `Warning`, `Skipped`, or `Planned` status;
- concise summary and allowlisted evidence;
- actionable remediation when appropriate;
- duration and side-effect classification.

Any `Fail` result causes a nonzero process exit after the report has been written.
Warnings and skipped checks remain visible but do not fail the process.

Reports use repository-relative paths, are gitignored, and must not contain
tokens, callback URLs, authorization query strings, or unreviewed command output.

## Hook placement

- Use `postprovision` when infrastructure or tenant configuration is sufficient.
- Use `postdeploy` when application code must be running.
- A hook may invoke the default read-only mode automatically.
- Delivery mode is never an automatic lifecycle hook.
- Do not rely only on `postup`; users may run provision and deploy separately.
