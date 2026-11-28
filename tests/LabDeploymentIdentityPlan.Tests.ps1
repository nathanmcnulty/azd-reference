$script:planTool = Join-Path (Split-Path -Parent $PSScriptRoot) 'tooling\Get-AzdLabDeploymentIdentityPlan.ps1'

function New-TestRegistry {
    param(
        [string] $DeployableKind = 'azure',
        [string] $ResourceGroup = 'rg-workload-sample',
        [string] $SourceRevision = ('a' * 40),
        [string] $EnvironmentSubscriptionId = '11111111-1111-4111-8111-111111111111'
    )

    [ordered]@{
        schemaVersion = '1.0'
        tenantId = '22222222-2222-4222-8222-222222222222'
        targetSubscriptionId = '11111111-1111-4111-8111-111111111111'
        subscriptions = @('11111111-1111-4111-8111-111111111111')
        solutions = @(
            [ordered]@{
                id = 'sample-solution'
                repository = 'https://github.com/example/sample'
                desiredEnvironment = 'lab'
                desiredResourceGroup = $ResourceGroup
                deployableKind = $DeployableKind
                environments = @(
                    [ordered]@{
                        name = 'lab'
                        subscriptionId = $EnvironmentSubscriptionId
                        resourceGroup = $ResourceGroup
                        sourceRevision = $SourceRevision
                        validationStatus = 'validated'
                        tenantObjectsTracked = $true
                    }
                )
            }
        )
    }
}

function Write-TestRegistry {
    param(
        [Parameter(Mandatory)] $Registry,
        [Parameter(Mandatory)][string] $Directory
    )

    $path = Join-Path $Directory ("registry-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    $Registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
    return $path
}

function Invoke-TestPlan {
    param(
        [Parameter(Mandatory)] $Registry,
        [Parameter(Mandatory)][string] $Directory,
        [string] $GitHubEnvironment = 'production',
        [string] $EnvironmentName = 'lab'
    )

    $registryPath = Write-TestRegistry -Registry $Registry -Directory $Directory
    $outputPath = Join-Path $Directory 'deployment-identity-plan.json'
    try {
        $raw = & $script:planTool `
            -RegistryPath $registryPath `
            -SolutionId 'sample-solution' `
            -EnvironmentName $EnvironmentName `
            -GitHubEnvironment $GitHubEnvironment `
            -OutputPath $outputPath 2>&1
        return [pscustomobject]@{
            Plan = (($raw | Out-String) | ConvertFrom-Json)
            OutputPath = $outputPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $registryPath) { [System.IO.File]::Delete($registryPath) }
        if (Test-Path -LiteralPath $outputPath) { [System.IO.File]::Delete($outputPath) }
    }
}

Describe 'Get-AzdLabDeploymentIdentityPlan' {
    BeforeAll {
        $script:planTool = Join-Path (Split-Path -Parent $PSScriptRoot) 'tooling\Get-AzdLabDeploymentIdentityPlan.ps1'
        $global:planTool = $script:planTool
        function global:New-TestRegistry {
            param(
                [string] $DeployableKind = 'azure',
                [string] $ResourceGroup = 'rg-workload-sample',
                [string] $SourceRevision = ('a' * 40),
                [string] $EnvironmentSubscriptionId = '11111111-1111-4111-8111-111111111111'
            )
            [ordered]@{
                schemaVersion = '1.0'
                tenantId = '22222222-2222-4222-8222-222222222222'
                targetSubscriptionId = '11111111-1111-4111-8111-111111111111'
                subscriptions = @('11111111-1111-4111-8111-111111111111')
                solutions = @([ordered]@{
                    id = 'sample-solution'
                    repository = 'https://github.com/example/sample'
                    desiredEnvironment = 'lab'
                    desiredResourceGroup = $ResourceGroup
                    deployableKind = $DeployableKind
                    environments = @([ordered]@{
                        name = 'lab'
                        subscriptionId = $EnvironmentSubscriptionId
                        resourceGroup = $ResourceGroup
                        sourceRevision = $SourceRevision
                        validationStatus = 'validated'
                        tenantObjectsTracked = $true
                    })
                })
            }
        }
        function global:Write-TestRegistry {
            param([Parameter(Mandatory)] $Registry, [Parameter(Mandatory)][string] $Directory)
            $path = Join-Path $Directory ("registry-{0}.json" -f ([guid]::NewGuid().ToString('N')))
            $Registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
            return $path
        }
        function global:Invoke-TestPlan {
            param(
                [Parameter(Mandatory)] $Registry,
                [Parameter(Mandatory)][string] $Directory,
                [string] $GitHubEnvironment = 'production',
                [string] $EnvironmentName = 'lab'
            )
            $registryPath = Write-TestRegistry -Registry $Registry -Directory $Directory
            $outputPath = Join-Path $Directory 'deployment-identity-plan.json'
            try {
                $raw = & $global:planTool -RegistryPath $registryPath -SolutionId 'sample-solution' -EnvironmentName $EnvironmentName -GitHubEnvironment $GitHubEnvironment -OutputPath $outputPath 2>&1
                return [pscustomobject]@{ Plan = (($raw | Out-String) | ConvertFrom-Json); OutputPath = $outputPath }
            }
            finally {
                if (Test-Path -LiteralPath $registryPath) { [System.IO.File]::Delete($registryPath) }
                if (Test-Path -LiteralPath $outputPath) { [System.IO.File]::Delete($outputPath) }
            }
        }
    }

    It 'creates a deterministic review-only plan with exact OIDC binding' {
        $registry = New-TestRegistry
        $first = Invoke-TestPlan -Registry $registry -Directory $TestDrive -GitHubEnvironment 'prod-lab'
        $second = Invoke-TestPlan -Registry $registry -Directory $TestDrive -GitHubEnvironment 'prod-lab'

        ($first.Plan | ConvertTo-Json -Depth 20) | Should -Be ($second.Plan | ConvertTo-Json -Depth 20)
        $first.Plan.deployableKind | Should -Be 'azure'
        $first.Plan.identityPlacement.resourceGroup | Should -Be 'rg-azd-lab-management'
        $first.Plan.identityPlacement.name.Length | Should -BeLessOrEqual 64
        $first.Plan.deploymentTemplateInputs.identityName | Should -Be $first.Plan.identityPlacement.name
        $first.Plan.deploymentTemplateInputs.repository | Should -Be 'example/sample'
        $first.Plan.deploymentTemplateInputs.githubEnvironment | Should -Be 'prod-lab'
        $first.Plan.deploymentTemplateInputs.grantContributor | Should -BeFalse
        $first.Plan.workload.scope | Should -Be '/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-workload-sample'
        $first.Plan.authorization.roleDefinitionName | Should -Be 'Contributor'
        $first.Plan.authorization.status | Should -Be 'proposed'
        $first.Plan.authorization.granted | Should -BeFalse
        $first.Plan.federatedCredential.issuer | Should -Be 'https://token.actions.githubusercontent.com'
        $first.Plan.federatedCredential.audience | Should -Be 'api://AzureADTokenExchange'
        $first.Plan.federatedCredential.subject | Should -Be 'repo:example/sample:environment:prod-lab'
        $first.Plan.sourceBinding.statement | Should -Match 'does not prove the local checkout'
        $first.Plan.guards.defaultBranch.status | Should -Be 'pending'
        $first.Plan.guards.liveOidc.status | Should -Be 'pending'
        $first.Plan.boundaries.graphAndBootstrap | Should -Be 'outside-deploy-identity-plan'
    }

    It 'does not confuse an inherited native exit code with planner failure' {
        $previousExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $previousExitCodeValue = if ($null -ne $previousExitCode) { $previousExitCode.Value } else { $null }
        try {
            $global:LASTEXITCODE = 23
            $result = Invoke-TestPlan -Registry (New-TestRegistry) -Directory $TestDrive
            $result.Plan.solutionId | Should -Be 'sample-solution'
            $global:LASTEXITCODE | Should -Be 23
        }
        finally {
            if ($null -ne $previousExitCode) { $global:LASTEXITCODE = $previousExitCodeValue }
            else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        }
    }

    It 'rejects a duplicate solution target' {
        $registry = New-TestRegistry
        $registry.solutions = @($registry.solutions[0], $registry.solutions[0])
        { Invoke-TestPlan -Registry $registry -Directory $TestDrive } | Should -Throw '*ambiguous*'
    }

    It 'does not echo registry identifiers in ambiguous lookup errors' {
        $privateMarker = 'private-synthetic-solution'
        $registry = New-TestRegistry
        $registry.solutions[0].id = $privateMarker
        $registry.solutions = @($registry.solutions[0], $registry.solutions[0])
        $registryPath = Write-TestRegistry -Registry $registry -Directory $TestDrive
        $failureMessage = $null
        try {
            & $script:planTool -RegistryPath $registryPath -SolutionId $privateMarker -EnvironmentName 'lab' -GitHubEnvironment 'lab'
        }
        catch {
            $failureMessage = $_.Exception.Message
        }
        finally {
            if (Test-Path -LiteralPath $registryPath) { [System.IO.File]::Delete($registryPath) }
        }
        $failureMessage | Should -Be 'The selected solution is ambiguous in the registry.'
        $failureMessage | Should -Not -Match $privateMarker
    }

    It 'rejects a duplicate environment target' {
        $registry = New-TestRegistry
        $environment = $registry.solutions[0].environments[0]
        $registry.solutions[0].environments = @($environment, $environment)
        { Invoke-TestPlan -Registry $registry -Directory $TestDrive } | Should -Throw '*ambiguous*'
    }

    It 'rejects non-Azure rows, invalid revisions, and missing subscription membership' {
        { Invoke-TestPlan -Registry (New-TestRegistry -DeployableKind 'tenant') -Directory $TestDrive } | Should -Throw '*not an azure*'
        { Invoke-TestPlan -Registry (New-TestRegistry -SourceRevision 'not-a-commit') -Directory $TestDrive } | Should -Throw '*40-hex*'
        { Invoke-TestPlan -Registry (New-TestRegistry -EnvironmentSubscriptionId '33333333-3333-4333-8333-333333333333') -Directory $TestDrive } | Should -Throw '*subscription*'
    }

    It 'rejects management and workload resource-group scope collisions' {
        { Invoke-TestPlan -Registry (New-TestRegistry -ResourceGroup 'RG-AZD-LAB-MANAGEMENT') -Directory $TestDrive } | Should -Throw '*cannot equal management*'
    }

    It 'rejects invalid GitHub environment characters' {
        { Invoke-TestPlan -Registry (New-TestRegistry) -Directory $TestDrive -GitHubEnvironment 'prod_lab' } | Should -Throw '*ASCII letters*'
    }

    It 'refuses to overwrite the source registry or an existing report' {
        $registryPath = Write-TestRegistry -Registry (New-TestRegistry) -Directory $TestDrive
        $before = [System.IO.File]::ReadAllText($registryPath)
        {
            & $script:planTool -RegistryPath $registryPath -SolutionId 'sample-solution' -EnvironmentName 'lab' -GitHubEnvironment 'lab' -OutputPath $registryPath
        } | Should -Throw
        [System.IO.File]::ReadAllText($registryPath) | Should -Be $before

        $outputPath = Join-Path $TestDrive 'preserved-report.json'
        [System.IO.File]::WriteAllText($outputPath, 'preserve this report')
        {
            & $script:planTool -RegistryPath $registryPath -SolutionId 'sample-solution' -EnvironmentName 'lab' -GitHubEnvironment 'lab' -OutputPath $outputPath
        } | Should -Throw
        [System.IO.File]::ReadAllText($outputPath) | Should -Be 'preserve this report'
    }

    It 'contains no Azure, GitHub, login, or hook command ASTs' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:planTool, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $commandNames = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true) | ForEach-Object { $_.GetCommandName() })
        $commandNames | Should -Not -Contain 'az'
        $commandNames | Should -Not -Contain 'azd'
        $commandNames | Should -Not -Contain 'gh'
        $commandNames | Should -Not -Contain 'Connect-AzAccount'
        $commandNames | Should -Not -Contain 'Invoke-RestMethod'
    }
}
