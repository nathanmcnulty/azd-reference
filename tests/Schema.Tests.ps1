Describe 'Portfolio JSON schemas' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
    }
    $cases = @(
        @{ Name = 'component manifest'; Schema = 'component-manifest.schema.json'; Fixture = 'component-manifest.json' },
        @{ Name = 'component lock'; Schema = 'azd-components-lock.schema.json'; Fixture = 'azd-components.lock.json' },
        @{ Name = 'deployment validation'; Schema = 'deployment-validation.schema.json'; Fixture = 'deployment-validation.json' },
        @{ Name = 'deployment receipt'; Schema = 'deployment-receipt.schema.json'; Fixture = 'deployment-receipt.json' }
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
        }
    }
}
