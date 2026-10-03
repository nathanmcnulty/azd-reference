BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'tooling/Azd.GitHubGovernance.psm1') -Force
}

Describe 'GitHub governance action inventory' {
    It 'rejects unpinned and unapproved actions in both step forms' -TestCases @(
        @{ content = "steps:`n  - uses: evil/payload@main" }
        @{ content = "steps:`n  - name: Deploy`n    uses: evil/payload@main" }
    ) {
        param($content)
        $result = Test-AzdGitHubWorkflowActionPolicy -WorkflowContents @(
            [pscustomobject]@{ path = 'workflow.yml'; content = $content }
        )
        $result.actionReferenceCount | Should -Be 1
        $result.state | Should -Be 'findings'
        @($result.findings | Where-Object { $_ -like 'unpinnedActionReference:*' }).Count | Should -Be 1
        @($result.findings | Where-Object { $_ -like 'actionNotExplicitlyAllowed:*' }).Count | Should -Be 1
    }

    It 'ignores shell text in either run block form and scans the following action' -TestCases @(
        @{ content = "steps:`n  - run: |`n      uses: evil/payload@main`n  - uses: actions/checkout@$('a' * 40)" }
        @{ content = "steps:`n  - name: Shell`n    run: |`n      - uses: evil/payload@main`n  - uses: actions/checkout@$('a' * 40)" }
    ) {
        param($content)
        $result = Test-AzdGitHubWorkflowActionPolicy -WorkflowContents @(
            [pscustomobject]@{ path = 'workflow.yml'; content = $content }
        )
        $result.actionReferenceCount | Should -Be 1
        $result.state | Should -Be 'current'
    }
}

Describe 'Owner recovery evidence' {
    It 'checks the administrator role rather than the App caller' {
        $ruleset = [pscustomobject]@{
            current_user_can_bypass = 'never'
            bypass_actors = @([pscustomobject]@{ actor_type = 'RepositoryRole'; actor_id = 5; bypass_mode = 'always' })
        }
        (Get-AzdGitHubOwnerRecoveryStatus -Ruleset $ruleset).state | Should -Be 'verified'
    }

    It 'explicitly requires manual verification when the read-only response omits bypass actors' {
        $result = Get-AzdGitHubOwnerRecoveryStatus -Ruleset ([pscustomobject]@{ id = 1 })
        $result.state | Should -Be 'manual-required'
        $result.findings.Count | Should -Be 0
    }

    It 'reports missing administrator recovery even when the caller can bypass' {
        $result = Get-AzdGitHubOwnerRecoveryStatus -Ruleset ([pscustomobject]@{
            current_user_can_bypass = 'always'; bypass_actors = @()
        })
        $result.state | Should -Be 'findings'
        $result.findings | Should -Contain 'defaultBranchRecoveryBypassMissing'
    }
}

Describe 'GitHub API failure handling' {
        It 'preserves HTTP failures and never treats them as absent protection' -TestCases @(
            @{ status = 403 }
            @{ status = 429 }
            @{ status = 500 }
        ) {
            param($status)
            Mock gh -ModuleName Azd.GitHubGovernance { $global:LASTEXITCODE = 1; @("HTTP/2.0 $status Error", '', '{"message":"Request failed"}') }
            $result = Get-AzdGitHubApiResult -Endpoint 'repos/owner/repo/branches/main/protection'
            $result.statusCode | Should -Be $status
            $result.successful | Should -BeFalse
            Get-AzdGitHubLegacyProtectionFinding -ApiResult $result | Should -Be 'legacyBranchProtectionAuditUnavailable'
        }

        It 'accepts only an explicit branch-not-protected response as absence' {
            Mock gh -ModuleName Azd.GitHubGovernance { $global:LASTEXITCODE = 1; @('HTTP/2.0 404 Not Found', '', '{"message":"Branch not protected"}') }
            $result = Get-AzdGitHubApiResult -Endpoint 'repos/owner/repo/branches/main/protection'
            @(Get-AzdGitHubLegacyProtectionFinding -ApiResult $result).Count | Should -Be 0
            $result.data.message = 'Not Found'
            Get-AzdGitHubLegacyProtectionFinding -ApiResult $result | Should -Be 'legacyBranchProtectionAuditUnavailable'
        }

        It 'reports existing legacy protection from a successful response' {
            Mock gh -ModuleName Azd.GitHubGovernance { $global:LASTEXITCODE = 0; @('HTTP/2.0 200 OK', 'Content-Type: application/json', '', '{"required_status_checks":{}}') }
            $result = Get-AzdGitHubApiResult -Endpoint 'repos/owner/repo/branches/main/protection'
            $result.successful | Should -BeTrue
            Get-AzdGitHubLegacyProtectionFinding -ApiResult $result | Should -Be 'legacyBranchProtectionPresent'
        }

        It 'reports an unavailable check when no HTTP response was received' {
            Mock gh -ModuleName Azd.GitHubGovernance { $global:LASTEXITCODE = 1 }
            $result = Get-AzdGitHubApiResult -Endpoint 'repos/owner/repo/branches/main/protection'
            $result.statusCode | Should -BeNullOrEmpty
            Get-AzdGitHubLegacyProtectionFinding -ApiResult $result | Should -Be 'legacyBranchProtectionAuditUnavailable'
        }
}
