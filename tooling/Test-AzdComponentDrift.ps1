[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $TargetPath,

    [switch] $PassThru,

    [switch] $NoThrow,

    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-ManagedFileHashMatch {
    param(
        [Parameter(Mandatory)][string] $TargetRoot,
        [Parameter(Mandatory)][string] $TargetFullPath,
        [Parameter(Mandatory)][string] $ExpectedHash
    )

    $bytes = [System.IO.File]::ReadAllBytes($TargetFullPath)
    if ((Get-Sha256Hex -Bytes $bytes) -eq $ExpectedHash) { return 'exact' }
    if (-not (Test-ExplicitLfPolicy -TargetRoot $TargetRoot -TargetFullPath $TargetFullPath)) { return $null }
    if ((Get-Sha256Hex -Bytes (Get-LfNormalizedContent -Bytes $bytes)) -eq $ExpectedHash) { return 'lf-normalized' }
    $null
}

$targetRoot = [System.IO.Path]::GetFullPath($TargetPath)
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    throw "TargetPath must be an existing directory: '$targetRoot'."
}
$lockPath = Join-Path $targetRoot 'azd-components.lock.json'
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "No azd-components.lock.json was found in '$targetRoot'."
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lockRaw = Get-Content -LiteralPath $lockPath -Raw
if (-not ($lockRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/azd-components-lock.schema.json') -ErrorAction Stop)) {
    throw 'The consumer component lock does not satisfy its schema.'
}
$lock = $lockRaw | ConvertFrom-Json
if ($lock.manifestVersion -ne '1.0') {
    throw "Unsupported consumer lock version '$($lock.manifestVersion)'."
}

$rootPrefix = $targetRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$rootItem = Get-Item -LiteralPath $targetRoot
if ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    throw "TargetPath cannot be a symbolic link or reparse point: '$targetRoot'."
}
$isWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
$comparison = if ($isWindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
$results = @()
$componentIds = @{}
$targetOwners = @{}
foreach ($component in @($lock.components)) {
    $componentId = [string] $component.id
    if ($componentIds.ContainsKey($componentId)) {
        throw "The consumer lock contains duplicate component ID '$componentId'."
    }
    $componentIds[$componentId] = $true
    foreach ($file in @($component.files)) {
        $relative = [string] $file.target
        $targetKey = $relative.ToLowerInvariant()
        if ($targetKey -eq 'azd-components.lock.json' -or
            $targetKey -eq '.git' -or $targetKey.StartsWith('.git/') -or
            $targetKey -eq '.azd' -or $targetKey.StartsWith('.azd/') -or
            $targetKey -eq '.github' -or $targetKey.StartsWith('.github/') -or
            $targetKey.StartsWith('.azd-reference-staging-')) {
            throw "The consumer lock contains a reserved target path: '$relative'."
        }
        if ($targetOwners.ContainsKey($targetKey)) {
            throw "The consumer lock assigns '$relative' to more than one component."
        }
        $targetOwners[$targetKey] = $componentId
        if ([System.IO.Path]::IsPathRooted($relative) -or ($relative -split '[\\/]' | Where-Object { $_ -eq '..' })) {
            throw "Locked target is not a safe relative path: '$relative'."
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $targetRoot $relative))
        if (-not $fullPath.StartsWith($rootPrefix, $comparison)) {
            throw "Locked target resolves outside TargetPath: '$relative'."
        }
        $unsafe = $false
        $cursor = $targetRoot
        foreach ($segment in $relative -split '[\\/]') {
            $cursor = Join-Path $cursor $segment
            if ((Test-Path -LiteralPath $cursor) -and
                ((Get-Item -LiteralPath $cursor).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                $unsafe = $true
                break
            }
        }
        $match = $null
        $state = if ($unsafe) {
            'unsafe'
        }
        elseif (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            'missing'
        }
        else {
            $match = Get-ManagedFileHashMatch -TargetRoot $targetRoot -TargetFullPath $fullPath -ExpectedHash ([string] $file.sha256)
            if ($match) { 'current' } else { 'modified' }
        }
        $results += [pscustomobject] [ordered]@{
            component = [string] $component.id
            version = [string] $component.version
            target = $relative.Replace('\', '/')
            state = $state
            match = $match
        }
    }
}

if (-not $Quiet) {
    foreach ($result in $results) {
        Write-Information ('[{0}] {1}@{2}: {3}' -f $result.state.ToUpperInvariant(), $result.component, $result.version, $result.target) -InformationAction Continue
    }
}
if ($PassThru) {
    $results
}
if (-not $NoThrow -and @($results | Where-Object state -ne 'current').Count -gt 0) {
    throw 'One or more managed component files are missing, modified, or unsafe.'
}
