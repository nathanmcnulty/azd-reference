BeforeAll {
    $templatePath = Join-Path $TestDrive 'security-host.json'
    & az bicep build --file (Join-Path $PSScriptRoot '../components/bicep/security-automation-host/security-automation-host.bicep') --outfile $templatePath
    if ($LASTEXITCODE) { throw 'Security host compilation failed.' }
    $template = Get-Content $templatePath -Raw | ConvertFrom-Json -Depth 100
}
Describe 'Function diagnostics deployment contract' {
    It 'retains invocation diagnostics with a bounded ingestion budget only in Function mode' {
        $site = @($template.resources | Where-Object type -eq 'Microsoft.Web/sites')[0]
        $workspace = @($template.resources | Where-Object type -eq 'Microsoft.OperationalInsights/workspaces')[0]
        $insights = @($template.resources | Where-Object type -eq 'Microsoft.Insights/components')[0]
        $workspace.condition | Should -Be $site.condition
        $insights.condition | Should -Be $site.condition
        $workspace.properties.retentionInDays | Should -Be 30
        $workspace.properties.workspaceCapping.dailyQuotaGb | Should -Be "[json('0.1')]"
        $insights.properties.WorkspaceResourceId | Should -Match 'Microsoft.OperationalInsights/workspaces'
        $connection = @($site.properties.siteConfig.appSettings | Where-Object name -eq 'APPLICATIONINSIGHTS_CONNECTION_STRING')
        $connection.Count | Should -Be 1
        $connection[0].value | Should -Match 'Microsoft.Insights/components.*ConnectionString'
    }
}

Describe 'Compiled security host boundaries' {
    It 'defaults to no hosted resources and binds scheduling to the lowercase package hash' {
        $template.parameters.computeMode.defaultValue | Should -BeExactly 'none'
        $template.variables.hosted | Should -BeExactly "[not(equals(parameters('computeMode'), 'none'))]"
        $template.variables.bundleHashValid | Should -Match "contains\('0123456789abcdef'"
        $template.variables.effectiveScheduleEnabled | Should -Match "parameters\('scheduleEnabled'\)"
        $template.variables.effectiveScheduleEnabled | Should -Match "variables\('bundleHashValid'\)"
        $template.variables.effectiveScheduleEnabled | Should -Match "parameters\('bundleBlob'\).*parameters\('bundleSha256'\)"

        $schedule = @($template.resources | Where-Object type -eq 'Microsoft.Automation/automationAccounts/schedules')
        $jobSchedule = @($template.resources | Where-Object type -eq 'Microsoft.Automation/automationAccounts/jobSchedules')
        $workflow = @($template.resources | Where-Object type -eq 'Microsoft.Logic/workflows')
        $function = @($template.resources | Where-Object type -eq 'Microsoft.Web/sites')
        $schedule.Count | Should -Be 1
        $jobSchedule.Count | Should -Be 1
        $workflow.Count | Should -Be 1
        $function.Count | Should -Be 1
        $schedule[0].condition | Should -Match "computeMode'.*automation.*effectiveScheduleEnabled"
        $jobSchedule[0].condition | Should -BeExactly $schedule[0].condition
        $workflow[0].condition | Should -Match "computeMode'.*logic-app"
        $workflow[0].properties.state | Should -Match 'effectiveScheduleEnabled'
        (@($function[0].properties.siteConfig.appSettings | Where-Object name -eq 'AzureWebJobs.SecurityReview.Disabled'))[0].value |
            Should -Match 'effectiveScheduleEnabled'
    }

    It 'keeps Function, Automation, and Logic App roles at their intended resource scopes' {
        $roles = @($template.resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')
        $functionHost = @($roles | Where-Object {
            $_.condition -eq "[variables('useFunction')]" -and
            $_.scope -match "Microsoft.Storage/storageAccounts'.*stf" -and
            $_.properties.roleDefinitionId -match 'blobOwner'
        })
        $functionEvidence = @($roles | Where-Object {
            $_.condition -eq "[variables('useFunction')]" -and
            $_.scope -match "blobServices/containers'.*createArray\('evidence', 'reports', 'packages'\)\[0\]" -and
            $_.properties.roleDefinitionId -match 'blobReader'
        })
        $functionReports = @($roles | Where-Object {
            $_.condition -eq "[variables('useFunction')]" -and
            $_.scope -match "blobServices/containers'.*createArray\('evidence', 'reports', 'packages'\)\[1\]" -and
            $_.properties.roleDefinitionId -match 'blobContributor'
        })
        $automationReaders = @($roles | Where-Object {
            $_.condition -eq "[variables('useAutomation')]" -and
            $_.scope -match "createArray\(0, 2\)\[copyIndex\(\)\]" -and
            $_.properties.roleDefinitionId -match 'blobReader'
        })
        $automationReports = @($roles | Where-Object {
            $_.condition -eq "[variables('useAutomation')]" -and
            $_.scope -match "blobServices/containers'.*createArray\('evidence', 'reports', 'packages'\)\[1\]" -and
            $_.properties.roleDefinitionId -match 'blobContributor'
        })
        $logicJobs = @($roles | Where-Object {
            $_.condition -match "computeMode'.*logic-app" -and
            $_.scope -match 'Microsoft.Automation/automationAccounts' -and
            $_.properties.roleDefinitionId -match 'jobOperator'
        })
        $functionHost.Count | Should -Be 1
        $functionEvidence.Count | Should -Be 1
        $functionReports.Count | Should -Be 1
        $automationReaders.Count | Should -Be 1
        $automationReaders[0].copy.count | Should -Match 'createArray\(0, 2\)'
        $automationReports.Count | Should -Be 1
        $logicJobs.Count | Should -Be 1
    }
}
