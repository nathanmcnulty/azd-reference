Describe 'Lab environment status' {
    BeforeAll {
        $script:repoRoot = Split-Path $PSScriptRoot -Parent
        $script:statusTool = Join-Path $script:repoRoot 'tooling/Get-AzdLabEnvironmentStatus.ps1'
        $script:subscriptionA = '22222222-2222-4222-8222-222222222222'
        $script:subscriptionB = '33333333-3333-4333-8333-333333333333'
        $script:tenant = '11111111-1111-4111-8111-111111111111'
    }

    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:inventory = Join-Path $script:caseRoot 'inventory'
        New-Item -ItemType Directory -Path $script:inventory -Force | Out-Null
        $script:registryPath = Join-Path $script:caseRoot 'registry.json'
        $script:outputPath = Join-Path $script:caseRoot 'status.json'
        $script:registry = [ordered]@{
            schemaVersion = '1.0'
            tenantId = $script:tenant
            targetSubscriptionId = $script:subscriptionA
            subscriptions = @($script:subscriptionA)
            subscriptionPolicies = @(
                [ordered]@{
                    subscriptionId = $script:subscriptionA
                    displayName = 'Example primary lab subscription'
                    role = 'primary'
                    monthlyCreditUSD = 150
                    budgetName = 'example-lab-budget'
                    budgetAmountUSD = 150
                    planningCeilingUSD = 120
                    notes = 'Planning values only.'
                }
            )
            solutions = @(
                [ordered]@{
                    id = 'example-solution'
                    repository = 'https://github.com/example/azd-example-solution'
                    desiredEnvironment = 'pilot'
                    deployableKind = 'azure'
                    desiredResourceGroup = 'rg-example-pilot'
                    desiredTags = [ordered]@{
                        solution = 'example-solution'
                        'lab-environment' = 'pilot'
                        owner = 'example-owner'
                        'cost-center' = 'example-cost-center'
                        portfolio = 'example-portfolio'
                        environment = 'pilot'
                        'managed-by' = 'azd-reference'
                    }
                    environments = @(
                        [ordered]@{
                            name = 'pilot'
                            subscriptionId = $script:subscriptionA
                            resourceGroup = 'rg-example-pilot'
                            sourceRevision = 'fixture-revision'
                            validationStatus = 'control-plane-only'
                            tenantObjectsTracked = $false
                        }
                    )
                }
            )
        }
        $script:registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
    }

    function global:Write-LabInventoryFixture {
        param(
            [string] $SubscriptionId = $script:subscriptionA,
            [array] $Groups = @(),
            [array] $Resources = @()
        )
        if ($Groups.Count -eq 0) { $groupJson = '[]' } else { $groupJson = $Groups | ConvertTo-Json -Depth 20 -AsArray }
        if ($Resources.Count -eq 0) { $resourceJson = '[]' } else { $resourceJson = $Resources | ConvertTo-Json -Depth 20 -AsArray }
        $groupJson | Set-Content -LiteralPath (Join-Path $script:inventory "groups-$SubscriptionId.json") -Encoding utf8NoBOM
        $resourceJson | Set-Content -LiteralPath (Join-Path $script:inventory "resources-$SubscriptionId.json") -Encoding utf8NoBOM
    }

    function global:Get-LabStandardTags {
        return [ordered]@{
            solution = 'example-solution'
            'lab-environment' = 'pilot'
            owner = 'example-owner'
            'cost-center' = 'example-cost-center'
            portfolio = 'example-portfolio'
            environment = 'pilot'
            'managed-by' = 'azd-reference'
        }
    }

    It 'reports a wrong tenant from live account validation without changing the account' {
        function global:az {
            param()
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'account') {
                return '[{"id":"22222222-2222-4222-8222-222222222222","tenantId":"99999999-9999-4999-8999-999999999999"},{"id":"44444444-4444-4444-8444-444444444444","tenantId":"11111111-1111-4111-8111-111111111111"}]'
            }
            return '[]'
        }
        try {
            { & $script:statusTool -RegistryPath $script:registryPath -OutputPath $script:outputPath } | Should -Throw '*coverage is failed*'
            $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
            $report.accountValidation.subscriptions[0].status | Should -Be 'tenant-mismatch'
            $report.coverage | Should -Be 'failed'
        }
        finally {
            Remove-Item -LiteralPath function:\az -ErrorAction SilentlyContinue
        }
    }

    It 'preserves live empty and singleton arrays and passes explicit subscriptions' {
        $global:labAzCalls = [System.Collections.Generic.List[string]]::new()
        function global:az {
            param()
            $global:LASTEXITCODE = 0
            $global:labAzCalls.Add(($args -join ' '))
            if ($args[0] -eq 'account') {
                return '[{"id":"22222222-2222-4222-8222-222222222222","tenantId":"11111111-1111-4111-8111-111111111111"},{"id":"44444444-4444-4444-8444-444444444444","tenantId":"11111111-1111-4111-8111-111111111111"}]'
            }
            if ($args[0] -eq 'group') {
                return '[{"name":"rg-example-pilot","tags":{}}]'
            }
            return '[]'
        }
        try {
            $report = & $script:statusTool -RegistryPath $script:registryPath
            $report.coverage | Should -Be 'complete'
            $report.solutions[0].environments[0].presence | Should -Be 'present'
            $report.solutions[0].environments[0].resourceCount | Should -Be 0
            @($global:labAzCalls | Where-Object { $_ -like 'group *' -or $_ -like 'resource *' } | Where-Object { $_ -notlike '*--subscription 22222222-2222-4222-8222-222222222222*' }).Count | Should -Be 0
            @($global:labAzCalls | Where-Object { $_ -like 'login *' -or $_ -like 'account set *' }).Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath function:\az -ErrorAction SilentlyContinue
            Remove-Variable -Name labAzCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'reports a missing resource group as missing after complete fixture reads' {
        Write-LabInventoryFixture -Groups @() -Resources @()
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath
        $report.coverage | Should -Be 'complete'
        $report.solutions[0].environments[0].presence | Should -Be 'missing'
        $report.solutions[0].environments[0].resourceCount | Should -Be 0
    }

    It 'surfaces subscription policies as planned-only constraints' {
        Write-LabInventoryFixture -Groups @() -Resources @()
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $report.subscriptionPolicyStatus | Should -Be 'planned-only'
        $report.subscriptionPolicies[0].subscriptionId | Should -Be $script:subscriptionA
        $report.subscriptionPolicies[0].planningCeilingUSD | Should -Be 120
        $report.subscriptionPolicies[0].PSObject.Properties.Name | Should -Not -Contain 'remainingCreditUSD'
    }

    It 'supports older registries without optional subscription policies' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $data.PSObject.Properties.Remove('subscriptionPolicies')
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        Write-LabInventoryFixture -Groups @() -Resources @()
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $report.subscriptionPolicyStatus | Should -Be 'planned-only'
        @($report.subscriptionPolicies).Count | Should -Be 0
    }

    It 'enforces the registry byte limit before parsing multibyte input' {
        $oversizedRegistryPath = Join-Path $script:caseRoot 'oversized-registry.json'
        $characterCount = [int] [Math]::Floor((5MB) / 2) + 1
        $largeSyntheticInput = 'é' * $characterCount
        [System.IO.File]::WriteAllText($oversizedRegistryPath, $largeSyntheticInput, [System.Text.UTF8Encoding]::new($false))
        (Get-Item -LiteralPath $oversizedRegistryPath).Length | Should -BeGreaterThan 5MB
        $largeSyntheticInput.Length | Should -BeLessThan 5MB
        { & $script:statusTool -RegistryPath $oversizedRegistryPath -InventoryDirectory $script:inventory } | Should -Throw '*bounded input limit*'
    }

    It 'does not echo malformed registry contents in input errors' {
        $privateMarker = 'private-synthetic-registry-canary'
        [System.IO.File]::WriteAllText($script:registryPath, ('{"private":"' + $privateMarker), [System.Text.UTF8Encoding]::new($false))
        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Not -BeNullOrEmpty
        $failureMessage | Should -Not -Match $privateMarker
    }

    It 'refuses to overwrite the registry or an existing status report' {
        Write-LabInventoryFixture -Groups @() -Resources @()
        $registryBefore = [System.IO.File]::ReadAllText($script:registryPath)
        { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:registryPath } | Should -Throw '*OutputPath*'
        [System.IO.File]::ReadAllText($script:registryPath) | Should -Be $registryBefore

        $existingOutputPath = Join-Path $script:caseRoot 'existing-status.json'
        [System.IO.File]::WriteAllText($existingOutputPath, 'preserve synthetic report')
        { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $existingOutputPath } | Should -Throw '*OutputPath*'
        [System.IO.File]::ReadAllText($existingOutputPath) | Should -Be 'preserve synthetic report'
    }

    It 'rejects duplicate, undeclared, nonpositive, and over-ceiling policies' {
        $cases = @(
            @{ Name = 'duplicate'; Error = '*duplicate subscription policies*'; Change = { param($data) $duplicate = $data.subscriptionPolicies[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $duplicate.displayName = 'Second policy'; $data.subscriptionPolicies = @($data.subscriptionPolicies[0], $duplicate) } },
            @{ Name = 'undeclared'; Error = '*undeclared subscription*'; Change = { param($data) $data.subscriptionPolicies[0].subscriptionId = '44444444-4444-4444-8444-444444444444' } },
            @{ Name = 'nonpositive'; Error = '*schema validation*'; Change = { param($data) $data.subscriptionPolicies[0].budgetAmountUSD = 0 } },
            @{ Name = 'over-ceiling'; Error = '*planning ceiling cannot exceed*'; Change = { param($data) $data.subscriptionPolicies[0].planningCeilingUSD = 151 } }
        )
        foreach ($case in $cases) {
            $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            & $case.Change $data
            $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
            { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory } | Should -Throw $case.Error
        }
    }

    It 'does not expose subscription identifiers in validation errors' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $data.subscriptionPolicies[0].subscriptionId = $script:subscriptionB
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'undeclared subscription'
        $failureMessage | Should -Not -Match $script:subscriptionB
    }

    It 'does not map a resource group across subscriptions' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $data.subscriptions = @($script:subscriptionA, $script:subscriptionB)
        $data.solutions[0].environments[0].subscriptionId = $script:subscriptionB
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        Write-LabInventoryFixture -SubscriptionId $script:subscriptionA -Groups @([ordered]@{ name = 'rg-example-pilot'; tags = (Get-LabStandardTags) }) -Resources @()
        Write-LabInventoryFixture -SubscriptionId $script:subscriptionB -Groups @() -Resources @()
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath
        $report.solutions[0].environments[0].presence | Should -Be 'missing'
        $report.extraGroups[0].presence | Should -Be 'unmapped'
        $report.extraGroups[0].subscriptionId | Should -Be $script:subscriptionA
    }

    It 'reports required tag drift separately from optional compatibility markers' {
        $wrongTags = [ordered]@{
            solution = 'other-solution'
            'lab-environment' = 'other-lab'
            owner = 'other-owner'
            'cost-center' = 'other-cost-center'
            portfolio = 'other-portfolio'
            environment = 'other-environment'
            'managed-by' = 'other-manager'
        }
        Write-LabInventoryFixture -Groups @([ordered]@{ name = 'RG-Example-Pilot'; tags = $wrongTags }) -Resources @([ordered]@{ name = 'resource-one'; resourceGroup = 'RG-EXAMPLE-PILOT'; tags = $wrongTags })
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $report.solutions[0].environments[0].presence | Should -Be 'present'
        $drift = $report.solutions[0].environments[0].tagDrift
        $drift.hasDrift | Should -BeTrue
        $drift.required.group.solution.state | Should -Be 'mismatch'
        $drift.required.resourceDriftCount | Should -Be 1
        $drift.compatibility.group.environment.state | Should -Be 'mismatch'
        $drift.compatibility.group.'managed-by'.state | Should -Be 'mismatch'
    }

    It 'does not treat missing inventory data as zero resources' {
        $groups = @([ordered]@{ name = 'rg-example-pilot'; tags = (Get-LabStandardTags) })
        $groups | ConvertTo-Json -Depth 20 -AsArray | Set-Content -LiteralPath (Join-Path $script:inventory "groups-$($script:subscriptionA).json") -Encoding utf8NoBOM
        $failureOutput = @()
        $failureMessage = $null
        try { $failureOutput = @(& $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath) }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is unknown'
        $failureOutput | Should -BeNullOrEmpty
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'unknown'
        $report.solutions[0].environments[0].resourceCount | Should -BeNullOrEmpty
    }

    It 'includes declared subscriptions without environment rows in aggregate coverage' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $data.subscriptions = @($script:subscriptionA, $script:subscriptionB)
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        Write-LabInventoryFixture -SubscriptionId $script:subscriptionA -Groups @() -Resources @()

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @(
                '-NoLogo', '-NoProfile', '-File', $script:statusTool,
                '-RegistryPath', $script:registryPath,
                '-InventoryDirectory', $script:inventory,
                '-OutputPath', $script:outputPath
            )) {
            $startInfo.ArgumentList.Add($argument)
        }
        $process = [System.Diagnostics.Process]::Start($startInfo)
        try {
            $standardOutput = $process.StandardOutput.ReadToEndAsync()
            $standardError = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $process.ExitCode | Should -Not -Be 0
            $standardOutput.GetAwaiter().GetResult() | Should -BeNullOrEmpty
            $standardError.GetAwaiter().GetResult() | Should -Match 'coverage is unknown'
        }
        finally {
            $process.Dispose()
        }

        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'unknown'
        $report.trackedResourceCount | Should -BeNullOrEmpty
        $report.untrackedResourceCount | Should -BeNullOrEmpty
        $report.subscriptions[1].subscriptionId | Should -Be $script:subscriptionB
        $report.subscriptions[1].groupsStatus | Should -Be 'unknown'
        $report.subscriptions[1].resourcesStatus | Should -Be 'unknown'
        $report.subscriptions[1].groupCount | Should -BeNullOrEmpty
        $report.subscriptions[1].resourceCount | Should -BeNullOrEmpty
    }

    It 'accepts ARM inventory IDs for the file subscription when subscriptionId is absent' {
        $groupId = "/subscriptions/$($script:subscriptionA)/resourceGroups/rg-example-pilot"
        $resourceId = "$groupId/providers/Microsoft.Storage/storageAccounts/example-one"
        Write-LabInventoryFixture -Groups @([ordered]@{ id = $groupId; name = 'rg-example-pilot'; tags = (Get-LabStandardTags) }) -Resources @([ordered]@{ id = $resourceId; name = 'example-one' })

        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $report.coverage | Should -Be 'complete'
        $report.solutions[0].environments[0].presence | Should -Be 'present'
        $report.solutions[0].environments[0].resourceCount | Should -Be 1
        $report.trackedResourceCount | Should -Be 1
        $report.untrackedResourceCount | Should -Be 0
        $report.subscriptions[0].resourceCount | Should -Be 1
    }

    It 'rejects resource inventory with <CaseName> group scope' -ForEach @(
        @{ CaseName = 'absent'; Metadata = @{} },
        @{ CaseName = 'null'; Metadata = @{ resourceGroup = $null } },
        @{ CaseName = 'blank'; Metadata = @{ resourceGroup = ' ' } },
        @{ CaseName = 'subscription-only'; Metadata = @{ id = '/subscriptions/22222222-2222-4222-8222-222222222222/providers/Microsoft.Authorization/policyAssignments/one' } }
    ) {
        $resource = [ordered]@{ name = 'one' }
        foreach ($key in $Metadata.Keys) { $resource[$key] = $Metadata[$key] }
        Write-LabInventoryFixture -Groups @() -Resources @($resource)

        $failureOutput = @()
        $failureMessage = $null
        try { $failureOutput = @(& $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath) }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is failed'
        $failureOutput | Should -BeNullOrEmpty
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'failed'
        $report.subscriptions[0].resourcesStatus | Should -Be 'failed'
        $report.subscriptions[0].resourceCount | Should -BeNullOrEmpty
        $report.trackedResourceCount | Should -BeNullOrEmpty
        $report.untrackedResourceCount | Should -BeNullOrEmpty
        $report.findings | Should -Contain "inventoryInvalid:resources:$($script:subscriptionA)"
    }

    It 'rejects conflicting <CaseName> group metadata' -ForEach @(
        @{ CaseName = 'group name and ARM ID'; Kind = 'groups' },
        @{ CaseName = 'resourceGroup and ARM ID'; Kind = 'resources' },
        @{ CaseName = 'resourceGroupName and ARM ID'; Kind = 'resources' },
        @{ CaseName = 'resourceGroup and resourceGroupName'; Kind = 'resources' }
    ) {
        $groupId = "/subscriptions/$($script:subscriptionA)/resourceGroups/rg-example-pilot"
        $group = [ordered]@{ name = 'rg-example-pilot'; id = $groupId }
        $resource = [ordered]@{ name = 'one'; id = "$groupId/providers/Microsoft.Storage/storageAccounts/one" }
        switch ($CaseName) {
            'group name and ARM ID' { $group.id = $groupId -replace 'rg-example-pilot', 'rg-actual' }
            'resourceGroup and ARM ID' {
                $resource.resourceGroup = 'rg-example-pilot'
                $resource.id = $resource.id -replace 'rg-example-pilot', 'rg-actual'
            }
            'resourceGroupName and ARM ID' {
                $resource.resourceGroupName = 'rg-example-pilot'
                $resource.id = $resource.id -replace 'rg-example-pilot', 'rg-actual'
            }
            'resourceGroup and resourceGroupName' {
                $resource.Remove('id')
                $resource.resourceGroup = 'rg-example-pilot'
                $resource.resourceGroupName = 'rg-actual'
            }
        }
        Write-LabInventoryFixture -Groups @($group) -Resources @($resource)

        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is failed'
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'failed'
        $report.subscriptions[0]."$($Kind)Status" | Should -Be 'failed'
        $report.trackedResourceCount | Should -BeNullOrEmpty
        $report.untrackedResourceCount | Should -BeNullOrEmpty
    }

    It 'rejects malformed <CaseName> ARM IDs despite usable direct group metadata' -ForEach @(
        @{ CaseName = 'resource prefix'; Kind = 'resources'; Id = '/resourceGroups/rg-example-pilot/providers/Microsoft.Storage/storageAccounts/one' },
        @{ CaseName = 'resource suffix'; Kind = 'resources'; Id = '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-example-pilot/providers/Microsoft.Storage/storageAccounts' },
        @{ CaseName = 'group suffix'; Kind = 'groups'; Id = '/subscriptions/22222222-2222-4222-8222-222222222222/resourceGroups/rg-example-pilot/providers/Microsoft.Storage/storageAccounts/one' }
    ) {
        $group = [ordered]@{ name = 'rg-example-pilot' }
        $resource = [ordered]@{ name = 'one'; resourceGroup = 'rg-example-pilot' }
        if ($Kind -eq 'groups') { $group.id = $Id } else { $resource.id = $Id }
        Write-LabInventoryFixture -Groups @($group) -Resources @($resource)

        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is failed'
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'failed'
        $report.subscriptions[0]."$($Kind)Status" | Should -Be 'failed'
        $report.trackedResourceCount | Should -BeNullOrEmpty
        $report.untrackedResourceCount | Should -BeNullOrEmpty
    }

    It 'accounts for every resource with consistent case-insensitive scope and null group fallback' {
        $groupId = "/subscriptions/$($script:subscriptionA)/resourceGroups/RG-EXAMPLE-PILOT"
        $groups = @(
            [ordered]@{ name = 'rg-example-pilot'; id = $groupId },
            [ordered]@{ name = 'rg-extra' }
        )
        $resources = @(
            [ordered]@{ name = 'one'; resourceGroup = $null; id = "$groupId/providers/Microsoft.Storage/storageAccounts/one" },
            [ordered]@{ name = 'two'; resourceGroup = 'rg-example-pilot'; resourceGroupName = 'RG-EXAMPLE-PILOT'; id = "$groupId/providers/Microsoft.Storage/storageAccounts/two" },
            [ordered]@{ name = 'three'; resourceGroup = $null; resourceGroupName = 'RG-EXTRA' }
        )
        Write-LabInventoryFixture -Groups $groups -Resources $resources

        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $report.coverage | Should -Be 'complete'
        $report.solutions[0].environments[0].resourceCount | Should -Be 2
        $report.subscriptions[0].resourceCount | Should -Be 3
        $report.trackedResourceCount | Should -Be 2
        $report.untrackedResourceCount | Should -Be 1
        ($report.trackedResourceCount + $report.untrackedResourceCount) | Should -Be $report.subscriptions[0].resourceCount
        @($report.unmappedResources).Count | Should -Be 1
        $report.unmappedResources[0].name | Should -Be 'three'
    }

    It 'rejects a resource group ARM ID from another subscription without subscriptionId' {
        $groupId = "/subscriptions/$($script:subscriptionB)/resourceGroups/rg-example-pilot"
        Write-LabInventoryFixture -Groups @([ordered]@{ id = $groupId; name = 'rg-example-pilot'; tags = (Get-LabStandardTags) }) -Resources @()

        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is failed'
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'failed'
        $report.subscriptions[0].groupsStatus | Should -Be 'failed'
    }

    It 'rejects a resource ARM ID from another subscription without subscriptionId' {
        $groupId = "/subscriptions/$($script:subscriptionA)/resourceGroups/rg-example-pilot"
        $resourceId = "/subscriptions/$($script:subscriptionB)/resourceGroups/rg-example-pilot/providers/Microsoft.Storage/storageAccounts/example-one"
        Write-LabInventoryFixture -Groups @([ordered]@{ id = $groupId; name = 'rg-example-pilot'; tags = (Get-LabStandardTags) }) -Resources @([ordered]@{ id = $resourceId; name = 'example-one' })

        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is failed'
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'failed'
        $report.subscriptions[0].resourcesStatus | Should -Be 'failed'
    }

    It 'does not silently count resources whose group is absent from inventory' {
        $resourceId = "/subscriptions/$($script:subscriptionA)/resourceGroups/rg-extra/providers/Microsoft.Storage/storageAccounts/example-one"
        Write-LabInventoryFixture -Groups @() -Resources @([ordered]@{ id = $resourceId; name = 'example-one' })

        $failureMessage = $null
        try { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory -OutputPath $script:outputPath }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match 'coverage is failed'
        $report = Get-Content -LiteralPath $script:outputPath -Raw | ConvertFrom-Json
        $report.coverage | Should -Be 'failed'
        $report.trackedResourceCount | Should -BeNullOrEmpty
        $report.untrackedResourceCount | Should -BeNullOrEmpty
        $report.findings | Should -Contain 'inventoryInconsistent:resourceGroupMissingFromGroupInventory'
        $report.subscriptions[0].resourceCount | Should -Be 1
    }

    It 'keeps declared tenant objects as tenant-only and never as resource presence' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $data.solutions[0].deployableKind = 'tenant'
        $data.solutions[0].environments[0].resourceGroup = $null
        $data.solutions[0].environments[0].tenantObjectsTracked = $true
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        Write-LabInventoryFixture -Groups @([ordered]@{ name = 'rg-unrelated'; tags = (Get-LabStandardTags) }) -Resources @()
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $environment = $report.solutions[0].environments[0]
        $environment.presence | Should -Be 'tenant-only'
        $environment.resourceCount | Should -BeNullOrEmpty
        $report.extraGroups[0].presence | Should -Be 'unmapped'
    }

    It 'reports an Azure row without a resource group as unmapped' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $data.solutions[0].environments[0].resourceGroup = $null
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        Write-LabInventoryFixture -Groups @() -Resources @()
        $report = & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory
        $report.solutions[0].environments[0].presence | Should -Be 'unmapped'
    }

    It 'rejects duplicate resource group mappings within a subscription' {
        $data = $script:registry | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $duplicate = $data.solutions[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $duplicate.id = 'second-solution'
        $data.solutions = @($data.solutions[0], $duplicate)
        $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:registryPath -Encoding utf8NoBOM
        Write-LabInventoryFixture -Groups @() -Resources @()
        { & $script:statusTool -RegistryPath $script:registryPath -InventoryDirectory $script:inventory } | Should -Throw '*Duplicate resource group mapping*'
    }
}
