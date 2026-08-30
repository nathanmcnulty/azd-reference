[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Head')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]+$')]
    [string] $Component,

    [Parameter(Mandatory)]
    [string] $TargetPath,

    [Parameter(ParameterSetName = 'Version')]
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$')]
    [string] $Version,

    [Parameter(ParameterSetName = 'Revision')]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string] $Revision,

    [switch] $AcceptDrift,

    [switch] $PruneRemovedFiles,

    [switch] $AllowDowngrade
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
        if ($repositoryPath -notmatch '^[^/]+/[^/]+$') {
            throw 'The GitHub origin must identify exactly one owner and repository.'
        }
        return "https://github.com/$repositoryPath"
    }
    if (-not [System.Uri]::IsWellFormedUriString($url, [System.UriKind]::Absolute)) {
        throw "The origin remote is not an absolute URI: '$url'."
    }
    $uri = [System.Uri] $url
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'The origin remote must be an HTTPS GitHub URL without credentials, query, or fragment.'
    }
    $repositoryPath = $uri.AbsolutePath.Trim('/') -replace '\.git$', ''
    if ($repositoryPath -notmatch '^[^/]+/[^/]+$') {
        throw 'The GitHub origin must identify exactly one owner and repository.'
    }
    return "https://github.com/$repositoryPath"
}

function Export-GitBlob {
    param(
        [Parameter(Mandatory)][string] $ReferenceRoot,
        [Parameter(Mandatory)][string] $Revision,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $Destination
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in '-C', $ReferenceRoot, 'cat-file', 'blob', "${Revision}:$RelativePath") {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Unable to start Git blob export.' }
        $destinationStream = [System.IO.File]::Create($Destination)
        try {
            $copyTask = $process.StandardOutput.BaseStream.CopyToAsync($destinationStream)
            $errorTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            [void] $copyTask.GetAwaiter().GetResult()
            $errorText = $errorTask.GetAwaiter().GetResult()
        }
        finally {
            $destinationStream.Dispose()
        }
        if ($process.ExitCode -ne 0) {
            throw "Unable to export committed component source '$RelativePath'. $errorText"
        }
    }
    finally {
        $process.Dispose()
    }
}

function Resolve-GitCommit {
    param(
        [Parameter(Mandatory)][string] $ReferenceRoot,
        [Parameter(Mandatory)][string] $Selector
    )

    $resolved = @(& git -C $ReferenceRoot rev-parse --verify --quiet --end-of-options "${Selector}^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or $resolved.Count -ne 1 -or [string] $resolved[0] -notmatch '^[0-9a-f]{40}$') {
        throw "Source selector does not resolve to exactly one commit: '$Selector'."
    }
    [string] $resolved[0]
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][byte[]] $Bytes)

    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-LfNormalizedContent {
    param([Parameter(Mandatory)][byte[]] $Bytes)

    $stream = [System.IO.MemoryStream]::new()
    try {
        for ($index = 0; $index -lt $Bytes.Length; $index++) {
            if ($Bytes[$index] -eq 13 -and $index + 1 -lt $Bytes.Length -and $Bytes[$index + 1] -eq 10) {
                continue
            }
            $stream.WriteByte($Bytes[$index])
        }
        $stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

function Test-ExplicitLfPolicy {
    param(
        [Parameter(Mandatory)][string] $TargetRoot,
        [Parameter(Mandatory)][string] $TargetFullPath
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    $repositoryRoot = @(& git -C $TargetRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $repositoryRoot.Count -ne 1) { return $false }
    $repositoryRoot = [System.IO.Path]::GetFullPath([string] $repositoryRoot[0])
    $relative = [System.IO.Path]::GetRelativePath($repositoryRoot, $TargetFullPath).Replace('\', '/')
    if ($relative -eq '..' -or $relative.StartsWith('../', [System.StringComparison]::Ordinal)) { return $false }

    $attributes = @(& git -C $repositoryRoot check-attr text eol -- $relative 2>$null)
    if ($LASTEXITCODE -ne 0) { return $false }
    $textValue = $null
    $eolValue = $null
    foreach ($line in $attributes) {
        if ([string] $line -match ': text: (?<value>.+)$') { $textValue = $Matches.value }
        if ([string] $line -match ': eol: (?<value>.+)$') { $eolValue = $Matches.value }
    }
    $textValue -eq 'set' -and $eolValue -eq 'lf'
}

function Test-ManagedFileHash {
    param(
        [Parameter(Mandatory)][string] $TargetRoot,
        [Parameter(Mandatory)][string] $TargetFullPath,
        [Parameter(Mandatory)][string] $ExpectedHash
    )

    $bytes = [System.IO.File]::ReadAllBytes($TargetFullPath)
    if ((Get-Sha256Hex -Bytes $bytes) -eq $ExpectedHash) { return $true }
    if (-not (Test-ExplicitLfPolicy -TargetRoot $TargetRoot -TargetFullPath $TargetFullPath)) { return $false }
    (Get-Sha256Hex -Bytes (Get-LfNormalizedContent -Bytes $bytes)) -eq $ExpectedHash
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$targetRoot = [System.IO.Path]::GetFullPath($TargetPath)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "TargetPath must be an existing directory: '$targetRoot'."
}

$sourceSelector = if ($Version) { "refs/tags/component/$Component/v$Version" } elseif ($Revision) { $Revision } else { 'HEAD' }
$sourceRevision = Resolve-GitCommit -ReferenceRoot $referenceRoot -Selector $sourceSelector
$manifestPaths = @(
    & git -C $referenceRoot ls-tree -r --name-only $sourceRevision -- components 2>$null |
        ForEach-Object { ([string] $_).Replace('\', '/') } |
        Where-Object { $_ -match '^components/(?:.*/)?component\.json$' }
)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to enumerate component manifests at '$sourceRevision'."
}
$manifestMatches = @(
    foreach ($candidatePath in $manifestPaths) {
        $candidateTemporary = [System.IO.Path]::GetTempFileName()
        try {
            Export-GitBlob -ReferenceRoot $referenceRoot -Revision $sourceRevision -RelativePath $candidatePath -Destination $candidateTemporary
            $candidateRaw = [System.IO.File]::ReadAllText($candidateTemporary)
            $candidateManifest = $candidateRaw | ConvertFrom-Json -ErrorAction Stop
            if ([string] $candidateManifest.id -eq $Component) {
                [pscustomobject]@{ Path = $candidatePath; Raw = $candidateRaw; Manifest = $candidateManifest }
            }
        }
        finally {
            if (Test-Path -LiteralPath $candidateTemporary) { [System.IO.File]::Delete($candidateTemporary) }
        }
    }
)
if ($manifestMatches.Count -ne 1) {
    throw "Expected exactly one component manifest for '$Component'; found $($manifestMatches.Count)."
}

$manifestPath = [string] $manifestMatches[0].Path
$manifestRaw = [string] $manifestMatches[0].Raw
$manifestSchema = Join-Path $referenceRoot 'schemas/component-manifest.schema.json'
if (-not ($manifestRaw | Test-Json -SchemaFile $manifestSchema -ErrorAction Stop)) {
    throw "Component '$Component' does not satisfy the component manifest schema."
}
$manifest = $manifestMatches[0].Manifest
if ([string] $manifest.manifestVersion -notin '1.0', '1.1') {
    throw "Unsupported component manifest version '$($manifest.manifestVersion)'."
}
if ($Version -and [string] $manifest.version -ne $Version) {
    throw "Component tag '$sourceSelector' contains version '$($manifest.version)', not requested version '$Version'."
}

$sourceRelativePaths = @(
    $manifestPath
    if ($manifest.PSObject.Properties.Name -contains 'changelog') { [string] $manifest.changelog }
    @($manifest.files | ForEach-Object { [string] $_.source })
)
foreach ($sourceRelativePath in $sourceRelativePaths) {
    & git -C $referenceRoot cat-file -e "${sourceRevision}:$sourceRelativePath" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Component source must be tracked by Git and present at '$sourceRevision': '$sourceRelativePath'."
    }
}
if (-not $Version -and -not $Revision) {
    $sourceStatus = @(& git -C $referenceRoot status --porcelain -- @sourceRelativePaths)
    if ($LASTEXITCODE -ne 0 -or $sourceStatus.Count -gt 0) {
        throw "Component '$Component' must be synchronized from clean, committed source."
    }
}

$plannedFiles = @()
$targetKeys = @{}
$componentSourceRoot = ([System.IO.Path]::GetDirectoryName($manifestPath).Replace('\', '/').TrimEnd('/') + '/')
foreach ($file in @($manifest.files)) {
    $sourceRelativePath = ([string] $file.source).Replace('\', '/')
    $targetRelativePath = ([string] $file.target).Replace('\', '/')
    if (-not ($sourceRelativePath.StartsWith($componentSourceRoot, [System.StringComparison]::Ordinal) -or
        $sourceRelativePath.StartsWith('schemas/', [System.StringComparison]::Ordinal))) {
        throw "Component source must be beneath its component directory or schemas/: '$sourceRelativePath'."
    }
    $targetLower = $targetRelativePath.ToLowerInvariant()
    if ($targetLower -eq 'azd-components.lock.json' -or
        $targetLower -eq '.git' -or $targetLower.StartsWith('.git/') -or
        $targetLower -eq '.azd' -or $targetLower.StartsWith('.azd/') -or
        $targetLower -eq '.github' -or $targetLower.StartsWith('.github/') -or
        $targetLower.StartsWith('.azd-reference-staging-')) {
        throw "Component target uses a reserved path: '$targetRelativePath'."
    }
    $targetFullPath = Resolve-SafeFilePath -Root $targetRoot -RelativePath $targetRelativePath -Label 'Component target'
    if (Test-Path -LiteralPath $targetFullPath -PathType Container) {
        throw "Component target must be a file, not a directory: '$targetRelativePath'."
    }
    $targetKey = $targetFullPath.ToUpperInvariant()
    if ($targetKeys.ContainsKey($targetKey)) {
        throw "Component manifest maps more than one source to '$($file.target)'."
    }
    $targetKeys[$targetKey] = $true
    $blobTemporary = [System.IO.Path]::GetTempFileName()
    try {
        Export-GitBlob -ReferenceRoot $referenceRoot -Revision $sourceRevision -RelativePath $sourceRelativePath -Destination $blobTemporary
        $blobHash = (Get-FileHash -LiteralPath $blobTemporary -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        if (Test-Path -LiteralPath $blobTemporary) { [System.IO.File]::Delete($blobTemporary) }
    }
    $plannedFiles += [pscustomobject]@{
        Source = $sourceRelativePath
        Target = $targetRelativePath
        TargetFullPath = $targetFullPath
        Sha256 = $blobHash
    }
}

$lockPath = Join-Path $targetRoot 'azd-components.lock.json'
$lock = if (Test-Path -LiteralPath $lockPath) {
    $lockRaw = Get-Content -LiteralPath $lockPath -Raw
    if (-not ($lockRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/azd-components-lock.schema.json') -ErrorAction Stop)) {
        throw 'The consumer component lock does not satisfy its schema.'
    }
    $lockRaw | ConvertFrom-Json
}
else {
    [pscustomobject]@{ manifestVersion = '1.0'; components = @() }
}
if ($lock.manifestVersion -ne '1.0') {
    throw "Unsupported consumer lock version '$($lock.manifestVersion)'."
}

$claimedTargets = @{}
$claimedComponentIds = @{}
foreach ($lockedComponent in @($lock.components)) {
    $lockedComponentId = [string] $lockedComponent.id
    if ($claimedComponentIds.ContainsKey($lockedComponentId)) {
        throw "The consumer lock contains duplicate component ID '$lockedComponentId'."
    }
    $claimedComponentIds[$lockedComponentId] = $true
    foreach ($lockedFile in @($lockedComponent.files)) {
        $lockedTarget = [string] $lockedFile.target
        $lockedTargetLower = $lockedTarget.ToLowerInvariant()
        if ($lockedTargetLower -eq 'azd-components.lock.json' -or
            $lockedTargetLower -eq '.git' -or $lockedTargetLower.StartsWith('.git/') -or
            $lockedTargetLower -eq '.azd' -or $lockedTargetLower.StartsWith('.azd/') -or
            $lockedTargetLower -eq '.github' -or $lockedTargetLower.StartsWith('.github/') -or
            $lockedTargetLower.StartsWith('.azd-reference-staging-')) {
            throw "The consumer lock contains a reserved target path: '$lockedTarget'."
        }
        $claimedKey = $lockedTargetLower
        if ($claimedTargets.ContainsKey($claimedKey)) {
            throw "The consumer lock assigns '$lockedTarget' to more than one component."
        }
        $claimedTargets[$claimedKey] = $lockedComponentId
    }
}
foreach ($planned in $plannedFiles) {
    $claimedKey = $planned.Target.ToLowerInvariant()
    if ($claimedTargets.ContainsKey($claimedKey) -and $claimedTargets[$claimedKey] -ne $Component) {
        throw "Component target '$($planned.Target)' is already owned by '$($claimedTargets[$claimedKey])'."
    }
}

$existingComponent = @($lock.components | Where-Object id -eq $Component)
if ($existingComponent.Count -gt 1) {
    throw "The consumer lock contains duplicate '$Component' entries."
}
$existingComponent = $existingComponent | Select-Object -First 1
$removedFiles = @()

if ($existingComponent) {
    $installedVersion = [System.Management.Automation.SemanticVersion]::Parse([string] $existingComponent.version)
    $selectedVersion = [System.Management.Automation.SemanticVersion]::Parse([string] $manifest.version)
    if ($selectedVersion -lt $installedVersion -and -not $AllowDowngrade) {
        throw "Component downgrade from '$installedVersion' to '$selectedVersion' requires -AllowDowngrade."
    }
    $newTargets = @($plannedFiles.Target)
    foreach ($existingFile in @($existingComponent.files)) {
        if ([string] $existingFile.target -notin $newTargets) {
            if (-not $PruneRemovedFiles) {
                throw "The new manifest no longer manages '$($existingFile.target)'. Rerun with -PruneRemovedFiles after reviewing the removal."
            }
            $removedTarget = Resolve-SafeFilePath -Root $targetRoot -RelativePath ([string] $existingFile.target) -Label 'Removed target'
            if (Test-Path -LiteralPath $removedTarget -PathType Container) {
                throw "Removed component target must be a file, not a directory: '$($existingFile.target)'."
            }
            if ((Test-Path -LiteralPath $removedTarget -PathType Leaf) -and
                -not (Test-ManagedFileHash -TargetRoot $targetRoot -TargetFullPath $removedTarget -ExpectedHash ([string] $existingFile.sha256))) {
                throw "Removed managed file is modified at '$($existingFile.target)'. Preserve or remove it manually before pruning."
            }
            $removedFiles += [pscustomobject]@{
                Target = ([string] $existingFile.target).Replace('\', '/')
                TargetFullPath = $removedTarget
            }
            continue
        }
        $existingTarget = Resolve-SafeFilePath -Root $targetRoot -RelativePath ([string] $existingFile.target) -Label 'Locked target'
        $drifted = -not (Test-Path -LiteralPath $existingTarget -PathType Leaf)
        if (-not $drifted) {
            $drifted = -not (Test-ManagedFileHash -TargetRoot $targetRoot -TargetFullPath $existingTarget -ExpectedHash ([string] $existingFile.sha256))
        }
        if ($drifted -and -not $AcceptDrift) {
            throw "Managed file drift detected at '$($existingFile.target)'. Review the difference and rerun with -AcceptDrift only if replacement is intended."
        }
    }
    if ([string] $existingComponent.version -eq [string] $manifest.version) {
        $existingTargets = @($existingComponent.files | ForEach-Object { [string] $_.target })
        if ($existingTargets.Count -ne $plannedFiles.Count -or
            @($existingTargets | Where-Object { $_ -notin @($plannedFiles.Target) }).Count -gt 0) {
            throw "Component '$Component@$($manifest.version)' has a different managed file set. Publish a new component version."
        }
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
$newComponentLock = [pscustomobject] [ordered]@{
    id = [string] $manifest.id
    version = [string] $manifest.version
    sourceRepository = $sourceRepository
    sourceRevision = $sourceRevision
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
$newLockJson = $newLock | ConvertTo-Json -Depth 20
if (-not ($newLockJson | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/azd-components-lock.schema.json') -ErrorAction Stop)) {
    throw 'The proposed consumer component lock does not satisfy its schema.'
}

$description = "Synchronize $Component@$($manifest.version) into '$targetRoot'"
if (-not $PSCmdlet.ShouldProcess($targetRoot, $description)) {
    return [pscustomobject]@{
        component = $Component
        version = [string] $manifest.version
        sourceRevision = $sourceRevision
        targets = @($plannedFiles.Target)
        removedTargets = @($removedFiles | ForEach-Object { $_.Target })
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
        Export-GitBlob -ReferenceRoot $referenceRoot -Revision $sourceRevision -RelativePath $planned.Source -Destination $staged
        $stagedHash = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($stagedHash -ne $planned.Sha256) {
            throw "Committed source hash changed while staging '$($planned.Source)'."
        }
        $planned | Add-Member -NotePropertyName StagedPath -NotePropertyValue $staged
        $index++
    }

    foreach ($removed in $removedFiles) {
        if (-not (Test-Path -LiteralPath $removed.TargetFullPath -PathType Leaf)) { continue }
        $backup = Join-Path $stagingRoot ("backup-$($applied.Count)")
        Copy-Item -LiteralPath $removed.TargetFullPath -Destination $backup
        Remove-Item -LiteralPath $removed.TargetFullPath -Force
        $applied.Add([pscustomobject]@{ Target = $removed.TargetFullPath; Backup = $backup })
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
    [System.IO.File]::WriteAllText($lockTemporary, $newLockJson + "`n", [System.Text.UTF8Encoding]::new($false))
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
    removedTargets = @($removedFiles | ForEach-Object { $_.Target })
    changed = $true
}
