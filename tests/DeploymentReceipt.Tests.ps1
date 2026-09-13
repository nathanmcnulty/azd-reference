Describe 'Deployment receipt writer' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:modulePath = Join-Path $script:repoRoot 'components/powershell/deployment-receipt/Azd.DeploymentReceipt.psd1'
        $script:schemaPath = Join-Path $script:repoRoot 'schemas/deployment-receipt.schema.json'
        Import-Module $script:modulePath -Force
    }

    It 'creates plan receipts with no applied actions' {
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode plan -Skipped 2 -Details @{ feature = 'example' }

        $receipt.schemaVersion | Should -Be '1.0'
        $receipt.mode | Should -Be 'plan'
        $receipt.summary.applied | Should -Be 0
        $receipt.summary.skipped | Should -Be 2
        { New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode plan -Applied 1 } | Should -Throw '*cannot report applied*'
    }

    It 'writes an atomic schema-valid enforce receipt to the producer-owned default path' {
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce -Applied 1 `
            -Artifacts 'reports/deployment-validation.json' -OperationalActions 'Prove live delivery.' -Details @{ feature = 'example' }

        $relative = Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath
        $relative | Should -Be 'reports/deployment-receipt.json'
        $path = Join-Path $TestDrive $relative
        Test-Path -LiteralPath $path | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw | Test-Json -SchemaFile $script:schemaPath -ErrorAction Stop) | Should -BeTrue
    }

    It 'rejects obvious sensitive data and unsafe artifact paths before writing' {
        { New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce -Details @{ clientSecret = 'do-not-write' } } | Should -Throw '*sensitive*'
        { New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce -OperationalActions 'Bearer do-not-write' } | Should -Throw '*cannot be written*'
        { New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce -Artifacts '../outside.json' } | Should -Throw '*repository-relative*'
    }

    It 'does not replace an existing receipt when the supplied receipt is invalid' {
        $reports = Join-Path $TestDrive 'reports'
        New-Item -ItemType Directory -Path $reports -Force | Out-Null
        $path = Join-Path $reports 'deployment-receipt.json'
        Set-Content -LiteralPath $path -Value 'preserve-me' -NoNewline

        { Write-AzdDeploymentReceipt -Receipt ([pscustomobject]@{ mode = 'plan'; summary = @{ applied = 1 } }) -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath } | Should -Throw '*cannot report applied*'
        Get-Content -LiteralPath $path -Raw | Should -Be 'preserve-me'
    }

    It 'rejects a report directory that traverses a reparse point' {
        $root = Join-Path $TestDrive 'root'
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $root, $outside | Out-Null
        $link = Join-Path $root 'reports'
        if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
            New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
        }
        else {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside | Out-Null
        }
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce

        { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $root -SchemaPath $script:schemaPath } | Should -Throw '*reparse point*'
        Test-Path -LiteralPath (Join-Path $outside 'deployment-receipt.json') | Should -BeFalse
    }
}
