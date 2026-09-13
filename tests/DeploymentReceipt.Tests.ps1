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

        $caseFolded = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode Plan
        $caseFolded.mode | Should -Be 'plan'
        Write-AzdDeploymentReceipt -Receipt $caseFolded -RepositoryRoot $TestDrive -OutputPath 'reports/case-folded-plan.json' -SchemaPath $script:schemaPath | Should -Be 'reports/case-folded-plan.json'
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

    It 'revalidates direct receipt objects before writing' {
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce
        $receipt.template = ''
        { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath } | Should -Throw '*Template must be nonempty*'

        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce
        $receipt.artifacts = @('reports/output.json?sig=secret')
        { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath } | Should -Throw '*cannot be written*'

        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce
        $receipt.artifacts = @((1..501 | ForEach-Object { "reports/$_.json" }))
        { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath } | Should -Throw '*limited to 500*'
        $receipt.artifacts = @()
        $receipt.operationalActions = @((1..501 | ForEach-Object { "Action $_" }))
        { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath } | Should -Throw '*limited to 500*'
    }

    It 'rejects ambiguous output paths before creating directories or moving the receipt' {
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce
        $root = Join-Path $TestDrive 'ambiguous-output-root'
        New-Item -ItemType Directory -Path $root | Out-Null
        foreach ($outputPath in @('', '.', 'reports/', 'reports//receipt.json', 'reports/./receipt.json', 'reports/receipt.json:metadata', 'reports\receipt.json')) {
            { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $root -OutputPath $outputPath -SchemaPath $script:schemaPath } | Should -Throw
        }
        Test-Path -LiteralPath (Join-Path $root 'reports') | Should -BeFalse
    }

    It 'rejects an existing directory as the receipt target' {
        $root = Join-Path $TestDrive 'directory-target-root'
        $reports = Join-Path $root 'reports'
        New-Item -ItemType Directory -Path $reports -Force | Out-Null
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce

        { Write-AzdDeploymentReceipt -Receipt $receipt -RepositoryRoot $root -OutputPath 'reports' -SchemaPath $script:schemaPath } | Should -Throw '*must name a file*'
        @(Get-ChildItem -LiteralPath $reports -Force).Count | Should -Be 0
    }

    It 'includes the emitted newline in the receipt byte limit' {
        $receipt = New-AzdDeploymentReceipt -Template example -TemplateVersion 0.1.0 -Mode enforce
        $payloadBytes = [System.Text.Encoding]::UTF8.GetByteCount(($receipt | ConvertTo-Json -Depth 30) + "`n")
        $root = Join-Path $TestDrive 'byte-limit-root'
        New-Item -ItemType Directory -Path $root | Out-Null

        InModuleScope Azd.DeploymentReceipt {
            param($Receipt, $RepositoryRoot, $SchemaPath, $PayloadBytes)
            $originalLimit = $script:MaxReceiptBytes
            try {
                $script:MaxReceiptBytes = $PayloadBytes
                { Write-AzdDeploymentReceipt -Receipt $Receipt -RepositoryRoot $RepositoryRoot -SchemaPath $SchemaPath } | Should -Not -Throw
                $script:MaxReceiptBytes = $PayloadBytes - 1
                { Write-AzdDeploymentReceipt -Receipt $Receipt -RepositoryRoot $RepositoryRoot -OutputPath 'reports/too-small.json' -SchemaPath $SchemaPath } | Should -Throw '*exceeds 1 MiB*'
            }
            finally {
                $script:MaxReceiptBytes = $originalLimit
            }
        } -Parameters @{ Receipt = $receipt; RepositoryRoot = $root; SchemaPath = $script:schemaPath; PayloadBytes = $payloadBytes }
    }

    It 'does not replace an existing receipt when the supplied receipt is invalid' {
        $reports = Join-Path $TestDrive 'reports'
        New-Item -ItemType Directory -Path $reports -Force | Out-Null
        $path = Join-Path $reports 'deployment-receipt.json'
        Set-Content -LiteralPath $path -Value 'preserve-me' -NoNewline

        $invalid = [pscustomobject]@{
            schemaVersion = '1.0'
            template = 'example'
            templateVersion = '0.1.0'
            mode = 'plan'
            summary = @{ applied = 1 }
            artifacts = @()
            operationalActions = @()
            details = @{}
        }
        { Write-AzdDeploymentReceipt -Receipt $invalid -RepositoryRoot $TestDrive -SchemaPath $script:schemaPath } | Should -Throw '*cannot report applied*'
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
