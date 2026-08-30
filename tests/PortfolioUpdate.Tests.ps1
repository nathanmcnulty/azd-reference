Describe 'Portfolio update preparation' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $reference = Join-Path $caseRoot 'reference'
        $portfolioRoot = Join-Path $caseRoot 'portfolio'
        $consumer = Join-Path $portfolioRoot 'consumer-one'
        $worktrees = Join-Path $caseRoot 'worktrees'
        New-Item -ItemType Directory -Path $reference, $consumer, $worktrees | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'components') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'schemas') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tooling') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot '.gitattributes') -Destination $reference

        & git -C $reference init --initial-branch main | Out-Null
        & git -C $reference config core.autocrlf false
        & git -C $reference config user.name 'reference tests'
        & git -C $reference config user.email 'reference-tests@example.invalid'
        & git -C $reference remote add origin 'https://github.com/example/azd-reference.git'
        & git -C $reference add --all
        & git -C $reference commit -m 'Reference fixture' | Out-Null
        & git -C $reference tag 'component/deployment-validation/v0.3.3'

        & git -C $consumer init --initial-branch main | Out-Null
        & git -C $consumer config core.autocrlf false
        & git -C $consumer config user.name 'consumer tests'
        & git -C $consumer config user.email 'consumer-tests@example.invalid'
        & git -C $consumer remote add origin 'https://github.com/example/consumer-one.git'
        New-Item -ItemType Directory -Path (Join-Path $consumer 'scripts') | Out-Null
        Set-Content -LiteralPath (Join-Path $consumer 'scripts/Test-Repository.ps1') -Encoding utf8NoBOM -Value "`$expected = Split-Path `$PSScriptRoot -Parent`nif ((Get-Location).Path -ne `$expected) { throw 'validation working directory mismatch' }`n'validated' | Write-Output"
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Consumer fixture' | Out-Null
        $consumerHead = (& git -C $consumer rev-parse HEAD).Trim()
        & git -C $consumer update-ref refs/remotes/origin/main $consumerHead

        $registryPath = Join-Path $caseRoot 'consumers.json'
        [ordered]@{
            schemaVersion = '1.0'
            referenceRepository = 'https://github.com/example/azd-reference'
            consumers = @(
                [ordered]@{
                    id = 'consumer-one'
                    repository = 'https://github.com/example/consumer-one'
                    checkoutDirectory = 'consumer-one'
                    solutionRoot = '.'
                    defaultBranch = 'main'
                    repositoryValidationWorkflow = '.github/workflows/validate.yml'
                    desiredBaseline = '2026.08.2'
                    rolloutRing = 'pilot'
                    adoption = 'adopted'
                    components = @(
                        [ordered]@{ id = 'deployment-validation'; desiredVersion = '0.3.3' }
                    )
                    validation = [ordered]@{ entryPoint = 'scripts/Test-Repository.ps1'; timeoutMinutes = 10 }
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $updater = Join-Path $reference 'tooling/Update-AzdPortfolio.ps1'
    }

    It 'plans without changing a consumer, branch, or worktree' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $result = @(& $updater -Component deployment-validation -Version 0.3.3 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'planned'
        $result[0].baseline | Should -Be '2026.08.2'
        (& git -C $consumer rev-parse HEAD).Trim() | Should -Be $beforeHead
        Test-Path -LiteralPath (Join-Path $consumer 'azd-components.lock.json') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
    }

    It 'selects only the rollout ring that approves the requested version' {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $heldConsumer = $registry.consumers[0].PSObject.Copy()
        $heldConsumer.id = 'consumer-held'
        $heldConsumer.repository = 'https://github.com/example/consumer-held'
        $heldConsumer.checkoutDirectory = 'consumer-held'
        $heldConsumer.components = @([pscustomobject]@{ id = 'deployment-validation'; desiredVersion = '0.3.2' })
        $registry.consumers = @($registry.consumers[0], $heldConsumer)
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $result = @(& $updater -Component deployment-validation -Version 0.3.3 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath)
        $result.Count | Should -Be 1
        $result[0].consumer | Should -Be 'consumer-one'
    }

    It 'prepares one isolated local branch and leaves the active checkout unchanged' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $result = @(& $updater -Component deployment-validation -Version 0.3.3 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'prepared'
        (& git -C $consumer rev-parse HEAD).Trim() | Should -Be $beforeHead
        Test-Path -LiteralPath (Join-Path $consumer 'azd-components.lock.json') | Should -BeFalse
        @(& git -C $consumer branch --list $result[0].branch).Count | Should -Be 1
        $preparedLock = (& git -C $consumer show "$($result[0].branch):azd-components.lock.json") | ConvertFrom-Json
        $preparedLock.baseline | Should -Be '2026.08.2'
        $result[0].baseline | Should -Be '2026.08.2'
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'resolves validation from the repository root and runs it from the solution root' {
        $solutionRoot = Join-Path $consumer 'nested-solution'
        New-Item -ItemType Directory -Path $solutionRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $solutionRoot '.gitkeep') -Encoding utf8NoBOM -Value ''
        Set-Content -LiteralPath (Join-Path $consumer 'scripts/Test-Repository.ps1') -Encoding utf8NoBOM -Value "`$expected = Join-Path (Split-Path `$PSScriptRoot -Parent) 'nested-solution'`nif ((Get-Location).Path -ne `$expected) { throw 'validation working directory mismatch' }`n'validated' | Write-Output"
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Add nested solution fixture' | Out-Null
        $consumerHead = (& git -C $consumer rev-parse HEAD).Trim()
        & git -C $consumer update-ref refs/remotes/origin/main $consumerHead

        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $registry.consumers[0].solutionRoot = 'nested-solution'
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $result = @(& $updater -Component deployment-validation -Version 0.3.3 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false)
        $result[0].state | Should -Be 'prepared'
        $result[0].validationOutput | Should -Contain 'validated'
        (& git -C $consumer show "$($result[0].branch):nested-solution/azd-components.lock.json") | Should -Not -BeNullOrEmpty
    }

    It 'removes its temporary branch when the consumer is already current' {
        & $updater -Component deployment-validation -Version 0.3.3 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false | Out-Null
        $preparedBranch = @(& git -C $consumer branch --list 'codex/update-*')[0].Trim()
        & git -C $consumer update-ref refs/remotes/origin/main $preparedBranch
        & git -C $consumer branch -D -- $preparedBranch | Out-Null

        $result = @(& $updater -Component deployment-validation -Version 0.3.3 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false)
        $result[0].state | Should -Be 'alreadyCurrent'
        $result[0].branch | Should -BeNullOrEmpty
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }
}
