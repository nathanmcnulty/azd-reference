[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$defaults = @{ SECURITY_COMPUTE_MODE='none'; SECURITY_SCHEDULE_ENABLED='false'; SECURITY_BUNDLE_BLOB='unconfigured.zip'; SECURITY_BUNDLE_SHA256=''; SECURITY_AUTOMATION_START='2030-01-01T00:00:00Z'; SECURITY_PUBLISHER_PRINCIPAL_ID=''; SECURITY_PUBLISHER_PRINCIPAL_TYPE='User' }
$raw = & azd env get-values --output json
if ($LASTEXITCODE -ne 0) { throw 'Select or initialize an azd environment first.' }
$values = ($raw -join "`n") | ConvertFrom-Json -AsHashtable
foreach ($key in $defaults.Keys) {
    if (-not $values.ContainsKey($key)) {
        & azd env set $key $defaults[$key]
        if ($LASTEXITCODE -ne 0) { throw "Could not initialize $key." }
        $values[$key]=$defaults[$key]
    }
}
if ($values.SECURITY_COMPUTE_MODE -notin @('none','function','automation','logic-app')) { throw 'Invalid SECURITY_COMPUTE_MODE.' }
if ($values.ContainsKey('SECURITY_DEPLOYED_COMPUTE_MODE') -and $values.SECURITY_DEPLOYED_COMPUTE_MODE -ne $values.SECURITY_COMPUTE_MODE) { throw 'Use a separate azd environment for an alternative compute mode; retire the previous host explicitly.' }
if ($values.SECURITY_SCHEDULE_ENABLED -notin @('true','false')) { throw 'SECURITY_SCHEDULE_ENABLED must be true or false.' }
if ($values.SECURITY_SCHEDULE_ENABLED -eq 'false' -and $values.ContainsKey('SECURITY_AUTOMATION_ACCOUNT') -and $values.SECURITY_AUTOMATION_ACCOUNT) {
    & (Join-Path $PSScriptRoot 'Set-SecuritySchedule.ps1') -SubscriptionId $values.AZURE_SUBSCRIPTION_ID -ResourceGroup $values.AZURE_RESOURCE_GROUP -AutomationAccountName $values.SECURITY_AUTOMATION_ACCOUNT -Enabled $false -Confirm:$false -AllowMissing
}
if ($values.SECURITY_SCHEDULE_ENABLED -eq 'true' -and $values.SECURITY_COMPUTE_MODE -in @('automation','logic-app') -and ($values.SECURITY_BUNDLE_SHA256 -notmatch '^[a-f0-9]{64}$' -or $values.SECURITY_BUNDLE_BLOB -ne "$($values.SECURITY_BUNDLE_SHA256).zip")) {
    throw 'Publish an approved immutable package and set its blob/hash before enabling scheduling.'
}
