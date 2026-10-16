[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PortfolioRoot,

    [string] $RegistryPath,

    [string] $StatusPath,

    [string] $ConsumerId,

    [switch] $ExcludeOpenPullRequests,

    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepositoryPart {
    param([Parameter(Mandatory)][string] $Repository)

    if ($Repository -notmatch '^https://github\.com/(?<owner>[A-Za-z0-9_.-]+)/(?<name>[A-Za-z0-9_.-]+)$') {
        throw "Only an exact GitHub repository URL may be updated: '$Repository'."
    }
    [pscustomobject]@{
        owner = [string] $Matches.owner
        name = [string] $Matches.name
        slug = "$($Matches.owner)/$($Matches.name)"
    }
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/consumers.json' }
$registryRaw = Get-Content -LiteralPath $RegistryPath -Raw
if (-not ($registryRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop)) {
    throw 'The portfolio consumer registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json

# Resolve the explicit selector before reading or computing status.
if ($ConsumerId.Length -gt 0) {
    if ($ConsumerId -cnotmatch '\A[a-z][a-z0-9-]{1,62}[a-z0-9]\z') {
        throw "ConsumerId must be one exact registry ID: '$ConsumerId'."
    }
    $selectedConsumers = @($registry.consumers | Where-Object { $_.id -ceq $ConsumerId })
    if ($selectedConsumers.Count -ne 1) {
        throw "ConsumerId references an unknown or duplicate consumer: '$ConsumerId'."
    }
}

$status = if ($StatusPath) {
    @(Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json)
}
else {
    $statusJson = & (Join-Path $referenceRoot 'tooling/Get-AzdPortfolioStatus.ps1') `
        -PortfolioRoot $PortfolioRoot `
        -RegistryPath $RegistryPath `
        -AsJson
    @($statusJson | ConvertFrom-Json)
}

$seenCandidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$candidates = @(
    foreach ($entry in $status) {
        if ($ConsumerId.Length -gt 0 -and $entry.consumer -cne $ConsumerId) { continue }
        if ([string] $entry.state -notin @('outdated', 'notAdopted')) { continue }

        $blockingFindings = @($entry.findings | Where-Object {
                [string] $_ -ne 'pendingAdoption' -and
                [string] $_ -notlike 'solutionFileRecommended:*'
            })
        if ($blockingFindings.Count -gt 0) {
            throw "Consumer '$($entry.consumer)' is not safe to update: $($blockingFindings -join ', ')."
        }

        if ($entry.consumer -isnot [string]) { throw 'Status consumer must be a scalar string.' }
        $consumer = @($registry.consumers | Where-Object { [string] $_.id -ceq [string] $entry.consumer })
        if ($consumer.Count -ne 1) { throw "Status references an unknown or duplicate consumer: '$($entry.consumer)'." }
        $consumer = $consumer[0]
        if ($entry.component -isnot [string] -or $entry.desiredVersion -isnot [string]) {
            throw 'Status component and desiredVersion must be scalar strings.'
        }
        $component = @($consumer.components | Where-Object { $_.id -ceq $entry.component })
        if ($component.Count -ne 1 -or $component[0].desiredVersion -cne $entry.desiredVersion) {
            throw "Status component or desiredVersion does not match the registry for '$($consumer.id)'."
        }
        if (-not $seenCandidates.Add("$($consumer.id)/$($entry.component)")) {
            throw "Duplicate consumer/component candidate: '$($consumer.id)/$($entry.component)'."
        }
        $parts = Get-RepositoryPart -Repository ([string] $consumer.repository)
        $branch = "codex/update-$($consumer.id)-$($entry.component)-v$($entry.desiredVersion)"

        if ($ExcludeOpenPullRequests) {
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI is required to inspect existing pull requests.' }
            $pullRequestJson = @(& gh pr list `
                    --repo $parts.slug `
                    --state open `
                    --head $branch `
                    --json url,headRefName,baseRefName,title 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to inspect existing pull requests for '$($consumer.id)'.`n$($pullRequestJson -join "`n")"
            }
            $pullRequests = @(if ($pullRequestJson.Count -gt 0) { ($pullRequestJson -join "`n") | ConvertFrom-Json })
            $expectedTitle = "chore: update $($entry.component) to $($entry.desiredVersion)"
            $exact = @($pullRequests | Where-Object {
                    [string] $_.headRefName -ceq $branch -and
                    [string] $_.baseRefName -ceq [string] $consumer.defaultBranch -and
                    [string] $_.title -ceq $expectedTitle
                })
            if ($exact.Count -gt 0) { continue }
        }

        [pscustomobject] [ordered]@{
            consumer = [string] $consumer.id
            component = [string] $entry.component
            version = [string] $entry.desiredVersion
            repository = [string] $consumer.repository
            repositoryOwner = [string] $parts.owner
            repositoryName = [string] $parts.name
            checkoutDirectory = [string] $consumer.checkoutDirectory
            defaultBranch = [string] $consumer.defaultBranch
            branch = $branch
        }
    }
)

if ($AsJson) {
    if ($candidates.Count -eq 0) { '[]' }
    else { ConvertTo-Json -InputObject $candidates -Depth 8 -Compress }
}
else {
    $candidates
}
