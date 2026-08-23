[CmdletBinding()]
param(
    [Alias('PlanOnly')]
    [switch] $Plan,

    [switch] $TestDelivery,

    [string] $OutputPath = 'reports/deployment-validation.json',

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enginePath = Join-Path $PSScriptRoot 'vendor/Azd.DeploymentValidation/Azd.DeploymentValidation.psd1'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw 'The deployment-validation component is missing. Synchronize it from azd-reference before using this skeleton.'
}
Import-Module $enginePath -Force
Import-Module (Join-Path $PSScriptRoot 'Deployment.Validation.psm1') -Force

$startedAt = [datetimeoffset]::UtcNow
$mode = if ($Plan) { 'plan' } elseif ($TestDelivery) { 'delivery' } else { 'verify' }
$definitions = @(Get-ProjectValidationDefinition)
$checks = @(Invoke-AzdValidationSet -Definitions $definitions -Plan:$Plan -AllowSyntheticDelivery:$TestDelivery)
$report = New-AzdValidationReport `
    -TemplateName 'replace-with-solution-name' `
    -TemplateVersion '0.1.0' `
    -Mode $mode `
    -StartedAt $startedAt `
    -Checks $checks `
    -Environment @{
        name = [string] $env:AZURE_ENV_NAME
        tenantId = [string] $env:AZURE_TENANT_ID
        subscriptionId = [string] $env:AZURE_SUBSCRIPTION_ID
        resourceGroup = [string] $env:AZURE_RESOURCE_GROUP
    } `
    -Requirements @{
        tools = @('az', 'azd')
        modules = @()
        permissions = @('Azure Resource Group read access')
    } `
    -NextSteps @('Add solution-specific security and delivery validation before publishing the template.')

$writtenPath = Write-AzdValidationReport -Report $report -OutputPath $OutputPath -RepositoryRoot $repositoryRoot
Write-AzdValidationSummary -Report $report
Write-Host "Validation report: $writtenPath"
if ($PassThru) { $report }
Assert-AzdValidationSucceeded -Report $report
