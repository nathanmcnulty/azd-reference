Describe 'Release integrity standard' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:tool = Join-Path $script:repoRoot 'tooling/Test-AzdReleaseIntegrity.ps1'
    }

    It 'passes the reference repository release-integrity starter' {
        $result = @(& $script:tool -RepositoryRoot $script:repoRoot)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'current'
        $result[0].enforcement | Should -Be 'migration'
    }

    It 'reports missing required security-policy sections' {
        $testRoot = Join-Path $TestDrive 'missing-security-section'
        New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/workflows') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot '.github/workflows/release-attestation.yml') -Destination (Join-Path $testRoot '.github/workflows/release-attestation.yml')
        $security = Get-Content -LiteralPath (Join-Path $script:repoRoot 'SECURITY.md') -Raw
        $security = $security -replace '(?m)^## Response targets\r?\n', ''
        Set-Content -LiteralPath (Join-Path $testRoot 'SECURITY.md') -Value $security -Encoding utf8NoBOM

        $result = @(& $script:tool -RepositoryRoot $testRoot)
        $result[0].findings | Should -Contain 'securityPolicyHeadingMissing:## Response targets'
    }

    It 'reports unpinned release workflow actions' {
        $testRoot = Join-Path $TestDrive 'unpinned-release-action'
        New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/workflows') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'SECURITY.md') -Destination (Join-Path $testRoot 'SECURITY.md')
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/release-attestation.yml') -Raw
        $workflow = $workflow -replace 'actions/attest@[0-9a-f]{40}', 'actions/attest@v4'
        Set-Content -LiteralPath (Join-Path $testRoot '.github/workflows/release-attestation.yml') -Value $workflow -Encoding utf8NoBOM

        $result = @(& $script:tool -RepositoryRoot $testRoot)
        $result.findings | Should -Contain 'attestationActionUnpinnedOrMissing'
        @($result.findings | Where-Object { $_ -like 'workflowActionUnpinned:actions/attest@v4' }).Count | Should -Be 1
    }
}
