Set-StrictMode -Version Latest

function ConvertTo-RequiredGuid {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Name)
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw "$Name must be a non-empty GUID."
    }
    $parsed.ToString()
}

function ConvertTo-BoundedOpaqueIdentifier {
    param([Parameter(Mandatory)][AllowEmptyString()][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($Value -isnot [string]) { throw "$Name must be a string." }
    $text = [string]$Value
    if ($text -cnotmatch '^[A-Za-z0-9_-]{1,512}$') {
        throw "$Name must use 1 to 512 ASCII letters, digits, underscores, or hyphens."
    }
    $text
}

function Get-Sha256Bytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Assert-NoReparsePointInPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $relative = $full.Substring($root.Length)
    foreach ($component in @($relative -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $component
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Package path component '$current' cannot be a reparse point."
            }
        }
    }
}

function Resolve-PackageFile {
    param([Parameter(Mandatory)][string]$PackageRoot, [Parameter(Mandatory)][string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Package path '$RelativePath' must be a safe relative path."
    }
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $candidate.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Package path '$RelativePath' escapes the package directory."
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw "Package file '$RelativePath' was not found." }
    Assert-NoReparsePointInPath -Path $candidate
    $candidate
}

function Import-IntuneDeviceHealthScriptPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [string]$SchemaPath = (Join-Path $PSScriptRoot 'remediation-package.schema.json')
    )

    $manifestFull = [IO.Path]::GetFullPath($ManifestPath)
    Assert-NoReparsePointInPath -Path $manifestFull
    $resolvedManifest = (Resolve-Path -LiteralPath $manifestFull -ErrorAction Stop).Path
    $schemaFull = [IO.Path]::GetFullPath($SchemaPath)
    Assert-NoReparsePointInPath -Path $schemaFull
    if (-not (Test-Path -LiteralPath $schemaFull -PathType Leaf)) { throw "Package schema '$schemaFull' was not found." }
    $manifestBytes = [IO.File]::ReadAllBytes($resolvedManifest)
    $manifestText = [Text.UTF8Encoding]::new($false, $true).GetString($manifestBytes)
    if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) { throw 'Test-Json is required to validate a device health script package.' }
    if (-not ($manifestText | Test-Json -SchemaFile $schemaFull -ErrorAction Stop)) { throw 'Package manifest failed remediation-package.schema.json validation.' }
    $manifest = $manifestText | ConvertFrom-Json -Depth 30
    if ($manifest.schemaVersion -ne '1.0' -or $manifest.packageType -ne 'intuneDeviceHealthScript') {
        throw 'Package manifest must use schemaVersion 1.0 and packageType intuneDeviceHealthScript.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.identityKey) -or $manifest.identityKey -notmatch '^[a-z0-9][a-z0-9._/-]{2,127}$') {
        throw 'Package identityKey is invalid.'
    }
    foreach ($name in @('displayName','description','publisher','version')) {
        if ([string]::IsNullOrWhiteSpace([string]$manifest.$name)) { throw "Package $name is required." }
    }
    if ($manifest.execution.runAsAccount -ne 'system' -or $manifest.execution.runAs32Bit -ne $false -or $manifest.execution.enforceSignatureCheck -ne $false) {
        throw 'Package execution must require system, 64-bit PowerShell, and signature-not-required.'
    }
    if ($manifest.assignment.schedule.type -ne 'daily' -or [int]$manifest.assignment.schedule.interval -ne 1 -or $manifest.assignment.schedule.useUtc -ne $true) {
        throw 'Package assignment must use the reviewed daily 24-hour UTC schedule.'
    }
    if ([string]$manifest.assignment.schedule.time -notmatch '^([01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,7})?$') {
        throw 'Package assignment schedule time is invalid.'
    }

    $root = Split-Path -Parent $resolvedManifest
    Assert-NoReparsePointInPath -Path $root
    $detectionPath = Resolve-PackageFile -PackageRoot $root -RelativePath ([string]$manifest.detectionScript.path)
    $remediationPath = Resolve-PackageFile -PackageRoot $root -RelativePath ([string]$manifest.remediationScript.path)
    $detectionBytes = [IO.File]::ReadAllBytes($detectionPath)
    $remediationBytes = [IO.File]::ReadAllBytes($remediationPath)
    foreach ($pair in @(
        @{ Name = 'detectionScript'; Path = $detectionPath; Bytes = $detectionBytes; Expected = [string]$manifest.detectionScript.sha256 },
        @{ Name = 'remediationScript'; Path = $remediationPath; Bytes = $remediationBytes; Expected = [string]$manifest.remediationScript.sha256 }
    )) {
        if ($pair.Expected -notmatch '^[a-f0-9]{64}$') { throw "$($pair.Name) sha256 must be lowercase SHA-256." }
        $actual = Get-Sha256Bytes -Bytes $pair.Bytes
        if ($actual -cne $pair.Expected) { throw "$($pair.Name) hash mismatch: expected $($pair.Expected), found $actual." }
        $lengthProperty = $manifest.$($pair.Name).PSObject.Properties['byteLength']
        if ($null -eq $lengthProperty -or [long]$lengthProperty.Value -ne $pair.Bytes.LongLength) {
            throw "$($pair.Name) byteLength does not match the package file."
        }
    }
    [pscustomobject]@{
        Manifest = $manifest
        ManifestPath = $resolvedManifest
        PackageRoot = $root
        DetectionPath = $detectionPath
        RemediationPath = $remediationPath
        ManifestSha256 = Get-Sha256Bytes -Bytes $manifestBytes
        DetectionBytes = $detectionBytes
        RemediationBytes = $remediationBytes
    }
}

function Invoke-GraphRequestChecked {
    param(
        [Parameter(Mandatory)][scriptblock]$GraphRequest,
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [object]$Body
    )
    & $GraphRequest -Method $Method -Uri $Uri -Body $Body
}

function Get-GraphCollection {
    param(
        [Parameter(Mandatory)][scriptblock]$GraphRequest,
        [Parameter(Mandatory)][string]$InitialUri,
        [Parameter(Mandatory)][string]$AllowedPathPrefix,
        [ValidateRange(1,100)][int]$MaximumPages = 20
    )
    $items = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    $initial = [uri]$InitialUri
    if ($initial.Scheme -ne 'https' -or $initial.Host -ne 'graph.microsoft.com' -or -not $initial.IsDefaultPort -or $initial.UserInfo -or $initial.Fragment -or $initial.AbsolutePath -ne $AllowedPathPrefix) {
        throw "Unsafe initial Graph collection URI '$InitialUri'."
    }
    $expectedPath = $initial.AbsolutePath
    $next = $initial.AbsoluteUri
    $page = 0
    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $page++
        if ($page -gt $MaximumPages) { throw "Graph paging exceeded $MaximumPages pages." }
        $uri = [uri]$next
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'graph.microsoft.com' -or -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.Fragment -or $uri.AbsolutePath -cne $expectedPath) {
            throw "Unsafe Graph paging URI '$next'."
        }
        if ($seen.ContainsKey($uri.AbsoluteUri)) { throw "Cyclic Graph paging URI '$next'." }
        $seen[$uri.AbsoluteUri] = $true
        $response = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri $uri.AbsoluteUri
        foreach ($item in @($response.value)) { if ($null -ne $item) { $items.Add($item) } }
        $nextProperty = $response.PSObject.Properties['@odata.nextLink']
        $next = if ($null -eq $nextProperty) { $null } else { [string]$nextProperty.Value }
    }
    $items.ToArray()
}

function ConvertTo-StrictUtcTimestamp {
    param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Name)
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { throw "$Name must include an explicit UTC offset." }
        return ([datetimeoffset]$Value).ToUniversalTime()
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Trim() -notmatch '(?i)(Z|[+-]\d{2}:\d{2})$') { throw "$Name must include an explicit UTC offset." }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($text.Trim(), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) { throw "$Name must be a valid timestamp." }
    $parsed.ToUniversalTime()
}

function Get-CanonicalServiceVersion {
    param([Parameter(Mandatory)][object]$Value)
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text -cnotmatch '^[1-9][0-9]*$') {
        throw 'Remote device health script version must be a canonical positive integer returned by Intune.'
    }
    $text
}

function New-DesiredDeviceHealthScriptBody {
    param([Parameter(Mandatory)][object]$Package)
    $manifest = $Package.Manifest
    [ordered]@{
        '@odata.type' = '#microsoft.graph.deviceHealthScript'
        displayName = [string]$manifest.displayName
        description = ('{0} [azd-managed-id:{1}]' -f [string]$manifest.description, [string]$manifest.identityKey).Trim()
        publisher = [string]$manifest.publisher
        detectionScriptContent = [Convert]::ToBase64String($Package.DetectionBytes)
        remediationScriptContent = [Convert]::ToBase64String($Package.RemediationBytes)
        runAsAccount = 'system'
        enforceSignatureCheck = $false
        runAs32Bit = $false
        roleScopeTagIds = @('0')
        isGlobalScript = $false
        deviceHealthScriptType = 'deviceHealthScript'
        detectionScriptParameters = @()
        remediationScriptParameters = @()
    }
}

function New-DesiredDeviceHealthScriptUpdateBody {
    param([Parameter(Mandatory)][object]$DesiredScript)
    $update = [ordered]@{}
    foreach ($name in @('@odata.type','displayName','description','publisher','detectionScriptContent','remediationScriptContent','runAsAccount','enforceSignatureCheck','runAs32Bit','roleScopeTagIds','deviceHealthScriptType','detectionScriptParameters','remediationScriptParameters')) {
        $update[$name] = $DesiredScript[$name]
    }
    $update
}

function Test-DesiredScriptMatch {
    param([Parameter(Mandatory)][object]$Actual, [Parameter(Mandatory)][object]$Desired)
    $null = Get-CanonicalServiceVersion -Value $Actual.version
    foreach ($name in @('displayName','description','publisher','detectionScriptContent','remediationScriptContent','runAsAccount','enforceSignatureCheck','runAs32Bit','isGlobalScript','deviceHealthScriptType')) {
        $property = $Actual.PSObject.Properties[$name]
        if ($null -eq $property -or ($property.Value | ConvertTo-Json -Compress) -cne ($Desired[$name] | ConvertTo-Json -Compress)) { return $false }
    }
    $actualTags = @($Actual.roleScopeTagIds | Sort-Object)
    if (($actualTags | ConvertTo-Json -Compress) -cne (@($Desired.roleScopeTagIds | Sort-Object) | ConvertTo-Json -Compress)) { return $false }
    if ((@($Actual.detectionScriptParameters) | ConvertTo-Json -Compress) -cne (@($Desired.detectionScriptParameters) | ConvertTo-Json -Compress)) { return $false }
    if ((@($Actual.remediationScriptParameters) | ConvertTo-Json -Compress) -cne (@($Desired.remediationScriptParameters) | ConvertTo-Json -Compress)) { return $false }
    return $true
}

function New-DesiredAssignmentBody {
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][ValidateSet('AllDevices','Group')][string]$AssignmentScope,
        [string]$GroupId
    )
    $target = if ($AssignmentScope -eq 'AllDevices') {
        [ordered]@{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' }
    }
    else {
        [ordered]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $GroupId }
    }
    [ordered]@{
        '@odata.type' = '#microsoft.graph.deviceHealthScriptAssignment'
        target = $target
        runRemediationScript = [bool]$Manifest.assignment.runRemediationScript
        runSchedule = [ordered]@{
            '@odata.type' = '#microsoft.graph.deviceHealthScriptDailySchedule'
            interval = 1
            useUtc = $true
            time = [string]$Manifest.assignment.schedule.time
        }
    }
}

function New-CompleteAssignmentSetBody {
    param(
        [Parameter(Mandatory)][object]$DesiredAssignment,
        [AllowNull()][object]$ExistingAssignment
    )
    $assignment = [ordered]@{
        '@odata.type' = [string]$DesiredAssignment.'@odata.type'
    }
    if ($null -ne $ExistingAssignment) {
        $assignmentId = [string]$ExistingAssignment.id
        if ([string]::IsNullOrWhiteSpace($assignmentId) -or $assignmentId.Length -gt 512 -or
            $assignmentId -cne $assignmentId.Trim() -or $assignmentId -match '\p{Cc}') {
            throw 'Assignment ID must be a nonempty opaque string of at most 512 characters without surrounding whitespace or control characters.'
        }
        $assignment.id = $assignmentId
    }
    $assignment.target = $DesiredAssignment.target
    $assignment.runRemediationScript = [bool]$DesiredAssignment.runRemediationScript
    $assignment.runSchedule = $DesiredAssignment.runSchedule
    [ordered]@{ deviceHealthScriptAssignments = @($assignment) }
}

function ConvertTo-NormalizedODataType {
    param([object]$Value)
    ([string]$Value).Trim().TrimStart('#').ToLowerInvariant()
}

function Get-NormalizedAssignmentTarget {
    param([Parameter(Mandatory)][object]$Assignment)
    $target = $Assignment.target
    $type = ConvertTo-NormalizedODataType $target.'@odata.type'
    $filterIdProperty = $target.PSObject.Properties['deviceAndAppManagementAssignmentFilterId']
    $filterTypeProperty = $target.PSObject.Properties['deviceAndAppManagementAssignmentFilterType']
    $filterId = if ($null -eq $filterIdProperty) { '' } else { [string]$filterIdProperty.Value }
    $filterType = if ($null -eq $filterTypeProperty) { '' } else { ([string]$filterTypeProperty.Value).Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($filterType)) { $filterType = 'none' }
    $filterId = $filterId.Trim()
    if ($filterType -eq 'none' -and $filterId -eq '00000000-0000-0000-0000-000000000000') { $filterId = '' }
    [ordered]@{
        targetType = $type
        groupId = if ($type -eq 'microsoft.graph.groupassignmenttarget') { ([string]$target.groupId).ToLowerInvariant() } else { $null }
        filterType = $filterType
        filterId = if ([string]::IsNullOrWhiteSpace($filterId)) { $null } else { $filterId.ToLowerInvariant() }
    }
}

function Test-DesiredAssignmentMatch {
    param([Parameter(Mandatory)][object]$Actual, [Parameter(Mandatory)][object]$Desired)
    if (-not (Test-AssignmentTargetMatch -Actual $Actual -Desired $Desired)) { return $false }
    if ([bool]$Actual.runRemediationScript -ne [bool]$Desired.runRemediationScript) { return $false }
    if ((ConvertTo-NormalizedODataType $Actual.runSchedule.'@odata.type') -ne (ConvertTo-NormalizedODataType $Desired.runSchedule.'@odata.type')) { return $false }
    if ([int]$Actual.runSchedule.interval -ne 1 -or [bool]$Actual.runSchedule.useUtc -ne $true) { return $false }
    $actualTime = [timespan]::Zero
    $desiredTime = [timespan]::Zero
    if (-not [timespan]::TryParse([string]$Actual.runSchedule.time, [Globalization.CultureInfo]::InvariantCulture, [ref]$actualTime)) { return $false }
    if (-not [timespan]::TryParse([string]$Desired.runSchedule.time, [Globalization.CultureInfo]::InvariantCulture, [ref]$desiredTime)) { return $false }
    ($actualTime -eq $desiredTime)
}

function Test-AssignmentTargetMatch {
    param([Parameter(Mandatory)][object]$Actual, [Parameter(Mandatory)][object]$Desired)
    $actualTarget = Get-NormalizedAssignmentTarget -Assignment $Actual
    $desiredTarget = Get-NormalizedAssignmentTarget -Assignment $Desired
    (($actualTarget | ConvertTo-Json -Compress) -ceq ($desiredTarget | ConvertTo-Json -Compress))
}

function Get-NormalizedAssignmentStateShapes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Assignments)
    $shapes = foreach ($assignment in @($Assignments)) {
        $target = Get-NormalizedAssignmentTarget -Assignment $assignment
        $time = [timespan]::Zero
        $timeText = if ([timespan]::TryParse([string]$assignment.runSchedule.time, [Globalization.CultureInfo]::InvariantCulture, [ref]$time)) { $time.ToString('c', [Globalization.CultureInfo]::InvariantCulture) } else { [string]$assignment.runSchedule.time }
        [pscustomobject][ordered]@{
            id = [string]$assignment.id
            target = $target
            runRemediationScript = $assignment.runRemediationScript
            scheduleType = ConvertTo-NormalizedODataType $assignment.runSchedule.'@odata.type'
            interval = $assignment.runSchedule.interval
            useUtc = $assignment.runSchedule.useUtc
            time = $timeText
        }
    }
    @($shapes | Sort-Object id)
}

function Get-AssignmentSetCurrentStateDigest {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Assignments)
    $state = [ordered]@{ assignments=@(Get-NormalizedAssignmentStateShapes -Assignments $Assignments) }
    Get-Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($state | ConvertTo-Json -Depth 20 -Compress)))
}

function Get-DeviceHealthScriptCurrentStateDigest {
    param([Parameter(Mandatory)][object]$Script, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Assignments)
    $scriptShape = [ordered]@{}
    foreach ($name in @('id','displayName','description','publisher','version','detectionScriptContent','remediationScriptContent','runAsAccount','enforceSignatureCheck','runAs32Bit','isGlobalScript','deviceHealthScriptType')) {
        $property = $Script.PSObject.Properties[$name]
        $scriptShape[$name] = if ($null -eq $property) { $null } else { $property.Value }
    }
    $scriptShape.roleScopeTagIds = @($Script.roleScopeTagIds | ForEach-Object { [string]$_ } | Sort-Object)
    $scriptShape.detectionScriptParameters = @($Script.detectionScriptParameters)
    $scriptShape.remediationScriptParameters = @($Script.remediationScriptParameters)
    $state = [ordered]@{ script=$scriptShape; assignments=@(Get-NormalizedAssignmentStateShapes -Assignments $Assignments) }
    Get-Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes(($state | ConvertTo-Json -Depth 20 -Compress)))
}

function Write-DurableJsonDocument {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value,
        [switch]$CreateNew,
        [string]$ExpectedLineageId,
        [scriptblock]$BeforeCommit
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine)
    $leaf = [IO.Path]::GetFileName($Path)
    $tempPath = Join-Path $parent ('.{0}.{1}.tmp' -f $leaf,[guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $parent ('.{0}.{1}.bak' -f $leaf,[guid]::NewGuid().ToString('N'))
    try {
        $tempStream = [IO.FileStream]::new($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
        try {
            $tempStream.Write($bytes, 0, $bytes.Length)
            $tempStream.Flush($true)
        }
        finally { $tempStream.Dispose() }
        if (-not $CreateNew) {
            $existingBytes = [IO.File]::ReadAllBytes($Path)
            try { $existingText = [Text.UTF8Encoding]::new($false, $true).GetString($existingBytes) } catch { throw 'Existing publication receipt is not valid UTF-8; it was preserved.' }
            try { $existing = $existingText | ConvertFrom-Json -Depth 30 } catch { throw 'Existing publication receipt is unreadable; it was preserved.' }
            $lineageProperty = $existing.PSObject.Properties['operationLineageId']
            if ([string]::IsNullOrWhiteSpace($ExpectedLineageId) -or $null -eq $lineageProperty -or [string]$lineageProperty.Value -cne $ExpectedLineageId) { throw 'Existing publication receipt lineage does not match this operation; it was preserved.' }
            foreach ($name in @('targetTenantId','callerTenantId','identityKey')) {
                $property = $existing.PSObject.Properties[$name]
                if ($null -eq $property -or [string]$property.Value -cne [string]$Value.$name) { throw "Existing publication receipt $name does not match this operation; it was preserved." }
            }
            $artifactProperty = $existing.PSObject.Properties['artifact']
            if ($null -eq $artifactProperty -or $null -eq $artifactProperty.Value) { throw 'Existing publication receipt artifact binding is missing; it was preserved.' }
            foreach ($name in @('packageManifestSha256','detectionScriptSha256','remediationScriptSha256')) {
                $property = $artifactProperty.Value.PSObject.Properties[$name]
                if ($null -eq $property -or [string]$property.Value -cne [string]$Value.artifact.$name) { throw "Existing publication receipt artifact $name does not match this operation; it was preserved." }
            }
            $statusProperty = $existing.PSObject.Properties['status']
            if ($null -eq $statusProperty -or ([string]$statusProperty.Value) -notin @('mutation-in-progress','unknown-outcome')) { throw 'Existing publication receipt is not an owned mutable checkpoint; it was preserved.' }
        }
        if ($BeforeCommit) { & $BeforeCommit -Path $Path -TemporaryPath $tempPath }
        if ($CreateNew) { [IO.File]::Move($tempPath, $Path) }
        else { [IO.File]::Replace($tempPath, $Path, $backupPath, $true) }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) { Remove-Item -LiteralPath $tempPath -Force }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) { Remove-Item -LiteralPath $backupPath -Force }
    }
}

function Write-PublicationCheckpoint {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TargetTenantId,
        [Parameter(Mandatory)][string]$CallerTenantId,
        [Parameter(Mandatory)][object]$Package,
        [Parameter(Mandatory)][string]$AssignmentScope,
        [string]$GroupId,
        [string]$DeviceHealthScriptId,
        [string]$PendingAction,
        [Parameter(Mandatory)][string]$LineageId,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$CompletedActions,
        [ValidateSet('mutation-in-progress','unknown-outcome')][string]$Status = 'mutation-in-progress',
        [switch]$CreateNew
    )
    $checkpoint = [ordered]@{
        schemaVersion = '1.0'
        status = $Status
        operationLineageId = $LineageId
        generatedAt = [datetimeoffset]::UtcNow.ToString('o')
        targetTenantId = $TargetTenantId
        callerTenantId = $CallerTenantId
        identityKey = [string]$Package.Manifest.identityKey
        deviceHealthScriptId = $DeviceHealthScriptId
        completedActions = @($CompletedActions)
        artifact = [ordered]@{
            packageManifestSha256 = [string]$Package.ManifestSha256
            detectionScriptSha256 = [string]$Package.Manifest.detectionScript.sha256
            remediationScriptSha256 = [string]$Package.Manifest.remediationScript.sha256
        }
        pendingAction = $PendingAction
        assignment = [ordered]@{ scope=$AssignmentScope; groupId=$GroupId; schedule=$Package.Manifest.assignment.schedule }
        evidenceBoundary = if ($PendingAction) { 'A mutation is about to be submitted and its outcome may become ambiguous. Preserve this checkpoint and reconcile before retrying.' } else { 'A mutation response was received but final script and assignment readback has not yet succeeded. Reconcile the exact recorded script ID before retrying.' }
    }
    Write-DurableJsonDocument -Path $Path -Value $checkpoint -CreateNew:$CreateNew -ExpectedLineageId $LineageId
}

function Invoke-IntuneDeviceHealthScriptPublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageManifestPath,
        [Parameter(Mandatory)][string]$TargetTenantId,
        [Parameter(Mandatory)][string]$CallerTenantId,
        [Parameter(Mandatory)][ValidateSet('AllDevices','Group')][string]$AssignmentScope,
        [string]$AssignmentGroupId,
        [AllowNull()][AllowEmptyString()][string]$ExpectedExistingScriptId,
        [AllowNull()][AllowEmptyString()][string]$ExpectedExistingStateSha256,
        [Parameter(Mandatory)][scriptblock]$GraphRequest,
        [Parameter(Mandatory)][string]$ReviewOutputPath,
        [switch]$Execute
    )
    $targetTenant = ConvertTo-RequiredGuid -Value $TargetTenantId -Name 'TargetTenantId'
    $callerTenant = ConvertTo-RequiredGuid -Value $CallerTenantId -Name 'CallerTenantId'
    if ($targetTenant -ne $callerTenant) { throw "CallerTenantId '$callerTenant' does not match TargetTenantId '$targetTenant'." }
    $groupId = $null
    if ($AssignmentScope -eq 'Group') {
        if ([string]::IsNullOrWhiteSpace($AssignmentGroupId)) { throw 'AssignmentGroupId is required when AssignmentScope is Group.' }
        $groupId = ConvertTo-RequiredGuid -Value $AssignmentGroupId -Name 'AssignmentGroupId'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($AssignmentGroupId)) { throw 'AssignmentGroupId must be omitted when AssignmentScope is AllDevices.' }

    $expectedScriptId = $null
    if (-not [string]::IsNullOrWhiteSpace($ExpectedExistingScriptId)) {
        $expectedScriptId = ConvertTo-RequiredGuid -Value $ExpectedExistingScriptId -Name 'ExpectedExistingScriptId'
        if ([string]$ExpectedExistingStateSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'ExpectedExistingStateSha256 is required with ExpectedExistingScriptId and must be lowercase SHA-256.' }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExpectedExistingStateSha256)) { throw 'ExpectedExistingScriptId is required with ExpectedExistingStateSha256.' }

    $package = Import-IntuneDeviceHealthScriptPackage -ManifestPath $PackageManifestPath
    $manifest = $package.Manifest
    $desiredScript = New-DesiredDeviceHealthScriptBody -Package $package
    $desiredAssignment = New-DesiredAssignmentBody -Manifest $manifest -AssignmentScope $AssignmentScope -GroupId $groupId
    $reviewFullPath = [IO.Path]::GetFullPath($ReviewOutputPath)
    if ($reviewFullPath -in @($package.ManifestPath, $package.DetectionPath, $package.RemediationPath)) { throw 'ReviewOutputPath cannot overwrite a package input.' }
    if (Test-Path -LiteralPath $reviewFullPath) { throw 'ReviewOutputPath already exists. Preserve it and use a new distinct path for every plan or execution.' }
    $operationLineageId = [guid]::NewGuid().ToString('D')
    $checkpointCreated = $false
    $base = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
    $allScripts = @(Get-GraphCollection -GraphRequest $GraphRequest -InitialUri $base -AllowedPathPrefix '/beta/deviceManagement/deviceHealthScripts')
    $marker = "[azd-managed-id:$($manifest.identityKey)]"
    $matches = @($allScripts | Where-Object { ([string]$_.description).Contains($marker, [StringComparison]::Ordinal) })
    if ($matches.Count -gt 1) { throw "Multiple device health scripts use identity marker '$marker'." }
    if ($matches.Count -eq 0 -and @($allScripts | Where-Object { [string]::Equals(([string]$_.displayName).Trim(), ([string]$manifest.displayName).Trim(), [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
        throw 'A device health script already uses the reviewed display name without the approved identity marker.'
    }

    $actions = New-Object 'System.Collections.Generic.List[string]'
    $completedActions = New-Object 'System.Collections.Generic.List[string]'
    $scriptId = $null
    $actualScript = $null
    $assignments = @()
    $observedStateSha256 = $null
    $reviewedAssignmentSetSha256 = $null
    $observedAssignmentSetSha256 = $null
    if ($matches.Count -eq 0) {
        if ($expectedScriptId) { throw 'ExpectedExistingScriptId was supplied, but the approved owned script was not found.' }
        $actions.Add('createScript')
        if ($Execute) {
            Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -CompletedActions @() -PendingAction createScript -LineageId $operationLineageId -CreateNew
            $checkpointCreated = $true
            try {
                $created = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method POST -Uri $base -Body $desiredScript
                $scriptId = ConvertTo-RequiredGuid -Value ([string]$created.id) -Name 'created script id'
            }
            catch {
                $failure = $_
                try { Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -CompletedActions @() -PendingAction createScript -LineageId $operationLineageId -Status unknown-outcome } catch {}
                throw $failure
            }
            $completedActions.Add('createScript')
            Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -LineageId $operationLineageId
            $actualScript = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri "$base/$scriptId"
            if ((ConvertTo-RequiredGuid -Value ([string]$actualScript.id) -Name 'created script readback id') -ne $scriptId) { throw 'Created script readback ID did not match the created ID; assignment was not attempted.' }
            if (-not (Test-DesiredScriptMatch -Actual $actualScript -Desired $desiredScript)) { throw 'Created script readback did not match the reviewed package; assignment was not attempted.' }
        }
    }
    else {
        $scriptId = ConvertTo-RequiredGuid -Value ([string]$matches[0].id) -Name 'existing script id'
        if (-not $expectedScriptId) {
            if ($Execute) { throw 'An owned script exists. Supply its explicitly reviewed ID and current state digest; null expectation is create-only.' }
            $actions.Add('existingRequiresExplicitReview')
        }
        elseif ($scriptId -ne $expectedScriptId) { throw "Owned script ID '$scriptId' does not match ExpectedExistingScriptId '$expectedScriptId'." }
        $actualScript = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri "$base/$scriptId"
        if ((ConvertTo-RequiredGuid -Value ([string]$actualScript.id) -Name 'existing script readback id') -ne $scriptId) { throw 'Existing script readback ID did not match the approved owned ID.' }
        $assignments = @(Get-GraphCollection -GraphRequest $GraphRequest -InitialUri "$base/$scriptId/assignments" -AllowedPathPrefix "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments")
        $reviewedAssignmentSetSha256 = Get-AssignmentSetCurrentStateDigest -Assignments $assignments
        $observedStateSha256 = Get-DeviceHealthScriptCurrentStateDigest -Script $actualScript -Assignments $assignments
        if ($expectedScriptId -and $observedStateSha256 -cne $ExpectedExistingStateSha256) { throw "Existing script state digest changed: expected $ExpectedExistingStateSha256, found $observedStateSha256." }
        if ($expectedScriptId) {
            if (-not (Test-DesiredScriptMatch -Actual $actualScript -Desired $desiredScript)) { $actions.Add('updateScript') }
            else { $actions.Add('reuseScript') }
        }
    }

    if ($scriptId -and ($matches.Count -eq 0 -or $expectedScriptId)) {
        if ($matches.Count -eq 0) {
            $assignments = @()
            $reviewedAssignmentSetSha256 = Get-AssignmentSetCurrentStateDigest -Assignments $assignments
        }
        $matchingAssignments = @($assignments | Where-Object { Test-AssignmentTargetMatch -Actual $_ -Desired $desiredAssignment })
        $unexpected = @($assignments | Where-Object { $_ -notin $matchingAssignments })
        if ($unexpected.Count -gt 0) { throw 'Existing script has assignment targets outside the explicitly reviewed scope; publication stopped.' }
        if ($matchingAssignments.Count -gt 1) { throw 'Existing script has duplicate assignments for the explicitly reviewed target.' }
        if ($matchingAssignments.Count -eq 0) { $actions.Add('createAssignment') }
        elseif (-not (Test-DesiredAssignmentMatch -Actual $matchingAssignments[0] -Desired $desiredAssignment)) { $actions.Add('updateAssignment') }
        else { $actions.Add('reuseAssignment') }
    }
    elseif (-not $scriptId) {
        $reviewedAssignmentSetSha256 = Get-AssignmentSetCurrentStateDigest -Assignments @()
        $actions.Add('createAssignmentAfterScript')
    }

    if ($Execute) {
        if ($actions -contains 'updateScript') {
            $desiredUpdateScript = New-DesiredDeviceHealthScriptUpdateBody -DesiredScript $desiredScript
            Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -PendingAction updateScript -LineageId $operationLineageId -CreateNew:(-not $checkpointCreated)
            $checkpointCreated = $true
            try { $null = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method PATCH -Uri "$base/$scriptId" -Body $desiredUpdateScript }
            catch {
                $failure = $_
                try { Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -PendingAction updateScript -LineageId $operationLineageId -Status unknown-outcome } catch {}
                throw $failure
            }
            $completedActions.Add('updateScript')
            Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -LineageId $operationLineageId
        }
        $actualScript = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri "$base/$scriptId"
        if ((ConvertTo-RequiredGuid -Value ([string]$actualScript.id) -Name 'pre-assignment script readback id') -ne $scriptId) { throw 'Pre-assignment script readback ID did not match the approved script ID.' }
        if (-not (Test-DesiredScriptMatch -Actual $actualScript -Desired $desiredScript)) { throw 'Script readback did not match the reviewed package; assignment was not attempted.' }
        $assignments = @(Get-GraphCollection -GraphRequest $GraphRequest -InitialUri "$base/$scriptId/assignments" -AllowedPathPrefix "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments")
        $currentAssignmentSetSha256 = Get-AssignmentSetCurrentStateDigest -Assignments $assignments
        $matchingAssignments = @($assignments | Where-Object { Test-AssignmentTargetMatch -Actual $_ -Desired $desiredAssignment })
        $unexpected = @($assignments | Where-Object { $_ -notin $matchingAssignments })
        if ($unexpected.Count -gt 0 -or $matchingAssignments.Count -gt 1) { throw 'Assignment set changed outside the explicitly reviewed target before mutation.' }
        if ($currentAssignmentSetSha256 -cne $reviewedAssignmentSetSha256) { throw 'Assignment set changed after review; no complete-set assignment action was attempted.' }
        if ($matchingAssignments.Count -eq 0 -and -not ($actions -contains 'createAssignment' -or $actions -contains 'createAssignmentAfterScript')) { throw 'Reviewed assignment disappeared before mutation.' }
        if (($actions -contains 'createAssignment' -or $actions -contains 'createAssignmentAfterScript') -and $matchingAssignments.Count -ne 0) { throw 'The reviewed assignment target appeared after review; no complete-set assignment action was attempted.' }
        if ($actions -contains 'updateAssignment' -and $matchingAssignments.Count -ne 1) { throw 'The reviewed assignment target changed after review; no complete-set assignment action was attempted.' }
        $assignmentAction = if ($actions -contains 'updateAssignment') { 'updateAssignment' } elseif ($actions -contains 'createAssignment' -or $actions -contains 'createAssignmentAfterScript') { 'createAssignment' } else { $null }
        if ($assignmentAction) {
            $existingAssignment = if ($assignmentAction -eq 'updateAssignment') { $matchingAssignments[0] } else { $null }
            $completeAssignmentBody = New-CompleteAssignmentSetBody -DesiredAssignment $desiredAssignment -ExistingAssignment $existingAssignment
            Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -PendingAction assignCompleteSet -LineageId $operationLineageId -CreateNew:(-not $checkpointCreated)
            $checkpointCreated = $true
            try { $null = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method POST -Uri "$base/$scriptId/assign" -Body $completeAssignmentBody }
            catch {
                $failure = $_
                try { Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -PendingAction assignCompleteSet -LineageId $operationLineageId -Status unknown-outcome } catch {}
                throw $failure
            }
            $completedActions.Add($assignmentAction)
            Write-PublicationCheckpoint -Path $reviewFullPath -TargetTenantId $targetTenant -CallerTenantId $callerTenant -Package $package -AssignmentScope $AssignmentScope -GroupId $groupId -DeviceHealthScriptId $scriptId -CompletedActions @($completedActions) -LineageId $operationLineageId
        }

        $actualScript = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri "$base/$scriptId"
        if ((ConvertTo-RequiredGuid -Value ([string]$actualScript.id) -Name 'final script readback id') -ne $scriptId) { throw 'Final script readback ID did not match the approved script ID.' }
        if (-not (Test-DesiredScriptMatch -Actual $actualScript -Desired $desiredScript)) { throw 'Script readback did not match the reviewed package.' }
        $assignments = @(Get-GraphCollection -GraphRequest $GraphRequest -InitialUri "$base/$scriptId/assignments" -AllowedPathPrefix "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments")
        $matchingAssignments = @($assignments | Where-Object { Test-AssignmentTargetMatch -Actual $_ -Desired $desiredAssignment })
        if ($assignments.Count -ne 1 -or $matchingAssignments.Count -ne 1 -or -not (Test-DesiredAssignmentMatch -Actual $matchingAssignments[0] -Desired $desiredAssignment)) {
            throw 'Final assignment readback was not the complete reviewed target, filter, and schedule set.'
        }
        $observedAssignmentSetSha256 = Get-AssignmentSetCurrentStateDigest -Assignments $assignments
        $observedStateSha256 = Get-DeviceHealthScriptCurrentStateDigest -Script $actualScript -Assignments $assignments
    }

    if (-not $Execute -and $null -eq $observedAssignmentSetSha256) { $observedAssignmentSetSha256 = $reviewedAssignmentSetSha256 }
    $review = [ordered]@{
        schemaVersion = '1.0'
        status = if ($Execute) { 'validated' } else { 'planned' }
        operationLineageId = $operationLineageId
        generatedAt = [datetimeoffset]::UtcNow.ToString('o')
        targetTenantId = $targetTenant
        callerTenantId = $callerTenant
        execute = [bool]$Execute
        identityKey = [string]$manifest.identityKey
        displayName = [string]$manifest.displayName
        packageVersion = [string]$manifest.version
        serviceVersion = if ($null -eq $actualScript) { $null } else { Get-CanonicalServiceVersion -Value $actualScript.version }
        deviceHealthScriptId = $scriptId
        actions = @($actions)
        completedActions = @($completedActions)
        artifact = [ordered]@{
            packageManifestSha256 = [string]$package.ManifestSha256
            detectionScriptSha256 = [string]$manifest.detectionScript.sha256
            remediationScriptSha256 = [string]$manifest.remediationScript.sha256
        }
        execution = $manifest.execution
        assignment = [ordered]@{
            scope = $AssignmentScope
            groupId = $groupId
            targetType = [string]$desiredAssignment.target.'@odata.type'
            filterType = 'none'
            filterId = $null
            runRemediationScript = [bool]$manifest.assignment.runRemediationScript
            schedule = $manifest.assignment.schedule
        }
        expectedExisting = [ordered]@{ scriptId=$expectedScriptId; stateSha256=$ExpectedExistingStateSha256 }
        reviewedAssignmentSetSha256 = $reviewedAssignmentSetSha256
        observedStateSha256 = $observedStateSha256
        observedAssignmentSetSha256 = $observedAssignmentSetSha256
        evidenceBoundary = 'Graph readback proves control-plane content and assignment only. It does not prove endpoint execution, effective Defender policy, or availability of the local full inventory.'
    }
    Write-DurableJsonDocument -Path $reviewFullPath -Value $review -CreateNew:(-not $checkpointCreated) -ExpectedLineageId $operationLineageId
    [pscustomobject]$review
}

function Get-IntuneDeviceHealthScriptReadback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetTenantId,
        [Parameter(Mandatory)][string]$CallerTenantId,
        [Parameter(Mandatory)][string]$DeviceHealthScriptId,
        [Parameter(Mandatory)][string]$PackageManifestPath,
        [Parameter(Mandatory)][ValidateSet('AllDevices','Group')][string]$AssignmentScope,
        [string]$AssignmentGroupId,
        [Parameter(Mandatory)][scriptblock]$GraphRequest,
        [Parameter(Mandatory)][scriptblock]$OutputProjector,
        [Parameter(Mandatory)][string]$OutputPath,
        [ValidateRange(1,720)][int]$MaximumStateAgeHours = 48,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )
    $targetTenant = ConvertTo-RequiredGuid -Value $TargetTenantId -Name 'TargetTenantId'
    $callerTenant = ConvertTo-RequiredGuid -Value $CallerTenantId -Name 'CallerTenantId'
    $scriptId = ConvertTo-RequiredGuid -Value $DeviceHealthScriptId -Name 'DeviceHealthScriptId'
    if ($targetTenant -ne $callerTenant) { throw "CallerTenantId '$callerTenant' does not match TargetTenantId '$targetTenant'." }
    $groupId = $null
    if ($AssignmentScope -eq 'Group') {
        if ([string]::IsNullOrWhiteSpace($AssignmentGroupId)) { throw 'AssignmentGroupId is required when AssignmentScope is Group.' }
        $groupId = ConvertTo-RequiredGuid -Value $AssignmentGroupId -Name 'AssignmentGroupId'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($AssignmentGroupId)) { throw 'AssignmentGroupId must be omitted when AssignmentScope is AllDevices.' }
    $package = Import-IntuneDeviceHealthScriptPackage -ManifestPath $PackageManifestPath
    $desiredScript = New-DesiredDeviceHealthScriptBody -Package $package
    $desiredAssignment = New-DesiredAssignmentBody -Manifest $package.Manifest -AssignmentScope $AssignmentScope -GroupId $groupId
    $outputFullPath = [IO.Path]::GetFullPath($OutputPath)
    if ($outputFullPath -in @($package.ManifestPath,$package.DetectionPath,$package.RemediationPath)) { throw 'OutputPath cannot overwrite a package input.' }
    if (Test-Path -LiteralPath $outputFullPath) { throw 'OutputPath already exists. Preserve it and use a new distinct readback path.' }
    $base = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$scriptId"
    $script = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri $base
    if ((ConvertTo-RequiredGuid -Value ([string]$script.id) -Name 'readback script id') -ne $scriptId) { throw 'Script readback ID did not match the requested ID.' }
    if (-not (Test-DesiredScriptMatch -Actual $script -Desired $desiredScript)) { throw 'Script readback does not match the exact reviewed package.' }
    $assignments = @(Get-GraphCollection -GraphRequest $GraphRequest -InitialUri "$base/assignments" -AllowedPathPrefix "/beta/deviceManagement/deviceHealthScripts/$scriptId/assignments")
    $matchingAssignments = @($assignments | Where-Object { Test-AssignmentTargetMatch -Actual $_ -Desired $desiredAssignment })
    if ($assignments.Count -ne 1 -or $matchingAssignments.Count -ne 1 -or -not (Test-DesiredAssignmentMatch -Actual $matchingAssignments[0] -Desired $desiredAssignment)) {
        throw 'Script assignment readback does not match the complete reviewed target, filter, and schedule set.'
    }
    $stateCollectionUri = "$base/deviceRunStates?`$expand=managedDevice"
    $states = @(Get-GraphCollection -GraphRequest $GraphRequest -InitialUri $stateCollectionUri -AllowedPathPrefix "/beta/deviceManagement/deviceHealthScripts/$scriptId/deviceRunStates")
    $stateRecords = foreach ($state in $states) {
        $stateId = ConvertTo-BoundedOpaqueIdentifier -Value $state.id -Name 'device run state id'
        $managedDeviceProperty = $state.PSObject.Properties['managedDevice']
        if ($null -eq $managedDeviceProperty -or $null -eq $managedDeviceProperty.Value) { throw "Device run state '$stateId' did not include the expanded managedDevice relationship." }
        $managedDeviceId = ConvertTo-RequiredGuid -Value ([string]$managedDeviceProperty.Value.id) -Name "device run state '$stateId' managed device id"
        [pscustomobject][ordered]@{ state=$state; id=$stateId; managedDeviceId=$managedDeviceId }
    }
    $seenStateIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $stateRecords) {
        if (-not $seenStateIds.Add($record.id)) { throw 'Duplicate device run state IDs were returned.' }
    }
    $summaries = foreach ($record in $stateRecords) {
        $state = $record.state
        $stateId = $record.id
        $managedDeviceId = $record.managedDeviceId
        $deviceUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/${managedDeviceId}?`$select=id,azureADDeviceId,lastSyncDateTime"
        $device = Invoke-GraphRequestChecked -GraphRequest $GraphRequest -Method GET -Uri $deviceUri
        $directManagedDeviceId = ConvertTo-RequiredGuid -Value ([string]$device.id) -Name 'managed device readback id'
        if ($directManagedDeviceId -cne $managedDeviceId) { throw "Device run state '$stateId' expanded managed device ID did not match the direct managed device readback." }
        $entraDeviceId = ConvertTo-RequiredGuid -Value ([string]$device.azureADDeviceId) -Name 'managed device azureADDeviceId'
        $stateTime = ConvertTo-StrictUtcTimestamp -Value $state.lastStateUpdateDateTime -Name 'device run state lastStateUpdateDateTime'
        $fresh = $stateTime -le $Now.ToUniversalTime() -and $stateTime -ge $Now.ToUniversalTime().AddHours(-$MaximumStateAgeHours)
        $output = [string]$state.preRemediationDetectionScriptOutput
        $projection = & $OutputProjector -Output $output -State $state -StateTime $stateTime -Now $Now -MaximumStateAgeHours $MaximumStateAgeHours
        if ($null -eq $projection -or $null -eq $projection.PSObject.Properties['summary'] -or $null -eq $projection.PSObject.Properties['eligibleForReview']) {
            throw 'OutputProjector must return summary and eligibleForReview properties.'
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($output)
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { $outputHash = ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $algorithm.Dispose() }
        [ordered]@{
            stateId = $stateId
            managedDeviceId = $managedDeviceId
            entraDeviceId = $entraDeviceId
            detectionState = [string]$state.detectionState
            lastStateUpdateDateTime = $stateTime.ToString('o')
            fresh = $fresh
            outputLength = $output.Length
            outputSha256 = $outputHash
            summary = $projection.summary
            eligibleForReview = [bool]$projection.eligibleForReview
        }
    }
    $managedIds = @($summaries | ForEach-Object { $_.managedDeviceId })
    $entraIds = @($summaries | ForEach-Object { $_.entraDeviceId })
    if (@($managedIds | Sort-Object -Unique).Count -ne $managedIds.Count) { throw 'Multiple run states mapped to the same managed device ID.' }
    if (@($entraIds | Sort-Object -Unique).Count -ne $entraIds.Count) { throw 'Multiple run states mapped to the same Entra device ID.' }
    $readback = [ordered]@{
        schemaVersion = '1.0'
        capturedAt = [datetimeoffset]::UtcNow.ToString('o')
        targetTenantId = $targetTenant
        callerTenantId = $callerTenant
        package = [ordered]@{ identityKey=[string]$package.Manifest.identityKey; version=[string]$package.Manifest.version; manifestSha256=[string]$package.ManifestSha256; detectionScriptSha256=[string]$package.Manifest.detectionScript.sha256; remediationScriptSha256=[string]$package.Manifest.remediationScript.sha256 }
        deviceHealthScript = [ordered]@{ id = $scriptId; displayName = [string]$script.displayName; description = [string]$script.description; serviceVersion=Get-CanonicalServiceVersion -Value $script.version; stateSha256=Get-DeviceHealthScriptCurrentStateDigest -Script $script -Assignments $assignments }
        expectedAssignment = [ordered]@{ scope=$AssignmentScope; groupId=$groupId; targetType=[string]$desiredAssignment.target.'@odata.type'; filterType='none'; filterId=$null; runRemediationScript=[bool]$package.Manifest.assignment.runRemediationScript; schedule=$package.Manifest.assignment.schedule }
        assignments = @($assignments | ForEach-Object { $target=Get-NormalizedAssignmentTarget -Assignment $_; [ordered]@{ id = [string]$_.id; targetType=$target.targetType; groupId=$target.groupId; filterType=$target.filterType; filterId=$target.filterId; runRemediationScript = [bool]$_.runRemediationScript; runSchedule = $_.runSchedule } })
        deviceRunStates = @($summaries)
        endpointLocalInventoryFileAvailableFromServer = $false
        evidenceBoundary = 'Intune device run states retain bounded script output and latest control-plane state. The caller-supplied projector controls which reviewed fields are persisted. A truncated result does not make an endpoint local full inventory available from Graph.'
    }
    Write-DurableJsonDocument -Path $outputFullPath -Value $readback -CreateNew
    [pscustomobject]$readback
}

Export-ModuleMember -Function @(
    'Import-IntuneDeviceHealthScriptPackage',
    'Invoke-IntuneDeviceHealthScriptPublication',
    'Get-IntuneDeviceHealthScriptReadback'
)
