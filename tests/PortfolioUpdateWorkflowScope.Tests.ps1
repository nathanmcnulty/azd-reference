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
