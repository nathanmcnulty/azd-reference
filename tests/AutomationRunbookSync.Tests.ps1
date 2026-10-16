Describe 'Automation runbook lifecycle source-only synchronization' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:reference = Join-Path $TestDrive 'reference'
        New-Item -ItemType Directory -Path $script:reference | Out-Null
        foreach ($directory in @('components', 'schemas', 'tooling')) {
            Copy-Item -LiteralPath (Join-Path $script:repoRoot $directory) -Destination $script:reference -Recurse
        }
        Copy-Item -LiteralPath (Join-Path $script:repoRoot '.gitattributes') -Destination $script:reference
        & git -C $script:reference init --initial-branch main | Out-Null
        & git -C $script:reference config core.autocrlf false
        & git -C $script:reference config commit.gpgsign false
        & git -C $script:reference config user.name 'azd-reference tests'
        & git -C $script:reference config user.email 'azd-reference-tests@example.invalid'
        & git -C $script:reference remote add origin 'https://github.com/example/azd-reference.git'
        & git -C $script:reference add --all
        & git -C $script:reference commit -m 'Source-only candidate fixture' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the isolated source fixture.' }
        $script:revision = (& git -C $script:reference rev-parse HEAD).Trim()
        $script:sync = Join-Path $script:reference 'tooling/Sync-AzdComponent.ps1'
        $script:drift = Join-Path $script:reference 'tooling/Test-AzdComponentDrift.ps1'
    }

    BeforeEach {
        $consumer = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $consumer | Out-Null
        & $script:sync -Component automation-runbook-lifecycle -Revision $script:revision -TargetPath $consumer | Out-Null
    }

    It 'vendors exact bytes and immutable source provenance without a release tag' {
        $lock = Get-Content (Join-Path $consumer 'azd-components.lock.json') -Raw | ConvertFrom-Json
        $lock.components.Count | Should -Be 1
        $entry = $lock.components[0]
        $entry.id | Should -Be 'automation-runbook-lifecycle'
        $entry.version | Should -Be '0.1.0'
        $entry.sourceRevision | Should -BeExactly $script:revision
        $entry.files.Count | Should -Be 2
        foreach ($file in $entry.files) {
            $sourceHash = (Get-FileHash (Join-Path $script:reference $file.source)).Hash.ToLowerInvariant()
            $targetHash = (Get-FileHash (Join-Path $consumer $file.target)).Hash.ToLowerInvariant()
            $targetHash | Should -BeExactly $sourceHash
            $file.sha256 | Should -BeExactly $sourceHash
        }
        { & $script:drift -TargetPath $consumer } | Should -Not -Throw
    }

    It 'refuses substantive consumer drift and preserves the modified file' {
        $path = Join-Path $consumer 'scripts/vendor/Azd.AutomationRunbookLifecycle/Azd.AutomationRunbookLifecycle.psm1'
        Add-Content -LiteralPath $path -Value '# Consumer modification'
        $modifiedHash = (Get-FileHash $path).Hash
        { & $script:drift -TargetPath $consumer } | Should -Throw
        { & $script:sync -Component automation-runbook-lifecycle -Revision $script:revision -TargetPath $consumer } | Should -Throw
        (Get-FileHash $path).Hash | Should -BeExactly $modifiedHash
    }

    It 'keeps consumer-owned wrappers outside the managed file set' {
        $wrapper = Join-Path $consumer 'postprovision.ps1'
        Set-Content -LiteralPath $wrapper -Value '# Caller owns publishing, schedules and grants.'
        $original = (Get-FileHash $wrapper).Hash
        & $script:sync -Component automation-runbook-lifecycle -Revision $script:revision -TargetPath $consumer | Out-Null
        (Get-FileHash $wrapper).Hash | Should -BeExactly $original
    }
}
