[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][guid]$SubscriptionId,[Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$AutomationAccountName,[Parameter(Mandatory)][bool]$Enabled,[switch]$AllowMissing)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
if ($PSCmdlet.ShouldProcess("$AutomationAccountName/SecurityReviewSixHourly", "Set enabled=$Enabled")) {
    $token = Get-SecurityAccessToken -Resource 'https://management.azure.com/' -AuthMode AzureCli
    $uri = "https://management.azure.com/subscriptions/$($SubscriptionId.Guid)/resourceGroups/$([uri]::EscapeDataString($ResourceGroup))/providers/Microsoft.Automation/automationAccounts/$([uri]::EscapeDataString($AutomationAccountName))/schedules/SecurityReviewSixHourly?api-version=2024-10-23"
    try {
        Invoke-RestMethod -Uri $uri -Method Patch -Headers @{Authorization="Bearer $token"} -ContentType 'application/json' -Body (@{properties=@{isEnabled=$Enabled}} | ConvertTo-Json -Compress) -MaximumRedirection 0 | Out-Null
        $state = Invoke-RestMethod -Uri $uri -Method Get -Headers @{Authorization="Bearer $token"} -MaximumRedirection 0
        if ($state.properties.isEnabled -ne $Enabled) { throw 'Schedule state did not converge.' }
    } catch {
        if ($AllowMissing -and $_.Exception.PSObject.Properties.Name -contains 'Response' -and [int]$_.Exception.Response.StatusCode -eq 404) { return }
        throw 'Unable to verify the requested Automation schedule state.'
    }
}
