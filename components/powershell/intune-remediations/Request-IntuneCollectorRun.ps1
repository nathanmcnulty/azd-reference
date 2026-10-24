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
    [ValidateSet('AllDevices','Group')][string]$AssignmentScope='AllDevices',
    [guid]$AssignmentGroupId,
    [guid[]]$ExpectedGroupMemberEntraDeviceId,
    [switch]$Execute
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($TargetTenantId -eq [guid]::Empty -or $CallerTenantId -ne $TargetTenantId -or
   $DeviceHealthScriptId -eq [guid]::Empty -or $ManagedDeviceId -eq [guid]::Empty -or $ExpectedEntraDeviceId -eq [guid]::Empty){throw 'Nonempty exact caller, target, script and managed-device identities are required.'}
if(Test-Path -LiteralPath $ReceiptPath){throw 'ReceiptPath already exists. Preserve it and select a new path.'}
$hasAssignmentGroupId=$PSBoundParameters.ContainsKey('AssignmentGroupId')
$hasExpectedGroupRoster=$PSBoundParameters.ContainsKey('ExpectedGroupMemberEntraDeviceId')
$groupId=$null
$expectedGroupRoster=@()
if($AssignmentScope -eq 'AllDevices'){
    if($hasAssignmentGroupId -or $hasExpectedGroupRoster){throw 'AssignmentGroupId and ExpectedGroupMemberEntraDeviceId must be omitted when AssignmentScope is AllDevices.'}
}else{
    if(-not $hasAssignmentGroupId -or $AssignmentGroupId -eq [guid]::Empty){throw 'A nonempty AssignmentGroupId is required when AssignmentScope is Group.'}
    if(-not $hasExpectedGroupRoster -or @($ExpectedGroupMemberEntraDeviceId).Count -lt 1 -or @($ExpectedGroupMemberEntraDeviceId).Count -gt 100){throw 'Group scope requires 1 to 100 explicit expected Entra device IDs.'}
    $groupId=$AssignmentGroupId.ToString()
    $expectedGroupRoster=@($ExpectedGroupMemberEntraDeviceId|ForEach-Object {
        if($_ -eq [guid]::Empty){throw 'Expected group member Entra device IDs must be nonempty GUIDs.'}
        $_.ToString()
    }|Sort-Object)
    if(@($expectedGroupRoster|Select-Object -Unique).Count -ne $expectedGroupRoster.Count){throw 'Expected group member Entra device IDs must be unique.'}
    if($ExpectedEntraDeviceId.ToString() -notin $expectedGroupRoster){throw 'The selected Entra device must be present in the exact expected group roster.'}
}
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
if(@($assignments.value).Count -ne 1 -or $assignments.PSObject.Properties['@odata.nextLink']){throw 'On-demand validation requires one fully captured assignment.'}
$assignment=$assignments.value[0]
$target=$assignment.target
$filterId=$target.PSObject.Properties['deviceAndAppManagementAssignmentFilterId']
$filterType=$target.PSObject.Properties['deviceAndAppManagementAssignmentFilterType']
$expectedTargetType=if($AssignmentScope -eq 'Group'){'microsoft.graph.groupAssignmentTarget'}else{'microsoft.graph.allDevicesAssignmentTarget'}
$targetGroupId=[guid]::Empty
$targetMatches=([string]$target.'@odata.type').TrimStart('#') -ceq $expectedTargetType
if($AssignmentScope -eq 'Group'){
    $targetMatches=$targetMatches -and [guid]::TryParse([string]$target.groupId,[ref]$targetGroupId) -and $targetGroupId -eq $AssignmentGroupId
}
if(-not $targetMatches -or
   ($filterId -and [string]$filterId.Value -notin @('','00000000-0000-0000-0000-000000000000')) -or
   ($filterType -and [string]$filterType.Value -notin @('','none'))){throw "On-demand validation requires the reviewed unfiltered $AssignmentScope assignment."}
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
if(([string]$schedule.'@odata.type').Trim().TrimStart('#').ToLowerInvariant() -cne 'microsoft.graph.devicehealthscriptdailyschedule' -or
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
$observedGroupRoster=@()
if($AssignmentScope -eq 'Group'){
    $groupUri="https://graph.microsoft.com/v1.0/groups/${groupId}?`$select=id,securityEnabled,groupTypes,membershipRule,membershipRuleProcessingState"
    $group=& $GraphRequest -Method GET -Uri $groupUri -Body $null
    $observedGroupId=[guid]::Empty
    $securityEnabled=$group.PSObject.Properties['securityEnabled']
    $groupTypes=$group.PSObject.Properties['groupTypes']
    $membershipRule=$group.PSObject.Properties['membershipRule']
    $membershipRuleProcessingState=$group.PSObject.Properties['membershipRuleProcessingState']
    if(-not [guid]::TryParse([string]$group.id,[ref]$observedGroupId) -or $observedGroupId -ne $AssignmentGroupId){throw 'The reviewed group metadata identity did not match AssignmentGroupId.'}
    if($null -eq $securityEnabled -or $securityEnabled.Value -isnot [bool] -or $securityEnabled.Value -ne $true){throw 'Group scope requires an exact securityEnabled Boolean true group.'}
    if($null -eq $groupTypes -or $null -eq $groupTypes.Value -or $null -eq $membershipRule -or $null -eq $membershipRuleProcessingState){throw 'Group scope requires complete static membership metadata.'}
    if(@($groupTypes.Value|ForEach-Object {[string]$_}) -icontains 'DynamicMembership' -or
       -not [string]::IsNullOrWhiteSpace([string]$membershipRule.Value) -or
       -not [string]::IsNullOrWhiteSpace([string]$membershipRuleProcessingState.Value)){
        throw 'Group scope requires a static group without a dynamic membership rule.'
    }
    # The v1.0 relationship can omit service principals. The uncast beta relationship exposes all direct member types so any non-device fails closed.
    $membersUri="https://graph.microsoft.com/beta/groups/${groupId}/members?`$select=id,deviceId"
    $membersResponse=& $GraphRequest -Method GET -Uri $membersUri -Body $null
    if($membersResponse.PSObject.Properties['@odata.nextLink']){throw 'Group member paging is not accepted; use a reviewed static group with at most 100 directly returned members.'}
    $membersValue=$membersResponse.PSObject.Properties['value']
    if($null -eq $membersValue){throw 'Group members response did not contain a complete value collection.'}
    $members=@($membersValue.Value)
    if($members.Count -gt 100){throw 'Group scope supports at most 100 direct device members.'}
    $seenMemberObjectIds=@{}
    $seenMemberDeviceIds=@{}
    foreach($member in $members){
        if($null -eq $member){throw 'Group members cannot contain null directory objects.'}
        if(([string]$member.'@odata.type').TrimStart('#') -cne 'microsoft.graph.device'){throw 'Group scope supports only direct device members.'}
        $memberObjectId=[guid]::Empty
        $memberDeviceId=[guid]::Empty
        if(-not [guid]::TryParse([string]$member.id,[ref]$memberObjectId) -or $memberObjectId -eq [guid]::Empty){throw 'Each group member must have a nonempty device directory object ID.'}
        if(-not [guid]::TryParse([string]$member.deviceId,[ref]$memberDeviceId) -or $memberDeviceId -eq [guid]::Empty){throw 'Each group device member must have a nonempty Entra device ID.'}
        $memberObjectKey=$memberObjectId.ToString()
        $memberDeviceKey=$memberDeviceId.ToString()
        if($seenMemberObjectIds.ContainsKey($memberObjectKey) -or $seenMemberDeviceIds.ContainsKey($memberDeviceKey)){throw 'Group members contain a duplicate directory object or Entra device identity.'}
        $seenMemberObjectIds[$memberObjectKey]=$true
        $seenMemberDeviceIds[$memberDeviceKey]=$true
    }
    $observedGroupRoster=@($seenMemberDeviceIds.Keys|Sort-Object)
    if(($observedGroupRoster|ConvertTo-Json -Compress) -cne ($expectedGroupRoster|ConvertTo-Json -Compress)){throw 'Observed direct group device members did not exactly match the reviewed Entra device roster.'}
    if($entraId.ToString() -notin $observedGroupRoster){throw 'The selected endpoint is not a direct member of the reviewed group.'}
}
$receipt=[ordered]@{
    schemaVersion='1.0';operationId=[guid]::NewGuid().ToString();status='Planned';targetTenantId=$TargetTenantId.ToString();callerTenantId=$CallerTenantId.ToString()
    deviceHealthScriptId=$DeviceHealthScriptId.ToString();serviceVersion=[string]$script.version;managedDeviceId=$ManagedDeviceId.ToString();entraDeviceId=$entraId.ToString()
    packageManifestSha256=$package.ManifestSha256
    onDemandRemediationSha256=[string]$manifest.remediationScript.sha256
    assignmentScope=$AssignmentScope;assignmentGroupId=$groupId
    expectedGroupMemberEntraDeviceIds=@($expectedGroupRoster);observedGroupMemberEntraDeviceIds=@($observedGroupRoster)
    groupReadPermissions=if($AssignmentScope -eq 'Group'){@('GroupMember.Read.All','Device.Read.All')}else{@()}
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
