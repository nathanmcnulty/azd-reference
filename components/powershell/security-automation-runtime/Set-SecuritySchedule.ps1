[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$SubscriptionId,[Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$AutomationAccountName,[Parameter(Mandatory)][bool]$Enabled,[switch]$AllowMissing)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
if ($PSCmdlet.ShouldProcess("$AutomationAccountName/SecurityReviewSixHourly", "Set enabled=$Enabled")) {
    $target = @{SubscriptionId=$SubscriptionId;TenantId=$TenantId;ResourceGroup=$ResourceGroup;ResourceType='Microsoft.Automation/automationAccounts';Name=$AutomationAccountName}
    Assert-SecurityAzureResource @target | Out-Null
    $token = Get-SecurityAccessToken -Resource 'https://management.azure.com/' -AuthMode AzureCli -TenantId $TenantId -SubscriptionId $SubscriptionId
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/providers/Microsoft.Automation/automationAccounts/$([uri]::EscapeDataString($AutomationAccountName))/schedules/SecurityReviewSixHourly?api-version=2024-10-23"
    $body = @{properties=@{isEnabled=$Enabled}} | ConvertTo-Json -Compress
    # AllowMissing covers only a missing schedule, never an unverified parent or subscription.
    Assert-SecurityAzureResource @target | Out-Null
    try {
        Invoke-RestMethod -Uri $uri -Method Patch -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body $body -MaximumRedirection 0 | Out-Null
    } catch {
        if ($AllowMissing -and $_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return }
        throw 'Unable to set the requested Automation schedule state.'
    }
    try {
        $state = Invoke-RestMethod -Uri $uri -Method Get -Headers @{Authorization="Bearer $token"} -MaximumRedirection 0
        if ($state.properties.isEnabled -ne $Enabled) { throw 'Schedule state did not converge.' }
    } catch {
        throw 'Unable to verify the requested Automation schedule state.'
    }
}
