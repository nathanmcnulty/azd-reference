BeforeAll {
    $compiledPath = Join-Path $TestDrive 'foundry.json'
    & az bicep build --file (Join-Path $PSScriptRoot '../components/powershell/foundry-stateless-agent/foundry-stateless-agent.bicep') --outfile $compiledPath
    if ($LASTEXITCODE) { throw 'Foundry component compilation failed.' }
    $template = Get-Content $compiledPath -Raw | ConvertFrom-Json -Depth 100
}
Describe 'Compiled optional Foundry resources' {
    It 'defaults disabled and creates no tools, storage, connections or compute hosts' {
        $template.parameters.enabled.defaultValue | Should -BeFalse
        @($template.resources).Count | Should -Be 5
        foreach ($resource in $template.resources) { $resource.condition | Should -Match "parameters\('enabled'\)" }
        @($template.resources | Where-Object { $_.type -notin @('Microsoft.CognitiveServices/accounts','Microsoft.CognitiveServices/accounts/projects','Microsoft.CognitiveServices/accounts/deployments','Microsoft.Authorization/roleAssignments') }).Count | Should -Be 0
        $template.parameters.PSObject.Properties.Name | Should -Not -Contain 'runtimePrincipalId'
    }
    It 'pins the configurable default model and disables local authentication and version upgrades' {
        $template.parameters.modelName.defaultValue | Should -BeExactly 'gpt-6-luna'
        $template.parameters.modelVersion.defaultValue | Should -BeExactly '2026-09-22'
        $account = @($template.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts')[0]
        $account.properties.disableLocalAuth | Should -BeTrue
        $deployment = @($template.resources | Where-Object type -eq 'Microsoft.CognitiveServices/accounts/deployments')[0]
        $deployment.properties.versionUpgradeOption | Should -BeExactly 'NoAutoUpgrade'
        $deployment.properties.model.version | Should -BeExactly "[parameters('modelVersion')]"
    }
    It 'limits role targets to the new project identity and explicitly selected setup principal' {
        $roles = @($template.resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')
        $roles.Count | Should -Be 2
        @($roles | Where-Object { $_.properties.principalId -match "parameters\('setupPrincipalId'\)" }).Count | Should -Be 1
        @($roles | Where-Object { $_.properties.principalId -match 'Microsoft.CognitiveServices/accounts/projects' }).Count | Should -Be 1
        @($roles | Where-Object { $_.scope -notmatch 'Microsoft.CognitiveServices/accounts' }).Count | Should -Be 0
        $template.outputs.projectEndpoint.value | Should -Match 'services.ai.azure.com/api/projects'
    }
}
