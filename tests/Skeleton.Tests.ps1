BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $skeletonPath = Join-Path $repositoryRoot 'skeleton'
    $reportSchema = Join-Path $repositoryRoot 'schemas/deployment-validation.schema.json'
}

Describe 'Starter skeleton' {
    It 'includes the security policy and release-attestation starter' {
        Test-Path -LiteralPath (Join-Path $skeletonPath 'SECURITY.md') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $skeletonPath '.github/workflows/release-attestation.yml') -PathType Leaf | Should -BeTrue

        $integrityTool = Join-Path $repositoryRoot 'tooling/Test-AzdReleaseIntegrity.ps1'
        $result = @(& $integrityTool -RepositoryRoot $skeletonPath)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'current'
    }

    It 'runs Plan without authentication, cloud calls, or delivery actions' {
        $consumer = Join-Path $TestDrive 'consumer'
        Copy-Item -LiteralPath $skeletonPath -Destination $consumer -Recurse

        $script:azInvoked = $false
        function global:az {
            $script:azInvoked = $true
            throw 'The Azure CLI must not be invoked during Plan.'
        }

        try {
            $report = & (Join-Path $consumer 'scripts/Test-Deployment.ps1') `
                -Plan `
                -OutputPath 'reports/plan.json' `
                -PassThru

            $script:azInvoked | Should -BeFalse
            $report.mode | Should -Be 'plan'
            $report.outcome | Should -Be 'planned'
            @($report.checks | Where-Object status -notin 'planned', 'skipped').Count | Should -Be 0

            $reportPath = Join-Path $consumer 'reports/plan.json'
            Test-Path -LiteralPath $reportPath -PathType Leaf | Should -BeTrue
            (Get-Content -LiteralPath $reportPath -Raw |
                Test-Json -SchemaFile $reportSchema -ErrorAction Stop) | Should -BeTrue
        }
        finally {
            Remove-Item Function:\az -ErrorAction SilentlyContinue
        }
    }

    It 'uses the selected subscription for context validation without requiring a tenant variable' {
        $consumer = Join-Path $TestDrive 'scoped-consumer'
        $scopedSkeletonPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skeleton'
        New-Item -ItemType Directory -Path $consumer | Out-Null
        Get-ChildItem -LiteralPath $scopedSkeletonPath -Force | Copy-Item -Destination $consumer -Recurse
        Test-Path -LiteralPath (Join-Path $consumer 'azure.yaml') -PathType Leaf | Should -BeTrue

        $names = @('AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID')
        $original = @{}
        foreach ($name in $names) {
            $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            $original[$name] = if ($item) { $item.Value } else { $null }
        }
        $script:azInvocations = @()
        $script:azContext = '{"id":"11111111-1111-1111-1111-111111111111","tenantId":"22222222-2222-2222-2222-222222222222"}'
        function global:az {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)

            $script:azInvocations += ,@($Arguments)
            $global:LASTEXITCODE = 0
            if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
                return $script:azContext
            }
        }

        try {
            $env:AZURE_SUBSCRIPTION_ID = '11111111-1111-1111-1111-111111111111'
            Remove-Item -LiteralPath Env:AZURE_TENANT_ID -ErrorAction SilentlyContinue
            Import-Module (Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1') -Force
            Import-Module (Join-Path $consumer 'scripts/Deployment.Validation.psm1') -Force
            $definition = @(Get-ProjectValidationDefinition | Where-Object Id -eq 'context.azure-cli-session')

            $definition.Count | Should -Be 1
            & $definition[0].Action

            $accountCall = @($script:azInvocations | Where-Object { $_[0] -eq 'account' -and $_[1] -eq 'show' })
            $accountCall.Count | Should -Be 1
            $accountCall[0] | Should -Contain '--subscription'
            $accountCall[0][([Array]::IndexOf($accountCall[0], '--subscription') + 1)] | Should -Be $env:AZURE_SUBSCRIPTION_ID

            $script:azContext = '{"id":"33333333-3333-3333-3333-333333333333","tenantId":"22222222-2222-2222-2222-222222222222"}'
            { & $definition[0].Action } | Should -Throw '*expected subscription*'

            $script:azContext = '{"id":"11111111-1111-1111-1111-111111111111","tenantId":"22222222-2222-2222-2222-222222222222"}'
            $env:AZURE_TENANT_ID = '44444444-4444-4444-4444-444444444444'
            { & $definition[0].Action } | Should -Throw '*expected tenant*'
        }
        finally {
            Remove-Item Function:\az -ErrorAction SilentlyContinue
            foreach ($name in $names) {
                if ($null -eq $original[$name]) {
                    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
                }
                else {
                    Set-Item -LiteralPath "Env:$name" -Value $original[$name]
                }
            }
        }
    }
}
