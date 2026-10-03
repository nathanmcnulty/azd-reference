[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$SolutionRoot,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('security-package-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $solutions = @(); $ids = @{}; $runtimeRevision=$null; $provenance=@()
    $requiredRuntimeTargets = @(
        'scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1'
        'scripts/vendor/Azd.SecurityAutomation/Invoke-SecurityRunbook.ps1'
        'host.json'
        'SecurityReview/function.json'
        'SecurityReview/run.ps1'
        'scripts/vendor/Azd.SecurityAutomation/Build-SecurityBundle.ps1'
        'scripts/vendor/Azd.SecurityAutomation/Publish-SecurityHost.ps1'
        'scripts/vendor/Azd.SecurityAutomation/Set-SecuritySchedule.ps1'
        'scripts/vendor/Azd.SecurityAutomation/Initialize-SecurityEnvironment.ps1'
        'scripts/vendor/Azd.SecurityAutomation/Deploy-SecuritySource.ps1'
        'scripts/vendor/Azd.SecurityAutomation/azd-components-lock.schema.json'
        'scripts/vendor/Azd.SecurityAutomation/permission-requirements.schema.json'
    )
    foreach ($root in $SolutionRoot) {
        $root = (Resolve-Path -LiteralPath $root).Path
        & git -C $root diff --quiet HEAD -- scripts data schemas config modules queries policies remediations host.json SecurityReview security-bundle.json azd-components.lock.json azd-permissions.json
        if ($LASTEXITCODE -ne 0) { throw 'Package sources have dirty tracked changes. Commit the reviewed source first.' }
        $revision = (& git -C $root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $revision -notmatch '^[a-f0-9]{40}$') { throw 'Package sources require an exact Git commit.' }
        foreach ($metadataPath in @('azd-components.lock.json','azd-permissions.json')) {
            & git -C $root ls-files --error-unmatch -- $metadataPath 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Package metadata must be tracked in the reviewed commit: $metadataPath" }
        }
        $lockPath=Join-Path $root 'azd-components.lock.json'
        $schemaPath=Join-Path $PSScriptRoot 'azd-components-lock.schema.json'
        if (-not (Test-Path -LiteralPath $schemaPath)) { $schemaPath=Join-Path $PSScriptRoot '../../../schemas/azd-components-lock.schema.json' }
        $lockJson=Get-Content -LiteralPath $lockPath -Raw
        if (-not (Test-Json -Json $lockJson -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Invalid canonical component lock.' }
        $lock=$lockJson | ConvertFrom-Json
        $runtimeLocks=@($lock.components | Where-Object id -eq 'security-automation-runtime')
        if ($runtimeLocks.Count -ne 1) { throw 'Each package source requires one security runtime component lock.' }
        $runtimeLock=$runtimeLocks[0]
        foreach ($requiredTarget in $requiredRuntimeTargets) {
            if (@($runtimeLock.files | Where-Object target -eq $requiredTarget).Count -ne 1) { throw "Security runtime lock must include $requiredTarget exactly once." }
        }
        if (@($runtimeLock.files).Count -ne $requiredRuntimeTargets.Count) { throw 'Security runtime lock must match the complete reviewed runtime target set.' }
        if ($runtimeRevision -and $runtimeRevision -ne $runtimeLock.sourceRevision) { throw 'Mixed security runtime revisions cannot be combined.' }
        $runtimeRevision=$runtimeLock.sourceRevision
        $lockedTargets=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($componentLock in $lock.components) {
            foreach ($lockedFile in $componentLock.files) {
                $normalizedTarget=$lockedFile.target.Replace('\','/')
                if (-not $lockedTargets.Add($normalizedTarget)) { throw "Component target is locked more than once: $normalizedTarget" }
                $path=[IO.Path]::GetFullPath((Join-Path $root $lockedFile.target))
                if (-not $path.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Component target escapes its root.' }
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Locked component file is missing: $normalizedTarget" }
                $cursor=$root
                foreach ($part in $normalizedTarget -split '/') {
                    $cursor=Join-Path $cursor $part
                    if ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Locked component target traverses a link: $normalizedTarget" }
                }
                if ((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ne $lockedFile.sha256) { throw "Locked component file drift detected: $normalizedTarget" }
            }
        }
        $invokingRuntimeHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1')).Hash.ToLowerInvariant()
        $moduleLocks=@($runtimeLock.files | Where-Object target -eq 'scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1')
        if ($moduleLocks.Count -ne 1 -or $moduleLocks[0].sha256 -ne $invokingRuntimeHash) { throw 'Invoking runtime does not match the selected package lock.' }
        $invokingBuilderHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
        $builderLocks=@($runtimeLock.files | Where-Object target -eq 'scripts/vendor/Azd.SecurityAutomation/Build-SecurityBundle.ps1')
        if ($builderLocks.Count -ne 1 -or $builderLocks[0].sha256 -ne $invokingBuilderHash) { throw 'Invoking bundle builder does not match the selected package lock.' }
        $id = (Get-Content -LiteralPath (Join-Path $root 'azd-permissions.json') -Raw | ConvertFrom-Json).solutionId
        if ($id -notmatch '^azd-[a-z0-9-]+$' -or $ids.ContainsKey($id)) { throw 'Invalid or duplicate solution id.' }
        $ids[$id]=$true
        $provenance+=@{solutionId=$id;sourceRevision=$revision;runtimeRevision=$runtimeRevision}
        if (-not (Test-Path -LiteralPath (Join-Path $root 'scripts/Invoke-Solution.ps1'))) { throw "No evidence runner for $id." }
        $tracked = @(& git -C $root ls-files -- scripts data schemas config modules queries policies remediations)
        if ($LASTEXITCODE -ne 0 -or $tracked.Count -eq 0) { throw 'Package sources must be tracked in Git.' }
        $approvedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $tracked) { $null=$approvedPaths.Add($entry.Replace('\','/')) }
        foreach ($directory in @('scripts','data','schemas','config','modules','queries','policies','remediations')) {
            $source = Join-Path $root $directory
            if (-not (Test-Path -LiteralPath $source)) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
                if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source links are not accepted.' }
                $relative = [IO.Path]::GetRelativePath($root,$file.FullName)
                if (-not $approvedPaths.Contains($relative.Replace('\','/'))) { continue }
                $cursor = $root
                foreach ($part in $relative -split '[\\/]') {
                    $cursor = Join-Path $cursor $part
                    if ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Package source traverses a link.' }
                }
                if ($file.Extension -notin @('.ps1','.psm1','.psd1','.json','.kql','.xml')) { continue }
                $target = Join-Path $temporary "$id/$relative"
                New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
                Copy-Item -LiteralPath $file.FullName -Destination $target
            }
        }
        $entry=@{ id=$id; runner="$id/scripts/Invoke-Solution.ps1"; input="$id.json" }
        $configurationPath=Join-Path $root 'security-bundle.json'
        if (Test-Path -LiteralPath $configurationPath) {
            & git -C $root ls-files --error-unmatch -- security-bundle.json 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Source bundle configuration must be tracked in Git.' }
            $sourceConfiguration=Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json
            $sourceEntries=@($sourceConfiguration.solutions | Where-Object id -eq $id)
            if ($sourceConfiguration.schemaVersion -ne '1.0' -or $sourceEntries.Count -ne 1) { throw 'Invalid source bundle configuration.' }
            $entry.input=$sourceEntries[0].input
            if ($sourceEntries[0].PSObject.Properties.Name -contains 'artifactFiles') { $entry.artifactFiles=@($sourceEntries[0].artifactFiles) }
        }
        $solutions += $entry
    }
    $runtime = Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1'
    $runtimeTarget = Join-Path $temporary 'scripts/vendor/Azd.SecurityAutomation'
    New-Item -ItemType Directory -Path $runtimeTarget -Force | Out-Null
    Copy-Item -LiteralPath $runtime -Destination $runtimeTarget
    foreach ($name in @('host.json','function.json','run.ps1')) {
        $source = if ($name -eq 'host.json') { Join-Path $SolutionRoot[0] $name } else { Join-Path $SolutionRoot[0] "SecurityReview/$name" }
        $target = if ($name -eq 'host.json') { Join-Path $temporary $name } else { Join-Path $temporary "SecurityReview/$name" }
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    @{schemaVersion='1.0';solutions=$solutions} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $temporary 'security-bundle.json') -Encoding utf8NoBOM
    $files = @(Get-ChildItem -LiteralPath $temporary -Recurse -File | Sort-Object FullName | ForEach-Object {
        @{path=[IO.Path]::GetRelativePath($temporary,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    @{schemaVersion='1.0';files=$files;sourceCommits=$provenance} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $temporary 'bundle-manifest.json') -Encoding utf8NoBOM
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    if (Test-Path -LiteralPath $OutputPath) { throw 'Output package already exists. Select a new path to preserve immutable packages.' }
    New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
    Compress-Archive -Path (Join-Path $temporary '*') -DestinationPath $OutputPath -CompressionLevel Optimal
    [pscustomobject]@{path=$OutputPath;sha256=(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant();solutionIds=@($ids.Keys | Sort-Object);fileCount=$files.Count}
} finally {
    $cleanupRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $cleanupPath = [IO.Path]::GetFullPath($temporary)
    if (-not $cleanupPath.StartsWith($cleanupRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($cleanupPath) -notmatch '^security-(package|bundle|run)-[a-f0-9]{32}$') { throw 'Refusing cleanup outside the task temporary directory.' }
    if (Test-Path -LiteralPath $cleanupPath) {
        if ((Get-Item -LiteralPath $cleanupPath).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing recursive cleanup of a reparse point.' }
        Remove-Item -LiteralPath $cleanupPath -Recurse -Force
    }
}
