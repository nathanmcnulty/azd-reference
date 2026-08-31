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

    [ValidateSet('Plan', 'Prepare')]
    [string] $Operation = 'Plan',

    [string] $RegistryPath,

    [ValidatePattern('^[a-z][a-z0-9-]+$')]
    [string] $ConsumerId,

    [string] $WorktreeRoot,

    [switch] $PruneRemovedFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SafePath {
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][string] $Label
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath) -or
        ($RelativePath -ne '.' -and ($RelativePath -split '[\\/]' | Where-Object { $_ -in '..', '.' }))) {
        throw "$Label must be a safe relative path: '$RelativePath'."
    }
    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    $candidate = if ($RelativePath -eq '.') { $fullRoot } else { [System.IO.Path]::GetFullPath((Join-Path $fullRoot $RelativePath)) }
    $rootPrefix = $fullRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ([System.OperatingSystem]::IsWindows()) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($candidate -ne $fullRoot -and -not $candidate.StartsWith($rootPrefix, $comparison)) {
        throw "$Label resolves outside its allowed root: '$RelativePath'."
    }
    if ((Get-Item -LiteralPath $fullRoot).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "$Label root cannot be a symbolic link or reparse point: '$fullRoot'."
    }
    $cursor = $fullRoot
    if ($RelativePath -ne '.') {
        foreach ($segment in $RelativePath -split '[\\/]') {
            $cursor = Join-Path $cursor $segment
            if ((Test-Path -LiteralPath $cursor) -and
                ((Get-Item -LiteralPath $cursor).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                throw "$Label cannot traverse a symbolic link or reparse point: '$cursor'."
            }
        }
    }
    $candidate
}

function Get-NormalizedOrigin {
    param([Parameter(Mandatory)][string] $RepositoryRoot)

    # Read the declared fetch URL rather than a rewritten transport URL or
    # pushurl. Publication separately binds its network operations to the exact
    # registry URL.
    $origin = @(& git -C $RepositoryRoot config --get remote.origin.url 2>$null)
    if ($LASTEXITCODE -ne 0 -or $origin.Count -ne 1) { throw "Repository has no unambiguous origin: '$RepositoryRoot'." }
    $value = ([string] $origin[0]).Trim()
    if ($value -match '^git@github\.com:(?<path>.+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.path -replace '\.git$', '')"
    }
    if ($value -match '^https://github\.com/(?<path>[^?#]+?)(?:\.git)?$') {
        return "https://github.com/$($Matches.path -replace '\.git$', '')"
    }
    $value
}

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Git failed in '$RepositoryRoot': git $($Arguments -join ' ')`n$($output -join "`n")" }
    $output
}

function Get-SafeEmptyWorktreeResidue {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $WorktreeRoot,
        [Parameter(Mandatory)][string] $WorktreePath,
        [Parameter(Mandatory)][bool] $WindowsPlatform
    )

    try {
        $comparison = if ($WindowsPlatform) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        $rootFull = [System.IO.Path]::GetFullPath($WorktreeRoot)
        $targetFull = [System.IO.Path]::GetFullPath($WorktreePath)
        if (-not $WorktreePath.Equals($targetFull, $comparison)) { return $null }
        $rootPrefix = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $targetFull.StartsWith($rootPrefix, $comparison)) { return $null }
        if (-not (Test-Path -LiteralPath $rootFull -PathType Container -ErrorAction Stop)) { return $null }

        $resolvedRoot = (Resolve-Path -LiteralPath $rootFull -ErrorAction Stop).Path
        if (-not $resolvedRoot.Equals($rootFull, $comparison)) { return $null }
        if ((Get-Item -Force -LiteralPath $resolvedRoot -ErrorAction Stop).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $null }

        # Registration must be checked freshly even when the target is already absent.
        $worktreeList = @(& git -C $RepositoryRoot worktree list --porcelain 2>&1)
        if ($LASTEXITCODE -ne 0) { return $null }
        foreach ($line in $worktreeList) {
            if ([string] $line -notmatch '^worktree (?<path>.+)$') {
                if ([string] $line -match '^worktree(?:\s|$)') { return $null }
                continue
            }
            $registeredPath = [System.IO.Path]::GetFullPath($Matches.path)
            if ($registeredPath.Equals($targetFull, $comparison)) { return $null }
        }

        if (-not (Test-Path -LiteralPath $targetFull -ErrorAction Stop)) {
            return [pscustomobject]@{ Path = $targetFull; IsAbsent = $true }
        }
        if (-not (Test-Path -LiteralPath $targetFull -PathType Container -ErrorAction Stop)) { return $null }
        $resolvedTarget = (Resolve-Path -LiteralPath $targetFull -ErrorAction Stop).Path
        if (-not $resolvedTarget.Equals($targetFull, $comparison)) { return $null }
        if ((Get-Item -Force -LiteralPath $resolvedTarget -ErrorAction Stop).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $null }
        if (@(Get-ChildItem -Force -LiteralPath $resolvedTarget -ErrorAction Stop).Count -ne 0) { return $null }
        [pscustomobject]@{ Path = $resolvedTarget; IsAbsent = $false }
    }
    catch {
        $null
    }
}

function Remove-EmptyWorktreeResidueWithRetry {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $WorktreeRoot,
        [Parameter(Mandatory)][string] $WorktreePath,
        [Parameter(Mandatory)][bool] $WindowsPlatform,
        [ValidateRange(1, 10)][int] $MaximumAttempts = 4,
        [scriptblock] $DeleteDirectory = { param($Path) [System.IO.Directory]::Delete($Path, $false) },
        [scriptblock] $Delay = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds }
    )

    if (-not $WindowsPlatform) { return $false }
    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $safeResidue = Get-SafeEmptyWorktreeResidue -RepositoryRoot $RepositoryRoot -WorktreeRoot $WorktreeRoot -WorktreePath $WorktreePath -WindowsPlatform $WindowsPlatform
            if (-not $safeResidue) { return $false }
            if ($safeResidue.IsAbsent) { return $true }
            try { & $DeleteDirectory $safeResidue.Path }
            catch {
                if ($attempt -eq $MaximumAttempts) { return $false }
            }
            if (-not (Test-Path -LiteralPath $safeResidue.Path -ErrorAction Stop)) { return $true }
            if ($attempt -lt $MaximumAttempts) { & $Delay (100 * $attempt) }
        }
        catch {
            return $false
        }
    }
    $false
}

function Remove-PreparedWorktree {
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $WorktreeRoot,
        [Parameter(Mandatory)][string] $WorktreePath,
        [bool] $WindowsPlatform = [System.OperatingSystem]::IsWindows()
    )

    try {
        Invoke-GitChecked -RepositoryRoot $RepositoryRoot -Arguments @('worktree', 'remove', $WorktreePath) | Out-Null
    }
    catch {
        $originalDiagnostic = $_.Exception.Message
        $recovered = $false
        try {
            $recovered = Remove-EmptyWorktreeResidueWithRetry `
                -RepositoryRoot $RepositoryRoot `
                -WorktreeRoot $WorktreeRoot `
                -WorktreePath $WorktreePath `
                -WindowsPlatform $WindowsPlatform
        }
        catch {
            $recovered = $false
        }
        if ($recovered) { return }
        throw "$originalDiagnostic`nWindows worktree cleanup retry was refused or exhausted."
    }
}

function Invoke-BoundedValidation {
    param(
        [Parameter(Mandatory)][string] $ValidationPath,
        [Parameter(Mandatory)][string] $WorkingDirectory,
        [Parameter(Mandatory)][int] $TimeoutMinutes
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'pwsh'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $WorkingDirectory
    foreach ($argument in '-NoProfile', '-NonInteractive', '-File', $ValidationPath) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "Unable to start consumer validation: '$ValidationPath'." }
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $timeoutMilliseconds = $TimeoutMinutes * 60000
        if (-not $process.WaitForExit($timeoutMilliseconds)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Consumer validation exceeded its $TimeoutMinutes minute timeout."
        }
        $output = @()
        $stdout = $standardOutput.GetAwaiter().GetResult()
        $stderr = $standardError.GetAwaiter().GetResult()
        if ($stdout) { $output += @($stdout -split '\r?\n' | Where-Object { $_ -ne '' }) }
        if ($stderr) { $output += @($stderr -split '\r?\n' | Where-Object { $_ -ne '' }) }
        if ($process.ExitCode -ne 0) {
            throw "Consumer validation failed with exit code $($process.ExitCode).`n$($output -join "`n")"
        }
        @($output)
    }
    finally {
        $process.Dispose()
    }
}

$referenceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$portfolioRootFull = [System.IO.Path]::GetFullPath($PortfolioRoot)
if (-not (Test-Path -LiteralPath $portfolioRootFull -PathType Container)) {
    throw "PortfolioRoot must be an existing directory: '$portfolioRootFull'."
}
if (-not $RegistryPath) { $RegistryPath = Join-Path $referenceRoot 'portfolio/consumers.json' }
$registryRaw = Get-Content -LiteralPath $RegistryPath -Raw
if (-not ($registryRaw | Test-Json -SchemaFile (Join-Path $referenceRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop)) {
    throw 'The portfolio consumer registry does not satisfy its schema.'
}
$registry = $registryRaw | ConvertFrom-Json

$tag = "component/$Component/v$Version"
$tagRevision = @(& git -C $referenceRoot rev-parse --verify --quiet --end-of-options "refs/tags/${tag}^{commit}" 2>$null)
if ($LASTEXITCODE -ne 0 -or $tagRevision.Count -ne 1 -or [string] $tagRevision[0] -notmatch '^[0-9a-f]{40}$') {
    throw "Reviewed component tag does not exist: '$tag'."
}
$tagRevision = [string] $tagRevision[0]

$selectedConsumers = @(
    foreach ($consumer in @($registry.consumers)) {
        if ($ConsumerId -and [string] $consumer.id -ne $ConsumerId) { continue }
        $desired = @($consumer.components | Where-Object { [string] $_.id -eq $Component })
        if ($desired.Count -gt 1) { throw "Consumer '$($consumer.id)' declares '$Component' more than once." }
        if ($desired.Count -eq 1) {
            if ([string] $desired[0].desiredVersion -eq $Version) {
                [pscustomobject]@{ Consumer = $consumer; Desired = $desired[0] }
            }
        }
    }
)
if ($selectedConsumers.Count -eq 0) { throw "No registered consumer approves '$Component@$Version'." }
if ($Operation -eq 'Prepare' -and -not $WorktreeRoot) { throw '-WorktreeRoot is required for Prepare.' }
if ($WorktreeRoot) {
    $worktreeRootFull = [System.IO.Path]::GetFullPath($WorktreeRoot)
    if (-not (Test-Path -LiteralPath $worktreeRootFull -PathType Container)) {
        throw "WorktreeRoot must be an existing directory: '$worktreeRootFull'."
    }
    if ((Get-Item -LiteralPath $worktreeRootFull).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "WorktreeRoot cannot be a symbolic link or reparse point: '$worktreeRootFull'."
    }
}

$results = @()
foreach ($selection in $selectedConsumers) {
    $consumer = $selection.Consumer
    $checkoutRoot = Resolve-SafePath -Root $portfolioRootFull -RelativePath ([string] $consumer.checkoutDirectory) -Label 'Checkout directory'
    if (-not (Test-Path -LiteralPath $checkoutRoot -PathType Container)) {
        throw "Consumer checkout is unavailable: '$checkoutRoot'."
    }
    if ((Get-NormalizedOrigin -RepositoryRoot $checkoutRoot) -ne [string] $consumer.repository) {
        throw "Consumer origin does not match the registry: '$($consumer.id)'."
    }
    $activeSolutionRoot = Resolve-SafePath -Root $checkoutRoot -RelativePath ([string] $consumer.solutionRoot) -Label 'Solution root'
    if (-not (Test-Path -LiteralPath $activeSolutionRoot -PathType Container)) {
        throw "Consumer solution root is unavailable: '$activeSolutionRoot'."
    }

    $branch = "codex/update-$($consumer.id)-$Component-v$Version"
    $syncParameters = @{
        Component = $Component
        Version = $Version
        TargetPath = $activeSolutionRoot
        WhatIf = $true
    }
    if ($consumer.PSObject.Properties.Name -contains 'desiredBaseline') {
        $syncParameters.Baseline = [string] $consumer.desiredBaseline
    }
    if ($PruneRemovedFiles) { $syncParameters.PruneRemovedFiles = $true }
    $plan = & (Join-Path $referenceRoot 'tooling/Sync-AzdComponent.ps1') @syncParameters
    if ($Operation -eq 'Plan') {
        $results += [pscustomobject] [ordered]@{
            consumer = [string] $consumer.id
            operation = 'Plan'
            component = $Component
            version = $Version
            sourceRevision = $tagRevision
            baseline = $plan.baseline
            branch = $branch
            targets = @($plan.targets)
            removedTargets = @($plan.removedTargets)
            state = 'planned'
        }
        continue
    }

    if (-not ($consumer.PSObject.Properties.Name -contains 'validation')) {
        throw "Consumer '$($consumer.id)' has no approved validation entry point."
    }
    & git -C $checkoutRoot show-ref --verify --quiet "refs/heads/$branch" 2>$null
    if ($LASTEXITCODE -eq 0) { throw "Local update branch already exists: '$branch'." }
    & git -C $checkoutRoot show-ref --verify --quiet "refs/remotes/origin/$branch" 2>$null
    if ($LASTEXITCODE -eq 0) { throw "Remote-tracking update branch already exists: '$branch'." }

    $worktreePath = Join-Path $worktreeRootFull ($consumer.id + '-' + $Component + '-v' + $Version.Replace('.', '-'))
    if (Test-Path -LiteralPath $worktreePath) { throw "Update worktree path already exists: '$worktreePath'." }
    if (-not $PSCmdlet.ShouldProcess($consumer.id, "Prepare isolated update branch '$branch'")) {
        $results += [pscustomobject]@{ consumer = [string] $consumer.id; operation = 'Prepare'; state = 'whatIf'; branch = $branch }
        continue
    }

    $prepared = $false
    $removePreparedBranch = $false
    try {
        Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @('worktree', 'add', '-b', $branch, $worktreePath, "origin/$($consumer.defaultBranch)") | Out-Null
        $worktreeSolution = Resolve-SafePath -Root $worktreePath -RelativePath ([string] $consumer.solutionRoot) -Label 'Worktree solution root'
        $syncParameters.TargetPath = $worktreeSolution
        $syncParameters.Remove('WhatIf')
        $syncResult = & (Join-Path $referenceRoot 'tooling/Sync-AzdComponent.ps1') @syncParameters

        $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($relative in @($syncResult.targets) + @($syncResult.removedTargets) + 'azd-components.lock.json') {
            $solutionRelative = if ([string] $consumer.solutionRoot -eq '.') { [string] $relative } else { ([string] $consumer.solutionRoot).TrimEnd('/').Replace('\', '/') + '/' + ([string] $relative).Replace('\', '/') }
            [void] $allowed.Add($solutionRelative)
        }
        $changed = @(Invoke-GitChecked -RepositoryRoot $worktreePath -Arguments @('status', '--porcelain', '--untracked-files=all') | ForEach-Object {
            if ([string] $_ -notmatch '^.. (?<path>.+)$') { throw "Unexpected Git status entry: '$_'." }
            $Matches.path.Replace('\', '/')
        })
        foreach ($changedPath in $changed) {
            if (-not $allowed.Contains($changedPath)) { throw "Update changed an unmanaged path: '$changedPath'." }
        }
        if ($changed.Count -eq 0) {
            $prepared = $true
            $removePreparedBranch = $true
            $results += [pscustomobject] [ordered]@{
                consumer = [string] $consumer.id
                operation = 'Prepare'
                component = $Component
                version = $Version
                sourceRevision = $tagRevision
                baseline = $syncResult.baseline
                branch = $null
                state = 'alreadyCurrent'
            }
            continue
        }

        $validationPath = Resolve-SafePath -Root $worktreePath -RelativePath ([string] $consumer.validation.entryPoint) -Label 'Validation entry point'
        if (-not (Test-Path -LiteralPath $validationPath -PathType Leaf)) {
            throw "Validation entry point is missing: '$validationPath'."
        }
        $validationOutput = @(Invoke-BoundedValidation -ValidationPath $validationPath -WorkingDirectory $worktreeSolution -TimeoutMinutes ([int] $consumer.validation.timeoutMinutes))

        foreach ($changedPath in $changed) {
            Invoke-GitChecked -RepositoryRoot $worktreePath -Arguments @('add', '--', $changedPath) | Out-Null
        }
        Invoke-GitChecked -RepositoryRoot $worktreePath -Arguments @('commit', '-m', "chore: update $Component to $Version") | Out-Null
        $commit = [string] (Invoke-GitChecked -RepositoryRoot $worktreePath -Arguments @('rev-parse', 'HEAD') | Select-Object -First 1)
        $prepared = $true
        $results += [pscustomobject] [ordered]@{
            consumer = [string] $consumer.id
            operation = 'Prepare'
            component = $Component
            version = $Version
            sourceRevision = $tagRevision
            baseline = $syncResult.baseline
            branch = $branch
            commit = $commit
            validationOutput = @($validationOutput | ForEach-Object { [string] $_ })
            state = 'prepared'
        }
    }
    finally {
        if ($prepared -and (Test-Path -LiteralPath $worktreePath)) {
            Remove-PreparedWorktree -RepositoryRoot $checkoutRoot -WorktreeRoot $worktreeRootFull -WorktreePath $worktreePath
        }
        if ($removePreparedBranch) {
            Invoke-GitChecked -RepositoryRoot $checkoutRoot -Arguments @('branch', '-D', '--', $branch) | Out-Null
        }
    }
}

$results
