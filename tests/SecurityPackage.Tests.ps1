BeforeAll {
    $component=Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime'
    $builder=Join-Path $component 'Build-SecurityBundle.ps1'
    function New-PackageTestSource {
        param([string]$Path,[string]$Id,[string]$Revision=('a'*40))
        New-Item -ItemType Directory -Path "$Path/scripts/vendor/Azd.SecurityAutomation","$Path/SecurityReview" -Force | Out-Null
        Copy-Item "$component/Azd.SecurityAutomation.psm1" "$Path/scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1"
        Copy-Item "$component/host.json" "$Path/host.json"
        Copy-Item "$component/function.json" "$Path/SecurityReview/function.json"
        Copy-Item "$component/run.ps1" "$Path/SecurityReview/run.ps1"
        Set-Content "$Path/scripts/Invoke-Solution.ps1" 'param($InputPath,$OutputDirectory) Set-Content (Join-Path $OutputDirectory "review.json") "{}"'
        @{solutionId=$Id} | ConvertTo-Json | Set-Content "$Path/azd-permissions.json"
        $files=@('scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1','host.json','SecurityReview/function.json','SecurityReview/run.ps1') | ForEach-Object {
            @{target=$_;sha256=(Get-FileHash "$Path/$_").Hash.ToLowerInvariant()}
        }
        @{components=@(@{id='security-automation-runtime';sourceRevision=$Revision;files=@($files)})} | ConvertTo-Json -Depth 10 | Set-Content "$Path/azd-components.lock.json"
        & git -C $Path init --quiet
        & git -C $Path config core.autocrlf false
        & git -C $Path add .
        & git -C $Path -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Fixture source'
        if ($LASTEXITCODE -ne 0) { throw 'Fixture Git commit failed.' }
    }
}
Describe 'Immutable security packages' {
    It 'packages two clean engines with exact source commits and excludes untracked files' {
        $one=Join-Path $TestDrive 'one'; $two=Join-Path $TestDrive 'two'
        New-PackageTestSource $one 'azd-one'; New-PackageTestSource $two 'azd-two'
        Set-Content "$one/scripts/local-secret.ps1" 'untracked-local-content'
        $result=& $builder -SolutionRoot @($one,$two) -OutputPath "$TestDrive/combined.zip"
        Expand-Archive $result.path "$TestDrive/expanded"
        Test-Path "$TestDrive/expanded/azd-one/scripts/local-secret.ps1" | Should -BeFalse
        $manifest=Get-Content "$TestDrive/expanded/bundle-manifest.json" -Raw | ConvertFrom-Json
        @($manifest.sourceCommits).Count | Should -Be 2
        $manifest.sourceCommits[0].sourceRevision | Should -Match '^[a-f0-9]{40}$'
    }
    It 'rejects dirty tracked code' {
        $root=Join-Path $TestDrive 'dirty'; New-PackageTestSource $root 'azd-dirty'
        Add-Content "$root/scripts/Invoke-Solution.ps1" '# dirty'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/dirty.zip" } | Should -Throw '*dirty tracked*'
    }
    It 'rejects mixed runtime revisions' {
        $one=Join-Path $TestDrive 'mix-one'; $two=Join-Path $TestDrive 'mix-two'
        New-PackageTestSource $one 'azd-mix-one'; New-PackageTestSource $two 'azd-mix-two' ('b'*40)
        { & $builder -SolutionRoot @($one,$two) -OutputPath "$TestDrive/mixed.zip" } | Should -Throw '*Mixed*'
    }
    It 'rejects committed component drift' {
        $root=Join-Path $TestDrive 'drift'; New-PackageTestSource $root 'azd-drift'
        Add-Content "$root/scripts/vendor/Azd.SecurityAutomation/Azd.SecurityAutomation.psm1" '# drift'
        & git -C $root add .
        & git -C $root -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Drift fixture'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/drift.zip" } | Should -Throw '*drift*'
    }
}
