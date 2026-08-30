Describe 'Component synchronization' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $reference = Join-Path $caseRoot 'reference'
        $consumer = Join-Path $caseRoot 'consumer'
        New-Item -ItemType Directory -Path $reference, $consumer | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'components') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'schemas') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot 'tooling') -Destination $reference -Recurse
        Copy-Item -LiteralPath (Join-Path $script:repoRoot '.gitattributes') -Destination $reference
        & git -C $reference init --initial-branch main | Out-Null
        & git -C $reference config core.autocrlf false
        & git -C $reference config user.name 'azd-reference tests'
        & git -C $reference config user.email 'azd-reference-tests@example.invalid'
        & git -C $reference remote add origin 'https://github.com/example/azd-reference.git'
        & git -C $reference add --all
        & git -C $reference commit -m 'Test fixture' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create the Git reference fixture.' }
        $initialRevision = (& git -C $reference rev-parse HEAD).Trim()
        & git -C $reference tag 'component/deployment-validation/v0.3.3' $initialRevision
        if ($LASTEXITCODE -ne 0) { throw 'Unable to tag the Git reference fixture.' }

        $sync = Join-Path $reference 'tooling/Sync-AzdComponent.ps1'
        $drift = Join-Path $reference 'tooling/Test-AzdComponentDrift.ps1'
    }

    It 'copies exact bytes and writes a pinned lock' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $lock = Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json
        $lock.components.Count | Should -Be 1
        $lock.components[0].sourceRevision | Should -Match '^[0-9a-f]{40}$'
        foreach ($file in $lock.components[0].files) {
            $target = Join-Path $consumer $file.target
            Test-Path -LiteralPath $target | Should -BeTrue
            (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $file.sha256
        }
        { & $drift -TargetPath $consumer } | Should -Not -Throw
    }

    It 'synchronizes notification contracts as a first-class component' {
        & $sync -Component notification-contracts -TargetPath $consumer | Out-Null
        $lock = Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json
        $lock.components[0].id | Should -Be 'notification-contracts'
        $lock.components[0].version | Should -Be '1.0.0'
        $lock.components[0].files.Count | Should -Be 2
        { & $drift -TargetPath $consumer } | Should -Not -Throw
    }

    It 'is deterministic for the same component revision' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $firstHash = (Get-FileHash -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Algorithm SHA256).Hash
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $secondHash = (Get-FileHash -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Algorithm SHA256).Hash
        $secondHash | Should -Be $firstHash
    }

    It 'installs an exact tagged component version after HEAD advances' {
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.version = '0.4.0'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Advance component fixture' | Out-Null

        & $sync -Component deployment-validation -Version 0.3.3 -TargetPath $consumer | Out-Null
        $lock = Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json
        $lock.components[0].version | Should -Be '0.3.3'
        $lock.components[0].sourceRevision | Should -Be $initialRevision
    }

    It 'installs an exact full source revision' {
        & $sync -Component deployment-validation -Revision $initialRevision -TargetPath $consumer | Out-Null
        $lock = Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json
        $lock.components[0].sourceRevision | Should -Be $initialRevision
    }

    It 'rejects missing and mismatched component version tags before writing' {
        { & $sync -Component deployment-validation -Version 9.9.8 -TargetPath $consumer } | Should -Throw '*does not resolve*'
        & git -C $reference tag 'component/deployment-validation/v9.9.9' $initialRevision
        { & $sync -Component deployment-validation -Version 9.9.9 -TargetPath $consumer } | Should -Throw '*not requested version*'
        Test-Path -LiteralPath (Join-Path $consumer 'azd-components.lock.json') | Should -BeFalse
    }

    It 'rejects changed managed content under the same component version' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $sourceModule = Join-Path $reference 'components/powershell/deployment-validation/Azd.DeploymentValidation.psm1'
        Add-Content -LiteralPath $sourceModule -Value '# incompatible same-version change'
        & git -C $reference add --all
        & git -C $reference commit -m 'Invalid same-version fixture' | Out-Null
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*Publish a new component version*'
    }

    It 'preserves a consumer portfolio baseline' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $lockPath = Join-Path $consumer 'azd-components.lock.json'
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $lock | Add-Member -NotePropertyName baseline -NotePropertyValue '2026.08'
        $lock | Select-Object manifestVersion, baseline, components | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        (Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json).baseline | Should -Be '2026.08'
    }

    It 'sets an exact requested portfolio baseline transactionally' {
        $plan = & $sync -Component deployment-validation -TargetPath $consumer -Baseline '2026.08.2' -WhatIf
        $plan.baseline | Should -Be '2026.08.2'
        Test-Path -LiteralPath (Join-Path $consumer 'azd-components.lock.json') | Should -BeFalse

        $result = & $sync -Component deployment-validation -TargetPath $consumer -Baseline '2026.08.2'
        $result.baseline | Should -Be '2026.08.2'
        (Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json).baseline | Should -Be '2026.08.2'
    }

    It 'refuses to overwrite managed drift by default' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $managed = Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psm1'
        Add-Content -LiteralPath $managed -Value '# local change'
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*drift detected*'
    }

    It 'requires explicit acceptance before replacing drift' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $managed = Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psm1'
        Add-Content -LiteralPath $managed -Value '# local change'
        { & $sync -Component deployment-validation -TargetPath $consumer -AcceptDrift } | Should -Not -Throw
        { & $drift -TargetPath $consumer } | Should -Not -Throw
    }

    It 'accepts CRLF representation only under an explicit text eol=lf policy' {
        & git -C $consumer init --initial-branch main | Out-Null
        & git -C $consumer config core.autocrlf false
        Set-Content -LiteralPath (Join-Path $consumer '.gitattributes') -Encoding utf8NoBOM -Value 'scripts/vendor/** text eol=lf'
        & git -C $consumer add .gitattributes
        & git -C $consumer -c user.name=test -c user.email=test@example.invalid commit -m 'Consumer attributes' | Out-Null
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null

        $managed = Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'
        $text = [System.IO.File]::ReadAllText($managed).Replace("`r`n", "`n").Replace("`n", "`r`n")
        [System.IO.File]::WriteAllText($managed, $text, [System.Text.UTF8Encoding]::new($false))

        { & $drift -TargetPath $consumer } | Should -Not -Throw
        (@(& $drift -TargetPath $consumer -PassThru) | Where-Object target -like '*.psd1').match | Should -Be 'lf-normalized'
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Not -Throw
    }

    It 'rejects CRLF representation without an explicit LF policy' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $managed = Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'
        $text = [System.IO.File]::ReadAllText($managed).Replace("`r`n", "`n").Replace("`n", "`r`n")
        [System.IO.File]::WriteAllText($managed, $text, [System.Text.UTF8Encoding]::new($false))
        { & $drift -TargetPath $consumer } | Should -Throw '*missing, modified, or unsafe*'
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*drift detected*'
    }

    It 'rejects a substantive change even when LF normalization is allowed' {
        & git -C $consumer init --initial-branch main | Out-Null
        Set-Content -LiteralPath (Join-Path $consumer '.gitattributes') -Encoding utf8NoBOM -Value 'scripts/vendor/** text eol=lf'
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $managed = Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'
        $text = [System.IO.File]::ReadAllText($managed).Replace("`r`n", "`n").Replace("`n", "`r`n") + '# changed'
        [System.IO.File]::WriteAllText($managed, $text, [System.Text.UTF8Encoding]::new($false))
        { & $drift -TargetPath $consumer } | Should -Throw '*missing, modified, or unsafe*'
    }

    It 'refuses parent traversal in a committed component mapping' {
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files[0].target = '../outside.psm1'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Unsafe mapping fixture' | Out-Null
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw
        Test-Path -LiteralPath (Join-Path $TestDrive 'outside.psm1') | Should -BeFalse
    }

    It 'refuses an ignored untracked source that a manifest claims is committed' {
        $componentRoot = Join-Path $reference 'components/powershell/deployment-validation'
        $ignoredSource = Join-Path $componentRoot 'ignored-secret.txt'
        Set-Content -LiteralPath $ignoredSource -Value 'must-not-be-vendored' -NoNewline
        Set-Content -LiteralPath (Join-Path $reference '.gitignore') -Value 'ignored-secret.txt'
        $manifestPath = Join-Path $componentRoot 'component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files += [pscustomobject]@{
            source = 'components/powershell/deployment-validation/ignored-secret.txt'
            target = 'scripts/vendor/Azd.DeploymentValidation/ignored-secret.txt'
        }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add .gitignore $manifestPath
        & git -C $reference commit -m 'Ignored source fixture' | Out-Null
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*must be tracked by Git*'
        Test-Path -LiteralPath (Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/ignored-secret.txt') | Should -BeFalse
    }

    It 'refuses reserved consumer targets' {
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files[0].target = '.git/config'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Reserved target fixture' | Out-Null
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*reserved path*'
    }

    It 'refuses a directory where a managed file is expected even when drift is accepted' {
        $directoryTarget = Join-Path $consumer 'scripts/vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'
        New-Item -ItemType Directory -Path $directoryTarget -Force | Out-Null
        { & $sync -Component deployment-validation -TargetPath $consumer -AcceptDrift } | Should -Throw '*must be a file*'
    }

    It 'refuses credential-bearing origin URLs' {
        & git -C $reference remote set-url origin 'https://x-access-token:do-not-write@github.com/example/azd-reference.git'
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*without credentials*'
        Test-Path -LiteralPath (Join-Path $consumer 'azd-components.lock.json') | Should -BeFalse
    }

    It 'refuses targets claimed by another locked component' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $lockPath = Join-Path $consumer 'azd-components.lock.json'
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
        $other = $lock.components[0] | Select-Object *
        $other.id = 'other-component'
        $lock.components = @($lock.components[0], $other)
        $lock | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM
        { & $sync -Component deployment-validation -TargetPath $consumer -AcceptDrift } | Should -Throw '*more than one component*'
        { & $drift -TargetPath $consumer } | Should -Throw '*more than one component*'
    }

    It 'refuses implicit deletion when a new manifest drops a managed file' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.version = '0.4.0'
        $manifest.files = @($manifest.files | Select-Object -First 1)
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Removal fixture' | Out-Null
        { & $sync -Component deployment-validation -TargetPath $consumer } | Should -Throw '*no longer manages*'
    }

    It 'prunes only clean formerly managed files when explicitly requested' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $removedTarget = [string] $manifest.files[-1].target
        $manifest.version = '0.4.0'
        $manifest.files = @($manifest.files | Select-Object -First ($manifest.files.Count - 1))
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Versioned removal fixture' | Out-Null

        & $sync -Component deployment-validation -TargetPath $consumer -PruneRemovedFiles | Out-Null
        Test-Path -LiteralPath (Join-Path $consumer $removedTarget) | Should -BeFalse
        $lock = Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json
        @($lock.components[0].files | Where-Object target -eq $removedTarget).Count | Should -Be 0
    }

    It 'requires a new version before pruning a managed file' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $removedTarget = [string] $manifest.files[-1].target
        $manifest.files = @($manifest.files | Select-Object -First ($manifest.files.Count - 1))
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Unversioned removal fixture' | Out-Null

        { & $sync -Component deployment-validation -TargetPath $consumer -PruneRemovedFiles } | Should -Throw '*Publish a new component version*'
        Test-Path -LiteralPath (Join-Path $consumer $removedTarget) | Should -BeTrue
    }

    It 'refuses to prune a modified obsolete file even when replacement drift is accepted' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $removedTarget = [string] $manifest.files[-1].target
        Add-Content -LiteralPath (Join-Path $consumer $removedTarget) -Value '# keep me'
        $manifest.version = '0.4.0'
        $manifest.files = @($manifest.files | Select-Object -First ($manifest.files.Count - 1))
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Modified removal fixture' | Out-Null

        { & $sync -Component deployment-validation -TargetPath $consumer -PruneRemovedFiles -AcceptDrift } | Should -Throw '*modified*'
        Test-Path -LiteralPath (Join-Path $consumer $removedTarget) | Should -BeTrue
    }

    It 'blocks downgrades unless explicitly allowed' {
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null
        $manifestPath = Join-Path $reference 'components/powershell/deployment-validation/component.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.version = '0.4.0'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Upgrade fixture' | Out-Null
        & $sync -Component deployment-validation -TargetPath $consumer | Out-Null

        { & $sync -Component deployment-validation -Revision $initialRevision -TargetPath $consumer } | Should -Throw '*requires -AllowDowngrade*'
        { & $sync -Component deployment-validation -Revision $initialRevision -TargetPath $consumer -AllowDowngrade } | Should -Not -Throw
        (Get-Content -LiteralPath (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json).components[0].version | Should -Be '0.3.3'
    }

    It 'plans without changing the consumer' {
        & $sync -Component deployment-validation -TargetPath $consumer -WhatIf | Out-Null
        Test-Path -LiteralPath (Join-Path $consumer 'azd-components.lock.json') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $consumer -Force).Count | Should -Be 0
    }
}
