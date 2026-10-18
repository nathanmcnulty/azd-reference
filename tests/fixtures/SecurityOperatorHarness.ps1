# Offline boundary harness: every native/HTTP operation is intercepted and unexpected calls fail.
$global:SecurityOperatorOriginalFunctions=@{}
foreach ($name in @('az','azd','Invoke-RestMethod','Invoke-WebRequest','Get-SecurityOperatorArgument','Add-SecurityOperatorEvent')) {
    $existing=Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
    if ($existing) { $global:SecurityOperatorOriginalFunctions[$name]=$existing.ScriptBlock }
}
function global:Get-SecurityOperatorArgument {
    param([string[]]$Arguments,[string]$Name)
    $index = [Array]::IndexOf($Arguments,$Name)
    if ($index -lt 0 -or $index + 1 -ge $Arguments.Count) { throw "Missing explicit native selector: $Name" }
    $Arguments[$index + 1]
}
function global:Add-SecurityOperatorEvent {
    param([string]$Event,[switch]$Write)
    $global:SecurityOperator.Events.Add($Event)
    if ($Write) { $global:SecurityOperator.Writes.Add($Event) }
    if ($global:SecurityOperator.DisableAfter -eq $Event) { $global:SecurityOperator.State='Disabled' }
}
function global:az {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    $f=$global:SecurityOperator
    $f.Native.Add('az '+($Arguments -join ' '))
    if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
        if ((Get-SecurityOperatorArgument $Arguments '--subscription') -ne $f.Subscription) { throw 'Unapproved subscription selector.' }
        return (@{id=$(if($f.Fault -eq 'wrong-subscription'){$f.DefaultSubscription}else{$f.Subscription});tenantId=$(if($f.Fault -eq 'wrong-tenant'){$f.DefaultTenant}else{$f.Tenant});environmentName='AzureCloud'} | ConvertTo-Json)
    }
    if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'get-access-token') {
        if ((Get-SecurityOperatorArgument $Arguments '--subscription') -ne $f.Subscription -or $Arguments -contains '--tenant') { throw 'Unapproved token context or incompatible CLI selectors.' }
        if ((Get-SecurityOperatorArgument $Arguments '--resource') -notin @('https://management.azure.com/','https://storage.azure.com/')) { throw 'Unexpected token audience.' }
        return (@{accessToken=$f.Token;tenant=$f.Tenant;subscription=$f.Subscription} | ConvertTo-Json)
    }
    if (($Arguments[0..3] -join ' ') -eq 'functionapp deployment source config-zip') {
        if ((Get-SecurityOperatorArgument $Arguments '--subscription') -ne $f.Subscription -or (Get-SecurityOperatorArgument $Arguments '--resource-group') -ne 'test-group' -or (Get-SecurityOperatorArgument $Arguments '--name') -ne 'test-function') { throw 'Unapproved Function target.' }
        if (-not (Test-Path -LiteralPath (Get-SecurityOperatorArgument $Arguments '--src'))) { throw 'Missing source package.' }
        Add-SecurityOperatorEvent Function -Write
        return
    }
    throw 'Unexpected Azure CLI operation; no native executable is allowed.'
}
function global:azd {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    $f=$global:SecurityOperator
    $f.Native.Add('azd '+($Arguments -join ' '))
    if ($Arguments[0] -eq 'env' -and $Arguments[1] -eq 'get-values') {
        if ($Arguments -contains '--environment') {
            if ((Get-SecurityOperatorArgument $Arguments '--environment') -ne 'approved-environment') { throw 'Unapproved azd environment read.' }
        } elseif ($f.SelectedEnvironment -ne 'approved-environment') { throw 'Implicit changed azd environment read.' }
        return ($f.Environment | ConvertTo-Json)
    }
    if ((Get-SecurityOperatorArgument $Arguments '--environment') -ne 'approved-environment') { throw 'Unapproved azd mutation target.' }
    if ($Arguments[0] -eq 'env' -and $Arguments[1] -eq 'set') {
        $f.Environment[$Arguments[2]]=$Arguments[3]
        Add-SecurityOperatorEvent "EnvSet:$($Arguments[2])" -Write
        return
    }
    if ($Arguments[0] -eq 'provision' -and $Arguments -contains '--no-prompt') {
        $f.ProvisionedHash=$f.Environment.SECURITY_BUNDLE_SHA256
        Add-SecurityOperatorEvent Provision -Write
        return
    }
    throw 'Unexpected azd operation; no native executable is allowed.'
}
function global:Invoke-RestMethod {
    [CmdletBinding()]
    param([uri]$Uri,[string]$Method='Get',[hashtable]$Headers,[object]$Body,[string]$ContentType,[int]$TimeoutSec,[int]$MaximumRedirection=-1)
    $f=$global:SecurityOperator
    if ($MaximumRedirection -ne 0 -or $Headers.Authorization -cne "Bearer $($f.Token)") { throw 'Unsafe HTTP authentication or redirects.' }
    $address=$Uri.AbsoluteUri
    $f.Http.Add("$Method $address")
    $subscriptionBase="https://management.azure.com/subscriptions/$($f.Subscription)"
    if ($address -ceq "${subscriptionBase}?api-version=2022-12-01" -and $Method -eq 'Get') {
        $f.SubscriptionReads++
        if ($f.DisableOnSubscriptionRead -eq $f.SubscriptionReads) { $f.State='Disabled' }
        Add-SecurityOperatorEvent "Subscription:$($f.State)"
        if ($f.Fault -eq 'failed-metadata') { throw 'Offline metadata failure.' }
        $metadata=@{id="/subscriptions/$($f.Subscription)";subscriptionId=$f.Subscription;tenantId=$f.Tenant;state=$f.State}
        if ($f.Fault -eq 'missing-state') { $metadata.Remove('state') }
        if ($f.Fault -eq 'malformed-state') { $metadata.state=@{value='Enabled'} }
        return [pscustomobject]$metadata
    }
    $resources=@(
        @{type='Microsoft.Storage/storageAccounts';name='teststorage';version='2023-05-01'}
        @{type='Microsoft.Web/sites';name='test-function';version='2024-04-01'}
        @{type='Microsoft.Automation/automationAccounts';name='test-automation';version='2024-10-23'}
    )
    foreach ($resource in $resources) {
        $id="/subscriptions/$($f.Subscription)/resourceGroups/test-group/providers/$($resource.type)/$($resource.name)"
        if ($address -ceq "https://management.azure.com${id}?api-version=$($resource.version)" -and $Method -eq 'Get') {
            Add-SecurityOperatorEvent "Resource:$($resource.type)"
            if ($f.Fault -eq 'missing-resource') { throw 'Offline resource lookup failed.' }
            if ($f.Fault -eq 'wrong-resource' -or ($f.Fault -eq 'wrong-storage' -and $resource.type -eq 'Microsoft.Storage/storageAccounts') -or ($f.Fault -eq 'wrong-compute' -and $resource.type -ne 'Microsoft.Storage/storageAccounts')) { $id=$id.Replace('test-group','another-group') }
            return [pscustomobject]@{id=$id;type=$resource.type;name=$resource.name;properties=@{primaryEndpoints=@{blob='https://teststorage.blob.core.windows.net/'}}}
        }
    }
    $automation="$subscriptionBase/resourceGroups/test-group/providers/Microsoft.Automation/automationAccounts/test-automation"
    if ($address -ceq "$automation/runbooks/Invoke-SecurityReview/draft/content?api-version=2024-10-23" -and $Method -eq 'Put') {
        if ($ContentType -ne 'text/powershell' -or -not $Body) { throw 'Invalid runbook content.' }
        Add-SecurityOperatorEvent Content -Write
        return
    }
    if ($address -ceq "$automation/runbooks/Invoke-SecurityReview/publish?api-version=2024-10-23" -and $Method -eq 'Post') {
        if ($ContentType -ne 'application/json' -or $Body -cne '{}') { throw 'Invalid publish body.' }
        Add-SecurityOperatorEvent Publish -Write
        return
    }
    if ($address -ceq "$automation/schedules/SecurityReviewSixHourly?api-version=2024-10-23") {
        if ($Method -eq 'Patch') {
            Add-SecurityOperatorEvent Patch -Write
            if ($f.ScheduleMissing) {
                $error=[Exception]::new('Offline missing schedule.')
                $error | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{StatusCode=404})
                throw $error
            }
            $f.ScheduleEnabled=($Body | ConvertFrom-Json).properties.isEnabled
            return
        }
        if ($Method -eq 'Get') {
            if ($f.ScheduleReadMissing) {
                $error=[Exception]::new('Offline missing readback.')
                $error | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{StatusCode=404})
                throw $error
            }
            return [pscustomobject]@{properties=@{isEnabled=$f.ScheduleEnabled}}
        }
    }
    throw 'Unexpected HTTP operation; network access is prohibited.'
}
function global:Invoke-WebRequest {
    [CmdletBinding()]
    param([uri]$Uri,[string]$Method='Get',[hashtable]$Headers,[string]$InFile,[string]$OutFile,[int]$TimeoutSec,[int]$MaximumRedirection=-1)
    $f=$global:SecurityOperator
    if ($MaximumRedirection -ne 0 -or $Headers.Authorization -cne "Bearer $($f.Token)") { throw 'Unsafe Blob authentication or redirects.' }
    $hash=(Get-FileHash -LiteralPath $InFile).Hash.ToLowerInvariant()
    if ($Uri.AbsoluteUri -cne "https://teststorage.blob.core.windows.net/packages/$hash.zip" -or $Method -ne 'Put' -or $Headers['If-None-Match'] -cne '*' -or $Headers['x-ms-blob-type'] -cne 'BlockBlob') { throw 'Unexpected Blob operation.' }
    $f.Http.Add("$Method $($Uri.AbsoluteUri)")
    Add-SecurityOperatorEvent Blob -Write
}
function New-SecurityOperatorFixture {
    param([string]$Component,[string]$Root)
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    foreach ($name in @('Azd.SecurityAutomation.psm1','Publish-SecurityHost.ps1','Set-SecuritySchedule.ps1','Deploy-SecuritySource.ps1','Initialize-SecurityEnvironment.ps1','Invoke-SecurityRunbook.ps1')) { Copy-Item (Join-Path $Component $name) (Join-Path $Root $name) }
    Set-Content -LiteralPath (Join-Path $Root 'package.zip') -Value 'offline package bytes'
    Set-Content -LiteralPath (Join-Path $Root 'Build-SecurityBundle.ps1') -Value @'
param($SolutionRoot,$OutputPath)
Add-SecurityOperatorEvent Package
if ($global:SecurityOperator.ChangeSelectedOnPackage) { $global:SecurityOperator.SelectedEnvironment='unrelated-environment' }
if ($global:SecurityOperator.ChangeTargetOnPackage) { $global:SecurityOperator.Environment.AZURE_TENANT_ID=$global:SecurityOperator.DefaultTenant }
New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
Set-Content -LiteralPath $OutputPath -Value 'offline package bytes'
[pscustomobject]@{path=$OutputPath}
'@
    $global:SecurityOperator=@{
        Subscription='11111111-1111-4111-8111-111111111111';Tenant='22222222-2222-4222-8222-222222222222'
        DefaultSubscription='33333333-3333-4333-8333-333333333333';DefaultTenant='44444444-4444-4444-8444-444444444444'
        Token=[guid]::NewGuid().ToString('N');State='Enabled';Fault='';DisableAfter='';ScheduleEnabled=$true;SubscriptionReads=0;DisableOnSubscriptionRead=0
        ScheduleMissing=$false;ScheduleReadMissing=$false;Root=$Root;SelectedEnvironment='approved-environment'
        ChangeSelectedOnPackage=$false;ChangeTargetOnPackage=$false;ProvisionedHash=$null
        Events=[Collections.Generic.List[string]]::new();Writes=[Collections.Generic.List[string]]::new()
        Native=[Collections.Generic.List[string]]::new();Http=[Collections.Generic.List[string]]::new()
        Environment=@{
            AZURE_ENV_NAME='approved-environment';SECURITY_COMPUTE_MODE='automation';SECURITY_SCHEDULE_ENABLED='false';SECURITY_BUNDLE_BLOB='unconfigured.zip';SECURITY_BUNDLE_SHA256=''
            SECURITY_AUTOMATION_START='2030-01-01T00:00:00Z';SECURITY_PUBLISHER_PRINCIPAL_ID='';SECURITY_PUBLISHER_PRINCIPAL_TYPE='User'
            SECURITY_AUTOMATION_ACCOUNT='test-automation';SECURITY_FUNCTION_APP='test-function';AZURE_RESOURCE_GROUP='test-group'
            AZURE_SUBSCRIPTION_ID='11111111-1111-4111-8111-111111111111';AZURE_TENANT_ID='22222222-2222-4222-8222-222222222222';SECURITY_STORAGE_ACCOUNT='teststorage'
        }
    }
}
function Invoke-SecurityOperatorEntry {
    param([string]$Entry,[switch]$WhatIf)
    $f=$global:SecurityOperator
    $context=@{SubscriptionId=$f.Environment.AZURE_SUBSCRIPTION_ID;TenantId=$f.Environment.AZURE_TENANT_ID;ResourceGroup=$f.Environment.AZURE_RESOURCE_GROUP}
    switch ($Entry) {
        Publisher { & (Join-Path $f.Root 'Publish-SecurityHost.ps1') @context -ComputeMode $f.Environment.SECURITY_COMPUTE_MODE -StorageAccount $f.Environment.SECURITY_STORAGE_ACCOUNT -PackagePath (Join-Path $f.Root 'package.zip') -AutomationAccountName $f.Environment.SECURITY_AUTOMATION_ACCOUNT -FunctionAppName $f.Environment.SECURITY_FUNCTION_APP -Confirm:$false -WhatIf:$WhatIf }
        Schedule { & (Join-Path $f.Root 'Set-SecuritySchedule.ps1') @context -AutomationAccountName $f.Environment.SECURITY_AUTOMATION_ACCOUNT -Enabled $false -Confirm:$false -WhatIf:$WhatIf }
        Deploy { & (Join-Path $f.Root 'Deploy-SecuritySource.ps1') -SolutionRoot $f.Root }
        Initialize { & (Join-Path $f.Root 'Initialize-SecurityEnvironment.ps1') }
        default { throw 'Unknown test entrypoint.' }
    }
}
function Remove-SecurityOperatorHarness {
    foreach ($name in @('az','azd','Invoke-RestMethod','Invoke-WebRequest','Get-SecurityOperatorArgument','Add-SecurityOperatorEvent')) {
        # Remove-Item does not interpret a global: prefix on the Function provider path.
        Remove-Item "Function:$name" -ErrorAction Stop
        if ($global:SecurityOperatorOriginalFunctions.ContainsKey($name)) {
            Set-Item "Function:global:$name" -Value $global:SecurityOperatorOriginalFunctions[$name]
            if ((Get-Command $name -CommandType Function).ScriptBlock.ToString() -cne $global:SecurityOperatorOriginalFunctions[$name].ToString()) { throw "Harness did not restore $name." }
        } elseif (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue) { throw "Harness leaked function $name." }
    }
    Remove-Variable SecurityOperator,SecurityOperatorOriginalFunctions -Scope Global -ErrorAction Stop
}
