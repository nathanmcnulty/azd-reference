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
        $remote = Join-Path $caseRoot 'consumer-one.git'
        $repository = 'https://github.com/example/consumer-one'
        New-Item -ItemType Directory -Path $consumer, $worktrees -Force | Out-Null

        & git init --bare --initial-branch main $remote | Out-Null

        & git -C $consumer init --initial-branch main | Out-Null
        & git -C $consumer config user.name 'publisher tests'
        & git -C $consumer config user.email 'publisher-tests@example.invalid'
        & git -C $consumer remote add origin "$repository.git"
        New-Item -ItemType Directory -Path (Join-Path $consumer 'scripts') | Out-Null
        Set-Content -LiteralPath (Join-Path $consumer 'scripts/Test-Repository.ps1') -Encoding utf8NoBOM -Value "'validated' | Write-Output"
        Set-Content -LiteralPath (Join-Path $consumer 'README.md') -Encoding utf8NoBOM -Value '# Consumer fixture'
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Consumer fixture' | Out-Null
        & git -C $consumer push $remote main | Out-Null
        $consumerHead = (& git -C $consumer rev-parse HEAD).Trim()
        & git -C $consumer update-ref refs/remotes/origin/main $consumerHead

        $registryPath = Join-Path $caseRoot 'consumers.json'
        [ordered]@{
            schemaVersion = '1.0'
            referenceRepository = 'https://github.com/nathanmcnulty/azd-reference'
            consumers = @(
                [ordered]@{
                    id = 'consumer-one'
                    repository = $repository
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

        $addUnmaterializedSecondConsumer = {
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
            $registry.consumers += [pscustomobject] [ordered]@{
                id = 'consumer-two'
                repository = 'https://github.com/example/consumer-two'
                checkoutDirectory = 'consumer-two'
                solutionRoot = '.'
                defaultBranch = 'main'
                repositoryValidationWorkflow = '.github/workflows/validate.yml'
                rolloutRing = 'pilot'
                adoption = 'adopted'
                components = @(
                    [pscustomobject] [ordered]@{ id = 'deployment-validation'; desiredVersion = '0.3.3' }
                )
                validation = [pscustomobject] [ordered]@{ entryPoint = 'scripts/Test-Repository.ps1'; timeoutMinutes = 10 }
            }
            $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM
        }

        $global:PublisherTestGitApplication = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $global:PublisherTestRegisteredRepository = $repository
        $global:PublisherTestBareRepository = $remote
        $global:PublisherTestCreateRace = $false
        function global:git {
            $mappedArguments = @(
                foreach ($argument in $args) {
                    if ([string] $argument -eq $global:PublisherTestRegisteredRepository) {
                        $global:PublisherTestBareRepository
                    }
                    else {
                        $argument
                    }
                }
            )
            $lease = [string] ($mappedArguments | Where-Object { [string] $_ -like '--force-with-lease=refs/heads/*:' } | Select-Object -First 1)
            if ($global:PublisherTestCreateRace -and $lease) {
                $reference = ($lease -replace '^--force-with-lease=', '').TrimEnd(':')
                $existingRevision = (& $global:PublisherTestGitApplication --git-dir=$global:PublisherTestBareRepository rev-parse refs/heads/main).Trim()
                & $global:PublisherTestGitApplication --git-dir=$global:PublisherTestBareRepository update-ref $reference $existingRevision
            }
            & $global:PublisherTestGitApplication @mappedArguments
        }
        function global:gh {
            param([Parameter(ValueFromRemainingArguments)][string[]] $ArgumentList)

            $global:LASTEXITCODE = 0
            if ($ArgumentList[0] -eq 'auth') { return }
            if ($ArgumentList[0] -eq 'pr') {
                'https://github.com/example/consumer-one/pull/1'
                return
            }
            $global:LASTEXITCODE = 1
        }
    }

    AfterEach {
        Remove-Item Function:\git, Function:\gh -ErrorAction SilentlyContinue
        Remove-Variable PublisherTestGitApplication, PublisherTestRegisteredRepository, PublisherTestBareRepository, PublisherTestCreateRace -Scope Global -ErrorAction SilentlyContinue
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

    It 'rejects an unknown single-consumer selector without mutation' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()

        { & $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-missing `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -WhatIf } | Should -Throw '*identify exactly one registered consumer*'

        (& git -C $consumer rev-parse HEAD).Trim() | Should -Be $beforeHead
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'plans only the exact selected consumer and leaves other consumers untouched' {
        & $addUnmaterializedSecondConsumer
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $unselectedCheckout = Join-Path $portfolioRoot 'consumer-two'

        $result = @(& $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -WhatIf)

        $result.Count | Should -Be 1
        $result[0].consumer | Should -Be 'consumer-one'
        $result[0].state | Should -Be 'whatIf'
        (& git -C $consumer rev-parse HEAD).Trim() | Should -Be $beforeHead
        Test-Path -LiteralPath $unselectedCheckout | Should -BeFalse
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'publishes only the exact selected consumer and does not inspect another checkout' {
        & $addUnmaterializedSecondConsumer
        $unselectedCheckout = Join-Path $portfolioRoot 'consumer-two'

        $result = @(& $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false)

        $result.Count | Should -Be 1
        $result[0].consumer | Should -Be 'consumer-one'
        $result[0].state | Should -Be 'published'
        Test-Path -LiteralPath $unselectedCheckout | Should -BeFalse
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 1
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

    It 'publishes an atomically created ref through the exact registered URL' {
        $result = @(& $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false)

        $result[0].state | Should -Be 'published'
        $result[0].pullRequest | Should -Be 'https://github.com/example/consumer-one/pull/1'
        $published = @(& git ls-remote --heads $remote "refs/heads/$($result[0].branch)")
        $published.Count | Should -Be 1
        ($published[0] -split '\s+')[0] | Should -Be $result[0].commit
    }

    It 'fails closed when Git URL rewrite configuration is visible' {
        & git -C $consumer config "url.$remote.insteadOf" $repository
        { & $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*URL rewrite configuration is not allowed*'
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 0
    }

    It 'refreshes a stale default-branch tracking ref before preparation' {
        $remoteClone = Join-Path $caseRoot 'remote-writer'
        & git clone $remote $remoteClone | Out-Null
        & git -C $remoteClone config user.name 'remote writer'
        & git -C $remoteClone config user.email 'remote-writer@example.invalid'
        Set-Content -LiteralPath (Join-Path $remoteClone 'REMOTE.md') -Encoding utf8NoBOM -Value 'new default branch commit'
        & git -C $remoteClone add --all
        & git -C $remoteClone commit -m 'Advance remote main' | Out-Null
        & git -C $remoteClone push origin main | Out-Null
        $liveMain = (& git -C $remoteClone rev-parse HEAD).Trim()
        (& git -C $consumer rev-parse refs/remotes/origin/main).Trim() | Should -Not -Be $liveMain

        $result = @(& $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false)

        (& git -C $consumer rev-parse "$($result[0].branch)^").Trim() | Should -Be $liveMain
    }

    It 'rejects an existing live deterministic update branch before preparation' {
        $branch = 'codex/update-consumer-one-deployment-validation-v0.3.3'
        & git -C $consumer push $remote "HEAD:refs/heads/$branch" | Out-Null

        { & $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*Remote update branch already exists*'
        @(& git -C $consumer branch --list $branch).Count | Should -Be 0
    }

    It 'fails atomic creation when the branch appears during validation' {
        $global:PublisherTestCreateRace = $true
        { & $publisher `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*Git failed*'
    }

    It 'contains only expected-absent branch creation and draft pull-request publication commands' {
        $source = Get-Content -LiteralPath $publisher -Raw
        $source | Should -Match "--force-with-lease=refs/heads/"
        $source | Should -Match "'pr', 'create', '--draft'"
        $source | Should -Not -Match "'--force'"
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
