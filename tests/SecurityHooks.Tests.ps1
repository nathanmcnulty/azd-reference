BeforeAll {
    $component=Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime'
    . (Join-Path $PSScriptRoot 'fixtures/SecurityOperatorHarness.ps1')
}
AfterAll { Remove-SecurityOperatorHarness }
Describe 'Security azd hook transitions' {
    BeforeEach { New-SecurityOperatorFixture -Component $component -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) }
    It 'explicitly pauses the default existing Automation schedule when disabled' {
        Invoke-SecurityOperatorEntry Initialize
        $global:SecurityOperator.ScheduleEnabled | Should -BeFalse
        ($global:SecurityOperator.Writes -join ',') | Should -Be 'Patch'
    }
    It 'rejects an enabled unconfigured package before writes' {
        $global:SecurityOperator.Environment.SECURITY_SCHEDULE_ENABLED='true'
        { Invoke-SecurityOperatorEntry Initialize } | Should -Throw '*approved immutable*'
        $global:SecurityOperator.Writes.Count | Should -Be 0
    }
    It 'rejects switching an existing environment to another compute kind before writes' {
        $global:SecurityOperator.Environment.SECURITY_DEPLOYED_COMPUTE_MODE='function'
        { Invoke-SecurityOperatorEntry Initialize } | Should -Throw '*separate azd environment*'
        $global:SecurityOperator.Writes.Count | Should -Be 0
    }
    It 'refreshes Automation parameters using the published package without republishing' {
        $result=Invoke-SecurityOperatorEntry Deploy
        @($global:SecurityOperator.Writes | Where-Object { $_ -eq 'Publish' }).Count | Should -Be 1
        $global:SecurityOperator.ProvisionedHash | Should -Be $result.bundleSha256
        @($global:SecurityOperator.Writes | Where-Object { $_ -eq 'Provision' }).Count | Should -Be 1
        $global:SecurityOperator.Environment.SECURITY_DEPLOYED_COMPUTE_MODE | Should -Be 'automation'
    }
    It 'preserves local default-off initialization without Azure or token access' {
        $global:SecurityOperator.Environment=@{AZURE_ENV_NAME='approved-environment'}
        Invoke-SecurityOperatorEntry Initialize
        $global:SecurityOperator.Environment.SECURITY_COMPUTE_MODE | Should -Be 'none'
        $global:SecurityOperator.Environment.SECURITY_SCHEDULE_ENABLED | Should -Be 'false'
        @($global:SecurityOperator.Native | Where-Object { $_ -like 'az *' }).Count | Should -Be 0
        $global:SecurityOperator.Http.Count | Should -Be 0
    }
    It 'leaves local deployment mode free of package creation and mutations' {
        $global:SecurityOperator.Environment=@{SECURITY_COMPUTE_MODE='none'}
        Invoke-SecurityOperatorEntry Deploy
        $global:SecurityOperator.Writes.Count | Should -Be 0
        $global:SecurityOperator.Events.Count | Should -Be 0
    }
}
