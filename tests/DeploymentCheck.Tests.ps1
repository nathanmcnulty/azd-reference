BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $templatePath = Join-Path $repositoryRoot 'examples/deployment-check'
}

Describe 'Named deployment check template' {
    It 'plans only its three read-only checks without calling Azure' {
        $consumer = Join-Path $TestDrive 'deployment-check'
        Copy-Item -LiteralPath $templatePath -Destination $consumer -Recurse
        function global:az { throw 'Offline planning must not invoke Azure CLI.' }
        try {
            $report = & (Join-Path $consumer 'scripts/Test-Deployment.ps1') -Plan -PassThru
            $report.outcome | Should -Be 'planned'
            @($report.checks.id) | Should -Be @(
                'context.azure-cli-session', 'context.template-root', 'infrastructure.resource-group'
            )
            @($report.checks | Where-Object status -ne 'planned').Count | Should -Be 0
            Get-Content (Join-Path $consumer 'reports/deployment-validation.json') -Raw |
                Test-Json -SchemaFile (Join-Path $repositoryRoot 'schemas/deployment-validation.schema.json') |
                Should -BeTrue
        }
        finally { Remove-Item Function:\az -ErrorAction SilentlyContinue }
    }

    It 'retains the proven resource-group-only infrastructure and GUI contract' {
        foreach ($relativePath in @('infra/main.bicep', 'infra/main.parameters.json', 'azd-gui.json')) {
            Get-Content (Join-Path $templatePath $relativePath) -Raw |
                Should -BeExactly (Get-Content (Join-Path $repositoryRoot "skeleton/$relativePath") -Raw)
        }
        Get-Content (Join-Path $templatePath 'azure.yaml') -Raw |
            Should -BeExactly ((Get-Content (Join-Path $repositoryRoot 'skeleton/azure.yaml') -Raw).
                Replace('replace-with-solution-name', 'azd-deployment-check'))
    }

    It 'is a self-contained locked consumer with no placeholder solution name' {
        & (Join-Path $repositoryRoot 'tooling/Test-AzdComponentDrift.ps1') -TargetPath $templatePath -Quiet
        $lock = Get-Content (Join-Path $templatePath 'azd-components.lock.json') -Raw
        $lock | Test-Json -SchemaFile (Join-Path $repositoryRoot 'schemas/azd-components-lock.schema.json') |
            Should -BeTrue
        Get-ChildItem $templatePath -File -Recurse | Select-String 'replace-with-solution-name' |
            Should -BeNullOrEmpty
    }
}
