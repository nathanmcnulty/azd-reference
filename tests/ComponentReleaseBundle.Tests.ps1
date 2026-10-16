Describe 'Exact component release bundle acquisition' {
    BeforeAll {
        $script:tool = Join-Path (Split-Path $PSScriptRoot -Parent) 'tooling/Get-AzdComponentReleaseBundle.ps1'
        $stubRoot = Join-Path $TestDrive 'native-gh-stub'
        New-Item -ItemType Directory -Path $stubRoot | Out-Null
        $stubScript = Join-Path $stubRoot 'offline-gh.ps1'
        @'
param([Parameter(ValueFromRemainingArguments)][string[]] $ArgumentList)
$ErrorActionPreference = 'Stop'
if ($env:GH_TOKEN -and $env:GH_TOKEN -cne 'offline-fixture-not-a-credential') { exit 90 }
$root = $env:AZD_BUNDLE_FIXTURE
[IO.File]::AppendAllText((Join-Path $root 'calls.jsonl'), (ConvertTo-Json -InputObject $ArgumentList -Compress) + "`n")
if ($ArgumentList[0] -cne 'api' -or $ArgumentList[1] -cne '--hostname' -or
    $ArgumentList[2] -cne 'github.com' -or $ArgumentList[3] -cne '--method' -or $ArgumentList[4] -cne 'GET') { exit 91 }
$endpoint = @($ArgumentList | Where-Object { $_ -clike 'repos/*' })
if ($endpoint.Count -ne 1) { exit 92 }
$page = @($ArgumentList | Where-Object { $_ -cmatch '^page=\d+$' })
if (Test-Path (Join-Path $root 'api-failure')) { exit 93 }
if ($endpoint[0] -ceq 'repos/nathanmcnulty/azd-reference/actions/workflows/release-attestation.yml/runs') {
    if ($page.Count -ne 1) { exit 94 }
    $file = Join-Path $root ('runs-' + $page[0].Substring(5) + '.json')
}
elseif ($endpoint[0] -ceq 'repos/nathanmcnulty/azd-reference/actions/runs/101/artifacts') {
    if ($page.Count -ne 1) { exit 95 }
    $file = Join-Path $root ('artifacts-' + $page[0].Substring(5) + '.json')
}
elseif ($endpoint[0] -ceq 'repos/nathanmcnulty/azd-reference/actions/artifacts/201/zip') {
    if (Test-Path (Join-Path $root 'download-failure')) { exit 96 }
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root 'artifact.zip'))
    $stream = [Console]::OpenStandardOutput()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
    exit 0
}
else { exit 97 }
if (-not (Test-Path -LiteralPath $file)) { exit 98 }
[Console]::Write([IO.File]::ReadAllText($file))
exit 0
'@ | Set-Content -LiteralPath $stubScript -Encoding utf8NoBOM
        $pwsh = (Get-Process -Id $PID).Path
        if ($IsWindows) {
            ('@"{0}" -NoLogo -NoProfile -File "{1}" %*' -f $pwsh, $stubScript) |
                Set-Content -LiteralPath (Join-Path $stubRoot 'gh.cmd') -Encoding ascii
        }
        else {
            $quotedPwsh = "'" + $pwsh.Replace("'", "'\''") + "'"
            $quotedScript = "'" + $stubScript.Replace("'", "'\''") + "'"
            "#!/bin/sh`nexec $quotedPwsh -NoLogo -NoProfile -File $quotedScript `"`$@`"" |
                Set-Content -LiteralPath (Join-Path $stubRoot 'gh') -Encoding utf8NoBOM
            & chmod +x (Join-Path $stubRoot 'gh')
            if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the offline gh executable.' }
        }
        $originalPath = $env:PATH
        $originalToken = $env:GH_TOKEN
        $originalHost = $env:GH_HOST
        $originalFixture = $env:AZD_BUNDLE_FIXTURE
        $env:PATH = $stubRoot + [IO.Path]::PathSeparator + $originalPath
        $env:GH_TOKEN = 'offline-fixture-not-a-credential'
        $env:GH_HOST = 'github.com'

        function Write-BundleFixturePage {
            param([string] $Kind, [object[]] $Items, [int] $Total = $Items.Count, [int] $Page = 1)

            $property = if ($Kind -eq 'runs') { 'workflow_runs' } else { 'artifacts' }
            $response = @{ total_count = $Total; $property = @($Items | Where-Object { $null -ne $_ }) }
            ConvertTo-Json -InputObject $response -Depth 20 |
                Set-Content -LiteralPath (Join-Path $fixture "$Kind-$Page.json") -Encoding utf8NoBOM
        }

        function Write-BundleFixtureZip {
            param([string[]] $Names = @($entryName), [int] $ExternalAttributes = 0, [switch] $Empty)

            $path = Join-Path $fixture 'artifact.zip'
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
            $archive = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Names) {
                    $entry = $archive.CreateEntry($name)
                    $entry.ExternalAttributes = $ExternalAttributes
                    $stream = $entry.Open()
                    try { if (-not $Empty) { $stream.Write($bundleBytes, 0, $bundleBytes.Length) } }
                    finally { $stream.Dispose() }
                }
            }
            finally { $archive.Dispose() }
        }

        function Get-BundleFixtureCalls {
            $path = Join-Path $fixture 'calls.jsonl'
            if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path | ForEach-Object { ,($_ | ConvertFrom-Json) } }
        }
    }

    BeforeEach {
        $fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixture | Out-Null
        $env:AZD_BUNDLE_FIXTURE = $fixture
        $env:GH_TOKEN = 'offline-fixture-not-a-credential'
        $env:GH_HOST = 'github.com'
        $acquire = @{
            ExpectedRepository = 'nathanmcnulty/azd-reference'
            ExpectedTag = 'component/example-component/v1.2.3'
            ExpectedCommit = 'a' * 40
            DestinationPath = Join-Path $fixture 'received.tar.gz'
        }
        $artifactName = 'azd-reference-component-example-component-v1.2.3'
        $entryName = "$artifactName.tar.gz"
        # Deliberately includes NUL, invalid UTF-8, and newline bytes. A text
        # pipeline corrupting the native download must fail the success test.
        $bundleBytes = [byte[]] @(31, 139, 8, 0, 255, 254, 128, 10, 13, 0, 42)
        $run = @{
            id = 101
            path = '.github/workflows/release-attestation.yml'
            head_branch = $acquire.ExpectedTag
            head_sha = $acquire.ExpectedCommit
            event = 'push'; status = 'completed'; conclusion = 'success'
            repository = @{ id = 301; full_name = $acquire.ExpectedRepository }
            head_repository = @{ id = 301; full_name = $acquire.ExpectedRepository }
        }
        $artifact = @{
            id = 201; name = $artifactName; expired = $false
            expires_at = [DateTimeOffset]::UtcNow.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            workflow_run = @{
                id = 101; repository_id = 301; head_repository_id = 301
                head_branch = $acquire.ExpectedTag; head_sha = $acquire.ExpectedCommit
            }
        }
        Write-BundleFixturePage -Kind runs -Items @($run)
        Write-BundleFixturePage -Kind artifacts -Items @($artifact)
        Write-BundleFixtureZip
    }

    AfterAll {
        $env:PATH = $originalPath
        $env:GH_TOKEN = $originalToken
        $env:GH_HOST = $originalHost
        $env:AZD_BUNDLE_FIXTURE = $originalFixture
    }

    It 'downloads the exact artifact ID and preserves the original binary bundle bytes' {
        $result = @(& $script:tool @acquire)
        $result.Count | Should -Be 1
        $result[0].repository | Should -BeExactly $acquire.ExpectedRepository
        $result[0].tag | Should -BeExactly $acquire.ExpectedTag
        $result[0].revision | Should -BeExactly $acquire.ExpectedCommit
        $result[0].bundlePath | Should -BeExactly $acquire.DestinationPath
        $result[0].runId | Should -Be 101
        $result[0].artifactId | Should -Be 201
        [Convert]::ToHexString([IO.File]::ReadAllBytes($acquire.DestinationPath)) |
            Should -BeExactly ([Convert]::ToHexString($bundleBytes))
        $calls = @(Get-BundleFixtureCalls)
        $calls.Count | Should -Be 3
        $calls[0] | Should -Contain 'head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $calls[0] | Should -Contain 'branch=component/example-component/v1.2.3'
        $calls[0] | Should -Contain 'event=push'
        $calls[0] | Should -Contain 'status=success'
        $calls[2][-1] | Should -BeExactly 'repos/nathanmcnulty/azd-reference/actions/artifacts/201/zip'
        ($calls | ConvertTo-Json -Depth 5) | Should -Not -Match 'offline-fixture-not-a-credential'
        @(Get-ChildItem -LiteralPath $fixture -Directory -Filter '.azd-release-*').Count | Should -Be 0
    }

    It 'accepts only exact workflow path suffixes <_>' -ForEach @('', '@component/example-component/v1.2.3', '@refs/tags/component/example-component/v1.2.3') {
        $run.path += $_
        Write-BundleFixturePage -Kind runs -Items @($run)
        { & $script:tool @acquire } | Should -Not -Throw
    }

    It 'rejects invalid expected identity <Field> before GitHub access' -ForEach @(
        @{ Field = 'ExpectedRepository'; Value = 'other/azd-reference' },
        @{ Field = 'ExpectedRepository'; Value = 'NathanMcNulty/azd-reference' },
        @{ Field = 'ExpectedTag'; Value = 'component/example-component/v01.2.3' },
        @{ Field = 'ExpectedTag'; Value = 'component/example-component/v1.2.3-01' },
        @{ Field = 'ExpectedTag'; Value = 'component/../v1.2.3' },
        @{ Field = 'ExpectedTag'; Value = "component/example-component/v1.2.3`n" },
        @{ Field = 'ExpectedCommit'; Value = ('A' * 40) },
        @{ Field = 'ExpectedCommit'; Value = 'HEAD' }
    ) {
        $acquire[$Field] = $Value
        { & $script:tool @acquire } | Should -Throw
        @(Get-BundleFixtureCalls).Count | Should -Be 0
    }

    It 'allows the existing local gh authentication without supplying credential arguments' {
        $env:GH_TOKEN = $null
        (& $script:tool @acquire).artifactId | Should -Be 201
        $calls = @(Get-BundleFixtureCalls)
        $calls.Count | Should -Be 3
        ($calls | ConvertTo-Json -Depth 5) | Should -Not -Match '(?i)token|authorization|credential'
        $env:GH_TOKEN | Should -BeNullOrEmpty
    }

    It 'requires the exact GitHub host before API access' {
        $env:GH_HOST = 'github.example.invalid'
        { & $script:tool @acquire } | Should -Throw
        @(Get-BundleFixtureCalls).Count | Should -Be 0
    }

    It 'refuses an existing destination or nonexistent parent without overwriting anything' -ForEach @('file', 'directory', 'parent') {
        if ($_ -eq 'file') { 'keep' | Set-Content -LiteralPath $acquire.DestinationPath }
        elseif ($_ -eq 'directory') { New-Item -ItemType Directory -Path $acquire.DestinationPath | Out-Null }
        else { $acquire.DestinationPath = Join-Path $fixture 'missing/bundle.tar.gz' }
        { & $script:tool @acquire } | Should -Throw '*new file*'
        @(Get-BundleFixtureCalls).Count | Should -Be 0
        if ($_ -eq 'file') { (Get-Content -LiteralPath $acquire.DestinationPath -Raw).Trim() | Should -BeExactly 'keep' }
    }

    It 'rejects wrong or missing run evidence <Field>' -ForEach @(
        @{ Field = 'id'; Value = '101' },
        @{ Field = 'path'; Value = '.github/workflows/other.yml' },
        @{ Field = 'path'; Value = '.github/workflows/release-attestation.yml@refs/heads/main' },
        @{ Field = 'head_branch'; Value = 'main' },
        @{ Field = 'head_sha'; Value = ('b' * 40) },
        @{ Field = 'event'; Value = 'workflow_dispatch' },
        @{ Field = 'status'; Value = 'in_progress' },
        @{ Field = 'conclusion'; Value = 'failure' },
        @{ Field = 'conclusion'; Value = $null },
        @{ Field = 'repository'; Value = @{ id = 301; full_name = 'other/azd-reference' } },
        @{ Field = 'head_repository'; Value = @{ id = 301; full_name = 'other/azd-reference' } },
        @{ Field = 'head_repository'; Value = @{ id = 302; full_name = 'nathanmcnulty/azd-reference' } },
        @{ Field = 'head_repository'; Value = $null }
    ) {
        $run[$Field] = $Value
        Write-BundleFixturePage -Kind runs -Items @($run)
        { & $script:tool @acquire } | Should -Throw
        Test-Path -LiteralPath $acquire.DestinationPath | Should -BeFalse
        @(Get-BundleFixtureCalls).Count | Should -Be 1
    }

    It 'rejects missing or ambiguous successful runs' -ForEach @('missing', 'ambiguous') {
        $other = $run.Clone(); $other.id = 102
        $items = if ($_ -eq 'missing') { @() } else { @($run, $other) }
        Write-BundleFixturePage -Kind runs -Items $items
        { & $script:tool @acquire } | Should -Throw '*Exactly one successful*'
        @(Get-BundleFixtureCalls).Count | Should -Be 1
    }

    It 'fully enumerates runs and artifacts before choosing an exact match' {
        $otherRuns = @(foreach ($id in 1..100) { $other = $run.Clone(); $other.id = 1000 + $id; $other.head_branch = 'another-tag'; $other })
        Write-BundleFixturePage -Kind runs -Items $otherRuns -Total 101
        Write-BundleFixturePage -Kind runs -Items @($run) -Total 101 -Page 2
        $otherArtifacts = @(foreach ($id in 1..100) { @{ id = 2000 + $id; name = "other-$id" } })
        Write-BundleFixturePage -Kind artifacts -Items $otherArtifacts -Total 101
        Write-BundleFixturePage -Kind artifacts -Items @($artifact) -Total 101 -Page 2
        (& $script:tool @acquire).artifactId | Should -Be 201
        @(Get-BundleFixtureCalls).Count | Should -Be 5
    }

    It 'finds ambiguity on later pages of <_>' -ForEach @('runs', 'artifacts') {
        $items = @(foreach ($id in 1..100) {
            if ($_ -eq 'runs') { $other = $run.Clone(); $other.id = 1000 + $id; $other.head_branch = 'another-tag'; $other }
            else { @{ id = 2000 + $id; name = "other-$id" } }
        })
        if ($_ -eq 'runs') { $items[0] = $run; $duplicate = $run.Clone(); $duplicate.id = 102 }
        else { $items[0] = $artifact; $duplicate = $artifact.Clone(); $duplicate.id = 202 }
        Write-BundleFixturePage -Kind $_ -Items $items -Total 101
        Write-BundleFixturePage -Kind $_ -Items @($duplicate) -Total 101 -Page 2
        { & $script:tool @acquire } | Should -Throw '*Exactly one*'
        Test-Path -LiteralPath $acquire.DestinationPath | Should -BeFalse
    }

    It 'fails closed on malformed or incomplete API evidence <_>' -ForEach @('json', 'array', 'count', 'collection', 'duplicate', 'short-page', 'capped', 'failure') {
        switch ($_) {
            json { '{bad' | Set-Content (Join-Path $fixture 'runs-1.json') }
            array { '[]' | Set-Content (Join-Path $fixture 'runs-1.json') }
            count { '{"total_count":"1","workflow_runs":[]}' | Set-Content (Join-Path $fixture 'runs-1.json') }
            collection { '{"total_count":1,"workflow_runs":{}}' | Set-Content (Join-Path $fixture 'runs-1.json') }
            duplicate { Write-BundleFixturePage -Kind runs -Items @($run, $run) }
            short-page { Write-BundleFixturePage -Kind runs -Items @($run) -Total 101 }
            capped { Write-BundleFixturePage -Kind runs -Items @($run) -Total 1000 }
            failure { New-Item -ItemType File -Path (Join-Path $fixture 'api-failure') | Out-Null }
        }
        { & $script:tool @acquire } | Should -Throw
        Test-Path -LiteralPath $acquire.DestinationPath | Should -BeFalse
    }

    It 'rejects changing pagination totals and duplicate IDs across pages' -ForEach @('total', 'id') {
        $items = @(foreach ($id in 1..100) { $other = $run.Clone(); $other.id = 1000 + $id; $other.head_branch = 'another-tag'; $other })
        Write-BundleFixturePage -Kind runs -Items $items -Total 101
        if ($_ -eq 'total') { Write-BundleFixturePage -Kind runs -Items @($run) -Total 102 -Page 2 }
        else { Write-BundleFixturePage -Kind runs -Items @($items[0]) -Total 101 -Page 2 }
        { & $script:tool @acquire } | Should -Throw
        Test-Path -LiteralPath $acquire.DestinationPath | Should -BeFalse
    }

    It 'rejects missing, differently named, and ambiguous artifacts' -ForEach @('missing', 'wrong-name', 'ambiguous') {
        $other = $artifact.Clone(); $other.id = 202
        $items = switch ($_) {
            missing { @() }
            wrong-name { $other.name = $artifactName.ToUpperInvariant(); @($other) }
            ambiguous { @($artifact, $other) }
        }
        Write-BundleFixturePage -Kind artifacts -Items $items
        { & $script:tool @acquire } | Should -Throw '*Exactly one artifact*'
        @(Get-BundleFixtureCalls).Count | Should -Be 2
    }

    It 'rejects expired or unknown expiration evidence <_>' -ForEach @('expired', 'past', 'malformed', 'missing', 'local-time', 'string-boolean') {
        switch ($_) {
            expired { $artifact.expired = $true }
            past { $artifact.expires_at = '2000-01-01T00:00:00Z' }
            malformed { $artifact.expires_at = '2099-13-01T00:00:00Z' }
            missing { $artifact.Remove('expires_at') }
            local-time { $artifact.expires_at = '2099-01-01T00:00:00' }
            string-boolean { $artifact.expired = 'false' }
        }
        Write-BundleFixturePage -Kind artifacts -Items @($artifact)
        { & $script:tool @acquire } | Should -Throw '*expiration*'
        @(Get-BundleFixtureCalls).Count | Should -Be 2
    }

    It 'rejects mismatched or missing artifact workflow binding <_>' -ForEach @('id', 'repository_id', 'head_repository_id', 'head_sha', 'head_branch', 'workflow_run') {
        if ($_ -eq 'workflow_run') { $artifact.Remove('workflow_run') }
        else { $artifact.workflow_run[$_] = if ($_ -in @('head_sha', 'head_branch')) { 'wrong' } else { 999 } }
        Write-BundleFixturePage -Kind artifacts -Items @($artifact)
        { & $script:tool @acquire } | Should -Throw '*workflow_run*'
        @(Get-BundleFixtureCalls).Count | Should -Be 2
    }

    It 'rejects unsafe, additional, missing, or malformed ZIP entries <_>' -ForEach @('traversal', 'backslash', 'absolute', 'directory', 'extra', 'duplicate', 'wrong-name', 'empty', 'symlink', 'malformed', 'download') {
        switch ($_) {
            traversal { Write-BundleFixtureZip -Names @("../$entryName") }
            backslash { Write-BundleFixtureZip -Names @("..\$entryName") }
            absolute { Write-BundleFixtureZip -Names @("/$entryName") }
            directory { Write-BundleFixtureZip -Names @("$entryName/") }
            extra { Write-BundleFixtureZip -Names @($entryName, 'extra.txt') }
            duplicate { Write-BundleFixtureZip -Names @($entryName, $entryName) }
            wrong-name { Write-BundleFixtureZip -Names @('other.tar.gz') }
            empty { Write-BundleFixtureZip -Empty }
            symlink { Write-BundleFixtureZip -ExternalAttributes ([int] (0xA000 -shl 16)) }
            malformed { [IO.File]::WriteAllText((Join-Path $fixture 'artifact.zip'), 'not a ZIP') }
            download { New-Item -ItemType File -Path (Join-Path $fixture 'download-failure') | Out-Null }
        }
        { & $script:tool @acquire } | Should -Throw
        Test-Path -LiteralPath $acquire.DestinationPath | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fixture $entryName) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $fixture -Directory -Filter '.azd-release-*').Count | Should -Be 0
        @(Get-BundleFixtureCalls).Count | Should -Be 3
    }
}
