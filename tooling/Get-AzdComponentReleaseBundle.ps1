#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ExpectedRepository,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ExpectedTag,
    [Parameter(Mandatory)][ValidatePattern('(?-i)^[0-9a-f]{40}\z')][string] $ExpectedCommit,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $DestinationPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# Acquisition is not acceptance. The caller must still pass these exact bytes to
# Test-AzdReleaseIntegrity -AcceptComponentRelease before preparing any update.
if ($ExpectedRepository -cne 'nathanmcnulty/azd-reference') {
    throw 'Component bundle acquisition requires the exact repository nathanmcnulty/azd-reference.'
}
$number = '(?:0|[1-9][0-9]*)'
$prerelease = '(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
$versionPattern = "$number\.$number\.$number(?:-$prerelease(?:\.$prerelease)*)?"
if ($ExpectedTag -cnotmatch "^component/[a-z][a-z0-9-]{1,62}[a-z0-9]/v$versionPattern\z") {
    throw 'ExpectedTag must be component/<component-id>/v<valid-semantic-version>.'
}
if ($env:GH_HOST -and $env:GH_HOST -cne 'github.com') {
    throw 'Component bundle acquisition requires GH_HOST to be unset or github.com.'
}
$destinationFull = [System.IO.Path]::GetFullPath($DestinationPath)
$destinationParent = [System.IO.Path]::GetDirectoryName($destinationFull)
if ((Test-Path -LiteralPath $destinationFull) -or
    -not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
    throw 'DestinationPath must be a new file in an existing directory.'
}
$ghPath = (Get-Command gh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

function Test-BundleInteger {
    param($Value, [long] $Minimum = 1)

    ($Value -is [int] -or $Value -is [long]) -and $Value -ge $Minimum
}

function Get-BundleApiList {
    param(
        [Parameter(Mandatory)][string] $Endpoint,
        [Parameter(Mandatory)][string] $Collection,
        [string[]] $Filters = @(),
        [switch] $WorkflowSearch
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[long]]::new()
    $total = $null
    $page = 1
    do {
        $arguments = @('api', '--hostname', 'github.com', '--method', 'GET',
            '-H', 'Accept: application/vnd.github+json', '-H', 'X-GitHub-Api-Version: 2022-11-28',
            $Endpoint, '-f', 'per_page=100', '-f', "page=$page") + $Filters
        $output = @(& $ghPath @arguments 2>$null)
        if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
            throw 'GitHub component bundle evidence is unavailable.'
        }
        try { $response = ($output -join "`n") | ConvertFrom-Json -AsHashtable -NoEnumerate -DateKind String }
        catch { throw 'GitHub component bundle evidence is malformed JSON.' }
        if ($response -isnot [System.Collections.IDictionary] -or
            -not (Test-BundleInteger -Value $response.total_count -Minimum 0) -or
            $response[$Collection] -isnot [array]) {
            throw 'GitHub component bundle evidence has an unknown list shape.'
        }
        # Filtered workflow searches are capped at 1,000 by GitHub. Even a
        # cap-sized response cannot establish that no further match exists.
        if ($WorkflowSearch -and $response.total_count -ge 1000) {
            throw 'Workflow search reached the API result cap; uniqueness cannot be established.'
        }
        if ($null -eq $total) { $total = $response.total_count }
        if ($response.total_count -ne $total -or
            $response[$Collection].Count -ne [Math]::Min(100, $total - $items.Count)) {
            throw 'GitHub component bundle pagination is incomplete or changed during acquisition.'
        }
        foreach ($item in $response[$Collection]) {
            if ($item -isnot [System.Collections.IDictionary] -or
                -not (Test-BundleInteger -Value $item.id) -or -not $ids.Add($item.id)) {
                throw 'GitHub component bundle evidence contains a missing, invalid, or duplicate ID.'
            }
            $items.Add($item)
        }
        $page++
    } while ($items.Count -lt $total)
    $items.ToArray()
}

$workflowPath = '.github/workflows/release-attestation.yml'
$runs = @(Get-BundleApiList -Endpoint "repos/$ExpectedRepository/actions/workflows/release-attestation.yml/runs" `
    -Collection 'workflow_runs' -Filters @('-f', 'event=push', '-f', "branch=$ExpectedTag", '-f', "head_sha=$ExpectedCommit", '-f', 'status=success') -WorkflowSearch)
$matchingRuns = @(
    foreach ($run in $runs) {
        foreach ($field in 'path', 'head_branch', 'head_sha', 'event', 'status', 'conclusion') {
            if ($run[$field] -isnot [string] -or [string]::IsNullOrEmpty($run[$field])) {
                throw 'Workflow run identity or completion evidence is missing or malformed.'
            }
        }
        foreach ($field in 'repository', 'head_repository') {
            if ($run[$field] -isnot [System.Collections.IDictionary] -or
                $run[$field].full_name -isnot [string] -or -not (Test-BundleInteger -Value $run[$field].id)) {
                throw 'Workflow run repository identity is missing or malformed.'
            }
        }
        if ($run.repository.full_name -cne $ExpectedRepository -or
            $run.head_repository.full_name -cne $ExpectedRepository -or
            $run.repository.id -ne $run.head_repository.id -or
            $run.head_sha -cne $ExpectedCommit -or $run.event -cne 'push' -or
            $run.status -cne 'completed' -or $run.conclusion -cne 'success') {
            throw 'Workflow run does not match the exact repository, commit, push event, and successful completion.'
        }
        if ($run.head_branch -cne $ExpectedTag) { continue }
        if ($run.path -cne $workflowPath -and $run.path -cne "$workflowPath@$ExpectedTag" -and
            $run.path -cne "$workflowPath@refs/tags/$ExpectedTag") {
            throw 'Workflow run does not match the exact release-attestation workflow path and tag.'
        }
        $run
    }
)
if ($matchingRuns.Count -ne 1) {
    throw 'Exactly one successful release-attestation push run must match the expected component tag and commit.'
}
$run = $matchingRuns[0]
$artifactName = 'azd-reference-' + $ExpectedTag.Replace('/', '-')
$artifacts = @(Get-BundleApiList -Endpoint "repos/$ExpectedRepository/actions/runs/$($run.id)/artifacts" -Collection 'artifacts')
$matchingArtifacts = @(
    foreach ($artifact in $artifacts) {
        if ($artifact.name -isnot [string] -or [string]::IsNullOrEmpty($artifact.name)) {
            throw 'Artifact name is missing or malformed.'
        }
        if ($artifact.name -ceq $artifactName) { $artifact }
    }
)
if ($matchingArtifacts.Count -ne 1) {
    throw 'Exactly one artifact must have the expected component release bundle name.'
}
$artifact = $matchingArtifacts[0]
$expiration = [DateTimeOffset]::MinValue
if ($artifact['expired'] -isnot [bool] -or $artifact['expired'] -or
    $artifact['expires_at'] -isnot [string] -or
    $artifact['expires_at'] -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
    -not [DateTimeOffset]::TryParse($artifact['expires_at'], [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None, [ref] $expiration) -or $expiration -le [DateTimeOffset]::UtcNow) {
    throw 'The exact component release artifact is expired or has unknown expiration evidence.'
}
$binding = $artifact.workflow_run
if ($binding -isnot [System.Collections.IDictionary] -or
    -not (Test-BundleInteger -Value $binding.id) -or $binding.id -ne $run.id -or
    -not (Test-BundleInteger -Value $binding.repository_id) -or $binding.repository_id -ne $run.repository.id -or
    -not (Test-BundleInteger -Value $binding.head_repository_id) -or $binding.head_repository_id -ne $run.head_repository.id -or
    $binding.head_sha -isnot [string] -or $binding.head_sha -cne $ExpectedCommit -or
    $binding.head_branch -isnot [string] -or $binding.head_branch -cne $ExpectedTag) {
    throw 'Artifact workflow_run does not bind the exact run, repository, tag, and commit.'
}

$staging = Join-Path $destinationParent ('.azd-release-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
try {
    $zipPath = Join-Path $staging 'artifact.zip'
    # PowerShell 7.6 preserves native stdout bytes with direct file redirection.
    # Never pipe this response through text cmdlets or follow a supplied URL.
    & $ghPath api --hostname github.com --method GET `
        -H 'X-GitHub-Api-Version: 2022-11-28' `
        "repos/$ExpectedRepository/actions/artifacts/$($artifact.id)/zip" > $zipPath 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'The exact component release artifact download failed.' }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $expectedEntry = "$artifactName.tar.gz"
        if ($zip.Entries.Count -ne 1 -or $zip.Entries[0].FullName -cne $expectedEntry -or
            $zip.Entries[0].Length -le 0 -or
            ($zip.Entries[0].ExternalAttributes -band 0x10) -ne 0 -or
            (($zip.Entries[0].ExternalAttributes -shr 16) -band 0xF000) -notin @(0, 0x8000)) {
            throw 'Artifact ZIP must contain only the exact regular component release tar.gz file.'
        }
        $stagedBundle = Join-Path $staging $expectedEntry
        $inputStream = $zip.Entries[0].Open()
        try {
            $outputStream = [System.IO.File]::Open($stagedBundle, [System.IO.FileMode]::CreateNew)
            try { $inputStream.CopyTo($outputStream) }
            finally { $outputStream.Dispose() }
        }
        finally { $inputStream.Dispose() }
    }
    finally { $zip.Dispose() }
    if ($expiration -le [DateTimeOffset]::UtcNow) { throw 'The component release artifact expired during acquisition.' }
    [System.IO.File]::Move($stagedBundle, $destinationFull, $false)
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}

[pscustomobject] [ordered]@{
    repository = $ExpectedRepository
    tag = $ExpectedTag
    revision = $ExpectedCommit
    bundlePath = $destinationFull
    runId = $run.id
    artifactId = $artifact.id
}
