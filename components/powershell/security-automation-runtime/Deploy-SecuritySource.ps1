[CmdletBinding()]
param([string[]]$SolutionRoot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
$raw = & azd env get-values --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the selected azd environment.' }
$values = ($raw -join "`n") | ConvertFrom-Json -AsHashtable -DateKind String
if ($values.SECURITY_COMPUTE_MODE -eq 'none') { Write-Information 'Local mode: use Invoke-Solution with an explicit evidence snapshot.' -InformationAction Continue; return }
if ($values.SECURITY_COMPUTE_MODE -notin @('function','automation','logic-app')) { throw 'Invalid SECURITY_COMPUTE_MODE.' }
if ($values.AZURE_ENV_NAME -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\z') { throw 'An explicit AZURE_ENV_NAME is required for hosted deployment.' }
$environmentName = $values.AZURE_ENV_NAME
$target = @{SubscriptionId=$values.AZURE_SUBSCRIPTION_ID;TenantId=$values.AZURE_TENANT_ID;ResourceGroup=$values.AZURE_RESOURCE_GROUP}
$compute = if ($values.SECURITY_COMPUTE_MODE -eq 'function') {
    @{ResourceType='Microsoft.Web/sites';Name=$values.SECURITY_FUNCTION_APP}
} else { @{ResourceType='Microsoft.Automation/automationAccounts';Name=$values.SECURITY_AUTOMATION_ACCOUNT} }
function Assert-DeploymentTarget {
    $currentRaw = & azd env get-values --environment $environmentName --output json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to verify the captured azd environment.' }
    $current = ($currentRaw -join "`n") | ConvertFrom-Json -AsHashtable -DateKind String
    foreach ($key in @('AZURE_ENV_NAME','AZURE_SUBSCRIPTION_ID','AZURE_TENANT_ID','AZURE_RESOURCE_GROUP','SECURITY_STORAGE_ACCOUNT','SECURITY_COMPUTE_MODE','SECURITY_FUNCTION_APP','SECURITY_AUTOMATION_ACCOUNT')) {
        if ($current[$key] -cne $values[$key]) { throw 'The captured azd deployment target changed; restart with the intended environment.' }
    }
    Assert-SecurityAzureResource @target -ResourceType 'Microsoft.Storage/storageAccounts' -Name $values.SECURITY_STORAGE_ACCOUNT | Out-Null
    Assert-SecurityAzureResource @target @compute | Out-Null
}
# Invalid or stale selectors must fail before package work or persistent azd state changes.
Assert-DeploymentTarget
if (-not $SolutionRoot) { $SolutionRoot=@([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) }
$artifactDirectory = Join-Path $SolutionRoot[0] 'artifacts/packages'
$packagePath = Join-Path $artifactDirectory ("review-"+[guid]::NewGuid().ToString('N')+'.zip')
$package = & (Join-Path $PSScriptRoot 'Build-SecurityBundle.ps1') -SolutionRoot $SolutionRoot -OutputPath $packagePath
$parameters = @{
    ComputeMode=$values.SECURITY_COMPUTE_MODE; SubscriptionId=$values.AZURE_SUBSCRIPTION_ID;TenantId=$values.AZURE_TENANT_ID
    ResourceGroup=$values.AZURE_RESOURCE_GROUP; StorageAccount=$values.SECURITY_STORAGE_ACCOUNT
    PackagePath=$package.path; Confirm=$false
}
if ($values.SECURITY_COMPUTE_MODE -eq 'function') { $parameters.FunctionAppName=$values.SECURITY_FUNCTION_APP }
else { $parameters.AutomationAccountName=$values.SECURITY_AUTOMATION_ACCOUNT }
Assert-DeploymentTarget
$published = & (Join-Path $PSScriptRoot 'Publish-SecurityHost.ps1') @parameters
foreach ($entry in @{SECURITY_BUNDLE_BLOB=$published.bundleBlob;SECURITY_BUNDLE_SHA256=$published.bundleSha256}.GetEnumerator()) {
    Assert-DeploymentTarget
    & azd env set $entry.Key $entry.Value --environment $environmentName
    if ($LASTEXITCODE -ne 0) { throw 'Published source, but failed to record immutable package metadata.' }
}
if ($values.SECURITY_COMPUTE_MODE -in @('automation','logic-app')) {
    # Provision refreshes the job/workflow parameters; provision does not invoke this postdeploy hook.
    Assert-DeploymentTarget
    & azd provision --no-prompt --environment $environmentName
    if ($LASTEXITCODE -ne 0) { throw 'Source published, but scheduled bundle parameters were not refreshed. Keep scheduling disabled.' }
}
Assert-DeploymentTarget
& azd env set SECURITY_DEPLOYED_COMPUTE_MODE $values.SECURITY_COMPUTE_MODE --environment $environmentName
if ($LASTEXITCODE -ne 0) { throw 'Failed to record the deployed compute mode.' }
$published
