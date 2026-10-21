[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $RegistryPath,

    [string] $OutputPath,

    [string] $InventoryDirectory,

    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$maxInputBytes = 5MB
$schemaPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) 'schemas/lab-environments.schema.json'

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string[]] $Names
    )

    if ($null -eq $InputObject) { return $null }
    foreach ($name in $Names) {
        if ($InputObject.PSObject.Properties.Name -contains $name) {
            return $InputObject.$name
        }
    }
    return $null
}

function Get-TagMap {
    param($InputObject)

    $result = @{}
    $tagObject = Get-PropertyValue -InputObject $InputObject -Names @('tags')
    if ($null -ne $tagObject) {
        foreach ($property in $tagObject.PSObject.Properties) {
            $result[[string] $property.Name] = [string] $property.Value
        }
    }
    return $result
}

function Get-ResourceGroupName {
    param($InputObject)

    foreach ($field in @('resourceGroup', 'resourceGroupName')) {
        $direct = Get-PropertyValue -InputObject $InputObject -Names @($field)
        if ($null -ne $direct -and -not [string]::IsNullOrWhiteSpace([string] $direct)) {
            return [string] $direct
        }
    }
    $id = [string] (Get-PropertyValue -InputObject $InputObject -Names @('id'))
    if ($id -match '(?i)/resourceGroups/([^/]+)') {
        return [System.Uri]::UnescapeDataString($Matches[1])
    }
    return $null
}

function Assert-InventoryShape {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Data,
        [Parameter(Mandatory)][ValidateSet('groups', 'resources')][string] $Kind,
        [Parameter(Mandatory)][string] $SubscriptionId
    )

    foreach ($item in $Data) {
        if ($null -eq $item -or $item -is [string] -or $item -is [ValueType]) {
            throw 'Inventory entries must be JSON objects.'
        }
        $name = [string] (Get-PropertyValue -InputObject $item -Names @('name'))
        $id = [string] (Get-PropertyValue -InputObject $item -Names @('id'))
        if ($Kind -eq 'groups' -and [string]::IsNullOrWhiteSpace($name)) {
            throw 'Resource groups must include a name.'
        }
        if ($Kind -eq 'resources' -and [string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($id)) {
            throw 'Resources must include a name or id.'
        }
        $itemSubscription = Get-PropertyValue -InputObject $item -Names @('subscriptionId')
        if ($null -ne $itemSubscription -and [string] $itemSubscription -and [string] $itemSubscription -ine $SubscriptionId) {
            throw 'Inventory entry subscription does not match its file.'
        }
        $idResourceGroup = $null
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $idPattern = if ($Kind -eq 'groups') {
                '^/subscriptions/([^/]+)/resourceGroups/([^/]+)$'
            }
            else {
                '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/[^/]+(?:/[^/]+/[^/]+)+$'
            }
            if ($id -notmatch $idPattern) {
                throw 'Inventory entry ARM ID does not identify the expected scope.'
            }
            if ($Matches[1] -ine $SubscriptionId) {
                throw 'Inventory entry subscription does not match its file.'
            }
            $idResourceGroup = [System.Uri]::UnescapeDataString($Matches[2])
            if ([string]::IsNullOrWhiteSpace($idResourceGroup) -or $idResourceGroup.Contains('/')) {
                throw 'Inventory entry ARM ID has an invalid resource group.'
            }
            if ($Kind -eq 'groups' -and $name -ine $idResourceGroup) {
                throw 'Inventory group name does not match its ARM ID.'
            }
        }
        if ($Kind -eq 'resources') {
            $resourceGroup = $idResourceGroup
            foreach ($field in @('resourceGroup', 'resourceGroupName')) {
                $direct = Get-PropertyValue -InputObject $item -Names @($field)
                if ($null -eq $direct -or [string]::IsNullOrWhiteSpace([string] $direct)) { continue }
                if ($direct -isnot [string] -or ($resourceGroup -and $direct -ine $resourceGroup)) {
                    throw 'Inventory resource group metadata is inconsistent.'
                }
                $resourceGroup = $direct
            }
            if ([string]::IsNullOrWhiteSpace([string] $resourceGroup)) {
                throw 'Resources must identify a resource group.'
            }
        }
    }
}

function Get-ExpectedTagMap {
    param(
        [Parameter(Mandatory)] $Solution,
        [Parameter(Mandatory)] $Environment
    )

    $custom = Get-PropertyValue -InputObject $Solution -Names @('desiredTags')
    $environmentValue = [string] $Environment.name
    $defaults = [ordered]@{
        solution = [string] $Solution.id
        'lab-environment' = $environmentValue
        owner = 'unassigned'
        'cost-center' = 'unassigned'
        portfolio = 'azd'
        environment = $environmentValue
        'managed-by' = 'azd'
    }
    foreach ($key in @('solution', 'lab-environment', 'owner', 'cost-center', 'portfolio', 'environment', 'managed-by')) {
        if ($null -ne $custom -and $custom.PSObject.Properties.Name -contains $key) {
            $defaults[$key] = [string] $custom.$key
        }
    }
    return $defaults
}

function Compare-Tag {
    param(
        [Parameter(Mandatory)][hashtable] $Tags,
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][string] $Expected
    )

    if (-not $Tags.ContainsKey($Key)) {
        return [pscustomobject] [ordered]@{
            expected = $Expected
            observed = $null
            state = 'missing'
        }
    }
    $observed = [string] $Tags[$Key]
    return [pscustomobject] [ordered]@{
        expected = $Expected
        observed = $observed
        state = if ($observed -ceq $Expected) { 'match' } else { 'mismatch' }
    }
}

function Invoke-AzJsonRead {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $Description
    )

    $output = @(& az @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Description failed (exit code $exitCode)."
    }
    try {
        return ($output -join "`n") | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
    }
    catch {
        throw "$Description returned invalid JSON."
    }
}

function Get-InventoryResult {
    param(
        [Parameter(Mandatory)][string] $SubscriptionId,
        [Parameter(Mandatory)][ValidateSet('groups', 'resources')][string] $Kind,
        [Parameter(Mandatory)][bool] $FixtureMode
    )

    if ($FixtureMode) {
        $inventoryPath = Join-Path ([System.IO.Path]::GetFullPath($InventoryDirectory)) "$Kind-$SubscriptionId.json"
        if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
            return [pscustomobject] [ordered]@{
                status = 'unknown'
                data = @()
                finding = "inventoryMissing:$Kind"
            }
        }
        try {
            $inventoryFile = Get-Item -LiteralPath $inventoryPath -ErrorAction Stop
            if ($inventoryFile.Length -gt $maxInputBytes) { throw 'input limit' }
            $inventoryRaw = Get-Content -LiteralPath $inventoryPath -Raw -ErrorAction Stop
            $data = $inventoryRaw | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
            if ($null -eq $data -or $data -isnot [array]) { throw 'not an array' }
            Assert-InventoryShape -Data $data -Kind $Kind -SubscriptionId $SubscriptionId
            return [pscustomobject] [ordered]@{
                status = 'complete'
                data = @($data)
                finding = $null
            }
        }
        catch {
            return [pscustomobject] [ordered]@{
                status = 'failed'
                data = @()
                finding = "inventoryInvalid:$Kind"
            }
        }
    }

    try {
        $arguments = if ($Kind -eq 'groups') {
            @('group', 'list', '--subscription', $SubscriptionId, '--output', 'json')
        }
        else {
            @('resource', 'list', '--subscription', $SubscriptionId, '--output', 'json')
        }
        $description = "Azure $Kind query for subscription '$SubscriptionId'"
        $data = Invoke-AzJsonRead -Arguments $arguments -Description $description
        if ($data -isnot [array]) { throw "$description returned a non-array result." }
        Assert-InventoryShape -Data $data -Kind $Kind -SubscriptionId $SubscriptionId
        return [pscustomobject] [ordered]@{
            status = 'complete'
            data = @($data)
            finding = $null
        }
    }
    catch {
        return [pscustomobject] [ordered]@{
            status = 'failed'
            data = @()
            finding = "queryFailed:$Kind"
        }
    }
}

function Get-TagDrift {
    param(
        [Parameter(Mandatory)] $ExpectedTags,
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)][AllowEmptyCollection()][array] $Resources,
        [Parameter(Mandatory)][string] $ResourceGroup
    )

    $groupTags = Get-TagMap -InputObject $Group
    $groupDrift = [ordered]@{}
    $compatibilityDrift = [ordered]@{}
    $hasGroupDrift = $false
    foreach ($key in @('solution', 'lab-environment', 'owner', 'cost-center', 'portfolio')) {
        $comparison = Compare-Tag -Tags $groupTags -Key $key -Expected ([string] $ExpectedTags[$key])
        $groupDrift[$key] = $comparison
        if ($comparison.state -ne 'match') { $hasGroupDrift = $true }
    }
    foreach ($key in @('environment', 'managed-by')) {
        $compatibilityDrift[$key] = Compare-Tag -Tags $groupTags -Key $key -Expected ([string] $ExpectedTags[$key])
    }

    $resourceDriftCount = 0
    $compatibilityResourceDriftCount = 0
    foreach ($resource in $Resources) {
        if ((Get-ResourceGroupName -InputObject $resource) -ine $ResourceGroup) { continue }
        $tags = Get-TagMap -InputObject $resource
        foreach ($key in @('solution', 'lab-environment', 'owner', 'cost-center', 'portfolio')) {
            $comparison = Compare-Tag -Tags $tags -Key $key -Expected ([string] $ExpectedTags[$key])
            if ($comparison.state -ne 'match') {
                $resourceDriftCount++
                break
            }
        }
        foreach ($key in @('environment', 'managed-by')) {
            $comparison = Compare-Tag -Tags $tags -Key $key -Expected ([string] $ExpectedTags[$key])
            if ($comparison.state -ne 'match') {
                $compatibilityResourceDriftCount++
                break
            }
        }
    }

    return [pscustomobject] [ordered]@{
        hasDrift = ($hasGroupDrift -or $resourceDriftCount -gt 0)
        required = [pscustomobject] [ordered]@{
            group = [pscustomobject] $groupDrift
            resourceDriftCount = $resourceDriftCount
        }
        compatibility = [pscustomobject] [ordered]@{
            group = [pscustomobject] $compatibilityDrift
            resourceDriftCount = $compatibilityResourceDriftCount
        }
        resourceDriftCount = $resourceDriftCount
    }
}

if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw 'The lab environment schema is unavailable.'
}
$registryFile = $null
try {
    $registryFile = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
}
catch {
    throw 'RegistryPath must reference an existing readable registry file.'
}
$registryFullPath = $registryFile.FullName
if ($registryFile.Length -gt $maxInputBytes) {
    throw 'The lab environment registry exceeds the bounded input limit.'
}

$outputFullPath = $null
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    try {
        $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals($outputFullPath, $registryFullPath)) {
            throw 'OutputPath must not overwrite the registry.'
        }
        if (Test-Path -LiteralPath $outputFullPath) {
            throw 'OutputPath must name a new file.'
        }
    }
    catch {
        if ($_.Exception.Message -like 'OutputPath must *') { throw }
        throw 'OutputPath is not a valid new file path.'
    }
}

try {
    $registryRaw = Get-Content -LiteralPath $registryFullPath -Raw -ErrorAction Stop
}
catch {
    throw 'The lab environment registry could not be read.'
}
try {
    $registryValid = $registryRaw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop
}
catch {
    throw 'The lab environment registry failed schema validation.'
}
if (-not $registryValid) {
    throw 'The lab environment registry does not satisfy its schema.'
}
try {
    $registry = $registryRaw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw 'The lab environment registry JSON could not be parsed.'
}

$subscriptionIds = @($registry.subscriptions | ForEach-Object { ([string] $_).ToLowerInvariant() })
$targetSubscriptionId = ([string] $registry.targetSubscriptionId).ToLowerInvariant()
if ($targetSubscriptionId -notin $subscriptionIds) {
    throw 'The target subscription must appear in the subscription list.'
}
$solutionIds = @($registry.solutions | ForEach-Object { [string] $_.id })
if (@($solutionIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw 'The lab environment registry contains duplicate solution IDs.'
}
$subscriptionPolicies = if ($registry.PSObject.Properties.Name -contains 'subscriptionPolicies') { @($registry.subscriptionPolicies) } else { @() }
$policyIds = @($subscriptionPolicies | ForEach-Object { ([string] $_.subscriptionId).ToLowerInvariant() })
if (@($policyIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw 'The lab registry contains duplicate subscription policies.'
}
foreach ($policy in $subscriptionPolicies) {
    $policySubscriptionId = ([string] $policy.subscriptionId).ToLowerInvariant()
    if ($policySubscriptionId -notin $subscriptionIds) {
        throw 'A subscription policy references an undeclared subscription.'
    }
    try {
        $monthlyCredit = [decimal] $policy.monthlyCreditUSD
        $budgetAmount = [decimal] $policy.budgetAmountUSD
        $planningCeiling = [decimal] $policy.planningCeilingUSD
    }
    catch {
        throw 'A subscription policy contains an invalid amount.'
    }
    if ($monthlyCredit -le 0 -or $budgetAmount -le 0 -or $planningCeiling -le 0) {
        throw 'Subscription policy amounts must be positive.'
    }
    if ($planningCeiling -gt $monthlyCredit) {
        throw 'A subscription policy planning ceiling cannot exceed monthly credit.'
    }
}

$fixtureMode = -not [string]::IsNullOrWhiteSpace($InventoryDirectory)
if ($fixtureMode -and -not (Test-Path -LiteralPath $InventoryDirectory -PathType Container)) {
    throw 'The inventory directory is missing.'
}

$accountValidation = [ordered]@{
    status = if ($fixtureMode) { 'not-run-fixture' } else { 'pending' }
    expectedTenantId = [string] $registry.tenantId
    subscriptions = @()
}
$inventoryBySubscription = @{}
$findings = [System.Collections.Generic.List[string]]::new()

if (-not $fixtureMode) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI is required for live reads.'
    }
    try {
        $accounts = Invoke-AzJsonRead -Arguments @('account', 'list', '--all', '--output', 'json') -Description 'Azure account list query'
    }
    catch {
        $accountValidation.status = 'failed'
        $findings.Add('queryFailed:accountList')
        $accounts = @()
    }
    foreach ($subscriptionId in $subscriptionIds) {
        $accountMatches = @($accounts | Where-Object { ([string] $_.id).ToLowerInvariant() -ceq $subscriptionId })
        $tenantMatches = @($accountMatches | Where-Object { [string] $_.tenantId -ieq [string] $registry.tenantId })
        $entryStatus = if ($tenantMatches.Count -gt 0 -and $tenantMatches.Count -eq $accountMatches.Count) { 'validated' } elseif ($accountMatches.Count -gt 0) { 'tenant-mismatch' } else { 'subscription-unavailable' }
        $accountValidation.subscriptions += [pscustomobject] [ordered]@{
            subscriptionId = $subscriptionId
            status = $entryStatus
        }
        if ($entryStatus -ne 'validated') { $findings.Add("accountValidation:${entryStatus}:$subscriptionId") }
        $inventoryBySubscription[$subscriptionId] = [ordered]@{
            accountStatus = $entryStatus
            groups = if ($entryStatus -eq 'validated') { $null } else { [pscustomobject]@{ status = 'failed'; data = @(); finding = 'accountValidationFailed' } }
            resources = if ($entryStatus -eq 'validated') { $null } else { [pscustomobject]@{ status = 'failed'; data = @(); finding = 'accountValidationFailed' } }
        }
    }
    if (@($accountValidation.subscriptions | Where-Object status -eq 'validated').Count -eq $subscriptionIds.Count) {
        $accountValidation.status = 'validated'
    }
    elseif ($accountValidation.status -ne 'failed') {
        $accountValidation.status = 'failed'
    }
}
else {
    foreach ($subscriptionId in $subscriptionIds) {
        $inventoryBySubscription[$subscriptionId] = [ordered]@{
            accountStatus = 'not-run-fixture'
            groups = $null
            resources = $null
        }
    }
}

foreach ($subscriptionId in $subscriptionIds) {
    if ($null -eq $inventoryBySubscription[$subscriptionId].groups) {
        $inventoryBySubscription[$subscriptionId].groups = Get-InventoryResult -SubscriptionId $subscriptionId -Kind groups -FixtureMode $fixtureMode
    }
    if ($null -eq $inventoryBySubscription[$subscriptionId].resources) {
        $inventoryBySubscription[$subscriptionId].resources = Get-InventoryResult -SubscriptionId $subscriptionId -Kind resources -FixtureMode $fixtureMode
    }
    foreach ($result in @($inventoryBySubscription[$subscriptionId].groups, $inventoryBySubscription[$subscriptionId].resources)) {
        if ($result.status -ne 'complete' -and $result.finding) { $findings.Add("$($result.finding):$subscriptionId") }
    }
    $inventory = $inventoryBySubscription[$subscriptionId]
    if ($inventory.groups.status -eq 'complete' -and $inventory.resources.status -eq 'complete') {
        $inventoryGroupNames = @{}
        foreach ($group in @($inventory.groups.data)) {
            $groupName = [string] (Get-PropertyValue -InputObject $group -Names @('name'))
            if ($groupName) { $inventoryGroupNames[$groupName] = $true }
        }
        foreach ($resource in @($inventory.resources.data)) {
            $resourceGroup = Get-ResourceGroupName -InputObject $resource
            if (-not [string]::IsNullOrWhiteSpace([string] $resourceGroup) -and -not $inventoryGroupNames.ContainsKey([string] $resourceGroup)) {
                $findings.Add('inventoryInconsistent:resourceGroupMissingFromGroupInventory')
                break
            }
        }
    }
}

$expectedGroupsBySubscription = @{}
foreach ($subscriptionId in $subscriptionIds) { $expectedGroupsBySubscription[$subscriptionId] = @{} }
$solutionReports = [System.Collections.Generic.List[object]]::new()
$unmappedGroups = [System.Collections.Generic.List[object]]::new()
$unmappedResources = [System.Collections.Generic.List[object]]::new()
$trackedResourceCount = 0
$untrackedResourceCount = 0
$unknownCoverage = $false

foreach ($solution in @($registry.solutions)) {
    $environmentReports = [System.Collections.Generic.List[object]]::new()
    foreach ($environment in @($solution.environments)) {
        $subscriptionId = ([string] $environment.subscriptionId).ToLowerInvariant()
        $expectedResourceGroup = [string] $environment.resourceGroup
        $expectedTags = Get-ExpectedTagMap -Solution $solution -Environment $environment
        $subscriptionKnown = $subscriptionId -in $subscriptionIds
        if ($subscriptionKnown -and $expectedResourceGroup) {
            if ($expectedGroupsBySubscription[$subscriptionId].ContainsKey($expectedResourceGroup)) {
                throw 'Duplicate resource group mapping within a subscription.'
            }
            $expectedGroupsBySubscription[$subscriptionId][$expectedResourceGroup] = $true
        }
        $inventory = if ($subscriptionKnown) { $inventoryBySubscription[$subscriptionId] } else { $null }
        $groupResult = if ($null -ne $inventory) { $inventory.groups } else { [pscustomobject]@{ status = 'failed'; data = @(); finding = 'subscriptionNotDeclared' } }
        $resourceResult = if ($null -ne $inventory) { $inventory.resources } else { [pscustomobject]@{ status = 'failed'; data = @(); finding = 'subscriptionNotDeclared' } }
        $group = @($groupResult.data | Where-Object { [string] (Get-PropertyValue -InputObject $_ -Names @('name')) -ieq $expectedResourceGroup }) | Select-Object -First 1
        $resources = @($resourceResult.data | Where-Object { (Get-ResourceGroupName -InputObject $_) -ieq $expectedResourceGroup })
        $coverageStatus = if (-not $subscriptionKnown) { 'failed' } elseif ($groupResult.status -ne 'complete' -or $resourceResult.status -ne 'complete') { if ($groupResult.status -eq 'failed' -or $resourceResult.status -eq 'failed') { 'failed' } else { 'unknown' } } else { 'complete' }
        if ($coverageStatus -ne 'complete') { $unknownCoverage = $true }
        $deployableKind = if ($solution.PSObject.Properties.Name -contains 'deployableKind') { [string] $solution.deployableKind } else { 'azure' }
        $presence = if (-not $subscriptionKnown) { 'unmapped' } elseif ([string]::IsNullOrWhiteSpace($expectedResourceGroup)) { if ($deployableKind -eq 'tenant') { 'tenant-only' } else { 'unmapped' } } elseif ($coverageStatus -ne 'complete') { 'unknown' } elseif ($null -ne $group) { 'present' } else { 'missing' }
        $resourceCount = if ($coverageStatus -eq 'complete' -and -not [string]::IsNullOrWhiteSpace($expectedResourceGroup)) { $resources.Count } else { $null }
        $tagDrift = if ($null -ne $group -and $resourceResult.status -eq 'complete') { Get-TagDrift -ExpectedTags $expectedTags -Group $group -Resources $resourceResult.data -ResourceGroup $expectedResourceGroup } else { $null }
        $rowTracked = if ($null -ne $resourceCount) { $resourceCount } else { $null }
        $rowUntracked = if ($null -ne $rowTracked) { 0 } else { $null }
        if ($null -ne $rowTracked) { $trackedResourceCount += $rowTracked }
        $environmentReports.Add([pscustomobject] [ordered]@{
                name = [string] $environment.name
                subscriptionId = $subscriptionId
                resourceGroup = if ($expectedResourceGroup) { $expectedResourceGroup } else { $null }
                sourceRevision = $environment.sourceRevision
                validationStatus = [string] $environment.validationStatus
                tenantObjectsTracked = [bool] $environment.tenantObjectsTracked
                coverageStatus = $coverageStatus
                presence = $presence
                resourceCount = $resourceCount
                trackedResourceCount = $rowTracked
                untrackedResourceCount = $rowUntracked
                tagDrift = $tagDrift
            })
    }
    $solutionReports.Add([pscustomobject] [ordered]@{
            id = [string] $solution.id
            repository = [string] $solution.repository
            desiredEnvironment = [string] $solution.desiredEnvironment
            desiredResourceGroup = if ($solution.PSObject.Properties.Name -contains 'desiredResourceGroup' -and $null -ne $solution.desiredResourceGroup) { [string] $solution.desiredResourceGroup } else { $null }
            deployableKind = if ($solution.PSObject.Properties.Name -contains 'deployableKind') { [string] $solution.deployableKind } else { $null }
            environments = @($environmentReports)
        })
}

foreach ($subscriptionId in $subscriptionIds) {
    $inventory = $inventoryBySubscription[$subscriptionId]
    if ($inventory.groups.status -ne 'complete' -or $inventory.resources.status -ne 'complete') { continue }
    foreach ($group in @($inventory.groups.data)) {
        $groupName = [string] (Get-PropertyValue -InputObject $group -Names @('name'))
        if (-not $expectedGroupsBySubscription[$subscriptionId].ContainsKey($groupName)) {
            $groupResources = @($inventory.resources.data | Where-Object { (Get-ResourceGroupName -InputObject $_) -ieq $groupName })
            $unmappedGroups.Add([pscustomobject] [ordered]@{
                    name = $groupName
                    subscriptionId = $subscriptionId
                    presence = 'unmapped'
                    resourceCount = $groupResources.Count
                })
            $untrackedResourceCount += $groupResources.Count
            foreach ($resource in $groupResources) {
                $unmappedResources.Add([pscustomobject] [ordered]@{
                        name = [string] (Get-PropertyValue -InputObject $resource -Names @('name'))
                        id = [string] (Get-PropertyValue -InputObject $resource -Names @('id'))
                        subscriptionId = $subscriptionId
                        resourceGroup = $groupName
                    })
            }
        }
    }
}

$subscriptionReports = @(
    foreach ($subscriptionId in $subscriptionIds) {
        $inventory = $inventoryBySubscription[$subscriptionId]
        [pscustomobject] [ordered]@{
            subscriptionId = $subscriptionId
            accountStatus = [string] $inventory.accountStatus
            groupsStatus = [string] $inventory.groups.status
            resourcesStatus = [string] $inventory.resources.status
            groupCount = if ($inventory.groups.status -eq 'complete') { @($inventory.groups.data).Count } else { $null }
            resourceCount = if ($inventory.resources.status -eq 'complete') { @($inventory.resources.data).Count } else { $null }
            extraGroupCount = @($unmappedGroups | Where-Object subscriptionId -eq $subscriptionId).Count
            unmappedResourceCount = @($unmappedResources | Where-Object subscriptionId -eq $subscriptionId).Count
        }
    }
)

$inventoryFailed = @($subscriptionReports | Where-Object { $_.groupsStatus -eq 'failed' -or $_.resourcesStatus -eq 'failed' }).Count -gt 0
$inventoryUnknown = @($subscriptionReports | Where-Object { $_.groupsStatus -eq 'unknown' -or $_.resourcesStatus -eq 'unknown' }).Count -gt 0
$coverage = if ($inventoryFailed -or ($findings | Where-Object { $_ -like 'queryFailed:*' -or $_ -like 'inventoryInvalid:*' -or $_ -like 'inventoryInconsistent:*' -or $_ -like 'accountValidation:*' -or $_ -like 'subscriptionNotDeclared:*' })) { 'failed' } elseif ($unknownCoverage -or $inventoryUnknown) { 'unknown' } else { 'complete' }
$report = [pscustomobject] [ordered]@{
    schemaVersion = '1.0'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    tenantId = [string] $registry.tenantId
    targetSubscriptionId = $targetSubscriptionId
    inventoryMode = if ($fixtureMode) { 'fixture' } else { 'live-read' }
    coverage = $coverage
    subscriptionPolicyStatus = 'planned-only'
    subscriptionPolicies = @($subscriptionPolicies)
    accountValidation = [pscustomobject] $accountValidation
    subscriptions = $subscriptionReports
    solutions = @($solutionReports)
    extraGroups = @($unmappedGroups)
    unmappedResources = @($unmappedResources)
    trackedResourceCount = if ($coverage -eq 'complete') { $trackedResourceCount } else { $null }
    untrackedResourceCount = if ($coverage -eq 'complete') { $untrackedResourceCount } else { $null }
    findings = @($findings | Select-Object -Unique)
}

if ($OutputPath) {
    $outputParent = Split-Path -Parent $outputFullPath
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }
    $reportBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    try {
        $stream = [System.IO.File]::Open($outputFullPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        try {
            $stream.Write($reportBytes, 0, $reportBytes.Length)
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        throw 'The status report could not be written to a new output file.'
    }
}

if ($coverage -ne 'complete') {
    throw "Lab environment status coverage is $coverage."
}

if ($AsJson) { $report | ConvertTo-Json -Depth 20 }
else { $report }
