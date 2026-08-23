[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]+$')]
    [string] $Component,

    [Parameter(Mandatory)]
    [string] $TargetPath,

    [switch] $AcceptDrift
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SafeFilePath {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $Label
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        ($RelativePath -split '[\\/]' | Where-Object { $_ -eq '..' })) {
        throw "$Label must be a relative file path without parent traversal: '$RelativePath'."
    }

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
    $comparison = if ($isWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $candidate.StartsWith($rootPrefix, $comparison)) {
        throw "$Label resolves outside its allowed root: '$RelativePath'."
    }

    $cursor = $fullRoot
    if ((Get-Item -LiteralPath $cursor).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "$Label root cannot be a symbolic link or reparse point: '$fullRoot'."
    }
    foreach ($segment in $RelativePath -split '[\\/]') {
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "$Label cannot traverse a symbolic link or reparse point: '$cursor'."
            }
        }
    }
    return $candidate
}

function Get-NormalizedRepositoryUrl {
    param([Parameter(Mandatory)][string] $ReferenceRoot)

    $url = (& git -C $ReferenceRoot remote get-url origin 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $url) {
        throw 'The reference repository must have an origin remote.'
    }
    if ($url -match '^git@github\.com:(?<path>.+?)(?:\.git)?$') {
        $repositoryPath = $Matches.path -replace '\.git$', ''
        return "https://github.com/$repositoryPath"
    }
    if (-not [System.Uri]::IsWellFormedUriString($url, [System.UriKind]::Absolute)) {
        throw "The origin remote is not an absolute URI: '$url'."
    }
    return $url -replace '\.git$', ''
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$targetRoot = [System.IO.Path]::GetFullPath($TargetPath)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "TargetPath must be an existing directory: '$targetRoot'."
}

$manifestMatches = @(
    Get-ChildItem -LiteralPath (Join-Path $referenceRoot 'components') -Filter component.json -File -Recurse |
        Where-Object {
            $candidateManifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            $candidateManifest.id -eq $Component
        }
)
if ($manifestMatches.Count -ne 1) {
    throw "Expected exactly one component manifest for '$Component'; found $($manifestMatches.Count)."
}

$manifestPath = $manifestMatches[0].FullName
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.manifestVersion -ne '1.0') {
    throw "Unsupported component manifest version '$($manifest.manifestVersion)'."
}

$sourceRevision = (& git -C $referenceRoot rev-parse HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceRevision -notmatch '^[0-9a-f]{40}$') {
    throw 'The reference source must be a Git repository at a full commit revision.'
}

$sourceRelativePaths = @(
    [System.IO.Path]::GetRelativePath($referenceRoot, $manifestPath)
    @($manifest.files | ForEach-Object { [string] $_.source })
)
$sourceStatus = @(& git -C $referenceRoot status --porcelain -- @sourceRelativePaths)
if ($LASTEXITCODE -ne 0 -or $sourceStatus.Count -gt 0) {
    throw "Component '$Component' must be synchronized from clean, committed source."
}

$plannedFiles = @()
$targetKeys = @{}
foreach ($file in @($manifest.files)) {
    $sourceFullPath = Resolve-SafeFilePath -Root $referenceRoot -RelativePath ([string] $file.source) -Label 'Component source'
    $targetFullPath = Resolve-SafeFilePath -Root $targetRoot -RelativePath ([string] $file.target) -Label 'Component target'
    if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) {
        throw "Component source file does not exist: '$($file.source)'."
    }
    $targetKey = $targetFullPath.ToUpperInvariant()
    if ($targetKeys.ContainsKey($targetKey)) {
        throw "Component manifest maps more than one source to '$($file.target)'."
    }
    $targetKeys[$targetKey] = $true
    $plannedFiles += [pscustomobject]@{
        Source = ([string] $file.source).Replace('\', '/')
        SourceFullPath = $sourceFullPath
        Target = ([string] $file.target).Replace('\', '/')
        TargetFullPath = $targetFullPath
        Sha256 = (Get-FileHash -LiteralPath $sourceFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$lockPath = Join-Path $targetRoot 'azd-components.lock.json'
$lock = if (Test-Path -LiteralPath $lockPath) {
    Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
}
else {
    [pscustomobject]@{ manifestVersion = '1.0'; components = @() }
}
if ($lock.manifestVersion -ne '1.0') {
    throw "Unsupported consumer lock version '$($lock.manifestVersion)'."
}

$existingComponent = @($lock.components | Where-Object id -eq $Component)
if ($existingComponent.Count -gt 1) {
    throw "The consumer lock contains duplicate '$Component' entries."
}
$existingComponent = $existingComponent | Select-Object -First 1

if ($existingComponent) {
    $newTargets = @($plannedFiles.Target)
    foreach ($existingFile in @($existingComponent.files)) {
        if ([string] $existingFile.target -notin $newTargets) {
            throw "The new manifest no longer manages '$($existingFile.target)'. Handle component file removal explicitly before synchronizing."
        }
        $existingTarget = Resolve-SafeFilePath -Root $targetRoot -RelativePath ([string] $existingFile.target) -Label 'Locked target'
        $drifted = -not (Test-Path -LiteralPath $existingTarget -PathType Leaf)
        if (-not $drifted) {
            $actualHash = (Get-FileHash -LiteralPath $existingTarget -Algorithm SHA256).Hash.ToLowerInvariant()
            $drifted = $actualHash -ne [string] $existingFile.sha256
        }
        if ($drifted -and -not $AcceptDrift) {
            throw "Managed file drift detected at '$($existingFile.target)'. Review the difference and rerun with -AcceptDrift only if replacement is intended."
        }
    }
    if ([string] $existingComponent.version -eq [string] $manifest.version) {
        $existingHashes = @{}
        foreach ($existingFile in @($existingComponent.files)) {
            $existingHashes[[string] $existingFile.target] = [string] $existingFile.sha256
        }
        foreach ($planned in $plannedFiles) {
            if (-not $existingHashes.ContainsKey($planned.Target) -or $existingHashes[$planned.Target] -ne $planned.Sha256) {
                throw "Component '$Component@$($manifest.version)' has different managed content. Publish a new component version."
            }
        }
    }
}
else {
    foreach ($planned in $plannedFiles) {
        if ((Test-Path -LiteralPath $planned.TargetFullPath) -and -not $AcceptDrift) {
            throw "Unmanaged target already exists at '$($planned.Target)'. Review it and rerun with -AcceptDrift only if replacement is intended."
        }
    }
}

$sourceRepository = Get-NormalizedRepositoryUrl -ReferenceRoot $referenceRoot
$lockRevision = if ($existingComponent -and [string] $existingComponent.version -eq [string] $manifest.version) {
    [string] $existingComponent.sourceRevision
}
else {
    $sourceRevision
}
$newComponentLock = [pscustomobject] [ordered]@{
    id = [string] $manifest.id
    version = [string] $manifest.version
    sourceRepository = $sourceRepository
    sourceRevision = $lockRevision
    files = @($plannedFiles | ForEach-Object {
        [pscustomobject] [ordered]@{
            source = $_.Source
            target = $_.Target
            sha256 = $_.Sha256
        }
    })
}
$otherComponents = @($lock.components | Where-Object id -ne $Component)
$newLockData = [ordered]@{ manifestVersion = '1.0' }
if ($lock.PSObject.Properties.Name -contains 'baseline') {
    $newLockData.baseline = [string] $lock.baseline
}
$newLockData.components = @($otherComponents + $newComponentLock | Sort-Object id)
$newLock = [pscustomobject] $newLockData

$description = "Synchronize $Component@$($manifest.version) into '$targetRoot'"
if (-not $PSCmdlet.ShouldProcess($targetRoot, $description)) {
    return [pscustomobject]@{
        component = $Component
        version = [string] $manifest.version
        sourceRevision = $sourceRevision
        targets = @($plannedFiles.Target)
        changed = $false
    }
}

$stagingRoot = Join-Path $targetRoot ('.azd-reference-staging-{0}' -f [guid]::NewGuid().ToString('N'))
$applied = [System.Collections.Generic.List[object]]::new()
$lockBackup = $null
try {
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    if (Test-Path -LiteralPath $lockPath) {
        $lockBackup = Join-Path $stagingRoot 'azd-components.lock.backup.json'
        Copy-Item -LiteralPath $lockPath -Destination $lockBackup
    }
    $index = 0
    foreach ($planned in $plannedFiles) {
        $staged = Join-Path $stagingRoot ("source-$index")
        Copy-Item -LiteralPath $planned.SourceFullPath -Destination $staged
        $planned | Add-Member -NotePropertyName StagedPath -NotePropertyValue $staged
        $index++
    }

    foreach ($planned in $plannedFiles) {
        $targetDirectory = Split-Path -Parent $planned.TargetFullPath
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        $backup = $null
        if (Test-Path -LiteralPath $planned.TargetFullPath) {
            $backup = Join-Path $stagingRoot ("backup-$($applied.Count)")
            Copy-Item -LiteralPath $planned.TargetFullPath -Destination $backup
        }
        $temporaryTarget = Join-Path $targetDirectory ('.{0}.{1}.tmp' -f [System.IO.Path]::GetFileName($planned.TargetFullPath), [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $planned.StagedPath -Destination $temporaryTarget
        Move-Item -LiteralPath $temporaryTarget -Destination $planned.TargetFullPath -Force
        $applied.Add([pscustomobject]@{ Target = $planned.TargetFullPath; Backup = $backup })
    }

    $lockTemporary = Join-Path $stagingRoot 'azd-components.lock.new.json'
    $lockJson = $newLock | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($lockTemporary, $lockJson + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $lockTemporary -Destination $lockPath -Force
}
catch {
    for ($rollbackIndex = $applied.Count - 1; $rollbackIndex -ge 0; $rollbackIndex--) {
        $item = $applied[$rollbackIndex]
        if ($item.Backup) {
            Copy-Item -LiteralPath $item.Backup -Destination $item.Target -Force
        }
        elseif (Test-Path -LiteralPath $item.Target) {
            Remove-Item -LiteralPath $item.Target -Force
        }
    }
    if ($lockBackup) {
        Copy-Item -LiteralPath $lockBackup -Destination $lockPath -Force
    }
    elseif (Test-Path -LiteralPath $lockPath) {
        Remove-Item -LiteralPath $lockPath -Force
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

[pscustomobject]@{
    component = $Component
    version = [string] $manifest.version
    sourceRevision = $sourceRevision
    targets = @($plannedFiles.Target)
    changed = $true
}
