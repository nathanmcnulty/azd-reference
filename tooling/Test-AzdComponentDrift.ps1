[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $TargetPath,

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        $state = if ($unsafe) {
            'unsafe'
        }
        elseif (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            'missing'
        }
        else {
            $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -eq [string] $file.sha256) { 'current' } else { 'modified' }
        }
        $results += [pscustomobject] [ordered]@{
            component = [string] $component.id
            version = [string] $component.version
            target = $relative.Replace('\', '/')
            state = $state
        }
    }
}

foreach ($result in $results) {
    Write-Host ('[{0}] {1}@{2}: {3}' -f $result.state.ToUpperInvariant(), $result.component, $result.version, $result.target)
}
if ($PassThru) {
    $results
}
if (@($results | Where-Object state -ne 'current').Count -gt 0) {
    throw 'One or more managed component files are missing, modified, or unsafe.'
}
