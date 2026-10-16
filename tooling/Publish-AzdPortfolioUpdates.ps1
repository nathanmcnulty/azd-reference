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

    # Required for real publication; WhatIf remains a release-evidence-free plan.
    [string] $ReleaseBundlePath,

    [ValidatePattern('(?-i)^[0-9a-f]{40}\z')]
    [string] $ExpectedRevision,

    [switch] $PreparedBranchesOnly,

    [switch] $PruneRemovedFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $output = @(& git --no-replace-objects -C $RepositoryRoot @Arguments 2>&1)
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

function Assert-ComponentReleaseAcceptance {
    # The workflow read token is deliberately separate from the consumer App
    # token. Never pass either credential as an argument or retain it in output.
    $hadToken = Test-Path Env:GH_TOKEN
    $previousToken = $env:GH_TOKEN
    try {
        if ($env:AZD_RELEASE_READ_TOKEN) { $env:GH_TOKEN = $env:AZD_RELEASE_READ_TOKEN }
        & (Join-Path $referenceRoot 'tooling/Test-AzdReleaseIntegrity.ps1') `
            -AcceptComponentRelease -RepositoryRoot $referenceRoot `
            -ExpectedRepository 'nathanmcnulty/azd-reference' `
            -ExpectedTag $tag -ExpectedCommit $ExpectedRevision `
            -BundlePath $ReleaseBundlePath | Out-Null
    }
    finally {
        if ($hadToken) { $env:GH_TOKEN = $previousToken }
        else { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
    }
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/consumers.json' }
$registryRaw = Get-Content -LiteralPath $RegistryPath -Raw
if (-not ($registryRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop)) {
    throw 'The portfolio consumer registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json

$consumerIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($consumer in @($registry.consumers)) {
    $registeredConsumerId = [string] $consumer.id
    if (-not $consumerIds.Add($registeredConsumerId)) {
        throw "Portfolio registry contains a duplicate consumer ID: '$registeredConsumerId'."
    }
    $componentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($declaredComponent in @($consumer.components)) {
        $componentId = [string] $declaredComponent.id
        if (-not $componentIds.Add($componentId)) {
            throw "Consumer '$registeredConsumerId' contains a duplicate component ID: '$componentId'."
        }
    }
}

if ($ConsumerId) {
    $registeredMatches = @($registry.consumers | Where-Object { [string] $_.id -ceq $ConsumerId })
    if ($registeredMatches.Count -ne 1) {
        throw "ConsumerId must identify exactly one registered consumer: '$ConsumerId'."
    }
}

$selectedConsumers = @(
    foreach ($consumer in @($registry.consumers)) {
        if ($ConsumerId -and [string] $consumer.id -cne $ConsumerId) { continue }
        $desired = @($consumer.components | Where-Object {
                [string] $_.id -ceq $Component -and [string] $_.desiredVersion -ceq $Version
            })
        if ($desired.Count -eq 1) { $consumer }
    }
)
if ($selectedConsumers.Count -eq 0) { throw "No registered consumer approves '$Component@$Version'." }

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

if (-not $ReleaseBundlePath -or -not $ExpectedRevision) {
    throw 'Publication requires -ReleaseBundlePath and -ExpectedRevision from the reviewed release tag.'
}
if ($ExpectedRevision -cne $localRevision) {
    throw 'ExpectedRevision does not match the trusted local and origin component tag.'
}
$updateParameters.ExpectedRevision = $ExpectedRevision
Assert-ComponentReleaseAcceptance

if (-not (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI is required to publish portfolio updates.'
}
Invoke-GhChecked -Arguments @('auth', 'status') | Out-Null

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

    if ($PreparedBranchesOnly) {
        $preparedRevision = [string] (Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
                'rev-parse', '--verify', '--end-of-options', "refs/heads/$branch"
            ) | Select-Object -First 1)
        $prepared = [pscustomobject] [ordered]@{
            consumer = [string] $consumer.id
            branch = $branch
            commit = $preparedRevision
            state = 'prepared'
        }
    }
    else {
        $consumerUpdateParameters = $updateParameters.Clone()
        $consumerUpdateParameters.Operation = 'Prepare'
        $consumerUpdateParameters.WorktreeRoot = $WorktreeRoot
        $consumerUpdateParameters.ConsumerId = [string] $consumer.id
        $preparedResults = @(& (Join-Path $referenceRoot 'tooling/Update-AzdPortfolio.ps1') @consumerUpdateParameters -Confirm:$false)
        if ($preparedResults.Count -ne 1) {
            throw "Consumer '$($consumer.id)' did not produce exactly one preparation result."
        }
        $prepared = $preparedResults[0]
    }
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
    # Tree equality cannot establish history: a merge can have the same tree
    # and first parent while importing an unrelated second-parent history.
    $preparedParents = @(Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
        'show', '--no-patch', '--format=%P', '--end-of-options', $prepared.commit
    ))
    if ($preparedParents.Count -ne 1 -or [string] $preparedParents[0] -cne $liveDefaultRevision) {
        throw "Prepared commit must have exactly one parent equal to the current live default branch: '$($prepared.branch)'."
    }

    $lockPath = if ([string] $consumer.solutionRoot -eq '.') {
        'azd-components.lock.json'
    }
    else {
        ([string] $consumer.solutionRoot).TrimEnd('/').Replace('\', '/') + '/azd-components.lock.json'
    }
    $lockRaw = @(Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @('show', "$($prepared.commit):$lockPath")) -join "`n"
    if (-not ($lockRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/azd-components-lock.schema.json') -ErrorAction Stop)) {
        throw 'Prepared lock does not satisfy its schema.'
    }
    $lock = $lockRaw | ConvertFrom-Json
    $lockedComponent = @($lock.components | Where-Object { [string] $_.id -eq $Component })
    if ($lockedComponent.Count -ne 1 -or [string] $lockedComponent[0].sourceRevision -cne $ExpectedRevision -or
        [string] $lockedComponent[0].version -cne $Version -or
        [string] $lockedComponent[0].sourceRepository -cne [string] $registry.referenceRepository) {
        throw "Prepared lock provenance does not match '$tag' for '$($prepared.consumer)'."
    }
    $hashEvidence = @($lockedComponent[0].files | ForEach-Object { "- ``$($_.target)``: ``$($_.sha256)``" }) -join "`n"

    # Inspect and reproduce exact Git objects in a disposable detached worktree,
    # without running consumer code. Reuse the existing synchronization guards.
    $inspectionPath = Join-Path ([System.IO.Path]::GetTempPath()) ('azd-release-inspect-' + [guid]::NewGuid().ToString('N'))
    $hadReplaceSetting = Test-Path Env:GIT_NO_REPLACE_OBJECTS
    $previousReplaceSetting = $env:GIT_NO_REPLACE_OBJECTS
    try {
        $env:GIT_NO_REPLACE_OBJECTS = '1'
        # Inspect canonical blobs without host-default CRLF expansion. These
        # command-local settings leave the consumer's configuration unchanged;
        # its committed attributes and the exact-tree comparison still apply.
        Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
            '-c', 'core.autocrlf=false', '-c', 'core.eol=lf',
            'worktree', 'add', '--detach', $inspectionPath, $prepared.commit
        ) | Out-Null
        $inspectionSolution = if ($consumer.solutionRoot -ceq '.') { $inspectionPath } else {
            Resolve-ConsumerCheckout -Root $inspectionPath -RelativePath $consumer.solutionRoot
        }
        $inspection = & (Join-Path $referenceRoot 'tooling/Sync-AzdComponent.ps1') `
            -Component $Component -Revision $ExpectedRevision -TargetPath $inspectionSolution -WhatIf
        if ($inspection.version -cne $Version -or $inspection.sourceRevision -cne $ExpectedRevision) {
            throw 'Prepared component content does not match the accepted release.'
        }
        # Reproduce the one-component update from its exact parent using the
        # existing synchronizer. Exact tree equality also covers other lock
        # entries, baseline policy, deleted paths, and unrelated branch changes.
        Invoke-GitChecked -RepositoryRoot $inspectionPath -Arguments @(
            '-c', 'core.autocrlf=false', '-c', 'core.eol=lf', 'reset', '--hard', "$($prepared.commit)^"
        ) | Out-Null
        $replayParameters = @{
            Component = $Component
            Revision = $ExpectedRevision
            TargetPath = $inspectionSolution
            Confirm = $false
        }
        if ($consumer.PSObject.Properties.Name -contains 'desiredBaseline') {
            $replayParameters.Baseline = [string] $consumer.desiredBaseline
        }
        if ($PruneRemovedFiles) { $replayParameters.PruneRemovedFiles = $true }
        & (Join-Path $referenceRoot 'tooling/Sync-AzdComponent.ps1') @replayParameters | Out-Null
        Invoke-GitChecked -RepositoryRoot $inspectionPath -Arguments @('add', '--all') | Out-Null
        $expectedTree = [string] (Invoke-GitChecked -RepositoryRoot $inspectionPath -Arguments @('write-tree') | Select-Object -First 1)
        $preparedTree = [string] (Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @('rev-parse', '--verify', "$($prepared.commit)^{tree}") | Select-Object -First 1)
        if ($expectedTree -cne $preparedTree) {
            throw 'Prepared branch tree does not match the exact registry-approved component update.'
        }
    }
    finally {
        try {
            if (Test-Path -LiteralPath $inspectionPath) {
                Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @('worktree', 'remove', '--force', $inspectionPath) | Out-Null
            }
        }
        finally {
            if ($hadReplaceSetting) { $env:GIT_NO_REPLACE_OBJECTS = $previousReplaceSetting }
            else { Remove-Item Env:GIT_NO_REPLACE_OBJECTS -ErrorAction SilentlyContinue }
        }
    }

    # Recheck the actual bytes and signed identity immediately before writes.
    # An earlier accepted result is not authorization for this publication.
    Assert-ComponentReleaseAcceptance
    $finalBranchRevision = [string] (Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
        'rev-parse', '--verify', '--end-of-options', "refs/heads/$($prepared.branch)"
    ) | Select-Object -First 1)
    if ($finalBranchRevision -cne [string] $prepared.commit) {
        throw "Prepared branch moved during release verification: '$($prepared.branch)'."
    }
    Assert-NoGitUrlRewrite -RepositoryRoot $checkoutRoot
    Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @(
        'push', '--porcelain', "--force-with-lease=refs/heads/$($prepared.branch):",
        ([string] $consumer.repository), "$($prepared.commit):refs/heads/$($prepared.branch)"
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
