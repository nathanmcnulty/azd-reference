[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PortfolioRoot,

    [string] $RegistryPath,

    [string] $BaselinePath,

    [switch] $AsJson,

    [switch] $FailOnFindings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SafeDirectory {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $Label
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        ($RelativePath -ne '.' -and ($RelativePath -split '[\\/]' | Where-Object { $_ -in '..', '.' }))) {
        throw "$Label must be a safe relative path: '$RelativePath'."
    }
    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = if ($RelativePath -eq '.') { $fullRoot } else { [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath)) }
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ([System.OperatingSystem]::IsWindows()) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($candidate -ne $fullRoot -and -not $candidate.StartsWith($rootPrefix, $comparison)) {
        throw "$Label resolves outside its allowed root: '$RelativePath'."
    }
    if ((Get-Item -LiteralPath $fullRoot -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "$Label root cannot be a symbolic link or reparse point: '$fullRoot'."
    }
    $cursor = $fullRoot
    if ($RelativePath -ne '.') {
        foreach ($segment in $RelativePath -split '[\\/]') {
            $cursor = Join-Path $cursor $segment
            if ((Test-Path -LiteralPath $cursor) -and
                ((Get-Item -LiteralPath $cursor -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                throw "$Label cannot traverse a symbolic link or reparse point: '$cursor'."
            }
        }
    }
    $candidate
}

function Get-NormalizedOrigin {
    param([Parameter(Mandatory)][string] $RepositoryRoot)

    $origin = @(& git -C $RepositoryRoot remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or $origin.Count -ne 1) { return $null }
    $value = ([string] $origin[0]).Trim()
    if ($value -match '^git@github\.com:(?<path>.+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.path -replace '\.git$', '')"
    }
    if ($value -match '^https://github\.com/(?<path>[^?#]+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.path -replace '\.git$', '')"
    }
    $value
}

function Resolve-ComponentReleaseRevision {
    param(
        [Parameter(Mandatory)][string] $ReferenceRoot,
        [Parameter(Mandatory)][string] $ComponentId,
        [Parameter(Mandatory)][string] $Version
    )

    $tagReference = "refs/tags/component/$ComponentId/v$Version"
    $revision = @(& git -C $ReferenceRoot rev-parse --verify --quiet --end-of-options "${tagReference}^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $revision.Count -ne 1 -or [string] $revision[0] -notmatch '^[0-9a-f]{40}$') {
        return [pscustomobject]@{ state = 'missing'; revision = $null }
    }
    $resolvedRevision = [string] $revision[0]
    $manifestPaths = @(& git -C $ReferenceRoot ls-tree -r --name-only $resolvedRevision -- components 2>$null | Where-Object { [string] $_ -match '^components/(?:.*/)?component\.json$' })
    if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ state = 'invalid'; revision = $resolvedRevision } }
    $manifestMatches = @(
        foreach ($manifestPath in $manifestPaths) {
            $raw = @(& git -C $ReferenceRoot show "${resolvedRevision}:$manifestPath" 2>$null) -join "`n"
            if ($LASTEXITCODE -ne 0) { continue }
            try { $manifest = $raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ([string] $manifest.id -eq $ComponentId -and [string] $manifest.version -eq $Version) { $manifest }
        }
    )
    if ($manifestMatches.Count -ne 1) { return [pscustomobject]@{ state = 'invalid'; revision = $resolvedRevision } }
    [pscustomobject]@{ state = 'valid'; revision = $resolvedRevision }
}

function Test-DependabotUpdatePolicy {
    param([Parameter(Mandatory)][string] $Raw)

    $lines = @($Raw -split '\r?\n')
    $updatesIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^updates:\s*(?:#.*)?$') { $updatesIndex = $index; break }
    }
    if ($updatesIndex -lt 0) { return $false }

    $entryIndent = $null
    $entries = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    for ($index = $updatesIndex + 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -match '^\S' -and $line -notmatch '^\s*#') { break }
        if ($line -match '^(?<indent>\s*)-\s+[^#\s]') {
            $indentLength = $Matches.indent.Length
            if ($null -eq $entryIndent) { $entryIndent = $indentLength }
            if ($indentLength -eq $entryIndent) {
                if ($current.Count -gt 0) { $entries.Add(($current -join "`n")); $current.Clear() }
            }
        }
        if ($null -ne $entryIndent) { $current.Add($line) }
    }
    if ($current.Count -gt 0) { $entries.Add(($current -join "`n")) }
    if ($entries.Count -eq 0) { return $false }
    foreach ($entry in $entries) {
        if ($entry -notmatch '(?m)^\s+groups:\s*(?:#.*)?$' -or
            $entry -notmatch '(?m)^\s+open-pull-requests-limit:\s*[1-9][0-9]*\s*(?:#.*)?$') { return $false }
    }
    $true
}

function Add-WorkflowPolicyFinding {
    param(
        [Parameter(Mandatory)][string] $CheckoutRoot,
        [Parameter(Mandatory)] $WorkflowPolicy,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]] $Findings
    )

    $workflowRoot = Join-Path $CheckoutRoot '.github/workflows'
    if (Test-Path -LiteralPath $workflowRoot -PathType Container) {
        foreach ($workflow in @(Get-ChildItem -LiteralPath $workflowRoot -File | Where-Object Extension -in '.yml', '.yaml')) {
            $relative = [System.IO.Path]::GetRelativePath($CheckoutRoot, $workflow.FullName).Replace('\', '/')
            $raw = Get-Content -LiteralPath $workflow.FullName -Raw
            if ([string] $WorkflowPolicy.externalActions -eq 'full-commit-sha') {
                foreach ($match in [regex]::Matches($raw, '(?m)^\s*-?\s*uses:\s*["'']?(?<value>[^\s"''#]+)')) {
                    $action = $match.Groups['value'].Value
                    if (-not $action.StartsWith('./', [System.StringComparison]::Ordinal) -and
                        -not $action.StartsWith('docker://', [System.StringComparison]::Ordinal) -and
                        $action -notmatch '@[0-9a-fA-F]{40}$') {
                        $Findings.Add("workflowActionUnpinned:${relative}:$action")
                    }
                }
            }
            if ([string] $WorkflowPolicy.defaultPermissions -eq 'contents-read') {
                $blockPolicy = $raw -match '(?ms)^permissions:\s*\r?\n(?:(?:[ \t]+[^\r\n]*)?\r?\n)*?[ \t]+contents:\s*read\s*(?:#.*)?$'
                $inlinePolicy = $raw -match '(?m)^permissions:\s*\{[^\r\n}]*contents:\s*read[^\r\n}]*\}\s*(?:#.*)?$'
                if (-not $blockPolicy -and -not $inlinePolicy) { $Findings.Add("workflowPermissionsNotRestricted:$relative") }
            }
        }
    }

    if ([string] $WorkflowPolicy.dependencyUpdates -eq 'grouped-and-bounded') {
        $dependabotPath = Join-Path $CheckoutRoot '.github/dependabot.yml'
        if (Test-Path -LiteralPath $dependabotPath -PathType Leaf) {
            $dependabot = Get-Content -LiteralPath $dependabotPath -Raw
            if (-not (Test-DependabotUpdatePolicy -Raw $dependabot)) {
                $Findings.Add('dependencyUpdatesNotGroupedAndBounded')
            }
        }
    }
}

function Get-CanonicalComponentTarget {
    param(
        [Parameter(Mandatory)][string] $ReferenceRoot,
        [Parameter(Mandatory)][string] $ComponentId
    )

    $canonicalMatches = @(
        Get-ChildItem -LiteralPath (Join-Path $ReferenceRoot 'components') -Filter component.json -File -Recurse |
            ForEach-Object {
                $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                if ([string] $manifest.id -eq $ComponentId) { $manifest }
            }
    )
    if ($canonicalMatches.Count -ne 1) { return @() }
    @($canonicalMatches[0].files | ForEach-Object { [string] $_.target })
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$portfolioRootFull = [System.IO.Path]::GetFullPath($PortfolioRoot)
if (-not (Test-Path -LiteralPath $portfolioRootFull -PathType Container)) {
    throw "PortfolioRoot must be an existing directory: '$portfolioRootFull'."
}
if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/consumers.json' }
$registryFull = [System.IO.Path]::GetFullPath($RegistryPath)
$registryRaw = Get-Content -LiteralPath $registryFull -Raw
if (-not ($registryRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop)) {
    throw 'The portfolio consumer registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json
if (-not $BaselinePath) { $BaselinePath = Join-Path $referenceRoot 'portfolio/repository-baseline.json' }
$baselineRaw = Get-Content -LiteralPath $BaselinePath -Raw
if (-not ($baselineRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/repository-baseline.schema.json') -ErrorAction Stop)) {
    throw 'The repository baseline does not satisfy its schema.'
}
$baseline = $baselineRaw | ConvertFrom-Json

$consumerIds = @{}
foreach ($consumer in @($registry.consumers)) {
    if ($consumerIds.ContainsKey([string] $consumer.id)) { throw "Duplicate consumer ID '$($consumer.id)'." }
    $consumerIds[[string] $consumer.id] = $true
    $componentIds = @{}
    foreach ($component in @($consumer.components)) {
        if ($componentIds.ContainsKey([string] $component.id)) { throw "Consumer '$($consumer.id)' contains duplicate component '$($component.id)'." }
        $componentIds[[string] $component.id] = $true
    }
}

$results = @()
foreach ($consumer in @($registry.consumers)) {
    $checkoutRoot = Resolve-SafeDirectory -Root $portfolioRootFull -RelativePath ([string] $consumer.checkoutDirectory) -Label 'Checkout directory'
    $consumerFindings = [System.Collections.Generic.List[string]]::new()
    $lock = $null
    $driftResults = @()
    $solutionRoot = $null

    if (-not (Test-Path -LiteralPath $checkoutRoot -PathType Container)) {
        $consumerFindings.Add('checkoutUnavailable')
    }
    else {
        $origin = Get-NormalizedOrigin -RepositoryRoot $checkoutRoot
        if ($origin -ne [string] $consumer.repository) { $consumerFindings.Add('originMismatch') }
        $status = @(& git -C $checkoutRoot status --porcelain 2>$null)
        if ($LASTEXITCODE -eq 0 -and $status.Count -gt 0) { $consumerFindings.Add('checkoutDirty') }
        foreach ($requiredFile in @($baseline.requiredRepositoryFiles)) {
            $requiredPath = Resolve-SafeDirectory -Root $checkoutRoot -RelativePath ([string] $requiredFile) -Label 'Required repository file'
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { $consumerFindings.Add("repositoryFileMissing:$requiredFile") }
        }
        $repositoryValidationWorkflow = [string] $consumer.repositoryValidationWorkflow
        $repositoryValidationWorkflowPath = Resolve-SafeDirectory -Root $checkoutRoot -RelativePath $repositoryValidationWorkflow -Label 'Repository validation workflow'
        if (-not (Test-Path -LiteralPath $repositoryValidationWorkflowPath -PathType Leaf)) {
            $consumerFindings.Add("repositoryValidationWorkflowMissing:$repositoryValidationWorkflow")
        }
        Add-WorkflowPolicyFinding -CheckoutRoot $checkoutRoot -WorkflowPolicy $baseline.workflowPolicy -Findings $consumerFindings
        $solutionRoot = Resolve-SafeDirectory -Root $checkoutRoot -RelativePath ([string] $consumer.solutionRoot) -Label 'Solution root'
        if (-not (Test-Path -LiteralPath $solutionRoot -PathType Container)) {
            $consumerFindings.Add('solutionUnavailable')
        }
        else {
            foreach ($requiredFile in @($baseline.requiredSolutionFiles)) {
                $requiredPath = Resolve-SafeDirectory -Root $solutionRoot -RelativePath ([string] $requiredFile) -Label 'Required solution file'
                if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { $consumerFindings.Add("solutionFileMissing:$requiredFile") }
            }
            foreach ($recommendedFile in @($baseline.recommendedSolutionFiles)) {
                $recommendedPath = Resolve-SafeDirectory -Root $solutionRoot -RelativePath ([string] $recommendedFile) -Label 'Recommended solution file'
                if (-not (Test-Path -LiteralPath $recommendedPath -PathType Leaf)) { $consumerFindings.Add("solutionFileRecommended:$recommendedFile") }
            }
            if ($consumer.PSObject.Properties.Name -contains 'validation') {
                $validationPath = Resolve-SafeDirectory -Root $checkoutRoot -RelativePath ([string] $consumer.validation.entryPoint) -Label 'Validation entry point'
                if (-not (Test-Path -LiteralPath $validationPath -PathType Leaf)) { $consumerFindings.Add('validationEntryPointMissing') }
            }
            elseif ($consumer.adoption -eq 'adopted') {
                $consumerFindings.Add('validationNotConfigured')
            }
            $lockPath = Join-Path $solutionRoot 'azd-components.lock.json'
            if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
                $consumerFindings.Add('lockMissing')
            }
            else {
                try {
                    $lockRaw = Get-Content -LiteralPath $lockPath -Raw
                    if (-not ($lockRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/azd-components-lock.schema.json') -ErrorAction Stop)) {
                        throw 'invalid lock'
                    }
                    $lock = $lockRaw | ConvertFrom-Json
                    if ($consumer.PSObject.Properties.Name -contains 'desiredBaseline') {
                        if (-not ($lock.PSObject.Properties.Name -contains 'baseline')) { $consumerFindings.Add('missingBaseline') }
                        elseif ([string] $lock.baseline -ne [string] $consumer.desiredBaseline) { $consumerFindings.Add('baselineMismatch') }
                    }
                    $driftResults = @(& (Join-Path $referenceRoot 'tooling/Test-AzdComponentDrift.ps1') -TargetPath $solutionRoot -PassThru -NoThrow -Quiet)
                }
                catch {
                    $consumerFindings.Add('invalidLock')
                    $lock = $null
                }
            }
        }
    }

    foreach ($desired in @($consumer.components)) {
        $state = 'current'
        $installedVersion = $null
        $findings = [System.Collections.Generic.List[string]]::new()
        foreach ($finding in $consumerFindings) { $findings.Add($finding) }
        $desiredComponentId = [string] $desired.id
        $desiredVersion = [string] $desired.desiredVersion
        $desiredRelease = Resolve-ComponentReleaseRevision -ReferenceRoot $referenceRoot -ComponentId $desiredComponentId -Version $desiredVersion
        if ($desiredRelease.state -eq 'missing') { $findings.Add("desiredReleaseTagMissing:$desiredComponentId@$desiredVersion") }
        elseif ($desiredRelease.state -eq 'invalid') { $findings.Add("desiredReleaseTagInvalid:$desiredComponentId@$desiredVersion") }

        if ('checkoutUnavailable' -in $consumerFindings -or 'solutionUnavailable' -in $consumerFindings) {
            $state = 'checkoutUnavailable'
        }
        elseif ('invalidLock' -in $consumerFindings) {
            $state = 'invalidLock'
        }
        else {
            $installed = @(if ($lock) { $lock.components | Where-Object { [string] $_.id -eq $desiredComponentId } })
            if ($installed.Count -eq 0) {
                $canonicalTargets = @(Get-CanonicalComponentTarget -ReferenceRoot $referenceRoot -ComponentId ([string] $desired.id))
                $unmanaged = @($canonicalTargets | Where-Object { Test-Path -LiteralPath (Join-Path $solutionRoot $_) -PathType Leaf })
                $state = if ($unmanaged.Count -gt 0) { 'unmanagedTargets' } else { 'notAdopted' }
            }
            elseif ($installed.Count -gt 1) {
                $state = 'invalidLock'
            }
            else {
                $installed = $installed[0]
                $installedVersion = [string] $installed.version
                $componentDrift = @($driftResults | Where-Object { [string] $_.component -eq $desiredComponentId })
                if (@($componentDrift | Where-Object state -eq 'unsafe').Count -gt 0) { $state = 'unsafe' }
                elseif (@($componentDrift | Where-Object state -eq 'missing').Count -gt 0) { $state = 'missing' }
                elseif (@($componentDrift | Where-Object state -eq 'modified').Count -gt 0) { $state = 'drifted' }
                elseif ([string] $installed.sourceRepository -ne [string] $registry.referenceRepository) { $state = 'sourceMismatch' }
                else {
                    $installedSemVer = [System.Management.Automation.SemanticVersion]::Parse($installedVersion)
                    $desiredSemVer = [System.Management.Automation.SemanticVersion]::Parse($desiredVersion)
                    $installedRelease = Resolve-ComponentReleaseRevision -ReferenceRoot $referenceRoot -ComponentId $desiredComponentId -Version $installedVersion
                    if ($installedRelease.state -eq 'missing') { $findings.Add("installedReleaseTagMissing:$desiredComponentId@$installedVersion") }
                    elseif ($installedRelease.state -eq 'invalid') { $findings.Add("installedReleaseTagInvalid:$desiredComponentId@$installedVersion") }
                    elseif ([string] $installed.sourceRevision -ne [string] $installedRelease.revision) { $findings.Add("installedSourceRevisionMismatch:$desiredComponentId@$installedVersion") }

                    if ($installedSemVer -lt $desiredSemVer) { $state = 'outdated' }
                    elseif ($installedSemVer -gt $desiredSemVer) { $state = 'versionAhead' }
                    elseif ($installedRelease.state -eq 'missing') { $state = 'installedReleaseTagMissing' }
                    elseif ($installedRelease.state -eq 'invalid') { $state = 'installedReleaseTagInvalid' }
                    elseif ([string] $installed.sourceRevision -ne [string] $installedRelease.revision) { $state = 'sourceRevisionMismatch' }
                }
            }
        }

        if ($consumer.adoption -eq 'pending' -and $state -eq 'notAdopted') { $findings.Add('pendingAdoption') }
        $results += [pscustomobject] [ordered]@{
            consumer = [string] $consumer.id
            repository = [string] $consumer.repository
            rolloutRing = [string] $consumer.rolloutRing
            component = [string] $desired.id
            desiredVersion = $desiredVersion
            installedVersion = $installedVersion
            state = $state
            findings = @($findings)
        }
    }
}

if ($AsJson) {
    $results | ConvertTo-Json -Depth 8
}
else {
    $results
}

$failureStates = 'checkoutUnavailable', 'invalidLock', 'unsafe', 'missing', 'drifted', 'unmanagedTargets', 'sourceMismatch', 'sourceRevisionMismatch', 'installedReleaseTagMissing', 'installedReleaseTagInvalid', 'outdated', 'notAdopted'
if ($FailOnFindings -and @($results | Where-Object { $_.state -in $failureStates -or @($_.findings).Count -gt 0 }).Count -gt 0) {
    throw 'The portfolio contains unavailable, unadopted, outdated, or drifted components.'
}
