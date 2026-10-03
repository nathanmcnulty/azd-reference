[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateSet('function','automation','logic-app')][string]$ComputeMode,
    [Parameter(Mandatory)][guid]$SubscriptionId,[Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$StorageAccount,[Parameter(Mandatory)][string]$PackagePath,
    [string]$FunctionAppName,[string]$AutomationAccountName
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
$blob = "$hash.zip"
if (-not $PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroup",'Upload immutable review bundle and publish host source')) { return }
$account = (& az account show --output json --only-show-errors 2>$null) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $account.id -ne $SubscriptionId.Guid) { throw 'Select the requested subscription in the cached Azure CLI session first.' }
Invoke-SecurityBlobTransfer -Account $StorageAccount -Container packages -Blob $blob -Path $package -Direction Upload -AuthMode AzureCli
if ($ComputeMode -eq 'function') {
    if (-not $FunctionAppName) { throw 'FunctionAppName is required.' }
    & az functionapp deployment source config-zip --subscription $SubscriptionId.Guid --resource-group $ResourceGroup --name $FunctionAppName --src $package --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Function source deployment failed.' }
} else {
    if (-not $AutomationAccountName) { throw 'AutomationAccountName is required.' }
    $token = Get-SecurityAccessToken -Resource 'https://management.azure.com/' -AuthMode AzureCli -TenantId $account.tenantId
    $base = "https://management.azure.com/subscriptions/$($SubscriptionId.Guid)/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/providers/Microsoft.Automation/automationAccounts/$([uri]::EscapeDataString($AutomationAccountName))/runbooks/Invoke-SecurityReview"
    $headers = @{Authorization="Bearer $token"}
    Invoke-RestMethod -Uri "$base/draft/content?api-version=2024-10-23" -Method Put -Headers $headers -ContentType 'text/powershell' -Body (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-SecurityRunbook.ps1') -Raw) -MaximumRedirection 0 | Out-Null
    Invoke-RestMethod -Uri "$base/publish?api-version=2024-10-23" -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -MaximumRedirection 0 | Out-Null
}
[pscustomobject]@{bundleBlob=$blob;bundleSha256=$hash;sourcePublished=$true;scheduleEnabled=$false;note='Redeploy host parameters with this bundle hash before manually enabling its schedule.'}
