[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][guid]$TargetTenantId,
    [Parameter(Mandatory)][guid]$CallerTenantId,
    [Parameter(Mandatory)][guid]$DeviceHealthScriptId,
    [Parameter(Mandatory)][guid]$ManagedDeviceId,
    [Parameter(Mandatory)][guid]$ExpectedEntraDeviceId,
    [Parameter(Mandatory)][string]$PackageManifestPath,
    [Parameter(Mandatory)][scriptblock]$GraphRequest,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [switch]$Execute
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($TargetTenantId -eq [guid]::Empty -or $CallerTenantId -ne $TargetTenantId -or
   $DeviceHealthScriptId -eq [guid]::Empty -or $ManagedDeviceId -eq [guid]::Empty -or $ExpectedEntraDeviceId -eq [guid]::Empty){throw 'Nonempty exact caller, target, script and managed-device identities are required.'}
if(Test-Path -LiteralPath $ReceiptPath){throw 'ReceiptPath already exists. Preserve it and select a new path.'}
Import-Module (Join-Path $PSScriptRoot 'Intune.DeviceHealthScripts.psm1') -Force
$package=Import-IntuneDeviceHealthScriptPackage -ManifestPath $PackageManifestPath
$manifest=$package.Manifest
$reviewedNoOpRemediationSha256=@(
    '1fd8fe911e793b6f04c571855596bcf51d63ff407bc2e886286626b49f3c698a', # Defender AV inventory no-op
    '854028b6e489b24480c1db577701a2f97500b0bce1f47de176b176a1dea1f92a'  # Firewall logging evidence no-op
)
if([string]$manifest.remediationScript.sha256 -notin $reviewedNoOpRemediationSha256){
    throw 'On-demand collector execution requires an exact reviewed hash-locked no-op remediation companion.'
}
$root='https://graph.microsoft.com/beta/deviceManagement'
$scriptUri="$root/deviceHealthScripts/$DeviceHealthScriptId"
$script=& $GraphRequest -Method GET -Uri $scriptUri -Body $null
if([string]$script.id -cne $DeviceHealthScriptId.ToString() -or
   [string]$script.displayName -cne [string]$manifest.displayName -or
   [string]$script.description -cne ('{0} [azd-managed-id:{1}]' -f [string]$manifest.description,[string]$manifest.identityKey).Trim() -or
   [string]$script.runAsAccount -cne 'system' -or $script.runAs32Bit -ne $false -or
   [string]$script.publisher -cne [string]$manifest.publisher -or [string]$script.version -cnotmatch '^[1-9]\d*$' -or
   $script.enforceSignatureCheck -ne $false -or $script.isGlobalScript -ne $false -or
   [string]$script.deviceHealthScriptType -cne 'deviceHealthScript' -or
   (@($script.roleScopeTagIds|Sort-Object)|ConvertTo-Json -Compress) -cne (@('0')|ConvertTo-Json -Compress)){throw 'Remote collector identity or execution context differs from the reviewed package.'}
foreach($parameterProperty in @('detectionScriptParameters','remediationScriptParameters')){
    $property=$script.PSObject.Properties[$parameterProperty]
    if($null -eq $property -or @($property.Value).Count -ne 0){throw 'Remote collector parameters are not the reviewed empty parameter set.'}
}
$sha=[Security.Cryptography.SHA256]::Create()
try {
    foreach($name in @('detectionScript','remediationScript')){
        $bytes=[Convert]::FromBase64String([string]$script."$($name)Content")
        $digest=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
        if($digest -cne [string]$manifest.$name.sha256){throw 'Remote collector bytes differ from the reviewed package.'}
    }
}finally{$sha.Dispose()}
$assignments=& $GraphRequest -Method GET -Uri "$scriptUri/assignments" -Body $null
if(@($assignments.value).Count -ne 1 -or $assignments.PSObject.Properties['@odata.nextLink']){throw 'On-demand validation requires one fully captured All devices assignment.'}
$assignment=$assignments.value[0]
$target=$assignment.target
$filterId=$target.PSObject.Properties['deviceAndAppManagementAssignmentFilterId']
$filterType=$target.PSObject.Properties['deviceAndAppManagementAssignmentFilterType']
if(([string]$target.'@odata.type').TrimStart('#') -cne 'microsoft.graph.allDevicesAssignmentTarget' -or
   ($filterId -and [string]$filterId.Value -notin @('','00000000-0000-0000-0000-000000000000')) -or
   ($filterType -and [string]$filterType.Value -notin @('','none'))){throw 'On-demand validation requires the reviewed unfiltered All devices assignment.'}
$runRemediationProperty=$assignment.PSObject.Properties['runRemediationScript']
$scheduleProperty=$assignment.PSObject.Properties['runSchedule']
if($null -eq $runRemediationProperty -or $runRemediationProperty.Value -isnot [bool] -or $runRemediationProperty.Value -ne $false -or
   $null -eq $scheduleProperty -or $null -eq $scheduleProperty.Value){throw 'The scheduled assignment must explicitly disable remediation and contain the reviewed daily schedule.'}
$schedule=$scheduleProperty.Value
$intervalProperty=$schedule.PSObject.Properties['interval']
$useUtcProperty=$schedule.PSObject.Properties['useUtc']
$timeProperty=$schedule.PSObject.Properties['time']
$integerTypes=@('System.Byte','System.SByte','System.Int16','System.UInt16','System.Int32','System.UInt32','System.Int64','System.UInt64')
$actualScheduleTime=[timespan]::Zero
$desiredScheduleTime=[timespan]::Zero
$timeMatches=$null -ne $timeProperty -and $timeProperty.Value -is [string] -and
    [timespan]::TryParse([string]$timeProperty.Value,[Globalization.CultureInfo]::InvariantCulture,[ref]$actualScheduleTime) -and
    [timespan]::TryParse([string]$manifest.assignment.schedule.time,[Globalization.CultureInfo]::InvariantCulture,[ref]$desiredScheduleTime) -and
    $actualScheduleTime -eq $desiredScheduleTime
if([string]$schedule.'@odata.type' -cne '#microsoft.graph.deviceHealthScriptDailySchedule' -or
   $null -eq $intervalProperty -or $null -eq $intervalProperty.Value -or $intervalProperty.Value.GetType().FullName -notin $integerTypes -or $intervalProperty.Value -ne 1 -or
   $null -eq $useUtcProperty -or $useUtcProperty.Value -isnot [bool] -or $useUtcProperty.Value -ne $true -or
   -not $timeMatches){
    throw 'The scheduled assignment does not exactly match the reviewed daily type, integer interval, Boolean UTC flag, and time.'
}
$deviceUri="$root/managedDevices/$ManagedDeviceId"
$device=& $GraphRequest -Method GET -Uri $deviceUri -Body $null
if([string]$device.id -cne $ManagedDeviceId.ToString() -or [string]$device.operatingSystem -cne 'Windows' -or
   [string]$device.managementAgent -notin @('mdm','configurationManagerClientMdm','configurationManagerClientMdmEas')){throw 'The selected device is not the expected Windows MDM endpoint.'}
$entraId=[guid]::Empty
if(-not [guid]::TryParse([string]$device.azureADDeviceId,[ref]$entraId) -or $entraId -eq [guid]::Empty -or $entraId -ne $ExpectedEntraDeviceId){throw 'The selected endpoint does not match the reviewed Entra device identity.'}
$receipt=[ordered]@{
    schemaVersion='1.0';operationId=[guid]::NewGuid().ToString();status='Planned';targetTenantId=$TargetTenantId.ToString();callerTenantId=$CallerTenantId.ToString()
    deviceHealthScriptId=$DeviceHealthScriptId.ToString();serviceVersion=[string]$script.version;managedDeviceId=$ManagedDeviceId.ToString();entraDeviceId=$entraId.ToString()
    packageManifestSha256=$package.ManifestSha256
    onDemandRemediationSha256=[string]$manifest.remediationScript.sha256
    requestedAt=[datetimeoffset]::UtcNow.ToString('o');accepted=$false;endpointExecutionProven=$false
    method='POST';uri="$deviceUri/initiateOnDemandProactiveRemediation";body=@{scriptPolicyId=$DeviceHealthScriptId.ToString()}
    permission='DeviceManagementManagedDevices.PrivilegedOperations.All'
    evidenceBoundary='CallerTenantId is an assertion supplied from the authenticated context. The on-demand action can invoke the remediation companion when detection exits 1, so execution is allowed only for a hard-coded reviewed no-op hash. Accepted only means the service queued a request; fresh device run-state evidence is required.'
}
$full=[IO.Path]::GetFullPath($ReceiptPath)
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
$persist=@{initialized=$false;sha256=$null}
function Save-Receipt {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Depth 20))
    $temporary="$full.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if(-not $persist.initialized){
            [IO.File]::Move($temporary,$full,$false)
            $persist.initialized=$true
        }else{
            if((Get-FileHash -LiteralPath $full).Hash -cne $persist.sha256){throw 'Receipt changed outside this operation; preserve it before retrying.'}
            [IO.File]::Move($temporary,$full,$true)
        }
        $persist.sha256=(Get-FileHash -LiteralPath $full).Hash
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
Save-Receipt
if($Execute -and $PSCmdlet.ShouldProcess($ManagedDeviceId.ToString(),'Request the verified collector with a hash-locked no-op remediation companion on demand')){
    $receipt.status='AttemptedUnknownOutcome';Save-Receipt
    $null=& $GraphRequest -Method POST -Uri $receipt.uri -Body $receipt.body
    $receipt.status='Accepted';$receipt.accepted=$true;Save-Receipt
}
[pscustomobject]$receipt
