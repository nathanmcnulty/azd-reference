Describe 'Flex scheduled-poller host component' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:componentRoot = Join-Path $script:repoRoot 'components/bicep/flex-scheduled-poller-host'
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:componentRoot 'component.json') -Raw | ConvertFrom-Json
        $script:source = Get-Content -LiteralPath (Join-Path $script:componentRoot 'flex-scheduled-poller-host.bicep') -Raw
    }

    It 'publishes one independently versioned pilot module' {
        $script:manifest.id | Should -Be 'flex-scheduled-poller-host'
        $script:manifest.version | Should -Be '0.1.0'
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
}
