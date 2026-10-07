Describe 'Agent backlog contract and tooling' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:validator = Join-Path $script:repoRoot 'tooling/Test-AzdBacklog.ps1'
        $script:exporter = Join-Path $script:repoRoot 'tooling/Export-AzdBacklogMarkdown.ps1'
        $script:statusTool = Join-Path $script:repoRoot 'tooling/Get-AzdBacklogStatus.ps1'
        $script:revision = '0123456789abcdef0123456789abcdef01234567'

        function New-BacklogItem {
            param(
                [Parameter(Mandatory)][string] $Id,
                [string] $Status = 'proposed',
                [string[]] $Dependencies = @(),
                [string[]] $Evidence = @(),
                [string] $Authorization = 'local-only',
                [AllowNull()][object] $Claim = $null,
                [string] $Title = 'Test item'
            )

            [ordered]@{
                id = $Id
                title = $Title
                kind = 'verification'
                priority = 'P1'
                status = $Status
                wave = 0
                problem = 'The test condition needs evidence.'
                scope = @('Exercise the bounded test condition.')
                acceptance = @('The expected validation result is observed.')
                validation = @('Record the explicit test result.')
                dependencies = @($Dependencies)
                authorization = $Authorization
                components = @('backlog-tooling')
                sources = @('tests/Backlog.Tests.ps1')
                evidence = @($Evidence)
                blocker = $null
                claim = $Claim
            }
        }

        function New-Backlog {
            param(
                [Parameter(Mandatory)][string] $Repository,
                [Parameter(Mandatory)][object[]] $Items
            )

            [ordered]@{
                schemaVersion = '1.0.0'
                repository = $Repository
                sourceRevision = $script:revision
                capturedAt = '2026-10-03'
                items = @($Items)
            }
        }

        function Write-BacklogFixture {
            param(
                [Parameter(Mandatory)][string] $Path,
                [Parameter(Mandatory)] $Backlog
            )

            $Backlog | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $Path -Encoding utf8NoBOM
        }

        function New-ValidClaim {
            [ordered]@{
                owner = 'test-agent'
                worktree = 'E:/test-worktree'
                baseRevision = $script:revision
                startedAt = '2026-10-03T12:00:00Z'
            }
        }
    }

    It 'validates standalone and staged repositories with cross dependencies and aggregates them' {
        $standalonePath = Join-Path $TestDrive 'standalone.json'
        $stagedPath = Join-Path $TestDrive 'staged.json'
        Write-BacklogFixture -Path $standalonePath -Backlog (New-Backlog `
                -Repository 'nathanmcnulty/azd-standalone' `
                -Items @(
                    New-BacklogItem -Id 'BASE-001' -Status done -Evidence @('Validated locally.')
                ))
        Write-BacklogFixture -Path $stagedPath -Backlog (New-Backlog `
                -Repository 'nathanmcnulty/azd-work-in-progress/staged-solution' `
                -Items @(
                    New-BacklogItem -Id 'STAGED-001' -Status ready `
                        -Dependencies @('nathanmcnulty/azd-standalone:BASE-001')
                ))

        $validation = & $script:validator -Paths $standalonePath, $stagedPath
        $validation.valid | Should -BeTrue
        $validation.repositories | Should -Be 2
        $validation.items | Should -Be 2

        $rows = @(& $script:statusTool -Paths $standalonePath, $stagedPath)
        $rows.Count | Should -Be 2
        @($rows.id) | Should -Be @('BASE-001', 'STAGED-001')
        $rows[1].dependencies | Should -Contain 'nathanmcnulty/azd-standalone:BASE-001'
        $rows[1].path | Should -Be ([IO.Path]::GetFullPath($stagedPath))

        $ready = @(& $script:statusTool -Paths $standalonePath, $stagedPath -ReadyOnly)
        $ready.Count | Should -Be 1
        $ready[0].id | Should -Be 'STAGED-001'
    }

    It 'rejects a dependency cycle' {
        $path = Join-Path $TestDrive 'cycle.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog -Repository 'nathanmcnulty/cycle' -Items @(
                New-BacklogItem -Id 'CYCLE-001' -Dependencies @('CYCLE-002')
                New-BacklogItem -Id 'CYCLE-002' -Dependencies @('CYCLE-001')
            ))

        { & $script:validator -Paths $path } | Should -Throw '*Dependency cycle*'
    }

    It 'rejects an unresolved cross-repository dependency' {
        $path = Join-Path $TestDrive 'unresolved.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog `
                -Repository 'nathanmcnulty/unresolved' `
                -Items @(
                    New-BacklogItem -Id 'UNRESOLVED-001' `
                        -Dependencies @('nathanmcnulty/missing:MISSING-001')
                ))

        { & $script:validator -Paths $path } | Should -Throw '*requires that repository backlog in -Paths*'
    }

    It 'rejects ready work with an unmet dependency' {
        $path = Join-Path $TestDrive 'ready-unmet.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog -Repository 'nathanmcnulty/ready-unmet' -Items @(
                New-BacklogItem -Id 'DEP-001'
                New-BacklogItem -Id 'READY-001' -Status ready -Dependencies @('DEP-001')
            ))

        { & $script:validator -Paths $path } | Should -Throw "*status 'ready'*not done*"
    }

    It 'rejects in-progress work with an unmet dependency' {
        $path = Join-Path $TestDrive 'in-progress-unmet.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog -Repository 'nathanmcnulty/in-progress-unmet' -Items @(
                New-BacklogItem -Id 'DEP-001'
                New-BacklogItem -Id 'ACTIVE-001' -Status in-progress `
                    -Dependencies @('DEP-001') -Claim (New-ValidClaim)
            ))

        { & $script:validator -Paths $path } | Should -Throw "*status 'in-progress'*not done*"
    }

    It 'rejects done work with an unmet dependency' {
        $path = Join-Path $TestDrive 'done-unmet.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog -Repository 'nathanmcnulty/done-unmet' -Items @(
                New-BacklogItem -Id 'DEP-001'
                New-BacklogItem -Id 'DONE-001' -Status done `
                    -Dependencies @('DEP-001') -Evidence @('Completion evidence.')
            ))

        { & $script:validator -Paths $path } | Should -Throw "*status 'done'*not done*"
    }

    It 'rejects done work with blank evidence' {
        $path = Join-Path $TestDrive 'done-blank.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog `
                -Repository 'nathanmcnulty/done-blank' `
                -Items @(New-BacklogItem -Id 'DONE-001' -Status done))

        { & $script:validator -Paths $path } | Should -Throw '*requires evidence*'
    }

    It 'rejects an in-progress item with a blank claim' {
        $path = Join-Path $TestDrive 'claim-blank.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog `
                -Repository 'nathanmcnulty/claim-blank' `
                -Items @(New-BacklogItem -Id 'ACTIVE-001' -Status in-progress -Claim $null))

        { & $script:validator -Paths $path } | Should -Throw '*requires a claim*'
    }

    It 'rejects duplicate item IDs without case sensitivity' {
        $path = Join-Path $TestDrive 'duplicate.json'
        Write-BacklogFixture -Path $path -Backlog (New-Backlog -Repository 'nathanmcnulty/duplicate' -Items @(
                New-BacklogItem -Id 'DUP-001'
                New-BacklogItem -Id 'dup-001'
            ))

        { & $script:validator -Paths $path } | Should -Throw '*Duplicate item ID*'
    }

    It 'renders hostile Markdown as inert text and detects a stale generated view' {
        $path = Join-Path $TestDrive 'hostile.json'
        $outputPath = Join-Path $TestDrive 'backlog.md'
        $hostile = '<script>alert(1)</script> *bold* _em_ [link](https://example.com/a_b) ![image](https://example.com/x.png) `code`' + " validator's café #heading &#39;"
        Write-BacklogFixture -Path $path -Backlog (New-Backlog -Repository 'nathanmcnulty/hostile' -Items @(
                New-BacklogItem -Id 'HOST-001' -Title $hostile -Authorization publication
                New-BacklogItem -Id 'HOST-002' -Status ready -Title 'Eligible local review'
            ))

        & $script:exporter -Path $path -OutputPath $outputPath | Out-Null
        { & $script:exporter -Path $path -OutputPath $outputPath -Check } | Should -Not -Throw
        $markdown = Get-Content -LiteralPath $outputPath -Raw
        $markdown | Should -Not -Match ([regex]::Escape('<script>'))
        $markdown | Should -Not -Match ([regex]::Escape('![image]'))
        $markdown | Should -Not -Match ([regex]::Escape('[link](https://'))
        $markdown | Should -Match ([regex]::Escape('&lt;script&gt;'))
        $markdown | Should -Match ([regex]::Escape('&ast;bold&ast;'))
        $markdown | Should -Match ([regex]::Escape('https&colon;//example.com'))
        $markdown | Should -Match ([regex]::Escape('validator&#39;s'))
        $markdown | Should -Match ([regex]::Escape('&num;heading'))
        $markdown | Should -Match ([regex]::Escape('&amp;&num;39;'))
        [Net.WebUtility]::HtmlDecode($markdown) | Should -Match ([regex]::Escape("validator's café"))
        ([regex]::Matches($markdown, '\*\*Agent handoff prompt:\*\*')).Count | Should -Be 1
        ([regex]::Matches($markdown, '\*\*Review and authorization note:\*\*')).Count | Should -Be 1

        Add-Content -LiteralPath $outputPath -Encoding utf8NoBOM -Value 'stale'
        { & $script:exporter -Path $path -OutputPath $outputPath -Check } |
            Should -Throw '*out of date*'
    }
}
