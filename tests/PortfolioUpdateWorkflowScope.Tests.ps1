Describe 'Bounded portfolio workflow dispatch' {
    BeforeAll {
        $source = Get-Content (Join-Path $PSScriptRoot '../.github/workflows/portfolio-updates.yml') -Raw
        $scopeBlock = [regex]::Match($source, '(?s)- name: Validate requested execution scope.*?run: \|\r?\n(?<code>.*?)(?=\r?\n      - name:)').Groups['code'].Value
        $scopeCode = [scriptblock]::Create(($scopeBlock -replace '(?m)^          ', ''))
    }
    BeforeEach {
        $saved = @{}
        foreach ($name in 'EVENT_NAME','SELECTED_CONSUMER','PLAN_ONLY','GITHUB_OUTPUT') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
        $env:GITHUB_OUTPUT = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $env:EVENT_NAME = 'workflow_dispatch'
        $env:SELECTED_CONSUMER = 'consumer-one'
        $env:PLAN_ONLY = 'true'
    }
    AfterEach {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
    It 'defaults manual dispatch to a required exact consumer and plan-only' {
        $source | Should -Match '(?s)consumer:.*?required: true.*?type: string'
        $source | Should -Match '(?s)plan_only:.*?required: true.*?default: true.*?type: boolean'
        & $scopeCode
        Get-Content $env:GITHUB_OUTPUT | Should -Be 'publish-allowed=false'
    }
    It 'permits explicitly non-plan manual runs' {
        $env:PLAN_ONLY = 'false'
        & $scopeCode
        Get-Content $env:GITHUB_OUTPUT | Should -Be 'publish-allowed=true'
    }
    It 'preserves existing automatic publication eligibility for <_>' -ForEach @('schedule','push') {
        $env:EVENT_NAME = $_
        $env:SELECTED_CONSUMER = ''
        $env:PLAN_ONLY = ''
        & $scopeCode
        Get-Content $env:GITHUB_OUTPUT | Should -Be 'publish-allowed=true'
    }
    It 'rejects invalid manual selectors before allowing downstream jobs: <_>' -ForEach @('', '*', 'Consumer-one', "consumer-one`n", 'consumer-one,consumer-two') {
        $env:SELECTED_CONSUMER = $_
        { & $scopeCode } | Should -Throw '*exact registered consumer ID*'
        Test-Path $env:GITHUB_OUTPUT | Should -BeFalse
    }
    It 'rejects absent or invalid manual plan-only values: <_>' -ForEach @('', 'TRUE', 'yes') {
        $env:PLAN_ONLY = $_
        { & $scopeCode } | Should -Throw '*explicit plan-only boolean*'
    }
    It 'gates all downstream jobs on explicit publication eligibility' {
        foreach ($job in 'prepare','publish','configuration-required') {
            $block = [regex]::Match($source, "(?s)\n  ${job}:.*?(?=\n  [a-z-]+:|\z)").Value
            $block | Should -Match "if:.*needs.discover.outputs.publish-allowed == 'true'"
        }
    }
    It 'checks trusted candidate scope before token creation and again before publication' {
        $publish = $source.Substring($source.IndexOf("`n  publish:"))
        $publish.IndexOf('Assert-AzdPortfolioUpdateScope.ps1') | Should -BeLessThan $publish.IndexOf('actions/create-github-app-token@')
        $publish.LastIndexOf('Assert-AzdPortfolioUpdateScope.ps1') | Should -BeGreaterThan $publish.IndexOf('actions/create-github-app-token@')
        $publish.LastIndexOf('Assert-AzdPortfolioUpdateScope.ps1') | Should -BeLessThan $publish.IndexOf('gh auth setup-git')
        ([regex]::Matches($source, '-PlanOnly:\(\$env:PLAN_ONLY -ceq ''true''\) -ForPublication')).Count | Should -Be 4
        $source | Should -Match 'CANDIDATE_JSON: \$\{\{ toJSON\(matrix\) \}\}'
        $source | Should -Not -Match "'\$\{\{ matrix\."
    }
}

Describe 'Portfolio workflow readiness reporting' {
    BeforeAll {
        $source = Get-Content (Join-Path $PSScriptRoot '../.github/workflows/portfolio-updates.yml') -Raw
        $reportBlock = [regex]::Match($source, '(?s)- name: Explain portfolio update readiness.*?(?=\r?\n      - name:)').Value
        $reportBody = [regex]::Match($reportBlock, '(?s)run: \|\r?\n(?<code>.*)').Groups['code'].Value
        $reportCode = [scriptblock]::Create(($reportBody -replace '(?m)^          ', ''))
    }
    BeforeEach {
        $saved = @{}
        foreach ($name in 'SELECTED_CONSUMER', 'GITHUB_STEP_SUMMARY') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $tooling = Join-Path $caseRoot 'portfolio/azd-reference/tooling'
        New-Item -ItemType Directory $tooling -Force | Out-Null
        Copy-Item (Join-Path $PSScriptRoot '../tooling/Get-AzdPortfolioUpdateReport.ps1') $tooling
        $env:SELECTED_CONSUMER = 'consumer-one'
        $env:GITHUB_STEP_SUMMARY = Join-Path $caseRoot 'job-summary.md'
        Push-Location $caseRoot
    }
    AfterEach {
        Pop-Location
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
    It 'runs reporting and artifact upload after candidate failure without swallowing that failure' {
        $reportBlock | Should -Match '(?m)^        if: always\(\)$'
        $source | Should -Match '(?s)- name: Upload portfolio report\s+if: always\(\).*?portfolio-update-selection.json.*?portfolio-update-readiness.json.*?portfolio-update-readiness.md'
        $candidateBlock = [regex]::Match($source, '(?s)- name: Audit and select explicitly approved updates.*?(?=\r?\n      - name:)').Value
        $candidateBlock | Should -Match '-DiagnosticsPath ./portfolio-update-selection.json'
        $candidateBlock | Should -Not -Match 'continue-on-error|catch|finally'
    }
    It 'renders unknown readiness when the audit never produced status' {
        & $reportCode
        Get-Content $env:GITHUB_STEP_SUMMARY -Raw | Should -Match 'readiness is unknown.*status audit did not produce'
        Test-Path ./portfolio-update-readiness.json | Should -BeFalse
    }
    It 'produces JSON and a useful summary after selection failed with an exact missing tag' {
        @{
            consumer = 'consumer-one'; repository = 'https://github.com/example/consumer-one'
            component = 'example-component'; desiredVersion = '1.2.3'; installedVersion = '1.2.2'
            state = 'outdated'; findings = @('desiredReleaseTagMissing:example-component@1.2.3')
        } | ConvertTo-Json | Set-Content ./portfolio-status.json
        @{ state = 'failed'; consumer = 'consumer-one'; excludeOpenPullRequests = $true; error = 'Original selection failure'; suppressed = @() } |
            ConvertTo-Json | Set-Content ./portfolio-update-selection.json
        & $reportCode
        $report = Get-Content ./portfolio-update-readiness.json -Raw | ConvertFrom-Json
        $report.selectionState | Should -Be 'failed'
        $report.candidateCount | Should -BeNullOrEmpty
        Get-Content $env:GITHUB_STEP_SUMMARY -Raw | Should -Match 'component/example-component/v1.2.3'
        Get-Content $env:GITHUB_STEP_SUMMARY -Raw | Should -Match 'Original selection failure'
        Test-Path ./portfolio-update-readiness.md | Should -BeTrue
        Test-Path ./portfolio-update-plan.json | Should -BeFalse
    }
}
