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
    It 'rejects changed declared artifact content before running an engine' {
        $root=Join-Path $TestDrive 'artifact-change'
        New-Item -ItemType Directory $root | Out-Null
        Set-Content "$root/runner.ps1" 'param($InputPath,$OutputDirectory) throw "Engine must not run"'
        @{schemaVersion='1.0';solutions=@(@{id='azd-artifacts';runner='runner.ps1';input='input.json';artifactFiles=@(@{blob='policy.xml';path='policy.xml';sha256=('0'*64)})})} | ConvertTo-Json -Depth 10 | Set-Content "$root/config.json"
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            Mock Invoke-SecurityBlobTransfer { param($Path) Set-Content -LiteralPath $Path '{}' }
            { Invoke-HostedSecurityBundle -BundleRoot $Root -ConfigurationPath "$Root/config.json" -Account 'teststorage' } | Should -Throw '*artifact hash mismatch*'
            Should -Invoke Invoke-SecurityBlobTransfer -Times 0 -Exactly -ParameterFilter { $Direction -eq 'Upload' }
        }
    }
}

Describe 'Immutable package republication' {
    It 'reuses existing content only when its downloaded hash matches: <HashMatches>' -ForEach @(@{HashMatches=$true},@{HashMatches=$false}) {
        $package=Join-Path $TestDrive 'approved.zip'
        [IO.File]::WriteAllText($package,'approved-content')
        InModuleScope Azd.SecurityAutomation -Parameters @{Package=$package;HashMatches=$HashMatches} {
            param($Package,$HashMatches)
            $script:downloadContent=if($HashMatches){'approved-content'}else{'different-content'}
            Mock Get-SecurityAccessToken { 'test-token' }
            Mock Invoke-WebRequest {
                param($Method,$OutFile)
                if($Method -eq 'Put') {
                    $exception=[Exception]::new('already exists')
                    $exception|Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{StatusCode=412})
                    throw $exception
                }
                [IO.File]::WriteAllText($OutFile,$script:downloadContent)
            }
            if($HashMatches){ Invoke-SecurityBlobTransfer -Account teststorage -Container packages -Blob approved.zip -Path $Package -Direction Upload }
            else { { Invoke-SecurityBlobTransfer -Account teststorage -Container packages -Blob approved.zip -Path $Package -Direction Upload } | Should -Throw '*Immutable package verification failed*' }
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {$Method -eq 'Put'}
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {$OutFile}
        }
    }
}
