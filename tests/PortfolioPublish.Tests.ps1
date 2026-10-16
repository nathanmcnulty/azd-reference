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
        & git -C $consumer config core.autocrlf false
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

        $addSecondConsumer = {
            param([switch] $Materialize)

            $secondCheckout = Join-Path $portfolioRoot 'consumer-two'
            $secondRemote = Join-Path $caseRoot 'consumer-two.git'
            $secondRepository = 'https://github.com/example/consumer-two'
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
            $registry.consumers += [pscustomobject] [ordered]@{
                id = 'consumer-two'
                repository = $secondRepository
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

            $secondHead = $null
            if ($Materialize) {
                New-Item -ItemType Directory -Path $secondCheckout | Out-Null
                & git init --bare --initial-branch main $secondRemote | Out-Null
                & git -C $secondCheckout init --initial-branch main | Out-Null
                & git -C $secondCheckout config core.autocrlf false
                & git -C $secondCheckout config user.name 'publisher tests'
                & git -C $secondCheckout config user.email 'publisher-tests@example.invalid'
                & git -C $secondCheckout remote add origin "$secondRepository.git"
                New-Item -ItemType Directory -Path (Join-Path $secondCheckout 'scripts') | Out-Null
                Set-Content -LiteralPath (Join-Path $secondCheckout 'scripts/Test-Repository.ps1') -Encoding utf8NoBOM -Value "'validated' | Write-Output"
                Set-Content -LiteralPath (Join-Path $secondCheckout 'README.md') -Encoding utf8NoBOM -Value '# Second consumer fixture'
                & git -C $secondCheckout add --all
                & git -C $secondCheckout commit -m 'Second consumer fixture' | Out-Null
                & git -C $secondCheckout push $secondRemote main | Out-Null
                $secondHead = (& git -C $secondCheckout rev-parse HEAD).Trim()
                & git -C $secondCheckout update-ref refs/remotes/origin/main $secondHead
                $global:PublisherTestRepositoryMap[$secondRepository] = $secondRemote
            }

            [pscustomobject]@{
                Checkout = $secondCheckout
                Remote = $secondRemote
                Repository = $secondRepository
                Head = $secondHead
            }
        }

        $bundlePath = Join-Path $caseRoot 'component-release.tar.gz'
        'Offline bundle fixture; attestation verification is mocked.' | Set-Content $bundlePath
        $releaseTag = 'component/deployment-validation/v0.3.3'
        $expectedRevision = (& git --no-replace-objects -C $script:repoRoot rev-parse "refs/tags/${releaseTag}^{commit}").Trim()
        $tagObject = (& git --no-replace-objects -C $script:repoRoot rev-parse "refs/tags/${releaseTag}^{tag}").Trim()
        $publishEvidence = @{ ReleaseBundlePath = $bundlePath; ExpectedRevision = $expectedRevision }
        $savedToken = $env:GH_TOKEN
        $savedReadToken = $env:AZD_RELEASE_READ_TOKEN
        $env:GH_TOKEN = 'fixture-app-credential'
        $env:AZD_RELEASE_READ_TOKEN = 'fixture-read-credential'
        $global:PublisherTestReferenceRoot = $script:repoRoot
        $global:PublisherTestReleaseTag = $releaseTag
        $global:PublisherTestReleaseCommit = $expectedRevision
        $global:PublisherTestTagObject = $tagObject
        $global:PublisherTestVerifyCount = 0
        $global:PublisherTestFailVerifyAt = 0
        $global:PublisherTestMoveBranchAtVerify = $false
        $global:PublisherTestConsumerRoot = $consumer
        $global:PublisherTestVerificationTokens = [System.Collections.Generic.List[string]]::new()
        $global:PublisherTestWriteTokens = [System.Collections.Generic.List[string]]::new()
        $global:PublisherTestGitApplication = (Get-Command git -CommandType Application | Select-Object -First 1).Source
        $global:PublisherTestRepositoryMap = @{ $repository = $remote }
        $global:PublisherTestBareRepository = $remote
        $global:PublisherTestCreateRace = $false
        $global:PublisherTestPullRequests = @{}
        function global:git {
            # No test reads live GitHub tag state. Map only this exact read to
            # local fixture evidence; all consumer remotes are local bare repos.
            if ($args -contains 'ls-remote' -and $args -contains 'origin' -and
                $args -contains $global:PublisherTestReferenceRoot) {
                $global:LASTEXITCODE = 0
                "$($global:PublisherTestTagObject)`trefs/tags/$($global:PublisherTestReleaseTag)"
                "$($global:PublisherTestReleaseCommit)`trefs/tags/$($global:PublisherTestReleaseTag)^{}"
                return
            }
            if ($args -contains 'push') { $global:PublisherTestWriteTokens.Add([string] $env:GH_TOKEN) }
            $mappedArguments = @(
                foreach ($argument in $args) {
                    $argumentText = [string] $argument
                    if ($global:PublisherTestRepositoryMap.ContainsKey($argumentText)) {
                        $global:PublisherTestRepositoryMap[$argumentText]
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
            if ($ArgumentList[0] -eq 'api') {
                if ($ArgumentList[-1] -like '*/git/ref/tags/*') {
                    return (@{ ref = "refs/tags/$global:PublisherTestReleaseTag"; object = @{ type = 'tag'; sha = $global:PublisherTestTagObject } } | ConvertTo-Json -Depth 5)
                }
                if ($ArgumentList[-1] -like '*/git/tags/*') {
                    return (@{ sha = $global:PublisherTestTagObject; tag = $global:PublisherTestReleaseTag; object = @{ type = 'commit'; sha = $global:PublisherTestReleaseCommit }; verification = @{ verified = $true } } | ConvertTo-Json -Depth 5)
                }
                throw 'Unexpected API request in offline publisher fixture.'
            }
            if ($ArgumentList[0] -eq 'attestation') {
                $global:PublisherTestVerifyCount++
                $global:PublisherTestVerificationTokens.Add([string] $env:GH_TOKEN)
                if ($global:PublisherTestMoveBranchAtVerify -and $global:PublisherTestVerifyCount -eq 2) {
                    & $global:PublisherTestGitApplication -C $global:PublisherTestConsumerRoot update-ref `
                        refs/heads/codex/update-consumer-one-deployment-validation-v0.3.3 refs/heads/main
                }
                if ($global:PublisherTestVerifyCount -eq $global:PublisherTestFailVerifyAt) { $global:LASTEXITCODE = 1 }
                return
            }
            if ($ArgumentList[0] -eq 'pr') {
                $global:PublisherTestWriteTokens.Add([string] $env:GH_TOKEN)
                $repoIndex = [Array]::IndexOf($ArgumentList, '--repo')
                if ($repoIndex -lt 0 -or $repoIndex + 1 -ge $ArgumentList.Count) {
                    $global:LASTEXITCODE = 1
                    return
                }
                $repositorySlug = $ArgumentList[$repoIndex + 1]
                $pullRequestUrl = "https://github.com/$repositorySlug/pull/1"
                $global:PublisherTestPullRequests[$repositorySlug] = $pullRequestUrl
                $pullRequestUrl
                return
            }
            $global:LASTEXITCODE = 1
        }
    }

    AfterEach {
        Remove-Item Function:\git, Function:\gh -ErrorAction SilentlyContinue
        Remove-Variable PublisherTest* -Scope Global -ErrorAction SilentlyContinue
        if ($null -eq $savedToken) { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue } else { $env:GH_TOKEN = $savedToken }
        if ($null -eq $savedReadToken) { Remove-Item Env:AZD_RELEASE_READ_TOKEN -ErrorAction SilentlyContinue } else { $env:AZD_RELEASE_READ_TOKEN = $savedReadToken }
    }

    It 'plans publication without creating a branch, worktree, or remote state' {
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()
        $result = @(& $publisher @publishEvidence `
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

        { & $publisher @publishEvidence `
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
        $second = & $addSecondConsumer
        $beforeHead = (& git -C $consumer rev-parse HEAD).Trim()

        $result = @(& $publisher @publishEvidence `
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
        Test-Path -LiteralPath $second.Checkout | Should -BeFalse
        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'publishes only the exact selected consumer and does not inspect another checkout' {
        $second = & $addSecondConsumer

        $result = @(& $publisher @publishEvidence `
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
        Test-Path -LiteralPath $second.Checkout | Should -BeFalse
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'rejects duplicate registry consumer IDs in default mode without mutation' {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $duplicate = $registry.consumers[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $duplicate.checkoutDirectory = 'duplicate-consumer-one'
        $registry.consumers += $duplicate
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        { & $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*duplicate consumer ID*'

        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'rejects duplicate component IDs before selected publication can mutate state' {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $registry.consumers[0].components += [pscustomobject]@{ id = 'deployment-validation'; desiredVersion = '0.3.3' }
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        { & $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*duplicate component ID*'

        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'rejects a selected consumer version mismatch without mutation' {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $registry.consumers[0].components[0].desiredVersion = '0.3.2'
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        { & $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*No registered consumer approves*'

        @(& git -C $consumer branch --list 'codex/update-*').Count | Should -Be 0
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-*').Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'resumes a different exact consumer when an earlier branch and pull request exist' {
        $second = & $addSecondConsumer -Materialize
        $earlierBranch = 'codex/update-consumer-one-deployment-validation-v0.3.3'
        & $global:PublisherTestGitApplication --git-dir=$remote update-ref "refs/heads/$earlierBranch" $consumerHead
        $global:PublisherTestPullRequests['example/consumer-one'] = 'https://github.com/example/consumer-one/pull/earlier'

        $result = @(& $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-two `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false)

        $result.Count | Should -Be 1
        $result[0].consumer | Should -Be 'consumer-two'
        $result[0].pullRequest | Should -Be 'https://github.com/example/consumer-two/pull/1'
        (& $global:PublisherTestGitApplication --git-dir=$remote rev-parse "refs/heads/$earlierBranch").Trim() | Should -Be $consumerHead
        $global:PublisherTestPullRequests['example/consumer-one'] | Should -Be 'https://github.com/example/consumer-one/pull/earlier'
        @(& git ls-remote --heads $second.Remote 'refs/heads/codex/update-consumer-two-deployment-validation-v0.3.3').Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'publishes every eligible consumer when ConsumerId is omitted' {
        $second = & $addSecondConsumer -Materialize

        $result = @(& $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false)

        $result.Count | Should -Be 2
        @($result.consumer | Sort-Object) | Should -Be @('consumer-one', 'consumer-two')
        @(& git ls-remote --heads $remote 'refs/heads/codex/update-consumer-one-deployment-validation-v0.3.3').Count | Should -Be 1
        @(& git ls-remote --heads $second.Remote 'refs/heads/codex/update-consumer-two-deployment-validation-v0.3.3').Count | Should -Be 1
        $global:PublisherTestPullRequests['example/consumer-one'] | Should -Be 'https://github.com/example/consumer-one/pull/1'
        $global:PublisherTestPullRequests['example/consumer-two'] | Should -Be 'https://github.com/example/consumer-two/pull/1'
        @(Get-ChildItem -LiteralPath $worktrees -Force).Count | Should -Be 0
    }

    It 'rejects a registry for a different reference origin before publication' {
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        $registry.referenceRepository = 'https://github.com/example/other-reference'
        $registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryPath -Encoding utf8NoBOM

        { & $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -WhatIf } | Should -Throw '*origin does not match*'
    }

    It 'publishes an atomically created ref through the exact registered URL' {
        $result = @(& $publisher @publishEvidence `
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
        { & $publisher @publishEvidence `
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

        $result = @(& $publisher @publishEvidence `
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

        { & $publisher @publishEvidence `
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
        { & $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Confirm:$false } | Should -Throw '*Git failed*'
    }

    It 'publishes canonical Git content under automatic CRLF checkout without changing consumer settings' {
        & git -C $consumer config core.autocrlf true
        & git -C $consumer config core.eol crlf
        $result = & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false
        $result.state | Should -Be 'published'
        (& git -C $consumer config core.autocrlf).Trim() | Should -BeExactly 'true'
        (& git -C $consumer config core.eol).Trim() | Should -BeExactly 'crlf'
        $global:PublisherTestVerifyCount | Should -Be 2
    }

    It 'replays a prepared upgrade from canonical parent blobs under CRLF defaults' {
        & (Join-Path $script:repoRoot 'tooling/Sync-AzdComponent.ps1') -Component deployment-validation `
            -Version 0.3.2 -TargetPath $consumer -Confirm:$false | Out-Null
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Previous canonical component' | Out-Null
        & git -C $consumer push $remote main 2>&1 | Out-Null
        & git -C $consumer update-ref refs/remotes/origin/main HEAD
        $prepared = & (Join-Path $script:repoRoot 'tooling/Update-AzdPortfolio.ps1') `
            -Component deployment-validation -Version 0.3.3 -ExpectedRevision $expectedRevision -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Operation Prepare -Confirm:$false
        & git -C $consumer config core.autocrlf true
        & git -C $consumer config core.eol crlf
        $result = & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -PreparedBranchesOnly -Confirm:$false
        $result.state | Should -Be 'published'
        $result.commit | Should -BeExactly $prepared.commit
        (& git -C $consumer config core.autocrlf).Trim() | Should -BeExactly 'true'
        (& git -C $consumer config core.eol).Trim() | Should -BeExactly 'crlf'
    }

    It 'rejects changed canonical content under automatic CRLF checkout with forged hashes <Forge>' -ForEach @(
        @{ Forge = $false; Error = '*Managed file drift*' },
        @{ Forge = $true; Error = '*different managed content*' }
    ) {
        & git -C $consumer config core.autocrlf true
        & git -C $consumer config core.eol crlf
        $prepared = & (Join-Path $script:repoRoot 'tooling/Update-AzdPortfolio.ps1') `
            -Component deployment-validation -Version 0.3.3 -ExpectedRevision $expectedRevision -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Operation Prepare -Confirm:$false
        & git -C $consumer checkout $prepared.branch 2>&1 | Out-Null
        $lockPath = Join-Path $consumer 'azd-components.lock.json'
        $lock = Get-Content $lockPath -Raw | ConvertFrom-Json
        $file = $lock.components[0].files[0]
        $managedPath = Join-Path $consumer $file.target
        $text = [IO.File]::ReadAllText($managedPath).Replace("`r`n", "`n") + "# changed canonical content`n"
        [IO.File]::WriteAllText($managedPath, $text, [Text.UTF8Encoding]::new($false))
        if ($Forge) {
            $file.sha256 = (Get-FileHash $managedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $lock | ConvertTo-Json -Depth 30 | Set-Content $lockPath
        }
        & git -C $consumer add --all
        & git -C $consumer commit --amend --no-edit | Out-Null
        { & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -PreparedBranchesOnly -Confirm:$false } |
            Should -Throw $Error
        $global:PublisherTestWriteTokens.Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
        (& git -C $consumer config core.autocrlf).Trim() | Should -BeExactly 'true'
    }

    It 'reproduces an explicitly approved baseline during publication' {
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $registry.consumers[0] | Add-Member -NotePropertyName desiredBaseline -NotePropertyValue '2026.10'
        $registry | ConvertTo-Json -Depth 20 | Set-Content $registryPath
        $result = & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false
        $result.state | Should -Be 'published'
        $lock = (& git -C $consumer show "$($result.commit):azd-components.lock.json" | Out-String) | ConvertFrom-Json
        $lock.baseline | Should -BeExactly '2026.10'
    }

    It 'reproduces an approved removal without restoring a retired managed file' {
        & (Join-Path $script:repoRoot 'tooling/Sync-AzdComponent.ps1') -Component deployment-validation `
            -Version 0.3.2 -TargetPath $consumer -Confirm:$false | Out-Null
        $retiredPath = Join-Path $consumer 'retired-fixture.txt'
        'Retired fixture bytes' | Set-Content $retiredPath
        $lockPath = Join-Path $consumer 'azd-components.lock.json'
        $lock = Get-Content $lockPath -Raw | ConvertFrom-Json
        $lock.components[0].files += [pscustomobject]@{
            source = 'retired-fixture.txt'; target = 'retired-fixture.txt'
            sha256 = (Get-FileHash $retiredPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $lock | ConvertTo-Json -Depth 20 | Set-Content $lockPath
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Previously managed file fixture' | Out-Null
        & git -C $consumer push $remote main 2>&1 | Out-Null
        $global:PublisherTestWriteTokens.Clear()
        & git -C $consumer update-ref refs/remotes/origin/main HEAD
        $result = & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -PruneRemovedFiles -Confirm:$false
        $result.state | Should -Be 'published'
        @(& git -C $consumer ls-tree --name-only $result.commit -- retired-fixture.txt).Count | Should -Be 0
    }

    It 'requires supplied release evidence before preparation or any write' {
        { & $publisher -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false } |
            Should -Throw '*requires -ReleaseBundlePath and -ExpectedRevision*'
        $global:PublisherTestVerifyCount | Should -Be 0
        $global:PublisherTestWriteTokens.Count | Should -Be 0
        @(Get-ChildItem $worktrees -Force).Count | Should -Be 0
    }

    It 'rejects an expected revision that differs from the trusted selected tag' {
        $publishEvidence.ExpectedRevision = 'a' * 40
        { & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false } |
            Should -Throw '*ExpectedRevision does not match*'
        $global:PublisherTestVerifyCount | Should -Be 0
        $global:PublisherTestWriteTokens.Count | Should -Be 0
    }

    It 'restores an initially absent GH_TOKEN on verification <Outcome>' -ForEach @(
        @{ Outcome = 'success'; FailAt = 0 }, @{ Outcome = 'failure'; FailAt = 1 }
    ) {
        Remove-Item Env:GH_TOKEN
        $global:PublisherTestFailVerifyAt = $FailAt
        $invoke = {
            & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false
        }
        if ($FailAt) { $invoke | Should -Throw '*attestation verification failed*' }
        else { (& $invoke).state | Should -Be 'published' }
        Test-Path Env:GH_TOKEN | Should -BeFalse
        @($global:PublisherTestVerificationTokens | Where-Object { $_ -cne 'fixture-read-credential' }).Count | Should -Be 0
        @($global:PublisherTestWriteTokens | Where-Object { $_ -ne '' }).Count | Should -Be 0
    }

    It 'restores the App credential after verification and uses it only for writes' {
        (& $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false).state | Should -Be 'published'
        $global:PublisherTestVerifyCount | Should -Be 2
        @($global:PublisherTestVerificationTokens | Where-Object { $_ -cne 'fixture-read-credential' }).Count | Should -Be 0
        @($global:PublisherTestWriteTokens | Where-Object { $_ -cne 'fixture-app-credential' }).Count | Should -Be 0
        $env:GH_TOKEN | Should -BeExactly 'fixture-app-credential'
    }

    It 'uses the existing CLI authentication when a separate read credential is absent' {
        Remove-Item Env:AZD_RELEASE_READ_TOKEN
        (& $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false).state | Should -Be 'published'
        @($global:PublisherTestVerificationTokens | Where-Object { $_ -cne 'fixture-app-credential' }).Count | Should -Be 0
        $env:GH_TOKEN | Should -BeExactly 'fixture-app-credential'
    }

    It 'stops before writes and restores the App credential when verification fails at boundary <_>' -ForEach @(1, 2) {
        $global:PublisherTestFailVerifyAt = $_
        { & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false } |
            Should -Throw '*attestation verification failed*'
        $global:PublisherTestWriteTokens.Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
        $env:GH_TOKEN | Should -BeExactly 'fixture-app-credential'
    }

    It 'rejects tampered prepared <Attack> before any write' -ForEach @(
        @{ Attack = 'revision'; Mode = 'sourceRevision'; Error = '*Prepared lock provenance does not match*' },
        @{ Attack = 'revision array'; Mode = 'sourceRevisionArray'; Error = '*JSON*' },
        @{ Attack = 'version array'; Mode = 'versionArray'; Error = '*JSON*' },
        @{ Attack = 'repository array'; Mode = 'sourceRepositoryArray'; Error = '*JSON*' },
        @{ Attack = 'managed bytes'; Mode = 'bytes'; Error = '*Managed file drift*' },
        @{ Attack = 'managed bytes and forged lock hashes'; Mode = 'forged'; Error = '*different managed content*' },
        @{ Attack = 'unmanaged paths'; Mode = 'extra'; Error = '*Prepared branch tree does not match*' },
        @{ Attack = 'unapproved baseline'; Mode = 'baseline'; Error = '*Prepared branch tree does not match*' },
        @{ Attack = 'unrelated lock component'; Mode = 'otherComponent'; Error = '*Prepared branch tree does not match*' }
    ) {
        $prepared = & (Join-Path $script:repoRoot 'tooling/Update-AzdPortfolio.ps1') `
            -Component deployment-validation -Version 0.3.3 -ExpectedRevision $expectedRevision -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Operation Prepare -Confirm:$false
        & git -C $consumer checkout $prepared.branch 2>&1 | Out-Null
        $lockPath = Join-Path $consumer 'azd-components.lock.json'
        $lock = Get-Content $lockPath -Raw | ConvertFrom-Json
        $locked = $lock.components[0]
        if ($Mode -eq 'sourceRevision') { $locked.sourceRevision = 'a' * 40 }
        elseif ($Mode.EndsWith('Array')) { $field = $Mode -replace 'Array$', ''; $locked.$field = @($locked.$field) }
        elseif ($Mode -eq 'baseline') { $lock | Add-Member -NotePropertyName baseline -NotePropertyValue '2099.01' -Force }
        elseif ($Mode -eq 'otherComponent') {
            $other = $locked | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $other.id = 'unrelated-component'
            foreach ($file in $other.files) { $file.target = 'unrelated/' + $file.target }
            $lock.components += $other
        }
        elseif ($Mode -eq 'extra') { Set-Content (Join-Path $consumer 'unexpected.txt') 'Unmanaged fixture change' }
        else {
            $managedPath = Join-Path $consumer $locked.files[0].target
            Add-Content $managedPath '# Tampered prepared content'
            if ($Mode -eq 'forged') { $locked.files[0].sha256 = (Get-FileHash $managedPath -Algorithm SHA256).Hash.ToLowerInvariant() }
        }
        $lock | ConvertTo-Json -Depth 30 | Set-Content $lockPath
        & git -C $consumer add --all
        & git -C $consumer commit --amend --no-edit | Out-Null
        { & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -PreparedBranchesOnly -Confirm:$false } |
            Should -Throw $Error
        $global:PublisherTestWriteTokens.Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
    }

    It 'rejects a forged two-parent merge even when its first parent and tree are approved' {
        $prepared = & (Join-Path $script:repoRoot 'tooling/Update-AzdPortfolio.ps1') `
            -Component deployment-validation -Version 0.3.3 -ExpectedRevision $expectedRevision -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Operation Prepare -Confirm:$false
        $tree = (& git -C $consumer rev-parse "$($prepared.commit)^{tree}").Trim()
        $otherParent = (& git -C $consumer commit-tree $tree -m 'Unrelated fixture history').Trim()
        $merge = (& git -C $consumer commit-tree $tree -p $consumerHead -p $otherParent -m 'Forged identical-tree merge').Trim()
        & git -C $consumer update-ref "refs/heads/$($prepared.branch)" $merge
        (& git -C $consumer rev-parse "$merge^1").Trim() | Should -BeExactly $consumerHead
        (& git -C $consumer rev-parse "$merge^{tree}").Trim() | Should -BeExactly $tree
        { & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -PreparedBranchesOnly -Confirm:$false } |
            Should -Throw '*exactly one parent equal to the current live default branch*'
        $global:PublisherTestVerifyCount | Should -Be 1
        $global:PublisherTestWriteTokens.Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
    }

    It 'refuses a prepared branch moved during last-mile release verification' {
        $global:PublisherTestMoveBranchAtVerify = $true
        { & $publisher @publishEvidence -Component deployment-validation -Version 0.3.3 -ConsumerId consumer-one `
            -PortfolioRoot $portfolioRoot -WorktreeRoot $worktrees -RegistryPath $registryPath -Confirm:$false } |
            Should -Throw '*Prepared branch moved during release verification*'
        $global:PublisherTestWriteTokens.Count | Should -Be 0
        $global:PublisherTestPullRequests.Count | Should -Be 0
    }

    It 'contains only expected-absent branch creation and draft pull-request publication commands' {
        $source = Get-Content -LiteralPath $publisher -Raw
        $source | Should -Match "--force-with-lease=refs/heads/"
        $source | Should -Match "'pr', 'create', '--draft'"
        $source | Should -Match ([regex]::Escape('"$($prepared.commit):refs/heads/$($prepared.branch)"'))
        $source | Should -Not -Match "(?s)'push'[^)]*'--force'"
        $source | Should -Not -Match "'pr',\s*'(?:merge|review)'"
    }

    It 'can publish an exact branch that was prepared before publication credentials are used' {
        $updater = Join-Path $script:repoRoot 'tooling/Update-AzdPortfolio.ps1'
        $prepared = @(& $updater `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -Operation Prepare `
                -Confirm:$false)

        $prepared.Count | Should -Be 1
        $prepared[0].state | Should -Be 'prepared'

        $published = @(& $publisher @publishEvidence `
                -Component deployment-validation `
                -Version 0.3.3 `
                -ConsumerId consumer-one `
                -PortfolioRoot $portfolioRoot `
                -WorktreeRoot $worktrees `
                -RegistryPath $registryPath `
                -PreparedBranchesOnly `
                -Confirm:$false)

        $published.Count | Should -Be 1
        $published[0].state | Should -Be 'published'
        $published[0].commit | Should -Be $prepared[0].commit
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

Describe 'Credential-separated portfolio update workflow' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:updateWorkflow = Join-Path $script:repoRoot '.github/workflows/portfolio-updates.yml'
    }

    It 'prepares before minting a narrowly scoped App token and only publishes prepared branches' {
        $source = Get-Content -LiteralPath $updateWorkflow -Raw
        $source | Should -Match '(?m)^\s*schedule:'
        $source | Should -Match '(?m)^\s*workflow_dispatch:'
        $source | Should -Match '(?m)^permissions:\r?\n\s+contents: read$'
        $source | Should -Match 'environment: portfolio-updates'
        $source | Should -Match 'persist-credentials: false'
        $source | Should -Match '(?m)^\s{2}prepare:'
        $source | Should -Match '(?m)^\s{2}publish:'
        $source | Should -Match 'git\s+-C\s+\$consumerRoot\s+bundle create'
        $source | Should -Match 'actions/upload-artifact@[0-9a-f]{40}'
        $source | Should -Match 'actions/download-artifact@[0-9a-f]{40}'
        $source | Should -Match 'actions/create-github-app-token@[0-9a-f]{40}'
        $source | Should -Match 'permission-contents: write'
        $source | Should -Match 'permission-pull-requests: write'
        $source | Should -Match '-PreparedBranchesOnly'
        $source.IndexOf('-Operation Prepare') | Should -BeLessThan $source.IndexOf('actions/create-github-app-token@')
        $source.IndexOf('actions/upload-artifact@', $source.IndexOf('-Operation Prepare')) | Should -BeLessThan $source.IndexOf('actions/create-github-app-token@')
        $source.IndexOf('actions/create-github-app-token@') | Should -BeLessThan $source.IndexOf('-PreparedBranchesOnly')
        $source | Should -Not -Match '(?i)az login|connect-azaccount|connect-mggraph'
    }
}
