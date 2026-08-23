Describe 'Deployment validation engine' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $modulePath = Join-Path $script:repoRoot 'components/powershell/deployment-validation/Azd.DeploymentValidation.psd1'
        Import-Module $modulePath -Force
    }
    It 'does not invoke actions while planning' {
        $script:actionInvoked = $false
        $result = Invoke-AzdValidationCheck -Id 'context.plan' -Phase context -Title 'Plan' -Summary 'Plan only' `
            -SideEffect readOnly -Plan -Action { $script:actionInvoked = $true }
        $script:actionInvoked | Should -BeFalse
        $result.status | Should -Be 'planned'
    }

    It 'requires explicit authorization for synthetic delivery' {
        $script:deliveryInvoked = $false
        $result = Invoke-AzdValidationCheck -Id 'delivery.test' -Phase delivery -Title 'Delivery' -Summary 'Delivery' `
            -SideEffect syntheticDelivery -Action { $script:deliveryInvoked = $true }
        $script:deliveryInvoked | Should -BeFalse
        $result.status | Should -Be 'skipped'
    }

    It 'executes authorized synthetic delivery' {
        $script:deliveryInvoked = $false
        $result = Invoke-AzdValidationCheck -Id 'delivery.test' -Phase delivery -Title 'Delivery' -Summary 'Delivery' `
            -SideEffect syntheticDelivery -AllowSyntheticDelivery -Action { $script:deliveryInvoked = $true }
        $script:deliveryInvoked | Should -BeTrue
        $result.status | Should -Be 'pass'
    }

    It 'captures exception type without persisting the exception message' {
        $result = Invoke-AzdValidationCheck -Id 'security.failure' -Phase security -Title 'Failure' -Summary 'Safe failure' `
            -Action { throw 'secret-value-that-must-not-be-written' }
        $result.status | Should -Be 'fail'
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'secret-value-that-must-not-be-written'
        $result.actual.exceptionType | Should -Match 'Exception'
    }

    It 'redacts sensitive keys and signed URLs recursively' {
        $safe = ConvertTo-AzdSafeData -Value @{
            clientSecret = 'do-not-write'
            nested = @{ callbackUrl = 'https://example.invalid/callback?sig=do-not-write'; name = 'safe' }
        }
        $safe.clientSecret | Should -Be '[REDACTED]'
        $safe.nested.callbackUrl | Should -Be '[REDACTED]'
        $safe.nested.name | Should -Be 'safe'
    }

    It 'writes an atomic schema-valid repository-relative report' {
        $check = Invoke-AzdValidationCheck -Id 'context.local' -Phase context -Title 'Local' -Summary 'Local passed' -SideEffect none -Action {}
        $report = New-AzdValidationReport -TemplateName example -TemplateVersion 0.1.0 -Mode verify `
            -StartedAt ([datetimeoffset]::UtcNow) -Checks @($check) -Requirements @{ tools = @(); modules = @(); permissions = @() }
        $relative = Write-AzdValidationReport -Report $report -OutputPath 'reports/result.json' -RepositoryRoot $TestDrive
        $relative | Should -Be 'reports/result.json'
        $output = Join-Path $TestDrive 'reports/result.json'
        Test-Path -LiteralPath $output | Should -BeTrue
        (Get-Content -LiteralPath $output -Raw | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/deployment-validation.schema.json') -ErrorAction Stop) | Should -BeTrue
    }

    It 'rejects report output outside the repository root' {
        $report = [pscustomobject]@{ outcome = 'passed' }
        { Write-AzdValidationReport -Report $report -OutputPath '../outside.json' -RepositoryRoot $TestDrive } | Should -Throw
        { Write-AzdValidationReport -Report $report -OutputPath ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'absolute.json'))) -RepositoryRoot $TestDrive } | Should -Throw
    }
}
