Set-StrictMode -Version Latest

$script:StatusOrder = @('pass', 'fail', 'warning', 'info', 'skipped', 'planned')
$script:PhaseOrder = @('context', 'infrastructure', 'identity', 'configuration', 'security', 'runtime', 'delivery')
$script:SensitiveNamePattern = '(?i)(^|[-_])(authorization|access.?token|refresh.?token|secret|password|client.?secret|api.?key|callback.?url|webhook.?url|sas|signature|sig)([-_]|$)'
$script:SensitiveUrlPattern = '(?i)[?&](sig|signature|token|code|key|secret|sas)='

function ConvertTo-AzdSafeData {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object] $Value,

        [string] $Name = ''
    )

    process {
        if ($Name -match $script:SensitiveNamePattern) {
            return '[REDACTED]'
        }
        if ($null -eq $Value) {
            return $null
        }
        if ($Value -is [string]) {
            if ($Value -match $script:SensitiveUrlPattern) {
                return '[REDACTED URL]'
            }
            return $Value
        }
        if ($Value -is [System.Collections.IDictionary]) {
            $safe = [ordered]@{}
            foreach ($key in $Value.Keys) {
                $child = $Value[$key]
                if ($child -is [System.Collections.IEnumerable] -and $child -isnot [string] -and $child -isnot [System.Collections.IDictionary]) {
                    [object[]] $safeItems = @($child | ForEach-Object { ConvertTo-AzdSafeData -Value $_ -Name ([string] $key) })
                    $safe[[string] $key] = $safeItems
                }
                else {
                    $safe[[string] $key] = ConvertTo-AzdSafeData -Value $child -Name ([string] $key)
                }
            }
            return $safe
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $safe = [ordered]@{}
            foreach ($property in $Value.PSObject.Properties) {
                $child = $property.Value
                if ($child -is [System.Collections.IEnumerable] -and $child -isnot [string] -and $child -isnot [System.Collections.IDictionary]) {
                    [object[]] $safeItems = @($child | ForEach-Object { ConvertTo-AzdSafeData -Value $_ -Name $property.Name })
                    $safe[$property.Name] = $safeItems
                }
                else {
                    $safe[$property.Name] = ConvertTo-AzdSafeData -Value $child -Name $property.Name
                }
            }
            return $safe
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            return @($Value | ForEach-Object { ConvertTo-AzdSafeData -Value $_ })
        }
        if ($Value -is [ValueType]) {
            return $Value
        }
        return [string] $Value
    }
}

function New-AzdCheckOutcome {
    [CmdletBinding()]
    param(
        [ValidateSet('pass', 'warning', 'info', 'skipped')]
        [string] $Status = 'pass',

        [Parameter(Mandatory)]
        [string] $Summary,

        [AllowNull()]
        [object] $Expected,

        [AllowNull()]
        [object] $Actual,

        [hashtable] $Evidence = @{},

        [hashtable] $Metadata = @{},

        [AllowNull()]
        [string] $Remediation
    )

    $outcome = [pscustomobject] [ordered]@{
        status = $Status
        summary = $Summary
        expected = $Expected
        actual = $Actual
        evidence = $Evidence
        metadata = $Metadata
        remediation = $Remediation
    }
    $outcome.PSObject.TypeNames.Insert(0, 'Azd.Validation.CheckOutcome')
    return $outcome
}

function Invoke-AzdValidationCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z][a-z0-9.-]+$')]
        [string] $Id,

        [Parameter(Mandatory)]
        [ValidateSet('context', 'infrastructure', 'identity', 'configuration', 'security', 'runtime', 'delivery')]
        [string] $Phase,

        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter(Mandatory)]
        [string] $Summary,

        [Parameter(Mandatory)]
        [scriptblock] $Action,

        [ValidateSet('none', 'readOnly', 'negativeProbe', 'syntheticDelivery')]
        [string] $SideEffect = 'readOnly',

        [AllowNull()]
        [object] $Expected,

        [AllowNull()]
        [string] $Remediation,

        [switch] $Plan,

        [switch] $AllowSyntheticDelivery,

        [string] $SkipReason
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = 'pass'
    $actual = $null
    $evidence = @{}
    $metadata = @{}
    $resultSummary = $Summary
    $resultRemediation = $Remediation

    if ($Plan) {
        $status = if ($SkipReason) { 'skipped' } else { 'planned' }
        if ($SkipReason) { $resultSummary = $SkipReason }
    }
    elseif ($SkipReason) {
        $status = 'skipped'
        $resultSummary = $SkipReason
    }
    elseif ($SideEffect -eq 'syntheticDelivery' -and -not $AllowSyntheticDelivery) {
        $status = 'skipped'
        $resultSummary = 'Synthetic delivery was not authorized. Rerun with -TestDelivery to execute this check.'
    }
    else {
        try {
            $actionOutput = @(& $Action)
            if ($actionOutput.Count -gt 1) {
                throw 'A validation action returned more than one value. Return one New-AzdCheckOutcome object or no output.'
            }
            if ($actionOutput.Count -eq 1) {
                $outcome = $actionOutput[0]
                if ($outcome.PSObject.TypeNames -notcontains 'Azd.Validation.CheckOutcome') {
                    throw 'A validation action returned an unsupported value. Use New-AzdCheckOutcome for structured output.'
                }
                $status = $outcome.status
                $resultSummary = $outcome.summary
                $Expected = $outcome.expected
                $actual = $outcome.actual
                $evidence = $outcome.evidence
                $metadata = $outcome.metadata
                if ($outcome.remediation) { $resultRemediation = $outcome.remediation }
            }
        }
        catch {
            $status = 'fail'
            $resultSummary = $Summary
            $actual = [ordered]@{ exceptionType = $_.Exception.GetType().FullName }
        }
    }

    $stopwatch.Stop()
    return [pscustomobject] [ordered]@{
        id = $Id
        phase = $Phase
        title = $Title
        status = $status
        summary = $resultSummary
        sideEffect = $SideEffect
        durationMs = [int] $stopwatch.ElapsedMilliseconds
        expected = ConvertTo-AzdSafeData -Value $Expected
        actual = ConvertTo-AzdSafeData -Value $actual
        evidence = ConvertTo-AzdSafeData -Value $evidence
        remediation = $resultRemediation
        metadata = ConvertTo-AzdSafeData -Value $metadata
    }
}

function New-AzdValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TemplateName,

        [Parameter(Mandatory)]
        [string] $TemplateVersion,

        [Parameter(Mandatory)]
        [ValidateSet('plan', 'verify', 'delivery')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [datetimeoffset] $StartedAt,

        [Parameter(Mandatory)]
        [object[]] $Checks,

        [hashtable] $Environment = @{},

        [hashtable] $Requirements = @{ tools = @(); modules = @(); permissions = @() },

        [string[]] $NextSteps = @()
    )

    $completedAt = [datetimeoffset]::UtcNow
    $summary = [ordered]@{}
    foreach ($status in $script:StatusOrder) {
        $summary[$status] = @($Checks | Where-Object status -eq $status).Count
    }

    $outcome = if ($summary.fail -gt 0) {
        'failed'
    }
    elseif ($Mode -eq 'plan') {
        'planned'
    }
    elseif ($summary.warning -gt 0) {
        'passedWithWarnings'
    }
    else {
        'passed'
    }

    $orderedChecks = @($Checks | Sort-Object `
        @{ Expression = { $script:PhaseOrder.IndexOf($_.phase) } },
        @{ Expression = { $_.id } })

    return [pscustomobject] [ordered]@{
        schemaVersion = '1.0'
        reportType = 'azdDeploymentValidation'
        startedAt = $StartedAt.UtcDateTime.ToString('o')
        completedAt = $completedAt.UtcDateTime.ToString('o')
        durationMs = [int] [math]::Max(0, ($completedAt - $StartedAt).TotalMilliseconds)
        template = [ordered]@{ name = $TemplateName; version = $TemplateVersion }
        environment = ConvertTo-AzdSafeData -Value $Environment
        mode = $Mode
        requirements = ConvertTo-AzdSafeData -Value $Requirements
        outcome = $outcome
        summary = $summary
        checks = $orderedChecks
        nextSteps = @(ConvertTo-AzdSafeData -Value $NextSteps)
    }
}

function Write-AzdValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Report,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    if ([System.IO.Path]::IsPathRooted($OutputPath) -or $OutputPath -split '[\\/]' -contains '..') {
        throw 'OutputPath must be repository-relative and cannot contain parent traversal.'
    }

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $target = [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
    $comparison = if ($isWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $target.StartsWith($rootPrefix, $comparison)) {
        throw 'OutputPath resolves outside RepositoryRoot.'
    }

    $directory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = Join-Path $directory ('.{0}.{1}.tmp' -f [System.IO.Path]::GetFileName($target), [guid]::NewGuid().ToString('N'))
    try {
        $json = $Report | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    return [System.IO.Path]::GetRelativePath($root, $target).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
}

function Write-AzdValidationSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Report)

    foreach ($check in $Report.checks) {
        $prefix = '[{0}]' -f $check.status.ToUpperInvariant()
        Write-Host ('{0} {1}: {2}' -f $prefix, $check.id, $check.summary)
    }
    Write-Host ('Outcome: {0}; pass={1}, fail={2}, warning={3}, info={4}, skipped={5}, planned={6}' -f `
        $Report.outcome, $Report.summary.pass, $Report.summary.fail, $Report.summary.warning,
        $Report.summary.info, $Report.summary.skipped, $Report.summary.planned)
}

function Assert-AzdValidationSucceeded {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Report)

    if ($Report.outcome -eq 'failed') {
        throw "Deployment validation failed with $($Report.summary.fail) failed check(s)."
    }
}

Export-ModuleMember -Function @(
    'Assert-AzdValidationSucceeded',
    'ConvertTo-AzdSafeData',
    'Invoke-AzdValidationCheck',
    'New-AzdCheckOutcome',
    'New-AzdValidationReport',
    'Write-AzdValidationReport',
    'Write-AzdValidationSummary'
)
