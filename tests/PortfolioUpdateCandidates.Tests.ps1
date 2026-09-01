Describe 'Portfolio update candidate selection' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:selector = Join-Path $script:repoRoot 'tooling/Get-AzdPortfolioUpdateCandidates.ps1'
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
}
