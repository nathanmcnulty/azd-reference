Describe 'Scheduled GitHub governance audit credential' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/github-governance-audit.yml') -Raw
        $script:standard = Get-Content -LiteralPath (Join-Path $script:repoRoot 'standards/github-governance.md') -Raw
        $script:runbook = Get-Content -LiteralPath (Join-Path $script:repoRoot 'docs/github-governance-audit.md') -Raw
    }

    It 'uses the current SHA-pinned GitHub App token action instead of a PAT' {
        $script:workflow | Should -Match '(?m)^\s+uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3\.2\.0$'
        $script:workflow | Should -Match 'AZD_GOVERNANCE_APP_CLIENT_ID'
        $script:workflow | Should -Match 'AZD_GOVERNANCE_APP_PRIVATE_KEY'
        $script:workflow | Should -Not -Match 'AZD_GOVERNANCE_READ_TOKEN'
        $script:standard | Should -Match 'dedicated personal-account GitHub\s+App'
    }

    It 'limits the short-lived token to registered repositories and read permissions' {
        $script:workflow | Should -Match 'repositories: \$\{\{ steps\.repository-scope\.outputs\.names \}\}'
        $script:workflow | Should -Match 'permission-administration: read'
        $script:workflow | Should -Match 'permission-contents: read'
        $script:workflow | Should -Match 'GH_TOKEN: \$\{\{ steps\.governance-token\.outputs\.token \}\}'
        $script:workflow | Should -Match "if: github\.ref == 'refs/heads/main'"
        $script:workflow | Should -Match 'environment: github-governance-audit'
    }

    It 'documents the selected-repository installation and private-key lifecycle' {
        $script:runbook | Should -Match 'Install only on the repositories in the governance registry'
        $script:runbook | Should -Match 'Environment secret `AZD_GOVERNANCE_APP_PRIVATE_KEY`'
        $script:runbook | Should -Match 'restricted to the `main` branch'
        $script:runbook | Should -Match 'rotate it deliberately'
        $script:runbook | Should -Match 'never put it in workflow output or repository files'
    }
}
