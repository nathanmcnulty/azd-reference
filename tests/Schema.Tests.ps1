Describe 'Portfolio JSON schemas' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }
    $cases = @(
        @{ Name = 'component manifest'; Schema = 'component-manifest.schema.json'; Fixture = 'component-manifest.json' },
        @{ Name = 'component lock'; Schema = 'azd-components-lock.schema.json'; Fixture = 'azd-components.lock.json' },
        @{ Name = 'portfolio consumers'; Schema = 'portfolio-consumers.schema.json'; Fixture = 'portfolio-consumers.json' },
        @{ Name = 'repository baseline'; Schema = 'repository-baseline.schema.json'; Fixture = 'repository-baseline.json' },
        @{ Name = 'deployment validation'; Schema = 'deployment-validation.schema.json'; Fixture = 'deployment-validation.json' },
        @{ Name = 'deployment receipt'; Schema = 'deployment-receipt.schema.json'; Fixture = 'deployment-receipt.json' },
        @{ Name = 'notification envelope'; Schema = 'notification-envelope.schema.json'; Fixture = 'notification-envelope.json' },
        @{ Name = 'notification delivery result'; Schema = 'notification-delivery-result.schema.json'; Fixture = 'notification-delivery-result.json' }
    )

    It 'accepts the valid <Name> fixture' -ForEach $cases {
        $schemaPath = Join-Path $script:repoRoot "schemas/$Schema"
        $fixturePath = Join-Path $PSScriptRoot "fixtures/valid/$Fixture"
        (Get-Content -LiteralPath $fixturePath -Raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) | Should -BeTrue
    }

    It 'rejects the invalid <Name> fixture' -ForEach $cases {
        $schemaPath = Join-Path $script:repoRoot "schemas/$Schema"
        $fixturePath = Join-Path $PSScriptRoot "fixtures/invalid/$Fixture"
        { Get-Content -LiteralPath $fixturePath -Raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop } | Should -Throw
    }

    It 'accepts every canonical component manifest' {
        $schemaPath = Join-Path $script:repoRoot 'schemas/component-manifest.schema.json'
        $manifests = @(Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'components') -Filter component.json -File -Recurse)
        $manifests.Count | Should -BeGreaterThan 0
        foreach ($manifest in $manifests) {
            (Get-Content -LiteralPath $manifest.FullName -Raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) | Should -BeTrue
            $data = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
            if ($data.manifestVersion -eq '1.1') {
                Test-Path -LiteralPath (Join-Path $script:repoRoot $data.changelog) -PathType Leaf | Should -BeTrue
            }
            $moduleManifests = @($data.files | Where-Object { [string] $_.source -like '*.psd1' })
            foreach ($moduleManifest in $moduleManifests) {
                $moduleData = Import-PowerShellDataFile -LiteralPath (Join-Path $script:repoRoot $moduleManifest.source)
                ([string] $moduleData.ModuleVersion) | Should -Be ([string] $data.version)
            }
        }
    }

    It 'accepts the canonical portfolio registry and repository baseline' {
        $portfolioRoot = Join-Path $script:repoRoot 'portfolio'
        (Get-Content -LiteralPath (Join-Path $portfolioRoot 'consumers.json') -Raw |
            Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop) | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $portfolioRoot 'repository-baseline.json') -Raw |
            Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/repository-baseline.schema.json') -ErrorAction Stop) | Should -BeTrue
    }

    It 'rejects parent traversal in every repository-relative path contract' {
        $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/valid/component-manifest.json') -Raw | ConvertFrom-Json
        $manifest.files[0].source = '../outside.psm1'
        { $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/component-manifest.schema.json') -ErrorAction Stop } | Should -Throw

        $lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/valid/azd-components.lock.json') -Raw | ConvertFrom-Json
        $lock.components[0].files[0].target = 'scripts/../../outside.psm1'
        { $lock | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/azd-components-lock.schema.json') -ErrorAction Stop } | Should -Throw

        $receipt = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/valid/deployment-receipt.json') -Raw | ConvertFrom-Json
        $receipt.artifacts = @('../../outside.json')
        { $receipt | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/deployment-receipt.schema.json') -ErrorAction Stop } | Should -Throw

        $portfolio = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/valid/portfolio-consumers.json') -Raw | ConvertFrom-Json
        $portfolio.consumers[0].checkoutDirectory = '../outside'
        { $portfolio | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop } | Should -Throw

        $portfolio = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/valid/portfolio-consumers.json') -Raw | ConvertFrom-Json
        $portfolio.consumers[0].repositoryValidationWorkflow = '../outside.yml'
        { $portfolio | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop } | Should -Throw

        $portfolio = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/valid/portfolio-consumers.json') -Raw | ConvertFrom-Json
        $portfolio.consumers[0].PSObject.Properties.Remove('repositoryValidationWorkflow')
        { $portfolio | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/portfolio-consumers.schema.json') -ErrorAction Stop } | Should -Throw
    }
}
