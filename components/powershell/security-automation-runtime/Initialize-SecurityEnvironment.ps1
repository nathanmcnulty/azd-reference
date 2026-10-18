[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1') -Force
$defaults = @{ SECURITY_COMPUTE_MODE='none'; SECURITY_SCHEDULE_ENABLED='false'; SECURITY_BUNDLE_BLOB='unconfigured.zip'; SECURITY_BUNDLE_SHA256=''; SECURITY_AUTOMATION_START='2030-01-01T00:00:00Z'; SECURITY_PUBLISHER_PRINCIPAL_ID=''; SECURITY_PUBLISHER_PRINCIPAL_TYPE='User' }
$raw = & azd env get-values --output json
if ($LASTEXITCODE -ne 0) { throw 'Select or initialize an azd environment first.' }
$values = ($raw -join "`n") | ConvertFrom-Json -AsHashtable -DateKind String
$missing = @($defaults.Keys | Where-Object { -not $values.ContainsKey($_) })
foreach ($key in $missing) { $values[$key]=$defaults[$key] }
if ($values.SECURITY_COMPUTE_MODE -notin @('none','function','automation','logic-app')) { throw 'Invalid SECURITY_COMPUTE_MODE.' }
if ($values.ContainsKey('SECURITY_DEPLOYED_COMPUTE_MODE') -and $values.SECURITY_DEPLOYED_COMPUTE_MODE -ne $values.SECURITY_COMPUTE_MODE) { throw 'Use a separate azd environment for an alternative compute mode; retire the previous host explicitly.' }
if ($values.SECURITY_SCHEDULE_ENABLED -notin @('true','false')) { throw 'SECURITY_SCHEDULE_ENABLED must be true or false.' }
if ($values.SECURITY_SCHEDULE_ENABLED -eq 'true' -and $values.SECURITY_COMPUTE_MODE -in @('automation','logic-app') -and ($values.SECURITY_BUNDLE_SHA256 -notmatch '^[a-f0-9]{64}$' -or $values.SECURITY_BUNDLE_BLOB -ne "$($values.SECURITY_BUNDLE_SHA256).zip")) {
    throw 'Publish an approved immutable package and set its blob/hash before enabling scheduling.'
}
$pauseSchedule = $values.SECURITY_SCHEDULE_ENABLED -eq 'false' -and $values.ContainsKey('SECURITY_AUTOMATION_ACCOUNT') -and $values.SECURITY_AUTOMATION_ACCOUNT
if (($values.SECURITY_COMPUTE_MODE -ne 'none' -or $pauseSchedule -or $missing.Count -gt 0) -and $values.AZURE_ENV_NAME -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\z') { throw 'An explicit AZURE_ENV_NAME is required to initialize this environment.' }
$environmentName = $values.AZURE_ENV_NAME
function Assert-EnvironmentTarget {
    if ($environmentName) {
        $currentRaw = & azd env get-values --environment $environmentName --output json
        if ($LASTEXITCODE -ne 0) { throw 'Unable to verify the captured azd environment.' }
        $current = ($currentRaw -join "`n") | ConvertFrom-Json -AsHashtable -DateKind String
        foreach ($key in $defaults.Keys) { if (-not $current.ContainsKey($key)) { $current[$key]=$defaults[$key] } }
        foreach ($key in @($defaults.Keys) + @('AZURE_ENV_NAME','AZURE_SUBSCRIPTION_ID','AZURE_TENANT_ID','AZURE_RESOURCE_GROUP','SECURITY_AUTOMATION_ACCOUNT','SECURITY_DEPLOYED_COMPUTE_MODE')) {
            if ($current[$key] -cne $values[$key]) { throw 'The captured azd initialization target changed; restart with the intended environment.' }
        }
    }
    if ($pauseSchedule) {
        Assert-SecurityAzureResource -SubscriptionId $values.AZURE_SUBSCRIPTION_ID -TenantId $values.AZURE_TENANT_ID -ResourceGroup $values.AZURE_RESOURCE_GROUP -ResourceType 'Microsoft.Automation/automationAccounts' -Name $values.SECURITY_AUTOMATION_ACCOUNT | Out-Null
    } elseif ($values.SECURITY_COMPUTE_MODE -ne 'none') {
        Assert-SecurityAzureTarget -SubscriptionId $values.AZURE_SUBSCRIPTION_ID -TenantId $values.AZURE_TENANT_ID
    }
}
Assert-EnvironmentTarget
foreach ($key in $missing) {
    Assert-EnvironmentTarget
    & azd env set $key $defaults[$key] --environment $environmentName
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize $key." }
}
if ($pauseSchedule) {
    Assert-EnvironmentTarget
    & (Join-Path $PSScriptRoot 'Set-SecuritySchedule.ps1') -SubscriptionId $values.AZURE_SUBSCRIPTION_ID -TenantId $values.AZURE_TENANT_ID -ResourceGroup $values.AZURE_RESOURCE_GROUP -AutomationAccountName $values.SECURITY_AUTOMATION_ACCOUNT -Enabled $false -Confirm:$false -AllowMissing
}
