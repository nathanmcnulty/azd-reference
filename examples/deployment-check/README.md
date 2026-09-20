# Azure deployment check

A small first deployment for Azure Deployment Studio (`azd-gui`): choose a
subscription, region, and a new environment name, create one empty resource group,
then check that the selected Azure CLI account can read it.

## What it creates

- One resource group named `rg-<environment-name>`, tagged with `azd-env-name`.
- A subscription deployment record created by Azure Resource Manager.

There are no applications, identities, role assignments, secrets, Graph calls,
or optional components. This is an infrastructure and authentication check;
it does not prove that another application template will deploy successfully.
Your subscription policies may add or require other resources. Review the
deployment preview and your subscription's policies and billing before proceeding.

## Before starting

Install Azure Developer CLI 1.23.0 or later, Azure CLI, and PowerShell 7. Use an
account allowed to create subscription deployments and create, read, and delete
resource groups in the selected subscription (for example, a subscription
Contributor). The template does not grant permissions. The GUI's subscription
access check confirms readable context; it does not prove deployment permission.

Use a fresh environment name with at least two characters. Confirm that
`rg-<environment-name>` does not already exist. Keep this resource group dedicated
to the check: cleanup deletes the resource group and anything later placed in it.

## Deploy and validate

In Azure Deployment Studio, select **Azure deployment check**, review its source,
choose an empty local project folder, and follow the prerequisite and connection
steps. Use the same intended tenant/account for Azure Developer CLI and Azure CLI.
Choose your subscription and region, review the deployment, and deploy. There are
no extra configuration questions.

For CLI use, initialize from this repository's `examples/deployment-check`
subdirectory at a reviewed commit, or copy this directory into an empty project
folder. Then run:

```powershell
azd auth login
az login
azd env new <new-environment-name>
azd provision
```

Use the normal broker/browser login flows, or reuse existing cached sessions.
Select the intended subscription and region when prompted. The postprovision hook
runs three read-only checks: complete template files, the selected subscription's
Azure CLI context, and the deployed resource group. It writes
`reports/deployment-validation.json`. A failed validation does not roll back the
resource group; correct the connection and rerun validation or clean up.

The GUI's validation action reruns those checks. From the CLI, run the hook with
the selected environment loaded:

```powershell
azd hooks run postprovision
```

An offline inspection is also available; it makes no cloud calls:

```powershell
./scripts/Test-Deployment.ps1 -Plan
```

## Clean up

Confirm the selected environment and that its resource group contains only this
check's resources. Use the GUI's delete-resources action, or run `azd down` and
review its confirmation. Verify the group was removed:

```powershell
az group exists --subscription <selected-subscription-id> --name rg-<environment-name>
```

The result should be `false`. Local environment files and validation reports may
remain; keep them private. The template includes its validation component and
provenance lock, so deployment never downloads code from the reference repository.
