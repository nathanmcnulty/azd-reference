#Requires -Version 7.6
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TemplatePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$template = Get-Content -Raw -LiteralPath $TemplatePath | ConvertFrom-Json
$deployments = @($template.resources | Where-Object type -eq 'Microsoft.Resources/deployments')
if ($deployments.Count -ne 1 -or $template.resources.Count -ne 1) { throw 'Expected exactly the alert module and no receiver resources.' }
$deployment = $deployments[0]
$parameters = $deployment.properties.parameters
if ($parameters.windowSize.value -cne 'PT30M' -or $parameters.evaluationFrequency.value -cne 'PT5M' -or
    $parameters.autoMitigate.value -ne $false -or $parameters.query.value -cne "[parameters('query')]" -or
    $parameters.workspaceResourceId.value -cne "[resourceId('Microsoft.OperationalInsights/workspaces', parameters('workspaceName'))]" -or
    $parameters.actionGroupResourceId.value -cne "[resourceId('Microsoft.Insights/actionGroups', parameters('actionGroupName'))]") {
    throw 'Automation wrapper changed window, evaluation, query, mitigation, or symbolic target flow.'
}
$nested = $deployment.properties.template
$rules = @($nested.resources | Where-Object type -eq 'Microsoft.Insights/scheduledQueryRules')
if ($rules.Count -ne 1 -or $nested.resources.Count -ne 1) { throw 'Expected exactly one nested scheduled-query rule.' }
$properties = $rules[0].properties
if ($nested.parameters.windowSize.defaultValue -cne 'PT5M' -or
    (@($nested.parameters.windowSize.allowedValues) -join ',') -cne 'PT5M,PT10M,PT30M' -or
    $properties.windowSize -cne "[parameters('windowSize')]" -or
    $properties.evaluationFrequency -cne "[parameters('evaluationFrequency')]" -or
    $properties.autoMitigate -cne "[parameters('autoMitigate')]" -or
    $properties.actions.actionGroups[0] -cne "[parameters('actionGroupResourceId')]" -or
    $properties.criteria.allOf[0].query -cne "[parameters('query')]") {
    throw 'Nested rule changed the selected window, unchanged default, or policy/routing inputs.'
}
Write-Output 'Automation PT30M compiled flow verified; no live acceptance or delivery is claimed.'
