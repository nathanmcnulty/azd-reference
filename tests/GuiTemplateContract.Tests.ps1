BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skeletonPath = Join-Path $script:repoRoot 'skeleton'
    $script:manifestPath = Join-Path $script:skeletonPath 'azd-gui.json'
}

Describe 'GUI template contract skeleton' {
    It 'is valid JSON and declares the skeleton prerequisites and connections' {
        { Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
        $manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json

        $manifest.schemaVersion | Should -Be '1.0'
        $manifest.minimumAzdVersion | Should -Be '1.23.0'
        $manifest.requiresInteractiveTerminal | Should -BeFalse
        @($manifest.prerequisites.id) | Should -Be @('azd', 'az-cli', 'pwsh')
        @($manifest.connections.id) | Should -Be @('azd', 'azureCli')
        @($manifest.permissionChecks.id) | Should -Be @('azure-subscription-access')
    }

    It 'leaves azd target controls native and declares no custom configuration' {
        $manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
        @($manifest.configuration.groups).Count | Should -Be 0

        $parameters = Get-Content -LiteralPath (Join-Path $script:skeletonPath 'infra/main.parameters.json') -Raw | ConvertFrom-Json
        $parameters.parameters.environmentName.value | Should -Be '${AZURE_ENV_NAME}'
        $parameters.parameters.location.value | Should -Be '${AZURE_LOCATION}'
    }

    It 'matches the skeleton azd version and noninteractive postprovision hook' {
        $manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
        $azureYaml = Get-Content -LiteralPath (Join-Path $script:skeletonPath 'azure.yaml') -Raw

        $azureYaml | Should -Match 'azd: ">= 1\.23\.0"'
        $azureYaml | Should -Match 'shell: pwsh'
        $azureYaml | Should -Match 'interactive: false'
        $manifest.minimumAzdVersion | Should -Be '1.23.0'
    }
}
