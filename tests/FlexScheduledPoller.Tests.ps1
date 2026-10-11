Describe 'Flex scheduled-poller host component' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:componentRoot = Join-Path $script:repoRoot 'components/bicep/flex-scheduled-poller-host'
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:componentRoot 'component.json') -Raw | ConvertFrom-Json
        $script:source = Get-Content -LiteralPath (Join-Path $script:componentRoot 'flex-scheduled-poller-host.bicep') -Raw
    }

    It 'publishes one independently versioned pilot module' {
        $script:manifest.id | Should -Be 'flex-scheduled-poller-host'
        $script:manifest.version | Should -Be '0.2.0'
        $script:manifest.status | Should -Be 'pilot'
        @($script:manifest.files.source) | Should -Be @(
            'components/bicep/flex-scheduled-poller-host/flex-scheduled-poller-host.bicep'
        )
    }

    It 'defaults the on-demand host to the minimum Flex memory without always-ready instances' {
        $script:source | Should -Match '(?s)@allowed\(\[\s*512\s*2048\s*4096\s*\]\)\s*param instanceMemoryMB int = 512'
        $script:source | Should -Match 'instanceMemoryMB: instanceMemoryMB'
        $script:source | Should -Match 'param maximumInstanceCount int = 1'
        $script:source | Should -Match 'alwaysReady: \[\]'
        $script:source | Should -Match "tier: 'FlexConsumption'"
    }

    It 'does not force a telemetry or Log Analytics dependency on poller consumers' {
        $script:source | Should -Not -Match 'Microsoft\.OperationalInsights/workspaces'
        $script:source | Should -Not -Match 'Microsoft\.Insights/components'
        $script:source | Should -Not -Match 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    }

    It 'keeps solution behavior outside the component' {
        $script:source | Should -Not -Match 'graph\.microsoft\.com|AuditLogs|riskDetections|AdaptiveCard|Teams'
        $script:source | Should -Match '@secure\(\)\s*param applicationSettings object'
        $script:source | Should -Match 'AZD_POLLER_STATE_CONTAINER'
        $script:source | Should -Match 'AZD_POLLER_DEAD_LETTER_CONTAINER'
    }

    It 'supports state-preserving in-place consumer adoption' {
        $script:source | Should -Match "param deploymentContainerName string = 'function-releases'"
        $script:source | Should -Match "param stateContainerName string = 'poller-state'"
        $script:source | Should -Match "param deadLetterContainerName string = 'poller-dead-letter'"
        $script:source | Should -Match 'param storageAccountSettingAliases array = \[\]'
        $script:source | Should -Match 'param stateContainerSettingAliases array = \[\]'
        $script:source | Should -Match 'param deadLetterContainerSettingAliases array = \[\]'
        $script:source | Should -Match 'compatibilitySettings'
        $script:source | Should -Match 'concat\(solutionSettings, compatibilitySettings'
    }

    It 'keeps secrets and storage connection strings out of outputs' {
        $script:source | Should -Not -Match 'output\s+\w*(connection|string|key|url)\w*'
        $script:source | Should -Match 'Storage Blob Data Contributor'
    }

    It 'preserves immutable consumer wrapper bytes apart from the two declared offline adaptations' {
        $root = Join-Path $script:repoRoot 'tests/fixtures/bicep/flex-scheduled-poller-host'
        $provenance = Get-Content (Join-Path $root 'provenance.json') -Raw | ConvertFrom-Json
        foreach ($consumer in $provenance.consumers) {
            $shape = if ($consumer.repository.EndsWith('/azd-pim')) { 'pim' } else { 'risk' }
            $adapted = [IO.File]::ReadAllText((Join-Path $root "$shape-wrapper.bicep")).Replace("`r`n", "`n")
            $original = $adapted.Replace("param identityOnlyStorage bool = false`n", '').Replace("    identityOnlyStorage: identityOnlyStorage`n", '').Replace(
                "'../../../../components/bicep/flex-scheduled-poller-host/flex-scheduled-poller-host.bicep'",
                "'../vendor/Azd.FlexScheduledPoller/flex-scheduled-poller-host.bicep'"
            )
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($original))) | Should -BeExactly $consumer.wrapperSha256
            $consumer.componentVersion | Should -BeExactly '0.1.0'
            $consumer.componentRevision | Should -BeExactly 'a79ed9ab9ae2ec10ff3d3c50a011d878c9524592'
        }
    }

    It 'preserves the canonical legacy component for default parity without reusing its version' {
        $root = Join-Path $script:repoRoot 'tests/fixtures/bicep/flex-scheduled-poller-host'
        $provenance = Get-Content (Join-Path $root 'provenance.json') -Raw | ConvertFrom-Json
        (Get-FileHash (Join-Path $root 'legacy-0.1.0.bicep')).Hash | Should -BeExactly $provenance.legacyComponent.sha256
        $script:manifest.version | Should -BeExactly '0.2.0'
    }
}
