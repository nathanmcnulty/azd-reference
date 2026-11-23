[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ManifestPath,

    [ValidateRange(1, 5)]
    [int] $MaxConcurrency = 5,

    [switch] $AsJson,

    [switch] $FailOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion -lt [version] '7.6') {
    throw 'The portfolio check queue requires PowerShell 7.6 or later, matching the azd-reference tooling baseline.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'The portfolio check queue requires 64-bit PowerShell, matching the azd-reference tooling baseline.'
}

if (-not (Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) {
    Import-Module Microsoft.PowerShell.ThreadJob -ErrorAction Stop
}

function ConvertTo-UtcTimestamp {
    param([Parameter(Mandatory)][DateTimeOffset] $Value)

    $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-QueueFailureResult {
    param(
        [Parameter(Mandatory)] $Task,
        [Parameter(Mandatory)][string] $Message
    )

    $finishedAt = [DateTimeOffset]::UtcNow
    [pscustomobject][ordered]@{
        sequence = $Task.sequence
        id = $Task.id
        script = $Task.scriptPath
        serializationKey = $Task.serializationKey
        queuedAt = ConvertTo-UtcTimestamp -Value $Task.queuedAt
        startedAt = $null
        finishedAt = ConvertTo-UtcTimestamp -Value $finishedAt
        queueWaitMilliseconds = [Math]::Round((([System.Diagnostics.Stopwatch]::GetTimestamp() - [long] $Task.enqueueTimestamp) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency), 3)
        runMilliseconds = 0.0
        status = 'failed'
        exitCode = 1
        lastNativeExitCode = $null
        error = $Message
        output = @()
    }
}

function Get-QueueJobFailureMessage {
    param(
        [Parameter(Mandatory)] $Job,
        [AllowNull()][string] $ReceiveFailureMessage
    )

    $reason = $Job.JobStateInfo.Reason
    if (-not $reason) {
        $childJobs = @($Job.ChildJobs)
        if ($childJobs.Count -gt 0 -and $null -ne $childJobs[0]) {
            $reason = $childJobs[0].JobStateInfo.Reason
        }
    }

    $message = if ($reason) { $reason.Message } else { "Worker ended in state '$($Job.State)' without returning a result." }
    if ($ReceiveFailureMessage) { $message = "$message Receive-Job detail: $ReceiveFailureMessage" }
    $message
}

$resolvedManifest = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) {
    throw "ManifestPath must be an existing file: '$resolvedManifest'."
}

try {
    $manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
}
catch {
    throw "The portfolio check manifest is not valid JSON: $($_.Exception.Message)"
}

if ($manifest -isnot [System.Collections.IDictionary]) {
    throw 'The portfolio check manifest must be a JSON object.'
}
if (-not $manifest.Contains('schemaVersion') -or [string] $manifest.schemaVersion -ne '1.0') {
    throw "The portfolio check manifest must use schemaVersion '1.0'."
}
if (-not $manifest.Contains('checks')) {
    throw "The portfolio check manifest must contain a 'checks' array."
}

$manifestChecks = @($manifest.checks)
if ($manifestChecks.Count -lt 1 -or $manifestChecks.Count -gt 100) {
    throw 'A portfolio check manifest must contain between 1 and 100 checks.'
}

$manifestDirectory = [System.IO.Path]::GetDirectoryName($resolvedManifest)
$seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$pending = [System.Collections.Generic.List[object]]::new()
$sequence = 0

foreach ($entry in $manifestChecks) {
    $sequence++
    if ($entry -isnot [System.Collections.IDictionary]) {
        throw "Check $sequence must be a JSON object."
    }

    foreach ($requiredProperty in @('id', 'executionClass', 'script')) {
        if (-not $entry.Contains($requiredProperty)) {
            throw "Check $sequence is missing '$requiredProperty'."
        }
    }

    $id = [string] $entry.id
    if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "Check $sequence has an invalid id '$id'."
    }
    if (-not $seenIds.Add($id)) {
        throw "Check id '$id' is duplicated."
    }
    if ([string] $entry.executionClass -cne 'offline') {
        throw "Check '$id' must declare executionClass 'offline'."
    }

    $relativeOrAbsoluteScript = [string] $entry.script
    if ([string]::IsNullOrWhiteSpace($relativeOrAbsoluteScript)) {
        throw "Check '$id' must provide a script path."
    }
    $scriptPath = if ([System.IO.Path]::IsPathRooted($relativeOrAbsoluteScript)) {
        [System.IO.Path]::GetFullPath($relativeOrAbsoluteScript)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $manifestDirectory $relativeOrAbsoluteScript))
    }
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals([System.IO.Path]::GetExtension($scriptPath), '.ps1')) {
        throw "Check '$id' must point to a PowerShell .ps1 script."
    }
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Check '$id' script does not exist: '$scriptPath'."
    }

    $arguments = @()
    if ($entry.Contains('arguments') -and $null -ne $entry.arguments) {
        if ($entry.arguments -is [string]) {
            throw "Check '$id' arguments must be a JSON array of strings."
        }
        $arguments = @($entry.arguments)
        foreach ($argument in $arguments) {
            if ($argument -isnot [string]) {
                throw "Check '$id' arguments must be a JSON array of strings."
            }
        }
    }

    $serializationKey = ''
    if ($entry.Contains('serializationKey') -and $null -ne $entry.serializationKey) {
        if ($entry.serializationKey -isnot [string]) {
            throw "Check '$id' serializationKey must be a string or null."
        }
        $serializationKey = ([string] $entry.serializationKey).Trim()
    }

    $queuedAt = [DateTimeOffset]::UtcNow
    $pending.Add([pscustomobject][ordered]@{
        sequence = $sequence
        id = $id
        scriptPath = $scriptPath
        arguments = [string[]] $arguments
        serializationKey = $serializationKey
        normalizedSerializationKey = if ($serializationKey.Length -gt 0) { $serializationKey.ToUpperInvariant() } else { $null }
        queuedAt = $queuedAt
        enqueueTimestamp = [System.Diagnostics.Stopwatch]::GetTimestamp()
    })
}

$queueStartedAt = [DateTimeOffset]::UtcNow
$queueTimer = [System.Diagnostics.Stopwatch]::StartNew()
$running = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()

while ($pending.Count -gt 0 -or $running.Count -gt 0) {
    $madeProgress = $false

    # Scan past blocked keys so one busy checkout or target does not hold up
    # unrelated work that can safely start in another slot.
    for ($pendingIndex = 0; $pendingIndex -lt $pending.Count -and $running.Count -lt $MaxConcurrency;) {
        $task = $pending[$pendingIndex]
        $keyOccupied = $false
        if ($null -ne $task.normalizedSerializationKey) {
            $keyOccupied = @(
                $running | Where-Object {
                    $_.normalizedSerializationKey -ceq $task.normalizedSerializationKey
                }
            ).Count -gt 0
        }
        if ($keyOccupied) {
            $pendingIndex++
            continue
        }

        $workerSpec = [pscustomobject][ordered]@{
            sequence = $task.sequence
            id = $task.id
            scriptPath = $task.scriptPath
            arguments = $task.arguments
            serializationKey = $task.serializationKey
            queuedAt = ConvertTo-UtcTimestamp -Value $task.queuedAt
            enqueueTimestamp = $task.enqueueTimestamp
        }

        try {
            $safeJobName = $task.id -replace '[^A-Za-z0-9_.-]', '_'
            $job = Start-ThreadJob -Name "portfolio-$safeJobName" -ScriptBlock {
                $queueTask = $using:workerSpec

                $startedAt = [DateTimeOffset]::UtcNow
                $queueWaitMilliseconds = ([System.Diagnostics.Stopwatch]::GetTimestamp() - [long] $queueTask.enqueueTimestamp) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
                $runTimer = [System.Diagnostics.Stopwatch]::StartNew()
                $output = [System.Collections.Generic.List[string]]::new()
                $workerState = [pscustomobject]@{
                    status = 'passed'
                    errorMessage = $null
                    lastNativeExitCode = $null
                }
                $exitCode = 0
                $global:LASTEXITCODE = 0

                try {
                    $ErrorActionPreference = 'Stop'
                    $invokeArguments = @($queueTask.arguments)
                    & $queueTask.scriptPath @invokeArguments 2>&1 | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                            $workerState.status = 'failed'
                            if ($exitCode -eq 0) { $exitCode = 1 }
                            if (-not $workerState.errorMessage) { $workerState.errorMessage = $_.ToString() }
                        }
                        $output.Add([string] $_)
                    }
                    $workerState.lastNativeExitCode = [int] $global:LASTEXITCODE
                    if ([int] $global:LASTEXITCODE -ne 0) {
                        $workerState.status = 'failed'
                        $exitCode = [int] $global:LASTEXITCODE
                    }
                }
                catch {
                    $workerState.status = 'failed'
                    $workerState.lastNativeExitCode = [int] $global:LASTEXITCODE
                    $exitCode = if ($workerState.lastNativeExitCode -ne 0) { $workerState.lastNativeExitCode } else { 1 }
                    $workerState.errorMessage = $_.Exception.Message
                }
                finally {
                    $runTimer.Stop()
                    $finishedAt = [DateTimeOffset]::UtcNow
                }

                [pscustomobject][ordered]@{
                    sequence = $queueTask.sequence
                    id = $queueTask.id
                    script = $queueTask.scriptPath
                    serializationKey = $queueTask.serializationKey
                    queuedAt = $queueTask.queuedAt
                    startedAt = $startedAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
                    finishedAt = $finishedAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
                    queueWaitMilliseconds = [Math]::Round($queueWaitMilliseconds, 3)
                    runMilliseconds = [Math]::Round($runTimer.Elapsed.TotalMilliseconds, 3)
                    status = $workerState.status
                    exitCode = $exitCode
                    lastNativeExitCode = $workerState.lastNativeExitCode
                    error = $workerState.errorMessage
                    output = [string[]] $output.ToArray()
                }
            }
            $running.Add([pscustomobject]@{
                job = $job
                normalizedSerializationKey = $task.normalizedSerializationKey
                task = $task
            })
        }
        catch {
            $results.Add((Get-QueueFailureResult -Task $task -Message "Unable to start check: $($_.Exception.Message)"))
        }

        $pending.RemoveAt($pendingIndex)
        $madeProgress = $true
    }

    for ($runningIndex = $running.Count - 1; $runningIndex -ge 0; $runningIndex--) {
        $entry = $running[$runningIndex]
        if ($entry.job.State -notin @('Completed', 'Failed', 'Stopped')) { continue }

        $received = @()
        $receiveFailureMessage = $null
        try {
            $received = @(Receive-Job -Job $entry.job -ErrorAction SilentlyContinue)
        }
        catch {
            # Keep the receive detail alongside the durable job state and child error.
            $receiveFailureMessage = $_.Exception.Message
        }
        $record = @(
            $received | Where-Object {
                $null -ne $_ -and
                $_.PSObject.Properties.Name -contains 'id' -and
                $_.PSObject.Properties.Name -contains 'status' -and
                $_.PSObject.Properties.Name -contains 'queueWaitMilliseconds'
            } | Select-Object -Last 1
        )

        if ($record.Count -eq 0) {
            $message = Get-QueueJobFailureMessage -Job $entry.job -ReceiveFailureMessage $receiveFailureMessage
            $record = @(Get-QueueFailureResult -Task $entry.task -Message $message)
        }
        elseif ($entry.job.State -ne 'Completed') {
            $record[0].status = 'failed'
            $record[0].exitCode = 1
            if (-not $record[0].error) { $record[0].error = "Worker ended in state '$($entry.job.State)'." }
        }

        $results.Add($record[0])
        Remove-Job -Job $entry.job -Force -ErrorAction SilentlyContinue
        $running.RemoveAt($runningIndex)
        $madeProgress = $true
    }

    if (-not $madeProgress -and $running.Count -gt 0) {
        Start-Sleep -Milliseconds 25
    }
}

$queueTimer.Stop()
$queueFinishedAt = [DateTimeOffset]::UtcNow
$orderedResults = @($results | Sort-Object -Property sequence)
$failedCount = @($orderedResults | Where-Object status -ne 'passed').Count
$workerIntervals = [System.Collections.Generic.List[object]]::new()
foreach ($check in $orderedResults) {
    if (-not $check.startedAt -or -not $check.finishedAt) { continue }
    $workerIntervals.Add([pscustomobject]@{
        startedAt = [DateTimeOffset]::Parse($check.startedAt)
        finishedAt = [DateTimeOffset]::Parse($check.finishedAt)
    })
}
$observedMaxConcurrency = 0
foreach ($candidate in $workerIntervals) {
    $activeWorkers = @(
        $workerIntervals | Where-Object {
            $_.startedAt -le $candidate.startedAt -and $_.finishedAt -gt $candidate.startedAt
        }
    ).Count
    if ($activeWorkers -gt $observedMaxConcurrency) { $observedMaxConcurrency = $activeWorkers }
}
$summary = [pscustomobject][ordered]@{
    schemaVersion = '1.0'
    startedAt = ConvertTo-UtcTimestamp -Value $queueStartedAt
    finishedAt = ConvertTo-UtcTimestamp -Value $queueFinishedAt
    elapsedMilliseconds = [Math]::Round($queueTimer.Elapsed.TotalMilliseconds, 3)
    maxConcurrency = $MaxConcurrency
    observedMaxConcurrency = $observedMaxConcurrency
    checkCount = $orderedResults.Count
    passedCount = $orderedResults.Count - $failedCount
    failedCount = $failedCount
    checks = $orderedResults
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 10
}
else {
    $summary
}

if ($FailOnFailure -and $failedCount -gt 0) {
    throw "Portfolio check queue completed with $failedCount failed check(s)."
}
