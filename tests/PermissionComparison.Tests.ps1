Describe 'Permission requirement comparison' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:tool = Join-Path $script:repoRoot 'tooling/Get-AzdPermissionComparison.ps1'
        $script:schema = Join-Path $script:repoRoot 'schemas/permission-requirements.schema.json'
        function New-PermissionTestManifest {
            param([string] $Id, [object[]] $Requirement, [string] $Coverage = 'complete')
            $directory = Join-Path $TestDrive $Id
            $null = New-Item -ItemType Directory -Path $directory -Force
            Set-Content -LiteralPath (Join-Path $directory 'source.txt') -Value 'permission evidence'
            $hash = (Get-FileHash -LiteralPath (Join-Path $directory 'source.txt')).Hash.ToLowerInvariant()
            $entries = @(
                foreach ($item in $Requirement) {
                    [ordered]@{
                        resource = $item.Resource; kind = $item.Kind; permission = $item.Permission
                        principal = 'worker'; phase = $item.Phase; feature = $item.Feature
                        defaultEnabled = $item.Enabled; scope = $item.Scope; rationale = 'test capability'
                        evidenceState = 'code'; evidence = @(@{ path = 'source.txt'; sha256 = $hash })
                    }
                }
            )
            $gaps = @()
            if ($Coverage -eq 'partial') { $gaps = @('pending review') }
            $manifest = @{
                schemaVersion = '1.0'; solutionId = $Id; status = 'implemented'; coverage = $Coverage
                reviewedOn = '2026-10-02'; requirements = $entries
                gaps = $gaps
            }
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $directory 'azd-permissions.json')
        }
        function New-PermissionTestRegistry {
            param([string[]] $Id)
            $path = Join-Path $TestDrive 'registry.json'
            @{
                schemaVersion = '1.0'; scope = 'test'; legacyCopies = @()
                solutions = @($Id | ForEach-Object { @{ id = $_; manifest = "$_/azd-permissions.json" } })
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
            $path
        }
        function New-TestRequirement {
            param([string] $Permission = 'AuditLog.Read.All', [string] $Kind = 'application',
                [string] $Resource = 'https://graph.microsoft.com', [string] $Scope = 'tenant',
                [string] $Phase = 'runtime', [string] $Feature = 'core', [bool] $Enabled = $true)
            @{ Permission = $Permission; Kind = $Kind; Resource = $Resource; Scope = $Scope; Phase = $Phase; Feature = $Feature; Enabled = $Enabled }
        }
    }

    It 'reports shared and added permissions while excluding bootstrap and optional grants' {
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement))
        New-PermissionTestManifest -Id 'extra' -Requirement @(
            (New-TestRequirement), (New-TestRequirement -Permission 'User.Read.All'),
            (New-TestRequirement -Permission 'Application.ReadWrite.All' -Phase deployment),
            (New-TestRequirement -Permission 'Mail.Send' -Feature email -Enabled $false)
        )
        $registry = New-PermissionTestRegistry -Id base, extra
        $result = & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -BaseSolution base -AdditionalSolution extra
        $result.comparisonComplete | Should -BeTrue
        @($result.permissions | Where-Object relationship -eq shared).permission | Should -Be 'AuditLog.Read.All'
        @($result.permissions | Where-Object relationship -eq added).permission | Should -Be 'User.Read.All'
        $result.permissions.Count | Should -Be 2
        $result.features.Count | Should -Be 0
        $result.excludeFeatures.Count | Should -Be 0
        $result.includeOptional | Should -BeFalse
        $enabled = & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -BaseSolution base -AdditionalSolution extra -Feature extra:email
        @($enabled.permissions.permission) | Should -Contain 'Mail.Send'
        $enabled.features | Should -Be @('extra:email')
        $receipt = & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -BaseSolution base -AdditionalSolution extra -Feature extra:email -ExcludeFeature base:core -IncludeOptional -AsJson | ConvertFrom-Json
        $receipt.features | Should -Be @('extra:email')
        $receipt.excludeFeatures | Should -Be @('base:core')
        $receipt.includeOptional | Should -BeTrue
    }

    It 'keeps delegated, resource, scope, and read-write differences separate' {
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement))
        New-PermissionTestManifest -Id 'extra' -Requirement @(
            (New-TestRequirement -Kind delegated), (New-TestRequirement -Resource 'other-api'),
            (New-TestRequirement -Scope 'specific-group'), (New-TestRequirement -Permission 'AuditLog.ReadWrite.All')
        )
        $result = & $script:tool -PortfolioRoot $TestDrive -RegistryPath (New-PermissionTestRegistry base, extra) -BaseSolution base -AdditionalSolution extra
        @($result.permissions | Where-Object relationship -eq shared).Count | Should -Be 0
        @($result.permissions | Where-Object relationship -eq added).Count | Should -Be 4
    }

    It 'reports partial, missing, and changed evidence without claiming a complete comparison' {
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement)) -Coverage partial
        New-PermissionTestManifest -Id 'extra' -Requirement @((New-TestRequirement))
        Set-Content -LiteralPath (Join-Path $TestDrive 'extra/source.txt') -Value 'changed'
        $result = & $script:tool -PortfolioRoot $TestDrive -RegistryPath (New-PermissionTestRegistry base, extra, missing)
        $result.comparisonComplete | Should -BeFalse
        @($result.inventory | Where-Object solution -eq extra).findings | Should -Contain 'Changed evidence: source.txt'
        @($result.inventory | Where-Object solution -eq missing).state | Should -Be 'missing'
    }

    It 'rejects unknown selections and duplicate requirements' {
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement))
        $registry = New-PermissionTestRegistry base
        { & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -BaseSolution unknown } | Should -Throw '*Unknown solution*'
        { & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -Feature base:unknown } | Should -Throw '*Unknown feature*'
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement), (New-TestRequirement))
        { & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry } | Should -Throw '*Duplicate requirement*'
    }

    It 'rejects path traversal and unmodeled permission kinds through the schema' {
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement))
        $manifest = Get-Content (Join-Path $TestDrive 'base/azd-permissions.json') -Raw | ConvertFrom-Json
        $manifest.requirements[0].evidence[0].path = '../outside.txt'
        { $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile $script:schema -ErrorAction Stop } | Should -Throw
        $manifest.requirements[0].evidence[0].path = 'source.txt:stream'
        { $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile $script:schema -ErrorAction Stop } | Should -Throw
        $registryPath = New-PermissionTestRegistry base
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
        $registry.solutions[0].manifest = 'base/azd-permissions.json:stream'
        $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath
        { & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registryPath } | Should -Throw
        $manifest.requirements[0].evidence[0].path = 'source.txt'
        $manifest.requirements[0].kind = 'scope-or-role'
        { $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile $script:schema -ErrorAction Stop } | Should -Throw
        $manifest.requirements[0].kind = 'application'
        $manifest.requirements[0].evidence[0] | Add-Member -NotePropertyName documentationUrl -NotePropertyValue 'https://example.invalid/permission-reference'
        $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile $script:schema -ErrorAction Stop | Should -BeTrue
    }

    It 'accepts the tracked location registry' {
        Get-Content (Join-Path $script:repoRoot 'portfolio/permission-solutions.json') -Raw |
            Test-Json -SchemaFile (Join-Path $script:repoRoot 'schemas/permission-solutions.schema.json') -ErrorAction Stop | Should -BeTrue
    }

    It 'requires explicit gaps for partial coverage and disallows gaps for complete coverage' {
        New-PermissionTestManifest -Id 'base' -Requirement @((New-TestRequirement))
        $manifest = Get-Content (Join-Path $TestDrive 'base/azd-permissions.json') -Raw | ConvertFrom-Json
        $manifest.gaps = @('unresolved capability')
        { $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile $script:schema -ErrorAction Stop } | Should -Throw
        $manifest.coverage = 'partial'
        $manifest.gaps = @()
        { $manifest | ConvertTo-Json -Depth 10 | Test-Json -SchemaFile $script:schema -ErrorAction Stop } | Should -Throw
    }

    It 'honors excluded features and an explicit deployment phase without including runtime roles' {
        New-PermissionTestManifest -Id 'base' -Requirement @(
            (New-TestRequirement), (New-TestRequirement -Permission 'Mail.Send' -Feature email),
            (New-TestRequirement -Permission 'Application.ReadWrite.All' -Kind delegated -Phase deployment)
        )
        $registry = New-PermissionTestRegistry base
        $runtime = & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -ExcludeFeature base:email
        $runtime.permissions.permission | Should -Be 'AuditLog.Read.All'
        $deployment = & $script:tool -PortfolioRoot $TestDrive -RegistryPath $registry -Phase deployment
        $deployment.permissions.permission | Should -Be 'Application.ReadWrite.All'
        $deployment.permissions.kind | Should -Be 'delegated'
    }

    It 'validates the reference starter manifests without requiring external checkouts' {
        foreach ($relativePath in 'skeleton/azd-permissions.json', 'examples/deployment-check/azd-permissions.json') {
            Get-Content (Join-Path $script:repoRoot $relativePath) -Raw |
                Test-Json -SchemaFile $script:schema -ErrorAction Stop | Should -BeTrue
        }
    }
}
