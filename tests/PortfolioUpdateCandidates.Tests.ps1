Describe 'Portfolio update candidate selection' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:selector = Join-Path $script:repoRoot 'tooling/Get-AzdPortfolioUpdateCandidates.ps1'
        function gh { throw 'GitHub CLI must be mocked in candidate tests.' }
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $portfolioRoot = Join-Path $caseRoot 'portfolio'
        New-Item -ItemType Directory -Path $portfolioRoot | Out-Null
        $registryPath = Join-Path $caseRoot 'consumers.json'
        [ordered]@{
            schemaVersion = '1.0'
            referenceRepository = 'https://github.com/nathanmcnulty/azd-reference'
            consumers = @(
                [ordered]@{
                    id = 'consumer-one'
                    repository = 'https://github.com/example/consumer-one'
                    checkoutDirectory = 'consumer-one'
                    solutionRoot = '.'
                    defaultBranch = 'main'
                    repositoryValidationWorkflow = '.github/workflows/validate.yml'
                    rolloutRing = 'pilot'
                    adoption = 'adopted'
                    components = @([ordered]@{ id = 'example-component'; desiredVersion = '1.2.3' })
                    validation = [ordered]@{ entryPoint = 'scripts/Test-Repository.ps1'; timeoutMinutes = 10 }
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM
        $statusPath = Join-Path $caseRoot 'status.json'
        $diagnosticsPath = Join-Path $caseRoot 'selection.json'
    }

    It 'selects only explicitly desired safe version or adoption changes' {
        @(
            [ordered]@{
                consumer = 'consumer-one'
                component = 'example-component'
                desiredVersion = '1.2.3'
                installedVersion = $null
                state = 'notAdopted'
                findings = @()
            }
        ) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM

        $json = & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -AsJson
        $result = @($json | ConvertFrom-Json)

        $result.Count | Should -Be 1
        $result[0].consumer | Should -Be 'consumer-one'
        $result[0].component | Should -Be 'example-component'
        $result[0].version | Should -Be '1.2.3'
        $result[0].branch | Should -Be 'codex/update-consumer-one-example-component-v1.2.3'
        $result[0].repositoryOwner | Should -Be 'example'
        $result[0].repositoryName | Should -Be 'consumer-one'
        $result[0].defaultBranch | Should -Be 'main'
    }

    It 'returns an empty JSON array when every desired component is current' {
        @(
            [ordered]@{
                consumer = 'consumer-one'
                component = 'example-component'
                desiredVersion = '1.2.3'
                installedVersion = '1.2.3'
                state = 'current'
                findings = @()
            }
        ) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM

        (& $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -AsJson) |
            Should -Be '[]'
    }

    It 'fails closed instead of preparing a candidate with repository findings' {
        @(
            [ordered]@{
                consumer = 'consumer-one'
                component = 'example-component'
                desiredVersion = '1.2.3'
                installedVersion = '1.2.2'
                state = 'outdated'
                findings = @('checkoutDirty')
            }
        ) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM

        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath } |
            Should -Throw '*not safe to update*checkoutDirty*'
    }
    It 'validates an exact selector before opening the status file' -ForEach @('unknown-consumer', 'Consumer-one', 'consumer-*', "consumer-one`n") {
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath 'does-not-exist.json' -ConsumerId $_ } |
            Should -Throw '*ConsumerId*'
    }

    It 'rejects an ambiguous registry selector before processing status' {
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $registry.consumers = @($registry.consumers[0], $registry.consumers[0])
        $registry | ConvertTo-Json -Depth 20 | Set-Content $registryPath
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath 'does-not-exist.json' -ConsumerId 'consumer-one' } |
            Should -Throw '*duplicate consumer*'
    }

    It 'ignores unrelated unsafe records before evaluating findings' {
        @(
            @{ consumer = 'unrelated-consumer'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @('checkoutDirty') },
            @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() }
        ) | ConvertTo-Json -Depth 10 | Set-Content $statusPath
        $result = @((& $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -ConsumerId 'consumer-one' -AsJson) | ConvertFrom-Json)
        $result.Count | Should -Be 1
        $result[0].consumer | Should -BeExactly 'consumer-one'
    }

    It 'returns no candidates when selected consumer is current even if unrelated consumer is unsafe' {
        @(
            @{ consumer = 'unrelated-consumer'; state = 'outdated'; findings = @('checkoutDirty') },
            @{ consumer = 'consumer-one'; state = 'current'; findings = @() }
        ) | ConvertTo-Json -Depth 10 | Set-Content $statusPath
        (& $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -ConsumerId 'consumer-one' -AsJson) | Should -Be '[]'
    }

    It 'rejects status component or version not explicitly requested by registry' -ForEach @(
        @{ component = 'unregistered-component'; version = '1.2.3' },
        @{ component = 'example-component'; version = '9.9.9' }
    ) {
        @{ consumer = 'consumer-one'; component = $component; desiredVersion = $version; state = 'outdated'; findings = @() } |
            ConvertTo-Json -Depth 10 | Set-Content $statusPath
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath } |
            Should -Throw '*does not match the registry*'
    }

    It 'rejects duplicate consumer and component candidate rows' {
        $record = @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() }
        @($record, $record) | ConvertTo-Json -Depth 10 | Set-Content $statusPath
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath } |
            Should -Throw '*Duplicate consumer/component candidate*'
    }

    It 'preserves all-consumer selection when ConsumerId is empty' {
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $other = $registry.consumers[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $other.id = 'consumer-two'
        $other.repository = 'https://github.com/example/consumer-two'
        $other.checkoutDirectory = 'consumer-two'
        $registry.consumers = @($registry.consumers[0], $other)
        $registry | ConvertTo-Json -Depth 20 | Set-Content $registryPath
        @(
            @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() },
            @{ consumer = 'consumer-two'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() }
        ) | ConvertTo-Json -Depth 10 | Set-Content $statusPath
        $result = @((& $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -ConsumerId '' -AsJson) | ConvertFrom-Json)
        $result.Count | Should -Be 2
    }

    It 'records only observed exact open PR suppression without changing the candidate output' {
        @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() } |
            ConvertTo-Json | Set-Content $statusPath
        Mock gh {
            $global:LASTEXITCODE = 0
            '[{"url":"https://github.com/example/consumer-one/pull/7","headRefName":"codex/update-consumer-one-example-component-v1.2.3","baseRefName":"main","title":"chore: update example-component to 1.2.3"}]'
        }
        (& $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -ExcludeOpenPullRequests -DiagnosticsPath $diagnosticsPath -AsJson) | Should -Be '[]'
        $observed = Get-Content $diagnosticsPath -Raw | ConvertFrom-Json
        $observed.state | Should -Be 'completed'
        $observed.excludeOpenPullRequests | Should -BeTrue
        $observed.suppressed.Count | Should -Be 1
        $observed.suppressed[0].base | Should -Be 'main'
        $observed.suppressed[0].pullRequestUrls | Should -Be @('https://github.com/example/consumer-one/pull/7')
    }

    It 'does not suppress an inexact PR <field>' -ForEach @(
        @{ field = 'headRefName' }, @{ field = 'baseRefName' }, @{ field = 'title' }
    ) {
        @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() } |
            ConvertTo-Json | Set-Content $statusPath
        $pullRequest = @{ url = 'https://github.com/example/consumer-one/pull/7'; headRefName = 'codex/update-consumer-one-example-component-v1.2.3'; baseRefName = 'main'; title = 'chore: update example-component to 1.2.3' }
        $pullRequest[$field] = 'different'
        Mock gh -MockWith ({ $global:LASTEXITCODE = 0; ConvertTo-Json -InputObject @($pullRequest) -Compress }.GetNewClosure())
        $candidates = @((& $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -ExcludeOpenPullRequests -DiagnosticsPath $diagnosticsPath -AsJson) | ConvertFrom-Json)
        $candidates.Count | Should -Be 1
        (Get-Content $diagnosticsPath -Raw | ConvertFrom-Json).suppressed.Count | Should -Be 0
    }

    It 'retains the original selection failure while writing diagnostics' {
        @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @('desiredReleaseTagMissing:example-component@1.2.3') } |
            ConvertTo-Json | Set-Content $statusPath
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -DiagnosticsPath $diagnosticsPath -AsJson } |
            Should -Throw '*not safe to update*desiredReleaseTagMissing*'
        $observed = Get-Content $diagnosticsPath -Raw | ConvertFrom-Json
        $observed.state | Should -Be 'failed'
        $observed.error | Should -Match 'desiredReleaseTagMissing:example-component@1.2.3'
        $observed.suppressed.Count | Should -Be 0
    }

    It 'retains a failed PR lookup rather than reporting a successful empty selection' {
        @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @() } |
            ConvertTo-Json | Set-Content $statusPath
        Mock gh { $global:LASTEXITCODE = 1; 'lookup failed' }
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -ExcludeOpenPullRequests -DiagnosticsPath $diagnosticsPath -AsJson } |
            Should -Throw '*Unable to inspect existing pull requests*'
        $observed = Get-Content $diagnosticsPath -Raw | ConvertFrom-Json
        $observed.state | Should -Be 'failed'
        $observed.suppressed.Count | Should -Be 0
    }

    It 'does not mask a selection failure if the optional diagnostics cannot be written' {
        @{ consumer = 'consumer-one'; component = 'example-component'; desiredVersion = '1.2.3'; state = 'outdated'; findings = @('checkoutDirty') } |
            ConvertTo-Json | Set-Content $statusPath
        { & $script:selector -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -StatusPath $statusPath -DiagnosticsPath (Join-Path $caseRoot 'absent/selection.json') -WarningAction SilentlyContinue } |
            Should -Throw '*not safe to update*checkoutDirty*'
    }

}
