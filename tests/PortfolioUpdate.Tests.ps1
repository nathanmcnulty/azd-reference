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
        & git -C $reference tag 'component/deployment-validation/v1.0.0'

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
                        [ordered]@{ id = 'deployment-validation'; desiredVersion = '1.0.0' }
                    )
                    validation = [ordered]@{ entryPoint = 'scripts/Test-Repository.ps1'; timeoutMinutes = 10 }
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $updater = Join-Path $reference 'tooling/Update-AzdPortfolio.ps1'
    }

    It 'plans without changing a consumer, branch, or worktree' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $result = @(& $updater -Component deployment-validation -Version 1.0.0 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath)
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
        $heldConsumer.components = @([pscustomobject]@{ id = 'deployment-validation'; desiredVersion = '0.9.0' })
        $registry.consumers = @($registry.consumers[0], $heldConsumer)
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        $result = @(& $updater -Component deployment-validation -Version 1.0.0 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath)
        $result.Count | Should -Be 1
        $result[0].consumer | Should -Be 'consumer-one'
    }

    It 'prepares one isolated local branch and leaves the active checkout unchanged' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $result = @(& $updater -Component deployment-validation -Version 1.0.0 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false)
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

        $result = @(& $updater -Component deployment-validation -Version 1.0.0 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false)
        $result[0].state | Should -Be 'prepared'
        $result[0].validationOutput | Should -Contain 'validated'
        (& git -C $consumer show "$($result[0].branch):nested-solution/azd-components.lock.json") | Should -Not -BeNullOrEmpty
    }

    It 'removes its temporary branch when the consumer is already current' {
        & $updater -Component deployment-validation -Version 1.0.0 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false | Out-Null
        $preparedBranch = @(& git -C $consumer branch --list 'codex/update-*')[0].Trim()
        & git -C $consumer update-ref refs/remotes/origin/main $preparedBranch
        & git -C $consumer branch -D -- $preparedBranch | Out-Null

        $result = @(& $updater -Component deployment-validation -Version 1.0.0 -PortfolioRoot $portfolioRoot -RegistryPath $registryPath -Operation Prepare -WorktreeRoot $worktrees -Confirm:$false)
        $result[0].state | Should -Be 'alreadyCurrent'
        $result[0].branch | Should -BeNullOrEmpty
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }
}

Describe 'Windows worktree cleanup recovery' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $updaterSource = Join-Path $script:repoRoot 'tooling/Update-AzdPortfolio.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($updaterSource, [ref] $tokens, [ref] $parseErrors)
        $parseErrors.Count | Should -Be 0
        foreach ($functionName in 'Invoke-GitChecked', 'Get-SafeEmptyWorktreeResidue', 'Remove-EmptyWorktreeResidueWithRetry', 'Remove-PreparedWorktree') {
            $functionAst = $ast.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
                }, $true)
            $functionAst | Should -Not -BeNullOrEmpty
            Invoke-Expression $functionAst.Extent.Text
        }
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $repository = Join-Path $caseRoot 'repository'
        $worktreeRoot = Join-Path $caseRoot 'worktrees'
        $residue = Join-Path $worktreeRoot 'consumer-component-v1-0-0'
        New-Item -ItemType Directory -Path $repository, $worktreeRoot, $residue | Out-Null
        & git -C $repository init --initial-branch main | Out-Null
    }

    AfterEach {
        Remove-Item Function:\git -ErrorAction SilentlyContinue
        Remove-Variable CleanupTestGitApplication, CleanupTestResidue -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable CleanupTestState -Scope Script -ErrorAction SilentlyContinue
    }

    It 'retries a transient native deletion failure with bounded backoff' {
        $script:CleanupTestState = [pscustomobject]@{ Attempts = 0; Delays = @() }
        $delete = {
            param($Path)
            $script:CleanupTestState.Attempts++
            if ($script:CleanupTestState.Attempts -lt 3) { throw 'simulated transient directory lock' }
            [System.IO.Directory]::Delete($Path, $false)
        }
        $delay = { param($Milliseconds) $script:CleanupTestState.Delays += $Milliseconds }

        $result = Remove-EmptyWorktreeResidueWithRetry `
            -RepositoryRoot $repository `
            -WorktreeRoot $worktreeRoot `
            -WorktreePath $residue `
            -WindowsPlatform $true `
            -DeleteDirectory $delete `
            -Delay $delay

        $result | Should -BeTrue
        $script:CleanupTestState.Attempts | Should -Be 3
        $script:CleanupTestState.Delays | Should -Be @(100, 200)
        Test-Path -LiteralPath $residue | Should -BeFalse
    }

    It 'accepts an already-absent unregistered target without invoking deletion' {
        Remove-Item -LiteralPath $residue
        $script:CleanupTestState = [pscustomobject]@{ Attempts = 0 }
        $delete = {
            param($Path)
            $script:CleanupTestState.Attempts++
            throw "Deletion must not run for an already-absent target: '$Path'."
        }

        $result = Remove-EmptyWorktreeResidueWithRetry `
            -RepositoryRoot $repository `
            -WorktreeRoot $worktreeRoot `
            -WorktreePath $residue `
            -WindowsPlatform $true `
            -DeleteDirectory $delete

        $result | Should -BeTrue
        $script:CleanupTestState.Attempts | Should -Be 0
        Test-Path -LiteralPath $residue | Should -BeFalse
    }

    It 'refuses an already-absent target that is still registered' {
        Remove-Item -LiteralPath $residue
        $global:CleanupTestGitApplication = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $global:CleanupTestResidue = $residue
        function global:git {
            if (@($args) -join ' ' -like '*worktree list --porcelain*') {
                $global:LASTEXITCODE = 0
                "worktree $($global:CleanupTestResidue.Replace('\', '/'))"
                return
            }
            & $global:CleanupTestGitApplication @args
        }

        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true) | Should -BeFalse
        Test-Path -LiteralPath $residue | Should -BeFalse
    }

    It 'never retries outside the dedicated worktree root' {
        $outside = Join-Path $caseRoot 'outside-residue'
        New-Item -ItemType Directory -Path $outside | Out-Null
        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $outside -WindowsPlatform $true) | Should -BeFalse
        Test-Path -LiteralPath $outside | Should -BeTrue
    }

    It 'never retries a non-empty residue' {
        Set-Content -LiteralPath (Join-Path $residue 'retained.txt') -Value 'must remain'
        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $residue 'retained.txt') | Should -BeTrue
    }

    It 'never retries a reparse-point residue' {
        Remove-Item -LiteralPath $residue
        $junctionTarget = Join-Path $caseRoot 'junction-target'
        New-Item -ItemType Directory -Path $junctionTarget | Out-Null
        $linkType = if ([System.OperatingSystem]::IsWindows()) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $residue -Target $junctionTarget | Out-Null

        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true) | Should -BeFalse
        Test-Path -LiteralPath $residue | Should -BeTrue
        Test-Path -LiteralPath $junctionTarget | Should -BeTrue
    }

    It 'never retries an exact path that is still registered' {
        $global:CleanupTestGitApplication = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $global:CleanupTestResidue = $residue
        function global:git {
            if (@($args) -join ' ' -like '*worktree list --porcelain*') {
                $global:LASTEXITCODE = 0
                "worktree $($global:CleanupTestResidue.Replace('\', '/'))"
                return
            }
            & $global:CleanupTestGitApplication @args
        }

        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true) | Should -BeFalse
        Test-Path -LiteralPath $residue | Should -BeTrue
    }

    It 'never retries when the supplied path differs from its full resolution' {
        $nonCanonical = Join-Path $worktreeRoot 'nested/../consumer-component-v1-0-0'
        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $nonCanonical -WindowsPlatform $true) | Should -BeFalse
        Test-Path -LiteralPath $residue | Should -BeTrue
    }

    It 'never retries on a non-Windows platform decision' {
        (Remove-EmptyWorktreeResidueWithRetry -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $false) | Should -BeFalse
        Test-Path -LiteralPath $residue | Should -BeTrue
    }

    It 'recovers through the wrapper only after Git leaves safe empty residue' {
        function global:git {
            if (@($args) -join ' ' -like '*worktree remove*') {
                $global:LASTEXITCODE = 1
                'simulated transient Windows removal failure'
                return
            }
            if (@($args) -join ' ' -like '*worktree list --porcelain*') {
                $global:LASTEXITCODE = 0
                return
            }
            $global:LASTEXITCODE = 1
        }

        { Remove-PreparedWorktree -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true } |
            Should -Not -Throw
        Test-Path -LiteralPath $residue | Should -BeFalse
    }

    It 'preserves the original Git diagnostic when recovery is refused' {
        function global:git {
            $global:LASTEXITCODE = 1
            'original worktree removal diagnostic'
        }

        { Remove-PreparedWorktree -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true } |
            Should -Throw '*original worktree removal diagnostic*'
        Test-Path -LiteralPath $residue | Should -BeTrue
    }

    It 'preserves the original Git diagnostic when safety revalidation throws' {
        function global:git {
            if (@($args) -join ' ' -like '*worktree remove*') {
                $global:LASTEXITCODE = 1
                'original worktree removal diagnostic'
                return
            }
            if (@($args) -join ' ' -like '*worktree list --porcelain*') {
                throw 'secondary revalidation exception'
            }
            $global:LASTEXITCODE = 1
        }

        $caught = $null
        try {
            Remove-PreparedWorktree -RepositoryRoot $repository -WorktreeRoot $worktreeRoot -WorktreePath $residue -WindowsPlatform $true
        }
        catch {
            $caught = $_.Exception.Message
        }

        $caught | Should -Match 'original worktree removal diagnostic'
        $caught | Should -Match 'Windows worktree cleanup retry was refused or exhausted'
        $caught | Should -Not -Match 'secondary revalidation exception'
        Test-Path -LiteralPath $residue | Should -BeTrue
    }
}
