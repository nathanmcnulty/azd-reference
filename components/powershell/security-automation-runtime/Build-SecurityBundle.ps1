[CmdletBinding()]
param([Parameter(Mandatory)][string[]]$SolutionRoot,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('security-package-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $solutions = @(); $ids = @{}; $runtimeRevision=$null; $provenance=@()
    foreach ($root in $SolutionRoot) {
        $root = (Resolve-Path -LiteralPath $root).Path
        & git -C $root diff --quiet HEAD -- scripts data schemas config modules queries policies remediations host.json SecurityReview azd-components.lock.json azd-permissions.json
        if ($LASTEXITCODE -ne 0) { throw 'Package sources have dirty tracked changes. Commit the reviewed source first.' }
        $revision = (& git -C $root rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $revision -notmatch '^[a-f0-9]{40}$') { throw 'Package sources require an exact Git commit.' }
        $lockPath=Join-Path $root 'azd-components.lock.json'
        $lock=Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $runtimeLocks=@($lock.components | Where-Object id -eq 'security-automation-runtime')
        if ($runtimeLocks.Count -ne 1) { throw 'Each package source requires one security runtime component lock.' }
        $runtimeLock=$runtimeLocks[0]
        if ($runtimeRevision -and $runtimeRevision -ne $runtimeLock.sourceRevision) { throw 'Mixed security runtime revisions cannot be combined.' }
        $runtimeRevision=$runtimeLock.sourceRevision
        foreach ($lockedFile in $runtimeLock.files) {
            $path=[IO.Path]::GetFullPath((Join-Path $root $lockedFile.target))
            if (-not $path.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Component target escapes its root.' }
            if ((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ne $lockedFile.sha256) { throw 'Security runtime component drift detected.' }
        }
        $invokingRuntimeHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Azd.SecurityAutomation.psm1')).Hash.ToLowerInvariant()
        $moduleLocks=@($runtimeLock.files | Where-Object target -eq 'scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1')
        if ($moduleLocks.Count -ne 1 -or $moduleLocks[0].sha256 -ne $invokingRuntimeHash) { throw 'Invoking runtime does not match the selected package lock.' }
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
        $solutions += @{ id=$id; runner="$id/scripts/Invoke-Solution.ps1"; input="$id.json" }
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
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
