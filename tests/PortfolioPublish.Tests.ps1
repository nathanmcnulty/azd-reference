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
        $remoteUri = ([uri] $remote).AbsoluteUri
        & git -C $consumer config "url.$remoteUri.insteadOf" $repository
        & git -C $consumer remote set-url --push origin 'https://github.com/example/divergent-push-target.git'
        New-Item -ItemType Directory -Path (Join-Path $consumer 'scripts') | Out-Null
        Set-Content -LiteralPath (Join-Path $consumer 'scripts/Test-Repository.ps1') -Encoding utf8NoBOM -Value "'validated' | Write-Output"
        Set-Content -LiteralPath (Join-Path $consumer 'README.md') -Encoding utf8NoBOM -Value '# Consumer fixture'
        & git -C $consumer add --all
        & git -C $consumer commit -m 'Consumer fixture' | Out-Null
        & git -C $consumer push $repository main | Out-Null
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

        $fakeBin = Join-Path $caseRoot 'fake-bin'
        New-Item -ItemType Directory -Path $fakeBin | Out-Null
        if ([System.OperatingSystem]::IsWindows()) {
            $fakeGh = Join-Path $fakeBin 'gh.cmd'
            @'
@echo off
if "%1"=="auth" exit /b 0
if "%1"=="pr" echo https://github.com/example/consumer-one/pull/1& exit /b 0
exit /b 1
'@ | Set-Content -LiteralPath $fakeGh -Encoding ascii
        }
        else {
            $fakeGh = Join-Path $fakeBin 'gh'
            @'
#!/bin/sh
if [ "$1" = "auth" ]; then exit 0; fi
if [ "$1" = "pr" ]; then echo https://github.com/example/consumer-one/pull/1; exit 0; fi
exit 1
'@ | Set-Content -LiteralPath $fakeGh -Encoding utf8NoBOM
            & chmod +x $fakeGh
        }
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

    It 'ignores a divergent pushurl and publishes only to the registered repository' {
        $previousPath = $env:PATH
        try {
            $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $previousPath
            $result = @(& $publisher `
                    -Component deployment-validation `
                    -Version 0.3.3 `
                    -PortfolioRoot $portfolioRoot `
                    -WorktreeRoot $worktrees `
                    -RegistryPath $registryPath `
                    -Confirm:$false)

            $result[0].state | Should -Be 'published'
            $result[0].pullRequest | Should -Be 'https://github.com/example/consumer-one/pull/1'
            (& git -C $consumer remote get-url --push origin).Trim() | Should -Be 'https://github.com/example/divergent-push-target.git'
            $published = @(& git ls-remote --heads $remote "refs/heads/$($result[0].branch)")
            $published.Count | Should -Be 1
            ($published[0] -split '\s+')[0] | Should -Be $result[0].commit
        }
        finally {
            $env:PATH = $previousPath
        }
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

        $previousPath = $env:PATH
        try {
            $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $previousPath
            $result = @(& $publisher `
                    -Component deployment-validation `
                    -Version 0.3.3 `
                    -PortfolioRoot $portfolioRoot `
                    -WorktreeRoot $worktrees `
                    -RegistryPath $registryPath `
                    -Confirm:$false)

            (& git -C $consumer rev-parse "$($result[0].branch)^").Trim() | Should -Be $liveMain
        }
        finally {
            $env:PATH = $previousPath
        }
    }

    It 'rejects an existing live deterministic update branch before preparation' {
        $branch = 'codex/update-consumer-one-deployment-validation-v0.3.3'
        & git -C $consumer push $repository "HEAD:refs/heads/$branch" | Out-Null

        $previousPath = $env:PATH
        try {
            $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $previousPath
            { & $publisher `
                    -Component deployment-validation `
                    -Version 0.3.3 `
                    -PortfolioRoot $portfolioRoot `
                    -WorktreeRoot $worktrees `
                    -RegistryPath $registryPath `
                    -Confirm:$false } | Should -Throw '*Remote update branch already exists*'
            @(& git -C $consumer branch --list $branch).Count | Should -Be 0
        }
        finally {
            $env:PATH = $previousPath
        }
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
