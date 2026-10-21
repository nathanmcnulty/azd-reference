[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $RegistryPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $SolutionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $EnvironmentName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $GitHubEnvironment,

    [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$maxInputBytes = 5MB
$managementResourceGroupName = 'rg-azd-lab-management'
$issuer = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'
$schemaPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) 'schemas/lab-environments.schema.json'

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string] $Name
    )

    if ($null -eq $InputObject -or $InputObject.PSObject.Properties.Name -notcontains $Name) {
        throw "Registry property '$Name' is required for this plan."
    }
    return $InputObject.$Name
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string] $Value)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    throw 'RegistryPath must reference an existing registry file.'
}
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw 'The lab environment schema was not found beside this tool.'
}

$registryFile = Get-Item -LiteralPath $RegistryPath -ErrorAction Stop
if ($registryFile.Length -gt $maxInputBytes) {
    throw 'The registry exceeds the bounded input size.'
}

try {
    if (-not (Test-Json -Path $registryFile.FullName -SchemaFile $schemaPath -ErrorAction Stop)) {
        throw 'Registry schema validation returned false.'
    }
}
catch {
    throw 'Registry schema validation failed.'
}

try {
    $registry = Get-Content -LiteralPath $registryFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
}
catch {
    throw 'Registry JSON could not be parsed.'
}

if ($GitHubEnvironment -notmatch '^[A-Za-z0-9-]{1,64}$') {
    throw 'GitHubEnvironment must contain only ASCII letters, numbers, and hyphens.'
}

$targetSubscriptionId = ([string] (Get-RequiredProperty -InputObject $registry -Name 'targetSubscriptionId')).ToLowerInvariant()
$tenantId = ([string] (Get-RequiredProperty -InputObject $registry -Name 'tenantId')).ToLowerInvariant()
$declaredSubscriptions = @((Get-RequiredProperty -InputObject $registry -Name 'subscriptions') | ForEach-Object { ([string] $_).ToLowerInvariant() })
if (@($declaredSubscriptions | Where-Object { $_ -eq $targetSubscriptionId }).Count -ne 1) {
    throw 'Registry targetSubscriptionId must appear exactly once in subscriptions.'
}

$solutions = @((Get-RequiredProperty -InputObject $registry -Name 'solutions') | Where-Object { [string] $_.id -ceq $SolutionId })
if ($solutions.Count -eq 0) {
    throw 'The selected solution was not found in the registry.'
}
if ($solutions.Count -ne 1) {
    throw 'The selected solution is ambiguous in the registry.'
}
$solution = $solutions[0]

$solutionKind = [string] (Get-RequiredProperty -InputObject $solution -Name 'deployableKind')
if ($solutionKind -cne 'azure') {
    throw 'The selected solution is not an azure deployable row.'
}

$environments = @((Get-RequiredProperty -InputObject $solution -Name 'environments') | Where-Object { [string] $_.name -ceq $EnvironmentName })
if ($environments.Count -eq 0) {
    throw 'The selected environment was not found for the selected solution.'
}
if ($environments.Count -ne 1) {
    throw 'The selected environment is ambiguous for the selected solution.'
}
$environment = $environments[0]

$workloadSubscriptionId = ([string] (Get-RequiredProperty -InputObject $environment -Name 'subscriptionId')).ToLowerInvariant()
if (@($declaredSubscriptions | Where-Object { $_ -eq $workloadSubscriptionId }).Count -ne 1) {
    throw 'The selected environment subscription must appear exactly once in subscriptions.'
}

$workloadResourceGroupName = [string] (Get-RequiredProperty -InputObject $environment -Name 'resourceGroup')
if ([string]::IsNullOrWhiteSpace($workloadResourceGroupName)) {
    throw 'An azure deployment identity plan requires a non-null workload resource group.'
}
if ($workloadResourceGroupName -ieq $managementResourceGroupName) {
    throw "Workload resource group cannot equal management resource group '$managementResourceGroupName'."
}

$sourceRevision = [string] (Get-RequiredProperty -InputObject $environment -Name 'sourceRevision')
if ($sourceRevision -notmatch '^[0-9A-Fa-f]{40}$') {
    throw 'The selected environment sourceRevision must be a non-null immutable 40-hex commit.'
}
$sourceRevision = $sourceRevision.ToLowerInvariant()

$repository = [string] (Get-RequiredProperty -InputObject $solution -Name 'repository')
if ($repository -notmatch '^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$') {
    throw 'The selected repository is not a supported GitHub repository URL.'
}
$repositoryPath = $Matches[1]

$nameSeed = [string]::Join('|', @(
        $tenantId
        $targetSubscriptionId
        $repositoryPath.ToLowerInvariant()
        $GitHubEnvironment
        $EnvironmentName
    ))
$nameHash = Get-Sha256Hex -Value $nameSeed
$managedIdentityName = 'uami-lab-' + $nameHash.Substring(0, 48)
$managedIdentityResourceId = "/subscriptions/$targetSubscriptionId/resourceGroups/$managementResourceGroupName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$managedIdentityName"
$workloadScope = "/subscriptions/$workloadSubscriptionId/resourceGroups/$workloadResourceGroupName"
$federatedSubject = "repo:${repositoryPath}:environment:${GitHubEnvironment}"

$plan = [ordered]@{
    planVersion = '1.0'
    solutionId = $SolutionId
    environmentName = $EnvironmentName
    deployableKind = $solutionKind
    identityPlacement = [ordered]@{
        subscriptionId = $targetSubscriptionId
        resourceGroup = $managementResourceGroupName
        name = $managedIdentityName
        resourceId = $managedIdentityResourceId
        nameHash = $nameHash
        nameInputs = [ordered]@{
            tenantId = $tenantId
            subscriptionId = $targetSubscriptionId
            repository = $repositoryPath
            githubEnvironment = $GitHubEnvironment
            azdEnvironment = $EnvironmentName
        }
    }
    deploymentTemplateInputs = [ordered]@{
        identityName = $managedIdentityName
        repository = $repositoryPath
        githubEnvironment = $GitHubEnvironment
        workloadSubscriptionId = $workloadSubscriptionId
        workloadResourceGroup = $workloadResourceGroupName
        grantContributor = $false
    }
    workload = [ordered]@{
        subscriptionId = $workloadSubscriptionId
        resourceGroup = $workloadResourceGroupName
        scope = $workloadScope
    }
    authorization = [ordered]@{
        roleDefinitionName = 'Contributor'
        scope = $workloadScope
        status = 'proposed'
        granted = $false
        note = 'Plan only. No role assignment was created or queried.'
    }
    sourceBinding = [ordered]@{
        repository = $repository
        revision = $sourceRevision
        statement = 'The immutable revision binds this reviewed plan to a source reference; it does not prove the local checkout is clean, matches the revision, or is valid.'
    }
    federatedCredential = [ordered]@{
        issuer = $issuer
        audience = $audience
        subject = $federatedSubject
    }
    guards = [ordered]@{
        githubEnvironment = [ordered]@{
            value = $GitHubEnvironment
            validation = 'alnum-hyphen'
            status = 'validated-input'
        }
        defaultBranch = [ordered]@{
            status = 'pending'
            statement = 'Federated credentials must also constrain the repository default branch before live use.'
        }
        liveOidc = [ordered]@{
            status = 'pending'
            testsPending = @('GitHub Actions OIDC token exchange', 'default-branch subject guard', 'Azure role scope verification')
        }
    }
    boundaries = [ordered]@{
        graphAndBootstrap = 'outside-deploy-identity-plan'
        execution = 'review-only; az, gh, login, hooks, role assignment, and policy mutation are not executed'
    }
}

$json = $plan | ConvertTo-Json -Depth 20
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $outputFullPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        throw 'OutputPath parent directory must already exist.'
    }
    # CreateNew protects the input registry, existing reports, and files reached
    # through alternate paths from accidental overwrite, including write races.
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json + [Environment]::NewLine)
    $stream = [System.IO.File]::Open($outputFullPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $stream.Dispose()
    }
}
Write-Output $json
