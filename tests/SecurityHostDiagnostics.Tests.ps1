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
