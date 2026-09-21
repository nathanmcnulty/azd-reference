# Maester template validation

The four Maester templates are independently deployable consumers of the same
vendored components. Validate them in layers so a passing unit test or GitHub
workflow is not mistaken for proof that the deployed service, tenant boundary,
or teardown behavior works.

## Validation layers

Run these checks from each consumer checkout:

```powershell
$referenceRoot = 'E:\azd-reference' # change this for your local checkout
Invoke-Pester -Path .\tests -CI
az bicep build --file .\infra\main.bicep --stdout | Out-Null
& (Join-Path $referenceRoot 'tooling/Test-AzdComponentDrift.ps1') -TargetPath (Get-Location)
```

Run the reference-repository suite separately:

```powershell
Invoke-Pester -Path (Join-Path $referenceRoot 'tests') -CI
```

The component lock must name an immutable version, source revision, and file
hashes. A clean local checkout, a successful CI workflow, and a successful
Bicep build are separate evidence from a live deployment.

## Live validation matrix

Use a disposable environment and resource group for every row. Record the
environment name, resource group, commit, component-lock versions, tenant,
subscription, and the provider-side run or report identifier.

| Template | Deployment evidence | Teardown evidence |
| --- | --- | --- |
| `azd-maester-functionapp` | HTTP health/result response, report blob, and summary output | Resource group, managed identity, and local azd environment are absent |
| `azd-maester-azureautomation` | Automation runbook reaches `Completed` and uploads a report | Resource group, managed identity, and local azd environment are absent |
| `azd-maester-containerappjob` | Container Apps Job execution reaches `Succeeded` and writes a report | Resource group, managed identity, and local azd environment are absent |
| `azd-maester-azuredevops` | Pipeline is created, runs on the selected branch, and reaches `succeeded` | Resource group, workload application, pipeline, service connection, owned repository, and local azd environment are absent; reused repositories remain |

## Disposable run sequence

Use the normal browser/WAM-backed Azure login or an already valid Azure CLI
session. Do not use device-code authentication. Select the tenant and
subscription explicitly, then use a unique environment name:

```powershell
$environment = 'live-maester-<shape>-<yyyymmdd>'
azd env new $environment --location eastus
azd env set AZURE_SUBSCRIPTION_ID '<subscription-id>'
azd up
```

Supply the template-specific values documented by that consumer before
`azd up`. For Azure DevOps, use the intended organization and project and a
unique repository name when testing repository creation. Keep any pre-existing
repository outside the disposable name so ownership behavior is observable.

After recording the success evidence, run teardown even when validation fails:

```powershell
azd down --environment $environment --force --purge --no-prompt
azd env remove $environment --force
```

Verify the exact resource group with `az group exists`, and query any provider
objects created outside the resource group by their recorded IDs or names. An
`azd down` warning is not a clean teardown: check the exact Azure DevOps
pipeline, service connection, repository, and workload application before
closing the run.

## Evidence and failure handling

Keep a short result record containing:

- the consumer commit and every locked component version;
- tenant, subscription, environment, and resource-group names;
- the HTTP response, job/run ID, pipeline URL, or report location;
- teardown command output and read-only absence checks; and
- any quota or propagation delay that affected the run.

Never record access tokens, client secrets, or full Graph responses. If a
provider resource remains, preserve its exact identifier and remove only the
disposable resource that belongs to the test. Re-run the read-only absence
checks after cleanup rather than treating a local environment removal as proof
that the cloud resource was deleted.
