Describe 'Azure Monitor scheduled-query notifications component' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:componentRoot = Join-Path $script:repoRoot 'components/bicep/azure-monitor-scheduled-query-notifications'
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:componentRoot 'component.json') -Raw | ConvertFrom-Json
        $script:actionGroupSource = Get-Content -LiteralPath (Join-Path $script:componentRoot 'logic-app-action-group.bicep') -Raw
        $script:alertSource = Get-Content -LiteralPath (Join-Path $script:componentRoot 'scheduled-query-alert.bicep') -Raw
        $fixtureRoot = Join-Path $PSScriptRoot 'fixtures/bicep/azure-monitor-scheduled-query-notifications'
        $script:pimWrapperSource = Get-Content -LiteralPath (Join-Path $fixtureRoot 'pim-wrapper.bicep') -Raw
        $script:riskWrapperSource = Get-Content -LiteralPath (Join-Path $fixtureRoot 'risk-wrapper.bicep') -Raw
        $script:compiledAssertionSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Assert-AzureMonitorCompiledTemplate.ps1') -Raw
        $script:negativeAssertionSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-AzureMonitorCompiledAssertionNegative.ps1') -Raw
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

    It 'rejects empty required strings at the module boundary' {
        $requiredActionGroupStrings = @(
            'actionGroupName',
            'groupShortName',
            'logicAppResourceId',
            'receiverName',
            'logicAppTriggerName'
        )
        $requiredAlertStrings = @(
            'alertRuleName',
            'location',
            'workspaceResourceId',
            'actionGroupResourceId',
            'displayName',
            'alertDescription',
            'query'
        )
        foreach ($parameterName in $requiredActionGroupStrings) {
            $script:actionGroupSource | Should -Match "@minLength\(1\)(?:\s*@\w+\([^\r\n]+\))*\s*param $([regex]::Escape($parameterName)) string"
        }
        foreach ($parameterName in $requiredAlertStrings) {
            $script:alertSource | Should -Match "@minLength\(1\)(?:\s*@\w+\([^\r\n]+\))*\s*param $([regex]::Escape($parameterName)) string"
        }
    }

    It 'allows only the two reviewed pilot interval shapes' {
        $script:alertSource | Should -Match "(?s)@allowed\(\[\s*'PT5M'\s*\]\)\s*param evaluationFrequency string"
        $script:alertSource | Should -Match "(?s)@allowed\(\[\s*'PT5M'\s*'PT10M'\s*\]\)\s*param windowSize string"
    }

    It 'provides representative PIM and risk wrappers using symbolic resource IDs' {
        $script:pimWrapperSource | Should -Match 'logicAppResourceId: workflow\.id'
        $script:pimWrapperSource | Should -Match "logicAppTriggerName: 'manual'"
        $script:pimWrapperSource | Should -Match 'workspaceResourceId: workspace\.id'
        $script:pimWrapperSource | Should -Match 'actionGroupResourceId: actionGroup\.outputs\.actionGroupResourceId'
        $script:pimWrapperSource | Should -Match "evaluationFrequency: 'PT5M'"
        $script:pimWrapperSource | Should -Match "windowSize: 'PT5M'"
        $script:pimWrapperSource | Should -Match 'autoMitigate: true'
        $script:pimWrapperSource | Should -Match "(?s)name: 'ActivationEventId'.*name: 'CorrelationId'.*name: 'Actor'.*name: 'Role'"

        $script:riskWrapperSource | Should -Match 'logicAppResourceId: workflow\.id'
        $script:riskWrapperSource | Should -Match "logicAppTriggerName: 'manual'"
        $script:riskWrapperSource | Should -Match 'workspaceResourceId: workspace\.id'
        $script:riskWrapperSource | Should -Match 'actionGroupResourceId: actionGroup\.outputs\.actionGroupResourceId'
        $script:riskWrapperSource | Should -Match "evaluationFrequency: 'PT5M'"
        $script:riskWrapperSource | Should -Match "windowSize: 'PT10M'"
        $script:riskWrapperSource | Should -Match 'autoMitigate: false'
        $script:riskWrapperSource | Should -Match "name: 'Envelope'"
    }

    It 'asserts exact compiled property flow, dependencies, and output contracts' {
        $script:compiledAssertionSource | Should -Match 'actionResource\.name -ceq'
        $script:compiledAssertionSource | Should -Match 'properties\.groupShortName -ceq'
        $script:compiledAssertionSource | Should -Match 'logicAppReceivers\[0\]\.name -ceq'
        $script:compiledAssertionSource | Should -Match 'logicAppReceivers\[0\]\.resourceId -ceq'
        $script:compiledAssertionSource | Should -Match 'expectedCallbackExpression'
        $script:compiledAssertionSource | Should -Match "parameters\('logicAppTriggerName'\)"
        $script:compiledAssertionSource | Should -Match 'properties\.criteria\.allOf\[0\]\.dimensions'
        $script:compiledAssertionSource | Should -Match 'properties\.actions\.actionGroups\[0\]'
        $script:compiledAssertionSource | Should -Match 'actionGroup\.dependsOn'
        $script:compiledAssertionSource | Should -Match 'alert\.dependsOn'
        $script:compiledAssertionSource | Should -Match 'function Assert-ExactOutputContract'
        $script:compiledAssertionSource | Should -Match 'ExpectedOutputs\.Count'
        $script:compiledAssertionSource | Should -Match 'definition\.type -eq'
        $script:compiledAssertionSource | Should -Match 'definition\.value -ceq'
        $script:compiledAssertionSource | Should -Match 'actionGroupResourceId'
        $script:compiledAssertionSource | Should -Match 'alertRuleResourceId'
        $script:compiledAssertionSource | Should -Not -Match 'notmatch.*listCallbackUrl'
    }

    It 'contains executable negative cases for indirect and whole-resource leakage' {
        $script:negativeAssertionSource | Should -Match "Name 'alias-variable-indirection'"
        $script:negativeAssertionSource | Should -Match "variables\('callbackAlias'\)"
        $script:negativeAssertionSource | Should -Match "Name 'whole-resource-reference'"
        $script:negativeAssertionSource | Should -Match "reference\(resourceId\('Microsoft\.Insights/actionGroups'"
        $script:negativeAssertionSource | Should -Match 'unexpectedly passed'
    }

    It 'does not expose the callback URL as an output' {
        $script:actionGroupSource | Should -Not -Match 'output\s+\w*(callback|url)\w*'
    }
}
