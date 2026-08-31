[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Pim', 'Risk')]
    [string] $Shape,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $TemplatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-NestedDeployment {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Template,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $deploymentMatches = @($Template.resources | Where-Object {
            [string] $_.type -eq 'Microsoft.Resources/deployments' -and [string] $_.name -eq $Name
        })
    Assert-Condition ($deploymentMatches.Count -eq 1) "Expected exactly one nested deployment named '$Name'."
    return $deploymentMatches[0]
}

function Assert-ExactOutputContract {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Template,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ExpectedOutputs,

        [Parameter(Mandatory)]
        [string] $Context
    )

    $outputsProperty = $Template.PSObject.Properties['outputs']
    $actualOutputs = @(
        if ($null -ne $outputsProperty) {
            $outputsProperty.Value.PSObject.Properties
        }
    )
    Assert-Condition ($actualOutputs.Count -eq $ExpectedOutputs.Count) "$Context must expose exactly $($ExpectedOutputs.Count) output(s); found $($actualOutputs.Count)."

    foreach ($outputName in $ExpectedOutputs.Keys) {
        $matchingOutputs = @($actualOutputs | Where-Object Name -eq $outputName)
        Assert-Condition ($matchingOutputs.Count -eq 1) "$Context must expose only the '$outputName' output."
        $definition = $matchingOutputs[0].Value
        $definitionProperties = @($definition.PSObject.Properties)
        Assert-Condition ($definitionProperties.Count -eq 2) "$Context output '$outputName' may contain only type and value."
        Assert-Condition (@($definitionProperties.Name | Where-Object { $_ -notin @('type', 'value') }).Count -eq 0) "$Context output '$outputName' contains an unexpected property."
        Assert-Condition ([string] $definition.type -eq [string] $ExpectedOutputs[$outputName].type) "$Context output '$outputName' type must be '$($ExpectedOutputs[$outputName].type)'."
        Assert-Condition ([string] $definition.value -ceq [string] $ExpectedOutputs[$outputName].value) "$Context output '$outputName' value expression must be exactly '$($ExpectedOutputs[$outputName].value)'."
    }
}

$expected = if ($Shape -eq 'Pim') {
    [ordered]@{
        prefix = 'pim'
        workflowName = 'pim-fixture-workflow'
        actionGroupName = 'pim-fixture-action-group'
        groupShortName = 'PIM Entra'
        receiverName = 'PIM activation Teams workflow'
        triggerName = 'manual'
        alertRuleName = 'pim-fixture-alert'
        displayName = 'Microsoft Entra PIM activation completed'
        queryMarker = 'AuditLogs'
        autoMitigate = $true
        evaluationFrequency = 'PT5M'
        windowSize = 'PT5M'
        dimensions = @('ActivationEventId', 'CorrelationId', 'Actor', 'Role')
    }
}
else {
    [ordered]@{
        prefix = 'risk'
        workflowName = 'risk-fixture-workflow'
        actionGroupName = 'risk-fixture-action-group'
        groupShortName = 'Entra risk'
        receiverName = 'Risk notification workflow'
        triggerName = 'manual'
        alertRuleName = 'risk-fixture-alert'
        displayName = 'Microsoft Entra risk detection'
        queryMarker = 'AADRiskyUsers'
        autoMitigate = $false
        evaluationFrequency = 'PT5M'
        windowSize = 'PT10M'
        dimensions = @('Envelope')
    }
}

$template = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -Depth 100
$actionGroup = Get-NestedDeployment -Template $template -Name "$($expected.prefix)-action-group-fixture"
$alert = Get-NestedDeployment -Template $template -Name "$($expected.prefix)-alert-fixture"

$actionParameters = $actionGroup.properties.parameters
$alertParameters = $alert.properties.parameters

Assert-Condition ([string] $actionParameters.actionGroupName.value -eq $expected.actionGroupName) 'Action-group name was not passed exactly.'
Assert-Condition ([string] $actionParameters.groupShortName.value -eq $expected.groupShortName) 'Action-group short name was not passed exactly.'
Assert-Condition ([string] $actionParameters.logicAppResourceId.value -match "Microsoft\.Logic/workflows.*$([regex]::Escape($expected.workflowName))") 'Logic App resource ID was not derived from the wrapper resource.'
Assert-Condition ([string] $actionParameters.receiverName.value -eq $expected.receiverName) 'Logic App receiver name was not passed exactly.'
Assert-Condition ([string] $actionParameters.logicAppTriggerName.value -eq $expected.triggerName) 'Logic App trigger name was not passed exactly.'
Assert-Condition ((@($actionGroup.dependsOn) -join ' ') -match "Microsoft\.Logic/workflows.*$([regex]::Escape($expected.workflowName))") 'Action-group module does not depend on its Logic App resource.'

Assert-Condition ([string] $alertParameters.alertRuleName.value -eq $expected.alertRuleName) 'Alert-rule name was not passed exactly.'
Assert-Condition ([string] $alertParameters.displayName.value -eq $expected.displayName) 'Alert display name was not passed exactly.'
Assert-Condition ([string] $alertParameters.query.value -match [regex]::Escape($expected.queryMarker)) 'Representative query was not passed to the alert module.'
Assert-Condition ([bool] $alertParameters.autoMitigate.value -eq $expected.autoMitigate) 'autoMitigate does not match the consumer shape.'
Assert-Condition ([string] $alertParameters.evaluationFrequency.value -eq $expected.evaluationFrequency) 'Evaluation frequency does not match the consumer shape.'
Assert-Condition ([string] $alertParameters.windowSize.value -eq $expected.windowSize) 'Window size does not match the consumer shape.'
Assert-Condition ([string] $alertParameters.workspaceResourceId.value -match 'Microsoft\.OperationalInsights/workspaces.*fixture-workspace') 'Workspace resource ID was not derived from the wrapper resource.'
Assert-Condition ([string] $alertParameters.actionGroupResourceId.value -match "Microsoft\.Resources/deployments.*$($expected.prefix)-action-group-fixture.*outputs.*actionGroupResourceId") 'Alert action-group ID was not derived from the action-group module output.'
Assert-Condition ((@($alert.dependsOn) -join ' ') -match "Microsoft\.Resources/deployments.*$($expected.prefix)-action-group-fixture") 'Alert module does not depend on the action-group module.'

$actualDimensionObjects = @($alertParameters.dimensions.value)
$actualDimensions = @($actualDimensionObjects | ForEach-Object { [string] $_.name })
Assert-Condition ($actualDimensionObjects.Count -eq $expected.dimensions.Count) 'Alert dimension count does not match the consumer shape.'
for ($index = 0; $index -lt $expected.dimensions.Count; $index++) {
    Assert-Condition ($actualDimensions[$index] -eq $expected.dimensions[$index]) "Alert dimension $index does not match the consumer shape."
    Assert-Condition ([string] $actualDimensionObjects[$index].operator -eq 'Include') "Alert dimension $index does not use the Include operator."
    $dimensionValues = @($actualDimensionObjects[$index].values)
    Assert-Condition ($dimensionValues.Count -eq 1 -and [string] $dimensionValues[0] -eq '*') "Alert dimension $index does not include exactly the wildcard value."
}

$actionResource = @($actionGroup.properties.template.resources | Where-Object type -eq 'Microsoft.Insights/actionGroups')[0]
$alertResource = @($alert.properties.template.resources | Where-Object type -eq 'Microsoft.Insights/scheduledQueryRules')[0]
Assert-Condition ($null -ne $actionResource) 'Compiled action-group module does not contain the expected resource.'
Assert-Condition ($null -ne $alertResource) 'Compiled alert module does not contain the expected resource.'
Assert-Condition ([string] $actionResource.name -ceq "[parameters('actionGroupName')]") 'actionGroupName is not consumed by the action-group resource name.'
Assert-Condition ([string] $actionResource.properties.groupShortName -ceq "[parameters('groupShortName')]") 'groupShortName is not consumed by the action-group property.'
Assert-Condition ([string] $actionResource.properties.logicAppReceivers[0].name -ceq "[parameters('receiverName')]") 'receiverName is not consumed by the Logic App receiver.'
Assert-Condition ([string] $actionResource.properties.logicAppReceivers[0].resourceId -ceq "[parameters('logicAppResourceId')]") 'logicAppResourceId is not consumed by the Logic App receiver.'
$expectedCallbackExpression = "[listCallbackUrl(format('{0}/triggers/{1}', parameters('logicAppResourceId'), parameters('logicAppTriggerName')), '2019-05-01').value]"
Assert-Condition ([string] $actionResource.properties.logicAppReceivers[0].callbackUrl -ceq $expectedCallbackExpression) 'logicAppResourceId and logicAppTriggerName are not consumed by the exact callback expression.'
Assert-Condition ([bool] $actionResource.properties.logicAppReceivers[0].useCommonAlertSchema) 'Common alert schema is not enabled.'
Assert-Condition ([string] $alertResource.properties.displayName -eq "[parameters('displayName')]") 'displayName is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.description -eq "[parameters('alertDescription')]") 'alertDescription is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.evaluationFrequency -eq "[parameters('evaluationFrequency')]") 'evaluationFrequency is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.windowSize -eq "[parameters('windowSize')]") 'windowSize is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.autoMitigate -eq "[parameters('autoMitigate')]") 'autoMitigate is not consumed by the alert property.'
Assert-Condition ([string] $alertResource.properties.scopes[0] -eq "[parameters('workspaceResourceId')]") 'workspaceResourceId is not consumed by the alert scope.'
Assert-Condition ([string] $alertResource.properties.criteria.allOf[0].query -eq "[parameters('query')]") 'query is not consumed by the alert criteria.'
Assert-Condition ([string] $alertResource.properties.criteria.allOf[0].dimensions -eq "[parameters('dimensions')]") 'dimensions are not consumed by the alert criteria.'
Assert-Condition ([string] $alertResource.properties.actions.actionGroups[0] -eq "[parameters('actionGroupResourceId')]") 'actionGroupResourceId is not consumed by the alert action.'

Assert-ExactOutputContract -Template $template -ExpectedOutputs @{} -Context "$Shape wrapper"
Assert-ExactOutputContract -Template $actionGroup.properties.template -ExpectedOutputs @{
    actionGroupResourceId = @{
        type = 'string'
        value = "[resourceId('Microsoft.Insights/actionGroups', parameters('actionGroupName'))]"
    }
} -Context 'Canonical action-group module'
Assert-ExactOutputContract -Template $alert.properties.template -ExpectedOutputs @{
    alertRuleResourceId = @{
        type = 'string'
        value = "[resourceId('Microsoft.Insights/scheduledQueryRules', parameters('alertRuleName'))]"
    }
} -Context 'Canonical scheduled-query module'
Write-Output "$Shape compiled wrapper assertions passed."
