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
            token = 'ey.do-not-write'
            hostKey = 'host-do-not-write'
            authorizationHeader = 'Bearer do-not-write'
            connectionString = 'AccountName=a;AccountKey=do-not-write'
            credential = 'credential-do-not-write'
            nested = @{
                callback = @{ value = 'https://example.invalid/callback' }
                signedUri = [uri] 'https://example.invalid/callback?sig=do-not-write'
                name = 'safe'
            }
        }
        $safe.clientSecret | Should -Be '[REDACTED]'
        $safe.token | Should -Be '[REDACTED]'
        $safe.hostKey | Should -Be '[REDACTED]'
        $safe.authorizationHeader | Should -Be '[REDACTED]'
        $safe.connectionString | Should -Be '[REDACTED]'
        $safe.credential | Should -Be '[REDACTED]'
        $safe.nested.callback | Should -Be '[REDACTED]'
        $safe.nested.signedUri | Should -Be '[REDACTED URL]'
        $safe.nested.name | Should -Be 'safe'
    }

    It 'supports structured failed outcomes' {
        $result = Invoke-AzdValidationCheck -Id 'security.structured-failure' -Phase security -Title 'Structured failure' `
            -Summary 'Expected failure' -Expected 401 -Action {
                New-AzdCheckOutcome -Status fail -Summary 'The endpoint accepted an unauthenticated request.' `
                    -Expected 401 -Actual 200 -Evidence @{ probe = 'anonymous POST' } -Remediation 'Require authentication.'
            }
        $result.status | Should -Be 'fail'
        $result.actual | Should -Be 200
        $result.evidence.probe | Should -Be 'anonymous POST'
    }

    It 'creates safe coded failures without exposing sensitive details' {
        $failure = New-AzdCheckFailure -Code 'identity.requiredRoleMissing' `
            -Summary 'A required role is missing.' -Expected @('Role.Read.All') `
            -Details @{ roleName = 'Role.Read.All'; callbackUrl = 'https://example.invalid/?sig=secret' } `
            -Remediation 'Correct the role assignment.'

        $failure.status | Should -Be 'fail'
        $failure.actual.failureCode | Should -Be 'identity.requiredRoleMissing'
        $failure.actual.roleName | Should -Be 'Role.Read.All'
        (ConvertTo-AzdSafeData -Value $failure).actual.callbackUrl | Should -Be '[REDACTED]'
    }

    It 'gates dependent actions after a failed prerequisite' {
        $script:dependentInvoked = $false
        $definitions = @(
            New-AzdValidationCheckDefinition -Id 'context.exact' -Phase context -Title 'Context' -Summary 'Context' `
                -Action { New-AzdCheckFailure -Code 'context.mismatch' -Summary 'Context mismatch.' `
                    -Expected 'Exact context.' -Remediation 'Correct context.' }
            New-AzdValidationCheckDefinition -Id 'runtime.dependent' -Phase runtime -Title 'Dependent' -Summary 'Dependent' `
                -DependsOn 'context.exact' -Action { $script:dependentInvoked = $true }
        )

        $results = @(Invoke-AzdValidationSet -Definitions $definitions -AllowSyntheticDelivery)

        $script:dependentInvoked | Should -BeFalse
        ($results | Where-Object id -eq 'context.exact').status | Should -Be 'fail'
        ($results | Where-Object id -eq 'runtime.dependent').status | Should -Be 'skipped'
        ($results | Where-Object id -eq 'runtime.dependent').summary | Should -Match 'context\.exact'
    }

    It 'plans dependent checks without evaluating prerequisite outcomes' {
        $script:planDependencyInvoked = $false
        $definitions = @(
            New-AzdValidationCheckDefinition -Id 'context.planned' -Phase context -Title 'Context' -Summary 'Context' `
                -Action { throw 'must not execute' }
            New-AzdValidationCheckDefinition -Id 'runtime.planned' -Phase runtime -Title 'Runtime' -Summary 'Runtime' `
                -DependsOn 'context.planned' -Action { $script:planDependencyInvoked = $true }
        )

        $results = @(Invoke-AzdValidationSet -Definitions $definitions -Plan)

        $script:planDependencyInvoked | Should -BeFalse
        @($results | Where-Object status -eq 'planned').Count | Should -Be 2
    }

    It 'allows warning prerequisites but gates missing or forward dependencies' {
        $script:allowedInvoked = $false
        $script:blockedInvoked = $false
        $definitions = @(
            New-AzdValidationCheckDefinition -Id 'context.warning' -Phase context -Title 'Warning' -Summary 'Warning' `
                -Action { New-AzdCheckOutcome -Status warning -Summary 'Warning is acceptable.' }
            New-AzdValidationCheckDefinition -Id 'runtime.allowed' -Phase runtime -Title 'Allowed' -Summary 'Allowed' `
                -DependsOn 'context.warning' -Action { $script:allowedInvoked = $true }
            New-AzdValidationCheckDefinition -Id 'runtime.blocked' -Phase runtime -Title 'Blocked' -Summary 'Blocked' `
                -DependsOn 'runtime.later' -Action { $script:blockedInvoked = $true }
            New-AzdValidationCheckDefinition -Id 'runtime.later' -Phase runtime -Title 'Later' -Summary 'Later' -Action {}
        )

        $results = @(Invoke-AzdValidationSet -Definitions $definitions)

        $script:allowedInvoked | Should -BeTrue
        $script:blockedInvoked | Should -BeFalse
        ($results | Where-Object id -eq 'runtime.blocked').status | Should -Be 'skipped'
    }

    It 'turns malformed adapter output into a valid failed harness result' {
        $malformed = [pscustomobject]@{ id = 'runtime.incomplete'; phase = 'runtime'; status = 'pass' }
        $report = New-AzdValidationReport -TemplateName example -TemplateVersion 0.1.0 -Mode verify `
            -StartedAt ([datetimeoffset]::UtcNow) -Checks @($malformed)
        $report.outcome | Should -Be 'failed'
        $report.checks[0].id | Should -Be 'runtime.validation-harness.0'
        { Assert-AzdValidationSucceeded -Report $report } | Should -Throw
    }

    It 'applies plan and delivery policy centrally to declarative checks' {
        $script:readInvoked = $false
        $script:deliveryInvoked = $false
        $definitions = @(
            New-AzdValidationCheckDefinition -Id 'runtime.read' -Phase runtime -Title 'Read' -Summary 'Read' `
                -SideEffect readOnly -Action { $script:readInvoked = $true }
            New-AzdValidationCheckDefinition -Id 'delivery.synthetic' -Phase delivery -Title 'Delivery' -Summary 'Delivery' `
                -SideEffect syntheticDelivery -Action { $script:deliveryInvoked = $true }
        )
        $planned = @(Invoke-AzdValidationSet -Definitions $definitions -Plan -AllowSyntheticDelivery)
        $script:readInvoked | Should -BeFalse
        $script:deliveryInvoked | Should -BeFalse
        @($planned | Where-Object status -eq planned).Count | Should -Be 2

        $verified = @(Invoke-AzdValidationSet -Definitions $definitions)
        $script:readInvoked | Should -BeTrue
        $script:deliveryInvoked | Should -BeFalse
        ($verified | Where-Object id -eq 'delivery.synthetic').status | Should -Be 'skipped'
    }

    It 'writes an atomic schema-valid repository-relative report' {
        $check = Invoke-AzdValidationCheck -Id 'context.local' -Phase context -Title 'Local' -Summary 'Local passed' -SideEffect none -Action {}
        $report = New-AzdValidationReport -TemplateName example -TemplateVersion 0.1.0 -Mode verify `
            -StartedAt ([datetimeoffset]::UtcNow) -Checks @($check) -Requirements @{ tools = @(); modules = @(); permissions = @() }
        $schemaPath = Join-Path $script:repoRoot 'schemas/deployment-validation.schema.json'
        $relative = Write-AzdValidationReport -Report $report -OutputPath 'reports/result.json' -RepositoryRoot $TestDrive -SchemaPath $schemaPath
        $relative | Should -Be 'reports/result.json'
        $output = Join-Path $TestDrive 'reports/result.json'
        Test-Path -LiteralPath $output | Should -BeTrue
        (Get-Content -LiteralPath $output -Raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) | Should -BeTrue
    }

    It 'sanitizes the complete report before writing and rendering' {
        $check = Invoke-AzdValidationCheck -Id 'runtime.secret-boundary' -Phase runtime -Title 'Boundary' `
            -Summary 'Safe initial summary' -Action {
                New-AzdCheckOutcome -Status warning `
                    -Summary 'Callback https://example.invalid/hook?sig=summary-secret' `
                    -Evidence @{ authorizationHeader = 'Bearer header-secret'; signedUri = [uri] 'https://example.invalid/hook?sig=uri-secret' } `
                    -Remediation 'Retry with Bearer remediation-secret'
            }
        $report = New-AzdValidationReport -TemplateName example -TemplateVersion 0.1.0 -Mode verify `
            -StartedAt ([datetimeoffset]::UtcNow) -Checks @($check) -NextSteps @('Open https://example.invalid/hook?sig=next-step-secret')
        $schemaPath = Join-Path $script:repoRoot 'schemas/deployment-validation.schema.json'
        Write-AzdValidationReport -Report $report -OutputPath 'reports/safe.json' -RepositoryRoot $TestDrive -SchemaPath $schemaPath | Out-Null
        $raw = Get-Content -LiteralPath (Join-Path $TestDrive 'reports/safe.json') -Raw
        foreach ($secret in 'summary-secret', 'header-secret', 'uri-secret', 'remediation-secret', 'next-step-secret') {
            $raw | Should -Not -Match $secret
        }
        $rendered = (& { Write-AzdValidationSummary -Report $report } 6>&1 | Out-String)
        $rendered | Should -Not -Match 'summary-secret|remediation-secret'
    }

    It 'rejects invalid reports before replacing an existing report' {
        $schemaPath = Join-Path $script:repoRoot 'schemas/deployment-validation.schema.json'
        $output = Join-Path $TestDrive 'reports/existing.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
        Set-Content -LiteralPath $output -Value 'preserve-me' -NoNewline
        { Write-AzdValidationReport -Report ([pscustomobject]@{ outcome = 'passed' }) -OutputPath 'reports/existing.json' `
                -RepositoryRoot $TestDrive -SchemaPath $schemaPath } | Should -Throw '*does not satisfy*'
        Get-Content -LiteralPath $output -Raw | Should -Be 'preserve-me'
    }

    It 'rejects report paths that traverse a link or reparse point' {
        $root = Join-Path $TestDrive 'root'
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $root, $outside | Out-Null
        $linkPath = Join-Path $root 'reports'
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            New-Item -ItemType Junction -Path $linkPath -Target $outside | Out-Null
        }
        else {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $outside | Out-Null
        }
        $check = Invoke-AzdValidationCheck -Id 'context.link' -Phase context -Title 'Link' -Summary 'Link' -Action {}
        $report = New-AzdValidationReport -TemplateName example -TemplateVersion 0.1.0 -Mode verify -StartedAt ([datetimeoffset]::UtcNow) -Checks @($check)
        $schemaPath = Join-Path $script:repoRoot 'schemas/deployment-validation.schema.json'
        { Write-AzdValidationReport -Report $report -OutputPath 'reports/escape.json' -RepositoryRoot $root -SchemaPath $schemaPath } | Should -Throw '*reparse point*'
        Test-Path -LiteralPath (Join-Path $outside 'escape.json') | Should -BeFalse
    }

    It 'rejects report output outside the repository root' {
        $report = [pscustomobject]@{ outcome = 'passed' }
        { Write-AzdValidationReport -Report $report -OutputPath '../outside.json' -RepositoryRoot $TestDrive } | Should -Throw
        { Write-AzdValidationReport -Report $report -OutputPath ([System.IO.Path]::GetFullPath((Join-Path $TestDrive 'absolute.json'))) -RepositoryRoot $TestDrive } | Should -Throw
    }
}
