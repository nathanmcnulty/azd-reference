BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime/Azd.SecurityAutomation.psm1'
    Import-Module $modulePath -Force
    function Write-TestBundleManifest {
        param($Root)
        $config=Get-Content "$Root/config.json" -Raw|ConvertFrom-Json
        @{schemaVersion='1.0';files=@(Get-ChildItem $Root -File|Where-Object Name -ne 'bundle-manifest.json'|ForEach-Object {
            @{path=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}
        });sourceCommits=@($config.solutions|ForEach-Object {@{solutionId=$_.id;sourceRevision=('a'*40);runtimeRevision=('b'*40)}})}|ConvertTo-Json -Depth 10|Set-Content "$Root/bundle-manifest.json"
    }
}
Describe 'Security evidence runtime boundaries' {
    It 'accepts the Flex platform identity endpoint while rejecting unrelated or decorated endpoints' {
        InModuleScope Azd.SecurityAutomation {
            $oldEndpoint=$env:IDENTITY_ENDPOINT; $oldHeader=$env:IDENTITY_HEADER
            try {
                $env:IDENTITY_HEADER='fixture-header'
                Mock Invoke-RestMethod { @{access_token='fixture-token'} }
                $env:IDENTITY_ENDPOINT='http://169.254.255.2:8081/msi/token'
                Get-SecurityAccessToken -Resource 'https://storage.azure.com/' | Should -Be 'fixture-token'
                foreach ($unsupported in @('http://169.254.255.3:8081/msi/token','http://169.254.255.2:8082/msi/token','http://169.254.255.2:8081/other','https://example.com/msi/token','http://user@localhost/msi/token','http://localhost/msi/token#fragment')) {
                    $env:IDENTITY_ENDPOINT=$unsupported
                    { Get-SecurityAccessToken -Resource 'https://storage.azure.com/' } | Should -Throw '*identity endpoint*'
                }
                Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $MaximumRedirection -eq 0 -and $Headers['X-IDENTITY-HEADER'] -eq 'fixture-header' }
            } finally { $env:IDENTITY_ENDPOINT=$oldEndpoint; $env:IDENTITY_HEADER=$oldHeader }
        }
    }
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
        Write-TestBundleManifest $root
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
        Write-TestBundleManifest $root
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            Mock Invoke-SecurityBlobTransfer { param($Path) Set-Content -LiteralPath $Path '{}' }
            { Invoke-HostedSecurityBundle -BundleRoot $Root -ConfigurationPath "$Root/config.json" -Account 'teststorage' } | Should -Throw '*artifact hash mismatch*'
            Should -Invoke Invoke-SecurityBlobTransfer -Times 0 -Exactly -ParameterFilter { $Direction -eq 'Upload' }
        }
    }
}

Describe 'Hosted provenance and completion' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().Guid)
        New-Item -ItemType Directory $root|Out-Null
        Set-Content "$root/runner.ps1" 'param($InputPath,$OutputDirectory) Set-Content (Join-Path $OutputDirectory "review.json") (Get-Content $InputPath -Raw)'
        @{schemaVersion='1.0';solutions=@(@{id='azd-provenance';runner='runner.ps1';input='input.json'})}|ConvertTo-Json -Depth 10|Set-Content "$root/config.json"
        Write-TestBundleManifest $root
    }
    It 'rejects package file tampering before downloading or running evidence' {
        Set-Content "$root/runner.ps1" 'throw "changed"'
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            Mock Invoke-SecurityBlobTransfer {throw 'must not download'}
            {Invoke-HostedSecurityBundle -BundleRoot $Root -ConfigurationPath "$Root/config.json" -Account teststorage}|Should -Throw '*changed files*'
            Should -Invoke Invoke-SecurityBlobTransfer -Times 0 -Exactly
        }
    }
    It 'rejects missing or duplicate source identity: <Kind>' -ForEach @(@{Kind='missing'},@{Kind='duplicate'}) {
        $manifest=Get-Content "$root/bundle-manifest.json" -Raw|ConvertFrom-Json
        $manifest.sourceCommits=if($Kind -eq 'missing'){@()}else{@($manifest.sourceCommits[0],$manifest.sourceCommits[0])}
        $manifest|ConvertTo-Json -Depth 10|Set-Content "$root/bundle-manifest.json"
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            {Get-SecurityBundleProvenance -BundleRoot $Root -ConfigurationPath "$Root/config.json"}|Should -Throw '*provenance*'
        }
    }
    It 'records the actual package manifest and downloaded input hashes in the final marker' {
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            $script:completed=$null
            Mock Invoke-SecurityBlobTransfer {
                param($Direction,$Path,$Blob)
                if($Direction -ne 'Upload'){Set-Content -LiteralPath $Path '{"evidence":"test"}'}
                elseif($Blob -like '*/completed.json'){$script:completed=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
            }
            $result=Invoke-HostedSecurityBundle -BundleRoot $Root -ConfigurationPath "$Root/config.json" -Account teststorage
            $script:completed.bundleManifestSha256|Should -Be (Get-FileHash "$Root/bundle-manifest.json").Hash.ToLowerInvariant()
            $script:completed.sourceCommits[0].sourceRevision|Should -Be ('a'*40)
            $script:completed.inputs.Count|Should -Be 1
            $script:completed.inputs[0].path|Should -Be 'input.json'
            $script:completed.inputs[0].sha256|Should -Match '^[a-f0-9]{64}$'
            $script:completed.runId|Should -Be $result.runId
            $script:completed.files.Count|Should -Be 1
        }
    }
    It 'withholds every upload when an engine changes downloaded evidence: <Kind>' -ForEach @(@{Kind='overwrite'},@{Kind='delete'}) {
        $runner=if($Kind -eq 'overwrite'){'param($InputPath,$OutputDirectory) Set-Content $InputPath "changed"'}else{'param($InputPath,$OutputDirectory) Remove-Item -LiteralPath $InputPath'}
        Set-Content "$root/runner.ps1" $runner
        Write-TestBundleManifest $root
        InModuleScope Azd.SecurityAutomation -Parameters @{Root=$root} {
            param($Root)
            Mock Invoke-SecurityBlobTransfer {param($Direction,$Path) if($Direction -ne 'Upload'){Set-Content $Path '{}'}}
            {Invoke-HostedSecurityBundle -BundleRoot $Root -ConfigurationPath "$Root/config.json" -Account teststorage}|Should -Throw '*changed*evidence*'
            Should -Invoke Invoke-SecurityBlobTransfer -Times 0 -Exactly -ParameterFilter {$Direction -eq 'Upload'}
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
