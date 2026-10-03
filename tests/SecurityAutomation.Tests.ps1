BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime/Azd.SecurityAutomation.psm1'
    Import-Module $modulePath -Force
}
Describe 'Security evidence runtime boundaries' {
    It 'rejects write-oriented Graph endpoints before requesting a token' {
        { Invoke-SecurityGraphRead -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -Method POST -Body @{} } | Should -Throw '*read-only*'
    }
    It 'rejects alternative token destinations' {
        { Invoke-SecurityGraphRead -Uri 'https://graph.microsoft.com.example.org/v1.0/devices' } | Should -Throw '*HTTPS*'
    }
    It 'rejects parent traversal' {
        { Resolve-SecurityBundlePath -Root $TestDrive -RelativePath '../outside.ps1' } | Should -Throw '*traversal*'
    }
    It 'fails when configured evidence is absent' {
        $config = Join-Path $TestDrive 'config.json'
        @{schemaVersion='1.0';solutions=@(@{id='azd-test';runner='runner.ps1';input='absent.json'})} | ConvertTo-Json -Depth 5 | Set-Content $config
        { Invoke-SecurityBundle -BundleRoot $TestDrive -ConfigurationPath $config -InputDirectory $TestDrive -OutputDirectory $TestDrive } | Should -Throw '*Missing evidence*'
    }
    It 'runs the configured engine with absolute paths' {
        $config = Join-Path $TestDrive 'valid.json'
        Set-Content (Join-Path $TestDrive 'evidence.json') '{}'
        Set-Content (Join-Path $TestDrive 'runner.ps1') 'param($InputPath,$OutputDirectory) if (-not [IO.Path]::IsPathRooted($InputPath)) { throw "relative" }; Set-Content (Join-Path $OutputDirectory "review.json") (Get-Content $InputPath -Raw)'
        @{schemaVersion='1.0';solutions=@(@{id='azd-test';runner='runner.ps1';input='evidence.json'})} | ConvertTo-Json -Depth 5 | Set-Content $config
        Invoke-SecurityBundle -BundleRoot $TestDrive -ConfigurationPath $config -InputDirectory $TestDrive -OutputDirectory $TestDrive
        Test-Path (Join-Path $TestDrive 'azd-test/review.json') | Should -BeTrue
    }
    It 'rejects external pagination links' {
        InModuleScope Azd.SecurityAutomation {
            Mock Get-SecurityAccessToken { 'test-token' }
            Mock Invoke-RestMethod { [pscustomobject]@{value=@();'@odata.nextLink'='https://example.org/v1.0/devices'} }
            { Invoke-SecurityGraphRead -Uri 'https://graph.microsoft.com/v1.0/devices' } | Should -Throw '*pagination*'
        }
    }
}
