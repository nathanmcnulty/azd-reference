[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $TemplatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$template = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -Depth 100
$deployments = @($template.resources | Where-Object {
        $_.type -eq 'Microsoft.Resources/deployments' -and $_.name -eq 'poller-migration-fixture'
    })
Assert-Condition ($deployments.Count -eq 1) 'Expected exactly one poller migration deployment.'
$deployment = $deployments[0]
$parameters = $deployment.properties.parameters
Assert-Condition ($parameters.stateContainerName.value -eq 'existing-state') 'Existing state container was not preserved.'
Assert-Condition ($parameters.deadLetterContainerName.value -eq 'existing-dead-letter') 'Existing dead-letter container was not preserved.'
Assert-Condition ([int] $parameters.blobDeleteRetentionDays.value -eq 14) 'Existing retention was not preserved.'
Assert-Condition ([int] $parameters.instanceMemoryMB.value -eq 512) 'The fixture is not right-sized to 512 MB.'

$nested = $deployment.properties.template
$site = @($nested.resources | Where-Object type -eq 'Microsoft.Web/sites')[0]
$storage = @($nested.resources | Where-Object type -eq 'Microsoft.Storage/storageAccounts')[0]
$role = @($nested.resources | Where-Object type -eq 'Microsoft.Authorization/roleAssignments')[0]
Assert-Condition ($null -ne $site) 'Compiled component is missing the Function App.'
Assert-Condition ($null -ne $storage) 'Compiled component is missing Storage.'
Assert-Condition ($null -ne $role) 'Compiled component is missing Blob RBAC.'
Assert-Condition ([string] $site.properties.functionAppConfig.scaleAndConcurrency.instanceMemoryMB -eq "[parameters('instanceMemoryMB')]") 'Compiled Function App does not consume the memory parameter.'
Assert-Condition ([string] $site.properties.functionAppConfig.scaleAndConcurrency.maximumInstanceCount -eq "[parameters('maximumInstanceCount')]") 'Compiled Function App does not consume the instance ceiling.'
Assert-Condition (@($site.properties.functionAppConfig.scaleAndConcurrency.alwaysReady).Count -eq 0) 'Compiled Function App has an always-ready instance.'

Assert-Condition ($parameters.applicationSettings.value.POLLER_SCHEDULE -eq '0 */5 * * * *') 'Solution setting was not passed to the component.'
Assert-Condition ((@($parameters.storageAccountSettingAliases.value) -join ',') -eq 'LEGACY_STORAGE,AZD_POLLER_STORAGE_ACCOUNT_NAME') 'Storage aliases were not passed exactly.'
Assert-Condition ((@($parameters.stateContainerSettingAliases.value) -join ',') -eq 'LEGACY_STATE,LEGACY_STORAGE') 'State aliases were not passed exactly.'
Assert-Condition ((@($parameters.deadLetterContainerSettingAliases.value) -join ',') -eq 'LEGACY_DEAD_LETTER,LEGACY_STATE') 'Dead-letter aliases were not passed exactly.'
$appSettingsExpression = [string] $site.properties.siteConfig.appSettings
$solutionIndex = $appSettingsExpression.IndexOf("variables('solutionSettings')", [System.StringComparison]::Ordinal)
$genericIndex = $appSettingsExpression.LastIndexOf('AZD_POLLER_STATE_CONTAINER', [System.StringComparison]::Ordinal)
Assert-Condition ($solutionIndex -ge 0 -and $genericIndex -gt $solutionIndex) 'Component-owned settings are not emitted after solution settings.'
Assert-Condition ($appSettingsExpression -match "variables\('compatibilitySettings'\)") 'Compatibility aliases are absent from the compiled app settings.'
Assert-Condition ($nested.outputs.functionAppName.type -eq 'string') 'Function name output is missing.'
Assert-Condition ($nested.outputs.functionAppPrincipalId.type -eq 'string') 'Function principal output is missing.'
Write-Output 'Flex scheduled-poller compiled migration assertions passed.'
