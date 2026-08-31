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

    [ValidatePattern('^[a-z][a-z0-9-]+$')]
    [string] $ConsumerId,

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

function Assert-NoGitUrlRewrite {
    param([Parameter(Mandatory)][string] $RepositoryRoot)

    $output = @(& git -C $RepositoryRoot config --show-origin --get-regexp '^url\..*\.(insteadOf|pushInsteadOf)$' 2>&1)
    if ($LASTEXITCODE -notin 0, 1) {
        throw "Unable to inspect Git URL rewrite configuration in '$RepositoryRoot'.`n$($output -join "`n")"
    }
    if ($output.Count -gt 0) {
        throw "Git URL rewrite configuration is not allowed during portfolio publication.`n$($output -join "`n")"
    }
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

function Get-NormalizedRepositoryUrl {
    param([Parameter(Mandatory)][string] $Repository)

    $value = $Repository.Trim()
    if ($value -match '^git@github\.com:(?<path>.+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.path -replace '\.git$', '')"
    }
    if ($value -match '^https://github\.com/(?<path>[^?#]+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.path -replace '\.git$', '')"
    }
    $value
}

function Get-RemoteBranchRevision {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string] $Branch
    )

    $reference = "refs/heads/$Branch"
    $lines = @(Invoke-GitChecked -RepositoryRoot $RepositoryRoot -Arguments @('ls-remote', '--heads', $Repository, $reference))
    if ($lines.Count -eq 0) { return $null }
    if ($lines.Count -ne 1 -or [string] $lines[0] -notmatch "^(?<revision>[0-9a-f]{40})\s+$([regex]::Escape($reference))$") {
        throw "Unexpected remote branch response for '$reference'."
    }
    [string] $Matches.revision
}

function Resolve-ConsumerCheckout {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath
    )

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath))
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ([System.OperatingSystem]::IsWindows()) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $candidate.StartsWith($rootPrefix, $comparison)) {
        throw "Consumer checkout resolves outside the portfolio root: '$RelativePath'."
    }
    $candidate
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

if ($ConsumerId) {
    $registeredMatches = @($registry.consumers | Where-Object { [string] $_.id -ceq $ConsumerId })
    if ($registeredMatches.Count -ne 1) {
        throw "ConsumerId must identify exactly one registered consumer: '$ConsumerId'."
    }
}

Assert-NoGitUrlRewrite -RepositoryRoot $referenceRoot
$referenceOrigin = [string] (Invoke-GitChecked -RepositoryRoot $referenceRoot -Arguments @('config', '--get', 'remote.origin.url') | Select-Object -First 1)
$normalizedReferenceOrigin = Get-NormalizedRepositoryUrl -Repository $referenceOrigin
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
if ($ConsumerId) { $updateParameters.ConsumerId = $ConsumerId }

if (-not $PSCmdlet.ShouldProcess("$Component@$Version", 'prepare validated branches, create remote branches with expected-absent leases, and open draft pull requests')) {
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

$selectedConsumers = @(
    foreach ($consumer in @($registry.consumers)) {
        if ($ConsumerId -and [string] $consumer.id -cne $ConsumerId) { continue }
        $desired = @($consumer.components | Where-Object {
                [string] $_.id -eq $Component -and [string] $_.desiredVersion -eq $Version
            })
        if ($desired.Count -gt 0) { $consumer }
    }
)
if ($selectedConsumers.Count -eq 0) { throw "No registered consumer approves '$Component@$Version'." }
$publishedResults = @()
foreach ($consumer in $selectedConsumers) {
    $checkoutRoot = Resolve-ConsumerCheckout -Root $PortfolioRoot -RelativePath ([string] $consumer.checkoutDirectory)
    Assert-NoGitUrlRewrite -RepositoryRoot $checkoutRoot
    $declaredOrigin = [string] (Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
            'config', '--get', 'remote.origin.url'
        ) | Select-Object -First 1)
    if ((Get-NormalizedRepositoryUrl -Repository $declaredOrigin) -ne [string] $consumer.repository) {
        throw "Consumer origin does not match the registry: '$($consumer.id)'."
    }

    $defaultReference = "refs/heads/$($consumer.defaultBranch)"
    $trackingReference = "refs/remotes/origin/$($consumer.defaultBranch)"
    Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
        'fetch', '--no-tags', ([string] $consumer.repository), "+${defaultReference}:${trackingReference}"
    ) | Out-Null
    $liveDefaultRevision = Get-RemoteBranchRevision -RepositoryRoot $checkoutRoot -Repository ([string] $consumer.repository) -Branch ([string] $consumer.defaultBranch)
    if (-not $liveDefaultRevision) { throw "Consumer default branch is unavailable: '$($consumer.id)'." }
    $fetchedDefaultRevision = [string] (Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
            'rev-parse', '--verify', '--end-of-options', $trackingReference
        ) | Select-Object -First 1)
    if ($fetchedDefaultRevision -ne $liveDefaultRevision) {
        throw "Fetched default branch does not match the live remote: '$($consumer.id)'."
    }

    $branch = "codex/update-$($consumer.id)-$Component-v$Version"
    if (Get-RemoteBranchRevision -RepositoryRoot $checkoutRoot -Repository ([string] $consumer.repository) -Branch $branch) {
        throw "Remote update branch already exists: '$branch'."
    }

    $consumerUpdateParameters = $updateParameters.Clone()
    $consumerUpdateParameters.Operation = 'Prepare'
    $consumerUpdateParameters.WorktreeRoot = $WorktreeRoot
    $consumerUpdateParameters.ConsumerId = [string] $consumer.id
    $preparedResults = @(& (Join-Path $referenceRoot 'tooling/Update-AzdPortfolio.ps1') @consumerUpdateParameters -Confirm:$false)
    if ($preparedResults.Count -ne 1) {
        throw "Consumer '$($consumer.id)' did not produce exactly one preparation result."
    }
    $prepared = $preparedResults[0]
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

    Assert-NoGitUrlRewrite -RepositoryRoot $checkoutRoot
    Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
        'push', '--porcelain', "--force-with-lease=refs/heads/$($prepared.branch):",
        ([string] $consumer.repository), "refs/heads/$($prepared.branch):refs/heads/$($prepared.branch)"
    ) | Out-Null

    Assert-NoGitUrlRewrite -RepositoryRoot $checkoutRoot
    $publishedRevision = Get-RemoteBranchRevision -RepositoryRoot $checkoutRoot -Repository ([string] $consumer.repository) -Branch ([string] $prepared.branch)
    if ($publishedRevision -ne [string] $prepared.commit) {
        throw "Published branch does not match the prepared commit: '$($prepared.branch)'."
    }

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
