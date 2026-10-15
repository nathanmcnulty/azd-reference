BeforeAll {
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
}

Describe 'Supported PowerShell and Pester baseline' {
    It 'runs validation on PowerShell 7.6 and Pester 6.2 or later' {
        $PSVersionTable.PSVersion | Should -BeGreaterOrEqual ([version]'7.6')
        [Environment]::Is64BitProcess | Should -BeTrue
        (Get-Module Pester).Version | Should -BeGreaterOrEqual ([version]'6.2.0')
    }

    It 'declares the supported minimum and matching version in <Component>' -ForEach @(
        @{ Component = 'deployment-validation' }
        @{ Component = 'deployment-receipt' }
        @{ Component = 'graph-delegated-authentication' }
    ) {
        $componentRoot = Join-Path $script:repoRoot "components/powershell/$Component"
        $componentManifest = Get-Content (Join-Path $componentRoot 'component.json') -Raw | ConvertFrom-Json
        $modulePath = Get-ChildItem -LiteralPath $componentRoot -Filter '*.psd1'
        $moduleManifest = Import-PowerShellDataFile -LiteralPath $modulePath.FullName
        $moduleManifest.PowerShellVersion | Should -Be '7.6'
        $moduleManifest.ModuleVersion | Should -Be $componentManifest.version
    }

    It 'requires PowerShell 7.6 in <Tool>' -ForEach @(
        @{ Tool = 'Export-AzdBacklogMarkdown.ps1' }
        @{ Tool = 'Get-AzdBacklogStatus.ps1' }
        @{ Tool = 'Get-AzdPermissionComparison.ps1' }
        @{ Tool = 'Test-AzdBacklog.ps1' }
    ) {
        $toolPath = Join-Path $script:repoRoot "tooling/$Tool"
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($toolPath, [ref] $tokens, [ref] $errors)
        $errors | Should -BeNullOrEmpty
        $ast.ScriptRequirements.RequiredPSVersion | Should -Be ([version]'7.6')
    }
}
