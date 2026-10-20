Describe 'Fail-closed schema validation gates' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:permissionTool = Join-Path $script:repoRoot 'tooling/Get-AzdPermissionComparison.ps1'

        function Get-WorkflowSchemaGate {
            param([string] $Workflow, [string] $Step)
            $source = Get-Content -LiteralPath (Join-Path $script:repoRoot ".github/workflows/$Workflow") -Raw
            $pattern = '(?s)- name: ' + [regex]::Escape($Step) + '.*?run: \|\r?\n(?<code>.*?)(?=\r?\n      - name:|\z)'
            $code = [regex]::Match($source, $pattern).Groups['code'].Value -replace '(?m)^          ', ''
            if (-not $code) { throw "Missing workflow step: $Workflow / $Step" }
            $ast = [scriptblock]::Create($code).Ast
            $gates = @($ast.EndBlock.Statements | Where-Object { $_.Extent.Text -match '\bTest-Json\b' })
            if ($gates.Count -ne 1) { throw "Expected one schema gate: $Workflow / $Step" }
            [scriptblock]::Create($gates[0].Extent.Text)
        }
    }

    It 'rejects a false-only permission registry validation result before using its contents' {
        $registryPath = Join-Path $TestDrive 'registry.json'
        '{"schemaVersion":"1.0","scope":"test","legacyCopies":[],"solutions":[]}' | Set-Content -LiteralPath $registryPath
        Mock Test-Json { $false }

        { & $script:permissionTool -PortfolioRoot $TestDrive -RegistryPath $registryPath } |
            Should -Throw '*Permission solution registry failed schema validation*'
        Should -Invoke Test-Json -Times 1 -Exactly
    }

    It 'rejects a false-only permission manifest validation result before using its requirements' {
        $registryPath = Join-Path $TestDrive 'registry.json'
        '{"schemaVersion":"1.0","scope":"test","legacyCopies":[],"solutions":[{"id":"base","manifest":"azd-permissions.json"}]}' |
            Set-Content -LiteralPath $registryPath
        '{"schemaVersion":"1.0","solutionId":"base","coverage":"complete","gaps":[],"requirements":[],"status":"implemented","reviewedOn":"2026-10-02"}' |
            Set-Content -LiteralPath (Join-Path $TestDrive 'azd-permissions.json')
        Mock Test-Json { $true }
        Mock Test-Json { $false } -ParameterFilter { $SchemaFile -like '*permission-requirements.schema.json' }

        { & $script:permissionTool -PortfolioRoot $TestDrive -RegistryPath $registryPath } |
            Should -Throw '*Permission manifest failed schema validation*'
        Should -Invoke Test-Json -Times 1 -Exactly -ParameterFilter { $SchemaFile -like '*permission-requirements.schema.json' }
    }

    It 'rejects a false-only schema result in <Workflow>' -ForEach @(
        @{ Workflow = 'portfolio-updates.yml'; Step = 'Check out registered public consumers' },
        @{ Workflow = 'portfolio-drift.yml'; Step = 'Check out registered public consumers' },
        @{ Workflow = 'validate.yml'; Step = 'Validate the skeleton as a locked consumer' }
    ) {
        $gate = Get-WorkflowSchemaGate -Workflow $Workflow -Step $Step
        $registryRaw = '{}'
        $schemaPath = Join-Path $script:repoRoot 'schemas/portfolio-consumers.schema.json'
        Mock Test-Json { $false }

        Push-Location $script:repoRoot
        try { { & $gate } | Should -Throw '*failed schema validation*' }
        finally { Pop-Location }
        Should -Invoke Test-Json -Times 1 -Exactly
    }
}
