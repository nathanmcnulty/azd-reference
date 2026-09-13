# Deployment receipt standard

A deployment receipt records intended and applied configuration plus remaining
operational verification. It is distinct from a validation report, which records
checks actually executed.

The reusable receipt envelope contains:

- schema version and generation time;
- template name and version;
- deployment mode (`plan` or `enforce`);
- relative artifact references;
- applied, unchanged, skipped, warning, and failed operation counts;
- feature-specific details in an explicitly named `details` object; and
- unresolved operational actions such as consent or live delivery proof.

Receipts must not serialize local absolute paths, access tokens, callback URLs,
connection strings, or tenant values that are not necessary to understand the
deployment result.

## Candidate shared writer

`deployment-receipt` is a candidate component with no consumer adoption yet. It
writes `reports/deployment-receipt.json` by default and does not establish
target provenance or prove a deployment succeeded. A producer remains
responsible for choosing truthful counts, artifacts, details, and operational
actions.

After vendoring the component, import its manifest from the consumer's
`scripts/vendor` directory. The component vendors the matching schema beside
the module, so the default writer call uses that schema without a source-repo
path:

```powershell
Import-Module "$PSScriptRoot/vendor/Azd.DeploymentReceipt/Azd.DeploymentReceipt.psd1" -Force
$repositoryRoot = Split-Path -Parent $PSScriptRoot

$receipt = New-AzdDeploymentReceipt `
    -Template 'example-template' `
    -TemplateVersion '0.1.0' `
    -Mode plan `
    -Skipped 2 `
    -Details @{ feature = 'example' }

Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $repositoryRoot
```

Plan receipts always have `summary.applied` set to `0`; use `enforce` only when
the producer is recording actions it actually attempted. The writer bounds
output, rejects unsafe paths and obvious sensitive text, and writes through a
temporary file. Those checks are heuristic: producers must still avoid putting
secrets in arbitrary text, and a same-user process can race filesystem changes
after the final path check.
