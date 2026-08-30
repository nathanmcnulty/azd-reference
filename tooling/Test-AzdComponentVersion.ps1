[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $BaseRevision,

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath 'variable:PSNativeCommandUseErrorActionPreference') {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $output = @(& git @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Git failed with exit code $exitCode while running: git $($Arguments -join ' ')"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function ConvertTo-SafeRepositoryPath {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Description
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1f]' -or
        $Path -match '^[\\/]' -or $Path -match '^[A-Za-z]:' -or
        [System.IO.Path]::IsPathRooted($Path)) {
        throw "$Description must be a safe repository-relative path: '$Path'."
    }

    $normalized = $Path.Replace('\', '/')
    $segments = @($normalized -split '/')
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "$Description must be a safe repository-relative path: '$Path'."
    }

    $normalized
}

function Get-CurrentBlobId {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    $fullPath = Join-Path $RepositoryRoot ($RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return $null
    }

    $result = Invoke-GitCapture -Arguments @(
        '-C', $RepositoryRoot,
        'hash-object',
        "--path=$RelativePath",
        '--',
        $fullPath
    )
    if ($result.Output.Count -ne 1 -or [string] $result.Output[0] -notmatch '^[0-9a-f]+$') {
        throw "Git did not return a blob ID for '$RelativePath'."
    }

    [string] $result.Output[0]
}

function Get-BaseBlobId {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $ResolvedRevision,

        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    $objectSpec = "${ResolvedRevision}:$RelativePath"
    $result = Invoke-GitCapture -Arguments @(
        '-C', $RepositoryRoot,
        'rev-parse',
        '--verify',
        '--quiet',
        '--end-of-options',
        $objectSpec
    ) -AllowFailure
    if ($result.ExitCode -ne 0) {
        return $null
    }
    if ($result.Output.Count -ne 1 -or [string] $result.Output[0] -notmatch '^[0-9a-f]+$') {
        throw "Git did not return an object ID for '$RelativePath' at the base revision."
    }

    [string] $result.Output[0]
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is required to validate canonical component versions.'
}

$scriptParent = Split-Path $PSScriptRoot -Parent
$rootResult = Invoke-GitCapture -Arguments @('-C', $scriptParent, 'rev-parse', '--show-toplevel')
if ($rootResult.Output.Count -ne 1) {
    throw "Unable to determine the repository root from '$scriptParent'."
}
$repositoryRoot = [System.IO.Path]::GetFullPath([string] $rootResult.Output[0])

# Restrict the revision syntax before passing it to Git. The resolved commit hash is
# used for every subsequent object lookup, so manifest-provided paths cannot alter it.
if ($BaseRevision -notmatch '^[A-Za-z0-9@][A-Za-z0-9._/@~^{}+\-]*$') {
    throw "BaseRevision is not a safe Git revision: '$BaseRevision'."
}
$revisionResult = Invoke-GitCapture -Arguments @(
    '-C', $repositoryRoot,
    'rev-parse',
    '--verify',
    '--quiet',
    '--end-of-options',
    "${BaseRevision}^{commit}"
) -AllowFailure
if ($revisionResult.ExitCode -ne 0 -or $revisionResult.Output.Count -ne 1 -or
    [string] $revisionResult.Output[0] -notmatch '^[0-9a-f]+$') {
    throw "BaseRevision does not resolve to a commit in this repository: '$BaseRevision'."
}
$resolvedRevision = [string] $revisionResult.Output[0]

$manifestList = Invoke-GitCapture -Arguments @(
    '-C', $repositoryRoot,
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
    'components'
)
$manifestPaths = @(
    $manifestList.Output |
        ForEach-Object { ([string] $_).Replace('\', '/') } |
        Where-Object { $_ -match '^components/(?:.*/)?component\.json$' } |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $repositoryRoot ($_.Replace('/', [System.IO.Path]::DirectorySeparatorChar))) -PathType Leaf
        } |
        Sort-Object -Unique -CaseSensitive
)

$results = @()
$violations = @()
foreach ($manifestPathValue in $manifestPaths) {
    $manifestPath = ConvertTo-SafeRepositoryPath -Path $manifestPathValue -Description 'Component manifest path'
    $currentManifestFullPath = Join-Path $repositoryRoot ($manifestPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    try {
        $currentManifest = Get-Content -LiteralPath $currentManifestFullPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Current component manifest '$manifestPath' is not valid JSON: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace([string] $currentManifest.id) -or
        [string]::IsNullOrWhiteSpace([string] $currentManifest.version)) {
        throw "Current component manifest '$manifestPath' must define id and version."
    }

    $baseManifestBlob = Get-BaseBlobId -RepositoryRoot $repositoryRoot -ResolvedRevision $resolvedRevision -RelativePath $manifestPath
    if ($null -eq $baseManifestBlob) {
        $results += [pscustomobject] [ordered]@{
            component = [string] $currentManifest.id
            manifest = $manifestPath
            baseVersion = $null
            currentVersion = [string] $currentManifest.version
            state = 'new'
            changedPaths = @()
        }
        continue
    }

    $manifestObjectSpec = "${resolvedRevision}:$manifestPath"
    $baseManifestResult = Invoke-GitCapture -Arguments @('-C', $repositoryRoot, 'show', $manifestObjectSpec)
    try {
        $baseManifest = ($baseManifestResult.Output -join "`n") | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Base component manifest '$manifestPath' is not valid JSON: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace([string] $baseManifest.version)) {
        throw "Base component manifest '$manifestPath' must define version."
    }

    $baseVersion = [string] $baseManifest.version
    $currentVersion = [string] $currentManifest.version
    if ($baseVersion -ne $currentVersion) {
        $results += [pscustomobject] [ordered]@{
            component = [string] $currentManifest.id
            manifest = $manifestPath
            baseVersion = $baseVersion
            currentVersion = $currentVersion
            state = 'version-changed'
            changedPaths = @()
        }
        continue
    }

    $sourcePaths = @()
    foreach ($manifest in @($baseManifest, $currentManifest)) {
        if ($manifest.PSObject.Properties.Name -contains 'changelog' -and
            -not [string]::IsNullOrWhiteSpace([string] $manifest.changelog)) {
            $sourcePaths += ConvertTo-SafeRepositoryPath -Path ([string] $manifest.changelog) -Description "Component changelog in '$manifestPath'"
        }
    }
    foreach ($file in @($baseManifest.files) + @($currentManifest.files)) {
        if ($null -eq $file -or [string]::IsNullOrWhiteSpace([string] $file.source)) {
            throw "Component manifest '$manifestPath' contains a file entry without a source path."
        }
        $sourcePaths += ConvertTo-SafeRepositoryPath -Path ([string] $file.source) -Description "Managed source in '$manifestPath'"
    }
    $sourcePaths = @($sourcePaths | Sort-Object -Unique -CaseSensitive)

    $changedPaths = @()
    $currentManifestBlob = Get-CurrentBlobId -RepositoryRoot $repositoryRoot -RelativePath $manifestPath
    if ($baseManifestBlob -ne $currentManifestBlob) {
        $changedPaths += $manifestPath
    }
    foreach ($sourcePath in $sourcePaths) {
        $baseBlob = Get-BaseBlobId -RepositoryRoot $repositoryRoot -ResolvedRevision $resolvedRevision -RelativePath $sourcePath
        $currentBlob = Get-CurrentBlobId -RepositoryRoot $repositoryRoot -RelativePath $sourcePath
        if ($baseBlob -ne $currentBlob) {
            $changedPaths += $sourcePath
        }
    }

    $state = if ($changedPaths.Count -eq 0) { 'unchanged' } else { 'version-required' }
    $result = [pscustomobject] [ordered]@{
        component = [string] $currentManifest.id
        manifest = $manifestPath
        baseVersion = $baseVersion
        currentVersion = $currentVersion
        state = $state
        changedPaths = @($changedPaths)
    }
    $results += $result
    if ($state -eq 'version-required') {
        $violations += $result
    }
}

foreach ($result in $results) {
    Write-Information ('[{0}] {1}: {2} -> {3}' -f $result.state.ToUpperInvariant(), $result.component, $result.baseVersion, $result.currentVersion) -InformationAction Continue
    foreach ($changedPath in $result.changedPaths) {
        Write-Information "  changed: $changedPath" -InformationAction Continue
    }
}
if ($PassThru) {
    $results
}
if ($violations.Count -gt 0) {
    $components = @($violations | ForEach-Object { "$($_.component)@$($_.currentVersion)" }) -join ', '
    throw "Canonical component content changed without a component version change: $components. Update each component manifest version."
}
