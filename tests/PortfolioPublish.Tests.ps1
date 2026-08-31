Describe 'Guarded portfolio publication' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:publisher = Join-Path $script:repoRoot 'tooling/Publish-AzdPortfolioUpdates.ps1'
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $portfolioRoot = Join-Path $caseRoot 'portfolio'
        $consumer = Join-Path $portfolioRoot 'consumer-one'
        $worktrees = Join-Path $caseRoot 'worktrees'
        New-Item -ItemType Directory -Path $consumer, $worktrees -Force | Out-Null

        & git -C $consumer init --initial-branch main | Out-Null
        & git -C $consumer config user.name 'publisher tests'
        & git -C $consumer config user.email 'publisher-tests@example.invalid'
        & git -C $consumer remote add origin 'https://github.com/example/consumer-one.git'
        Set-Content -LiteralPath (Join-Path $consumer 'README.md') -Encoding utf8NoBOM -Value '# Consumer fixture'
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Consumer fixture' | Out-Null
        $consumerHead = (& git -C $consumer rev-parse HEAD).Trim()
        & git -C $consumer update-ref refs/remotes/origin/main $consumerHead

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
                    components = @(
                        [ordered]@{ id = 'deployment-validation'; desiredVersion = '0.3.3' }
                    )
                    validation = [ordered]@{ entryPoint = 'scripts/Test-Repository.ps1'; timeoutMinutes = 10 }
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM
    }

    It 'plans publication without creating a branch, worktree, or remote state' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $result = @(& $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -WhatIf)

        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'whatIf'
        $result[0].branch | Should -Be 'codex/update-consumer-one-deployment-validation-v0.3.3'
        (& git -C $consumer rev-parse HEAD).Trim() | Should -Be $beforeHead
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'rejects a registry for a different reference origin before publication' {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $registry.referenceRepository = 'https://github.com/example/other-reference'
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        { & $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -WhatIf } | Should -Throw '*origin does not match*'
    }

    It 'contains only non-force push and draft pull-request publication commands' {
        $source = Get-Content -LiteralPath $publisher -Raw
        $source | Should -Match "'push', '--porcelain'"
        $source | Should -Match "'pr', 'create', '--draft'"
        $source | Should -Not -Match "'push'[^\r\n]*(?:--force|-f(?:'|\s))"
        $source | Should -Not -Match "'pr',\s*'(?:merge|review)'"
    }
}

Describe 'Scheduled public portfolio drift workflow' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:workflow = Join-Path $script:repoRoot '.github/workflows/portfolio-drift.yml'
    }

    It 'is read-only, scheduled, manually dispatchable, and retains a report' {
        $source = Get-Content -LiteralPath $workflow -Raw
        $source | Should -Match '(?m)^\s*schedule:'
        $source | Should -Match '(?m)^\s*workflow_dispatch:'
        $source | Should -Match '(?m)^permissions:\r?\n\s+contents: read$'
        $source | Should -Match '-FailOnFindings'
        $source | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
        $source | Should -Not -Match '(?i)az login|connect-azaccount|connect-mggraph|Test-Repository\.ps1'
    }
}
