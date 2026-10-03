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
    It 'rejects same-host POST pagination to write endpoints' {
        InModuleScope Azd.SecurityAutomation {
            Mock Get-SecurityAccessToken { 'test-token' }
            Mock Invoke-RestMethod { [pscustomobject]@{value=@();'@odata.nextLink'='https://graph.microsoft.com/v1.0/groups'} }
            { Invoke-SecurityGraphRead -Uri 'https://graph.microsoft.com/v1.0/security/runHuntingQuery' -Method POST -Body @{Query='DeviceEvents | take 1'} } | Should -Throw '*POST pagination*'
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly
        }
    }
    It 'does not publish a completion marker after a partial upload failure' {
        $root=Join-Path $TestDrive 'partial'
        New-Item -ItemType Directory $root | Out-Null
        Set-Content "$root/runner.ps1" 'param($InputPath,$OutputDirectory) Set-Content (Join-Path $OutputDirectory "one.json") "{}"; Set-Content (Join-Path $OutputDirectory "two.json") "{}"'
        @{schemaVersion='1.0';solutions=@(@{id='azd-partial';runner='runner.ps1';input='input.json'})} | ConvertTo-Json -Depth 10 | Set-Content "$root/config.json"
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            $script:uploadCount=0
            Mock Invoke-SecurityBlobTransfer {
                param($Direction,$Path)
                if ($Direction -eq 'Upload') { $script:uploadCount++; if ($script:uploadCount -eq 2) { throw 'Upload failed' } }
                else { Set-Content -LiteralPath $Path '{}' }
            }
            { Invoke-HostedSecurityBundle -BundleRoot $Root -ConfigurationPath "$Root/config.json" -Account 'teststorage' } | Should -Throw '*Upload failed*'
            Should -Invoke Invoke-SecurityBlobTransfer -Times 0 -Exactly -ParameterFilter { $Blob -like '*/completed.json' }
        }
    }
}
