[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]+$')]
    [string] $Component,

    [Parameter(Mandatory)]
    [ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$')]
    [string] $Version,

    [Parameter(Mandatory)]
    [string] $PortfolioRoot,

    [Parameter(Mandatory)]
    [string] $WorktreeRoot,

    [string] $RegistryPath,

    [switch] $PruneRemovedFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git failed in '$RepositoryRoot': git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    @($output)
}

function Get-RemoteTagRevision {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $Tag
    )

    $tagReference = "refs/tags/$Tag"
    $lines = @(Invoke-GitChecked -RepositoryRoot $RepositoryRoot -Arguments @(
            'ls-remote', 'origin', $tagReference, "$tagReference^{}"
        ))
    $references = @{}
    foreach ($line in $lines) {
        if ([string] $line -notmatch '^(?<revision>[0-9a-f]{40})\s+(?<reference>refs/tags/.+)$') {
            throw "Unexpected remote tag response: '$line'."
        }
        $references[$Matches.reference] = $Matches.revision
    }
    if ($references.ContainsKey("$tagReference^{}")) { return [string] $references["$tagReference^{}"] }
    if ($references.ContainsKey($tagReference)) { return [string] $references[$tagReference] }
    throw "Reviewed component tag is not published to origin: '$Tag'."
}

function Get-RepositorySlug {
    param([Parameter(Mandatory)][string] $Repository)

    if ($Repository -notmatch '^https://github\.com/(?<slug>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$') {
        throw "Only an exact GitHub repository URL can be published: '$Repository'."
    }
    $Matches.slug
}

function Invoke-GhChecked {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $output = @(& gh @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI failed: gh $($Arguments -join ' ')`n$($output -join "`n")" }
    @($output)
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/consumers.json' }
$registryRaw = Get-Content -LiteralPath $RegistryPath -Raw
if (-not ($registryRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop)) {
    throw 'The portfolio consumer registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json

$referenceOrigin = [string] (Invoke-GitChecked -RepositoryRoot $referenceRoot -Arguments @('remote', 'get-url', 'origin') | Select-Object -First 1)
$normalizedReferenceOrigin = $referenceOrigin.Trim() -replace '^git@github\.com:', 'https://github.com/' -replace '\.git$', ''
if ($normalizedReferenceOrigin -ne [string] $registry.referenceRepository) {
    throw 'The reference repository origin does not match the consumer registry.'
}

$tag = "component/$Component/v$Version"
$localRevision = [string] (Invoke-GitChecked -RepositoryRoot $referenceRoot -Arguments @(
        'rev-parse', '--verify', '--end-of-options', "refs/tags/${tag}^{commit}"
    ) | Select-Object -First 1)
$remoteRevision = Get-RemoteTagRevision -RepositoryRoot $referenceRoot -Tag $tag
if ($localRevision -ne $remoteRevision) {
    throw "Local and origin component tags do not resolve to the same commit: '$tag'."
}

$updateParameters = @{
    Component = $Component
    Version = $Version
    PortfolioRoot = $PortfolioRoot
    RegistryPath = $RegistryPath
}
if ($PruneRemovedFiles) { $updateParameters.PruneRemovedFiles = $true }

if (-not $PSCmdlet.ShouldProcess("$Component@$Version", 'prepare validated branches, push them without force, and open draft pull requests')) {
    $plans = @(& (Join-Path $referenceRoot 'tooling/Update-AzdPortfolio.ps1') @updateParameters)
    foreach ($plan in $plans) {
        [pscustomobject] [ordered]@{
            consumer = $plan.consumer
            operation = 'Publish'
            component = $Component
            version = $Version
            sourceRevision = $localRevision
            branch = $plan.branch
            state = 'whatIf'
        }
    }
    return
}

if (-not (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI is required to publish portfolio updates.'
}
Invoke-GhChecked -Arguments @('auth', 'status') | Out-Null

$updateParameters.Operation = 'Prepare'
$updateParameters.WorktreeRoot = $WorktreeRoot
$preparedResults = @(& (Join-Path $referenceRoot 'tooling/Update-AzdPortfolio.ps1') @updateParameters -Confirm:$false)
$publishedResults = @()
foreach ($prepared in $preparedResults) {
    if ($prepared.state -eq 'alreadyCurrent') {
        $publishedResults += [pscustomobject] [ordered]@{
            consumer = $prepared.consumer
            operation = 'Publish'
            component = $Component
            version = $Version
            sourceRevision = $localRevision
            branch = $null
            state = 'alreadyCurrent'
        }
        continue
    }
    if ($prepared.state -ne 'prepared') {
        throw "Consumer '$($prepared.consumer)' did not produce a publishable branch."
    }

    $consumer = @($registry.consumers | Where-Object { [string] $_.id -eq [string] $prepared.consumer })
    if ($consumer.Count -ne 1) { throw "Prepared consumer is not unique in the registry: '$($prepared.consumer)'." }
    $consumer = $consumer[0]
    $checkoutRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetFullPath($PortfolioRoot)) ([string] $consumer.checkoutDirectory)))
    $repositorySlug = Get-RepositorySlug -Repository ([string] $consumer.repository)
    $branchRevision = [string] (Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
            'rev-parse', '--verify', '--end-of-options', "refs/heads/$($prepared.branch)"
        ) | Select-Object -First 1)
    if ($branchRevision -ne [string] $prepared.commit) {
        throw "Prepared branch moved before publication: '$($prepared.branch)'."
    }

    $lockPath = if ([string] $consumer.solutionRoot -eq '.') {
        'azd-components.lock.json'
    }
    else {
        ([string] $consumer.solutionRoot).TrimEnd('/').Replace('\', '/') + '/azd-components.lock.json'
    }
    $lockRaw = @(Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @('show', "$($prepared.commit):$lockPath")) -join "`n"
    $lock = $lockRaw | ConvertFrom-Json
    $lockedComponent = @($lock.components | Where-Object { [string] $_.id -eq $Component })
    if ($lockedComponent.Count -ne 1 -or [string] $lockedComponent[0].sourceRevision -ne $localRevision) {
        throw "Prepared lock provenance does not match '$tag' for '$($prepared.consumer)'."
    }
    $hashEvidence = @($lockedComponent[0].files | ForEach-Object { "- ``$($_.target)``: ``$($_.sha256)``" }) -join "`n"

    Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
        'push', '--porcelain', 'origin', "refs/heads/$($prepared.branch):refs/heads/$($prepared.branch)"
    ) | Out-Null

    $body = @"
## Component update

- Component: ``$Component@$Version``
- Reviewed tag: ``$tag``
- Source revision: ``$localRevision``
- Prepared commit: ``$($prepared.commit)``
- Validation: ``$($consumer.validation.entryPoint)`` completed successfully within its $($consumer.validation.timeoutMinutes)-minute bound.

## Managed file hashes

$hashEvidence

## Rollback

After merge, revert the consumer update commit with ``git revert $($prepared.commit)``. No runtime dependency on ``azd-reference`` is introduced.
"@
    $prOutput = @(Invoke-GhChecked -Arguments @(
            'pr', 'create', '--draft', '--repo', $repositorySlug,
            '--base', ([string] $consumer.defaultBranch), '--head', ([string] $prepared.branch),
            '--title', "chore: update $Component to $Version", '--body', $body
        ))
    $pullRequestUrl = [string] ($prOutput | Where-Object { [string] $_ -match '^https://github\.com/' } | Select-Object -Last 1)
    if (-not $pullRequestUrl) { throw "GitHub CLI did not return a pull request URL for '$($prepared.consumer)'." }

    $publishedResults += [pscustomobject] [ordered]@{
        consumer = [string] $prepared.consumer
        operation = 'Publish'
        component = $Component
        version = $Version
        sourceRevision = $localRevision
        branch = [string] $prepared.branch
        commit = [string] $prepared.commit
        pullRequest = $pullRequestUrl
        state = 'published'
    }
}

$publishedResults
