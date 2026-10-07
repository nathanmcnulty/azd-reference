#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $PortfolioRoot,
    [string] $RegistryPath = (Join-Path $PSScriptRoot '../portfolio/permission-solutions.json'),
    [string[]] $BaseSolution = @(),
    [string[]] $AdditionalSolution = @(),
    [ValidateSet('discovery', 'deployment', 'runtime', 'cleanup')][string[]] $Phase = @('runtime'),
    [string[]] $Feature = @(),
    [string[]] $ExcludeFeature = @(),
    [switch] $IncludeOptional,
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$schemaPath = Join-Path $PSScriptRoot '../schemas/permission-requirements.schema.json'
$root = (Resolve-Path -LiteralPath $PortfolioRoot).Path
$registryRaw = Get-Content -LiteralPath $RegistryPath -Raw
$null = $registryRaw | Test-Json -SchemaFile (Join-Path $PSScriptRoot '../schemas/permission-solutions.schema.json') -ErrorAction Stop
$registry = $registryRaw | ConvertFrom-Json

function Get-ContainedPath {
    param([string] $Directory, [string] $RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':') -or $RelativePath -match '\\' -or
        @($RelativePath -split '/' | Where-Object { $_ -in '.', '..', '' }).Count) {
        throw "Expected a safe relative path: $RelativePath"
    }
    $cursor = $Directory
    foreach ($segment in $RelativePath -split '/') {
        $cursor = Join-Path $cursor $segment
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Permission inventory cannot follow a link: $cursor"
        }
    }
    $cursor
}

if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'PortfolioRoot cannot be a symbolic link or reparse point.'
}
$inventory = @()
$allRequirements = @()
$knownIds = @()
$knownFeatures = @()
foreach ($solution in $registry.solutions) {
    if ($solution.id -cin $knownIds) { throw "Duplicate solution ID: $($solution.id)" }
    $knownIds += $solution.id
    $path = Get-ContainedPath -Directory $root -RelativePath $solution.manifest
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $inventory += [pscustomobject]@{ solution = $solution.id; state = 'missing'; coverage = 'unknown'; gaps = @('Manifest unavailable'); findings = @($solution.manifest) }
        continue
    }
    $raw = Get-Content -LiteralPath $path -Raw
    $null = $raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop
    $manifest = $raw | ConvertFrom-Json
    if ($manifest.solutionId -cne $solution.id) { throw "Solution ID mismatch in $path" }
    if ($manifest.coverage -eq 'complete' -and $manifest.gaps.Count) { throw "Complete inventory cannot contain gaps: $path" }
    $findings = @()
    $keys = @()
    foreach ($requirement in $manifest.requirements) {
        $selection = "$($solution.id):$($requirement.feature)"
        if ($selection -cnotin $knownFeatures) { $knownFeatures += $selection }
        $key = @($requirement.resource, $requirement.kind, $requirement.permission, $requirement.scope) | ConvertTo-Json -Compress
        $entryKey = @($key, $requirement.principal, $requirement.phase, $requirement.feature) | ConvertTo-Json -Compress
        if ($entryKey -cin $keys) { throw "Duplicate requirement in $path : $entryKey" }
        $keys += $entryKey
        foreach ($source in $requirement.evidence) {
            $sourcePath = Get-ContainedPath -Directory (Split-Path $path -Parent) -RelativePath $source.path
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { $findings += "Missing evidence: $($source.path)" }
            elseif ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $source.sha256) {
                $findings += "Changed evidence: $($source.path)"
            }
        }
        if ($requirement.phase -notin $Phase -or $selection -cin $ExcludeFeature) { continue }
        if (-not ($IncludeOptional -or $requirement.defaultEnabled -or $selection -cin $Feature)) { continue }
        $allRequirements += [pscustomobject]@{
            key = $key; solution = $solution.id; resource = $requirement.resource; kind = $requirement.kind
            permission = $requirement.permission; scope = $requirement.scope; principal = $requirement.principal
            phase = $requirement.phase; feature = $requirement.feature; evidenceState = $requirement.evidenceState
        }
    }
    $inventory += [pscustomobject]@{
        solution = $solution.id; state = $manifest.status; coverage = $manifest.coverage
        reviewedOn = $manifest.reviewedOn; gaps = @($manifest.gaps); findings = @($findings | Sort-Object -Unique)
    }
}
foreach ($id in @($BaseSolution) + @($AdditionalSolution)) {
    if ($id -cnotin $knownIds) { throw "Unknown solution: $id" }
}
foreach ($selection in @($Feature) + @($ExcludeFeature)) {
    if ($selection -cnotin $knownFeatures) { throw "Unknown feature: $selection" }
}
if (@($BaseSolution | Where-Object { $_ -cin $AdditionalSolution }).Count) {
    throw 'BaseSolution and AdditionalSolution must be disjoint.'
}
$selectedIds = @($BaseSolution) + @($AdditionalSolution)
$selectedInventory = @($inventory | Where-Object { -not $selectedIds.Count -or $_.solution -cin $selectedIds })
$baseKeys = @($allRequirements | Where-Object { $_.solution -cin $BaseSolution } | Select-Object -ExpandProperty key -Unique)
$additionalKeys = @($allRequirements | Where-Object { $_.solution -cin $AdditionalSolution } | Select-Object -ExpandProperty key -Unique)
$permissions = @(
    $allRequirements | Where-Object { -not $selectedIds.Count -or $_.solution -cin $selectedIds } |
        Group-Object -Property key -CaseSensitive | ForEach-Object {
            $first = $_.Group[0]
            $relationship = if (-not $selectedIds.Count) { 'inventory' }
                elseif ($first.key -cin $baseKeys -and $first.key -cin $additionalKeys) { 'shared' }
                elseif ($first.key -cin $additionalKeys) { 'added' } else { 'existing' }
            [pscustomobject]@{
                resource = $first.resource; kind = $first.kind; permission = $first.permission; scope = $first.scope
                relationship = $relationship; solutions = @($_.Group.solution | Sort-Object -Unique)
                uses = @($_.Group | Select-Object solution, principal, phase, feature, evidenceState)
            }
        } | Sort-Object resource, kind, permission, scope
)
$result = [pscustomobject]@{
    schemaVersion = '1.0'; phase = @($Phase); baseSolutions = @($BaseSolution); additionalSolutions = @($AdditionalSolution)
    features = @($Feature); excludeFeatures = @($ExcludeFeature); includeOptional = [bool] $IncludeOptional
    comparisonComplete = (@($selectedInventory | Where-Object { $_.coverage -ne 'complete' -or $_.findings.Count }).Count -eq 0)
    inventory = @($selectedInventory); permissions = @($permissions)
    legacyCopies = @($registry.legacyCopies | Where-Object { -not $selectedIds.Count -or $_.canonicalSolution -cin $selectedIds })
    note = 'Declared requirements only; no tenant consent or effective grants inspected. Matching requirements do not authorize sharing identities. Optional and proposed entries retain their evidence state.'
}
if ($AsJson) { $result | ConvertTo-Json -Depth 20 } else { $result }
