[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][guid]$SubscriptionId,[Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$AutomationAccountName,[Parameter(Mandatory)][bool]$Enabled)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
if ($PSCmdlet.ShouldProcess("$AutomationAccountName/SecurityReviewSixHourly", "Set enabled=$Enabled")) {
    $token = Get-SecurityAccessToken -Resource 'https://management.azure.com/' -AuthMode AzureCli
    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId.Guid)/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/providers/Microsoft.Automation/automationAccounts/$([uri]::EscapeDataString($AutomationAccountName))/schedules/SecurityReviewSixHourly?api-version=2024-10-23"
    Invoke-RestMethod -Uri $uri -Method Patch -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body (@{properties=@{isEnabled=$Enabled}} | ConvertTo-Json -Compress) -MaximumRedirection 0 | Out-Null
}
