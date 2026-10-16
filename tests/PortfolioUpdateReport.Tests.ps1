Describe 'Read-only portfolio update readiness projection' {
    BeforeAll {
        $script:reporter = Join-Path $PSScriptRoot '../tooling/Get-AzdPortfolioUpdateReport.ps1'
    }
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $caseRoot | Out-Null
        $statusPath = Join-Path $caseRoot 'status.json'
        $planPath = Join-Path $caseRoot 'plan.json'
        $selectionPath = Join-Path $caseRoot 'selection.json'
        $summaryPath = Join-Path $caseRoot 'summary.md'
        $entry = [ordered]@{
            consumer = 'consumer-one'
            repository = 'https://github.com/example/consumer-one'
            component = 'example-component'
            installedVersion = '1.2.3'
            desiredVersion = '1.2.3'
            state = 'current'
            findings = @()
        }
        $selection = [ordered]@{ state = 'completed'; consumer = 'consumer-one'; excludeOpenPullRequests = $true; error = $null; suppressed = @() }
        $selection | ConvertTo-Json -Depth 8 | Set-Content $selectionPath
        '[]' | Set-Content $planPath
        $reportArguments = @{ StatusPath = $statusPath; CandidatesPath = $planPath; SelectionDiagnosticsPath = $selectionPath; ConsumerId = 'consumer-one'; SummaryPath = $summaryPath }
    }

    It 'explains current zero-candidate results and limits every readiness claim' {
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $selection | ConvertTo-Json -Depth 8 | Set-Content $selectionPath
        $before = Get-FileHash $statusPath, $planPath, $selectionPath
        $report = (& $script:reporter @reportArguments -AsJson) | ConvertFrom-Json
        $report.candidateCount | Should -Be 0
        $report.selectionState | Should -Be 'completed'
        $report.records[0].decision | Should -Be 'current'
        $report.records[0].localProvenance.desiredTagAndManifest | Should -Be 'valid'
        $report.records[0].localProvenance.installedRevision | Should -Be 'matchesTag'
        $report.evidenceLimits.sourceAvailability | Should -Match '^notAssessed:'
        $report.evidenceLimits.signedReleaseAcceptance | Should -Match '^unverified:'
        $report.evidenceLimits.appReadiness | Should -Match '^unknown:'
        $report.evidenceLimits.reviewerReadiness | Should -Match '^unknown:'
        $report.evidenceLimits.publicationProof | Should -Match '^notEstablished:'
        Get-Content $summaryPath -Raw | Should -Match 'does not prove preparation or App publication'
        (Get-FileHash $statusPath, $planPath, $selectionPath).Hash | Should -Be $before.Hash
    }

    It 'directs versionAhead to registry review and never downgrade' {
        $entry.state = 'versionAhead'
        $entry.installedVersion = '2.0.0'
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $report = & $script:reporter @reportArguments
        $report.records[0].decision | Should -Be 'registryPinReview'
        $report.records[0].nextActions -join ' ' | Should -Match 'registry pin.*never downgrade'
        $report.candidateCount | Should -Be 0
    }

    It 'retains exact tag and revision blockers while selection remains failed' {
        $entry.state = 'outdated'
        $entry.installedVersion = '1.2.2'
        $entry.findings = @('desiredReleaseTagMissing:example-component@1.2.3', 'installedReleaseTagInvalid:example-component@1.2.2', 'installedSourceRevisionMismatch:example-component@1.2.2')
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $selection.state = 'failed'
        $selection.error = 'Consumer is not safe to update.'
        $selection | ConvertTo-Json -Depth 8 | Set-Content $selectionPath
        $report = & $script:reporter @reportArguments
        $report.selectionState | Should -Be 'failed'
        $report.candidateCount | Should -BeNullOrEmpty
        $report.records[0].decision | Should -Be 'blocked'
        $report.records[0].findings | Should -Be $entry.findings
        $report.records[0].localProvenance.desiredTag | Should -Be 'component/example-component/v1.2.3'
        $report.records[0].localProvenance.desiredTagAndManifest | Should -Be 'missing'
        $report.records[0].localProvenance.installedTagAndManifest | Should -Be 'invalid'
        $report.records[0].localProvenance.installedRevision | Should -Be 'mismatch'
        $report.records[0].nextActions -join ' ' | Should -Match 'component/example-component/v1.2.3'
        Get-Content $summaryPath -Raw | Should -Match 'not a successful zero-candidate result'
    }

    It 'reports absent adoption and projects the final candidate unchanged' {
        $entry.state = 'notAdopted'
        $entry.installedVersion = $null
        $entry.findings = @('pendingAdoption', 'solutionFileRecommended:README.md')
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $candidate = @{ consumer = 'consumer-one'; component = 'example-component'; version = '1.2.3'; branch = 'codex/update-consumer-one-example-component-v1.2.3' }
        ConvertTo-Json -InputObject @($candidate) | Set-Content $planPath
        $report = & $script:reporter @reportArguments
        $report.candidateCount | Should -Be 1
        $report.records[0].decision | Should -Be 'candidate'
        $report.records[0].reasons -join ' ' | Should -Match 'not been adopted'
        $report.candidates[0].branch | Should -Be $candidate.branch
        $report.records[0].localProvenance.installedTagAndManifest | Should -Be 'notApplicable'
    }

    It 'never infers existing PR suppression from an empty plan alone' {
        Remove-Item $selectionPath
        $entry.state = 'outdated'
        $entry.installedVersion = '1.2.2'
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $report = & $script:reporter @reportArguments
        $report.records[0].decision | Should -Be 'notSelected'
        $report.records[0].existingPullRequests.Count | Should -Be 0
        $report.records[0].reasons -join ' ' | Should -Match 'suppression is not established'
    }

    It 'uses exact PR evidence only after successful exclusion: <state>, <exclude>, <version>' -ForEach @(
        @{ state = 'completed'; exclude = $true; version = '1.2.3'; expected = 'existingPullRequest' },
        @{ state = 'failed'; exclude = $true; version = '1.2.3'; expected = 'notSelected' },
        @{ state = 'completed'; exclude = 'true'; version = '1.2.3'; expected = 'notSelected' },
        @{ state = 'completed'; exclude = $false; version = '1.2.3'; expected = 'notSelected' },
        @{ state = 'completed'; exclude = $true; version = '9.9.9'; expected = 'notSelected' }
    ) {
        $entry.state = 'outdated'
        $entry.installedVersion = '1.2.2'
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $selection.state = $state
        $selection.excludeOpenPullRequests = $exclude
        $selection.suppressed = @(@{
            consumer = 'consumer-one'; component = 'example-component'; version = $version
            repository = 'https://github.com/example/consumer-one'; base = 'main'
            branch = "codex/update-consumer-one-example-component-v$version"
            title = "chore: update example-component to $version"
            pullRequestUrls = @('https://github.com/example/consumer-one/pull/7')
        })
        $selection | ConvertTo-Json -Depth 8 | Set-Content $selectionPath
        $report = & $script:reporter @reportArguments
        $report.records[0].decision | Should -Be $expected
        if ($expected -eq 'existingPullRequest') {
            $report.records[0].existingPullRequests[0].base | Should -Be 'main'
            Get-Content $summaryPath -Raw | Should -Match 'https://github.com/example/consumer-one/pull/7'
        }
    }

    It 'excludes unrelated unavailable records from a selected-consumer report' {
        @($entry, @{ consumer = 'unrelated-consumer'; state = 'checkoutUnavailable'; findings = @('checkoutUnavailable') }) |
            ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $report = & $script:reporter @reportArguments
        $report.records.Count | Should -Be 1
        $report.records[0].consumer | Should -Be 'consumer-one'
        Get-Content $summaryPath -Raw | Should -Not -Match 'unrelated-consumer|checkoutUnavailable'
    }

    It 'keeps incomplete evidence unknown rather than claiming zero candidates' {
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        Remove-Item $planPath
        $report = & $script:reporter @reportArguments
        $report.selectionState | Should -Be 'unknown'
        $report.candidateCount | Should -BeNullOrEmpty
    }

    It 'does not infer suppression from incomplete observation rows' {
        $entry.state = 'outdated'
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $selection.suppressed = @($null, @{ consumer = 'consumer-one'; component = 'example-component'; version = '1.2.3' })
        $selection | ConvertTo-Json -Depth 8 | Set-Content $selectionPath
        $report = & $script:reporter @reportArguments
        $report.records[0].decision | Should -Be 'notSelected'
        $report.records[0].existingPullRequests.Count | Should -Be 0
    }

    It 'does not treat a stale plan as completed when the selector receipt is <receipt>' -ForEach @(
        @{ receipt = 'missing' }, @{ receipt = 'malformed' }, @{ receipt = 'wrongScope' }, @{ receipt = 'unknownState' }
    ) {
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        switch ($receipt) {
            'missing' { Remove-Item $selectionPath }
            'malformed' { '{broken' | Set-Content $selectionPath }
            'wrongScope' { $selection.consumer = 'another-consumer'; $selection | ConvertTo-Json | Set-Content $selectionPath }
            'unknownState' { $selection.state = 'pending'; $selection | ConvertTo-Json | Set-Content $selectionPath }
        }
        $report = & $script:reporter @reportArguments
        $report.selectionState | Should -Be 'unknown'
        $report.candidateCount | Should -BeNullOrEmpty
        $report.candidates.Count | Should -Be 0
    }

    It 'does not claim installed provenance when status short-circuited on drift' {
        $entry.state = 'drifted'
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $report = & $script:reporter @reportArguments
        $report.records[0].localProvenance.installedTagAndManifest | Should -Be 'notAssessed'
        $report.records[0].localProvenance.installedRevision | Should -Be 'notAssessed'
    }

    It 'handles a component-free consumer without claiming release provenance' {
        $entry.component = $null
        $entry.desiredVersion = $null
        $entry.installedVersion = $null
        $entry | ConvertTo-Json -Depth 8 | Set-Content $statusPath
        $report = & $script:reporter @reportArguments
        $report.records[0].localProvenance.desiredTagAndManifest | Should -Be 'notApplicable'
        $report.records[0].decision | Should -Be 'current'
    }
}
