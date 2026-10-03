BeforeAll {
    $component=Join-Path $PSScriptRoot '../components/powershell/security-automation-runtime'
    $referenceRoot=(Resolve-Path (Join-Path $component '../../..')).Path
    $builder=Join-Path $component 'Build-SecurityBundle.ps1'
    $runtimeManifest=Get-Content (Join-Path $component 'component.json') -Raw | ConvertFrom-Json
    function New-PackageTestSource {
        param([string]$Path,[string]$Id,[string]$Revision=('a'*40))
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        foreach ($file in $runtimeManifest.files) {
            $target=Join-Path $Path $file.target
            New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
            Copy-Item (Join-Path $referenceRoot $file.source) $target
        }
        Set-Content "$Path/scripts/Invoke-Solution.ps1" 'param($InputPath,$OutputDirectory) Set-Content (Join-Path $OutputDirectory "review.json") "{}"'
        @{solutionId=$Id} | ConvertTo-Json | Set-Content "$Path/azd-permissions.json"
        $files=$runtimeManifest.files | ForEach-Object {
            @{source=$_.source;target=$_.target;sha256=(Get-FileHash (Join-Path $Path $_.target)).Hash.ToLowerInvariant()}
        }
        @{manifestVersion='1.0';components=@(@{id='security-automation-runtime';version='0.1.2';sourceRepository='https://github.com/nathanmcnulty/azd-reference';sourceRevision=$Revision;files=@($files)})} | ConvertTo-Json -Depth 10 | Set-Content "$Path/azd-components.lock.json"
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
        @{schemaVersion='1.0';solutions=@(@{id='azd-one';input='evidence/one.json';artifactFiles=@(@{path='policies/one.xml';blob='approved/one.xml';sha256=('a'*64)})})} | ConvertTo-Json -Depth 10 | Set-Content "$one/security-bundle.json"
        & git -C $one add security-bundle.json
        & git -C $one -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Reviewed bundle configuration'
        Set-Content "$one/scripts/local-secret.ps1" 'untracked-local-content'
        $result=& $builder -SolutionRoot @($one,$two) -OutputPath "$TestDrive/combined.zip"
        Expand-Archive $result.path "$TestDrive/expanded"
        Test-Path "$TestDrive/expanded/azd-one/scripts/local-secret.ps1" | Should -BeFalse
        $manifest=Get-Content "$TestDrive/expanded/bundle-manifest.json" -Raw | ConvertFrom-Json
        @($manifest.sourceCommits).Count | Should -Be 2
        $manifest.sourceCommits[0].sourceRevision | Should -Match '^[a-f0-9]{40}$'
        $configuration=Get-Content "$TestDrive/expanded/security-bundle.json" -Raw | ConvertFrom-Json
        $oneConfiguration=@($configuration.solutions | Where-Object id -eq 'azd-one')[0]
        $oneConfiguration.input | Should -Be 'evidence/one.json'
        $oneConfiguration.artifactFiles[0].path | Should -Be 'policies/one.xml'
    }
    It 'rejects dirty tracked code' {
        $root=Join-Path $TestDrive 'dirty'; New-PackageTestSource $root 'azd-dirty'
        Add-Content "$root/scripts/Invoke-Solution.ps1" '# dirty'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/dirty.zip" } | Should -Throw '*dirty tracked*'
    }
    It 'rejects an untracked source bundle configuration' {
        $root=Join-Path $TestDrive 'untracked-config'; New-PackageTestSource $root 'azd-untracked-config'
        @{schemaVersion='1.0';solutions=@(@{id='azd-untracked-config';input='custom/input.json'})} | ConvertTo-Json -Depth 5 | Set-Content "$root/security-bundle.json"
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/untracked-config.zip" } | Should -Throw '*configuration must be tracked*'
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
    It 'rejects a missing file from a non-runtime component lock' {
        $root=Join-Path $TestDrive 'missing-component'; New-PackageTestSource $root 'azd-missing-component'
        $lock=Get-Content "$root/azd-components.lock.json" -Raw | ConvertFrom-Json
        $lock.components += @{id='security-automation-host';version='0.1.0';sourceRepository='https://github.com/nathanmcnulty/azd-reference';sourceRevision=('b'*40);files=@(@{source='components/bicep/security-automation-host/security-automation-host.bicep';target='infra/vendor/security-automation-host.bicep';sha256=('0'*64)})}
        $lock | ConvertTo-Json -Depth 10 | Set-Content "$root/azd-components.lock.json"
        & git -C $root add azd-components.lock.json
        & git -C $root -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Missing component fixture'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/missing-component.zip" } | Should -Throw '*component file is missing*'
    }
    It 'rejects hash drift in a non-runtime component lock' {
        $root=Join-Path $TestDrive 'other-drift'; New-PackageTestSource $root 'azd-other-drift'
        New-Item -ItemType Directory "$root/infra/vendor" -Force | Out-Null
        Set-Content "$root/infra/vendor/security-automation-host.bicep" 'fixture'
        $lock=Get-Content "$root/azd-components.lock.json" -Raw | ConvertFrom-Json
        $lock.components += @{id='security-automation-host';version='0.1.0';sourceRepository='https://github.com/nathanmcnulty/azd-reference';sourceRevision=('b'*40);files=@(@{source='components/bicep/security-automation-host/security-automation-host.bicep';target='infra/vendor/security-automation-host.bicep';sha256=('0'*64)})}
        $lock | ConvertTo-Json -Depth 10 | Set-Content "$root/azd-components.lock.json"
        & git -C $root add azd-components.lock.json infra/vendor/security-automation-host.bicep
        & git -C $root -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Other component drift fixture'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/other-drift.zip" } | Should -Throw '*component file drift*'
    }
    It 'rejects a malformed runtime source revision' {
        $root=Join-Path $TestDrive 'bad-revision'; New-PackageTestSource $root 'azd-bad-revision' 'not-a-commit'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/bad-revision.zip" } | Should -Throw
    }
    It 'rejects a lock that omits a host entrypoint' {
        $root=Join-Path $TestDrive 'omitted'; New-PackageTestSource $root 'azd-omitted'
        $lock=Get-Content "$root/azd-components.lock.json" -Raw | ConvertFrom-Json
        $lock.components[0].files=@($lock.components[0].files | Where-Object target -ne 'SecurityReview/run.ps1')
        $lock | ConvertTo-Json -Depth 10 | Set-Content "$root/azd-components.lock.json"
        & git -C $root add .
        & git -C $root -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Omitted target fixture'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/omitted.zip" } | Should -Throw '*include SecurityReview/run.ps1*'
    }
}

Describe 'Reviewed package metadata' {
    It 'rejects an untracked component lock even when its bytes are unchanged' {
        $root=Join-Path $TestDrive 'untracked-lock'; New-PackageTestSource $root 'azd-untracked-lock'
        & git -C $root rm --cached --quiet azd-components.lock.json
        & git -C $root -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Remove tracked lock fixture'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/untracked-lock.zip" } | Should -Throw '*metadata must be tracked*'
    }
}

Describe 'Reviewed package runner' {
    It 'rejects an untracked runner rather than publishing a missing entrypoint' {
        $root=Join-Path $TestDrive 'untracked-runner'; New-PackageTestSource $root 'azd-untracked-runner'
        & git -C $root rm --cached --quiet scripts/Invoke-Solution.ps1
        & git -C $root -c user.name='Package Test' -c user.email='test@example.invalid' commit --quiet -m 'Remove tracked runner fixture'
        { & $builder -SolutionRoot $root -OutputPath "$TestDrive/untracked-runner.zip" } | Should -Throw '*runner must be tracked*'
    }
}
