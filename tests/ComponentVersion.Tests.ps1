Describe 'Canonical component version immutability' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:guardSource = Join-Path $script:repoRoot 'tooling/Test-AzdComponentVersion.ps1'
    }

    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $reference = Join-Path $caseRoot 'reference'
        $componentRoot = Join-Path $reference 'components/example'
        $toolingRoot = Join-Path $reference 'tooling'
        New-Item -ItemType Directory -Path $componentRoot, $toolingRoot -Force | Out-Null
        Copy-Item -LiteralPath $script:guardSource -Destination $toolingRoot

        Set-Content -LiteralPath (Join-Path $componentRoot 'module.psm1') -Encoding utf8NoBOM -Value 'function Get-Example { ''example'' }'
        [ordered]@{
            manifestVersion = '1.0'
            id = 'example'
            version = '1.0.0'
            description = 'Example component.'
            files = @(
                [ordered]@{
                    source = 'components/example/module.psm1'
                    target = 'scripts/vendor/example/module.psm1'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $componentRoot 'component.json') -Encoding utf8NoBOM

        & git -C $reference init --initial-branch main | Out-Null
        & git -C $reference config core.autocrlf false
        & git -C $reference config user.name 'azd-reference tests'
        & git -C $reference config user.email 'azd-reference-tests@example.invalid'
        & git -C $reference add --all
        & git -C $reference commit -m 'Base component' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create the Git component fixture.' }

        $baseRevision = (& git -C $reference rev-parse HEAD).Trim()
        $guard = Join-Path $toolingRoot 'Test-AzdComponentVersion.ps1'
        $manifestPath = Join-Path $componentRoot 'component.json'
        $sourcePath = Join-Path $componentRoot 'module.psm1'
    }

    It 'passes an unchanged component' {
        { & $guard -BaseRevision $baseRevision } | Should -Not -Throw
        $result = @(& $guard -BaseRevision $baseRevision -PassThru)
        $result.Count | Should -Be 1
        $result[0].state | Should -Be 'unchanged'
    }

    It 'fails when a managed source changes without a version change' {
        Add-Content -LiteralPath $sourcePath -Encoding utf8NoBOM -Value "`n# same-version change"
        { & $guard -BaseRevision $baseRevision } | Should -Throw '*without a component version change*example@1.0.0*'
    }

    It 'fails when the canonical manifest changes without a version change' {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.description = 'Changed description.'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        { & $guard -BaseRevision $baseRevision } | Should -Throw '*without a component version change*'
    }

    It 'fails when a declared changelog changes without a version change' {
        $changelogPath = Join-Path $componentRoot 'CHANGELOG.md'
        Set-Content -LiteralPath $changelogPath -Encoding utf8NoBOM -Value '# 1.0.0'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest | Add-Member -NotePropertyName status -NotePropertyValue 'stable'
        $manifest | Add-Member -NotePropertyName changelog -NotePropertyValue 'components/example/CHANGELOG.md'
        $manifest.manifestVersion = '1.1'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        & git -C $reference add --all
        & git -C $reference commit -m 'Add changelog baseline' | Out-Null
        $changelogBase = (& git -C $reference rev-parse HEAD).Trim()

        Add-Content -LiteralPath $changelogPath -Encoding utf8NoBOM -Value "`nChanged notes"
        { & $guard -BaseRevision $changelogBase } | Should -Throw '*without a component version change*'
    }

    It 'checks the union of base and current managed sources' {
        Set-Content -LiteralPath (Join-Path $componentRoot 'additional.ps1') -Encoding utf8NoBOM -Value 'Write-Output additional'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files += [pscustomobject]@{
            source = 'components/example/additional.ps1'
            target = 'scripts/vendor/example/additional.ps1'
        }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        { & $guard -BaseRevision $baseRevision } | Should -Throw '*without a component version change*'
    }

    It 'passes changed canonical content with a version change' {
        Add-Content -LiteralPath $sourcePath -Encoding utf8NoBOM -Value "`n# compatible versioned change"
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.version = '1.1.0'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
        { & $guard -BaseRevision $baseRevision } | Should -Not -Throw
        (@(& $guard -BaseRevision $baseRevision -PassThru))[0].state | Should -Be 'version-changed'
    }

    It 'passes a new component that is absent from the base revision' {
        $newRoot = Join-Path $reference 'components/new-component'
        New-Item -ItemType Directory -Path $newRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $newRoot 'new.ps1') -Encoding utf8NoBOM -Value 'Write-Output new'
        [ordered]@{
            manifestVersion = '1.0'
            id = 'new-component'
            version = '0.1.0'
            description = 'New component.'
            files = @(
                [ordered]@{
                    source = 'components/new-component/new.ps1'
                    target = 'scripts/vendor/new-component/new.ps1'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $newRoot 'component.json') -Encoding utf8NoBOM

        { & $guard -BaseRevision $baseRevision } | Should -Not -Throw
        $results = @(& $guard -BaseRevision $baseRevision -PassThru)
        ($results | Where-Object component -eq 'new-component').state | Should -Be 'new'
    }

    It 'fails when a formerly managed source is deleted without a version change' {
        Remove-Item -LiteralPath $sourcePath
        { & $guard -BaseRevision $baseRevision } | Should -Throw '*without a component version change*'
    }

    It 'rejects missing and option-like base revisions safely' {
        { & $guard -BaseRevision 'revision-that-does-not-exist' } | Should -Throw '*does not resolve to a commit*'
        { & $guard -BaseRevision '--help' } | Should -Throw '*not a safe Git revision*'
        { & $guard -BaseRevision 'HEAD;Write-Output-owned' } | Should -Throw '*not a safe Git revision*'
    }
}
