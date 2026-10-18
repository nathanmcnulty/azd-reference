[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateSet('function','automation','logic-app')][string]$ComputeMode,
    [Parameter(Mandatory)][string]$SubscriptionId,[Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$StorageAccount,[Parameter(Mandatory)][string]$PackagePath,
    [string]$FunctionAppName,[string]$AutomationAccountName
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
$target = @{SubscriptionId=$SubscriptionId;TenantId=$TenantId;ResourceGroup=$ResourceGroup}
if ($ComputeMode -eq 'function') {
    if (-not $FunctionAppName) { throw 'FunctionAppName is required.' }
    $compute = @{ResourceType='Microsoft.Web/sites';Name=$FunctionAppName}
} else {
    if (-not $AutomationAccountName) { throw 'AutomationAccountName is required.' }
    $compute = @{ResourceType='Microsoft.Automation/automationAccounts';Name=$AutomationAccountName}
}
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
$blob = "$hash.zip"
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroup",'Upload immutable review bundle and publish host source')) { return }
# Validate every destination before the first write. Each later boundary rechecks current state.
Assert-SecurityAzureResource @target -ResourceType 'Microsoft.Storage/storageAccounts' -Name $StorageAccount | Out-Null
Assert-SecurityAzureResource @target @compute | Out-Null
Invoke-SecurityBlobTransfer -Account $StorageAccount -Container packages -Blob $blob -Path $package -Direction Upload -AuthMode AzureCli @target
if ($ComputeMode -eq 'function') {
    Assert-SecurityAzureResource @target @compute | Out-Null
    & az functionapp deployment source config-zip --subscription $SubscriptionId --resource-group $ResourceGroup --name $FunctionAppName --src $package --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Function source deployment failed.' }
} else {
    $token = Get-SecurityAccessToken -Resource 'https://management.azure.com/' -AuthMode AzureCli -TenantId $TenantId -SubscriptionId $SubscriptionId
    $base = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/providers/Microsoft.Automation/automationAccounts/$([uri]::EscapeDataString($AutomationAccountName))/runbooks/Invoke-SecurityReview"
    $headers = @{Authorization="Bearer $token"}
    $content = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-SecurityRunbook.ps1') -Raw
    Assert-SecurityAzureResource @target @compute | Out-Null
    Invoke-RestMethod -Uri "$base/draft/content?api-version=2024-10-23" -Method Put -Headers $headers -ContentType 'text/powershell' -Body $content -MaximumRedirection 0 | Out-Null
    Assert-SecurityAzureResource @target @compute | Out-Null
    Invoke-RestMethod -Uri "$base/publish?api-version=2024-10-23" -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -MaximumRedirection 0 | Out-Null
}
[pscustomobject]@{bundleBlob=$blob;bundleSha256=$hash;sourcePublished=$true;scheduleEnabled=$false;note='Redeploy host parameters with this bundle hash before manually enabling its schedule.'}
