#Requires -Version 7.0
[CmdletBinding()]
param(
    [string[]] $Paths = @('docs/backlog.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$referenceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$schemaPath = Join-Path $referenceRoot 'schemas/backlog.schema.json'
$findings = [Collections.Generic.List[string]]::new()
$backlogs = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$nodes = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($path in $Paths) {
    $fullPath = [IO.Path]::GetFullPath($path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Backlog does not exist: '$fullPath'."
    }

    $raw = Get-Content -LiteralPath $fullPath -Raw
    if (-not ($raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
        throw "Backlog does not satisfy its schema: '$fullPath'."
    }
    $backlog = $raw | ConvertFrom-Json -Depth 100
    $repository = [string] $backlog.repository
    if ($backlogs.ContainsKey($repository)) {
        $findings.Add("Duplicate repository '$repository' in '$fullPath'.")
        continue
    }

    $entry = [pscustomobject]@{ Path = $fullPath; Backlog = $backlog }
    $backlogs.Add($repository, $entry)
    $localIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($backlog.items)) {
        $itemId = [string] $item.id
        if (-not $localIds.Add($itemId)) {
            $findings.Add("Duplicate item ID '$itemId' in '$fullPath'.")
            continue
        }
        $nodeKey = "${repository}:$itemId"
        $nodes.Add($nodeKey, [pscustomobject]@{
                Key = $nodeKey
                Repository = $repository
                Item = $item
                Dependencies = [Collections.Generic.List[string]]::new()
            })

        if ([string] $item.status -eq 'blocked' -and [string]::IsNullOrWhiteSpace([string] $item.blocker)) {
            $findings.Add("Blocked item '$nodeKey' requires a blocker.")
        }
        if ([string] $item.status -ne 'blocked' -and $null -ne $item.blocker) {
            $findings.Add("Item '$nodeKey' must set blocker to null unless its status is blocked.")
        }
        if ([string] $item.status -eq 'done' -and @($item.evidence).Count -eq 0) {
            $findings.Add("Done item '$nodeKey' requires evidence.")
        }
        if ([string] $item.status -eq 'ready' -and [string] $item.authorization -ne 'local-only') {
            $findings.Add("Ready item '$nodeKey' must use local-only authorization.")
        }
        $hasClaim = $item.PSObject.Properties.Name -contains 'claim' -and $null -ne $item.claim
        if ([string] $item.status -eq 'in-progress' -and -not $hasClaim) {
            $findings.Add("In-progress item '$nodeKey' requires a claim with owner, worktree, baseRevision, and startedAt.")
        }
        if ([string] $item.status -ne 'in-progress' -and $hasClaim) {
            $findings.Add("Item '$nodeKey' must omit claim or set it to null unless its status is in-progress.")
        }
    }
}

foreach ($node in $nodes.Values) {
    foreach ($dependency in @($node.Item.dependencies)) {
        $dependencyText = [string] $dependency
        if ($dependencyText.Contains(':')) {
            $parts = $dependencyText.Split(':', 2)
            $targetRepository = $parts[0]
            $targetId = $parts[1]
            if (-not $backlogs.ContainsKey($targetRepository)) {
                $findings.Add("Cross-repository dependency '$dependencyText' for '$($node.Key)' requires that repository backlog in -Paths.")
                continue
            }
        }
        else {
            $targetRepository = $node.Repository
            $targetId = $dependencyText
        }

        $targetKey = "${targetRepository}:$targetId"
        if (-not $nodes.ContainsKey($targetKey)) {
            $findings.Add("Dependency '$dependencyText' for '$($node.Key)' does not resolve.")
            continue
        }
        $node.Dependencies.Add($targetKey)
        if ([string] $node.Item.status -in @('ready', 'in-progress', 'done') -and
            [string] $nodes[$targetKey].Item.status -ne 'done') {
            $findings.Add("Item '$($node.Key)' with status '$($node.Item.status)' depends on '$targetKey', which is not done.")
        }
    }
}

$visitState = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($key in $nodes.Keys) { $visitState[$key] = 0 }

function Test-BacklogNodeCycle {
    param(
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)] $GraphNodes,
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)] $AllFindings
    )

    if ($State[$Key] -eq 1) {
        $AllFindings.Add("Dependency cycle includes '$Key'.")
        return
    }
    if ($State[$Key] -eq 2) { return }

    $State[$Key] = 1
    foreach ($dependencyKey in $GraphNodes[$Key].Dependencies) {
        Test-BacklogNodeCycle -Key $dependencyKey -GraphNodes $GraphNodes -State $State -AllFindings $AllFindings
    }
    $State[$Key] = 2
}

foreach ($key in @($nodes.Keys)) {
    if ($visitState[$key] -eq 0) {
        Test-BacklogNodeCycle -Key $key -GraphNodes $nodes -State $visitState -AllFindings $findings
    }
}

if ($findings.Count -gt 0) {
    throw "Backlog validation failed:`n - $($findings -join "`n - ")"
}

[pscustomobject]@{
    valid = $true
    repositories = $backlogs.Count
    items = $nodes.Count
    paths = @($backlogs.Values.Path | Sort-Object)
}
