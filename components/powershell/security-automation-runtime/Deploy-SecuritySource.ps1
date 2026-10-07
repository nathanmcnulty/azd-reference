[CmdletBinding()]
param([string[]]$SolutionRoot)
$ErrorActionPreference='Stop'
$raw = & azd env get-values --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the selected azd environment.' }
$values = ($raw -join "`n") | ConvertFrom-Json -AsHashtable
if ($values.SECURITY_COMPUTE_MODE -eq 'none') { Write-Information 'Local mode: use Invoke-Solution with an explicit evidence snapshot.' -InformationAction Continue; return }
if (-not $SolutionRoot) { $SolutionRoot=@([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) }
$artifactDirectory = Join-Path $SolutionRoot[0] 'artifacts/packages'
$packagePath = Join-Path $artifactDirectory ("review-"+[guid]::NewGuid().ToString('N')+'.zip')
$package = & (Join-Path $PSScriptRoot 'Build-SecurityBundle.ps1') -SolutionRoot $SolutionRoot -OutputPath $packagePath
$parameters = @{
    ComputeMode=$values.SECURITY_COMPUTE_MODE; SubscriptionId=$values.AZURE_SUBSCRIPTION_ID
    ResourceGroup=$values.AZURE_RESOURCE_GROUP; StorageAccount=$values.SECURITY_STORAGE_ACCOUNT
    PackagePath=$package.path; Confirm=$false
}
if ($values.SECURITY_COMPUTE_MODE -eq 'function') { $parameters.FunctionAppName=$values.SECURITY_FUNCTION_APP }
else { $parameters.AutomationAccountName=$values.SECURITY_AUTOMATION_ACCOUNT }
$published = & (Join-Path $PSScriptRoot 'Publish-SecurityHost.ps1') @parameters
foreach ($entry in @{SECURITY_BUNDLE_BLOB=$published.bundleBlob;SECURITY_BUNDLE_SHA256=$published.bundleSha256}.GetEnumerator()) {
    & azd env set $entry.Key $entry.Value
    if ($LASTEXITCODE -ne 0) { throw 'Published source, but failed to record immutable package metadata.' }
}
if ($values.SECURITY_COMPUTE_MODE -in @('automation','logic-app')) {
    # Provision refreshes the job/workflow parameters; provision does not invoke this postdeploy hook.
    & azd provision --no-prompt
    if ($LASTEXITCODE -ne 0) { throw 'Source published, but scheduled bundle parameters were not refreshed. Keep scheduling disabled.' }
}
$published
& azd env set SECURITY_DEPLOYED_COMPUTE_MODE $values.SECURITY_COMPUTE_MODE
if ($LASTEXITCODE -ne 0) { throw 'Failed to record the deployed compute mode.' }
