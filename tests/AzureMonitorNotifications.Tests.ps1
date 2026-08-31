Describe 'Azure Monitor scheduled-query notifications component' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:componentRoot = Join-Path $script:repoRoot 'components/bicep/azure-monitor-scheduled-query-notifications'
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:componentRoot 'component.json') -Raw | ConvertFrom-Json
        $script:actionGroupSource = Get-Content -LiteralPath (Join-Path $script:componentRoot 'logic-app-action-group.bicep') -Raw
        $script:alertSource = Get-Content -LiteralPath (Join-Path $script:componentRoot 'scheduled-query-alert.bicep') -Raw
    }

    It 'publishes the two Bicep modules as a versioned pilot' {
        $script:manifest.id | Should -Be 'azure-monitor-scheduled-query-notifications'
        $script:manifest.version | Should -Be '0.1.0'
        $script:manifest.status | Should -Be 'pilot'
        @($script:manifest.files).Count | Should -Be 2
        @($script:manifest.files.source) | Should -Be @(
            'components/bicep/azure-monitor-scheduled-query-notifications/logic-app-action-group.bicep',
            'components/bicep/azure-monitor-scheduled-query-notifications/scheduled-query-alert.bicep'
        )
    }

    It 'keeps the Logic App workflow and notification policy solution-owned' {
        $script:actionGroupSource | Should -Not -Match "Microsoft\.Logic/workflows@"
        $script:alertSource | Should -Not -Match 'AuditLogs|AADRiskyUsers|AADUserRiskEvents|AdaptiveCard|teamsWebhook'
        $script:alertSource | Should -Match 'param query string'
        $script:alertSource | Should -Match 'param dimensions array'
    }

    It 'uses the reviewed Azure resource contracts and common alert schema' {
        $script:actionGroupSource | Should -Match "Microsoft\.Insights/actionGroups@2023-01-01"
        $script:actionGroupSource | Should -Match "listCallbackUrl\('\$\{logicAppResourceId\}/triggers/\$\{logicAppTriggerName\}', '2019-05-01'\)\.value"
        $script:actionGroupSource | Should -Match 'useCommonAlertSchema: true'
        $script:alertSource | Should -Match "Microsoft\.Insights/scheduledQueryRules@2023-12-01"
        $script:alertSource | Should -Match "timeAggregation: 'Count'"
        $script:alertSource | Should -Match "operator: 'GreaterThan'"
        $script:alertSource | Should -Match 'threshold: 0'
    }

    It 'parameterizes the proven PIM and risk differences' {
        $script:alertSource | Should -Match 'param autoMitigate bool'
        $script:alertSource | Should -Match 'param evaluationFrequency string'
        $script:alertSource | Should -Match 'param windowSize string'
        $script:alertSource | Should -Match 'param dimensions array'
    }

    It 'does not expose the callback URL as an output' {
        $script:actionGroupSource | Should -Not -Match 'output\s+\w*(callback|url)\w*'
    }
}
