Describe 'Catalog validation package and governance' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:actionRoot = Join-Path $script:repoRoot '.github/actions/catalog-validator'
        $script:registry = Get-Content -LiteralPath (Join-Path $script:repoRoot 'portfolio/github-governance-repositories.json') -Raw | ConvertFrom-Json
        $script:manifest = Get-Content -LiteralPath (Join-Path $script:actionRoot 'catalog-validator.manifest.json') -Raw | ConvertFrom-Json
    }

    It 'pins the desired workflow to an ancestor commit containing the complete package' {
        $revision = [string] $script:registry.catalogValidationPolicy.desiredWorkflowRevision
        $revision | Should -Match '^[0-9a-f]{40}$'
        & git -C $script:repoRoot merge-base --is-ancestor $revision HEAD
        $LASTEXITCODE | Should -Be 0
        foreach ($path in @(
                '.github/workflows/catalog-metadata.yml',
                '.github/actions/catalog-validator/action.yml',
                '.github/actions/catalog-validator/dist/index.js',
                '.github/actions/catalog-validator/catalog-validator.manifest.json',
                'schemas/catalog-metadata.schema.json'
            )) {
            & git -C $script:repoRoot cat-file -e "${revision}:$path"
            $LASTEXITCODE | Should -Be 0 -Because "$path must exist at the desired immutable revision"
        }
    }

    It 'keeps the bundled schema and manifest hashes synchronized' {
        $canonical = Join-Path $script:repoRoot 'schemas/catalog-metadata.schema.json'
        $bundled = Join-Path $script:actionRoot ([string] $script:manifest.schemaPath)
        (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToLowerInvariant() |
            Should -Be ([string] $script:manifest.schemaSha256)
        (Get-FileHash -LiteralPath $bundled -Algorithm SHA256).Hash.ToLowerInvariant() |
            Should -Be ([string] $script:manifest.schemaSha256)
        (Get-FileHash -LiteralPath (Join-Path $script:actionRoot ([string] $script:manifest.validatorPath)) -Algorithm SHA256).Hash.ToLowerInvariant() |
            Should -Be ([string] $script:manifest.validatorSha256)
    }

    It 'does not check out or execute repository-defined code' {
        $workflow = Get-Content -LiteralPath (Join-Path $script:repoRoot '.github/workflows/catalog-metadata.yml') -Raw
        $source = Get-Content -LiteralPath (Join-Path $script:actionRoot 'src/index.js') -Raw
        $workflow | Should -Not -Match '(?i)actions/checkout'
        $source | Should -Not -Match "node:child_process|execFile|spawn\("
        $workflow | Should -Match 'permissions:\s*\r?\n\s*contents: read'
    }

    It 'records explicit enrollment state for every governed repository' {
        @($script:registry.repositories).Count | Should -BeGreaterThan 0
        foreach ($repository in @($script:registry.repositories)) {
            [string] $repository.catalogValidation.state |
                Should -BeIn @('pending', 'pilot', 'required', 'exempt')
            if ([string] $repository.catalogValidation.state -eq 'exempt') {
                [string] $repository.catalogValidation.exemptionReason | Should -Not -BeNullOrEmpty
            }
        }
        $pilots = @($script:registry.repositories | Where-Object {
                [string] $_.catalogValidation.state -eq 'pilot'
            } | ForEach-Object { [string] $_.id })
        $pilots | Should -Be @('azd-emergency-access', 'azd-risk-based-ca')
    }

    It 'does not declare the catalog check required before pilot observation' {
        $context = [string] $script:registry.catalogValidationPolicy.requiredStatusCheck.context
        foreach ($repository in @($script:registry.repositories | Where-Object {
                    [string] $_.catalogValidation.state -ne 'required'
                })) {
            @($repository.requiredStatusChecks) | Should -Not -Contain $context
        }
    }
}
