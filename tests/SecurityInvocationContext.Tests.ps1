BeforeAll {
    $modulePath=Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime/Azd.SecurityAutomation.psm1'
    Import-Module $modulePath -Force
    function New-ContextFixture {
        param($Root)
        $null=New-Item -ItemType Directory $Root -Force
        Set-Content (Join-Path $Root 'inside.txt') 'synthetic'
        New-SecurityInvocationContext -Mode Hosted -EvidenceRoot $Root
    }
}
Describe 'Explicit immutable invocation context' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $context=New-ContextFixture $root
    }
    It 'uses sealed immutable string values with unique invocation IDs' {
        $context.GetType().IsSealed | Should -BeTrue
        $context | Should -BeOfType ([Collections.Immutable.ImmutableDictionary[string,string]])
        { $context['mode']='Offline' } | Should -Throw
        $changed=$context.SetItem('mode','Offline')
        (New-SecurityInvocationContext -Mode hosted -EvidenceRoot $root)['mode'] | Should -BeExactly Hosted
        $context['mode'] | Should -BeExactly Hosted
        $changed['mode'] | Should -BeExactly Offline
        (New-SecurityInvocationContext -Mode Hosted -EvidenceRoot $root)['invocationId'] | Should -Not -Be $context['invocationId']
    }
    It 'preserves exact context type across runspace argument binding' {
        $worker=[PowerShell]::Create()
        try {
            $null=$worker.AddScript('param($context) $context.GetType() -eq [Collections.Immutable.ImmutableDictionary[string,string]]').AddArgument($context)
            @($worker.Invoke())[0] | Should -BeTrue
        } finally { $worker.Dispose() }
    }
    It 'rejects mutable, deserialized, null and invalid version contexts' {
        foreach ($bad in @(@{mode='Hosted';evidenceRoot=$root},[pscustomobject]@{mode='Hosted';evidenceRoot=$root},$null,$context.SetItem('contractVersion','1.0'),$context.SetItem('mode','hosted'),$context.Remove('invocationId'),$context.Add('extra','value'),$context.SetItem('invocationId',''))) {
            { Resolve-SecurityEvidencePath -Path inside.txt -InputDirectory $root -InvocationContext $bad } | Should -Throw
        }
    }
    It 'allows own relative and absolute reads but denies cross-root, sibling-prefix and outside reads' {
        $own=Join-Path $root 'inside.txt'
        $sibling=New-ContextFixture ($root+'-sibling')
        Resolve-SecurityEvidencePath -Path inside.txt -InputDirectory $root -InvocationContext $context | Should -Be $own
        Resolve-SecurityEvidencePath -Path $own -InputDirectory $root -InvocationContext $context | Should -Be $own
        foreach ($outside in @((Join-Path $sibling['evidenceRoot'] 'inside.txt'), '../outside.txt')) {
            { Resolve-SecurityEvidencePath -Path $outside -InputDirectory $root -InvocationContext $context } | Should -Throw '*escapes*'
        }
        { Resolve-SecurityEvidencePath -Path absent.txt -InputDirectory $root -InvocationContext $context } | Should -Throw '*not found*'
    }
    It 'rejects provider paths rather than treating them as evidence' {
        foreach($path in @('env:PATH','variable:value','https://example.invalid/evidence')) {
            { Resolve-SecurityEvidencePath -Path $path -InputDirectory $root -InvocationContext $context } | Should -Throw
        }
    }
    It 'preserves intentional offline absolute and parent-relative paths' {
        $other=New-ContextFixture ($root+'-other')
        $offline=New-SecurityInvocationContext -Mode Offline -EvidenceRoot $root
        $file=Join-Path $other['evidenceRoot'] 'inside.txt'
        Resolve-SecurityEvidencePath -Path $file -InputDirectory $root -InvocationContext $offline | Should -Be $file
        Resolve-SecurityEvidencePath -Path ([IO.Path]::GetRelativePath($root,$file)) -InputDirectory $root -InvocationContext $offline | Should -Be $file
    }
    It 'rejects links inside and above the evidence root' {
        $other=New-ContextFixture ($root+'-other')
        $link=Join-Path $root 'linked'
        $null=New-Item -ItemType SymbolicLink -Path $link -Target $other['evidenceRoot']
        { Resolve-SecurityEvidencePath -Path linked/inside.txt -InputDirectory $root -InvocationContext $context } | Should -Throw '*link*'
        $nested=Join-Path $other['evidenceRoot'] 'nested'
        $null=New-Item -ItemType Directory $nested
        { New-SecurityInvocationContext -Mode Hosted -EvidenceRoot (Join-Path $link 'nested') } | Should -Throw '*link*'
    }
    It 'applies platform-sensitive root comparison' {
        if ($IsWindows) {
            Resolve-SecurityEvidencePath -Path (Join-Path $root.ToUpperInvariant() 'inside.txt') -InputDirectory $root -InvocationContext $context | Should -Not -BeNullOrEmpty
        } else {
            { Resolve-SecurityEvidencePath -Path (Join-Path $root.ToUpperInvariant() 'inside.txt') -InputDirectory $root -InvocationContext $context } | Should -Throw '*escapes*'
        }
    }
}
Describe 'All-runner invocation contract preflight' {
    BeforeEach {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $context=New-ContextFixture $root
        $config=Join-Path $root 'config.json'
        Set-Content (Join-Path $root 'runner.ps1') 'param($InputPath,$OutputDirectory,$InvocationContext) Set-Content (Join-Path $OutputDirectory "ran") $InvocationContext["mode"]'
        $configuration=@{schemaVersion='2.0';solutions=@(@{id='azd-first';runner='runner.ps1';runnerContractVersion='2.0';input='inside.txt'})}
    }
    It 'rejects missing context without executing a runner' {
        $configuration | ConvertTo-Json -Depth 5 | Set-Content $config
        # Binding is inspected without invoking an interactive mandatory-parameter prompt.
        (Get-Command Invoke-SecurityBundle).ParameterSets | ForEach-Object {
            @($_.Parameters | Where-Object { $_.IsMandatory -and $_.Name -in @('InvocationContext','Offline') }).Count | Should -Be 1
        }
        { Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $root -OutputDirectory $root -InvocationContext $null } | Should -Throw
        Test-Path (Join-Path $root 'azd-first/ran') | Should -BeFalse
    }
    It 'rejects mixed compatible and <Kind> runners before any runner executes' -ForEach @(
        @{Kind='old simple';Code='param($InputPath,$OutputDirectory) throw "must not run"';Version='2.0'}
        @{Kind='old advanced';Code='[CmdletBinding()]param($InputPath,$OutputDirectory) throw "must not run"';Version='2.0'}
        @{Kind='unknown contract';Code='param($InputPath,$OutputDirectory,$InvocationContext) throw "must not run"';Version='3.0'}
    ) {
        Set-Content (Join-Path $root 'old.ps1') $Code
        $configuration.solutions+=@{id='azd-second';runner='old.ps1';runnerContractVersion=$Version;input='inside.txt'}
        $configuration | ConvertTo-Json -Depth 5 | Set-Content $config
        { Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $root -OutputDirectory $root -InvocationContext $context } | Should -Throw '*Runner*'
        Test-Path (Join-Path $root 'azd-first/ran') | Should -BeFalse
    }
    It 'rejects legacy hosted bundles but retains explicit legacy offline invocation' {
        $configuration.schemaVersion='1.0'
        Set-Content (Join-Path $root 'runner.ps1') '[CmdletBinding()]param($InputPath,$OutputDirectory) Set-Content (Join-Path $OutputDirectory "ran") "offline"'
        $configuration | ConvertTo-Json -Depth 5 | Set-Content $config
        { Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $root -OutputDirectory $root -InvocationContext $context } | Should -Throw '*contract 2.0*'
        Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $root -OutputDirectory $root -Offline
        Get-Content (Join-Path $root 'azd-first/ran') | Should -Be offline
    }
    It 'passes the immutable context to an advanced contract runner and rejects mismatched roots' {
        $configuration | ConvertTo-Json -Depth 5 | Set-Content $config
        Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $root -OutputDirectory $root -InvocationContext $context
        Get-Content (Join-Path $root 'azd-first/ran') | Should -Be Hosted
        { Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $TestDrive -OutputDirectory $root -InvocationContext $context } | Should -Throw '*does not match*'
        { Invoke-SecurityBundle -BundleRoot $root -ConfigurationPath $config -InputDirectory $root -OutputDirectory $root -Offline:$false } | Should -Throw
    }
}
Describe 'Actual canonical two-runspace isolation' {
    BeforeAll { . (Join-Path $PSScriptRoot 'fixtures/SecurityInvocationOverlap.ps1') }
    It 'keeps own roots and cleanup isolated: first <First>, failure <Fail>, environment <Environment>' -ForEach @(
        @{First='A';Fail=$false;Environment=''}
        @{First='B';Fail=$false;Environment=''}
        @{First='A';Fail=$true;Environment=''}
        @{First='B';Fail=$true;Environment=''}
        @{First='A';Fail=$false;Environment='synthetic-original-boundary'}
        @{First='B';Fail=$false;Environment='synthetic-original-boundary'}
        @{First='A';Fail=$true;Environment='synthetic-original-boundary'}
        @{First='B';Fail=$true;Environment='synthetic-original-boundary'}
    ) {
        $root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $observations=@(Invoke-SecurityInvocationOverlapFixture -ModulePath $modulePath -Root $root -First $First -FailFirst $Fail -OriginalEnvironment $Environment)
        $observations.Count | Should -Be 2
        @($observations.id | Select-Object -Unique).Count | Should -Be 2
        @($observations.root | Select-Object -Unique).Count | Should -Be 2
        @($observations | Where-Object peerCleaned).Count | Should -Be 1
    }
}
